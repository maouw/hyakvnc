#! /usr/bin/env bash

HYAKVNC_VERSION="0.3.0"
if [ -n "${XDEBUG:-}" ]; then
	set -x
fi

# hyakvnc - A script to launch VNC sessions on Hyak

# = Preferences and settings:
# == App preferences:
HYAKVNC_LOG_PATH="${HYAKVNC_LOG_PATH:-$HOME/.hyakvnc.log}"
HYAKVNC_LOG_LEVEL="${HYAKVNC_LOG_LEVEL:-1}"
HYAKVNC_DIR="${HYAKVNC_DIR:-$HOME/.hyakvnc}"
HYAKVNC_CONFIG_DIR="${HYAKVNC_CONFIG_DIR:-$HOME/.config/hyakvnc}"
HYAKVNC_SSH_HOST="${HYAKVNC_SSH_HOST:-klone.hyak.uw.edu}"
HYAKVNC_VNC_PASSWORD="${HYAKVNC_VNC_PASSWORD:-password}"
HYAKVNC_STANDARD_TIMEOUT="${HYAKVNC_STANDARD_TIMEOUT:-30}" # How long to wait for a command to complete before timing out

# === macOS bundle identifiers for VNC viewer executables:
HYAKVNC_MACOS_VNC_VIEWER_BUNDLEIDS="${HYAKVNC_MACOS_VNC_VIEWER_BUNDLEIDS:-com.turbovnc.vncviewer.VncViewer com.realvnc.vncviewer com.tigervnc.vncviewer}"

# == Apptainer preferences:
HYAKVNC_CONTAINER="${HYAKVNC_CONTAINER:-}"                                                             # Path to container image
HYAKVNC_APPTAINER_BIN="${HYAKVNC_APPTAINER_BIN:-apptainer}"                                            # Name of apptainer binary
HYAKVNC_APPTAINER_CONFIG_DIR="${HYAKVNC_APPTAINER_CONFIG_DIR:-$HOME/.apptainer}"                       # Path to apptainer config directory
HYAKVNC_APPTAINER_INSTANCE_PREFIX="${HYAKVNC_APPTAINER_INSTANCE_PREFIX:-hyakvnc-}"                     # Prefix for apptainer instance names
HYAKVNC_APPTAINER_WRITABLE_TMPFS="${HYAKVNC_APPTAINER_WRITABLE_TMPFS:-${APPTAINER_WRITABLE_TMPFS:-1}}" # Whether to use a writable tmpfs for the container
HYAKVNC_APPTAINER_CLEANENV="${HYAKVNC_APPTAINER_CLEANENV:-${APPTAINER_CLEANENV:-1}}"                   # Whether to use a clean environment for the container
HYAKVNC_SET_APPTAINER_BIND_PATHS="${HYAKVNC_SET_APPTAINER_BIND_PATHS:-}"                               # Bind paths to set for the container
HYAKVNC_SET_APPTAINER_ARGS="${HYAKVNC_SET_APPTAINER_ARGS:-}"                                           # Environment variables to set for the container
HYAKVNC_APPTAINER_VNC_APP_NAME="${HYAKVNC_APPTAINER_VNC_APP_NAME:-vncserver}"                          # Name of the VNC app in the container (the %appstart section)

# == Slurm preferences:
HYAKVNC_SLURM_JOB_PREFIX="${HYAKVNC_SLURM_JOB_PREFIX:-hyakvnc-}"
HYAKVNC_SBATCH_POST_TIMEOUT="${HYAKVNC_SBATCH_POST_TIMEOUT:-120}"           # How long after submitting via sbatch to wait for the job to start before timing out
HYAKVNC_SLURM_OUTPUT="${HYAKVNC_SLURM_OUTPUT:-${SBATCH_OUTPUT:-}}"          # Where to send sbatch output
HYAKVNC_SLURM_JOB_NAME="${HYAKVNC_SLURM_JOBNAME:-${SBATCH_JOB_NAME:-}}"     # Name of the sbatch job
HYAKVNC_SLURM_ACCOUNT="${HYAKVNC_SLURM_ACCOUNT:-${SBATCH_ACCOUNT:-}}"       # Slurm account to use
HYAKVNC_SLURM_PARTITION="${HYAKVNC_SLURM_PARTITION:-${SBATCH_PARTITION:-}}" # Slurm partition to use
HYAKVNC_SLURM_CLUSTER="${HYAKVNC_SLURM_CLUSTER:-${SBATCH_CLUSTERS:-}}"      # Slurm cluster to use
HYAKVNC_SLURM_GRES="${HYAKVNC_SLURM_GRES:-${SBATCH_GRES:-}}"                # Number of GPUs to request
HYAKVNC_SLURM_MEM="${HYAKVNC_SLURM_MEM:-${SBATCH_MEM:-2G}}"                 # Amount of memory to request
HYAKVNC_SLURM_CPUS="${HYAKVNC_SLURM_CPUS:-4}"                               # Number of CPUs to request
HYAKVNC_SLURM_TIMELIMIT="${HYAKVNC_SLURM_TIMELIMIT:-${SBATCH_TIMELIMIT:-}}" # Slurm timelimit to use

# = Global variables:
LAUNCHED_JOBIDS=() # Array of launched jobs

# = Utility functions:

# log()
# Log a message, given a level and a message
function log {
	LEVEL="${1:-}"
	MESSAGE="${2:-}"
	[ -z "${MESSAGE}" ] && return 0

	shift
	shift

	# if level is symbolic, get a numeric value
	case "$LEVEL" in
	OFF) LEVNUM=0 ;;
	TRACE) LEVNUM=1 ;;
	DEBUG) LEVNUM=2 ;;
	INFO) LEVNUM=3 ;;
	WARN) LEVNUM=4 ;;
	ERROR) LEVNUM=5 ;;
	CRITICAL) LEVNUM=6 ;;
	[0-6]) LEVNUM="$LEVEL" ;;
	*) LEVNUM=3 ;; # default to INFO
	esac

	case "$LEVEL" in
	1 | t | trace | T | TRACE)
		if [ "$LEVNUM" -ge "${HYAKVNC_LOG_LEVEL}" ]; then
			tput -Txterm setaf 2 2>/dev/null
			printf "TRACE: %s\n" "${MESSAGE}" 1>&2
			tput -Txterm sgr0 2>/dev/null

		fi
		;;
	2 | d | debug | D | DEBUG)
		if [ "$LEVNUM" -ge "${HYAKVNC_LOG_LEVEL}" ]; then
			tput -Txterm setaf 6 2>/dev/null
			printf "DEBUG: %s\n" "${MESSAGE}" 1>&2
			tput -Txterm sgr0 2>/dev/null

		fi
		;;

	3 | i | info | I | INFO)
		if [ "$LEVNUM" -ge "${HYAKVNC_LOG_LEVEL}" ]; then
			tput -Txterm setaf 4 2>/dev/null
			printf "INFO: %s\n" "${MESSAGE}" 1>&2
			tput -Txterm sgr0 2>/dev/null

		fi
		;;
	4 | w | warn | warning | W | WARN | WARNING)
		if [ "$LEVNUM" -ge "${HYAKVNC_LOG_LEVEL}" ]; then
			tput -Txterm setaf 3 2>/dev/null
			printf "WARNING: %s\n" "${MESSAGE}" 1>&2
			tput -Txterm sgr0 2>/dev/null
		fi

		;;

	5 | e | error | E | ERROR)
		if [ "$LEVNUM" -ge "${HYAKVNC_LOG_LEVEL}" ]; then
			tput -Txterm setaf 1 2>/dev/null
			printf "ERROR: %s\n" "${MESSAGE}" 1>&2
			tput -Txterm sgr0 2>/dev/null
		fi
		;;
	6 | c | critical | C | CRITICAL)
		if [ "$LEVNUM" -ge "${HYAKVNC_LOG_LEVEL}" ]; then
			tput -Txterm setaf 1 2>/dev/null
			printf "CRITICAL: %s\n" "${MESSAGE}" 1>&2
			tput -Txterm sgr0 2>/dev/null
		fi
		;;
	esac

	return 0
}

# xvnc_ps_for_job()
# Get Xvnc process info for a job, given job ID, cluster, and either PID or PID file:
function xvnc_ps_for_job {
	local jobid cluster ppid ppidfile
	# Parse arguments:
	while true; do
		case ${1:-} in
		-j | --jobid)
			shift
			jobid="${1:-}"
			shift
			;;
		-c | --cluster)
			shift
			cluster="${1:-}"
			shift
			;;
		-P | --ppid)
			shift
			ppid="${1:-}"
			shift
			;;
		-f | --ppid-file)
			shift
			ppidfile="${1:-}"
			shift
			;;
		-*)
			log ERROR "Unknown option for get_vnc_port_from_job: ${1:-}\n"
			return 1
			;;
		*)
			break
			;;
		esac
		[ -z "${jobid:-}" ] && log ERROR "Job ID must be specified" && return 1
		[ -z "${cluster:-}" ] && log ERROR "Cluster must be specified" && return 1
		if [ -z "${ppid:-}" ]; then
			[ -z "${ppidfile:-}" ] && log ERROR "Parent PID or PID file must be specified" && return 1
			[ -e "${ppidfile:-}" ] && log ERROR "Parent PID file not found at expected location ${ppidfile}" && return 1
			read -r ppid <"${ppidfile}" || log ERROR "Failed to read parent PID from ${ppidfile}" && return 1
			[ -z "${ppid:-}" ] && log ERROR "Parent PID file at ${ppidfile} is empty" && return 1
		fi
	done

	# Get the VNC port from the job:
	result=$(srun --jobid "${jobid}" --quiet --error /dev/null sh -c "pgrep --parent ${jobid} --exact Xvnc --list-full || echo")
	[ -z "${result}" ] && log WARNING "Failed to get VNC port from job ${jobid}" && return 1
	echo "${result}"
}

# get_default_slurm_cluster()
# Get the default SLURM cluster
function get_default_slurm_cluster {
	local cluster
	# Get the default cluster:
	cluster=$(sacctmgr show cluster -nPs format=Cluster)
	[ -z "${cluster}" ] && log ERROR "Failed to get default cluster" && return 1
	echo "${cluster}"
}

# get_default_slurm_account()
# Get the default SLURM account
function get_default_slurm_account {
	local account
	# Get the default account:
	account=$(sacctmgr show user -nPs "${USER}" format=defaultaccount | grep -o -m 1 -E '\S+') || log ERROR "Failed to get default account" && return 1
	echo "${account}"
}

# get_slurm_partitions()
# Gets the SLURM partitions for the specified user and account on the specified cluster
function get_slurm_partitions {
	local user account cluster partitions
	user="${1:-${USER}}"
	account="${2:-get_default_slurm_account}"
	cluster="${3:-get_default_slurm_cluster}"
	partitions=$(sacctmgr show -nPs user "${user}" format=qos where account="${account}" cluster="${cluster}" | grep -o -m 1 -E '\S+' | tr ',' ' ') || log ERROR "Failed to get SLURM partitions" && return 1
	# Remove the account prefix from the partitions and return
	echo "${partitions//${account}-/}" && return 0
}

# get_default_slurm_partition()
# Gets the SLURM partitions for the specified user and account on the specified cluster
function get_default_slurm_partition {
	local user account cluster partitions partition
	user="${1:-${USER}}"
	account="${2:-get_default_slurm_account}"
	cluster="${3:-get_default_slurm_cluster}"
	partitions=$(get_slurm_partitions "${user}" "${account}" "${cluster}") ||
		log ERROR "Failed to get default SLURM partition" && return 1
	partition="${partitions% *}"
	[ -z "${partition}" ] && log ERROR "Failed to get default SLURM partition" && return 1
	echo "${partition}" && return 0

}

# expand_slurm_node_range()
# Expand a SLURM node range to a list of nodes
function expand_slurm_node_range {
	[ -z "${1:-}" ] && return 1
	result=$(scontrol show hostnames --oneliner "${1}" | grep -oE '^.+$' | tr ' ' '\n') || return 1
	echo "${result}" && return 0
}

# get_slurm_job_info()
# Get info about a SLURM job, given a list of job IDs
function get_slurm_job_info {
	[ $# -eq 0 ] && log ERROR "User or Job ID must be specified" && return 1

	local user="${1:-${USER}}"
	[ -z "${user}" ] && log ERROR "User must be specified" && return 1
	shift
	local squeue_format_fields='%i %j %a %P %u %T %M %l %C %m %D %N'
	squeue_format_fields="${squeue_format_fields// /\t}" # Replace spaces with tab
	local squeue_args=(--noheader --user "${user}" --format "${squeue_format_fields}")

	local jobids="${*:-}"
	if [ -n "${jobids}" ]; then
		jobids="${jobids//,/ }" # Replace commas with spaces
		squeue_args+=(--job "${jobids}")
	fi
	squeue "${squeue_args[@]}"
}

# get_squeue_job_status
# Get the status of a SLURM job, given a job ID
function get_squeue_job_status {
	local jobid="${1:-}"
	[ -z "${jobid}" ] && log ERROR "Job ID must be specified" && return 1
	squeue -j "${1}" -h -o '%T' || log ERROR "Failed to get status for job ${jobid}" && return 1
}

# check_slurmjob_port_open()
# Check if a port is open on a job, given job ID, cluster, port, and optionally a PID:
function check_slurmjob_port_open {
	local jobid cluster port pid
	# Parse arguments:
	while true; do
		case ${1:-} in
		-j | --jobid)
			shift
			jobid="${1:-}"
			shift
			;;
		-c | --cluster)
			shift
			cluster="${1:-}"
			shift
			;;
		-p | --port)
			shift
			port="${1:-}"
			shift
			;;
		--pid)
			shift
			pid="${1:-}"
			shift
			;;
		-*)
			log ERROR "Unknown option for check_slurmjob_port_open: ${1:-}"
			return 1
			;;
		*)
			break
			;;
		esac
		[ -z "${jobid:-}" ] && log ERROR "Job ID must be specified" && return 1
		[ -z "${cluster:-}" ] && log ERROR "Cluster must be specified" && return 1
		[ -z "${port:-}" ] && log ERROR "Port must be specified" && return 1
	done

	# Use fuser to check if the port is open on the job:
	result=$(srun --jobid "${jobid}" --clusters "${cluster}" --quiet --error /dev/null sh -c "fuser -s -n tcp ${port} || echo")
	[ -z "${result}" ] && return 1

	# If a PID was specified, check that the PID is in the list of PIDs using the port:
	if [ -n "${pid}" ]; then
		echo "${result}" | grep -oE "\b${pid}\b" && return 0 || return 1
	fi
	return 0
}

# stop_hyakvnc_session
# Stop a Hyak VNC session, given a job ID
function stop_hyakvnc_session {
	local jobid jobdir running_job_node instance_name should_cancel
	while true; do
		case ${1:-} in
		-c | --cancel)
			shift
			should_cancel=1
			;;
		-*)
			log ERROR "Unknown option for check_slurmjob_port_open: ${1:-}\n"
			return 1
			;;
		*)
			jobid="${1:-}"
			break
			;;
		esac
	done
	[ -z "${jobid}" ] && log ERROR "Job ID must be specified" && return 1
	jobdir="${HYAKVNC_DIR}/jobs/${jobid}"
	[ -e "${jobdir}" ] || log ERROR "Job directory ${jobdir} does not exist" && return 1
	running_job_node=$(squeue --job "${jobid}" --format "%N" --noheader) || log WARNING "Failed to get node for job ${jobid}"
	[ -z "${running_job_node}" ] && log WARNING "Failed to get node for job ${jobid}. Is it still running?" && return 1
	local xvnc_port xvnc_pid
	xvnc_port=$(cat "${jobdir}/xvnc_port.txt") || log WARNING "Failed to read VNC port from ${jobdir}/xvnc_port.txt"
	xvnc_pid=$(cat "${jobdir}/xvnc_pid.txt") || log WARNING "Failed to read VNC PID from ${jobdir}/xvnc_pid.txt"
	if check_slurmjob_port_open -j "${jobid}" -p "${xvnc_port}" --pid "${xvnc_pid}"; then
		log DEBUG "Job ${jobid} is running on ${running_job_node} with VNC port ${xvnc_port}"
	else
		log WARNING "Job ${jobid} on ${running_job_node} does not appear to be running VNC on port ${xvnc_port}"
	fi
	srun --jobid "${jobid}" --quiet --error /dev/null sh -c "apptainer instance stop ${instance_name}" || log WARNING "Apptainer failed to stop VNC process for job ${jobid} with instance name ${instance_name}"

	# Remove the job directory:
	rm -rf "${jobdir}" || log DEBUG "Failed to remove job directory ${jobdir}"

	if [ -n "${should_cancel}" ]; then
		log INFO "Cancelling job ${jobid}"
		scancel "${jobid}" || log ERROR "Failed to cancel job ${jobid}"
	fi
	return 0
}

# print_connection_info()
# Print connection instructions for a job, given job ID, port, \
# and (optional) port to open on the client:
function print_connection_info {
	local node port viewer_port
	# Parse arguments:
	while true; do
		case ${1:-} in
		-n | --node)
			shift
			node="${1:-}"
			shift
			;;
		-p | --port)
			shift
			port="${1:-}"
			shift
			;;
		--viewer-port)
			shift
			viewer_port="${1:-}"
			shift
			;;

		-*)
			log ERROR "Unknown option for print_connection_info: ${1:-}\n"
			return 1
			;;
		*)
			break
			;;
		esac
	done
	[ -z "${node:-}" ] && log ERROR "Node must be specified" && return 1
	[ -z "${port:-}" ] && log ERROR "Port must be specified" && return 1
	viewer_port="${viewer_port:-${HYAKVNC_VNC_VIEWER_PORT:-${port}}}"

	echo "Copy and paste these instructions into a command line terminal on your local machine to connect to the VNC session."
	echo "You may need to install a VNC client if you don't already have one."
	echo "If you are using Windows or are having trouble, try using the manual connection information."
	echo

	local base_connect_string="ssh -o StrictHostKeyChecking=no -J ${USER}@${HYAKVNC_SSH_HOST} ${node} -L ${viewer_port}:localhost:${port} sleep 10; vncviewer localhost:${viewer_port}"
	echo "Linux terminal (bash/zsh):"
	${base_connect_string}
	echo

	echo "macOS terminal:"
	printf "%s " "${base_connect_string}"
	for bundleid in ${HYAKVNC_MACOS_VNC_VIEWER_BUNDLEIDS}; do
		printf "open -b %s --args localhost:%s 2>/dev/null || " "${bundleid}" "${viewer_port}"
	done
	printf " || echo 'No VNC viewer found. Please install one or try entering the connection information manually.'"
	echo

	echo "Windows:"
	echo "(See below)"
	echo

	echo "Manual connection information:"
	echo -e "Configure your SSH client to connect to the address ${node} with username ${USER} through the \"jump host\" at the address \"${HYAKVNC_SSH_HOST}\"."
	echo -e "Enable local port forwarding from port ${viewer_port} on your machine ('localhost' or 127.0.0.1) to port ${port} on the remote host."
	echo -e "In your VNC client, connect to 'localhost' or 127.0.0.1 on port ${viewer_port}"
	echo
}

# cleanup_launched_jobs_and_exit()
# Cancel any jobs that were launched and exit
function cleanup_launched_jobs_and_exit() {
	local jobdir jobid
	trap - SIGINT SIGTSTP SIGTERM SIGHUP SIGABRT SIGQUIT
	# Cancel any jobs that were launched:
	for jobid in "${LAUNCHED_JOBIDS[@]}"; do
		jobdir="${HYAKVNC_DIR}/jobs/${jobid}"
		log WARNING "Cancelling launched job ${jobid}"
		scancel "${jobid}" || log ERROR "Failed to cancel job ${jobid}"
		[ -d "${jobdir}" ] && rm -rf "${jobdir}" && log DEBUG "Removed job directory ${jobdir}"
	done
	exit 1
}

# = Commands
function help_create {
	cat <<EOF
Usage: hyakvnc create [create options...] -c <container> [extra args to pass to apptainer...]

Description:
  Create a VNC session on Hyak.

Options:
  -h, --help	Show this help message and exit
  -c, --container	Path to container image (required)
  -j, --jobid	Don't launch a new job; instead, attach to this SLURM job ID (optional)
  -A, --account	Slurm account to use (default: ${HYAKVNC_SLURM_ACCOUNT})
  -p, --partition	Slurm partition to use (default: ${HYAKVNC_SLURM_PARTITION})
  -C, --cpus	Number of CPUs to request (default: ${HYAKVNC_SLURM_CPUS})
  -m, --mem	Amount of memory to request (default: ${HYAKVNC_SLURM_MEM})
  -t, --timelimit	Slurm timelimit to use (default: ${HYAKVNC_SLURM_TIMELIMIT})
  -g, --gpus	Number of GPUs to request (default: ${HYAKVNC_SLURM_GRES})

Extra arguments:
  Any extra arguments will be passed to apptainer instance start.
  See 'apptainer instance start --help' for more information.

Examples:
  # Create a VNC session using the container ~/containers/mycontainer.sif
  # Use the SLURM account escience, the partition gpu-a40, 4 CPUs, 1GB of memory, 1 GPU, and 1 hour of time
  hyakvnc create -c ~/containers/mycontainer.sif -A escience -p gpu-a40 -C 4 -m 1G -t 1:00:00 -g 1
EOF
}

# create
function cmd_create {
	local apptainer_start_args=()
	local sbatch_args=(--parsable)
	local container_basename container_name start
	while true; do
		case ${1:-} in
		-h | --help)
			help_create
			return 0
			;;
		-d | --debug) # Debug mode
			shift
			export HYAKVNC_LOG_LEVEL=2
			;;
		-c | --container)
			shift
			[ -z "${1:-}" ] && log ERROR "-c | --container requires a non-empty option argument" && exit 1
			export HYAKVNC_CONTAINER="${1:-}"
			shift
			;;
		-A | --account)
			[ -z "${1:-}" ] && log ERROR "-A | --account requires a non-empty option argument" && exit 1
			shift
			export HYAKVNC_SLURM_ACCOUNT="${1:-}"
			shift
			;;
		-p | --partition)
			shift
			[ -z "${1:-}" ] && log ERROR "-p | --partition requires a non-empty option argument" && exit 1
			export HYAKVNC_SLURM_PARTITION="${1:-}"
			shift
			;;
		-C | --cpus)
			shift
			[ -z "${1:-}" ] && log ERROR "--cpus requires a non-empty option argument" && exit 1
			export HYAKVNC_SLURM_CPUS="${1:-}"
			shift
			;;
		-m | --mem)
			shift
			[ -z "${1:-}" ] && log ERROR "--mem requires a non-empty option argument" && exit 1
			export HYAKVNC_SLURM_MEM="${1:-}"
			shift
			;;
		-t | --timelimit)
			shift
			[ -z "${1:-}" ] && log ERROR "--mem requires a non-empty option argument" && exit 1
			export HYAKVNC_SLURM_TIMELIMIT="${1:-}"
			shift
			;;
		-g | --gpus)
			shift
			export HYAKVNC_SBATCH_GRES="${1:-}"
			shift
			;;
		-j | --jobid) # Job ID to attach to (optional)
			shift
			export HYAKVNC_ATTACH_TO_SLURM_JOB_ID="${1:-}"
			shift
			log ERROR "Option not implemented yet" && exit 1
			;;
		--) # Args to pass to Apptainer
			shift
			if [ -z "${HYAKVNC_APPTAINER_ARGS:-}" ]; then
				export HYAKVNC_APPTAINER_ARGS="${HYAKVNC_APPTAINER_ARGS:-} ${*:-}"
			else
				export HYAKVNC_APPTAINER_ARGS="${*:-}"
			fi
			break
			;;
		-*)
			log ERROR "Unknown option: ${1:-}\n" && exit 1
			;;
		*)
			break
			;;
		esac
	done
	log INFO "Creating VNC job"

	# Check that container is specified
	[ -z "${HYAKVNC_CONTAINER}" ] && log ERROR "Container image must be specified" && exit 1

	# <TODO> add support for containers from URLs like docker:// or oras://
	# For now, just support files:
	[ ! -e "${HYAKVNC_CONTAINER}" ] && log ERROR "Container image at ${HYAKVNC_CONTAINER} does not exist	" && exit 1
	# Check that the container is readable:
	[ ! -r "${HYAKVNC_CONTAINER}" ] && log ERROR "Container image ${HYAKVNC_CONTAINER} is not readable" && exit 1
	container_basename="$(basename "${HYAKVNC_CONTAINER}")"
	[ -z "$container_basename" ] && log ERROR "Failed to get container basename from ${HYAKVNC_CONTAINER}" && exit 1
	container_name="${container_basename%.*}"
	[ -z "$container_basename" ] && log ERROR "Failed to get container name from ${container_basename}" && exit 1

	[ -z "${HYAKVNC_SLURM_JOB_NAME}" ] && export HYAKVNC_SLURM_JOB_NAME="${HYAKVNC_SLURM_JOB_PREFIX}${container_name}"

	# Set sbatch arugments or environment variables:
	#   CPUs has to be specified as a sbatch argument because it's not settable by environment variable:
	[ -n "${HYAKVNC_SLURM_CPUS}" ] && sbatch_args+=(--cpus-per-task "${HYAKVNC_SLURM_CPUS}") && log TRACE "Set --cpus-per-task to ${HYAKVNC_SLURM_CPUS}"
	[ -n "${HYAKVNC_SLURM_ACCOUNT}" ] && export SBATCH_ACCOUNT="${HYAKVNC_SLURM_ACCOUNT}" && log TRACE "Set SBATCH_ACCOUNT to ${SBATCH_ACCOUNT}"
	[ -n "${HYAKVNC_SLURM_PARTITION}" ] && export SBATCH_PARTITION="${HYAKVNC_SLURM_PARTITION}" && log TRACE "Set SBATCH_PARTITION to ${SBATCH_PARTITION}"
	[ -n "${HYAKVNC_SLURM_CLUSTER}" ] && export SBATCH_CLUSTERS="${HYAKVNC_SLURM_CLUSTER}" && log TRACE "Set SBATCH_CLUSTERS to ${SBATCH_CLUSTERS}"
	[ -n "${HYAKVNC_SLURM_TIMELIMIT}" ] && export SBATCH_TIMELIMIT="${HYAKVNC_SLURM_TIMELIMIT}" && log TRACE "Set SBATCH_TIMELIMIT to ${SBATCH_TIMELIMIT}"
	[ -n "${HYAKVNC_SLURM_JOB_NAME}" ] && export SBATCH_JOB_NAME="${HYAKVNC_SLURM_JOB_NAME}" && log TRACE "Set SBATCH_JOB_NAME to ${SBATCH_JOB_NAME}"
	[ -n "${HYAKVNC_SLURM_GRES}" ] && export SBATCH_GRES="${HYAKVNC_SLURM_GRES}" && log TRACE "Set SBATCH_GRES to ${SBATCH_GRES}"
	[ -n "${HYAKVNC_SLURM_MEM}" ] && export SBATCH_MEM="${HYAKVNC_SLURM_MEM}" && log TRACE "Set SBATCH_MEM to ${SBATCH_MEM}"
	[ -n "${HYAKVNC_SLURM_OUTPUT}" ] && export SBATCH_OUTPUT="${HYAKVNC_SLURM_OUTPUT}" && log TRACE "Set SBATCH_OUTPUT to ${SBATCH_OUTPUT}"

	case "${HYAKVNC_APPTAINER_WRITABLE_TMPFS}" in
	1 | true | yes | y | Y | TRUE | YES)
		apptainer_start_args+=(--writable-tmpfs)
		;;
	esac

	case "${HYAKVNC_APPTAINER_CLEANENV}" in
	1 | true | yes | y | Y | TRUE | YES)
		apptainer_start_args+=(--cleanenv)
		;;
	esac

	# Set up the bind paths:
	[ -n "${HYAKVNC_SET_APPTAINER_BIND_PATHS:-}" ] && apptainer_start_args+=(--bind "${HYAKVNC_SET_APPTAINER_BIND_PATHS}")

	[ -z "${HYAKVNC_SBATCH_JOBID}" ] && sbatch_args=("${sbatch_args[@]}" --job-name "${HYAKVNC_SLURM_JOB_PREFIX}")

	# <TODO> If a job ID was specified, don't launch a new job
	# <TODO> If a job ID was specified, check that the job exists and is running

	sbatch_args+=(--wrap)
	sbatch_args+=("\"${HYAKVNC_APPTAINER_BIN}\" instance start --app \"${HYAKVNC_APPTAINER_VNC_APP_NAME}\" --pid-file \"${HYAKVNC_DIR}/pids/\$SLURM_JOBID.pid\" ${apptainer_start_args[@]} \"${HYAKVNC_CONTAINER}\" \"${HYAKVNC_APPTAINER_INSTANCE_PREFIX}\${SLURM_JOB_ID}\"")

	# Trap signals to clean up the job if the user exits the script:
	trap cleanup_launched_jobs_and_exit SIGINT SIGTSTP SIGTERM SIGHUP SIGABRT SIGQUIT
	sbatch_result=$(sbatch "${sbatch_args[@]}") || log ERROR "Failed to launch job" && exit 1
	# Quit if no job ID was returned:
	[ -z "${sbatch_result:-}" ] && log ERROR "Failed to launch job" && exit 1

	# Parse job ID and cluster from sbatch result (semicolon separated):
	launched_jobid="${sbatch_result%%;*}"
	launched_cluster="${sbatch_result##*;}"
	[ -z "${launched_jobid:-}" ] && log ERROR "Failed to launch job" && exit 1

	# Wait for sbatch job to start running by monitoring the output of squeue:
	start=$EPOCHSECONDS
	while true; do
		if ((EPOCHSECONDS - start > HYAKVNC_SBATCH_POST_TIMEOUT)); then
			log ERROR "Timed out waiting for job to start" && exit 1
		fi

		squeue_result=$(squeue --job "${launched_jobid}" --clusters "${launched_cluster}" --format "%T" --noheader)
		case "${squeue_result:-}" in
		SIGNALING | PENDING | CONFIGURING | STAGE_OUT | SUSPENDED | REQUEUE_HOLD | REQUEUE_FED | RESV_DEL_HOLD | STOPPED | RESIZING | REQUEUED)
			log TRACE "Job ${launched_jobid} is in a state that could potentially run: ${squeue_result}"
			sleep 1
			continue
			;;
		RUNNING)
			log DEBUG "Job ${launched_jobid} is ${squeue_result}"
			break
			;;
		*) log ERROR "Job ${launched_jobid} is in unexpected state ${squeue_result}" && exit 1 ;;
		esac
	done

	# Identify the node the job is running on:
	local job_nodelist job_nodes launched_node launched_ppid_file xvnc_ps xvnc_port xvnc_name xvnc_host xvnc_pidfile xvnc_pid
	job_nodelist="$(squeue --job "${launched_jobid}" --clusters "${launched_cluster}" --format "%N" --noheader)" || log ERROR "Failed to get job nodes" && exit 1
	[ -z "${job_nodelist}" ] && log ERROR "Failed to get job nodes" && exit 1

	# Expand the job nodelist:
	job_nodes=$(expand_slurm_node_range "${job_nodelist}") || log ERROR "Failed to expand job nodelist ${job_nodelist}" && exit 1
	[ -z "${job_nodes}" ] && log ERROR "Failed to expand job nodelist ${job_nodelist}" && exit 1

	# Get the first node in the list:
	launched_node="${job_nodes%% *}"
	[ -z "${launched_node}" ] && log ERROR "Failed to parse job node from nodelist ${job_nodelist}" && exit 1

	# Find the PID file for the apptainer instance:
	launched_ppid_file="${HYAKVNC_DIR}/pids/${launched_jobid}.pid"

	# Wait for the PID file to be created:
	start=$EPOCHSECONDS
	until [ -r "${launched_ppid_file}" ]; do
		((EPOCHSECONDS - start > HYAKVNC_STANDARD_TIMEOUT)) && log ERROR "Timed out waiting for Xvnc pidfile to be created at ${launched_ppid_file}" && exit 1
	done

	# Set up the job directory:
	jobdir="${HYAKVNC_DIR}/jobs/${launched_jobid}"
	mkdir -p "${jobdir}" || log ERROR "Failed to create job directory ${jobdir}" && exit 1

	# Get details about the Xvnc process:
	xvnc_ps=$(xvnc_ps_for_job --jobid "${launched_jobid}" --cluster "${launched_cluster}" --ppid-file "${launched_ppid_file}") || log ERROR "Failed to get Xvnc process info for job" && exit 1
	[ -z "${xvnc_ps}" ] && log ERROR "Failed to get Xvnc process from job" && exit 1

	# Get the port and hostname:display part from the Xvnc process info.
	#   (The process info looks like this: '4280 /opt/TurboVNC/bin/Xvnc :1 -desktop TurboVNC: g3050:1 () -auth ...')
	xvnc_port=$(echo "${xvnc_ps}" | grep -oE 'rfbport[[:space:]]+[0-9]+' | grep -oE '[0-9]+') || log ERROR "Failed to get VNC port from job" && exit 1
	xvnc_name=$(echo "${xvnc_ps}" | grep -oE 'TurboVNC: .*:[0-9]+ \(\)' | cut -d' ' -f2) || log ERROR "Failed to get Xvnc PID file from job" && exit 1

	# The Xvnc process should be leaving a PID file named in the format "job_node:DISPLAY.pid". If it's not, this could be a problem:
	xvnc_host="${xvnc_name%%:*}"
	[ -z "$xvnc_host" ] && log WARNING "Failed to get VNC hostname from job" && exit 1
	[ xvnc_host != "${launched_node}" ] && log WARNING "Xvnc on ${xvnc_name} doesn't appear to be running on the same node (${launched_node}) as the job"

	# Look for the PID file for the Xvnc process in the ~/.vnc directory:
	[ -e "${xvnc_pidfile:=${HOME}/.vnc/${xvnc_name}.pid}" ] || log ERROR "Xvnc PID file doesn't exist at ${xvnc_pidfile}" && exit 1
	xvnc_pid=$(grep -m1 -oE '^[0-9]+' "${xvnc_pidfile}") || log ERROR "Failed to get VNC PID from PID file at  ${xvnc_pidfile}" && exit 1

	# Wait for port to be open on the job node for the Xvnc process:
	start=$EPOCHSECONDS
	while true; do
		if ((EPOCHSECONDS - start > HYAKVNC_STANDARD_TIMEOUT)); then
			log ERROR "Timed out waiting for port ${xvnc_port} to be open"
			break
		fi
		check_slurmjob_port_open -j "${launched_jobid}" -c "${launched_cluster}" -p "${xvnc_port}" --pid "${xvnc_pid}" && break
		sleep 1
	done

	# Write metadata:
	echo "${xvnc_ps}" >"${jobdir}/xvnc_ps.txt"
	echo "${xvnc_name}" >"${jobdir}/xvnc_name.txt"
	echo "${xvnc_port}" >"${jobdir}/xvnc_port.txt"
	echo "${xvnc_pidfile}" >"${jobdir}/xvnc_pidfile.txt"
	echo "${xvnc_pid}" >"${jobdir}/xvnc_pid.txt"
	echo "${launched_ppid_file}" >"${jobdir}/instance_ppid_file.txt"
	echo "${launched_jobid}" >"${jobdir}/jobid.txt"
	echo "${launched_cluster}" >"${jobdir}/launched_cluster.txt"
	echo "${launched_node}" >"${jobdir}/launched_node.txt"

	# Print connection strings:
	print_connection_info --node "${xvnc_host}" --port "${xvnc_port}" --viewer-port "${HYAKVNC_VNC_VIEWER_PORT}" || log ERROR "Failed to print connection info" && exit 1

	# Stop trapping the signals:
	trap - SIGINT SIGTSTP SIGTERM SIGHUP SIGABRT SIGQUIT
	return 0
}

function help_status {
	cat <<EOF
Usage: hyakvnc status [status options...]

Description:
  Check status of VNC session(s) on Hyak.

Options:
  -h, --help	Show this help message and exit
  -d, --debug	Print debug info
  -j, --jobid	Only check status of provided SLURM job ID (optional)

Examples:
  # Create a VNC session using the container ~/containers/mycontainer.sif
  # Check the status of job no. 12345:
  hyakvnc status -j 12345
  # Check the status of all VNC jobs:
  hyakvnc status
EOF
}

function cmd_status {
	local account running_jobid running_jobids
	while true; do
		case ${1:-} in
		-h | --help)
			help_status
			return 0
			;;
		-d | --debug) # Debug mode
			shift
			export HYAKVNC_LOG_LEVEL=2
			;;
		-j | --jobid) # Job ID to attach to (optional)
			shift
			running_jobid="${1:-}"
			shift
			;;
		-*)
			log ERROR "Unknown option: ${1:-}\n" && exit 1
			;;
		*)
			break
			;;
		esac
	done
	log INFO "Checking status of VNC jobs"

	# Loop over directories in ${HYAKVNC_DIR}/jobs
	squeue_args=(--me --states=RUNNING --noheader --format '%j %i')
	[ -n "${running_jobid:-}" ] && squeue_args+=(--job "${running_jobid}")
	running_jobids=$(squeue "${squeue_args[@]}" | grep -E "^${HYAKVNC_SLURM_JOB_PREFIX}" | grep -oE '[0-9]+$') || log WARNING "Found no running job IDs with names that match the prefix ${HYAKVNC_SLURM_JOB_PREFIX}" && return 1
	[ -z "${running_jobids:-}" ] && log WARNING "Found no running job IDs with names that match the prefix ${HYAKVNC_SLURM_JOB_PREFIX}" && return 1

	for running_jobid in ${running_jobids:-}; do
		local running_job_node jobdir xvnc_name xvnc_port xvnc_pid xvnc_ps launched_cluster launched_node
		running_job_node=$(squeue --job "${running_jobid}" --format "%N" --noheader) || log WARNING "Failed to get node for job ${running_jobid}" && continue
		[ -z "${running_job_node}" ] && log WARNING "Failed to get node for job ${running_jobid}" && continue

		jobdir="${HYAKVNC_DIR}/jobs/${running_jobid}"
		[ -e "${jobdir}" ] || continue
		[ -d "${jobdir}" ] || continue

		xvnc_name=$(cat "${jobdir}/xvnc_name.txt") || log WARNING "Failed to read VNC name from ${jobdir}/xvnc_name.txt" && continue
		xvnc_port=$(cat "${jobdir}/xvnc_port.txt") || log WARNING "Failed to read VNC port from ${jobdir}/xvnc_port.txt" && continue
		xvnc_pid=$(cat "${jobdir}/xvnc_pid.txt") || log WARNING "Failed to read VNC PID from ${jobdir}/xvnc_pid.txt" && continue
		launched_cluster=$(cat "${jobdir}/launched_cluster.txt") || log WARNING "Failed to read cluster from ${jobdir}/cluster.txt"
		launched_node=$(cat "${jobdir}/launched_node.txt") || log WARNING "Failed to read launched node from ${jobdir}/launched_node.txt"
		if check_slurmjob_port_open -j "${running_jobid}" -p "${xvnc_port}" --pid "${xvnc_pid}"; then
			echo "Job ${jobid} is running on ${running_job_node} with VNC port ${xvnc_port}"
		else
			log DEBUG "Job ${jobid} on ${running_job_node} does not appear to be running VNC on port ${xvnc_port}"
		fi
	done
}

function help_stop {
	cat <<EOF
Usage: hyakvnc stop [-a] [<jobids>...]
	
Description:
  Stop a provided HyakVNC sesssion and clean up its job directory

Options:
  -h, --help	Show this help message and exit
  -c, --cancel	Also cancel the SLURM job
  -a, --all	Stop all jobs

Examples:
  # Stop a VNC session running on job 123456:
  hyakvnc stop 123456
  # Stop a VNC session running on job 123456 and also cancel the job:
  hyakvnc stop -c 123456
  # Stop all VNC sessions:
  hyakvnc stop -a
  # Stop all VNC sessions and also cancel the jobs:
  hyakvnc stop -a -c
EOF
}

function help_show {
	cat <<EOF
Usage: hyakvnc show <jobid>

Description:
  Show connection information for a HyakVNC sesssion

Options:
  -h, --help	Show this help message and exit

Examples:
  # Show connection information for session running on job 123456:
  hyakvnc show 123456
EOF
}

function cmd_stop {
	local jobids all jobid should_cancel stop_hyakvnc_session_args
	stop_hyakvnc_session_args=""
	# Parse arguments:
	while true; do
		case ${1:-} in
		-h | --help)
			help_stop
			return 0
			;;
		-d | --debug) # Debug mode
			shift
			export HYAKVNC_LOG_LEVEL=2
			;;
		-a | --all)
			shift
			all=1
			;;
		-c | --cancel)
			shift
			stop_hyakvnc_session_args+=(--cancel)
			;;
		-*)
			log ERROR "Unknown option for stop: ${1:-}\n"
			return 1
			;;
		*)
			jobids="${*:-}"
			break
			;;
		esac
	done

	if [ -n "$all" ]; then
		jobids=$(squeue --me --format '%j %i' --noheader | grep -E "^${HYAKVNC_SLURM_JOB_PREFIX}" | grep -oE '[0-9]+$') || log WARNING "Found no running job IDs with names that match the prefix ${HYAKVNC_SLURM_JOB_PREFIX}"
	fi

	[ -z "${jobids}" ] && log ERROR "Must specify running job IDs" && exit 1

	# Cancel any jobs that were launched:
	for jobid in ${jobids}; do
		stop_hyakvnc_session "${stop_hyakvnc_session_args[@]}" --jobid "${jobid}" && log INFO "Stopped job ${jobid}"
	done
	return 0
}

function cmd_show {
	local jobids all jobid should_cancel stop_hyakvnc_session_args
	stop_hyakvnc_session_args=""
	# Parse arguments:
	while true; do
		case "${1:-}" in
		-h | --help)
			help_show
			return 0
			;;
		-d | --debug) # Debug mode
			shift
			export HYAKVNC_LOG_LEVEL=2
			;;
		-a | --all)
			shift
			all=1
			;;
		-c | --cancel)
			shift
			stop_hyakvnc_session_args+=(--cancel)
			;;
		-*)
			log ERROR "Unknown option for stop: ${1:-}\n"
			return 1
			;;
		*)
			jobids="${*:-}"
			break
			;;
		esac
	done

	if [ -n "$all" ]; then
		jobids=$(squeue --me --format '%j %i' --noheader | grep -E "^${HYAKVNC_SLURM_JOB_PREFIX}" | grep -oE '[0-9]+$') || log WARNING "Found no running job IDs with names that match the prefix ${HYAKVNC_SLURM_JOB_PREFIX}"
	fi

	[ -z "${jobids}" ] && log ERROR "Must specify running job IDs" && exit 1

	# Cancel any jobs that were launched:
	for jobid in ${jobids}; do
		stop_hyakvnc_session "${stop_hyakvnc_session_args[@]}" --jobid "${jobid}" && log INFO "Stopped job ${jobid}"
	done
	return 0
}

function cmd_help {
	while true; do
		case "${1:-}" in
		create)
			shift
			help_create "$@"

			return 0
			;;
		status)
			shift
			help_status "$@"
			return 0
			;;
		stop)
			shift
			help_stop "$@"
			return 0
			;;
		show)
			shift
			help_show "$@"
			return 0
			;;
		*)
			break
			;;
		esac
	done

	cat <<EOF
HyakVNC -- A tool for launching VNC sessions on Hyak $0
Usage: hyakvnc [options] [create|status|stop|show|help] [options] [args]

Description:
	Stop a provided HyakVNC sesssion and clean up its job directory

Options:
	-h, --help	Show this help message and exit
	-d, --debug	Also cancel the SLURM job
	-V, --version	Print version information and exit

Available commands:
	create	Create a new VNC session
	status	Check status of VNC session(s)
	stop	Stop a VNC session
	show	Show connection information for a VNC session
	help	Show help for a command
EOF
}

# = Main script:
# Initalize directories:
mkdir -p "${HYAKVNC_DIR}/jobs" || (log ERROR "Failed to create HYAKVNC jobs directory ${HYAKVNC_DIR}/jobs" && exit 1)
mkdir -p "${HYAKVNC_DIR}/pids" || (log ERROR "Failed to create HYAKVNC PIDs directory ${HYAKVNC_DIR}/pids" && exit 1)

# Parse first argument as action:

# If the first argument is a function in this file, set it to the action:

while true; do
	case "${1:-}" in
	-h | --help | help)
		shift
		cmd_help "$@"
		exit 0
		;;
	-d | --debug) # Debug mode
		shift
		export HYAKVNC_LOG_LEVEL=2
		;;
	-V | --version)
		shift
		echo "HyakVNC version ${HYAKVNC_VERSION}"
		exit 0
		;;
	create)
		shift
		cmd_create "$@"
		exit 0
		;;
	status)
		shift
		cmd_status "$@"
		exit 0
		;;
	stop)
		shift
		help_stop "$@"
		exit 0
		;;
	show)
		shift
		help_show "$@"
		exit 0
		;;
	*)
		log ERROR "Unknown command: ${1:-}"
		echo
		cmd_help
		exit 1
		;;
	esac
done
