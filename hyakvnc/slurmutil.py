import os
import subprocess
import sys
import time
from datetime import datetime, timedelta
from typing import Optional, Union, List, Dict, Tuple

from . import logger


def get_default_cluster() -> str:
    """
    Gets the default SLURM cluster.
    :return: the default SLURM cluster
    :raises LookupError: if no default cluster could be found
    """
    cmd = "sacctmgr show cluster -nPs format=Cluster".split()
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
    if res.returncode == 0:
        clusters = res.stdout.splitlines()
        if clusters:
            return clusters[0]
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
    res = subprocess.run(cmd.split(), stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
    if res.returncode == 0:
        accounts = res.stdout.splitlines()
        for x in accounts:
            if x:
                return x
    raise LookupError(f"Could not find default account for user '{user}' on cluster '{cluster}'")


def get_partitions(
    user: Optional[str] = None, account: Optional[str] = None, cluster: Optional[str] = None
) -> List[str]:
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
    res = subprocess.run(
        cmd.split(), stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True
    ).stdout.splitlines()
    for partitions in res:
        if partitions:
            return sorted([x.strip(f"{account}-") for x in partitions.split(",")])
    else:
        raise LookupError(f"Could not find partitions for user '{user}' and account '{account}' on cluster '{cluster}'")


def get_default_partition(
    user: Optional[str] = None, account: Optional[str] = None, cluster: Optional[str] = None
) -> str:
    """
    Gets the default SLURM partition for the specified user and account on the specified cluster.

    :param user: user to get partitions for
    :param account: SLURM account to get partitions for
    :param cluster: SLURM cluster to get partitions for
    :return: the partition for the specified user and account on the specified cluster
    :raises LookupError: if no partitions could be found
    """
    partitions = get_partitions(user=user, account=account, cluster=cluster)
    for p in partitions:
        if p:
            return p
    raise LookupError(
        f"Could not find default partition for user '{user}' and account '{account}' on cluster '{cluster}'"
    )


def node_range_to_list(s: str) -> List[str]:
    """
    Converts a node range to a list of nodes.
    :param s: node range
    :return: list of SLURM nodes
    :raises ValueError: if the node range could not be converted to a list of nodes
    """
    cmds = ["scontrol", "show", "hostnames", s]
    output = subprocess.run(cmds, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
    if output.returncode != 0:
        raise ValueError(f"Could not convert node range '{s}' to list of nodes:\n{output.stderr}")
    return output.stdout.rstrip().splitlines()


class SlurmJobInfo:
    fields: Dict[str, Dict[str, Union[str, Dict[str, str]]]] = {
        "job_id": {"squeue_field": "%i", "sacct_field": "JobID"},
        "job_name": {"squeue_field": "%j", "sacct_field": "JobName"},
        "account": {"squeue_field": "%a", "sacct_field": "Account"},
        "partition": {"squeue_field": "%P", "sacct_field": "Partition"},
        "user_name": {"squeue_field": "%u", "sacct_field": "User"},
        "state": {"squeue_field": "%T", "sacct_field": "State"},
        "time_used": {"squeue_field": "%M", "sacct_field": "Elapsed"},
        "time_limit": {"squeue_field": "%l", "sacct_field": "Timelimit"},
        "cpus": {"squeue_field": "%C", "sacct_field": "AllocCPUS"},
        "min_memory": {"squeue_field": "%m", "sacct_field": "ReqMem"},
        "num_nodes": {"squeue_field": "%D", "sacct_field": "NNodes"},
        "node_list": {"squeue_field": "%N", "sacct_field": "NodeList"},
        "command": {"squeue_field": "%o", "sacct_field": "SubmitLine"},
    }

    def __init__(
        self,
        job_id: int = None,
        job_name: str = None,
        account: str = None,
        partition: str = None,
        user_name: str = None,
        state: str = None,
        time_used: str = None,
        time_limit: str = None,
        cpus: int = None,
        min_memory: str = None,
        num_nodes: int = None,
        node_list: str = None,
        command: str = None,
    ):
        self.job_id = job_id
        self.job_name = job_name
        self.account = account
        self.partition = partition
        self.user_name = user_name
        self.state = state
        self.time_used = time_used
        self.time_limit = time_limit
        self.cpus = cpus
        self.min_memory = min_memory
        self.num_nodes = num_nodes
        self.node_list = node_list
        self.command = command

    @staticmethod
    def from_squeue_line(line: str, field_order=None, delimiter: Optional[str] = None) -> "SlurmJobInfo":
        """
        Creates a SlurmJobInfo from an squeue command
        :param line: output line from squeue command
        :param field_order: order of fields in line (defaults to order in SlurmJobInfo)
        :param delimiter: delimiter for fields in line
        :return: SlurmJobInfo created from line
        """

        valid_field_names = list(SlurmJobInfo.fields.keys())
        if field_order is None:
            field_order = valid_field_names

        if delimiter is None:
            all_fields_dict = {field_order[i]: x for i, x in enumerate(line.split())}
        else:
            all_fields_dict = {field_order[i]: x for i, x in enumerate(line.split(delimiter))}

        field_dict = {k: v for k, v in all_fields_dict.items() if k in valid_field_names}

        try:
            field_dict["job_id"] = int(field_dict["job_id"])
        except (ValueError, TypeError, KeyError):
            field_dict["job_id"] = None
        try:
            field_dict["num_nodes"] = int(field_dict["num_nodes"])
        except (ValueError, TypeError, KeyError):
            field_dict["num_nodes"] = None

        try:
            field_dict["cpus"] = int(field_dict["cpus"])
        except (ValueError, TypeError, KeyError):
            field_dict["cpus"] = None

        if field_dict.get("node_list") == "(null)":
            field_dict["node_list"] = None
        else:
            try:
                field_dict["node_list"] = node_range_to_list(field_dict["node_list"])
            except (ValueError, TypeError, KeyError, FileNotFoundError):
                logger.debug(f"Could not convert node range '{field_dict['node_list']}' to list of nodes")
                field_dict["node_list"] = None

        if field_dict.get("command") == "(null)":
            field_dict["command"] = None

        return SlurmJobInfo(**field_dict)


def get_job_infos(
    jobs: Optional[Union[int, List[int]]] = None, user: Optional[str] = os.getlogin(), cluster: Optional[str] = None
) -> Union[SlurmJobInfo, List[SlurmJobInfo], None]:
    """
    Gets the specified slurm job(s).
    :param user: User to get jobs for
    :param jobs: Job(s) to get
    :param cluster: Cluster to get jobs for
    :return: the specified slurm job(s) as a SlurmJobInfo object or list of SlurmJobInfos, or None if no jobs were found
    :raises LookupError: if the specified job(s) could not be found
    """
    cmds: List[str] = ["squeue", "--noheader"]
    if user:
        cmds += ["--user", user]
    if cluster:
        cmds += ["--clusters", cluster]

    job_is_int = isinstance(jobs, int)

    if jobs:
        if job_is_int:
            jobs = [jobs]

        jobs = ",".join([str(x) for x in jobs])
        cmds += ["--jobs", jobs]

    squeue_format_fields = "\t".join([v.get("squeue_field", "") for k, v in SlurmJobInfo.fields.items()])
    cmds += ["--format", squeue_format_fields]
    res = subprocess.run(cmds, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True, shell=False)
    if res.returncode != 0:
        raise LookupError(f"Could not get slurm jobs:\n{res.stderr}")

    jobs = [SlurmJobInfo.from_squeue_line(line.strip()) for line in res.stdout.splitlines() if line.strip()]
    if job_is_int:
        if len(jobs) > 0:
            return jobs[0]
        else:
            return None
    else:
        return jobs


def get_job_info(job_id: int, cluster: Optional[str] = None) -> Union[SlurmJobInfo, None]:
    """
    Gets the specified SLURM job.
    :param job_id: Job to get
    :param cluster: Cluster to get jobs for
    :return: the specified slurm job(s) as a SlurmJobInfo object
    :raises LookupError: if the specified job(s) could not be found
    """
    cmds: List[str] = ["squeue", "--noheader"]
    if cluster:
        cmds += ["--clusters", cluster]
    cmds += ["--jobs", str(job_id)]
    squeue_format_fields = "\t".join([v.get("squeue_field", "") for k, v in SlurmJobInfo.fields.items()])
    cmds += ["--format", squeue_format_fields]
    res = subprocess.run(cmds, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True, shell=False)
    if res.returncode != 0:
        return None
    jobs = [SlurmJobInfo.from_squeue_line(line.strip()) for line in res.stdout.splitlines() if line.strip()]
    job = jobs[0] if len(jobs) > 0 else None
    return job


def get_job_status(job_id: int) -> str:
    cmd = f"squeue -j {job_id} -h -o %T"
    res = subprocess.run(cmd.split(), stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
    if res.returncode != 0:
        raise RuntimeError(f"Could not get status for job {job_id}:\n{res.stderr}")
    return res.stdout.strip()


def wait_for_job_status(
    job_id: int, states: List[str], timeout: Optional[float] = None, poll_interval: float = 1.0
) -> str:
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


def get_historical_job_infos(
    after: Optional[Union[datetime, timedelta]] = None,
    before: Optional[Union[datetime, timedelta]] = None,
    job_id: Optional[int] = None,
    user: Optional[str] = os.getlogin(),
    cluster: Optional[str] = None,
) -> List[SlurmJobInfo]:
    """
    Gets the slurm jobs since the specified time.
    :param after: Time after which to get jobs
    :param before: Time before which to get jobs
    :param job_id: Job id to get
    :param user: User to get jobs for
    :param cluster: Cluster to get jobs for
    :return: the slurm jobs since the specified time as a list of SlurmJobInfos
    :raises LookupError: if the slurm jobs could not be found
    """
    now = datetime.now()
    assert isinstance(after, (datetime, timedelta, type(None))), "after must be a datetime or timedelta or None"
    assert isinstance(before, (datetime, timedelta, type(None))), "before must be a datetime or timedelta or None"

    after_abs = now - after if isinstance(after, timedelta) else after
    before_abs = now - before if isinstance(before, timedelta) else before

    cmds: List[str] = ["sacct", "--noheader", "-X", "--parsable2"]
    if user:
        cmds += ["--user", user]
    if cluster:
        cmds += ["--clusters", cluster]
    if after_abs:
        cmds += ["--starttime", after_abs.isoformat(timespec="seconds")]
    if before_abs:
        cmds += ["--endtime", before_abs.isoformat(timespec="seconds")]
    if job_id:
        cmds += ["--jobs", str(job_id)]

    sacct_format_fields = ",".join([v.get("sacct_field", "") for k, v in SlurmJobInfo.fields.items()])
    cmds += ["--format", sacct_format_fields]
    res = subprocess.run(cmds, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True, shell=False)
    if res.returncode != 0:
        raise LookupError(f"Could not get slurm jobs via `sacct`:\n{res.stderr}")

    jobs = [
        SlurmJobInfo.from_squeue_line(line.strip(), delimiter="|") for line in res.stdout.splitlines() if line.strip()
    ]
    return jobs


def cancel_job(job: Optional[int] = None, user: Optional[str] = os.getlogin(), cluster: Optional[str] = None):
    """
    Cancels the specified jobs.
    :param job: Job to cancel
    :param user: User to cancel jobs for
    :param cluster: Cluster to cancel jobs for
    :return: None
    :raises ValueError: if no job, user, or cluster is specified
    :raises RuntimeError: if the jobs could not be cancelled
    """
    if job is None and user is None and cluster is None:
        raise ValueError("Must specify at least one of job, user, or cluster")
    cmds = ["scancel"]
    if user:
        cmds += ["--user", user]
    if cluster:
        cmds += ["--clusters", cluster]
    if job:
        cmds += [str(job)]
    res = subprocess.run(cmds, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True, shell=False)
    if res.returncode != 0:
        raise RuntimeError(f"Could not cancel jobs with commands {cmds}: {res.stderr}")


def get_slurm_version_tuple():
    # Get SLURM version:
    res = subprocess.run(
        ["sinfo", "--version"], universal_newlines=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=False
    )
    if res.returncode != 0:
        raise RuntimeError(f"Could not get SLURM version:\n{res.stderr})")
    try:
        v = res.stdout
        assert isinstance(v, str), "Could not parse SLURM version"
        va = v.split(v)
        assert len(va) >= 2
        vt = tuple(va[1].split("."))
        assert len(vt) >= 2
        return vt
    except (ValueError, IndexError, TypeError, AssertionError):
        raise RuntimeError(f"Could not parse SLURM version from string {res.stdout}")


sbatch_option_info = {
    "account": "--account",  # [charge job to specified account]
    "acctg_freq": "--acctg-freq",  # [job accounting and profiling sampling intervals in seconds]
    "array": "--array",  # [job array index values]
    "batch": "--batch",  # [specify a list of node constraints]
    "bb": "--bb",  # [burst buffer specifications]
    "bbf": "--bbf",  # [burst buffer specification file]
    "begin": "--begin",  # [defer job until HH:MM MM/DD/YY]
    "chdir": "--chdir",  # [set working directory for batch script]
    "cluster_constraint": "--cluster-constraint",  # [specify a list of cluster constraints]
    "clusters": "--clusters",  # [comma separated list of clusters to issue]
    "comment": "--comment",  # [arbitrary comment]
    "constraint": "--constraint",  # [specify a list of constraints]
    "container": "--container",  # [path to OCI container bundle]
    "contiguous": "--contiguous",  # [demand a contiguous range of nodes]
    "core_spec": "--core-spec",  # [count of reserved cores]
    "cores_per_socket": "--cores-per-socket",  # [number of cores per socket to allocate]
    "cpu_freq": "--cpu-freq",  # [requested cpu frequency (and governor)]
    "cpus_per_gpu": "--cpus-per-gpu",  # [number of CPUs required per allocated GPU]
    "cpus_per_task": "--cpus-per-task",  # [number of cpus required per task]
    "deadline": "--deadline",  # [remove the job if no ending possible before]
    "delay_boot": "--delay-boot",  # [delay boot for desired node features]
    "dependency": "--dependency",  # [defer job until condition on jobid is satisfied]
    "distribution": "--distribution",  # [distribution method for processes to nodes]
    "error": "--error",  # [file for batch scripts standard error]
    "exclude": "--exclude",  # [exclude a specific list of hosts]
    "exclusive": "--exclusive",  # [allocate nodes in exclusive mode when]
    "export": "--export",  # [specify environment variables to export]
    "export_file": "--export-file",  # [specify environment variables file or file]
    "extra_node_info": "--extra-node-info",  # [combine request of sockets per node]
    "get_user_env": "--get-user-env",  # [load environment from local cluster]
    "gid": "--gid",  # [group ID to run job as (user root only)]
    "gpu_bind": "--gpu-bind",  # [task to gpu binding options]
    "gpu_freq": "--gpu-freq",  # [frequency and voltage of GPUs]
    "gpus": "--gpus",  # [count of GPUs required for the job]
    "gpus_per_node": "--gpus-per-node",  # [number of GPUs required per allocated node]
    "gpus_per_socket": "--gpus-per-socket",  # [number of GPUs required per allocated socket]
    "gpus_per_task": "--gpus-per-task",  # [number of GPUs required per spawned task]
    "gres": "--gres",  # [required generic resources]
    "gres_flags": "--gres-flags",  # [flags related to GRES management]
    "hint": "--hint",  # [bind tasks according to application hints]
    "hold": "--hold",  # [submit job in held state]
    "ignore_pbs": "--ignore-pbs",  # [ignore #PBS and #BSUB options in the batch script]
    "input": "--input",  # [file for batch scripts standard input]
    "job_name": "--job-name",  # [name of job]
    "kill_on_invalid_dep": "--kill-on-invalid-dep",  # [terminate job if invalid dependency]
    "licenses": "--licenses",  # [required license, comma separated]
    "mail_type": "--mail-type",  # [notify on state change: BEGIN, END, FAIL or ALL]
    "mail_user": "--mail-user",  # [who to send email notification for job state]
    "mcs_label": "--mcs-label",  # [mcs label if mcs plugin mcs/group is used]
    "mem": "--mem",  # [minimum amount of real memory]
    "mem_bind": "--mem-bind",  # [bind memory to locality domains (ldom)]
    "mem_per_cpu": "--mem-per-cpu",  # [maximum amount of real memory per allocated]
    "mem_per_cpu,__mem": "--mem-per-cpu,--mem",  # [specified.]
    "mem_per_gpu": "--mem-per-gpu",  # [real memory required per allocated GPU]
    "mincpus": "--mincpus",  # [minimum number of logical processors (threads)]
    "network": "--network",  # [specify information pertaining to the switch or network]
    "nice": "--nice",  # [decrease scheduling priority by value]
    "no_kill": "--no-kill",  # [do not kill job on node failure]
    "no_requeue": "--no-requeue",  # [if set, do not permit the job to be requeued]
    "nodefile": "--nodefile",  # [request a specific list of hosts]
    "nodelist": "--nodelist",  # [request a specific list of hosts]
    "nodes": "--nodes",  # [number of nodes on which to run (N = min\[-max\])]
    "ntasks": "--ntasks",  # [number of tasks to run]
    "ntasks_per_core": "--ntasks-per-core",  # [number of tasks to invoke on each core]
    "ntasks_per_gpu": "--ntasks-per-gpu",  # [number of tasks to invoke for each GPU]
    "ntasks_per_node": "--ntasks-per-node",  # [number of tasks to invoke on each node]
    "ntasks_per_socket": "--ntasks-per-socket",  # [number of tasks to invoke on each socket]
    "open_mode": "--open-mode",  # [ {append|truncate} output and error file}
    "output": "--output",  # [file for batch scripts standard output]
    "overcommit": "--overcommit",  # [overcommit resources]
    "oversubscribe": "--oversubscribe",  # [over subscribe resources with other jobs]
    "parsable": "--parsable",  # [outputs only the jobid and cluster name (if present)]
    "partition": "--partition",  # [partition requested]
    "power": "--power",  # [power management options]
    "prefer": "--prefer",  # [features desired but not required by job]
    "priority": "--priority",  # [set the priority of the job to value]
    "profile": "--profile",  # [enable acct_gather_profile for detailed data]
    "propagate": "--propagate",  # [propagate all \[or specific list of\] rlimits]
    "qos": "--qos",  # [quality of service]
    "quiet": "--quiet",  # [quiet mode (suppress informational messages)]
    "reboot": "--reboot",  # [reboot compute nodes before starting job]
    "requeue": "--requeue",  # [if set, permit the job to be requeued]
    "reservation": "--reservation",  # [allocate resources from named reservation]
    "signal": "--signal",  # [@time\] send signal when time limit within time seconds]
    "sockets_per_node": "--sockets-per-node",  # [number of sockets per node to allocate]
    "spread_job": "--spread-job",  # [spread job across as many nodes as possible]
    "switches": "--switches",  # [{@max-time-to-wait}]
    "test_only": "--test-only",  # [validate batch script but do not submit]
    "thread_spec": "--thread-spec",  # [count of reserved threads]
    "threads_per_core": "--threads-per-core",  # [number of threads per core to allocate]
    "time": "--time",  # [time limit]
    "time_min": "--time-min",  # [minimum time limit (if distinct)]
    "tmp": "--tmp",  # [minimum amount of temporary disk]
    "uid": "--uid",  # [user ID to run job as (user root only)]
    "use_min_nodes": "--use-min-nodes",  # [if a range of node counts is given, prefer the]
    "verbose": "--verbose",  # [verbose mode (multiple -vs increase verbosity)]
    "wait": "--wait",  # [wait for completion of submitted job]
    "wait_all_nodes": "--wait-all-nodes",
    # [wait for all nodes to be allocated if 0 (default) or wait until all nodes ready (1)]]
    "wckey": "--wckey",  # [wckey to run job under]
    "wrap": "--wrap",  # [wrap command string in a sh script and submit]
}


class SbatchCommand:
    def __init__(
        self,
        sbatch_options: Optional[Dict[str, Union[str, None]]] = None,
        sbatch_args: Optional[List[str]] = None,
        sbatch_executable: str = "sbatch",
    ):
        """
        :param sbatch_options: sbatch options
        :param sbatch_args: sbatch arguments
        :param sbatch_executable: sbatch executable
        """
        command_list = [sbatch_executable]
        for k, v in sbatch_options.items():
            if k in sbatch_option_info:
                command_list += [sbatch_option_info[k]]
            else:
                raise KeyError(f"Unrecognized sbatch option {k}")
        if sbatch_args:
            command_list += sbatch_args

        self.command_list = command_list
        self.sbatch_executable = sbatch_executable
        self.sbatch_options = sbatch_options
        self.sbatch_args = sbatch_args

    def __call__(self, **run_kwargs) -> Tuple[int, Union[str, None]]:
        """
        Submits a job to SLURM using sbatch with the list of commands specified in the constructor.
        :param run_args: args to pass to subprocess.run
        :param run_kwargs: kwargs to pass to subprocess.run
        """
        run_kwargs = run_kwargs or dict()
        run_kwargs.setdefault("stdout", subprocess.PIPE)
        run_kwargs.setdefault("stderr", subprocess.PIPE)
        run_kwargs.setdefault("shell", False)
        run_kwargs.setdefault("universal_newlines", True)
        run_kwargs.setdefault("encoding", sys.getdefaultencoding())
        logger.debug("Running sbatch command with args\n\t{self.command_list}")
        res = subprocess.run(self.command_list, **run_kwargs)
        if res.returncode != 0:
            raise RuntimeError(f"Could not launch sbatch job:\n{res.stderr}")
        if not res.stdout:
            raise RuntimeError("No sbatch output")
        try:
            out = res.stdout.strip().split()
            job_id, cluster_name = None, None
            if len(out) < 1:
                raise RuntimeError(f"Could not parse jobid from sbatch output: {res.stdout}")
            job_id = int(out[0])
            if len(out) > 1:
                cluster_name = out[1]
            if len(out) > 2:
                logger.warning(f"Unexpected sbatch output: {res.stdout}")
            return job_id, cluster_name
        except (ValueError, IndexError, TypeError, AttributeError):
            raise RuntimeError(f"Could not parse jobid from sbatch output: {res.stdout}")
