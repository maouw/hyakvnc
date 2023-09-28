import pprint
import re
from pathlib import Path
from typing import Optional, Union, List

from . import logger
from .apptainer import ApptainerInstanceInfo, apptainer_instance_list, apptainer_instance_stop
from .config import HyakVncConfig
from .slurmutil import get_job_infos, cancel_job
from .util import check_remote_pid_exists_and_port_open, check_remote_pid_exists, check_remote_port_open


class HyakVncSession:
    def __init__(
        self,
        job_id: int,
        apptainer_instance_info: ApptainerInstanceInfo,
        app_config: HyakVncConfig,
    ):
        """
        Represents a VNC instance on Hyak.
        :param job_id: SLURM job ID of the instance
        :param apptainer_instance_info: ApptainerInstanceInfo for the instance
        :param app_config: HyakVncConfig for the instance
        :raises ValueError: if the instance name cannot be parsed
        :raises FileNotFoundError: if the log file cannot be found
        """
        self.job_id = job_id
        self.apptainer_instance_info = apptainer_instance_info
        self.app_config = app_config
        self.vnc_port = None
        self.vnc_log_file_path = None
        self.vnc_pid_file_path = None

    def parse_vnc_info(self) -> None:
        logOutPath = self.apptainer_instance_info.logOutPath
        with open(logOutPath, "r") as lfp:
            contents = lfp.read()
            if not contents:
                raise RuntimeError(f"Log file at {logOutPath} is empty")
            rfbports = re.findall(r"\s+-rfbport\s+(?P<rfbport>\d+)\b", contents)
            if not rfbports:
                raise RuntimeError(f"Could not find VNC port from log file at {logOutPath}")
            try:
                vnc_port = int(rfbports[-1])
            except (ValueError, IndexError, TypeError):
                raise RuntimeError(f"Could not parse VNC port from log file at {logOutPath}")

            self.vnc_port = vnc_port

            vnc_log_file_paths = re.findall(
                rf"(?m)Log file is\s*(?P<logfilepath>.*/"
                + rf"{self.apptainer_instance_info.instance_host}.*:{self.vnc_port}\.log)$",
                contents,
            )
            if not vnc_log_file_paths:
                raise RuntimeError(f"Could not find VNC log file from Apptainer log file at {logOutPath}")
            self.vnc_log_file_path = Path(vnc_log_file_paths[-1]).expanduser()
            if not self.vnc_log_file_path.is_file():
                logger.debug(f"Could not find vnc log file at {self.vnc_log_file_path}")
                self.vnc_pid_file_path = self.vnc_log_file_path.with_suffix(".pid")
            if not self.vnc_pid_file_path.is_file():
                logger.debug(f"Could not find vnc log file at {self.vnc_pid_file_path}")

    def vnc_pid_file_exists(self) -> bool:
        if not self.vnc_pid_file_path:
            return False
        return Path(self.vnc_pid_file_path).is_file()

    def is_alive(self) -> bool:
        if self.vnc_pid_file_exists():
            return check_remote_pid_exists_and_port_open(
                slurm_job_id=self.job_id, pid=self.apptainer_instance_info.pid, port=self.vnc_port
            )
        return False

    def instance_is_running(self) -> bool:
        return check_remote_pid_exists(slurm_job_id=self.job_id, pid=self.apptainer_instance_info.pid)

    def port_is_open(self) -> bool:
        if self.vnc_port:
            return check_remote_port_open(slurm_job_id=self.job_id, port=self.vnc_port)
        return False

    def get_openssh_connection_string(
        self,
        login_host: str,
        port_on_client: Optional[int] = None,
        debug_connection: Optional[bool] = False,
        apple: Optional[bool] = False,
        fork_ssh: Optional[bool] = True,
    ) -> str:
        port_on_node = self.vnc_port
        if not port_on_node:
            raise RuntimeError("Could not find VNC port")
        compute_node = self.apptainer_instance_info.instance_host
        if not compute_node:
            raise RuntimeError("Could not find compute node")
        port_on_client = port_on_client or port_on_node
        if not port_on_client:
            raise RuntimeError("Could not find port on client")
        if not self.is_alive():
            raise RuntimeError("Instance is not alive")

        debug_connection_str = "-v" if debug_connection else ""
        fork_ssh_str = "-f" if fork_ssh else ""
        s_base = (
            f"ssh {debug_connection_str} {fork_ssh_str} -o StrictHostKeyChecking=no "
            + f"-J {login_host} {compute_node} -L {port_on_client}:localhost:{port_on_node}"
        )

        apple_bundles = ["com.tigervnc.tigervnc", "com.realvnc.vncviewer"]
        apple_cmds = [f"open -b {bundle} --args localhost:{port_on_client} 2>/dev/null" for bundle in apple_bundles]
        apple_cmds += [
            "echo 'Cannot find an installed VNC viewer on macOS "
            + "&& echo Please install one from https://www.realvnc.com/en/connect/download/viewer/ "
            + "or https://tigervnc.org/' "
            + "&& echo 'Alternatively, try entering the address "
            + "localhost:{port_on_client} into your VNC application'"
        ]
        apple_cmds_pasted = " || ".join(apple_cmds)
        s = (
            f"{s_base} sleep 10; vncviewer localhost:{port_on_client}"
            if not apple
            else (f"{s_base} sleep 10; " + apple_cmds_pasted)
        )
        return s

    def stop(self) -> None:
        if not self.job_id:
            raise RuntimeError("Could not find job ID")
        logger.info(f"Cancelling job {self.job_id}")
        logger.info(f"Stopping Apptainer instance {self.apptainer_instance_info.name} on job {self.job_id}")
        apptainer_instance_stop(instance=self.apptainer_instance_info.name, slurm_job_id=self.job_id)
        logger.info(f"Stopping SLURM job {self.job_id}")
        cancel_job(self.job_id)
        logger.info("Job {self.job_id} cancelled")
        if Path(self.vnc_pid_file_path).expanduser().is_file():
            logger.info(f"Removing PID file {self.vnc_pid_file_path}")
            try:
                Path(self.vnc_pid_file_path).expanduser().unlink()
            except (PermissionError, FileNotFoundError, TypeError):
                logger.warning(f"Could not remove PID file {self.vnc_pid_file_path}")

    def __str__(self):
        dct = {
            "apptainer_instance_info": self.apptainer_instance_info.__dict__,
            "apptainer_instance_prefix": str(self.app_config.apptainer_instance_prefix),
            "vnc_port": self.vnc_port,
            "vnc_log_file_path": str(self.vnc_log_file_path),
            "vnc_pid_file_path": str(self.vnc_pid_file_path),
            "job_id": str(self.job_id),
        }
        s = pprint.pformat(dct, indent=2, width=120)
        return f"{self.__class__.__name__}:\n{s}"

    @staticmethod
    def load_instance_from_path(
        job_id: int,
        app_config: HyakVncConfig,
        path: Union[Path, str],
    ) -> Union["HyakVncSession", None]:
        """
        Loads a HyakVncSession from an ApptainerInstanceInfo file.
        :param job_id: SLURM job ID of the instance
        :param app_config: HyakVncConfig for the instance
        :param path: path to ApptainerInstanceInfo file
        :return: HyakVncSession
        :raises ValueError: if instance_name and path are both None
        :raises FileNotFoundError: if apptainer config dir does not exist
        """
        try:
            apptainer_instance_info = ApptainerInstanceInfo.from_json(Path(path).expanduser())
            hyakvnc_session = HyakVncSession(
                job_id=job_id, apptainer_instance_info=apptainer_instance_info, app_config=app_config
            )
            return hyakvnc_session
        except (ValueError, FileNotFoundError) as e:
            logger.warning(f"Could not load instance from {path} due to {e}")
        return None

    @staticmethod
    def find_running_sessions(app_config: HyakVncConfig, job_id: Optional[int] = None) -> List["HyakVncSession"]:
        outs = list()
        if job_id:
            active_jobs = get_job_infos(jobs=[job_id])
        else:
            active_jobs = get_job_infos()

        for job_info in active_jobs:
            if job_info.job_name.startswith(app_config.job_prefix):
                logger.debug(f"Found job {job_info.job_id} with name {job_info.job_name}")
                running_instances = apptainer_instance_list(slurm_job_id=job_info.job_id)
                if not running_instances:
                    logger.debug(f"Could not find any running apptainer instances on job {job_info.job_id}")
                    return outs

                for instance in running_instances:
                    if instance.name.startswith(app_config.apptainer_instance_prefix):
                        logger.debug(f"Found apptainer instance {instance.name} with pid {instance.pid}")
                        sesh = HyakVncSession(job_info.job_id, instance, app_config)
                        sesh.parse_vnc_info()
                        if sesh.is_alive():
                            logger.debug(f"Session {sesh.apptainer_instance_info.name} is alive")
                            outs.append(sesh)
                        else:
                            logger.debug(f"Session {sesh.apptainer_instance_info.name} not alive")
        return outs
