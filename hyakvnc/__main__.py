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


from dataclasses import dataclass
from .version import VERSION
from slurmutil import get_slurm_cluster, get_slurm_partitions, get_slurm_default_account, get_slurm_job_details

# Base VNC port cannot be changed due to vncserver not having a stable argument
# interface:
BASE_VNC_PORT = os.environ.setdefault("HYAKVNC_BASE_VNC_PORT", "5900")

# List of Klone login node hostnames
LOGIN_NODE_LIST = os.environ.get("HYAKVNC_LOGIN_NODES", "klone-login01,klone1.hyak.uw.edu,klone2.hyak.uw.edu").split(
    ",")

# Name of Apptainer binary (formerly Singularity)
APPTAINER_BIN = os.environ.setdefault("HYAKVNC_APPTAINER_BIN", "apptainer")

# Checked to see if klone is authorized for intracluster access
AUTH_KEYS_FILEPATH = Path(os.environ.setdefault("HYAKVNC_AUTH_KEYS_FILEPATH", "~/.ssh/authorized_keys")).expanduser()

# Apptainer bindpaths can be overwritten if $APPTAINER_BINDPATH is defined.
# Bindpaths are used to mount storage paths to containerized environment.
APPTAINER_BINDPATH = os.environ.setdefault("APPTAINER_BINDPATH",
                                           os.environ.get("HYAKVNC_APPTAINER_BINDPATH",
                                                          os.environ.get("SINGULARITY_BINDPATH",
                                                                         "/tmp,$HOME,$PWD,/gscratch,/opt,/:/hyak_root,/sw,/mmfs1")))

APPTAINER_CONFIGDIR = Path(os.getenv("APPTAINER_CONFIGDIR", "~/.apptainer")).expanduser()
APPTAINER_INSTANCES_DIR = APPTAINER_CONFIGDIR / "instances"

# # SLURM UTILS

# Slurm configuration variables:
SLURM_CLUSTER = os.getenv("HYAKVNC_SLURM_CLUSTER", os.getenv("SBATCH_CLUSTERS", get_slurm_cluster()).split(",")[0])
SLURM_ACCOUNT = os.environ.get("HYAKVNC_SLURM_ACCOUNT", os.environ.setdefault("SBATCH_ACCOUNT",
                                                                               get_slurm_default_account(
                                                                                   cluster=SLURM_CLUSTER)))
SLURM_GPUS = os.environ.setdefault("SBATCH_GPUS", "0")
SLURM_CPUS_PER_TASK = os.environ.setdefault("HYAKVNC_SLURM_CPUS_PER_TASK", "1")
SBATCH_GPUS = os.environ.setdefault("SBATCH_GPUS", "0")
SBATCH_TIMELIMIT = os.environ.setdefault("SBATCH_TIMELIMIT", "1:00:00")

HYAKVNC_SLURM_JOBNAME_PREFIX = os.getenv("HYAKVNC_SLURM_JOBNAME_PREFIX", "hyakvnc-")
HYAKVNC_APPTAINER_INSTANCE_PREFIX = os.getenv("HYAKVNC_APPTAINER_INSTANCE_PREFIX", HYAKVNC_APPTAINER_INSTANCE_PREFIX + "vncserver-")


SBATCH_CLUSTERS = os.environ.setdefault("SBATCH_CLUSTERS", SLURM_CLUSTER)

found_sbatch_partitions = get_slurm_partitions(account=SBATCH_ACCOUNT, cluster=SBATCH_CLUSTERS)
if found_sbatch_partitions:
    HYAKVNC_SLURM_PARTITION = os.environ.get("HYAKVNC_SLURM_PARTITION", os.environ.setdefault("SBATCH_ACCOUNT",
                                                                                   get_slurm_default_account(
                                                                                       cluster=SLURM_CLUSTER)))

SB

if any(SBATCH_PARTITION := x for x in get_slurm_partitions(account=SBATCH_ACCOUNT, cluster=SBATCH_CLUSTERS)):
    os.environ.setdefault("SBATCH_PARTITION", SBATCH_PARTITION)

SBATCH_GPUS = os.environ.setdefault("SBATCH_GPUS", "0")
SBATCH_TIMELIMIT = os.environ.setdefault("SBATCH_TIMELIMIT", "1:00:00")

HYAKVNC_SLURM_JOBNAME_PREFIX = os.getenv("HYAKVNC_SLURM_JOBNAME_PREFIX", "hyakvnc-")
HYAKVNC_APPTAINER_INSTANCE_PREFIX = os.getenv("HYAKVNC_APPTAINER_INSTANCE_PREFIX", "hyakvnc-vncserver-")

def check_remote_pid_exists_and_port_open(host: str, pid: int, port: int) -> bool:
    cmd = f"ssh {host} ps -p {pid} && nc -z localhost {port}".split()
    res = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return res.returncode == 0


def get_apptainer_vnc_instances(apptainer_config_dir="~/.apptainer", instance_prefix: str ="hyakvnc-",
                                read_apptainer_config: bool = False):
    appdir = Path(apptainer_config_dir).expanduser() / 'instances' / 'app'
    assert appdir.exists(), f"Could not find apptainer instances dir at {appdir}"

    needed_keys = {'pid', 'user', 'name', 'image', }
    if read_apptainer_config:
        needed_keys.add('config')

    all_instance_json_files = appdir.rglob(instance_prefix + '*.json')

    running_hyakvnc_json_files = {p: r.groupdict() for p in all_instance_json_files if (
        r := re.match(rf'(?P<prefix>{instance_prefix})(?P<jobid>\d+)-(?P<appinstance>.*)\.json', p.name))
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




def create_job_with_container(container_path: str):
    #sbatch -A escience --job-name hyakvnc-xubuntu -p gpu-a40 -c 4 --mem=8G --time=1:00:00 --wrap "apptainer instance start --cleanenv --writable-tmpfs

    cmds = ["sbatch"]




    cmd = f"ssh {host} ps -p {pid} && nc -z localhost {port}".split()
    res = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return res.returncode == 0