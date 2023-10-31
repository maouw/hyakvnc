#! /usr/bin/env bash
# hyakvnc stop - Stop a HyakVNC session

# shellcheck disable=SC2292
[ -n "${XDEBUG:-}" ] && set -x # Set XDEBUG to print commands as they are executed
# shellcheck disable=SC2292
[ -n "${BASH_VERSION:-}" ] || { echo "Requires Bash"; exit 1; }
set -o pipefail # Use last non-zero exit code in a pipeline
set -o errtrace # Ensure the error trap handler is inherited
set -o nounset  # Exit if an unset variable is used
SCRIPTDIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=_lib.bash
source "${SCRIPTDIR}/_lib.bash"

# help_stop()
function help_stop() {
	cat <<EOF
Stop a HyakVNC session

Usage: hyakvnc stop [-a] [<jobids>...]
	
Description:
	Stop a provided HyakVNC sesssion and clean up its job directory.
	If no job ID is provided, a menu will be shown to select from running jobs.

Options:
	-h, --help	Show this help message and exit
	-n, --no-cancel	Don't cancel the SLURM job
	-a, --all	Stop all jobs

Examples:
	# Stop a VNC session running on job 123456:
	hyakvnc stop 123456
	# Stop a VNC session running on job 123456 and do not cancel the job:
	hyakvnc stop --no-cancel 123456
	# Stop all VNC sessions:
	hyakvnc stop -a
	# Stop all VNC sessions but do not cancel the jobs:
	hyakvnc stop -a -n
EOF
}

# cmd_stop()
function cmd_stop() {
	local jobids all jobid nocancel stop_hyakvnc_session_args
	should_cancel=1
	stop_hyakvnc_session_args=()
	# Parse arguments:
	while true; do
		case ${1:-} in
			-h | --help)
				help_stop
				return 0
				;;
			-d | --debug) # Debug mode
				shift
				export HYAKVNC_LOG_LEVEL=DEBUG
				;;
			-a | --all)
				shift
				all=1
				;;
			-n | --no-cancel)
				shift
				nocancel=1
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
	if [[ -z "${nocancel:-}" ]]; then
		stop_hyakvnc_session_args+=("--cancel")
	fi

	if [[ -n "${all}" ]]; then
		jobids=$(squeue --me --format '%j %i' --noheader | grep -E "^${HYAKVNC_SLURM_JOB_PREFIX}" | grep -oE '[0-9]+$') || log WARN "Found no running job IDs with names that match the prefix ${HYAKVNC_SLURM_JOB_PREFIX}"
	fi

	if [[ -z "${jobids}" ]]; then
		if [[ -t 0 ]]; then
			echo "Reading available job IDs to select from a menu"
			running_jobids=$(squeue --noheader --format '%j %i' | grep -E "^${HYAKVNC_SLURM_JOB_PREFIX}" | grep -oE '[0-9]+$') || {
				log WARN "Found no running jobs  with names that match the prefix ${HYAKVNC_SLURM_JOB_PREFIX}"
				return 1
			}
			PS3="Enter a number: "
			select jobids in ${running_jobids}; do
				echo "Selected job: ${jobids}" && echo && break
			done
		fi
	fi

	[[ -z "${jobids}" ]] && {
		log ERROR "Must specify running job IDs"
		exit 1
	}

	# Cancel any jobs that were launched:
	for jobid in ${jobids}; do
		stop_hyakvnc_session "${stop_hyakvnc_session_args[@]}" "${jobid}" && log INFO "Stopped job ${jobid}"
	done
	return 0
}

cmd_stop "$@"
