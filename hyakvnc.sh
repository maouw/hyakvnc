#! /usr/bin/env bash

HYAKVNC_LOG_PATH="${HYAKVNC_LOG_PATH:-$HOME/.hyakvnc.log}"
HYAKVNC_LOG_LEVEL="${HYAKVNC_LOG_LEVEL:-1}"
HYAKVNC_CONFIG_DIR="${HYAKVNC_CONFIG_DIR:-$HOME/.config/hyakvnc}"
HYAKVNC_JOB_PREFIX="${HYAKVNC_JOB_PREFIX:-hyakvnc}"
HYAKVNC_CONTAINER="${HYAKVNC_CONTAINER:-}"
HYAKVNC_APPTAINER_BIN="${HYAKVNC_APPTAINER_BIN:-apptainer}"
HYAKVNC_APPTAINER_CONFIG_DIR="${HYAKVNC_APPTAINER_CONFIG_DIR:-$HOME/.apptainer}"
HYAKVNC_APPTAINER_INSTANCE_PREFIX="${HYAKVNC_APPTAINER_INSTANCE_PREFIX:-hyakvnc}"
HYAKVNC_APPTAINER_WRITABLE_TMPFS="${HYAKVNC_APPTAINER_WRITABLE_TMPFS:-${APPTAINER_WRITABLE_TMPFS:-true}}"
HYAKVNC_APPTAINER_CLEANENV="${HYAKVNC_APPTAINER_CLEANENV:-${APPAINER_CLEANENV:-true}}"
HYAKVNC_SET_APPTAINER_BIND_PATHS="${HYAKVNC_SET_APPTAINER_BIND_PATHS:-}"
HYAKVNC_SET_APPTAINER_ENV_VARS="${HYAKVNC_SET_APPTAINER_ENV_VARS:-}"
HYAKVNC_SBATCH_POST_TIMEOUT="${HYAKVNC_SBATCH_POST_TIMEOUT:-120.0}"
HYAKVNC_SBATCH_OUTPUT_PATH="${HYAKVNC_SBATCH_OUTPUT_PATH:-/dev/null}"
HYAKVNC_SBATCH_JOB_NAME="${HYAKVNC_SBATCH_JOB_NAME:-}"
HYAKVNC_SLURM_ACCOUNT="${HYAKVNC_SLURM_ACCOUNT:-${SBATCH_ACCOUNT}}}"
HYAKVNC_SLURM_PARTITION="${HYAKVNC_SLURM_PARTITION:-}"
HYAKVNC_SLURM_CLUSTER="${HYAKVNC_SLURM_CLUSTER:-${SBATCH_CLUSTERS}}"
HYAKVNC_SLURM_GPUS="${HYAKVNC_SLURM_GPUS:-${SBATCH_GPUS}}"
HYAKVNC_SLURM_MEM="${HYAKVNC_SLURM_MEM:-${SBATCH_MEM:-2G}}"
HYAKVNC_SLURM_CPUS="${HYAKVNC_SLURM_CPUS:-${SLURM_CPUS_PER_TASK:-2}}"
HYAKVNC_SLURM_TIMELIMIT="${HYAKVNC_SLURM_TIMELIMIT:-${SBATCH_TIMELIMIT}}"
HYAKVNC_SSH_HOST="${HYAKVNC_SSH_HOST:-klone.hyak.uw.edu}"

_log() {
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

function help {
	echo "Usage: hyakvnc [options] [command]"
}

function _print_create_help {
	echo "Usage: hyakvnc create [options] [command]"
}

function _sbatch_launch {
}
function create {
	while true; do
		case ${1:-} in
		-h | --help | help)
			_print_create_help
			break
			;;
		-c | --container)
			shift
			export HYAKVNC_CONTAINER="${1:-}"
			shift
			if [ ! -e "${HYAKVNC_CONTAINER:-}" ]; then
				_log ERROR "Container image must be a file"
				exit 1
			fi
			;;
		-A | --account)
			shift
			export HYAKVNC_SLURM_ACCOUNT="${1:-}"
			shift
			;;
		-p | --partition)
			shift
			export HYAKVNC_SLURM_PARTITION="${1:-}"
			shift
			;;
		-C | --cpus)
			shift
			export HYAKVNC_SLURM_CPUS="${1:-}"
			shift
			;;
		-m | --mem)
			shift
			export HYAKVNC_SLURM_MEM="${1:-}"
			shift
			;;
		-t | --timelimit)
			shift
			export HYAKVNC_SLURM_TIMELIMIT="${1:-}"
			shift
			;;
		-g | --gpus)
			shift
			export HYAKVNC_SLURM_GPUS="${1:-}"
			shift
			;;
		-*)
			message ERROR "Unknown option: ${1:-}\n"
			exit 1
			;;
		*)
			break
			;;
		esac
	done

	if [ -z "${HYAKVNC_CONTAINER:-}" ]; then
		_log ERROR "Container image must be specified"
		exit 1
	fi

	sbatch_result=$(sbatch \
		--parsable \
		--job-name "${HYAKVNC_JOB_PREFIX}" \
		--output "${HYAKVNC_SBATCH_OUTPUT_PATH}" \
		--time "${HYAKVNC_SLURM_TIMELIMIT}" \
		--account "${HYAKVNC_SLURM_ACCOUNT}" \
		--clusters "${HYAKVNC_SLURM_CLUSTER}" \
		---partition "${HYAKVNC_SLURM_PARTITION}" \
		--cpus-per-task "${HYAKVNC_SLURM_CPUS}" \
		--mem "${HYAKVNC_SLURM_MEM}" \
		--gres "${HYAKVNC_SLURM_GPUS}" \
		---wrap \
		"apptainer instance start \"${HYAKVNC_CONTAINER}\" \"${HYAKVNC_APPTAINER_INSTANCE_PREFIX}-\${SLURM_JOB_ID}-${HYAKVNC_CONTAINER_NAME}\""
		) || _log ERROR "Failed to launch job" && exit 1
	[ -z "${sbatch_result:-}" ] && _log ERROR "Failed to launch job" && exit 1
	launched_jobid="${sbatch_result%%;*}"
	launched_cluster="${sbatch_result##*;}"
	[ -z "${launched_jobid:-}" ] && _log ERROR "Failed to launch job" && exit 1

	# Wait for sbatch job to start running by monitoring the output of squeue
	while true; do
		squeue_result=$(squeue --job "${launched_jobid}" --clusters "${launched_cluster}" --format "%T" --noheader)
		case "${squeue_result:-}" in
		SIGNALING | PENDING | CONFIGURING | STAGE_OUT | SUSPENDED | REQUEUE_HOLD | REQUEUE_FED | PENDING | RESV_DEL_HOLD | STOPPED | RESIZING | REQUEUED)
			_log INFO "Job ${launched_jobid} is ${squeue_result}"
			sleep 1
			continue
			;;
		RUNNING)
			_log INFO "Job ${launched_jobid} is ${squeue_result}"
			break
			;;
		*) _log ERROR "Job ${launched_jobid} is ${squeue_result}" && exit 1 ;;
		esac
	done

	job_nodelist=$(squeue --job "${launched_jobid}" --clusters "${launched_cluster}" --format "%N" --noheader)
	[ -z "${job_nodelist:-}" ] && _log ERROR "Failed to get job nodes" && exit 1
	job_nodes=$(scontrol show hostnames "${job_nodelist}" 2>/dev/null | )
	[ -z "${job_nodes:-}" ] && _log ERROR "Failed to get job nodes" && exit 1

	# Get the first node in the list
	job_node="${job_nodes%% *}"
	[ -z "${job_node:-}" ] && _log ERROR "Failed to get job node" && exit 1

	vncport=$(srun --jobid "${launched_jobid}" --clusters "${launched_cluster}" --nodelist "${job_node}" --pty bash -c pgrep -U $USER --exact Xvnc -a | grep -oE 'rfbport[[:space:]]+[0-9]+' | grep -oE '[0-9]+')
	[ -z "${vncport:-}" ] && _log ERROR "Failed to get VNC port" && exit 1
	vnc_pidfile=$HOME/.vnc/${job_node}:${vncport}.pid
	[ ! -e "${vnc_pidfile:-}" ] && _log ERROR "Failed to get VNC pidfile" && exit 1
	vnc_logfile=$HOME/.vnc/${job_node}:${vncport}.log
	[ ! -e "${vnc_logfile:-}" ] && _log ERROR "Failed to get VNC logfile" && exit 1

	print_connection_info "${job_node}" "${vncport}" "${vnc_pidfile}" "${vnc_logfile}"
	exit 0
}

function status {
	_log INFO "Checking status of VNC jobs"
	# Look in ~/.vnc for pidfiles:
	#   - if pidfile exists, check if process is running
	#   - if process is running, check if it is Xvnc
	#   - if Xvnc, check if it is running on the same node
	#   - if Xvnc is running on the same node, check if it is listening on the same port
	for pidfile in "$HOME"/.vnc/*:*.pid; do
		[ ! -e "${pidfile:-}" ] && continue
		# Get the node and port from the pidfile
		
	done
}
function _main {
	"${@:-help}"
}
