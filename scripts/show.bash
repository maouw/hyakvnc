#! /usr/bin/env bash
# hyakvnc show - Show connection information for a HyakVNC sesssion

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

# help_show()
function help_show() {
	cat <<EOF
Show connection information for a HyakVNC sesssion

Usage: hyakvnc show <jobid>
	
Description:
	Show connection information for a HyakVNC sesssion. 
	If no job ID is provided, a menu will be shown to select from running jobs.
	
Options:
	-h, --help	Show this help message and exit

Examples:
	# Show connection information for session running on job 123456:
	hyakvnc show 123456
	# Interactively select a job to show connection information for:
	hyakvnc show

	# Show connection information for session running on job 123456 for macOS:
	hyakvnc show -s mac 123456
EOF
}

# cmd_show()
function cmd_show() {
	local jobid running_jobids
	# Parse arguments:
	while true; do
		case "${1:-}" in
			-h | --help)
				help_show
				return 0
				;;
			-d | --debug) # Debug mode
				shift
				export HYAKVNC_LOG_LEVEL=DEBUG
				;;
			-*)
				log ERROR "Unknown option for show: ${1:-}\n"
				return 1
				;;
			*)
				jobid="${1:-}"
				break
				;;
		esac
	done

	if [[ -z "${jobid:-}" ]]; then
		if [[ -t 0 ]]; then
			echo "Reading available job IDs to select from a menu"
			running_jobids=$(squeue --noheader --format '%j %i' --states RUNNING | grep -E "^${HYAKVNC_SLURM_JOB_PREFIX}" | grep -oE '[0-9]+$') || {
				log WARN "Found no running jobs with names that match the prefix ${HYAKVNC_SLURM_JOB_PREFIX}"
				return 1
			}
			PS3="Enter a number: "
			select jobid in ${running_jobids}; do
				echo "Selected job: ${jobid}" && echo && break
			done
		fi
	fi
	[[ -z "${jobid}" ]] && {
		log ERROR "Must specify running job IDs"
		return 1
	}
	running_jobids=$(squeue --job "${jobid}" --noheader --format '%j %i' | grep -E "^${HYAKVNC_SLURM_JOB_PREFIX}" | grep -oE '[0-9]+$') || {
		log WARN "Found no running job for job ${jobid} with names that match the prefix ${HYAKVNC_SLURM_JOB_PREFIX}"
		return 1
	}
	print_connection_info -j "${jobid}" || {
		log ERROR "Failed to print connection info for job ${jobid}"
		return 1
	}
	return 0
}

cmd_show "$@"
