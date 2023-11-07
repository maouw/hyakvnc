#! /usr/bin/env bash
# hyakvnc stop - Stop a HyakVNC session

# Only enable these shell behaviours if we're not being sourced
if ! (return 0 2>/dev/null); then
	# shellcheck source=_header.bash
	source "${BASH_SOURCE[0]%/*}/_header.bash"
fi

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
	local all nocancel
	local -a stop_hyakvnc_session_args=()
	local -a jobids=()
	should_cancel=1
	stop_hyakvnc_session_args=()
	# Parse arguments:
	while true; do
		case ${1:-} in
		-h | --help)
			help_stop
			return 0
			;;
		-a | --all)
			all=1
			;;
		-n | --no-cancel)
			stop_hyakvnc_session_args+=("--cancel")
			;;
		-*)
			log ERROR "Unknown option for ${FUNCNAME#cmd_}: ${1:-}"
			return 1
			;;
		*) [[ -n "${1:-}" ]] || break
		jobids+=("${1:-}")
			;;
		esac
		shift
	done

	if [[ "${#jobids[@]}" -eq 0 ]]; then
		local jobinfos jobid
		local -a running_jobids

		jobinfos="$(cmd_status "${jobid:+-j "${jobid}"}" || true)"

		[[ -z "${jobinfos}" ]] && {
			log WARN "No jobs found"
			return 1
		}

		readarray -t running_jobids < <(echo "${jobinfos}" | tail -n +2 | grep -E --only-matching "^[0-9]+" || true)

		[[ "${#running_jobids[@]}" -eq 0 ]] && {
			log WARN "No jobs found"
			return 1
		}

		if [[ "${all:-0}" == "1" ]]; then
			jobids=("${running_jobids[@]}")
		elif [[ -z "${jobid:-}" ]] && [[ -t 0 ]]; then # stdin is a terminal
			echo "No job ID provided, showing all running jobs:"
			echo
			echo "${jobinfos}"
			echo
			PS3="Select a job to stop: "
			select jobid in "${running_jobids[@]}"; do
				[[ -n "${jobid:-}" ]] && echo "Selected job: ${jobid}" && jobids+=("${jobid}") && break
			done
		fi
	fi

	if [[ "${#jobids[@]}" -eq 0 ]]; then
		log WARN "No jobs to stop"
		return 1
	fi

	# Cancel any jobs that were launched:
	for jobid in "${jobids[@]}"; do
		stop_hyakvnc_session "${stop_hyakvnc_session_args[@]}" "${jobid}" && log INFO "Stopped job ${jobid}"
	done
	return 0
}

! (return 0 2>/dev/null) && cmd_stop "$@"
