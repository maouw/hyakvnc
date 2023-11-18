#! /usr/bin/env bash
# hyakvnc utility functions

# shellcheck disable=SC2292
[ -n "${_HYAKVNC_LIB_SLURM_LOADED:-}" ] && return 0 # Return if already loaded

# Only enable these shell behaviours if we're not being sourced
if ! (return 0 2>/dev/null); then
	set -EuT -o pipefail
	shopt -s inherit_errexit
fi



# check_slurm_running()
# Check if SLURM is running
#
# Returns: 0 if SLURM is running, 1 otherwise
function check_slurm_running() {
	sinfo >/dev/null 2>&1 || return 1
}

# expand_slurm_node_range()
# Expand a SLURM node range to a list of nodes
#
# Arguments:
# 	[...]: SLURM node range to expand
#
# stdout: List of nodes separated by spaces
# Returns: 0 if successful, 1 otherwise
function expand_slurm_node_range() {
	[[ -z "${1:-}" ]] && return 1
	scontrol show hostnames --oneliner "${1}" | tr ' ' '\n' || return 1
}

# get_slurm_job_info()
# Get information about SLURM jobs
#
# Wrapper around squeue that returns a list of associative arrays containing information about each job.
# If --ref is specified, the results are stored in the associative array with the given name instead of being printed.
#
# Arguments:
# 	--sep <separator>: Separator to use for fields (default: space)
# 	--ref <variable name>: Name of an associative array to store the results in
# 	--format <output_format>: Format string to use for squeue (default: '%i %j %a %P %u %T %M %l %C %m %D %N')
#	--no-format: Do not use a format string for squeue
# 	-- [args...] Additional arguments to pass to squeue
#
# stdout: If --ref is not specified, a list of dictionaries containing information about each job
# Returns: 0 if successful, 1 otherwise
function get_slurm_job_info() {
	local -a squeue_args=()
	local sep=' ' format='%i %j %a %P %u %T %M %l %C %m %D %N'
	local -n result_dct_ref

	# Parse arguments
	while true; do
		case "${1:-}" in
			--sep)
				shift || { log ERROR "$1 requires an argument"; return 1; }
				sep="$1" ;;
			--ref)
				shift || { log ERROR "$1 requires an argument"; return 1; }
				result_dct_ref="$1" ;;
			--format)
				shift || { log ERROR "$1 requires an argument"; return 1; }
				format="$1" ;;
			--no-format)
				format='' ;;
			--) shift && squeue_args+=("${@}")
			break ;;
			-*) log ERROR "Unknown option \"${1:-}\""; return 1 ;;
			*) break ;;
		esac
		shift
	done

	# Add format string to squeue arguments if specified:
	[[ -n "${format:-}" ]] && squeue_args+=(--format "${format// /${sep}}")

	# Run squeue and read output:
	local squeue_result
	squeue_result="$(squeue "${squeue_args[@]}" "${@}")" || { log ERROR "squeue failed with code $?"; return 1; }
	[[ -n "${squeue_result:-}" ]] || { log ERROR "squeue returned no text"; return 1; }

	# Read output line by line:
	local -a field_names=()
	while IFS= read -sr; do
		local -a fields
		local -A job_info=()
		local job_id
		local job_info_str

		if [[ "${#field_names[@]}" == 0 ]]; then
			IFS="${sep}" read -sra field_names <<<"${REPLY}"
			continue
		fi

		# Split line into fields:
		IFS="${sep}" read -sra fields <<<"${REPLY}"

		# Create associative array with job info using field names as keys:
		for f in "${!field_names[@]}"; do
			job_info["${field_names[${f}]}"]="${fields[${f}]:-}"
		done

		# Get job id:
		[[ -z "${job_id:=${job_info[JOBID]:-}}" ]] && { log WARN "No job ID for line \"${REPLY}\""; continue; }

		# Get job_info associative array as a string:
		job_info_str="$(declare -p job_info)"
		job_info_str="${job_info_str#*=}"

		# Store job info in result dictionary or print it:
		[[ -R result_dct_ref ]] && result_dct_ref["${job_info["JOBID"]}"]="${job_info_str}" || printf '%s\n' "${job_info_str}"

	done <<<"${squeue_result}"
	return 0
}

# slurm_list_partitions()
# List SLURM partitions
#
# Arguments:
# 	--cluster <name>: Cluster to list partitions for
#	--user <name>: User to list partitions for
#	--account <name>: Account to list partitions for
#	--max_count <n>: Maximum number of partitions to list
#
# stdout: List of partitions
# Returns: 0 if successful, 1 otherwise
function slurm_list_partitions() {
	check_command sacctmgr ERROR || return 1
	local cluster account partitions max_count user

	while true; do
		case "${1:-}" in
			--cluster)
				shift || { log ERROR "$1 requires an argument"; return 1; }
				cluster="$1" ;;
			--user)
				shift || { log ERROR "$1 requires an argument"; return 1; }
				user="$1" ;;
			--account)
				shift || { log ERROR "$1 requires an argument"; return 1; }
				account="$1" ;;
			--max-count)
				shift || { log ERROR "$1 requires an argument"; return 1; }
				max_count="$1" ;;
			*) break ;;
		esac
	done

	[[ -z "${user:=${USER:-}}" ]] && { log ERROR "No user specified"; return 1; }

	local sacctmgr_args=(show --noheader --parsable2 --associations user "${user:-}" format=qos)

	# Add filters if specified:
	[[ -n "${account:-}" ]] && sacctmgr_args+=(where "account=${account}")
	[[ -n "${cluster:-}" ]] && sacctmgr_args+=("cluster=${cluster}")

	# Get partitions:
	partitions="$(sacctmgr "${sacctmgr_args[@]}" | tr ',' '\n' | sort | uniq | head -n "${max_count:-0}")" || { log ERROR "sacctmgr failed with code $?"; return 1; }
	[[ -n "${partitions:-}" ]] || { log ERROR "No partitions found"; return 1; }

	# If running on klone, process the partition names as required (see `hyakalloc`)
	if [[ "${cluster:-}" == "klone" ]] && [[ -n "${partitions:-}" ]]; then
		partitions="$(echo "${partitions:-}" | klone_read_qos | sort | uniq || true)"
	fi

	# Return the partitions:
	echo "${partitions}"
	return 0
}

# slurm_list_clusters()
# List SLURM clusters
#
# Arguments:
# 	--max_count <n>  Maximum number of clusters to list (optional)
# stdout: List of clusters
# Returns: 0 if successful, 1 otherwise
function slurm_list_clusters() {
	check_command sacctmgr ERROR || return 1
	local clusters max_count
	local sacctmgr_args=(show cluster --noheader --parsable2 --associations format=Cluster)

	while true; do
		case "${1:-}" in
			--max-count)
				shift || { log ERROR "$1 requires an argument"; return 1; }
				max_count="$1" ;;
			*) break ;;
		esac
		shift
	done

	clusters="$(sacctmgr "${sacctmgr_args[@]}" | tr ',' '\n' | sort | uniq | head -n "${max_count:-0}")" || { log ERROR "sacctmgr failed to list clusters with code $?"; return 1; }
	[[ -n "${clusters:-}" ]] || { log ERROR "No clusters found"; return 1; }
	echo "${clusters:-}"
	return 0
}

# slurm_get_default_account()
# Get the default SLURM account
#
# Arguments:
# 	--cluster <name>: Cluster to get the default account for
#	--user <name>: User to get the default account for (default: $USER)
# stdout: Default account
# Returns: 0 if successful, 1 otherwise
function slurm_get_default_account() {
	check_command sacctmgr ERROR || return 1
	local user
	local default_account
	local sacctmgr_args=(--noheader --parsable2 --associations format=defaultaccount)

	while true; do
		case "${1:-}" in
			--cluster)
				shift || { log ERROR "$1 requires an argument"; return 1; }
				sacctmgr_args+=("cluster=$1") ;;
			--user)
				shift || { log ERROR "$1 requires an argument"; return 1; }
				user="$1" ;;
			*) break ;;
		esac
		shift
	done

	[[ -z "${user:=${USER:-}}" ]] && { log ERROR "No user specified"; return 1; }
	default_account="$(sacctmgr show user "${user}" "${sacctmgr_args[@]}" | tr ',' '\n' | sort | uniq | head -n 1)" || { log ERROR "sacctmgr failed with code $?"; return 1; }
	[[ -n "${default_account:-}" ]] || { log ERROR "No default account found"; return 1; }
	echo "${default_account}"
	return 0
}


SourcedFiles+=("${BASH_SOURCE[0]}")

_HYAKVNC_LIB_SLURM_LOADED=1
