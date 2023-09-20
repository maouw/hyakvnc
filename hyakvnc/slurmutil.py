# -*- coding: utf-8 -*-
import os
import subprocess
import sys
from typing import Optional, Union, Container

from .util import repeat_until


def get_default_cluster() -> str:
    cmd = f"sacctmgr show cluster -nPs format=Cluster".split()
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                         encoding=sys.getdefaultencoding()).stdout.splitlines()
    if res:
        return res[0]
    else:
        raise LookupError("Could not find default cluster")


def get_default_account(user: Optional[str] = None, cluster: Optional[str] = None) -> str:
    user = user or os.getlogin()
    cluster = cluster or get_default_cluster()

    cmd = f"sacctmgr show user -nPs {user} format=defaultaccount where cluster={cluster}"

    res = subprocess.run(cmd.split(), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                         encoding=sys.getdefaultencoding()).stdout.splitlines()

    if any(default_account := x for x in res):
        return default_account
    else:
        raise LookupError(f"Could not find default account for user '{user}' on cluster '{cluster}'")


def get_partitions(user: Optional[str] = None, account: Optional[str] = None, cluster: Optional[str] = None) -> set[
    str]:
    user = user or os.getlogin()
    cluster = cluster or get_default_cluster()
    account = account or get_default_account(user=user, cluster=cluster)
    cmd = f"sacctmgr show -nPs user {user} format=qos where account={account} cluster={cluster}"
    res = subprocess.run(cmd.split(), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                         encoding=sys.getdefaultencoding()).stdout.splitlines()

    if any(partitions := x for x in res):
        return {x.strip(f"{account}-") for x in partitions.split(',')}
    else:
        raise ValueError(f"Could not find partitions for user '{user}' and account '{account}' on cluster '{cluster}'")


def get_job_details(user: Optional[str] = None, jobs: Optional[Union[int, list[int]]] = None, me: bool = True,
                    cluster: Optional[str] = None,
                    fields=(
                        'JobId', 'Partition', 'Name', 'State', 'TimeUsed', 'TimeLimit', 'NumNodes',
                        'NodeList')) -> dict:
    if me and not user:
        user = os.getlogin()
    cluster = cluster or get_default_cluster()

    cmds: list[str] = ['squeue', '--noheader']
    fields_str = ','.join(fields)
    cmds += ['--Format', fields_str]

    if user:
        cmds += ['--user', user]
    if jobs:
        if isinstance(jobs, int):
            jobs = [jobs]
        jobs = ','.join([str(x) for x in jobs])
        cmds += ['--jobs', jobs]
    res = subprocess.run(cmds, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                         encoding=sys.getdefaultencoding()).stdout.splitlines()
    out = {x["JobId"]: x for x in [dict(zip(fields, line.split())) for line in res if line.strip()]}
    return out


def get_job_status(jobid: int) -> str:
    cmd = f"squeue -j {jobid} -h -o %T"
    res = subprocess.run(cmd.split(), stdout=subprocess.PIPE, stderr=subprocess.PIPE, encoding=sys.getdefaultencoding())
    if res.returncode != 0:
        raise ValueError(f"Could not get status for job {jobid}:\n{res.stderr}")
    return res.stdout.strip()


def wait_for_job_status(job_id: int, states: Container[str], timeout: Optional[float] = None,
                        poll_interval: float = 1.0) -> bool:
    """Waits for the specified job state to be reached"""
    return repeat_until(lambda: get_job_status(job_id), lambda x: x in states, timeout=timeout,
                        poll_interval=poll_interval)
