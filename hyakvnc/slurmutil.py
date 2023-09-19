# -*- coding: utf-8 -*-
import sys
import os
import subprocess
import re
from typing import Optional, Iterable, Union, List

import json
from pathlib import Path


def get_slurmd_config():
    cmd = f"slurmd -C".split()
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, encoding='utf-8').stdout.splitlines()
    return dict([re.match(r'([^=]+)+=(.*)', k).groups() for k in res.split()])


def get_slurm_cluster():
    cmd = f"sacctmgr show cluster -nPs format=Cluster".split()
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, encoding='utf-8').stdout.splitlines()
    if any(cluster := x for x in res):
        return cluster
    else:
        raise ValueError("Could not find cluster name")

def get_slurm_default_account(user: Optional[str] = None, cluster: Optional[str] = None):
    user = user or os.getlogin()
    cluster = cluster or get_slurm_cluster()
    cmd = f"sacctmgr show user -nPs {user} format=defaultaccount where cluster={cluster}".split()
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,  encoding='utf-8').stdout.splitlines()
    if any(default_account := x for x in res):
        return default_account
    else:
        raise ValueError(f"Could not find default account for user '{user}' on cluster '{cluster}'")


def get_slurm_partitions(user: Optional[str] = None, account: Optional[str] = None, cluster: Optional[str] = None):
    user = user or os.getlogin()
    cluster = cluster or get_slurm_cluster()
    account = account or get_slurm_default_account(user=user, cluster=cluster)
    cmd = f"sacctmgr show -nPs user {user} format=qos where account={account} cluster={cluster}".split()
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,  encoding='utf-8').stdout.splitlines()
    if any(partitions := x for x in res):
        return {x.strip(f"{account}-") for x in partitions.split(',')}
    else:
        raise ValueError(f"Could not find partitions for user '{user}' and account '{account}' on cluster '{cluster}'")


def get_slurm_job_details(user: Optional[str] = None, jobs: Optional[Union[int, list[int]]] = None, me: bool = True,
                          cluster: Optional[str] = None,
                          fields=(
                              'JobId', 'Partition', 'Name', 'State', 'TimeUsed', 'TimeLimit', 'NumNodes', 'NodeList')):
    if me and not user:
        user = os.getlogin()
    cluster = cluster or get_slurm_cluster()

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
    res = subprocess.run(cmds, stdout=subprocess.PIPE, stderr=subprocess.PIPE, encoding="utf-8").stdout.splitlines()
    out = {x["JobId"]: x for x in [dict(zip(fields, line.split())) for line in res if line.strip()]}
    return out
