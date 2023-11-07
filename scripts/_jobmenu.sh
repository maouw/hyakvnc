
	local -a jobids=()
	local -A jobnodes=()
	local -A jobstates=()
	local -A jobnames=()
	local -A jobruntimes=()
	local -A jobshortnames=()

	while IFS=';' read -r jobid state node runtime jobname; do
		[[ -n "${jobid:-}" ]] || continue
		jobids+=("${jobid}")
		[[ -n "${state:-}" ]] && jobstates["${jobid}"]="${state}"
		[[ -n "${node:-}" ]] && jobnodes["${jobid}"]="${node}"
		[[ -n "${runtime:-}" ]] && jobruntimes["${jobid}"]="${runtime}"
		[[ -n "${jobname:-}" ]] && jobnames["${jobid}"]="${jobname}"
		short_jobname="${jobname##${HYAKVNC_SLURM_JOB_PREFIX:-}}"
		[[ "${#short_jobname}" -gt 15 ]] && short_jobname="${short_jobname:: 12}..."
		[[ -n "${short_jobname:-}" ]] && jobshortnames["${jobid}"]="${short_jobname}"
	done < <(squeue "${squeue_args[@]}" | grep -E --only-matching "^[0-9_]\s+\S+\s+\S+\s+${HYAKVNC_SLURM_JOB_PREFIX:-}.*$" || true)

	if ! [[ -t 0 ]]; then
			local jobid
			echo "JobID\t(ShortJobName)\tState\tRuntime\tNode\tNotes"
			
			for jobid in "${jobids[@]}"; do
				jobname="${jobnames[${jobid}]:-<unnamed>}"
				short_jobname="${jobname##${HYAKVNC_SLURM_JOB_PREFIX:-}}"
				[[ "${#short_jobname}" -gt 15 ]] && short_jobname="${short_jobname:: 12}..."
				runtime="${jobruntimes[${jobid}]:-}"
				printf "%s\t%s\t%s\t%s\t%s\t%s\n" "${jobid}" "${short_jobname}" "${jobstates[${jobid}]:-<no state>}" "${runtime}" "${jobnodes[${jobid}]:-<no node>}"
				echo "(${short_jobname} ${runtime} (${jobstates[${jobid}]:-<no state>}) - ${jobid}"
			done
			[[ -z "${jobid:-}" ]] && {
				log WARN "Found no jobs with names that match the prefix \"\${HYAKVNC_SLURM_JOB_PREFIX}\""
				return 1
			}
			while read -r jobid; do
				echo "${jobid}"
			done < <(printf '%s\n' "${!jobnames[@]}" | sort -n)
			[[ -z "${jobid:-}" ]] && {
				log WARN "Found no jobs with names that match the prefix \"\${HYAKVNC_SLURM_JOB_PREFIX}\""
				return 1
			}

	if [[ -t 0 ]] && [[ "${HYAKVNC_DISABLE_TUI:-0}" != 1 ]] && check_command whiptail; then # stdin is a terminal
			local -a jobid_menu=()
			for jobid in "${jobids[@]}"; do
				jobid_menu+=("${jobid}" "(${jobshortnames[${jobid}]:-} ${jobruntimes[${jobid}]:-} (${jobstates[${jobid}]:-<no state>}")
			done
			if [[ "${HYAKVNC_DISABLE_TUI:-0}" != 1 ]] && check_command whiptail; then
				local jobid
				jobid="$(whiptail --title "HyakVNC" --menu "Select a job to show status for" 0 0 0 "${jobid_menu[@]}" 3>&1 1>&2 2>&3)" || {
					log WARN "No job selected"
					return 1
				}

				local jobmsg jobdir job_action_choice
				jobmsg="HyakVNC job ${jobid} is running on node ${jobnodes[${jobid}]:-<no node>}"
				[[ -n "${jobnames[${jobid}]:-}" ]] && jobmsg+="\nName: ${jobnames[${jobid}]}"
				[[ -n "${jobruntimes[${jobid}]:-}" ]] && jobmsg+="\nRuntime: ${jobruntimes[${jobid}]}"
				[[ -n "${jobstates[${jobid}]:-}" ]] && jobmsg+="\nState: ${jobstates[${jobid}]}"
				jobdir="${HYAKVNC_DIR:-}/jobs/${jobid}"
				
				if [[ -d "${jobdir:-}" ]]; then
					jobmsg+="\nJob directory: ${jobdir}"
				else
					jobmsg="${jobmsg}\nJob directory: ${jobdir} (WARNING: does not exist)"
				fi
				[[ -r "${jobdir}/vnc/socket.uds" ]] || jobmsg+="\nVNC SOCKET UNREADABLE"

				local -a job_actions=()
				local i=1
				job_actions+=( $((i++)) "Show connection info")
				job_actions+=( $((i++)) "Stop job")
				job_actions+=( $((i++)) "View log")

				job_action_choice="$(whiptail --title "HyakVNC" --menu "${jobmsg}" 0 0 0 "${job_actions[@]}" 3>&1 1>&2 2>&3)" || {
					log WARN "No action selected"
					return 1
				}

				case "${job_action_choice}" in
				1)
					print_connection_info -j "${jobid}" || {
						log ERROR "Failed to print connection info for job ${jobid}"
						return 1
					}
					;;
				2) # Stop job
					cmd_stop "${jobid}" || {
						log ERROR "Failed to stop job ${jobid}"
						return 1
					}
					;;
				3) # View log
					[[ -e "${jobdir}/vnc/vnc.log" ]] || {
						log WARN "Log file ${jobdir}/vnc/vnc.log does not exist"
						return 1
					}
					
					[[ -r "${jobdir}/vnc/vnc.log" ]] || {
						log WARN "Log file ${jobdir}/vnc/vnc.log is not readable"
						return 1
					}

					less +G "${jobdir}/vnc/vnc.log" || {
						log ERROR "Failed to view log for job ${jobid}"
						return 1
					}
					;; 
				*) log ERROR "Unknown job action: ${job_action_choice}"; return 1 ;;
				esac
		else
			local jobid
			echo "JobID\t(ShortJobName)\tState\tRuntime\tNode\tNotes"
			
			for jobid in "${jobids[@]}"; do
				jobname="${jobnames[${jobid}]:-<unnamed>}"
				short_jobname="${jobname##${HYAKVNC_SLURM_JOB_PREFIX:-}}"
				[[ "${#short_jobname}" -gt 15 ]] && short_jobname="${short_jobname:: 12}..."
				runtime="${jobruntimes[${jobid}]:-}"
				printf "%s\t%s\t%s\t%s\t%s\t%s\n" "${jobid}" "${short_jobname}" "${jobstates[${jobid}]:-<no state>}" "${runtime}" "${jobnodes[${jobid}]:-<no node>}"
				echo "(${short_jobname} ${runtime} (${jobstates[${jobid}]:-<no state>}) - ${jobid}"
			done
			[[ -z "${jobid:-}" ]] && {
				log WARN "Found no jobs with names that match the prefix \"\${HYAKVNC_SLURM_JOB_PREFIX}\""
				return 1
			}
			while read -r jobid; do
				echo "${jobid}"
			done < <(printf '%s\n' "${!jobnames[@]}" | sort -n)
			[[ -z "${jobid:-}" ]] && {
				log WARN "Found no jobs with names that match the prefix \"\${HYAKVNC_SLURM_JOB_PREFIX}\""
				return 1
			}
		fi
		fi
	fi



	

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

! (return 0 2>/dev/null) && cmd_status "$@"
