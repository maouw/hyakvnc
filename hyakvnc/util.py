import time
from typing import Callable, Optional, Union
import logging
from pathlib import Path
import subprocess
def repeat_until(func: Callable, condition: Callable[[int], bool], timeout: Optional[float] = None,
                 poll_interval: float = 1.0):
    begin_time = time.time()
    assert timeout is None or timeout > 0, "Timeout must be greater than zero"
    assert poll_interval > 0, "Poll interval must be greater than zero"
    timeout = timeout or -1.0
    while time.time() < begin_time + timeout:
        res = func()
        if condition(res):
            return res
        time.sleep(poll_interval)
    return False


def wait_for_file(path: Union[Path, str], timeout: Optional[float] = None,
                 poll_interval: float = 1.0):
    """
    Waits for the specified file to be present.
    """
    path = Path(path)
    logging.debug(f"Waiting for file `{path}` to exist")
    return repeat_until(lambda: path.exists(), lambda exists: exists, timeout=timeout, poll_interval=poll_interval)

def check_remote_pid_exists_and_port_open(host: str, pid: int, port: int) -> bool:
    cmd = f"ssh {host} ps -p {pid} && nc -z localhost {port}".split()
    res = subprocess.run(cmd, shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return res.returncode == 0
