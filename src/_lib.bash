#! /usr/bin/env bash
# hyakvnc utility functions

# shellcheck disable=SC2292
[ -n "${_HYAKVNC_LIB_LOADED:-}" ] && return 0 # Return if already loaded


# Only enable these shell behaviours if we're not being sourced
if ! (return 0 2>/dev/null); then
	set -EuT -o pipefail
	shopt -s inherit_errexit
fi


function hyakvnc_module_init_config() {
	local module="${1:-${HYAKVNC_MODULE:-}}"
	[[ -z "${module}" ]] && { log ERROR "Module not specified"; return 1; }
	local init_func="m_${module//-/_}_init_config"
	declare -F "${init_func}" >/dev/null || { log ERROR "Could not find initialization function for module \"${module}"\"; return 1; }
	"${init_func}" || { log ERROR "Failed to initialize module \"${module}\""; return 1; }
}


function hyakvnc_init() {
	[[ -n "${HYAKVNC_MODULE:-}" ]] && HYAKVNC_MODULE=$(hyakvnc_guess_module) || { log ERROR "Couldn't guess module"; return 1; }
	hyakvnc_init_config || { log ERROR "Couldn't initialize configuration"; return 1; }
	hyakvnc_load_config || { log ERROR "Couldn't load configuration"; return 1; }
	hyakvnc_module_init_config || { log ERROR "Couldn't initialize module configuration"; return 1; }
	hyakvnc_load_config || { log ERROR "Couldn't load configuration"; return 1; }
	hyakvnc_autoupdate || { log WARN "Couldn't check for updates"; }
#	[[ -n "${!HYAKVNC_@}" ]] && export "${!HYAKVNC_@}" # Export all HYAKVNC_ variables
#	[[ -n "${!SBATCH_@}" ]] && export "${!SBATCH_@}" # Export all SBATCH_ variables
#	[[ -n "${!APPTAINER_@}" ]] && export "${!SLURM_@}" # Export all APPTAINER_ variables
#	[[ -n "${!SINGULARITY_@}" ]] && export "${!SINGULARITY_@}" # Export all APPTAINER_ variables
}

	

function hyakvnc_init_config() {
	HYAKVNC_DIR="${HYAKVNC_DIR:-${HOME}/.hyakvnc}"                                                        # %% Local directory to store application. default:$HOME/.hyakvnc
	HYAKVNC_CONFIG_FILE="${HYAKVNC_DIR}/hyakvnc-config.sh"                                                # %% Configuration file to use. default: $HYAKVNC_DIR/hyakvnc-config.sh
	HYAKVNC_REPO_DIR="${HYAKVNC_REPO_DIR:-${HYAKVNC_DIR}/hyakvnc}"                                        # %% Local directory to store git repository. default: $HYAKVNC_DIR/hyakvnc
	HYAKVNC_CHECK_UPDATE_FREQUENCY="${HYAKVNC_CHECK_UPDATE_FREQUENCY:-0}"                                 # %% How often to check for updates in `[d]`ays or `[m]`inutes; use `0` for every time, `-1` to disable`, 1d` for daily, `10m` for every 10 minutes, etc. default: 0
	HYAKVNC_LOG_FILE="${HYAKVNC_LOG_FILE:-${HYAKVNC_DIR}/hyakvnc.log}"                                    # %% Log file to use. default: $HYAKVNC_DIR/hyakvnc.log
	HYAKVNC_LOG_LEVEL="${HYAKVNC_LOG_LEVEL:-INFO}"                                                        # %% Log level to use for interactive output. default: INFO
	HYAKVNC_LOG_FILE_LEVEL="${HYAKVNC_LOG_FILE_LEVEL:-DEBUG}"                                             # %% Log level to use for log file output. default: DEBUG
	HYAKVNC_DEFAULT_TIMEOUT="${HYAKVNC_DEFAULT_TIMEOUT:-30}"                                              # %% Seconds to wait for most commands to complete before timing out. default: 30
	HYAKVNC_JOB_PREFIX="${HYAKVNC_JOB_PREFIX:-hyakvnc-}"                                                  # %% Prefix to use for hyakvnc SLURM job names. default: hyakvnc-
	HYAKVNC_JOB_SUBMIT_TIMEOUT="${HYAKVNC_JOB_SUBMIT_TIMEOUT:-120}"                                       # %% Seconds after submitting job to wait for the job to start before timing out. default: 120

	# :%% VNC preferences
	HYAKVNC_VNC_PASSWORD="${HYAKVNC_VNC_PASSWORD:-password}"                                              # %% Password to use for new VNC sessions. default: password
	HYAKVNC_VNC_DISPLAY="${HYAKVNC_VNC_DISPLAY:-:10}"                                                     # %% VNC display to use. default: :10

	HYAKVNC_MODULE="${HYAKVNC_MODULE:-}"                                                                  # %% Module to load before launching VNC session. default: none
}


function check_bash_version() {
	if [ -z "${BASH_VERSION:-}" ] || [ "${BASH_VERSINFO:-0}" -lt 4 ] || { [ "${BASH_VERSINFO:-0}" -eq 4 ] && [ "${BASH_VERSINFO[1]:-0}" -lt 4 ] ;}; then
		echo >&2 "Requires Bash version > 4.x"; return 1
	else
		return 0
	fi
}

# shellcheck disable=SC1090
function hyakvnc_load_config() {
	if [[ -n "${HYAKVNC_CONFIG_FILE:-}" ]] && [[ -f "${HYAKVNC_CONFIG_FILE:-}" ]] && [[ -r "${HYAKVNC_CONFIG_FILE:-}" ]]; then
		# shellcheck source=/dev/null
		source "${HYAKVNC_CONFIG_FILE:-}" 2>/dev/null || { log ERROR "Couldn't load configuration file ${HYAKVNC_CONFIG_FILE:-}"; return 1; }
	else
		return 0
	fi
}

# shellcheck disable=SC2120 # Ignore unused arguments
function hyakvnc_describe_config() {
	check_command sed ERROR || return 1
	sed -E '/^\s*HYAKVNC_.*#\s*%%/!d; s/\.\s*default:.*$//; s/([^=]+)=.*#+\s*%+\s*(.*)$/\1=\2/g' "${1:-${BASH_SOURCE[0]}}"
}

# shellcheck disable=SC2034 # Unused variables left for documentation purposes
declare -A Hyakvnc_Config_Descriptions # Declare Hyakvnc_Config_Descriptions array
function hyakvnc_init_config_descriptions() {
	while IFS= read -r line; do
		key="${line%%=*}" value="${line##*=}"
		# shellcheck disable=SC2034 # Unused variables left for documentation purposes
		Hyakvnc_Config_Descriptions["${key}"]="${value}"
	done < <(hyakvnc_describe_config || true)
}

# check_command()
# Check if a command is available
# Arguments:
# - <command> - The command to check
# - <loglevel> <message> - Passed to log if the command is not available (optional)
function check_command() {
	if [[ -z "${1:-}" ]] || ! command -v "${1}" >/dev/null 2>&1; then
		if [[ $# -gt 1 ]]; then
			log "${@:2}" || echo >&2 "${@:2}" || true # If log fails, print to stderr
			return 1
		fi
	fi
	return 0
}

# ## Log levels for log() function:
declare -A Log_Levels Log_Level_Colors # Declare Log_Levels and Log_Level_Colors arrays
Log_Levels=(["OFF"]=0 ["CRITICAL"]=1 ["ERROR"]=2 ["WARN"]=3 ["INFO"]=4 ["DEBUG"]=5 ["TRACE"]=6 ["ALL"]=100)
Log_Level_Colors=(["CRITICAL"]=5 ["ERROR"]=1 ["WARN"]=3 ["INFO"]=4 ["DEBUG"]=6 ["TRACE"]=2)

# # Utility functions
function set_log_level() {
	[[ -n "${Log_Levels[${1:-}]:-}" ]] || { log ERROR "Invalid log level: ${1:-}"; return 1; }
	export HYAKVNC_LOG_LEVEL="${1:-}"
	return 0
}

# check_log_level()
# Check if the current log level is high enough to log a message
# Arguments: <level>
function check_log_level() {
	local level levelno refloglevel refloglevelno
	level="${1:-INFO}"
	refloglevel="${2:-${HYAKVNC_LOG_LEVEL:-INFO}}"
	[[ -z "${levelno:=${Log_Levels[${level}]}}" ]] && {
		echo >&2 "log(): Unknown log level: ${level}"
		return 1
	}
	[[ -z "${refloglevelno:=${Log_Levels[${refloglevel}]}}" ]] && {
		echo >&2 "log() Unknown log level: ${refloglevel}"
		return 1
	}
	[[ "${levelno}" -lt "${refloglevelno}" ]] && return 1
	return 0
}

# log()
# Log a message to the stderr and the log file if the log level is high enough
# Arguments: <level> <message>
# 	<level> is the log level, e.g. INFO, WARN, ERROR, etc. (default: INFO)
#	<message> is the message to log (default: empty string)
#
# Environment variables:
#	$HYAKVNC_LOG_LEVEL - The log level to use for interactive output (default: INFO)
#	$HYAKVNC_LOG_FILE - The log file to use (default: $HYAKVNC_DIR/hyakvnc.log)
#  	$HYAKVNC_LOG_FILE_LEVEL - The log level to use for log file output (default: DEBUG)
function log() {
	local level levelno colorno curlevelno curlogfilelevelno ctx logfilectx curloglevel curlogfilelevel newline continueline
	newline="\n"
	[[ "${1:-}" == "-n" ]] && {
		newline=''
		shift
	}

	[[ "${1:-}" == "-c" ]] && {
		continueline=1
		shift
	}

	[[ -z "${level:=${1:-}}" ]] && {
		echo >&2 "log(): No log level set"
		return 1
	}
	shift

	[[ -z "${levelno:=${Log_Levels[${level}]}}" ]] && {
		echo >&2 "log(): Unknown log level: ${level}"
		return 1
	}
	curloglevel="${HYAKVNC_LOG_LEVEL:-INFO}"

	[[ -z "${curlevelno:=${Log_Levels[${curloglevel}]}}" ]] && {
		echo >&2 "log() Unknown interactive log level: ${curloglevel}"
		return 1
	}

	curlogfilelevel="${HYAKVNC_LOG_FILE_LEVEL:-DEBUG}"
	[[ -z "${curlogfilelevelno:=${Log_Levels[${curlogfilelevel:-}]}}" ]] && {
		echo >&2 "log() Unknown logfile log level: ${curlogfilelevel}"
		return 1
	}

	colorno="${Log_Level_Colors[${level}]}"

	if [[ "${levelno}" -ge "${Log_Levels[DEBUG]}" ]] || [[ "${levelno}" -le "${Log_Levels[CRITICAL]}" ]]; then
		ctx=" [${BASH_SOURCE[1]##*/}:${BASH_LINENO[1]} in ${FUNCNAME[1]:-}()]"
	fi

	if [[ "${curlogfilelevelno}" -ge "${Log_Levels[DEBUG]}" ]] || [[ "${curlogfilelevelno}" -le "${Log_Levels[CRITICAL]}" ]]; then
		logfilectx=" [${BASH_SOURCE[1]##*/}:${BASH_LINENO[1]} in ${FUNCNAME[1]:-}()]"
	fi

	if [[ "${curlevelno}" -ge "${levelno}" ]]; then
		# If we're in a terminal, use colors:
		if [[ -z "${continueline:-}" ]]; then
			[[ -t 0 ]] && { tput setaf "${colorno:-}" 2>/dev/null || true; }
			printf "%s%s: " "${level:-}" "${ctx:- }" >&2 || true
			[[ -t 0 ]] && { tput sgr0 2>/dev/null || true; }
		fi

		# Print the rest of the message without colors:
		printf "%s%b" "${*-}" "${newline:-}" >&2 || true
	fi

#	if [[ "${curlogfilelevelno}" -ge "${levelno}" ]] && [[ -n "${HYAKVNC_LOG_FILE:-}" ]] && [[ -w "${HYAKVNC_LOG_FILE:-}" ]]; then
#		if [[ -z "${continueline:-}" ]]; then
#			printf "%s %s%s: " "$(date +'%F %T')" "${level:-}" "${logfilectx:- }" >&2 >>"${HYAKVNC_LOG_FILE}" || true
#		fi

#		printf "%s%b" "${*-}%s" "${newline:-}" >&2 >>"${HYAKVNC_LOG_FILE}" || true
#	fi
}

# ## Update functions:

# hyakvnc_pull_updates()
# Pull updates from the hyakvnc git repository
# Arguments: None
# Returns: 0 if successfuly updated, 1 if not or if an error occurred
function hyakvnc_pull_updates() {
	local cur_branch
	[[ -z "${HYAKVNC_REPO_DIR:-}" ]] && {
		log ERROR "HYAKVNC_REPO_DIR is not set. Can't pull updates."
		return 1
	}
	cur_branch="$(git -C "${HYAKVNC_REPO_DIR}" branch --show-current 2>&1 || true)"
	[[ -z "${cur_branch}" ]] && {
		log ERROR "Couldn't determine current branch. Can't pull updates."
		return 1
	}

	[[ "${cur_branch}" != "main" ]] && {
		log WARN "Current branch is ${cur_branch}, not main. Be warned that this branch may not be up to date."
	}

	log INFO "Updating hyakvnc..."
	git -C "${HYAKVNC_REPO_DIR}" pull --quiet origin "${cur_branch}" || {
		log WARN "Couldn't apply updates"
		return 0
	}

	log INFO "Successfully updated hyakvnc."
	return 0
}

# hyakvnc_check_updates()
# Check if a hyakvnc update is available
# Arguments: None
# Returns: 0 if an update is available, 1 if none or if an error occurred
function hyakvnc_check_updates() {
	log DEBUG "Checking for updates... "
	# Check if git is installed:
	check_command git ERROR || return 1

	# Check if git is available and that the git directory is a valid git repository:
	git -C "${HYAKVNC_REPO_DIR}" tag >/dev/null 2>&1 || {
		log DEBUG "Configured git directory ${HYAKVNC_REPO_DIR} doesn't seem to be a valid git repository. Can't check for updates"
		return 1
	}

	local cur_branch
	cur_branch="$(git -C "${HYAKVNC_REPO_DIR}" branch --show-current 2>&1 || true)"
	[[ -z "${cur_branch}" ]] && {
		log ERROR "Couldn't determine current branch. Can't pull updates."
		return 1
	}

	[[ "${cur_branch}" != "main" ]] && {
		log WARN "Current branch is ${cur_branch}, not main. Be warned that this branch may not be up to date."
	}

	local cur_date
	cur_date="$(git -C "${HYAKVNC_REPO_DIR}" show -s --format=%cd --date=human-local "${cur_branch}" || echo ???)"
	log INFO "The installed version was published ${cur_date}"

	touch "${HYAKVNC_REPO_DIR}/.last_update_check"

	# Get hash of local HEAD:
	if [[ "$(git -C "${HYAKVNC_REPO_DIR}" rev-parse "${cur_branch}" || true)" == "$(git -C "${HYAKVNC_REPO_DIR}" ls-remote --heads --refs origin "${cur_branch}" | cut -f1 || true)" ]]; then
		log INFO "hyakvnc is up to date."
		return 1
	fi

	git -C "${HYAKVNC_REPO_DIR}" fetch --quiet origin "${cur_branch}" || {
		log DEBUG "Failed to fetch from remote"
		return 1
	}

	local nchanges
	nchanges="$(git -C "${HYAKVNC_REPO_DIR}" rev-list HEAD...origin/"${cur_branch}" --count || echo 0)"
	if [[ "${nchanges}" -gt 0 ]]; then
		local new_date
		new_date="$(git -C "${HYAKVNC_REPO_DIR}" show -s --format=%cd --date=human-local origin/"${cur_branch}" || echo ???)"
		log INFO "Found ${nchanges} updates. Most recent: ${new_date}"
		return 0
	fi
	return 1
}

# hyakvnc_autoupdate()
# Unless updates were checked recenetly per $HYAKVNC_CHECK_UPDATE_FREQUENCY,
# 	check if a hyakvnc update is available. If running interactively, prompt
#	to apply update (or disable prompt in the future). If not running interactively,
#	apply the update.
# Arguments: None
# Returns: 0 if an update is available and the user wants to update, 1 if none or if an error occurred
function hyakvnc_autoupdate() {
	if [[ "${HYAKVNC_CHECK_UPDATE_FREQUENCY:-0}" == "-1" ]]; then
		log DEBUG "Skipping update check"
		return 1
	fi

	if [[ "${HYAKVNC_CHECK_UPDATE_FREQUENCY:-0}" != "0" ]]; then
		local update_frequency_unit="${HYAKVNC_CHECK_UPDATE_FREQUENCY:0-1}"
		local update_frequency_value="${HYAKVNC_CHECK_UPDATE_FREQUENCY:0:-1}"
		local find_m_arg=()

		case "${update_frequency_unit:=d}" in
			d)
				find_m_arg+=(-mtime "+${update_frequency_value:=0}")
				;;
			m)
				find_m_arg+=(-mmin "+${update_frequency_value:=0}")
				;;
			*)
				log ERROR "Invalid update frequency unit: ${update_frequency_unit}. Please use [d]ays or [m]inutes."
				return 1
				;;
		esac

		log DEBUG "Checking if ${HYAKVNC_REPO_DIR}/.last_update_check is older than ${update_frequency_value}${update_frequency_unit}..."

		if [[ -r "${HYAKVNC_REPO_DIR}/.last_update_check" ]] && [[ -z $(find "${HYAKVNC_REPO_DIR}/.last_update_check" -type f "${find_m_arg[@]}" -print || true) ]]; then
			log DEBUG "Skipping update check because the last check was less than ${update_frequency_value}${update_frequency_unit} ago."
			return 1
		fi

		log DEBUG "Checking for updates because the last check was more than ${update_frequency_value}${update_frequency_unit} ago."
	fi

	hyakvnc_check_updates || {
		log DEBUG "No updates found."
		return 1
	}

	if [[ -t 0 ]]; then # Check if we're running interactively
		while true; do # Ask user if they want to update
			local choice
			read -r -p "Would you like to update hyakvnc? [y/n] [x to disable]: " choice
			case "${choice}" in
				y | Y | yes | Yes)
					log INFO "Updating hyakvnc..."
					hyakvnc_pull_updates || {
						log WARN "Didn't update hyakvnc"
						return 0
					}
					log INFO "Successfully updated hyakvnc. Restarting..."
					echo
					exec "${0}" "$@" # Restart hyakvnc
					;;
				n | N | no | No)
					log INFO "Not updating hyakvnc"
					return 0
					;;
				x | X)
					log INFO "Disabling update checks"
					export HYAKVNC_CHECK_UPDATE_FREQUENCY="-1"
					if [[ -n "${HYAKVNC_CONFIG_FILE:-}" ]]; then
						touch "${HYAKVNC_CONFIG_FILE}" && echo 'HYAKVNC_CHECK_UPDATE_FREQUENCY=-1' >>"${HYAKVNC_CONFIG_FILE}"
						log INFO "Set HYAKVNC_CHECK_UPDATE_FREQUENCY=-1 in ${HYAKVNC_CONFIG_FILE}"
					fi
					return 0
					;;
				*)
					echo "Please enter y, n, or x"
					;;
			esac
		done
	else
		hyakvnc_pull_updates || {
			log INFO "Didn't update hyakvnc"
			return 0
		}
	fi
	return 0
}

# ## General utility functions:

# hyakvnc_config_init()
# Initialize the hyakvnc configuration
# Arguments: None
function hyakvnc_config_init() {
	# Create the hyakvnc directory if it doesn't exist:
	mkdir -p "${HYAKVNC_DIR}/jobs" || {
		log ERROR "Failed to create directory ${HYAKVNC_DIR}"
		return 1
	}

	if [[ -z "${HYAKVNC_MODE:-}" ]]; then
		if check_slurm_running; then
			HYAKVNC_MODE="slurm"
		elif check_command apptainer; then
			HYAKVNC_MODE="local"
			log DEBUG "Found Apptainer - Running hyakvnc in local mode"
		else
			log ERROR "Neither SLURM nor Apptainer are installed. Can't run hyakvnc because there's nowhere to launch the container."
			return 1
		fi
	fi
	if [[ -z "${HYAKVNC_APPTAINER_ADD_BINDPATHS:-}" ]]; then
		local d
		for d in /gscratch /data; do
			[[ -d "${d:-}" ]] && HYAKVNC_APPTAINER_ADD_BINDPATHS+="${d},"
		done
		HYAKVNC_APPTAINER_ADD_BINDPATHS="${HYAKVNC_APPTAINER_ADD_BINDPATHS%,}" # Remove trailing comma
		log TRACE "Set HYAKVNC_APPTAINER_ADD_BINDPATHS=\"${HYAKVNC_APPTAINER_ADD_BINDPATHS}\""
	fi

	if [[ "${HYAKVNC_MODE:-}" == "slurm" ]]; then
		check_slurm_running || { log ERROR "SLURM is not running. Can't run hyakvnc in SLURM mode."; return 1; }

		# Set default SLURM cluster, account, and partition if empty:
		if [[ -z "${HYAKVNC_SLURM_CLUSTER:-}" ]]; then
			HYAKVNC_SLURM_CLUSTER="$(slurm_list_clusters --max-count 1 || true)"
			[[ -z "${HYAKVNC_SLURM_CLUSTER:-}" ]] && { log ERROR "Failed to get default SLURM cluster"; return 1; }
			SBATCH_CLUSTERS="${HYAKVNC_SLURM_CLUSTER:-}" && log TRACE "Set SBATCH_CLUSTERS=\"${SBATCH_CLUSTERS}\""
		fi

		if [[ -z "${HYAKVNC_SLURM_ACCOUNT:-}" ]]; then
			HYAKVNC_SLURM_ACCOUNT="$(slurm_get_default_account --cluster "${HYAKVNC_SLURM_CLUSTER:-}" || true)"
			[[ -z "${HYAKVNC_SLURM_ACCOUNT:-}" ]] && { log ERROR "Failed to get default SLURM account"; return 1; }
			SBATCH_ACCOUNT="${HYAKVNC_SLURM_ACCOUNT:-}" && log TRACE "Set SBATCH_ACCOUNT=\"${SBATCH_ACCOUNT:-}\""
		fi

		if [[ -z "${HYAKVNC_SLURM_PARTITION:-}" ]]; then
			HYAKVNC_SLURM_PARTITION="$(slurm_list_partitions --account "${HYAKVNC_SLURM_ACCOUNT:-}" --cluster "${HYAKVNC_SLURM_CLUSTER:-}" --max-count 1 || true)" ||
				{ log ERROR "Failed to get SLURM partitions for user \"${USER:-}\" on account \"${HYAKVNC_SLURM_ACCOUNT:-}\" on cluster \"${HYAKVNC_SLURM_CLUSTER:-}\""; return 1; }
			SBATCH_PARTITION="${HYAKVNC_SLURM_PARTITION:-}" && log TRACE "Set SBATCH_PARTITION=\"${SBATCH_PARTITION:-}\""
		fi

		if [[ -z "${HYAKVNC_APPTAINER_ADD_BINDPATHS:-}" ]]; then
			local d
			for d in /gscratch /data; do
				[[ -d "${d}" ]] && HYAKVNC_APPTAINER_ADD_BINDPATHS+="${d},"
			done
			HYAKVNC_APPTAINER_ADD_BINDPATHS="${HYAKVNC_APPTAINER_ADD_BINDPATHS%,}" # Remove trailing comma
			log TRACE "Set HYAKVNC_APPTAINER_ADD_BINDPATHS=\"${HYAKVNC_APPTAINER_ADD_BINDPATHS}\""
		fi

	elif
		[[ "${HYAKVNC_MODE:-}" == "local" ]]; then
		check_command apptainer ERROR || { log ERROR "Apptainer is not installed. Can't run hyakvnc in local mode."; return 1; }
	else
		log ERROR "Invalid HYAKVNC_MODE: \"${HYAKVNC_MODE:-}\""
		return 1
	fi

	[[ -n "${!HYAKVNC_@}" ]] && export "${!HYAKVNC_@}" # Export all HYAKVNC_ variables
	[[ -n "${!SBATCH_@}" ]] && export "${!SBATCH_@}" # Export all SBATCH_ variables
	[[ -n "${!SLURM_@}" ]] && export "${!SLURM_@}" # Export all SLURM_ variables

	return 0
}

# stop_hyakvnc_session()
# Stop a Hyak VNC session, given a job ID
# Arguments: <jobid> [ -c | --cancel ] [ --no-rm ]
function stop_hyakvnc_session() {
	local jobid should_cancel no_rm
	while true; do
		case ${1:-} in
			-c | --cancel)
				shift
				should_cancel=1
				;;
			--no-rm) # Don't remove the job directory
				shift
				no_rm=1
				;;
			*)
				jobid="${1:-}"
				break
				;;
		esac
	done

	[[ -z "${jobid}" ]] && {
		log ERROR "Job ID must be specified"
		return 1
	}
	log DEBUG "Stopping VNC session for job ${jobid}"
	local jobdir pid tmpdirname
	jobdir="${HYAKVNC_DIR}/jobs/${jobid}"
	if [[ -d "${jobdir}" ]]; then
		local pidfile
		for pidfile in "${jobdir}/vnc/"*"${HYAKVNC_VNC_DISPLAY}".pid; do
			if [[ -r "${pidfile:-}" ]]; then
				read -r pid <"${pidfile}"
				[[ -z "${pid:-}" ]] && {
					log WARN "Failed to get pid from ${pidfile}"
					break
				}
				srun --jobid "${jobid}" kill "${pid}" || log WARN "srun failed to stop VNC process for job ${jobid} with pid ${pid}"
				break
			fi
		done
		if [[ -r "${jobdir}/tmpdirname" ]]; then
			read -r tmpdirname <"${pidfile}"
			[[ -z "${tmpdirname}" ]] && log WARN "Failed to get tmpdirname from ${jobdir}/tmpdirname"
			srun --quiet --jobid "${jobid}" rm -rf "${tmpdirname}" || log WARN "Failed to remove container /tmp directory at ${tmpdirname} job ${jobid}"
		fi
		[[ -n "${no_rm}" ]] || rm -rf "${jobdir}" && log DEBUG "Removed VNC directory ${jobdir}"
	else
		log WARN "Job directory ${jobdir} does not exist"
	fi

	if [[ -n "${should_cancel}" ]]; then
		log INFO "Cancelling job ${jobid}"
		sleep 1 # Wait for VNC process to exit
		scancel --full "${jobid}" || log ERROR "scancel failed to cancel job ${jobid}"
	fi
	return 0
}

# print_connection_info()
# Print connection instructions for a job, given job ID
# Arguments: -j | --jobid <jobid> (required) [ -p | --viewer-port <viewer_port> ] [ -n |--node <node> ] [ -s | --ssh-host <ssh_host> ]
#
# The generated connection string should look like this, depending on the the OS:
# ssh -f -L 6111:'/mmfs1/home/altan/.hyakvnc/jobs/14930429/socket.uds' -J altan@klone.hyak.uw.edu altan@g3071 sleep 10; vncviewer localhost:6111
function print_connection_info() {
	local jobid jobdir node socket_path viewer_port launch_hostname ssh_host
	viewer_port="${HYAKVNC_LOCALHOST_PORT:-5901}"
	ssh_host="${HYAKVNC_SSH_HOST:-klone.hyak.uw.edu}"
	# Parse arguments:
	while true; do
		case ${1:-} in
			-j | --jobid)
				shift
				jobid="${1:-}"
				shift
				;;
			-p | --viewer-port)
				shift
				viewer_port="${1:-viewer_port}"
				shift
				;;
			-n | --node)
				shift
				node="${1:-}"
				shift
				;;
			-s | --ssh-host)
				shift
				ssh_host="${1:-}"
				shift
				;;
			-*)
				log ERROR "Unknown option for print_connection_info: ${1:-}\n"
				return 1
				;;
			*)
				break
				;;
		esac
	done

	# Check arguments:
	[[ -z "${jobid}" ]] && {
		log ERROR "Job ID must be specified"
		return 1
	}
	[[ -z "${viewer_port}" ]] && {
		log ERROR "Viewer port must be specified"
		return 1
	}
	[[ -z "${ssh_host}" ]] && {
		log ERROR "SSH host must be specified"
		return 1
	}

	# Check that the job directory exists
	[[ -d "${jobdir:=${HYAKVNC_DIR}/jobs/${jobid}}" ]] || {
		log ERROR "Job directory ${jobdir} does not exist"
		return 1
	}

	[[ -e "${socket_path:=${HYAKVNC_DIR}/jobs/${jobid}/vnc/socket.uds}" ]] || {
		log ERROR "Socket file ${socket_path} does not exist"
		return 1
	}
	[[ -S "${socket_path}" ]] || {
		log ERROR "Socket file ${socket_path} is not a socket"
		return 1
	}
	[[ -n "${node:-}" ]] || node=$(squeue -h -j "${jobid}" -o '%N' | grep -o -m 1 -E '\S+')
	[[ -n "${node:-}" ]] || log DEBUG "Failed to get node for job ${jobid} from squeue"
	if [[ -r "${HYAKVNC_DIR}/jobs/${jobid}/vnc/hostname" ]] && launch_hostname=$(cat "${HYAKVNC_DIR}/jobs/${jobid}/vnc/hostname" 2>/dev/null || true) && [[ -n "${launch_hostname:-}" ]]; then
		[[ "${node}" = "${launch_hostname}" ]] || log WARN "Node for ${jobid} from hostname file (${HYAKVNC_DIR}/jobs/${jobid}/vnc/hostname) (${launch_hostname:-}) does not match node from squeue (${node}). Was the job restarted?"
		[[ -z "${node}" ]] && {
			log DEBUG "Node for ${jobid} from squeue is blank. Setting to ${launch_hostname}"
			node="${launch_hostname}"
		}
	else
		log WARN "Failed to get originally launched node for job ${jobid} from ${HYAKVNC_DIR}/jobs/${jobid}/hostname"
	fi

	[[ -z "${node}" ]] && {
		log ERROR "No node identified for job ${jobid}"
		return 1
	}

	local ssh_args
	ssh_args=()
	ssh_args+=("-o StrictHostKeyChecking=no")
	ssh_args+=("-L" "${viewer_port}:${socket_path}")
	ssh_args+=("-J" "${USER}@${HYAKVNC_SSH_HOST}")
	ssh_args+=("${USER}@${node}")

	# Print connection instruction header:

	cat <<EOF
==========
Copy and paste these instructions into a command line terminal on your local machine to connect to the VNC session.
You may need to install a VNC client if you don't already have one.

NOTE: If you receive an error that looks like "Permission denied (publickey,gssapi-keyex,gssapi-with-mic)", you don't have an SSH key set up. See https://hyak.uw.edu/docs/setup/intracluster-keys for more information. To set this up quickly on Linux, macOS, or Windows (WSL2/Cygwin), open a new terminal window on your machine and enter the following 2 commands before you try again:

[ ! -r ~/.ssh/id_rsa ] && ssh-keygen -t rsa -b 4096 -N '' -C "${USER}@uw.edu" -f ~/.ssh/id_rsa
ssh-copy-id -o StrictHostKeyChecking=no ${USER}@klone.hyak.uw.edu
---------
EOF
	# Print connection instructions for each operating system:
	echo "LINUX TERMINAL (bash/zsh):"
	echo "ssh -f ${ssh_args[*]} sleep 20 && vncviewer localhost:${viewer_port} || xdg-open vnc://localhost:${viewer_port} || echo 'No VNC viewer found. Please install one or try entering the connection information manually.'"
	echo

	echo "MACOS TERMINAL"
	printf "ssh -f %s sleep 20 && " "${ssh_args[*]}"
	# Print a command to open a VNC viewer for each bundle ID:
	HYAKVNC_MACOS_VNC_VIEWER_BUNDLEIDS=(com.turbovnc.vncviewer.VncViewer com.realvnc.vncviewer com.tigervnc.vncviewer)
	for bundleid in "${HYAKVNC_MACOS_VNC_VIEWER_BUNDLEIDS[@]}"; do
		printf "open -b %s --args localhost:%s 2>/dev/null || " "${bundleid}" "${viewer_port}"
	done

	# Try default VNC viewer built into macOS:
	printf "open vnc://localhost:%s 2>/dev/null || " "${viewer_port}"

	# And finally, print a command to warn the user if no VNC viewer was found:
	printf "echo 'No VNC viewer found. Please install one or try entering the connection information manually.'\n"
	echo

	echo "WINDOWS"
	echo "ssh -f ${ssh_args[*]} sleep 20 && cmd.exe /c cmd /c \"\$(cmd.exe /c where \"C:\Program Files\TurboVNC;C:\Program Files (x86)\TurboVNC:vncviewerw.bat\")\" localhost:${viewer_port} || echo 'No VNC viewer found. Please install one or try entering the connection information manually.'"
	echo
	echo "=========="

}

COMMANDS="create status stop show config update install help"

TITLE="hyakvnc -- A tool for launching VNC sessions on Hyak."

# show_usage()
function show_usage() {
	local isinstalled
	isinstalled=$(command -v hyakvnc || echo '')
	[[ -n "${isinstalled:-}" ]] && isinstalled=" (is already installed!)"

	cat <<EOF
Usage: hyakvnc [hyakvnc options] [${COMMANDS// /|}] [command options] [args...]

Description:
	Stop a provided HyakVNC sesssion and clean up its job directory

Options:
	-h, --help		Show this help message and exit
	-d, --debug		Print debugging information
	-V, --version	Print version information and exit

Available commands:
	create	Create a new VNC session
	status	Check status of VNC session(s)
	stop	Stop a VNC session
	show	Show connection information for a VNC session
	config	Show current configuration for hyakvnc
	update	Update hyakvnc
	install	Install hyakvnc so the "hyakvnc" command can be run from anywhere.${isinstalled:-}
	help	Show help for a command

See 'hyakvnc help <command>' for more information on a specific command.

EOF
}

# help_help()
function help_help() {
	cat <<EOF
Show help for a command
Usage: hyakvnc [hyakvnc options] help <command>

Description:
	Show help for a command in hyakvnc

Options:
	-h, --help		Show this help message and exit
	-u, --usage		Print only usage information
	-V, --version	Print version information and exit
EOF
}

# cmd_help()
function cmd_help() {
	local action_to_help
	[[ $# == 0 ]] && {
		echo "${TITLE}"
		show_usage "$@"
		exit 0
	}

	while true; do
		case ${1:-} in
			-h | --help)
				help_help
				exit 0
				;;
			-u | --usage)
				shift
				show_usage "$@"
				exit 0
				;;
			*) break ;;
		esac
	done

	if [[ -r "${SCRIPTDIR}/${1:-}.bash" ]]; then
		action_to_help="${1:-}"
		shift
		"${SCRIPTDIR}/${action_to_help}.bash" --help "$@"

	else
		log ERROR "Can't show help for unknown command: \"${1:-}\". Available commands: ${COMMANDS}"
		echo
		show_usage "$@"
		exit 1
	fi

}
# help_update()
function help_update() {
	cat <<EOF
Update hyakvnc

Usage: hyakvnc update [update options...]
	
Description:
	Update hyakvnc.

Options:
	-h, --help			Show this help message and exit

Examples:
	# Update hyakvnc
	hyakvnc update
EOF
}

# cmd_update()
function cmd_update() {
	log INFO "Checking for updates..."
	if ! hyakvnc_check_updates; then
		log INFO "No updates to apply."
	else
		log INFO "Applying updates..."
		if ! hyakvnc_pull_updates; then
			log WARN "No updates applied."
			exit 1
		else
			log INFO "Update complete."
		fi
	fi
}
# help_config()
function help_config() {
	cat <<EOF
Show the current configuration for hyakvnc

Usage: hyakvnc config [config options...]
	
Description:
	Show the current configuration for hyakvnc, as set in the user configuration file at ${HYAKVNC_CONFIG_FILE}, in the current environment, or the default values set by hyakvnc.

Options:
	-h, --help		Show this help message and exit

Examples:
	# Show configuration
	hyakvnc config
EOF
}

# cmd_config()
function cmd_config() {
	# Parse arguments:
	while true; do
		case "${1:-}" in
			-h | --help)
				help_config
				return 0
				;;
			-*)
				help log ERROR "Unknown option for config: ${1:-}\n"
				return 1
				;;
			*)
				break
				;;
		esac
	done
	export -p | sed -E 's/^declare\s+-x\s+//; /^HYAKVNC_/!d'
	return 0
}

# shellcheck source=/dev/null
source "${BASH_SOURCE%/*}/modules/apptainer.bash"

# shellcheck source=/dev/null
source "${BASH_SOURCE%/*}/modules/klone.bash"

function hyakvnc_guess_module() {
	if check_klone; then
		echo "klone"
	elif check_command apptainer; then
		echo "apptainer"
	else
		log ERROR "Neither SLURM nor Apptainer are installed. Can't run hyakvnc because there's nowhere to launch the container."
		return 1
	fi
}

function hyakvnc_command() {
	local module="${HYAKVNC_MODULE:-}"
	[[ -z "${module}" ]] && { module=$(hyakvnc_guess_module) || log ERROR "Failed to determine module to use"; return 1; }
	(($# < 1)) || { log ERROR "No command specified"; return 1; }
	local func="m_${module}_$1"
	declare -F "${func}" >/dev/null || func="hyakvnc_cmd_$1"
	declare -F "${func}" >/dev/null || { log ERROR "Unknown command: ${1:-}"; return 1; }
	shift
	"${func}" "$@"
}


_HYAKVNC_LIB_LOADED=1
