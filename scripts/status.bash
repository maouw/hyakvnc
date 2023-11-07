#! /usr/bin/env bash
# hyakvnc status - Show the status of a HyakVNC session

# Only enable these shell behaviours if we're not being sourced
if ! (return 0 2>/dev/null); then
	# shellcheck source=_header.bash
	source "${BASH_SOURCE:-%/*}/_header.bash"
fi

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
	--no-header	Don't print the header row

Examples:
	# Check the status of job no. 12345:
	hyakvnc status -j 12345
	# Check the status of all VNC jobs:
	hyakvnc status
EOF
}

# cmd_status()
function cmd_status() {
	local jobid jobinfos
	local header="JobID State Node Runtime Name\n"
	while true; do
		case ${1:-} in
		-h | --help)
			help_status
			return 0
			;;
		-j | --jobid) # Job ID to attach to (optional)
			[[ -z "${jobid:=${2:-}}" ]] && {
				log ERROR "No job ID provided for option ${1:-}"
				return 1
			}
			shift
			;;
		--no-header)
			header=""
			;;
		-*)
			log ERROR "Unknown option for ${FUNCNAME#cmd_}: ${1:-}"
			return 1
			;;
		*)
			break
			;;
		esac
		shift
	done

	jobinfos="$(slurm_list_running_hyakvnc "${jobid:+-j "${jobid}"}" || true)"

	if [[ -z "${jobinfos:-}" ]]; then # No jobs found
		log WARN "Found no running jobs with names that match the prefix \"${HYAKVNC_SLURM_JOB_PREFIX}\""
		return 1
	fi
	
	jobinfos="${header}${jobinfos}"

	if [[ -t 1 ]]; then # stdout is a terminal
	if check_command column; then
		echo -e "${jobinfos}" | column --table
	else
		echo -e "${jobinfos}" | tr ' ' '\t'
	fi
	else 
		echo -e "${jobinfos}"
	fi
}

! (return 0 2>/dev/null) && cmd_status "$@"
