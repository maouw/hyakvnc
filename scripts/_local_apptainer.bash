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
