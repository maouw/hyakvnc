import base64
import json
import subprocess
import sys
from pathlib import Path
from typing import Union, Dict, Any, Optional, List
import re
import inspect


class ApptainerInstanceInfo:
    def __init__(
        self,
        pid: int,
        name: str,
        image: Union[str, Path],
        logErrPath: Union[str, Path],
        logOutPath: Union[str, Path],
        instance_metadata_path: Optional[Union[str, Path]] = None,
        instance_host: Optional[str] = None,
        ppid: Optional[int] = None,
        user: Optional[str] = None,
        userns: Optional[bool] = None,
        cgroup: Optional[bool] = None,
        ip: Optional[str] = None,
        checkpoint: Optional[str] = None,
        config: Optional[Dict[str, Any]] = None,
    ):
        """
        Information about an apptainer instance.
        :param pid: pid of the instance
        :param name: name of the instance
        :param image: image of the instance
        :param logErrPath: path to stderr log of the instance
        :param logOutPath: path to stdout log of the instance
        :param instance_metadata_path: path to instance metadata file
        :param instance_host: host of the instance
        :param ppid: parent pid of the instance
        :param user: user of the instance
        :param userns: whether userns is enabled for the instance
        :param cgroup: whether cgroup is enabled for the instance
        :param ip: ip address of the instance
        :param checkpoint: checkpoint of the instance
        :param config: config of the instance
        """
        self.pid = pid
        self.ppid = ppid
        self.name = name
        self.user = user
        self.image = image
        self.userns = userns
        self.cgroup = cgroup
        self.ip = ip
        self.logErrPath = Path(logErrPath) if logErrPath else None
        self.logOutPath = Path(logOutPath) if logOutPath else None
        self.checkpoint = checkpoint
        self.config = config
        self.instance_metadata_path = Path(instance_metadata_path) if instance_metadata_path else None
        self.instance_host = instance_host

        p = self.logOutPath or self.logErrPath
        if p:
            if p.match("instances/logs/*/*/*") and len(p.parts) >= 5:
                ps = p.parts[-3:-1]
                if not self.instance_host:
                    self.instance_host = ps[0] if not self.instance_host else self.instance_host
                if not self.user:
                    self.user = ps[1]
                if not self.instance_metadata_path:
                    new_parts = list(p.parent.parts)
                    if new_parts[-3] == "logs" and new_parts[-4] == "instances":
                        new_parts[-3] = "app"
                        new_parts += [self.name, self.name + ".json"]
                        candidate_instance_metadata_path = Path(*new_parts)
                        if candidate_instance_metadata_path.is_file():
                            self.instance_metadata_path = candidate_instance_metadata_path

    def __str__(self):
        return json.dumps({k: v for k, v in self.__dict__.items() if v is not None}, sort_keys=False, default=str)

    def __repr__(self):
        d = self.__dict__.copy()
        for k, v in d.items():
            if isinstance(v, Path):
                d[k] = str(v)
        s = ", ".join([f"{k}={repr(v)}" for k, v in d.items() if v is not None])
        return f"ApptainerInstanceInfo({s})"

    @staticmethod
    def from_json(path: Union[str, Path], read_config: bool = False) -> "ApptainerInstanceInfo":
        """
        Loads a ApptainerInstanceInfo from a JSON file.
        :param path: path to JSON file
        :param read_config: whether to read the config from the JSON file
        :return: ApptainerInstanceInfo loaded from JSON file
        :raises ValueError: if the JSON file is invalid
        :raises FileNotFoundError: if the JSON file does not exist
        """
        path = Path(path).expanduser()
        try:
            with open(path, "r") as f:
                contents = json.load(f)
                if not read_config:
                    contents.pop("config", None)
                else:
                    if "config" in contents:
                        contents["config"] = json.loads(base64.b64decode(contents["config"]).decode("utf-8"))
                contents["instance_metadata_path"] = str(path)
                contents["name"] = str(path.stem)

                args_to_use = inspect.getfullargspec(ApptainerInstanceInfo.__init__).args
                dct = {k: v for k, v in contents.items() if k in args_to_use}
                return ApptainerInstanceInfo(**dct)
        except (json.JSONDecodeError, ValueError, TypeError) as e:
            raise ValueError(f"Cannot create from JSON: {path} due to {e}")
        except FileNotFoundError as e:
            raise FileNotFoundError(f"Could not find instance file: {path} due to {e}")

    @staticmethod
    def from_apptainer_instance_list_json(s: str, instance_host: Optional[str] = None) -> List["ApptainerInstanceInfo"]:
        """
        Loads a ApptainerInstanceInfo from a JSON description.
        :param s: JSON description
        :param instance_host: host of the instance
        """
        try:
            contents = json.loads(s, strict=False)
            instances = [
                ApptainerInstanceInfo(
                    pid=int(instance_dct["pid"]),
                    name=instance_dct["instance"],
                    image=instance_dct["img"],
                    logErrPath=instance_dct["logErrPath"],
                    logOutPath=instance_dct["logOutPath"],
                    ip=instance_dct.get("ip", None),
                    instance_host=instance_host,
                )
                for instance_dct in contents["instances"]
            ]
            return instances
        except (json.JSONDecodeError, ValueError, TypeError) as e:
            raise ValueError(f"Cannot create from JSON: {s} due to {e}")


def apptainer_instance_list(
    slurm_job_id: Optional[int] = None, host: Optional[str] = None
) -> List[ApptainerInstanceInfo]:
    """
    Lists all apptainer instances locally or running on a slurm job.
    """
    cmdv = list()
    if slurm_job_id:
        cmdv += ["srun", "--jobid", str(slurm_job_id)]
    elif host:
        cmdv += ["ssh", host]
    cmdv += ["apptainer", "instance", "list", "--json"]
    res = subprocess.run(
        cmdv,
        shell=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        universal_newlines=True,
        encoding=sys.getdefaultencoding(),
    )
    if res.returncode != 0 or not res.stdout:
        return list()
    instances = ApptainerInstanceInfo.from_apptainer_instance_list_json(res.stdout)
    return instances


def apptainer_instance_stop(
    instance: Union[str, None] = None,
    stop_all: bool = False,
    force: bool = False,
    signal_to_send: Optional[str] = None,
    timeout: Optional[int] = None,
    slurm_job_id: Optional[int] = None,
    host: Optional[str] = None,
):
    cmdv = list()
    if slurm_job_id:
        cmdv += ["srun", "--jobid", str(slurm_job_id)]
    elif host:
        cmdv += ["ssh", host]
    cmdv += ["apptainer", "instance", "stop"]
    if force:
        cmdv += ["--force"]
    if signal_to_send:
        cmdv += ["--signal", signal_to_send]
    if timeout:
        cmdv += ["--timeout", str(timeout)]
    if stop_all:
        cmdv += ["--all"]
    else:
        if instance:
            cmdv += [instance]
        else:
            raise ValueError("Must specify either `instance` or `all`")

    res = subprocess.run(
        cmdv,
        shell=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        universal_newlines=True,
        encoding=sys.getdefaultencoding(),
    )
    if res.returncode != 0:
        return list()

    if res.stderr:
        stopped = list()
        for line in res.stderr.splitlines():
            m = re.match(r".*INFO:\s*Stopping (?P<instance>\S+) instance of (?P<image>\S+) \(PID=(?P<pid>\d+)\)", line)
            if m:
                d = m.groupdict()
                d["pid"] = int(d["pid"])
                stopped.append(d)
        return stopped
