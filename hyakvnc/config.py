import json
import logging
import os
from pathlib import Path
from typing import Optional, Iterable, Union, Dict

from . import logger
from .slurmutil import get_default_cluster, get_default_account, get_default_partition


def get_first_env(env_vars: Iterable[str], default: Optional[str] = None, allow_blank: bool = False) -> str:
    """
    Gets the first environment variable that is set, or the default value if none are set.
    :param env_vars: list of environment variables to check
    :param default: default value to return if no environment variables are set
    :param allow_blank: whether to allow blank environment variables
    :return: the first environment variable that is set, or the default value if none are set
    """
    logger.debug(rf"Checking environment variables {env_vars}")
    for x in env_vars:
        res = os.environ.get(x, None)
        if res is not None:
            if allow_blank or res:
                logger.debug(rf"Using environment variable {x}={res}")
                return res
    logger.debug(rf"Using default value {default}")
    return default


class HyakVncConfig:
    """
    Configuration for hyakvnc.
    """

    def __init__(
        self,
        job_prefix: str = "hyakvnc",  # prefix for job names
        log_path: str = "~/.hyakvnc.log",  # path to log file
        apptainer_bin: str = "apptainer",  # path to apptainer binary
        apptainer_config_dir: str = "~/.apptainer",  # directory where apptainer config files are stored
        apptainer_instance_prefix: str = "hyakvnc",  # prefix for apptainer instance names
        apptainer_use_writable_tmpfs: bool = True,  # whether to mount a writable tmpfs for apptainer instances
        apptainer_cleanenv: bool = True,  # whether to use clean environment for apptainer instances
        apptainer_set_bind_paths: str = None,  # comma-separated list of paths to bind mount for apptainer instances
        apptainer_env_vars: Dict[str, str] = None,  # environment variables to set for apptainer instances
        sbatch_post_timeout: float = 120.0,  # timeout for waiting for sbatch to return
        sbatch_post_poll_interval: float = 1.0,  # poll interval for waiting for sbatch to return
        sbatch_output_path: Optional[str] = None,  # path to write sbatch output to
        ssh_host: Optional[
            str
        ] = "klone.hyak.uw.edu",  # intermediate host address between local machine and compute node
        account: Optional[str] = None,  # account to use for sbatch jobs | -A, --account, SBATCH_ACCOUNT
        partition: Optional[str] = None,  # partition to use for sbatch jobs | -p, --partition, SBATCH_PARTITION
        cluster: Optional[str] = "klone",  # cluster to use for sbatch jobs |  --clusters, SBATCH_CLUSTERS
        gpus: Optional[str] = None,  # number of gpus to use for sbatch jobs | -G, --gpus, SBATCH_GPUS
        timelimit: Optional[str] = None,  # time limit for sbatch jobs | --time, SBATCH_TIMELIMIT
        mem: Optional[str] = "8G",  # memory limit for sbatch jobs | --mem, SBATCH_MEM
        cpus: Optional[
            int
        ] = 4,  # number of cpus to use for sbatch jobs | -c, --cpus-per-task (not settable by env var)
    ):
        self.log_path = str(Path(log_path).expanduser())
        log_handler_file = logging.FileHandler(self.log_path, mode="a")
        log_handler_file.setFormatter(
            logging.Formatter("%(levelname)s: %(asctime)s %(message)s", datefmt="%m/%d/%Y %I:%M:%S %p")
        )
        log_handler_file.setLevel(logging.DEBUG)
        logger.addHandler(log_handler_file)
        logger.debug("Loading config")
        self.job_prefix = job_prefix
        self.apptainer_bin = apptainer_bin

        self.cluster = cluster
        if self.cluster:
            logger.debug(rf"Using cluster {self.cluster}")
        if not self.cluster:
            self.cluster = cluster or get_first_env(
                ["HYAKVNC_SLURM_CLUSTER", "SBATCH_CLUSTER"], default=get_default_cluster()
            )
        self.account = account or get_first_env(
            ["HYAKVNC_SLURM_ACCOUNT", "SBATCH_ACCOUNT"], get_default_account(cluster=self.cluster)
        )
        self.partition = partition or get_first_env(
            ["HYAKVNC_SLURM_PARTITION", "SBATCH_PARTITION"],
            get_default_partition(cluster=self.cluster, account=self.account),
        )
        self.gpus = gpus or get_first_env(["HYAKVNC_SLURM_GPUS", "SBATCH_GPUS"], None)
        self.timelimit = timelimit or get_first_env(["HYAKVNC_SLURM_TIMELIMIT", "SBATCH_TIMELIMIT"], None)
        self.mem = mem or get_first_env(["HYAKVNC_SLURM_MEM", "SBATCH_MEM"], None)
        self.cpus = int(cpus or get_first_env(["HYAKVNC_SLURM_CPUS", "SBATCH_CPUS_PER_TASK"]))
        self.sbatch_output_path = sbatch_output_path or get_first_env(
            ["HYAKVNC_SBATCH_OUTPUT_PATH", "SBATCH_OUTPUT"], "/dev/stdout"
        )
        self.apptainer_config_dir = apptainer_config_dir
        self.apptainer_instance_prefix = apptainer_instance_prefix
        self.apptainer_use_writable_tmpfs = apptainer_use_writable_tmpfs
        self.apptainer_cleanenv = apptainer_cleanenv
        self.apptainer_set_bind_paths = apptainer_set_bind_paths
        self.sbatch_post_timeout = sbatch_post_timeout
        self.sbatch_post_poll_interval = sbatch_post_poll_interval
        self.ssh_host = ssh_host

        self.apptainer_env_vars = apptainer_env_vars or dict()
        all_apptainer_env_vars = {
            x: os.environ.get(x, "")
            for x in os.environ.keys()
            if x.startswith("APPTAINER_")
            or x.startswith("APPTAINERENV_")
            or x.startswith("SINGULARITY_")
            or x.startswith("SINGULARITYENV_")
        }
        self.apptainer_env_vars.update(all_apptainer_env_vars)

        if self.apptainer_use_writable_tmpfs:
            self.apptainer_env_vars["APPTAINER_WRITABLE_TMPFS"] = "1" if self.apptainer_use_writable_tmpfs else "0"

        if self.apptainer_cleanenv:
            self.apptainer_env_vars["APPTAINER_CLEANENV"] = "1" if self.apptainer_cleanenv else "0"

            if self.apptainer_set_bind_paths:
                self.apptainer_env_vars["APPTAINER_BINDPATH"] = self.apptainer_set_bind_paths

    def to_json(self) -> str:
        """
        Converts this configuration to a JSON string.
        :return: JSON string representation of this configuration
        """
        return json.dumps({k: v for k, v in self.__dict__.items() if v is not None})

    @staticmethod
    def from_json(path: Union[str, Path]) -> "HyakVncConfig":
        """
        Loads a HyakVncConfig from a JSON file.
        :param path: path to JSON file
        :return: HyakVncConfig loaded from JSON file
        """
        if not Path(path).is_file():
            raise RuntimeError(f"Invalid path to configuration file: {path}")

        try:
            with open(path, "r") as f:
                contents = json.load(f)
                return HyakVncConfig(**contents)
        except (json.JSONDecodeError, ValueError, TypeError) as e:
            raise RuntimeError(f"Invalid JSON in configuration file: {path}") from e

    def __str(self):
        return self.to_json()

    def __repr__(self):
        return self.to_json()

    @staticmethod
    def load_app_config(path: Optional[Union[str, Path]] = None) -> "HyakVncConfig":
        """
        Loads a HyakVncConfig from a path to a JSON file. If the path is not specified, the default path is used.
        The default path can be modified with the HYAKVNC_CONFIG_PATH environment variable; otherwise,
        it  is "~/.config/hyakvnc/config.json". If it cannot load either file, it returns a default configuration.

        :param path: path to JSON file
        :return: HyakVncConfig loaded from JSON file
        """
        paths = []
        if path:
            path = Path(path).expanduser()
            paths += [path]
        default_path = Path(os.environ.setdefault("HYAKVNC_CONFIG_PATH", "~/.config/hyakvnc/config.json")).expanduser()
        paths += [default_path]
        for p in paths:
            if p.is_file():
                try:
                    return HyakVncConfig.from_json(path=p)
                except Exception as e:
                    logger.debug(f"Could not load config from {p}: {e}")
        return HyakVncConfig()
