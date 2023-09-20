import json
import logging
import os
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Optional, Iterable, Union

from .slurmutil import get_default_cluster, get_default_account, get_default_partition

def get_first_env(env_vars: Iterable[str], default: Optional[str] = None, allow_blank: bool = True) -> str:
    """
    Gets the first environment variable that is set, or the default value if none are set.
    :param env_vars: list of environment variables to check
    :param default: default value to return if no environment variables are set
    :param allow_blank: whether to allow blank environment variables
    :return: the first environment variable that is set, or the default value if none are set
    """

    no_match = [None] if allow_blank else ["None", ""]
    for x in env_vars:
        if (res := os.environ.get(x)) not in no_match:
            logging.debug(rf"Using environment variable {x}={res}")
            return res
    logging.debug(rf"Using default value {default}")
    return default


@dataclass
class HyakVncConfig:
    """
    Configuration for hyakvnc.
    """
    # script attributes
    job_prefix: str = "hyakvnc-"  # prefix for job names
    # apptainer config
    apptainer_bin: str = "apptainer"  # path to apptainer binary
    apptainer_config_dir: str = "~/.apptainer"  # directory where apptainer config files are stored
    apptainer_instance_prefix: str = "hyakvnc-"  # prefix for apptainer instance names
    apptainer_use_writable_tmpfs: Optional[bool] = None  # whether to mount a writable tmpfs for apptainer instances
    apptainer_cleanenv: Optional[bool] = None  # whether to use clean environment for apptainer instances
    apptainer_set_bind_paths: Optional[
        str] = None  # comma-separated list of paths to bind mount for apptainer instances
    apptainer_env_vars: Optional[dict[str]] = None  # environment variables to set for apptainer instances
    sbatch_post_timeout: float = 120.0  # timeout for waiting for sbatch to return
    sbatch_post_poll_interval: float = 1.0  # poll interval for waiting for sbatch to return

    # ssh config
    ssh_host = "klone.hyak.uw.edu"  # intermediate host address between local machine and compute node

    # slurm attributes
    account: Optional[str] = None  # account to use for sbatch jobs | -A, --account, SBATCH_ACCOUNT
    partition: Optional[str] = None  # partition to use for sbatch jobs | -p, --partition, SBATCH_PARTITION
    cluster: Optional[str] = None  # cluster to use for sbatch jobs |  --clusters, SBATCH_CLUSTERS
    gpus: Optional[str] = None  # number of gpus to use for sbatch jobs | -G, --gpus, SBATCH_GPUS
    timelimit: Optional[str] = None  # time limit for sbatch jobs | --time, SBATCH_TIMELIMIT
    mem: Optional[str] = None  # memory limit for sbatch jobs | --mem, SBATCH_MEM
    cpus: Optional[int] = None  # number of cpus to use for sbatch jobs | -c, --cpus-per-task (not settable by env var)

    def __post_init__(self) -> None:
        """
        Post-initialization hook for HyakVncConfig. Sets default values for unset attributes.
        :return: None
        """
        self.cluster = self.cluster or get_first_env(["HYAKVNC_SLURM_CLUSTER", "SBATCH_CLUSTER"],
                                                     get_default_cluster(), allow_blank=False)
        self.account = self.account or get_first_env(["HYAKVNC_SLURM_ACCOUNT", "SBATCH_ACCOUNT"],
                                                     get_default_account(cluster=self.cluster),
                                                     allow_blank=False)
        self.partition = self.partition or get_first_env(["HYAKVNC_SLURM_PARTITION", "SBATCH_PARTITION"],
                                                         get_default_partition(cluster=self.cluster,
                                                                                         account=self.account),
                                                         allow_blank=False)
        self.gpus = self.gpus or get_first_env(["HYAKVNC_SLURM_GPUS", "SBATCH_GPUS"], None)
        self.timelimit = self.timelimit or get_first_env(["HYAKVNC_SLURM_TIMELIMIT", "SBATCH_TIMELIMIT"], None)
        self.mem = self.mem or get_first_env(["HYAKVNC_SLURM_MEM", "SBATCH_MEM"], None)
        self.cpus = self.cpus or get_first_env(["HYAKVNC_SLURM_CPUS", "SBATCH_CPUS_PER_TASK"], None)

        all_apptainer_env_vars = {x: os.environ.get(x, "") for x in os.environ.keys() if
                                  x.startswith("APPTAINER_") or x.startswith("APPTAINERENV_") or x.startswith(
                                      "SINGULARITY_") or x.startswith("SINGULARITYENV_")}
        self.apptainer_env_vars = self.apptainer_env_vars or {}
        self.apptainer_env_vars = self.apptainer_env_vars.update(all_apptainer_env_vars)

        if self.apptainer_use_writable_tmpfs is not None:
            self.apptainer_env_vars["APPTAINER_WRITABLE_TMPFS"] = "1" if self.apptainer_use_writable_tmpfs else "0"

        if self.apptainer_cleanenv is not None:
            self.apptainer_env_vars["APPTAINER_CLEANENV"] = "1" if self.apptainer_cleanenv else "0"

            if self.apptainer_set_bind_paths is not None:
                self.apptainer_env_vars["APPTAINER_BINDPATH"] = self.apptainer_set_bind_paths

    def to_json(self) -> str:
        """
        Converts this configuration to a JSON string.
        :return: JSON string representation of this configuration
        """
        return json.dumps({k: v for k, v in asdict(self).items() if v is not None})

    @staticmethod
    def from_json(path: Union[str, Path]) -> "HyakVncConfig":
        """
        Loads a HyakVncConfig from a JSON file.
        :param path: path to JSON file
        :return: HyakVncConfig loaded from JSON file
        """
        if not Path(path).is_file():
            raise ValueError(f"Invalid path to configuration file: {path}")

        with open(path, "r") as f:
            contents = json.load(f)
            return HyakVncConfig(**contents)

    @staticmethod
    def from_jsons(s: str) -> "HyakVncConfig":
        """
        Loads a HyakVncConfig from a JSON string.
        :param s: JSON string
        :return: HyakVncConfig loaded from JSON string
        """
        return HyakVncConfig(**json.loads(s))
