import os
import pprint
import re
from dataclasses import asdict
from pathlib import Path
from typing import Optional, Union

from .apptainer import ApptainerInstanceInfo
from .slurmutil import get_job, cancel_job
from .util import check_remote_pid_exists_and_port_open, check_remote_pid_exists, check_remote_port_open
from . import logger


class HyakVncInstance:
    def __init__(self, apptainer_instance_info: ApptainerInstanceInfo, instance_prefix: str = None,
                 apptainer_config_dir: Optional[Union[str, Path]] = None):
        self.apptainer_instance_info = apptainer_instance_info
        apptainer_config_dir = apptainer_config_dir or Path("~/.apptainer")
        self.apptainer_config_dir = Path(apptainer_config_dir).expanduser()
        self.vnc_port = None
        self.vnc_log_file_path = None
        self.vnc_pid_file_path = None
        self.instance_prefix = instance_prefix
        self.job_id = None

        app_dir = self.apptainer_config_dir / 'instances' / 'app'
        assert app_dir.is_dir(), f"Could not find apptainer app dir at {app_dir}"

        self.compute_node = Path(self.apptainer_instance_info.instance_path).relative_to(app_dir).parts[0]
        try:
            name_meta = re.match(rf'(?P<prefix>{instance_prefix})-(?P<jobid>\d+)-(?P<appinstance>.*)',
                                 self.apptainer_instance_info.instance_name).groupdict()
        except AttributeError:
            raise ValueError(f"Could not parse instance name from {self.apptainer_instance_info.instance_name}")

        try:
            self.job_id = int(name_meta['jobid'])
        except (ValueError, IndexError, TypeError):
            raise ValueError(f"Could not parse jobid from {self.apptainer_instance_info.instance_name}")

        logOutPath = self.apptainer_instance_info.logOutPath
        if not logOutPath:
            logger.warning("No logOutPath for apptainer instance")
            return
        logOutPath = Path(logOutPath).expanduser()
        if not logOutPath.is_file():
            logger.warning(f"Could not find log file at {logOutPath}")
            return

        with open(logOutPath, 'r') as lf:
            logOutFile_contents = lf.read()
            rfbports = re.findall(r'\s+-rfbport\s+(?P<rfbport>\d+)\b', logOutFile_contents)
            try:
                vnc_port = int(rfbports[-1])
            except (ValueError, IndexError, TypeError):
                logger.warning(f"Could not parse VNC port from log file at {logOutPath}")
                return
            self.vnc_port = vnc_port

            vnc_log_file_paths = re.findall(
                rf'(?m)Log file is\s*(?P<logfilepath>.*/{self.compute_node}.*:{self.vnc_port}\.log)$',
                logOutFile_contents)

            try:
                vnc_log_file_path = Path(vnc_log_file_paths[-1]).expanduser()
            except (ValueError, IndexError, TypeError):
                logger.warning(f"Could not parse VNC log file path from log file at {logOutPath}")
                return
            if not vnc_log_file_path.is_file():
                logger.debug(f"Could not find vnc log file at {vnc_log_file_path}")
                return
            self.vnc_log_file_path = vnc_log_file_path
            vnc_pid_file_path = self.vnc_log_file_path.parent / (str(self.vnc_log_file_path.stem) + '.pid')
            if not vnc_pid_file_path.is_file():
                logger.debug(f"Could not find vnc PID file at {vnc_pid_file_path}")
                return
            self.vnc_pid_file_path = vnc_pid_file_path
        return

    def vnc_pid_file_exists(self):
        return self.vnc_pid_file_path.is_file()

    def is_alive(self):
        return self.vnc_pid_file_exists() and check_remote_pid_exists_and_port_open(self.compute_node,
                                                                                    self.apptainer_instance_info.pid,
                                                                                    self.vnc_port)

    def instance_is_running(self):
        return check_remote_pid_exists(self.compute_node, self.apptainer_instance_info.pid)

    def port_is_open(self):
        return check_remote_port_open(self.compute_node, self.vnc_port)

    def get_openssh_connection_string(self, login_host: str, port_on_client: Optional[int] = None,
                                      debug_connection: Optional[bool] = False,
                                      apple: Optional[bool] = False, fork_ssh: Optional[bool] = True) -> str:
        port_on_node = self.vnc_port
        assert port_on_node is not None, "Could not find VNC port"
        compute_node = self.compute_node
        assert compute_node is not None, "Could not find compute node"
        port_on_client = port_on_client or port_on_node
        assert port_on_client is not None, "Could not determine a port to open on the client"
        assert self.is_alive(), "Instance is not alive"

        debug_connection_str = "-v" if debug_connection else ""
        fork_ssh_str = "-f" if fork_ssh else ""
        s_base = f"ssh {debug_connection_str} {fork_ssh_str} -o StrictHostKeyChecking=no -J {login_host} {compute_node} -L {port_on_client}:localhost:{port_on_node}"

        apple_bundles = ["com.tigervnc.tigervnc", "com.realvnc.vncviewer"]
        apple_cmds = [f"open -b {bundle} --args localhost:{port_on_client} 2>/dev/null" for bundle in apple_bundles]
        apple_cmds += ["echo 'Cannot find an installed VNC viewer on macOS && echo Please install one from https://www.realvnc.com/en/connect/download/viewer/ or https://tigervnc.org/' && echo 'Alternatively, try entering the address localhost:{port_on_client} into your VNC application'"]
        apple_cmds_pasted = " || ".join(apple_cmds)
        s = f"{s_base} sleep 10; vncviewer localhost:{port_on_client}" if not apple else (f"{s_base} sleep 10; " + apple_cmds_pasted)
        return s

    def cancel(self):
        assert self.job_id is not None, "Could not find job ID"
        logger.info(f"Cancelling job {self.job_id}")
        cancel_job(self.job_id)
        logger.info("Job {self.job_id} cancelled")
        if Path(self.vnc_pid_file_path).expanduser().is_file():
            logger.info(f"Removing PID file {self.vnc_pid_file_path}")
            Path(self.vnc_pid_file_path).expanduser().unlink()

    def __repr__(self):
        return f"HyakVncInstance({self.apptainer_instance_info}, instance_prefix={self.instance_prefix}, apptainer_config_dir={self.apptainer_config_dir})"

    def __str__(self):
        dct = {
            "apptainer_instance_info":  asdict(self.apptainer_instance_info),
            "instance_prefix": str(self.instance_prefix),
            "apptainer_config_dir": str(self.apptainer_config_dir),
            "vnc_port": self.vnc_port,
            "vnc_log_file_path": str(self.vnc_log_file_path),
            "vnc_pid_file_path": str(self.vnc_pid_file_path),
            "job_id": str(self.job_id),
            "compute_node": str(self.compute_node)
        }
        s = pprint.pformat(dct, indent=2, width=120)
        return f"{self.__class__.__name__}:\n{s}"

    @staticmethod
    def load_instance(instance_prefix: str, instance_name: Optional[str] = None,
                      path: Optional[Union[str, Path]] = None, read_apptainer_config: Optional[bool] = False,
                      apptainer_config_dir: Optional[Union[str, Path]] = None) -> Union["HyakVncInstance", None]:
        assert ((instance_name is not None) ^ (path is not None)), "Must specify either instance name or path"
        if instance_name:
            apptainer_config_dir = apptainer_config_dir or Path("~/.apptainer").expanduser()
            path = Path(
                apptainer_config_dir).expanduser() / 'instances' / 'app' / instance_name / f"{instance_name}.json"
        else:
            if not apptainer_config_dir:
                pth = str(Path(path))
                m = re.match(r'^.+/instances/app/', pth)
                if not m:
                    raise ValueError(f"Could not determine apptainer config dir from path {path}")
                apptainer_config_dir = Path(m.group(0)).expanduser().parent.parent
            apptainer_config_dir = Path(apptainer_config_dir).expanduser()

        assert apptainer_config_dir.is_dir(), f"Could not find apptainer config dir at {apptainer_config_dir}"
        app_dir = Path(apptainer_config_dir).expanduser() / 'instances' / 'app'
        assert app_dir.is_dir(), f"Could not find apptainer app dir at {app_dir}"
        path = Path(path).expanduser()

        assert path.is_file(), f"Could not find apptainer instance file at {path}"

        apptainer_instance_info = ApptainerInstanceInfo.from_json(path, read_config=read_apptainer_config)
        hyakvnc_instance = HyakVncInstance(apptainer_instance_info=apptainer_instance_info,
                                           instance_prefix=instance_prefix, apptainer_config_dir=apptainer_config_dir)
        return hyakvnc_instance

    @staticmethod
    def find_running_instances(instance_prefix: str, apptainer_config_dir: Optional[Union[str, Path]] = None,
                               user: str = os.getlogin()) -> list["HyakVncInstance"]:
        apptainer_config_dir = apptainer_config_dir or Path("~/.apptainer").expanduser()
        app_dir = Path(apptainer_config_dir).expanduser() / 'instances' / 'app'
        assert app_dir.is_dir(), f"Could not find apptainer app dir at {app_dir}"

        active_jobs = get_job()
        outs = []
        active_compute_nodes = set([node for nodes in [job.node_list for job in active_jobs] for node in nodes])
        compute_directories = [(Path(app_dir) / node / user) for node in active_compute_nodes]
        all_instance_files = set(
            [f for fs in [p.rglob(instance_prefix + '*.json') for p in compute_directories] for f in fs])
        vnc_instance_files = set([p for p in all_instance_files if re.match(rf"^{instance_prefix}-\d+", p.name)])
        for p in vnc_instance_files:
            logger.debug(f"Found instance file {p}")
            instance_info = ApptainerInstanceInfo.from_json(p)
            instance = HyakVncInstance(instance_info, instance_prefix=instance_prefix,
                                       apptainer_config_dir=apptainer_config_dir)
            if instance.is_alive():
                logger.debug(f"Found instance {instance.apptainer_instance_info.instance_name} and it is alive")
                outs.append(instance)
            else:
                logger.debug(f"Found instance {instance.apptainer_instance_info.instance_name} but it is not alive")
        return outs
