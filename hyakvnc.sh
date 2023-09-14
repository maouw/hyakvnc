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
export SALLOC_ACCOUNT="${SALLOC_ACCOUNT:=escience}"
export SALLOC_DEBUG="${SALLOC_DEBUG:=0}"
export SALLOC_GPUS="${SALLOC_GPUS:=0}"
export SALLOC_PARTITION="${SALLOC_PARTITION:=gpu-a40}"
export SALLOC_TIMELIMIT="${SALLOC_TIMELIMIT:=1:00:00}"
export ARG_SALLOC_NTASKS="${ARG_SALLOC_NTASKS:=4}"

# Check if command exists:
function _command_exists {
	command -v "$1" >/dev/null 2>&1
}

# Check if the current host is a login node:
function _is_login_node {
	echo "${LOGIN_NODE_LIST[@]}" | grep -q "${CURRENT_HOSTNAME}"
}

_ANSI_BLUE=
_ANSI_BOLD=
_ANSI_CYAN=
_ANSI_GREEN=
_ANSI_MAGENTA=
_ANSI_RED=
_ANSI_RESET=
_ANSI_UNDERLINE=
_ANSI_YELLOW=

_log() {
	if [ -z "${_colors_initialized}" ]; then
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
	printf "$(date --rfc-3339=s) ${_ANSI_BOLD}${color}${level}${_ANSI_RESET}: ${color}$* ${_ANSI_RESET}\n" 1>&2
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

function launch {
	ARGS_TO_SALLOC=""
	NTASK_ARGUMENT="--ntasks=${ARG_SALLOC_NTASKS}"
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
			ARGS_TO_SALLOC="${ARGS_TO_SALLOC} $1"
			shift
			;;
		esac
	done
	[ -z "$SIF_FILE" ] && _log ERROR "Requires a --sif argument specifying the path to the container image" && exit 1
	SIF_FILE=$(realpath "${SIF_FILE}")
	SIF_BASENAME=$(basename "${SIF_FILE}")
	[ ! -f "$SIF_FILE" ] && _log ERROR "--sif requires a file to be present at ${SIF_FILE}" && exit 1

	ARGS_TO_SALLOC="${NTASK_ARGUMENT} ${ARGS_TO_SALLOC}"
	ARGS_TO_SALLOC="${ARGS_TO_SALLOC/  /}" # Remove double spaces

	_log INFO "Launching job with sif file ${SIF_FILE} and args ${ARGS_TO_SALLOC}"
	COMMAND_TO_RUN="salloc ${ARGS_TO_SALLOC} srun --job-name \"${SIF_BASENAME}\" --pty apptainer run --writable-tmpfs --cleanenv \"${SIF_FILE}\""
	_log INFO "Will run the following command:"
	echo "${COMMAND_TO_RUN}"

	if [ ! "$DRY_RUN" ]; then
		! _command_exists salloc && echo "ERROR: salloc not found" && exit 1
		! _is_login_node && echo "ERROR: You must run salloc from a login node. This is not a login node." && exit 1
		${COMMAND_TO_RUN}
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
