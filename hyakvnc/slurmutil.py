# -*- coding: utf-8 -*-
import os
import subprocess
import time
from dataclasses import dataclass, fields, field
from typing import Optional, Union, Container


def get_default_cluster() -> str:
    """
    Gets the default SLURM cluster.
    :return: the default SLURM cluster
    :raises LookupError: if no default cluster could be found
    """
    cmd = f"sacctmgr show cluster -nPs format=Cluster".split()
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True).stdout.splitlines()
    if res:
        return res[0]
    else:
        raise LookupError("Could not find default cluster")


def get_default_account(user: Optional[str] = None, cluster: Optional[str] = None) -> str:
    """
    Gets the default SLURM account for the specified user on the specified SLURM cluster.
    :param user: User to get default account for
    :param cluster: SLURM cluster to get default account for
    :return: the default SLURM account for the specified user on the specified cluster
    :raises LookupError: if no default account could be found
    """
    user = user or os.getlogin()
    cluster = cluster or get_default_cluster()

    cmd = f"sacctmgr show user -nPs {user} format=defaultaccount where cluster={cluster}"
    res = subprocess.run(cmd.split(), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if res.returncode == 0:
        accounts = res.stdout.splitlines()
        if any(default_account := x for x in accounts):
            return default_account
    raise LookupError(f"Could not find default account for user '{user}' on cluster '{cluster}'")


def get_partitions(user: Optional[str] = None,
                   account: Optional[str] = None,
                   cluster: Optional[str] = None) -> list[str]:
    """
    Gets the SLURM partitions for the specified user and account on the specified cluster.

    :param user: user to get partitions for
    :param account: SLURM account to get partitions for
    :param cluster: SLURM cluster to get partitions for
    :return: the SLURM partitions for the specified user and account on the specified cluster
    :raises LookupError: if no partitions could be found
    """
    user = user or os.getlogin()
    cluster = cluster or get_default_cluster()
    account = account or get_default_account(user=user, cluster=cluster)
    cmd = f"sacctmgr show -nPs user {user} format=qos where account={account} cluster={cluster}"
    res = subprocess.run(cmd.split(), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True).stdout.splitlines()

    if any(partitions := x for x in res):
        return sorted([x.strip(f"{account}-") for x in partitions.split(',')])
    else:
        raise LookupError(f"Could not find partitions for user '{user}' and account '{account}' on cluster '{cluster}'")


def get_default_partition(user: Optional[str] = None, account: Optional[str] = None,
                          cluster: Optional[str] = None) -> str:
    """
    Gets the default SLURM partition for the specified user and account on the specified cluster.

    :param user: user to get partitions for
    :param account: SLURM account to get partitions for
    :param cluster: SLURM cluster to get partitions for
    :return: the partition for the specified user and account on the specified cluster
    :raises LookupError: if no partitions could be found
    """
    partitions = get_partitions(user=user, account=account, cluster=cluster)
    if any(default_partition := x for x in partitions):
        return default_partition
    else:
        raise LookupError(
            f"Could not find default partition for user '{user}' and account '{account}' on cluster '{cluster}'")


def node_range_to_list(s: str) -> list[str]:
    """
    Converts a node range to a list of nodes.
    :param s: node range
    :return: list of SLURM nodes
    :raises ValueError: if the node range could not be converted to a list of nodes
    """
    output = subprocess.run(f"scontrol show hostnames {s}", stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if output.returncode != 0:
        raise ValueError(f"Could not convert node range '{s}' to list of nodes:\n{output.stderr}")
    return output.stdout.rstrip().splitlines()


@dataclass
class SlurmJob:
    job_id: int = field(metadata={"squeue_field": "JobID"})
    job_name: str = field(metadata={"squeue_field": "JobName"})
    account: str = field(metadata={"squeue_field": "Account"})
    partition: str = field(metadata={"squeue_field": "Partition"})
    user_name: str = field(metadata={"squeue_field": "UserName"})
    state: str = field(metadata={"squeue_field": "State"})
    time_used: str = field(metadata={"squeue_field": "TimeUsed"})
    time_limit: str = field(metadata={"squeue_field": "TimeLimit"})
    num_nodes: int = field(metadata={"squeue_field": "NumNodes"})
    node_list: str = field(metadata={"squeue_field": "NodeList"})
    command: str = field(metadata={"squeue_field": "Command"})
    cpus_per_task: int = field(metadata={"squeue_field": "cpus-per-task"})
    num_cpus: int = field(metadata={"squeue_field": "NumCPUs"})
    min_memory: str = field(metadata={"squeue_field": "MinMemory"})

    @staticmethod
    def from_squeue_line(line: str, field_order=None) -> "SlurmJob":
        """
        Creates a SlurmJob from an squeue command
        :param line: output line from squeue command
        :param field_order: order of fields in line (defaults to order in SlurmJob)
        :return: SlurmJob created from line
        """

        valid_field_names = [x.name for x in fields(SlurmJob)]
        if field_order is None:
            field_order = valid_field_names

        #
        all_fields_dict = {field_order[i]: x for i, x in enumerate(line.split())}
        field_dict = {k: v for k, v in all_fields_dict.items() if k in valid_field_names}

        try:
            field_dict["num_nodes"] = int(field_dict["num_nodes"])
        except (ValueError, TypeError, KeyError):
            field_dict["num_nodes"] = None
        try:
            field_dict["cpus_per_task"] = int(field_dict["cpus_per_task"])
        except (ValueError, TypeError, KeyError):
            field_dict["cpus_per_task"] = None
        try:
            field_dict["num_cpus"] = int(field_dict["num_cpus"])
        except (ValueError, TypeError, KeyError):
            field_dict["num_cpus"] = None

        try:
            field_dict["node_list"] = node_range_to_list(field_dict["node_list"])
        except (ValueError, TypeError, KeyError):
            field_dict["node_list"] = None

        return SlurmJob(**field_dict)


def get_job(jobs: Optional[Union[int, list[int]]] = None,
            user: Optional[str] = os.getlogin(),
            cluster: Optional[str] = None,
            field_names: Optional[Container[str]] = None
            ) -> Union[SlurmJob, list[SlurmJob], None]:
    """
    Gets the specified slurm job(s).
    :param user: User to get jobs for
    :param jobs: Job(s) to get
    :param cluster: Cluster to get jobs for
    :param field_names: Fields to get for jobs (defaults to all fields in SlurmJob)
    :return: the specified slurm job(s) as a SlurmJob object or list of SlurmJobs, or None if no jobs were found
    """
    cmds: list[str] = ['squeue', '--noheader']
    if user:
        cmds += ['--user', user]
    if cluster:
        cmds += ['--clusters', cluster]

    job_is_int = isinstance(jobs, int)

    if jobs:
        if job_is_int:
            jobs = [jobs]
        else:
            jobs = ','.join([str(x) for x in jobs])
        cmds += ['--jobs', jobs]

    slurm_job_fields = [f for f in fields(SlurmJob) if f.name in field_names]
    assert len(slurm_job_fields) > 0, "Must specify at least one field to get for slurm jobs"
    squeue_format_fields = ",".join([f.metadata.get("squeue_field", "") for f in slurm_job_fields])

    cmds += ['--Format', squeue_format_fields]
    res = subprocess.run(cmds, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if res.returncode != 0:
        raise ValueError(f"Could not get slurm jobs:\n{res.stderr}")

    jobs = [SlurmJob.from_squeue_line(line) for x in res.stdout.splitlines() if (line := x.strip())]
    if job_is_int:
        if len(jobs) > 0:
            return jobs[0]
        else:
            return None
    else:
        return jobs


def get_job_status(jobid: int) -> str:
    cmd = f"squeue -j {jobid} -h -o %T"
    res = subprocess.run(cmd.split(), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if res.returncode != 0:
        raise ValueError(f"Could not get status for job {jobid}:\n{res.stderr}")
    return res.stdout.strip()


def wait_for_job_status(job_id: int, states: list[str], timeout: Optional[float] = None,
                        poll_interval: float = 1.0) -> str:
    """
    Waits for the specified job to be in one of the specified states.
    :param job_id: job id to wait for
    :param states: list of states to wait for
    :param timeout: timeout for waiting for job to be in one of the specified states
    :param poll_interval: poll interval for waiting for job to be in one of the specified states
    :return: True if the job is in one of the specified states, False otherwise
    :raises TimeoutError: if the job is not in one of the specified states after the timeout
    """
    begin_time = time.time()
    assert isinstance(job_id, int), "Job id must be an integer"
    assert (timeout is None) or (timeout > 0), "Timeout must be greater than zero"
    assert poll_interval > 0, "Poll interval must be greater than zero"
    timeout = timeout or -1.0
    while time.time() < begin_time + timeout:
        res = get_job_status(job_id)
        if res in states:
            return res
        time.sleep(poll_interval)
    raise TimeoutError(f"Timed out waiting for job {job_id} to be in one of the following states: {states}")
