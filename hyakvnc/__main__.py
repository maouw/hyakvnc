#! /usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import json
import base64
from pathlib import Path
from typing import Optional, Iterable, Union, List
import re
import logging
import subprocess
from copy import deepcopy
from pprint import pformat
import shlex
import time
import tenacity
import argparse
from dataclasses import dataclass, asdict


from .slurmutil import get_default_cluster, get_default_account, get_partitions, wait_for_job_status
from .util import repeat_until, wait_for_file, check_remote_pid_exists_and_port_open

# Name of Apptainer binary (formerly Singularity)
APPTAINER_BIN = os.environ.setdefault("HYAKVNC_APPTAINER_BIN", "apptainer")

# Checked to see if klone is authorized for intracluster access
AUTH_KEYS_FILEPATH = Path(os.environ.setdefault("HYAKVNC_AUTH_KEYS_FILEPATH", "~/.ssh/authorized_keys")).expanduser()




@dataclass
class HyakVncConfig:
    # script attributes
    job_prefix: str = "hyakvnc-"
    # apptainer config
    apptainer_config_dir: str = "~/.apptainer"
    apptainer_instance_prefix: str = "hyakvnc-"
    apptainer_env_vars: Optional[dict] = None

    sbatch_post_timeout: float = 120.0
    sbatch_post_poll_interval: float = 1.0

    # ssh config
    ssh_host = "klone.hyak.uw.edu"

    # slurm attributes
    ## sbatch environment variables
    account: Optional[str] = None # -a, --account
    partition: Optional[str] = None # -p, --partition
    cluster: Optional[str] = None # --clusters, SBATCH_CLUSTERS
    gpus: Optional[str] = None # -G, --gpus, SBATCH_GPUS
    timelimit: Optional[str] = None # -t, --time, SBATCH_TIMELIMIT
    mem: Optional[str] = None # --mem, SBATCH_MEM
    cpus: Optional[int] = None # -c, --cpus-per-task (not settable by environment variable)

    def to_json(self):
        return json.dumps({k: v for k, v in asdict(self).items() if v is not None})
    @staticmethod
    def from_json(path):
        if not Path(path).is_file():
            raise ValueError(f"Invalid path to configuration file: {path}")

        with open(path, "r") as f:
            contents = json.load(f)
            return HyakVncConfig(**contents)
    @staticmethod
    def from_jsons(s: str):
        return HyakVncConfig(**json.loads(s))



def get_apptainer_vnc_instances(cfg: HyakVncConfig, read_apptainer_config: bool = False):
    appdir = Path(apptainer_config_dir).expanduser() / 'instances' / 'app'
    assert appdir.exists(), f"Could not find apptainer instances dir at {appdir}"

    needed_keys = {'pid', 'user', 'name', 'image', }
    if read_apptainer_config:
        needed_keys.add('config')

    all_instance_json_files = appdir.rglob(cfg.apptainer_instance_prefix + '*.json')

    running_hyakvnc_json_files = {p: r.groupdict() for p in all_instance_json_files if (
        r := re.match(rf'(?P<prefix>{cfg.apptainer_instance_prefix})(?P<jobid>\d+)-(?P<appinstance>.*)\.json', p.name))
                                  }
    outs = []
    #    frr := re.search(r'\s+-rfbport\s+(?P<rfbport>\d+\b', fr)

    for p, name_meta in running_hyakvnc_json_files.items():
        with open(p, 'r') as f:
            d = json.load(f)
            assert needed_keys <= d.keys(), f"Missing keys {needed_keys - d.keys()} in {jf}"

            logOutPath = Path(d['logOutPath']).expanduser()
            if not logOutPath.exists():
                continue

            if not read_apptainer_config:
                d.pop("config", None)
            else:
                d['config'] = json.loads(base64.b64decode(d['config']).decode('utf-8'))

            d['slurm_compute_node'] = slurm_compute_node = p.relative_to(appdir).parts[0]
            d['slurm_job_id'] = name_meta['jobid']

            with open(logOutPath, 'r') as f:
                logOutFile_contents = f.read()
                rfbports = re.findall(r'\s+-rfbport\s+(?P<rfbport>\d+)\b', logOutFile_contents)
                if not rfbports:
                    continue

                vnc_port = rfbports[-1]

                vnc_log_file_paths = re.findall(
                    rf'(?m)Log file is\s*(?P<logfilepath>.*[/]{d["slurm_compute_node"]}.*:{vnc_port}\.log)$',
                    logOutFile_contents)
                if not vnc_log_file_paths:
                    continue
                vnc_log_file_path = Path(vnc_log_file_paths[-1])
                if not vnc_log_file_path.exists():
                    logging.debug(f"Could not find vnc log file at {vnc_log_file_path}")
                    continue

                vnc_pid_file_path = Path(str(vnc_log_file_path).rstrip(".log") + '.pid')
                if not vnc_pid_file_path.exists():
                    logging.debug(f"Could not find vnc pid file at {vnc_pid_file_path}")
                    continue

                d['vnc_log_file_path'] = vnc_log_file_path
                d['vnc_pid_file_path'] = vnc_pid_file_path
                d['vnc_port'] = vnc_port

                logging.debug(
                    f"Checking port open on {d['slurm_compute_node']}:{vnc_port} for apptainer instance file {p}")

                if not check_remote_pid_exists_and_port_open(d['slurm_compute_node'], d['pid'], vnc_port):
                    logging.debug(
                        f"Could not find open port running on node {d['slurm_compute_node']}:{vnc_port} for apptainer instance file {p}")
                    continue

            outs.append(d)
    return outs


def get_openssh_connection_string_for_instance(instance: dict, login_host: str,
                                               port_on_client: Optional[int] = None) -> str:
    port_on_node = instance["vnc_port"]
    compute_node = instance["slurm_compute_node"]
    port_on_client = port_on_client or port_on_node
    s = f"ssh -v -f -o StrictHostKeyChecking=no -J {login_host} {compute_node} -L {port_on_client}:localhost:{port_on_node} sleep 10; vncviewer localhost:{port_on_client}"
    return s



def create_job_with_container(container_path, cfg: HyakVncConfig):
    if re.match(r"(?P<container_type>library|docker|shub|oras)://(?P<container_path>.*)", container_path):
        container_name = Path(container_path).stem

    else:
        container_path = container_path.expanduser().resolve()
        container_name = container_path.stem
        assert container_path.exists(), f"Could not find container at {container_path}"


    cmds = ["sbatch", "--parsable", "--job-name", cfg.job_prefix + container_name]

    sbatch_optinfo = {"account": "-A", "partition": "-p", "gpus": "-G", "timelimit": "--time", "mem": "--mem", "cpus": "-c"}
    sbatch_options = [item for pair in [(sbatch_optinfo[k], v) for k, v in asdict(cfg).items() if k in sbatch_optinfo.keys() and v is not None]
            for item in pair]

    cmds += sbatch_options

    apptainer_env_vars = {k: v for k, v in os.environ.items() if k.startswith("APPTAINER_") or k.startswith("SINGULARITY_") or k.startswith("SINGULARITYENV_") or k.startswith("APPTAINERENV_")}
    apptainer_env_vars_str = [ f"{k}={shlex.quote(v)}" for k, v in apptainer_env_vars.items()]

    apptainer_cmd = f"{apptainer_env_vars_str} apptainer instance start {container_path}  && while true; do sleep 10; done"
    cmds += ["--wrap", apptainer_cmd]



    # Launch sbatch process:
    logging.info("Launching sbatch process with command:\n" + " ".join(cmds))
    res = subprocess.run(cmds, stdout=subprocess.PIPE, stderr=subprocess.hPIPE, encoding="utf-8")

    try:
        job_id = int(res.stdout.strip().split(":")
    except (ValueError, IndexError, TypeError):
        raise RuntimeError(f"Could not parse jobid from sbatch output: {res.stdout}")


    s = wait_for_job_status(job_id, states= { "RUNNING" }, timeout=cfg.sbatch_post_timeout, cfg.sbatch_post_poll_interval)
    if not s:
        raise RuntimeError(f"Job {job_id} did not start running within {cfg.sbatch_post_timeout} seconds")






def kill(jobid: Optional[int] = None, all: bool = False):
    if all:
        vnc_instances = get_apptainer_vnc_instances()
        for vnc_instance in vnc_instances:
            subprocess.run(["scancel", str(vnc_instance['slurm_job_id'])])
        return

    if jobid:
        subprocess.run(["scancel", str(jobid)])
        return

    raise ValueError("Must specify either --all or <jobid>")

def create_arg_parser():
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest='command')

    # general arguments
    parser.add_argument('-d', '--debug',
                        dest='debug',
                        action='store_true',
                        help='Enable debug logging')

    parser.add_argument('-v', '--version',
                        dest='print_version',
                        action='store_true',
                        help='Print program version and exit')

    # command: create
    parser_create = subparsers.add_parser('create',
                                          help='Create VNC session')
    parser_create.add_argument('-p', '--partition',
                               dest='partition',
                               metavar='<partition>',
                               help='Slurm partition',
                               type=str)
    parser_create.add_argument('-A', '--account',
                               dest='account',
                               metavar='<account>',
                               help='Slurm account',
                               type=str)
    parser_create.add_argument('--timeout',
                               dest='timeout',
                               metavar='<time_in_seconds>',
                               help='[default: 120] Slurm node allocation and VNC startup timeout length (in seconds)',
                               default=120,
                               type=int)
    parser_create.add_argument('-t', '--time',
                               dest='time',
                               metavar='<time_in_hours>',
                               help='Subnode reservation time (in hours)',
                               type=int)
    parser_create.add_argument('-c', '--cpus',
                               dest='cpus',
                               metavar='<num_cpus>',
                               help='Subnode cpu count',
                               default=1,
                               type=int)
    parser_create.add_argument('-G', '--gpus',
                               dest='gpus',
                               metavar='[type:]<num_gpus>',
                               help='Subnode gpu count',
                               default="0"
                               type=str)
    parser_create.add_argument('--mem',
                               dest='mem',
                               metavar='<NUM[K|M|G|T]>',
                               help='Subnode memory amount with units',
                               type=str)
    parser_create.add_argument('--container',
                               dest='sing_container',
                               metavar='<path_to_container.sif>',
                               help='Path to VNC Apptainer/Singularity Container (.sif)',
                               required=True,
                               type=str)

    # status command
    parser_status = subparsers.add_parser('status',
                                          help='Print details of all VNC jobs with given job name and exit')

    # kill command
    parser_kill = subparsers.add_parser('kill',
                                        help='Kill specified job')

    kiLl_group = parser_kill.add_mutually_exclusive_group(required=True)
    kiLl_group.add_argument('job_id',
                             metavar='<job_id>',
                             help='Kill specified VNC session, cancel its VNC job, and exit',
                             type=int)

    kiLl_group.add_argument('-a', '--all',
                             action='store_true',
                            dest='kill_all',
                             help='Stop all VNC sessions and exit')

    parser_kill.set_defaults(func=kill)



arg_parser = create_arg_parser()
args = (arg_parser).parse_args()

print(args.func(*args.operands))