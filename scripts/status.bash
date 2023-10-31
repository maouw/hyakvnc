#! /usr/bin/env bash
# hyakvnc status - Show the status of a HyakVNC session

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

# help_status()
function help_status() {
	cat <<EOF
Show the status of running HyakVNC sessions

Usage: hyakvnc status [status options...]

Description:
	Check status of VNC session(s) on Hyak.

Options:
	-h, --help	Show this help message and exit
	-d, --debug	Print debug info
	-j, --jobid	Only check status of provided SLURM job ID (optional)

Examples:
	# Check the status of job no. 12345:
	hyakvnc status -j 12345
	# Check the status of all VNC jobs:
	hyakvnc status
EOF
}

# cmd_status()
function cmd_status() {
	local running_jobid running_jobids
	while true; do
		case ${1:-} in
			-h | --help)
				help_status
				return 0
				;;
			-d | --debug) # Debug mode
				shift
				export HYAKVNC_LOG_LEVEL=DEBUG
				;;
			-j | --jobid) # Job ID to attach to (optional)
				shift
				running_jobid="${1:-}"
				shift
				;;
			-*)
				log ERROR "Unknown option: ${1:-}\n"
				exit 1
				;;
			*)
				break
				;;
		esac
	done
	# Loop over directories in ${HYAKVNC_DIR}/jobs
	squeue_args=(--me --states=RUNNING --noheader --format '%j %i')
	[[ -n "${running_jobid:-}" ]] && squeue_args+=(--job "${running_jobid}")
	running_jobids=$(squeue "${squeue_args[@]}" | grep -E "^${HYAKVNC_SLURM_JOB_PREFIX}" | grep -oE '[0-9]+$') || {
		log WARN "Found no running job IDs with names that match the set job name prefix ${HYAKVNC_SLURM_JOB_PREFIX}"
		return 1
	}
	[[ -z "${running_jobids:-}" ]] && {
		log WARN "Found no running job IDs with names that match the prefix ${HYAKVNC_SLURM_JOB_PREFIX}"
		return 1
	}

	for running_jobid in ${running_jobids:-}; do
		local running_job_node jobdir
		running_job_node=$(squeue --job "${running_jobid}" --format "%N" --noheader --states=RUNNING) || {
			log WARN "Failed to get node for job ${running_jobid}"
			continue
		}
		[[ -z "${running_job_node}" ]] && {
			log WARN "Failed to get node for job ${running_jobid}"
			continue
		}
		jobdir="${HYAKVNC_DIR}/jobs/${running_jobid}"
		[[ ! -d "${jobdir}" ]] && {
			log WARN "Job directory ${jobdir} does not exist"
			continue
		}
		[[ ! -e "${jobdir}/vnc/socket.uds" ]] && {
			log WARN "Job socket not found at ${jobdir}/vnc/socket.uds"
			continue
		}
		[[ ! -S "${jobdir}/vnc/socket.uds" ]] && {
			log WARN "Job socket at ${jobdir}/vnc/socket.uds is not a socket"
			continue
		}
		echo "HyakVNC job ${running_jobid} is running on node ${running_job_node}"
	done
}

cmd_status "$@"
