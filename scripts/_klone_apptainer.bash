#! /usr/bin/env bash
# hyakvnc utility functions

HYAKVNC_SSH_HOST="${HYAKVNC_SSH_HOST:-klone.hyak.uw.edu}"             # %% Default SSH host to use for connection strings (default: `klone.

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


# ## General utility functions:

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
	result="$(scontrol show hostnames --oneliner "${1}" | grep -oE '^.+$' | tr ' ' '\n' || true)"
	[[ -z "${result:-}" ]] && return 1
	echo "${result}" && return 0
}

# get_slurm_job_info()
# Get info about a SLURM job, given a list of job IDs
# Arguments: <user> [<jobid>]

# shellcheck disable=SC2034
function get_slurm_job_info() {
	local -n result_dct_ref
	local -a field_names
	local -a squeue_args=()
	local sep=' '
	local format='%i %j %a %P %u %T %M %l %C %m %D %N'
	local -i ref_is_set=0
	# Parse arguments 
	while true; do
		case "${1:-}" in
			--sep)
				[[ -n "${2:-}" ]] || {
					echo "ERROR: --sep requires an argument" >&2
					return 1
				}
				shift
				sep="${1}"
				;;
			--ref)
				[[ -n "${2:-}" ]] || {
					echo "ERROR: --ref requires an argument" >&2
					return 1
				}
				shift
				result_dct_ref="${1}"
				ref_is_set=1
				;;
			--format)
				[[ -n "${2:-}" ]] || {
					echo "ERROR: --format requires an argument" >&2
					return 1
				}
				shift
				format="${1}"
				;;
			*)
				break
				;;
		esac
		shift
	done
	squeue_args+=("--format=${format}")
	local line i=0

	while read -r line; do
		(( i++ == 0 )) && {
			# First line contains header
			# Split header into fields
			IFS="${sep}" read -r -a field_names <<< "${line}"
			continue
		}
		local -A job_info

		# Split line into fields
		IFS="${sep}" read -r -a fields <<< "${line}"
		#readarray -d "${sep}" -t fields <<< "${line}"

		for f in "${!field_names[@]}"; do
			job_info["${field_names[${f}]}"]="${fields[${f}]}"
		done
		job_info_str="$(declare -p job_info)"
		[[ "${ref_is_set}" -eq 1 ]] && result_dct_ref["JOBID"]="${job_info_str#*=}" || printf "%s\n" "${job_info_str#*=}"
	done < <(squeue "${squeue_args[@]}" "${@}" || true)
	return 0	
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
# Logic copied from hyakalloc's hyakqos.py:QosResource.__init__():
# Arguments: <partition>
# shellcheck disable=SC2120
function klone_read_qos() {
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

function slurm_list_partitions() {
	check_command sacctmgr ERROR || return 1
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
	partitions="$(sacctmgr "${sacctmgr_args[@]}" | tr ',' '\n' | sort | uniq | head -n "${max_count:-0}" || true)"
	[[ -n "${partitions:-}" ]] || return 1

	# If running on klone, process the partition names as required (see `hyakalloc`)
	if [[ "${cluster:-}" == "klone" ]] && [[ -n "${partitions:-}" ]]; then
		partitions="$(echo "${partitions:-}" | klone_read_qos | sort | uniq || true)"
	fi

	# Return the partitions:
	echo "${partitions}"
	return 0
}

function slurm_list_clusters() {
	check_command sacctmgr ERROR || return 1
	local clusters max_count
	local sacctmgr_args=(show --noheader --parsable2 --associations format=Cluster)
	while true; do
		case "${1:-}" in
			-m | --max-count)
				shift
				max_count="${1:-}" # Number of partitions to list, 0 for all (passed to head -n -)
				shift
				;;
			*) break ;;
		esac
	done
	clusters="$(sacctmgr "${sacctmgr_args[@]}" | tr ',' '\n' | sort | uniq | head -n "${max_count:-0}" || true)"
	echo "${clusters:-}"
	return 0
}

function slurm_get_default_account() {
	check_command sacctmgr ERROR || return 1
	local cluster default_account
	local sacctmgr_args=(show --noheader --parsable2 --associations format=defaultaccount)
	[[ -n "${cluster:-}" ]] && sacctmgr_args+=("cluster=${cluster}")

	while true; do
		case "${1:-}" in
			-c | --cluster)
				shift
				cluster="${1:-}"
				shift
				;;
			*) break ;;
		esac
	done

	default_account="$(sacctmgr "${sacctmgr_args[@]}" | tr ',' '\n' | sort | uniq | head -n 1 || true)"
	echo "${default_account:-}"
	return 0
}

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
