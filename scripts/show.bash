#! /usr/bin/env bash
# hyakvnc show - Show connection information for a HyakVNC sesssion

# Only enable these shell behaviours if we're not being sourced
if ! (return 0 2>/dev/null); then
	set -o pipefail
	# shellcheck source=_header.bash
	source "${BASH_SOURCE[0]%/*}/_header.bash"
	# shellcheck source=status.bash
	source "${BASH_SOURCE[0]%/*}/status.bash"
fi

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
	local jobid
	# Parse arguments:
	while true; do
		case "${1:-}" in
		-h | --help)
			help_show
			return 0
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
		local jobinfos
		declare -a running_jobids

		echo "No job ID provided, showing all running jobs:"
		echo
		jobinfos="$(cmd_status "${jobid:+-j "${jobid}"}" || true)"

		[[ -z "${jobinfos}" ]] && {
			log WARN "No jobs to show"
			return 1
		}
		echo "${jobinfos}"

		local -a running_jobids
		readarray -t running_jobids < <(echo "${jobinfos}" | tail -n +2 | grep -E --only-matching "^[0-9]+" || true)
		
		[[ "${#running_jobids[@]}" -eq 0 ]] && {
			log WARN "No jobs to show"
			return 1
		}
		echo
		if [[ -z "${jobid:-}" ]] && [[ -t 0 ]]; then # stdin is a terminal
			PS3="Select a job to show: "
			select jobid in "${running_jobids[@]}"; do
				[[ -n "${jobid:-}" ]] && echo "Selected job: ${jobid}" && break
			done
		fi
	fi

	[[ -z "${jobid:-}" ]] && { log ERROR "Must specify running job IDs"; return 1; }

	print_connection_info -j "${jobid}" || { log ERROR "Failed to print connection info for job ${jobid}"; return 1; }

	return 0
}

! (return 0 2>/dev/null) && cmd_show "$@"
