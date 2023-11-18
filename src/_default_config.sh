#!/usr/bin/env bash

# :%% General preferences
HYAKVNC_DIR="${HYAKVNC_DIR:-${HOME}/.hyakvnc}"                                                           # %% Local directory to store application. default:$HOME/.hyakvnc
HYAKVNC_CONFIG_FILE="${HYAKVNC_DIR}/hyakvnc-config.sh"                                                   # %% Configuration file to use. default: $HYAKVNC_DIR/hyakvnc-config.sh
HYAKVNC_REPO_DIR="${HYAKVNC_REPO_DIR:-${HYAKVNC_DIR}/hyakvnc}"                                           # %% Local directory to store git repository. default: $HYAKVNC_DIR/hyakvnc
HYAKVNC_CHECK_UPDATE_FREQUENCY="${HYAKVNC_CHECK_UPDATE_FREQUENCY:-0}"                                    # %% How often to check for updates in `[d]`ays or `[m]`inutes; use `0` for every time, `-1` to disable`, 1d` for daily, `10m` for every 10 minutes, etc. default: 0
HYAKVNC_LOG_FILE="${HYAKVNC_LOG_FILE:-${HYAKVNC_DIR}/hyakvnc.log}"                                       # %% Log file to use. default: $HYAKVNC_DIR/hyakvnc.log
HYAKVNC_LOG_LEVEL="${HYAKVNC_LOG_LEVEL:-INFO}"                                                           # %% Log level to use for interactive output. default: INFO
HYAKVNC_LOG_FILE_LEVEL="${HYAKVNC_LOG_FILE_LEVEL:-DEBUG}"                                                # %% Log level to use for log file output. default: DEBUG
HYAKVNC_SSH_HOST="${HYAKVNC_SSH_HOST:-klone.hyak.uw.edu}"                                                # %% Default SSH host to use for connection strings. default: klone.hyak.uw.edu
HYAKVNC_DEFAULT_TIMEOUT="${HYAKVNC_DEFAULT_TIMEOUT:-30}"                                                 # %% Seconds to wait for most commands to complete before timing out. default: 30
HYAKVNC_JOB_PREFIX="${HYAKVNC_JOB_PREFIX:-hyakvnc-}"                                                     # %% Prefix to use for hyakvnc SLURM job names. default: hyakvnc-
HYAKVNC_JOB_SUBMIT_TIMEOUT="${HYAKVNC_JOB_SUBMIT_TIMEOUT:-120}"                                          # %% Seconds after submitting job to wait for the job to start before timing out. default: 120

# :%% VNC preferences
HYAKVNC_VNC_PASSWORD="${HYAKVNC_VNC_PASSWORD:-password}"                                                 # %% Password to use for new VNC sessions. default: password
HYAKVNC_VNC_DISPLAY="${HYAKVNC_VNC_DISPLAY:-:10}"                                                        # %% VNC display to use. default: :10

# :%% Apptainer preferences
HYAKVNC_APPTAINER_CONTAINERS_DIR="${HYAKVNC_APPTAINER_CONTAINERS_DIR:-}"                                 # %% Directory to look for apptainer containers.
HYAKVNC_APPTAINER_GHCR_ORAS_PRELOAD="${HYAKVNC_APPTAINER_GHCR_ORAS_PRELOAD:-1}"                          # %% Whether to preload SIF files from the ORAS GitHub Container Registry. default: 1
HYAKVNC_APPTAINER_BIN="${HYAKVNC_APPTAINER_BIN:-apptainer}"                                              # %% Name of apptainer binary. default: apptainer
HYAKVNC_APPTAINER_APP_VNCSERVER="${HYAKVNC_APPTAINER_APP_VNCSERVER:-vncserver}"                          # %% Name of app in the container that starts the VNC session. default: vncserver

# :%% Apptainer runtime preferences
HYAKVNC_APPTAINER_WRITABLE_TMPFS="${HYAKVNC_APPTAINER_WRITABLE_TMPFS:-${APPTAINER_WRITABLE_TMPFS:-1}}"   # %% Whether to use a writable tmpfs for the container. default: 1
HYAKVNC_APPTAINER_CLEANENV="${HYAKVNC_APPTAINER_CLEANENV:-${APPTAINER_CLEANENV:-1}}"                     # %% Whether to use a clean environment for the container. default: 1
HYAKVNC_APPTAINER_ADD_BINDPATHS="${HYAKVNC_APPTAINER_ADD_BINDPATHS:-}"                                   # %% Bind paths to add to the container.
HYAKVNC_APPTAINER_ADD_ENVVARS="${HYAKVNC_APPTAINER_ADD_ENVVARS:-}"                                       # %% Environment variables to add to before invoking apptainer.
HYAKVNC_APPTAINER_ADD_ARGS="${HYAKVNC_APPTAINER_ADD_ARGS:-}"                                             # %% Additional arguments to give apptainer.

# :%% Slurm preferences
HYAKVNC_SLURM_OUTPUT_DIR="${HYAKVNC_SLURM_OUTPUT_DIR:-${HYAKVNC_DIR}/slurm-output}"                      # %% Directory to store SLURM output files. default: $HYAKVNC_DIR/slurm-output
HYAKVNC_SLURM_OUTPUT="${HYAKVNC_SLURM_OUTPUT:-${SBATCH_OUTPUT:-${HYAKVNC_SLURM_OUTPUT_DIR}/job-%j.out}}" # %% Where to send SLURM job output. default: HYAKVNC_SLURM_OUTPUT_DIR/job-%j.out
HYAKVNC_SLURM_JOB_NAME="${HYAKVNC_SLURM_JOB_NAME:-${SBATCH_JOB_NAME:-}}"                                 # %% What to name the launched SLURM job.
HYAKVNC_SLURM_ACCOUNT="${HYAKVNC_SLURM_ACCOUNT:-${SBATCH_ACCOUNT:-}}"                                    # %% Slurm account to use.
HYAKVNC_SLURM_PARTITION="${HYAKVNC_SLURM_PARTITION:-${SBATCH_PARTITION:-}}"                              # %% Slurm partition to use.
HYAKVNC_SLURM_CLUSTER="${HYAKVNC_SLURM_CLUSTER:-${SBATCH_CLUSTERS:-}}"                                   # %% Slurm cluster to use.
HYAKVNC_SLURM_GPUS="${HYAKVNC_SLURM_GPUS:-${SBATCH_GPUS:-}}"                                             # %% Number of GPUs to request.
HYAKVNC_SLURM_MEM="${HYAKVNC_SLURM_MEM:-${SBATCH_MEM:-4G}}"                                              # %% Amount of memory to request, in [M]egabytes or [G]igabytes.
HYAKVNC_SLURM_CPUS="${HYAKVNC_SLURM_CPUS:-4}"                                                            # %% Number of CPUs to request.
HYAKVNC_SLURM_TIMELIMIT="${HYAKVNC_SLURM_TIMELIMIT:-${SBATCH_TIMELIMIT:-12:00:00}}"                      # %% Time limit for SLURM job.
