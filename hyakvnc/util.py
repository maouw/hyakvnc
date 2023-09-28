import subprocess
import sys
import time
from pathlib import Path
from typing import Callable, Optional, Union


def repeat_until(
    func: Callable,
    condition: Callable[[int], bool],
    timeout: Optional[float] = None,
    poll_interval: float = 1.0,
    max_iter: Optional[int] = None,
) -> bool:
    begin_time = time.time()
    assert timeout is None or timeout > 0, "Timeout must be greater than zero"
    assert poll_interval > 0, "Poll interval must be greater than zero"
    timeout = timeout or -1.0
    i = 0
    while time.time() < begin_time + timeout:
        if max_iter:
            if i >= max_iter:
                return False
        res = func()
        if condition(res):
            return True
        time.sleep(poll_interval)
        i += 1
    return False


def wait_for_file(path: Union[Path, str], timeout: Optional[float] = None, poll_interval: float = 1.0):
    """
    Waits for the specified file to be present.
    """
    path = Path(path)
    return repeat_until(lambda: path.exists(), lambda exists: exists, timeout=timeout, poll_interval=poll_interval)


def check_remote_pid_exists_and_port_open(
    pid: int, port: int, slurm_job_id: Optional[int] = None, host: Optional[str] = None
) -> bool:
    cmdv = list()
    if slurm_job_id:
        cmdv += ["srun", "--jobid", str(slurm_job_id)]
    elif host:
        cmdv += ["ssh", host]

    cmdv += ["ps", "--no-headers", "-p", str(pid), "&&", "nc", "-z", "localhost", str(port)]
    res = subprocess.run(
        cmdv,
        shell=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        universal_newlines=True,
        encoding=sys.getdefaultencoding(),
    )
    return res.returncode == 0


def check_remote_pid_exists(pid: int, slurm_job_id: Optional[int] = None, host: Optional[str] = None) -> bool:
    cmdv = list()
    if slurm_job_id:
        cmdv += ["srun", "--jobid", str(slurm_job_id)]
    elif host:
        cmdv += ["ssh", host]
    cmdv += ["ps", "--no-headers", "-p", str(pid)]
    res = subprocess.run(
        cmdv,
        shell=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        universal_newlines=True,
        encoding=sys.getdefaultencoding(),
    )
    return res.returncode == 0


def check_remote_port_open(port: int, slurm_job_id: Optional[int] = None, host: Optional[str] = None) -> bool:
    cmdv = list()
    if slurm_job_id:
        cmdv += ["srun", "--jobid", str(slurm_job_id)]
    elif host:
        cmdv += ["ssh", host]
    cmdv += ["nc", "-z", "localhost", str(port)]
    res = subprocess.run(
        cmdv,
        shell=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        universal_newlines=True,
        encoding=sys.getdefaultencoding(),
    )
    return res.returncode == 0
