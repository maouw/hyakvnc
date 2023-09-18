import os
from pathlib import Path
from dataclasses import dataclass
from .version import VERSION
from slurmutil import get_slurm_cluster,get_slurm_partitions,get_slurm_default_account,get_slurm_job_details

# Base VNC port cannot be changed due to vncserver not having a stable argument
# interface:
BASE_VNC_PORT = os.environ.setdefault("HYAKVNC_BASE_VNC_PORT", "5900")

# List of Klone login node hostnames
LOGIN_NODE_LIST = os.environ.get("HYAKVNC_LOGIN_NODES", "klone-login01,klone1.hyak.uw.edu,klone2.hyak.uw.edu").split(",")

# Name of Apptainer binary (formerly Singularity)
APPTAINER_BIN = os.environ.setdefault("HYAKVNC_APPTAINER_BIN", "apptainer")

# Checked to see if klone is authorized for intracluster access
AUTH_KEYS_FILEPATH = Path(os.environ.setdefault("HYAKVNC_AUTH_KEYS_FILEPATH", "~/.ssh/authorized_keys")).expanduser()

# Apptainer bindpaths can be overwritten if $APPTAINER_BINDPATH is defined.
# Bindpaths are used to mount storage paths to containerized environment.
APPTAINER_BINDPATH = os.environ.setdefault("APPTAINER_BINDPATH",
                                           os.environ.get("HYAKVNC_APPTAINER_BINDPATH",
                                                          os.environ.get("SINGULARITY_BINDPATH",
                                                                         "/tmp,$HOME,$PWD,/gscratch,/opt,/:/hyak_root,/sw,/mmfs1")))

APPTAINER_CONFIGDIR = Path(os.getenv("APPTAINER_CONFIGDIR", "~/.apptainer")).expanduser()
APPTAINER_INSTANCES_DIR = APPTAINER_CONFIGDIR / "instances"

# # SLURM UTILS

# Slurm configuration variables:
SLURM_CLUSTER = os.getenv("HYAKVNC_SLURM_CLUSTER", os.getenv("SBATCH_CLUSTERS", get_slurm_cluster()).split(",")[0])
SBATCH_CLUSTERS = os.environ.setdefault("SBATCH_CLUSTERS", SLURM_CLUSTER)
SBATCH_ACCOUNT = os.environ.get("HYAKVNC_SLURM_ACCOUNT", os.environ.setdefault("SBATCH_ACCOUNT", get_slurm_default_account(cluster=SLURM_CLUSTER)))

if any(SBATCH_PARTITION := x for x in get_slurm_partitions(account=SBATCH_ACCOUNT, cluster=SBATCH_CLUSTERS)):
    os.environ.setdefault("SBATCH_PARTITION", SBATCH_PARTITION)

SBATCH_GPUS = os.environ.setdefault("SBATCH_GPUS", "0")
SBATCH_TIMELIMIT = os.environ.setdefault("SBATCH_TIMELIMIT", "1:00:00")
