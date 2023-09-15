#! /usr/bin/env bash

set -f # Disable pathname expansion.
#set -o pipefail # Return exit status of the last command in the pipe that failed.
#set -e          # Exit immediately if a command exits with a non-zero status.
[ "$DEBUG" == 1 ] && set -x

CLUSTER_ADDRESS=${CLUSTER_ADDRESS:=klone.hyak.uw.edu}
PORT_ON_CLIENT=${PORT_ON_CLIENT:=5901}
CURRENT_HOSTNAME=$(hostname)

# List of Klone login node hostnames
LOGIN_NODE_LIST='klone-login01 klone1.hyak.uw.edu klone2.hyak.uw.edu'

# Slurm configuration variables:
export SBATCH_ACCOUNT="${SBATCH_ACCOUNT:=escience}"
export SBATCH_DEBUG="${SBATCH_DEBUG:=0}"
export SBATCH_GPUS="${SBATCH_GPUS:=0}"
export SBATCH_PARTITION="${SBATCH_PARTITION:=gpu-a40}"
export SBATCH_TIMELIMIT="${SBATCH_TIMELIMIT:=1:00:00}"
export ARG_SBATCH_NTASKS="${ARG_SBATCH_NTASKS:=4}"

# Check if command exists:
function _command_exists {
	command -v "$1" >/dev/null
}

# Check if the current host is a login node:
function _is_login_node {
	echo "${LOGIN_NODE_LIST[@]}" | grep -q "${CURRENT_HOSTNAME}"
}

APPTAINER_INSTANCES_DIR=${APPTAINER_INSTANCES_DIR:=${HOME}/.apptainer/instances}

function _find_vnc_instance_pid_files {
	# Make sure globstar is enabled
	shopt -s globstar
	for f in "$APPTAINER_INSTANCES_DIR"/app/**/*.json; do
		logOutPath=$(python3 -c'import json, sys;print(json.load(open(sys.argv[1]))["logOutPath"])' "$f" 2>/dev/null)
		[ -z "$logOutPath" ] && continue
		[ ! -f "$logOutPath" ] && continue

		vncPidFile=$(sed -E '/Log file is/!d; s/^.*[/]//; s/[.]log$/.pid/' "${logOutPath}")
		vncPidPath="${HOME}/.vnc/${vncPidFile}"
		if [ ! -f "$vncPidPath" ]; then
			echo "Could not find vncPidFile at ${vncPidPath}"
			continue
		fi
		echo $vncPidFile
	done
	shopt -u globstar
}

_log() {
	_ANSI_BLUE= _ANSI_BOLD= _ANSI_CYAN= _ANSI_GREEN= _ANSI_MAGENTA= _ANSI_RED= _ANSI_RESET= _ANSI_UNDERLINE= _ANSI_YELLOW=
	[[ "${BASH_SOURCE[0]:-}" != "${0}" ]] && sourced=1 || sourced=0
	[[ -t 1 ]] && piped=0 || piped=1 # detect if output is piped
	if [[ $piped -eq 0 ]]; then
		_ANSI_GREEN="\033[92m"
		_ANSI_RED="\033[91m"
		_ANSI_CYAN="\033[36m"
		_ANSI_YELLOW="\033[93m"
		_ANSI_MAGENTA="\033[95m"
		_ANSI_BLUE="\033[94m"
		_ANSI_RESET="\033[0m"
		_ANSI_BOLD="\033[1m"
		_ANSI_UNDERLINE="\033[4m"
	fi
	level="${1}"
	color="${_ANSI_RESET}"
	shift
	case "${level}" in
	INFO)
		color="${_ANSI_CYAN}"
		;;
	WARN)
		color="${_ANSI_YELLOW}"
		;;
	ERROR)
		color="${_ANSI_RED}"
		;;
	esac
	printf "$(date --rfc-3339=s) ${_ANSI_BOLD}${color}${level}${_ANSI_RESET}: ${color}$* ${_ANSI_RESET}\n"
}

function list_vnc_pids {
	for f in $HOME/.vnc/*.pid; do
		vnchostfull=$(basename ${f%%.pid})
		vnchost=${vnchostfull%%:*}
		vncport=${vnchostfull##*:}
		echo $vnchost $vncport
	done
}

function show_connection_string_for_linux_host {
	echo 'ssh -f -J klone.hyak.uw.edu g3071 -L 5901:localhost:5901 sleep 10; vncviewer localhost:5901'
	vnchost=$1
	vncport=$2
	echo "vncviewer ${vnchost}:${vncport}"
}

function generate_ssh_command {
	echo "ssh -f -N -J \"${CLUSTER_HOSTNAME}\" \${HOSTNAME 5901:localhost:5901"
}

function status {
	_log ERROR "status task not implemented"
}

function kill {
	_log ERROR "kill task not implemented"
}

function kill-all {
	_log ERROR "kill-all task not implemented"
}

function set-passwd {
	_log ERROR "set-passwd task not implemented"
}

function repair {
	_log ERROR "repair task not implemented"
}
function build {
	_log ERROR "build task not implemented"
}

sbatch -A escience --job-name thing2 -p gpu-a40 -c 1 --mem=1G --time=1:00:00 --wrap "apptainer instance start $(realpath ~/code/apptainer-test/looping/looping.sif) thing2 && while true; do sleep 10; done"

function launch {
	ARGS_TO_SBATCH=""
	NTASK_ARGUMENT="--ntasks=${ARG_SBATCH_NTASKS}"
	for i in "$@"; do
		case $i in
		--dry-run)
			DRY_RUN=1
			shift
			;;
		-n=* | --ntasks=*)
			NTASK_ARGUMENT="$1"
			shift # past argument=value
			;;
		-c=* | --cpus-per-task=*)
			NTASK_ARGUMENT="$1"
			shift # past argument=value
			;;
		--sif)
			shift
			[ -z "$1" ] && _log ERROR "--sif requires a non-empty option argument" && exit 1
			SIF_FILE="$1"
			shift # past argument=value
			;;
		*)
			ARGS_TO_SBATCH="${ARGS_TO_SBATCH} $1"
			shift
			;;
		esac
	done
	[ -z "$SIF_FILE" ] && _log ERROR "Requires a --sif argument specifying the path to the container image" && exit 1
	SIF_PATH=$(realpath "${SIF_FILE}")
	SIF_BASENAME="$(basename "${SIF_FILE}")"
	SIF_NAME="${SIF_BASENAME%.*}"

	[ ! -f "$SIF_PATH" ] && _log ERROR "--sif requires a file to be present at ${SIF_FILE}" && exit 1

	ARGS_TO_SBATCH="${NTASK_ARGUMENT} ${ARGS_TO_SBATCH}"
	ARGS_TO_SBATCH="${ARGS_TO_SBATCH/  /}" # Remove double spaces

	_log INFO "Launching job with sif file ${SIF_FILE} and args ${ARGS_TO_SBATCH}"

	#sbatch -A escience --job-name thing2 -p gpu-a40 -c 1 --mem=1G --time=1:00:00 --wrap "apptainer instance start $(realpath ~/code/apptainer-test/looping/looping.sif) thing2 && while true; do sleep 10; done"
	COMMAND_TO_RUN=
	_log INFO "Will run the following command:"
	echo "${COMMAND_TO_RUN}"

	if [ ! "$DRY_RUN" ]; then
		! _command_exists sbatch && echo "ERROR: sbatch not found" && exit 1
		! _is_login_node && echo "ERROR: You must run this from a login node. This is not a login node." && exit 1
		sbatch ${ARGS_TO_SBATCH} --job-name ${SIF_NAME} --wrap "apptainer instance start ${SIF_PATH} ${SIF_NAME}-\$SLURM_JOBID && while true; do sleep 10; done"
	else
		_log INFO "Dry run. Not running sbatch."
		_log INFO "Would have run sbatch ${ARGS_TO_SBATCH} --job-name ${SIF_NAME} --wrap \"apptainer instance start ${SIF_PATH} ${SIF_NAME}-\$SLURM_JOBID && while true; do sleep 10; done\""
	fi
}

function default {
	echo "Args:" "$@"
	help
}

function help {
	echo "$0 <task> <args>"
	echo "Tasks:"
	compgen -A function | grep -v '^_' | cat -n
}

# Set default action:
ACTION=default

# If the first argument is a function in this file, set it to the action:
if [ $# -gt 0 ] && [ $(compgen -A function | grep '^'"$1"'$') ]; then
	[ "$DEBUG" == 1 ] && echo "Setting action to $1"
	ACTION="$1"
	shift
fi

# Run the action:
"$ACTION" "$@"
