#! /usr/bin/env bash
# hyakvnc utility functions

export HYAKVNC_VERSION="0.3.1"

# shellcheck disable=SC2292
[ -n "${XDEBUG:-}" ] && set -x # Set XDEBUG to print commands as they are executed
# shellcheck disable=SC2292
[ -n "${BASH_VERSION:-}" ] || { echo "Requires Bash"; exit 1; }

# Check Bash version greater than 4:
if [[ "${BASH_VERSINFO:-0}" -lt 4 ]]; then
	echo "Requires Bash version > 4.x"
	exit 1
fi

# Check Bash version 4.4 or greater:
case "${BASH_VERSION:-0}" in
	4*) if [[ "${BASH_VERSINFO[1]:-0}" -lt 4 ]]; then
		echo "Requires Bash version > 4.x"
		exit 1
	fi ;;

	*) ;;
esac

set -o allexport # Export all variables

# ## App preferences:
HYAKVNC_DIR="${HYAKVNC_DIR:-${HOME}/.hyakvnc}"          # %% Local directory to store application data (default: `$HOME/.hyakvnc`)
HYAKVNC_CONFIG_FILE="${HYAKVNC_DIR}/hyakvnc-config.env" # %% Configuration file to use (default: `$HYAKVNC_DIR/hyakvnc-config.env`)
HYAKVNC_REPO_DIR="${HYAKVNC_REPO_DIR:-${HYAKVNC_DIR}/hyakvnc}"        # Local directory to store git repository (default: `$HYAKVNC_DIR/hyakvnc`)
HYAKVNC_CHECK_UPDATE_FREQUENCY="${HYAKVNC_CHECK_UPDATE_FREQUENCY:-0}" # %% How often to check for updates in `[d]`ays or `[m]`inutes (default: `0` for every time. Use `1d` for daily, `10m` for every 10 minutes, etc. `-1` to disable.)
HYAKVNC_LOG_FILE="${HYAKVNC_LOG_FILE:-${HYAKVNC_DIR}/hyakvnc.log}"    # %% Log file to use (default: `$HYAKVNC_DIR/hyakvnc.log`)
HYAKVNC_LOG_LEVEL="${HYAKVNC_LOG_LEVEL:-INFO}"                        # %% Log level to use for interactive output (default: `INFO`)
HYAKVNC_LOG_FILE_LEVEL="${HYAKVNC_LOG_FILE_LEVEL:-DEBUG}"             # %% Log level to use for log file output (default: `DEBUG`)
HYAKVNC_SSH_HOST="${HYAKVNC_SSH_HOST:-klone.hyak.uw.edu}"             # %% Default SSH host to use for connection strings (default: `klone.hyak.uw.edu`)
HYAKVNC_DEFAULT_TIMEOUT="${HYAKVNC_DEFAULT_TIMEOUT:-30}"              # %% Seconds to wait for most commands to complete before timing out (default: `30`)

# ## VNC preferences:
HYAKVNC_VNC_PASSWORD="${HYAKVNC_VNC_PASSWORD:-password}" # %% Password to use for new VNC sessions (default: `password`)
HYAKVNC_VNC_DISPLAY="${HYAKVNC_VNC_DISPLAY:-:10}"        # %% VNC display to use (default: `:1`)

HYAKVNC_MACOS_VNC_VIEWER_BUNDLEIDS="${HYAKVNC_MACOS_VNC_VIEWER_BUNDLEIDS:-com.turbovnc.vncviewer.VncViewer com.realvnc.vncviewer com.tigervnc.vncviewer}" # macOS bundle identifiers for VNC viewer executables (default: `com.turbovnc.vncviewer com.realvnc.vncviewer com.tigervnc.vncviewer`)

# ## Apptainer preferences:
HYAKVNC_APPTAINER_CONTAINERS_DIR="${HYAKVNC_APPTAINER_CONTAINERS_DIR:-}"                               # %% Directory to look for apptainer containers (default: (none))
HYAKVNC_APPTAINER_GHCR_ORAS_PRELOAD="${HYAKVNC_APPTAINER_GHCR_ORAS_PRELOAD:-1}"                        # %% Whether to preload SIF files from the ORAS GitHub Container Registry (default: `0`)
HYAKVNC_APPTAINER_BIN="${HYAKVNC_APPTAINER_BIN:-apptainer}"                                            # %% Name of apptainer binary (default: `apptainer`)
HYAKVNC_APPTAINER_CONTAINER="${HYAKVNC_APPTAINER_CONTAINER:-}"                                         # %% Path to container image to use (default: (none; set by `--container` option))
HYAKVNC_APPTAINER_APP_VNCSERVER="${HYAKVNC_APPTAINER_APP_VNCSERVER:-vncserver}"                        # %% Name of app in the container that starts the VNC session (default: `vncserver`)
HYAKVNC_APPTAINER_APP_VNCKILL="${HYAKVNC_APPTAINER_APP_VNCKILL:-vnckill}"                              # %% Name of app that cleanly stops the VNC session in the container (default: `vnckill`)
HYAKVNC_APPTAINER_WRITABLE_TMPFS="${HYAKVNC_APPTAINER_WRITABLE_TMPFS:-${APPTAINER_WRITABLE_TMPFS:-1}}" # %% Whether to use a writable tmpfs for the container (default: `1`)
HYAKVNC_APPTAINER_CLEANENV="${HYAKVNC_APPTAINER_CLEANENV:-${APPTAINER_CLEANENV:-1}}"                   # %% Whether to use a clean environment for the container (default: `1`)
HYAKVNC_APPTAINER_ADD_BINDPATHS="${HYAKVNC_APPTAINER_ADD_BINDPATHS:-}"                                 # %% Bind paths to add to the container (default: (none))
HYAKVNC_APPTAINER_ADD_ENVVARS="${HYAKVNC_APPTAINER_ADD_ENVVARS:-}"                                     #  %% Environment variables to add to before invoking apptainer (default: (none))
HYAKVNC_APPTAINER_ADD_ARGS="${HYAKVNC_APPTAINER_ADD_ARGS:-}"                                           #  %% Additional arguments to give apptainer (default: (none))

# ## Slurm preferences:
HYAKVNC_SLURM_JOB_PREFIX="${HYAKVNC_SLURM_JOB_PREFIX:-hyakvnc-}"    # %% Prefix to use for hyakvnc SLURM job names (default: `hyakvnc-`)
HYAKVNC_SLURM_SUBMIT_TIMEOUT="${HYAKVNC_SLURM_SUBMIT_TIMEOUT:-120}" # %% Seconds after submitting job to wait for the job to start before timing out (default: `120`)

HYAKVNC_SLURM_OUTPUT_DIR="${HYAKVNC_SLURM_OUTPUT_DIR:-${HYAKVNC_DIR}/slurm-output}"                      # %% Directory to store SLURM output files (default: `$HYAKVNC_DIR/slurm-output`)
HYAKVNC_SLURM_OUTPUT="${HYAKVNC_SLURM_OUTPUT:-${SBATCH_OUTPUT:-${HYAKVNC_SLURM_OUTPUT_DIR}/job-%j.out}}" # %% Where to send SLURM job output (default: `$HYAKVNC_SLURM_OUTPUT_DIR/job-%j.out`)

HYAKVNC_SLURM_JOB_NAME="${HYAKVNC_SLURM_JOB_NAME:-${SBATCH_JOB_NAME:-}}"            # %% What to name the launched SLURM job (default: (set according to container name))
HYAKVNC_SLURM_ACCOUNT="${HYAKVNC_SLURM_ACCOUNT:-${SBATCH_ACCOUNT:-}}"               # %% Slurm account to use (default: (autodetected))
HYAKVNC_SLURM_PARTITION="${HYAKVNC_SLURM_PARTITION:-${SBATCH_PARTITION:-}}"         # %% Slurm partition to use (default: (autodetected))
HYAKVNC_SLURM_CLUSTER="${HYAKVNC_SLURM_CLUSTER:-${SBATCH_CLUSTERS:-}}"              # %% Slurm cluster to use (default: (autodetected))
HYAKVNC_SLURM_GPUS="${HYAKVNC_SLURM_GPUS:-${SBATCH_GPUS:-}}"                        # %% Number of GPUs to request (default: (none))
HYAKVNC_SLURM_MEM="${HYAKVNC_SLURM_MEM:-${SBATCH_MEM:-4G}}"                         # %% Amount of memory to request, in [M]egabytes or [G]igabytes (default: `4G`)
HYAKVNC_SLURM_CPUS="${HYAKVNC_SLURM_CPUS:-4}"                                       # %% Number of CPUs to request (default: `4`)
HYAKVNC_SLURM_TIMELIMIT="${HYAKVNC_SLURM_TIMELIMIT:-${SBATCH_TIMELIMIT:-12:00:00}}" # %% Time limit for SLURM job (default: `12:00:00`)

# hyakvnc_load_config()
# Load the hyakvnc configuration from the config file
# This is high up in the file so that settings can be overridden by the user's config
# Arguments: None
function hyakvnc_load_config() {
	[[ -r "${HYAKVNC_CONFIG_FILE:-}" ]] || return 0 # Return if config file doesn't exist

	# Read each line of the parsed config file and export the variable:
	while IFS=$'\n' read -r line; do
		# Get the variable name by removing everything after the equals sign. Uses nameref to allow indirect assignment (see https://gnu.org/software/bash/manual/html_node/Shell-Parameters.html):
		declare -n varref="${line%%=*}"
		# Evaluate the right-hand side of the equals sign:
		varref="$(bash --restricted --posix -c "echo ${line#*=}" || true)"
		# Export the variable:
		export "${!varref}"
		# If DEBUG is not 0, print the variable:
		[[ "${DEBUG:-0}" != 0 ]] && echo "Loaded variable from \"CONFIG_FILE\": ${!varref}=(${varref})" >&2
	done < <(sed -E 's/^\s*//;  /^[^#=]+=.*/!d;  s/^([^=\s]+)\s+=/\1=/;' "${HYAKVNC_CONFIG_FILE}" || true) # Parse config file, ignoring comments and blank lines, removing leading whitespace, and removing whitespace before (but not after) the equals sign
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

	[[ -z "${level:=${1:-}}" ]] && {
		echo >&2 "log(): No log level set"
		return 1
	}

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
		ctx="[ ${BASH_SOURCE[1]##*/}:${BASH_LINENO[1]} in ${FUNCNAME[1]:-}() ]"
	fi

	if [[ "${curlogfilelevelno}" -ge "${Log_Levels[DEBUG]}" ]] || [[ "${curlogfilelevelno}" -le "${Log_Levels[CRITICAL]}" ]]; then
		logfilectx="[ ${BASH_SOURCE[1]##*/}:${BASH_LINENO[1]} in ${FUNCNAME[1]:-}() ]"
	fi

	if [[ "${curlevelno}" -ge "${levelno}" ]]; then
		# If we're in a terminal, use colors:
		if [[ -z "${continueline:-}" ]]; then
			[[ -t 0 ]] && { tput setaf "${colorno:-}" 2>/dev/null || true; }
			printf "%s%s: " "${level:-}" "${ctx:- }" >&2 || true
			[[ -t 0 ]] && { tput sgr0 2>/dev/null || true; }
		fi

		# Print the rest of the message without colors:
		printf "%s" "${*-}" >&2 || true

		# Add newline if not continuing a line:
		[[ -z "${nonewline:-}" ]] && { printf "\n" >&2 || true; }
	fi

	if [[ "${curlogfilelevelno}" -ge "${levelno}" ]]; then
		# If we're in a terminal, use colors:
		if [[ -z "${continueline:-}" ]]; then
			printf "%s%s: " "${level:-}" "${logfilectx:- }" >&2 >>"${HYAKVNC_LOG_FILE:-/dev/null}" || true
		fi

		printf "%s%s" "${*-}" "${newline:-}" >&2 >&2 >>"${HYAKVNC_LOG_FILE:-/dev/null}" || true
	fi
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
						return 1
					}
					log INFO "Successfully updated hyakvnc. Restarting..."
					echo
					exec "${0}" "${@}" # Restart hyakvnc
					;;
				n | N | no | No)
					log INFO "Not updating hyakvnc"
					return 1
					;;
				x | X)
					log INFO "Disabling update checks"
					export HYAKVNC_CHECK_UPDATE_FREQUENCY="-1"
					if [[ -n "${HYAKVNC_CONFIG_FILE:-}" ]]; then
						touch "${HYAKVNC_CONFIG_FILE}" && echo 'HYAKVNC_CHECK_UPDATE_FREQUENCY=-1' >>"${HYAKVNC_CONFIG_FILE}"
						log INFO "Set HYAKVNC_CHECK_UPDATE_FREQUENCY=-1 in ${HYAKVNC_CONFIG_FILE}"
					fi
					return 1
					;;
				*)
					echo "Please enter y, n, or x"
					;;
			esac
		done
	else
		hyakvnc_pull_updates || {
			log INFO "Didn't update hyakvnc"
			return 1
		}
	fi
	return 0
}

# ## General utility functions:

# check_command()
# Check if a command is available
# Arguments:
# - <command> - The command to check
# - <loglevel> <message> - Passed to log if the command is not available (optional)
function check_command() {
	if [[ -z "${1:-}" ]] || ! command -v "${1}" >/dev/null 2>&1; then
		[[ $# -gt 1 ]] && log "${@:2}"
		return 1
	fi
	return 0
}

# ## SLURM utility functons:

# check_slurm_running {
# Check if SLURM is running
# Arguments: None
function check_slurm_running() {
	sinfo >/dev/null 2>&1 || return 1
}

# expand_slurm_node_range()
# Expand a SLURM node range to a list of nodes
# Arguments: <node range>
function expand_slurm_node_range() {
	[[ -z "${1:-}" ]] && return 1
	result=$(scontrol show hostnames --oneliner "${1}" | grep -oE '^.+$' | tr ' ' '\n') || return 1
	echo "${result}" && return 0
}

# get_slurm_job_info()
# Get info about a SLURM job, given a list of job IDs
# Arguments: <user> [<jobid>]
function get_slurm_job_info() {
	[[ $# -eq 0 ]] && {
		log ERROR "User or Job ID must be specified"
		return 1
	}

	local user="${1:-${USER:-}}"
	[[ -z "${user}" ]] && {
		log ERROR "User must be specified"
		return 1
	}
	shift
	local squeue_format_fields='%i %j %a %P %u %T %M %l %C %m %D %N'
	squeue_format_fields="${squeue_format_fields// /\t}" # Replace spaces with tab
	local squeue_args=(--noheader --user "${user}" --format "${squeue_format_fields}")

	local jobids="${*:-}"
	if [[ -n "${jobids}" ]]; then
		jobids="${jobids//,/ }" # Replace commas with spaces
		squeue_args+=(--job "${jobids}")
	fi
	squeue "${squeue_args[@]}"
}

# get_squeue_job_status()
# Get the status of a SLURM job, given a job ID
# Arguments: <jobid>
function get_squeue_job_status() {
	local jobid="${1:-}"
	[[ -z "${jobid}" ]] && {
		log ERROR "Job ID must be specified"
		return 1
	}
	squeue -j "${1}" -h -o '%T' || {
		log ERROR "Failed to get status for job ${jobid}"
		return 1
	}
}

# klone_read_qos()
# Return the correct QOS on Hyak for the given partition on hyak
# Arguments: <partition>
# shellcheck disable=SC2120
function klone_read_qos() {
	# Logic copied from hyakalloc's hyakqos.py:QosResource.__init__():
	local qos_name="${1:-$(</dev/stdin)}"
	[[ -z "${qos_name:-}" ]] && return 1
	if [[ "${qos_name}" == *-* ]]; then
		qos_suffix="${qos_name#*-}" # Extract portion after the first "-"

		if [[ "${qos_suffix}" == *mem ]]; then
			echo "compute-${qos_suffix}"
		else
			echo "${qos_suffix}"
		fi
	else
		echo "compute"
	fi
}

function klone_list_hyak_partitions() {
	local cluster account partitions max_count
	local sacctmgr_args=(show --noheader --parsable2 --associations user "${USER}" format=qos)
	while true; do
		case "${1:-}" in
			--cluster)
				shift
				cluster="${1:-}"
				shift
				;;
			-A | --account)
				shift
				account="${1:-}"
				shift
				;;
			-m | --max-count)
				shift
				max_count="${1:-}" # Number of partitions to list, 0 for all (passed to head -n -)
				shift
				;;
			*) break ;;
		esac
	done
	# Add filters if specified:
	[[ -n "${account:-}" ]] && sacctmgr_args+=(where "account=${account}")
	[[ -n "${cluster:-}" ]] && sacctmgr_args+=("cluster=${cluster}")

	# Get partitions:
	partitions="$(sacctmgr "${sacctmgr_args[@]}" | tr ',' '\n' | sort | uniq | head -n "${max_count:=0}" || true)"
	[[ -n "${partitions:-}" ]] || return 1

	# If running on klone, process the partition names as required (see `hyakalloc`)
	if [[ "${cluster:-}" == "klone" ]]; then
		partitions="$(echo "${partitions}" | klone_read_qos | sort | uniq || true)"
		[[ -n "${partitions:-}" ]] || return 1
	fi

	# Return the partitions:
	echo "${partitions}"
	return 0
}

# hyakvnc_config_init()
# Initialize the hyakvnc configuration
# Arguments: None
function hyakvnc_config_init() {
	if check_slurm_running; then
		# Set default SLURM cluster, account, and partition if empty:
		if [[ -z "${HYAKVNC_SLURM_CLUSTER:-}" ]]; then
			HYAKVNC_SLURM_CLUSTER="$(sacctmgr show cluster -nPs format=Cluster | head -n 1 || true)" || {
				log ERROR "Failed to get default SLURM account"
				return 1
			}
			SBATCH_CLUSTERS="${HYAKVNC_SLURM_CLUSTER:-}" && log TRACE "Set SBATCH_CLUSTERS=\"${SBATCH_CLUSTERS}\""
		fi

		if [[ -z "${HYAKVNC_SLURM_ACCOUNT:-}" ]]; then
			# Get the default account for the cluster. Uses grep to get first non-whitespace line:
			HYAKVNC_SLURM_ACCOUNT=$(sacctmgr show user -nPs "${USER}" format=defaultaccount where cluster="${HYAKVNC_SLURM_CLUSTER}" | grep -o -m 1 -E '\S+') || {
				log ERROR "Failed to get default account"
				return 1
			}
		fi
		SBATCH_ACCOUNT="${HYAKVNC_SLURM_ACCOUNT:-}" && log TRACE "Set SBATCH_ACCOUNT=\"${SBATCH_ACCOUNT:-}\""

		if [[ -z "${HYAKVNC_SLURM_PARTITION:-}" ]]; then
			HYAKVNC_SLURM_PARTITION="$(klone_list_hyak_partitions --account "${HYAKVNC_SLURM_ACCOUNT:-}" --cluster "${HYAKVNC_SLURM_CLUSTER:-}" --max-count 1)" || { log ERROR "Failed to get SLURM partitions for user \"${USER:-}\" on account \"${HYAKVNC_SLURM_ACCOUNT:-}\" on cluster \"${HYAKVNC_SLURM_CLUSTER:-}\""; return 1; }

			SBATCH_PARTITION="${HYAKVNC_SLURM_PARTITION:-}" && log TRACE "Set SBATCH_PARTITION=\"${SBATCH_PARTITION:-}\""
		fi
	else
		log WARN "SLURM is not running. Can't get default SLURM cluster, account, and partition."
	fi

	# shellcheck disable=SC2046
	export "${!HYAKVNC_@}" # Export all HYAKVNC_ variables
	export "${!SBATCH_@}"  # Export all SBATCH_ variables
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

	[[ -n "${node}" ]] || node=$(squeue -h -j "${jobid}" -o '%N' | grep -o -m 1 -E '\S+') || log DEBUG "Failed to get node for job ${jobid} from squeue"
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
	for bundleid in ${HYAKVNC_MACOS_VNC_VIEWER_BUNDLEIDS}; do
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

hyakvnc_load_config # Load configuration

set +o allexport # Export all variables
