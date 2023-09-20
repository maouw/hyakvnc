#! /usr/bin/env python3
# -*- coding: utf-8 -*-

import argparse
import base64
import json
import logging
import os
import re
import shlex
import subprocess
from dataclasses import asdict
from pathlib import Path
from typing import Optional

from .config import HyakVncConfig
from .slurmutil import wait_for_job_status, get_job
from .util import check_remote_pid_exists_and_port_open
from .version import VERSION

app_config = HyakVncConfig()


def get_apptainer_vnc_instances(read_apptainer_config: bool = False):
    app_dir = Path(app_config.apptainer_config_dir).expanduser() / 'instances' / 'app'
    assert app_dir.exists(), f"Could not find apptainer instances dir at {app_dir}"

    needed_keys = {'pid', 'user', 'name', 'image'}
    if read_apptainer_config:
        needed_keys.add('config')

    all_instance_json_files = app_dir.rglob(app_config.apptainer_instance_prefix + '*.json')

    running_hyakvnc_json_files = {p: r.groupdict() for p in all_instance_json_files if (
        r := re.match(rf'(?P<prefix>{app_config.apptainer_instance_prefix})(?P<jobid>\d+)-(?P<appinstance>.*)\.json',
                      p.name))}
    outs = []
    #    frr := re.search(r'\s+-rfbport\s+(?P<rfbport>\d+\b', fr)

    for p, name_meta in running_hyakvnc_json_files.items():
        with open(p, 'r') as f:
            d = json.load(f)
            assert needed_keys <= d.keys(), f"Missing keys {needed_keys - d.keys()} in {d}"

            logOutPath = Path(d['logOutPath']).expanduser()
            if not logOutPath.exists():
                continue

            if not read_apptainer_config:
                d.pop("config", None)
            else:
                d['config'] = json.loads(base64.b64decode(d['config']).decode('utf-8'))
            d['slurm_compute_node'] = p.relative_to(app_dir).parts[0]
            d['slurm_job_id'] = name_meta['jobid']

            with open(logOutPath, 'r') as lf:
                logOutFile_contents = lf.read()
                rfbports = re.findall(r'\s+-rfbport\s+(?P<rfbport>\d+)\b', logOutFile_contents)
                if not rfbports:
                    continue

                vnc_port = rfbports[-1]

                vnc_log_file_paths = re.findall(
                    rf'(?m)Log file is\s*(?P<logfilepath>.*/{d["slurm_compute_node"]}.*:{vnc_port}\.log)$',
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


def cmd_create(container_path, dry_run=False):
    container_name = Path(container_path).stem

    if not re.match(r"(?P<container_type>library|docker|shub|oras)://(?P<container_path>.*)", container_path):
        container_path = container_path.expanduser().resolve()
        container_name = container_path.stem
        assert container_path.exists(), f"Could not find container at {container_path}"

    cmds = ["sbatch", "--parsable", "--job-name", app_config.job_prefix + container_name]

    sbatch_optinfo = {"account": "-A", "partition": "-p", "gpus": "-G", "timelimit": "--time", "mem": "--mem",
                      "cpus": "-c"}
    sbatch_options = [item for pair in [(sbatch_optinfo[k], v) for k, v in asdict(app_config).items() if
                                        k in sbatch_optinfo.keys() and v is not None] for item in pair]

    cmds += sbatch_options

    apptainer_env_vars_quoted = [f"{k}={shlex.quote(v)}" for k, v in app_config.apptainer_env_vars.items()]
    apptainer_env_vars_string = "" if apptainer_env_vars_quoted else (" ".join(apptainer_env_vars_quoted) + " ")

    # needs to match rf'(?P<prefix>{app_config.apptainer_instance_prefix})(?P<jobid>\d+)-(?P<appinstance>.*)'):
    apptainer_instance_name = rf"{app_config.apptainer_instance_prefix}-\$SLURM_JOB_ID-{container_name}"

    apptainer_cmd = apptainer_env_vars_string + rf"apptainer instance start {container_path} {apptainer_instance_name}"
    apptainer_cmd_with_rest = rf"{apptainer_cmd} && while true; do sleep 10; done"

    cmds += ["--wrap", apptainer_cmd_with_rest]

    # Launch sbatch process:
    logging.info("Launching sbatch process with command:\n" + " ".join(cmds))
    res = subprocess.run(cmds, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"Could not launch sbatch job:\n{res.stderr}")

    if not res.stdout:
        raise RuntimeError(f"No sbatch output")

    try:
        job_id = int(res.stdout.strip().split(":")[0])
    except (ValueError, IndexError, TypeError):
        raise RuntimeError(f"Could not parse jobid from sbatch output: {res.stdout}")

    logging.info(f"Launched sbatch job {job_id}")
    logging.info("Waiting for job to start running")

    try:
        wait_for_job_status(job_id, states=["RUNNING"], timeout=app_config.sbatch_post_timeout,
                            poll_interval=app_config.sbatch_post_poll_interval)
    except TimeoutError:
        raise TimeoutError(f"Job {job_id} did not start running within {app_config.sbatch_post_timeout} seconds")

    job = get_job(job_id)
    if not job:
        raise RuntimeError(f"Could not get job {job_id} after it started running")

    logging.info(f"Job {job_id} is now running")


def cmd_stop(job_id: Optional[int] = None, stop_all: bool = False):
    if stop_all:
        vnc_instances = get_apptainer_vnc_instances()
        for vnc_instance in vnc_instances:
            subprocess.run(["scancel", str(vnc_instance['slurm_job_id'])])
        return

    if job_id:
        subprocess.run(["scancel", str(job_id)])
        return


def cmd_status():
    vnc_instances = get_apptainer_vnc_instances(read_apptainer_config=True)
    print(json.dumps(vnc_instances, indent=2))


def create_arg_parser():
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest='command')

    # general arguments
    parser.add_argument('-d', '--debug', dest='debug', action='store_true', help='Enable debug logging')

    parser.add_argument('-v', '--version', dest='print_version', action='store_true',
                        help='Print program version and exit')

    # command: create
    parser_create = subparsers.add_parser('create', help='Create VNC session')
    parser_create.add_argument('--dry-run', dest='dry_run', action='store_true', help='Dry run (do not submit job)')
    parser_create.add_argument('-p', '--partition', dest='partition', metavar='<partition>', help='Slurm partition',
                               type=str)
    parser_create.add_argument('-A', '--account', dest='account', metavar='<account>', help='Slurm account', type=str)
    parser_create.add_argument('--timeout', dest='timeout', metavar='<time_in_seconds>',
                               help='[default: 120] Slurm node allocation and VNC startup timeout length (in seconds)',
                               default=120, type=int)
    parser_create.add_argument('-t', '--time', dest='time', metavar='<time_in_hours>',
                               help='Subnode reservation time (in hours)', type=int)
    parser_create.add_argument('-c', '--cpus', dest='cpus', metavar='<num_cpus>', help='Subnode cpu count', default=1,
                               type=int)
    parser_create.add_argument('-G', '--gpus', dest='gpus', metavar='[type:]<num_gpus>', help='Subnode gpu count',
                               default="0", type=str)
    parser_create.add_argument('--mem', dest='mem', metavar='<NUM[K|M|G|T]>', help='Subnode memory amount with units',
                               type=str)
    parser_create.add_argument('--container', dest='container', metavar='<path_to_container.sif>',
                               help='Path to VNC Apptainer/Singularity Container (.sif)', required=True, type=str)

    # status command
    parser_status = subparsers.add_parser('status', help='Print details of all VNC jobs with given job name and exit')

    # kill command
    parser_stop = subparsers.add_parser('stop', help='Stop specified job')

    parser_stop.add_argument('job_id', metavar='<job_id>',
                             help='Kill specified VNC session, cancel its VNC job, and exit', type=int)

    parser_stop_all = subparsers.add_parser('stop_all', help='Stop all VNC sessions and exit')
    return parser


arg_parser = create_arg_parser()
args = arg_parser.parse_args()

if args.debug:
    os.environ["HYAKVNC_LOG_LEVEL"] = "DEBUG"

log_level = logging.__dict__.get(os.environ.setdefault("HYAKVNC_LOG_LEVEL", "INFO").upper(), logging.INFO)

log_format = '%(asctime)s - %(levelname)s - %(funcName)s() - %(message)s'

if log_level == logging.DEBUG:
    log_format += " - %(pathname)s:%(lineno)d"

logging.basicConfig(level=log_level, format=log_format)

if args.print_version:
    print(VERSION)
    exit(0)

if args.command == 'create':
    cmd_create(args.container, dry_run=args.dry_run)
    exit(0)

if args.command == 'status':
    cmd_status()

if args.command == 'stop':
    cmd_stop(args.job_id)

if args.command == 'stop_all':
    cmd_stop(stop_all=True)

exit(0)
