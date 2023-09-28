#! /usr/bin/env python3

import argparse
import logging
import os
import pprint
import re
import shlex
import signal
import subprocess
import time
import json
from datetime import datetime
from pathlib import Path
from typing import Optional, Union
from .vncsession import HyakVncSession
from .config import HyakVncConfig
from .slurmutil import (
    wait_for_job_status,
    get_job_info,
    get_job_infos,
    get_historical_job_infos,
    cancel_job,
    SbatchCommand,
)
from .util import wait_for_file, repeat_until
from .version import VERSION
from . import logger

app_config = HyakVncConfig()

# Set path to load config from:
HYAKVNC_CONFIG_PATH = Path(
    os.environ.setdefault("HYAKVNC_CONFIG_PATH", "~/.config/hyakvnc/hyakvnc-config.json")
).expanduser()

# If that path exists, load config from file:
if HYAKVNC_CONFIG_PATH.is_file():
    try:
        app_config = HyakVncConfig.from_json(path=HYAKVNC_CONFIG_PATH)
    except (json.JSONDecodeError, RuntimeError, ValueError):
        logger.warning(f"Could not load config from {HYAKVNC_CONFIG_PATH}")

# Record time app started in case we need to clean up some jobs:
app_started = datetime.now()

# Keep track of job ids so we can clean up if necessary:
app_job_ids = []


def cmd_create(container_path: Union[str, Path], dry_run=False) -> Union[HyakVncSession, None]:
    """
    Allocates a compute node, starts a container, and launches a VNC session on it.
    :param container_path: Path to container to run
    :param dry_run: Whether to do a dry run (do not actually submit job)
    :return: None
    """
    container_path = Path(container_path)
    container_name = container_path.stem

    if not container_path.is_file():
        container_path = str(container_path)
        assert re.match(
            r"(?P<container_type>library|docker|shub|oras)://(?P<container_path>.*)", container_path
        ), f"Container path {container_path} is not a valid URI"

    else:
        container_path = container_path.expanduser()
        assert container_path.exists(), f"Container path {container_path} does not exist"
        assert container_path.is_file(), f"Container path {container_path} is not a file"

    cmds = ["sbatch", "--parsable", "--job-name", app_config.job_prefix + "-" + container_name]

    cmds += ["--output", app_config.sbatch_output_path]

    sbatch_opts = {
        "parsable": None,
        "job_name": app_config.job_prefix + "-" + container_name,
        "output": app_config.sbatch_output_path,
    }
    if app_config.account:
        sbatch_opts["account"] = app_config.account
    if app_config.partition:
        sbatch_opts["partition"] = app_config.partition
    if app_config.cluster:
        sbatch_opts["clusters"] = app_config.cluster
    if app_config.gpus:
        sbatch_opts["gpus"] = app_config.gpus
    if app_config.timelimit:
        sbatch_opts["time"] = app_config.timelimit
    if app_config.mem:
        sbatch_opts["mem"] = app_config.mem
    if app_config.cpus:
        sbatch_opts["cpus_per_task"] = app_config.cpus

    # Set up the environment variables to pass to Apptainer:
    apptainer_env_vars_quoted = [f"{k}={shlex.quote(v)}" for k, v in app_config.apptainer_env_vars.items()]
    apptainer_env_vars_string = "" if not apptainer_env_vars_quoted else (" ".join(apptainer_env_vars_quoted) + " ")

    # Template to name the apptainer instance:
    apptainer_instance_name = f"{app_config.apptainer_instance_prefix}-$SLURM_JOB_ID-{container_name}"
    # Command to start the apptainer instance:
    apptainer_cmd = f"apptainer instance start {container_path} {apptainer_instance_name}"

    # Command to start the apptainer instance and keep it running:
    apptainer_cmd_with_rest = apptainer_env_vars_string + f"{apptainer_cmd} && while true; do sleep 10; done"

    # The sbatch wrap functionality allows submitting commands without an sbatch script:t
    sbatch_opts["wrap"] = apptainer_cmd_with_rest

    sbatch_command = SbatchCommand(sbatch_options=sbatch_opts)

    if dry_run:
        print("Would have launched sbatch process with command list:\n\t" + sbatch_command.command_list)
        exit(0)

    def kill_self(sig=signal.SIGSTOP):
        os.kill(os.getpid(), sig)

    def cancel_created_jobs():
        for x in app_job_ids:
            logger.info(f"Cancelling job {x}")
            try:
                cancel_job(x)
            except (ValueError, RuntimeError):
                logger.error(f"Could not cancel job {x}")
            else:
                logger.info(f"Cancelled job {x}")

    def create_node_signal_handler(signal_number, frame):
        """
        Pass SIGINT to subprocess and exit program.
        """
        logger.debug(f"hyakvnc create: Caught signal: {signal_number}. Cancelling jobs: {app_job_ids}")
        cancel_created_jobs()
        exit(1)

    signal.signal(signal.SIGINT, create_node_signal_handler)
    signal.signal(signal.SIGTSTP, create_node_signal_handler)
    # signal.signal(signal.SIGKILL, create_node_signal_handler)
    # signal.signal(signal.SIGTERM, create_node_signal_handler)
    # signal.signal(signal.SIGABRT, create_node_signal_handler)

    job_id = None
    try:
        job_id, job_cluster = sbatch_command()
        app_job_ids.append(job_id)
    except RuntimeError as e:
        logger.error(f"Could not submit sbatch job: {e}")
        kill_self()

    logger.info(f"Launched sbatch job {job_id}. Waiting for job to start running")
    try:
        wait_for_job_status(
            job_id,
            states=["RUNNING"],
            timeout=app_config.sbatch_post_timeout,
            poll_interval=app_config.sbatch_post_poll_interval,
        )
    except TimeoutError:
        logger.error(f"Job {job_id} did not start running within {app_config.sbatch_post_timeout} seconds")
        try:
            job = get_historical_job_infos(job_id=job_id)
        except (LookupError, RuntimeError) as e:
            logger.error(f"Could not get historical info for job {job_id}: {e}")
        else:
            if job and len(job) > 0:
                job = job[0]
                state = job.state
                logger.warning(f"Job {job_id} was last in state ({state})")
        finally:
            cancel_created_jobs()
            kill_self()

    real_instance_name = f"{app_config.apptainer_instance_prefix}-{job_id}-{container_name}"
    job = get_job_info(job_id=job_id)
    instance_file = (
        Path(app_config.apptainer_config_dir)
        / "instances"
        / "app"
        / job.node_list[0]
        / job.user_name
        / real_instance_name
        / f"{real_instance_name}.json"
    ).expanduser()

    logger.info("Waiting for Apptainer instance to start running")
    if wait_for_file(str(instance_file), timeout=app_config.sbatch_post_timeout):
        time.sleep(10)  # sleep to wait for apptainer to actually start vncserver <FIXME>
        try:
            sessions = HyakVncSession.find_running_sessions(app_config, job_id=job_id)
            if len(sessions) == 0:
                logger.warning("No running VNC jobs found")
            sessions = [s for s in sessions if s.job_id == job_id]
            if len(sessions) == 0:
                logger.warning("No running VNC jobs found")
            sesh = sessions[0]
        except (ValueError, FileNotFoundError) as e:
            logger.error(f"Could not load instance file: {instance_file} due to error: {e}")
            kill_self()
        else:
            if not repeat_until(lambda: sesh.is_alive(), lambda alive: alive, timeout=app_config.sbatch_post_timeout):
                logger.error("Could not find a running VNC session for the instance {sesh}")
                kill_self()
            print("Connection string for VNC session on Linux-compatible shell:")
            print("  " + sesh.get_openssh_connection_string(login_host=app_config.ssh_host, apple=False))
            print("Connection string for VNC session on macOS:")
            print(" " + sesh.get_openssh_connection_string(login_host=app_config.ssh_host, apple=True))
            return sesh
    else:
        logger.info(f"Could not find instance file at {instance_file} before timeout")
        cancel_job(job_id)
        logger.info(f"Canceled job {job_id} before timeout")
        raise TimeoutError(f"Could not find instance file at {instance_file} before timeout")


def cmd_stop(job_id: Optional[int] = None, stop_all: bool = False):
    assert (job_id is not None) ^ (stop_all), "Must specify either a job id or stop all"
    vnc_sessions = HyakVncSession.find_running_sessions(app_config, job_id=job_id)
    for sesh in vnc_sessions:
        sesh.stop()
        print(f"Canceled job {sesh.job_id}")


def cmd_status():
    logger.info("Finding running VNC jobs...")
    vnc_instances = HyakVncSession.find_running_sessions(app_config)
    if len(vnc_instances) == 0:
        logger.info("No running VNC jobs found")
    else:
        logger.info(f"Found {len(vnc_instances)} running VNC jobs:")
        for instance in vnc_instances:
            print(
                f"Apptainer instance {instance.apptainer_instance_info.name} running as",
                f"SLURM job {instance.job_id} with VNC on port {instance.vnc_port}",
            )


def print_connection_string(job_id: Optional[int] = None, session: Optional[HyakVncSession] = None):
    assert (job_id is not None) ^ (session is not None), "Must specify either a job id or session"
    if job_id:
        sessions = HyakVncSession.find_running_sessions(app_config, job_id=job_id)
        if len(sessions) == 0:
            raise ValueError(f"Could not find session with job id {job_id}")
        session = sessions[0]
    assert session is not None, "Could not find session"

    print("OpenSSH string for VNC session:")
    print("  " + session.get_openssh_connection_string(login_host=app_config.ssh_host, apple=False))
    print("OpenSSH string for VNC session on macOS:")
    print(" " + session.get_openssh_connection_string(login_host=app_config.ssh_host, apple=True))


def print_config():
    print(app_config.to_json())


def create_arg_parser():
    parser = argparse.ArgumentParser(description="HyakVNC: VNC on Hyak", prog="hyakvnc")
    subparsers = parser.add_subparsers(dest="command")

    # general arguments
    parser.add_argument("-d", "--debug", dest="debug", action="store_true", help="Enable debug logging")

    parser.add_argument(
        "-v", "--version", dest="print_version", action="store_true", help="Print program version and exit"
    )

    # command: create
    parser_create = subparsers.add_parser("create", help="Create VNC session")
    parser_create.add_argument("--dry-run", dest="dry_run", action="store_true", help="Dry run (do not submit job)")
    parser_create.add_argument(
        "-p", "--partition", dest="partition", metavar="<partition>", help="Slurm partition", type=str
    )
    parser_create.add_argument("-A", "--account", dest="account", metavar="<account>", help="Slurm account", type=str)
    parser_create.add_argument(
        "--timeout",
        dest="timeout",
        metavar="<time_in_seconds>",
        help="[default: 120] Slurm node allocation and VNC startup timeout length (in seconds)",
        default=120,
        type=int,
    )
    parser_create.add_argument(
        "-t", "--time", dest="time", metavar="<time_in_hours>", help="Subnode reservation time (in hours)", type=int
    )
    parser_create.add_argument(
        "-c", "--cpus", dest="cpus", metavar="<num_cpus>", help="Subnode cpu count", default=1, type=int
    )
    parser_create.add_argument(
        "-G", "--gpus", dest="gpus", metavar="[type:]<num_gpus>", help="Subnode gpu count", default="0", type=str
    )
    parser_create.add_argument(
        "--mem", dest="mem", metavar="<NUM[K|M|G|T]>", help="Subnode memory amount with units", type=str
    )
    parser_create.add_argument(
        "--container",
        dest="container",
        metavar="<path_to_container.sif>",
        help="Path to VNC Apptainer/Singularity Container (.sif)",
        required=True,
        type=str,
    )

    # status command
    parser_status = subparsers.add_parser(  # noqa: F841
        "status", help="Print details of all VNC jobs with given job name and exit"
    )

    # kill command
    parser_stop = subparsers.add_parser("stop", help="Stop specified job")

    parser_stop.add_argument(
        "job_id", metavar="<job_id>", help="Kill specified VNC session, cancel its VNC job, and exit", type=int
    )

    subparsers.add_parser("stop-all", help="Stop all VNC sessions and exit")  # noqa: F841
    subparsers.add_parser("print-config", help="Print app configuration and exit")
    parser_print_connection_string = subparsers.add_parser(
        "print-connection-string", help="Print connection string for job and exit"
    )
    parser_print_connection_string.add_argument(
        "job_id", metavar="<job_id>", help="Job ID of session to connect to", type=int
    )
    return parser


arg_parser = create_arg_parser()
args = arg_parser.parse_args()

os.environ.setdefault("HYAKVNC_LOG_LEVEL", "INFO")

if args.debug:
    os.environ["HYAKVNC_LOG_LEVEL"] = "DEBUG"

log_level = logging.__dict__.get(os.getenv("HYAKVNC_LOG_LEVEL").upper(), logging.INFO)

logger.setLevel(log_level)


def main():
    if args.print_version:
        print(VERSION)
        exit(0)

    # Check SLURM version and print a warning if it's not 22.x:
    # check_slurm_version()

    if args.command == "create":
        try:
            cmd_create(args.container, dry_run=args.dry_run)
        except (TimeoutError, RuntimeError) as e:
            logger.error(f"Error: {e}")
            exit(1)

    elif args.command == "status":
        cmd_status()

    elif args.command == "stop":
        cmd_stop(args.job_id)

    elif args.command == "stop-all":
        cmd_stop(stop_all=True)

    elif args.command == "print-connection-string":
        print_connection_string(args.job_id)

    elif args.command == "print-config":
        print_config()

    else:
        arg_parser.print_help()


if __name__ == "__main__":
    main()
