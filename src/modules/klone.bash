#! /usr/bin/env bash

# shellcheck disable=SC2292
[ -n "${_HYAKVNC_LIB_KLONE_LOADED:-}" ] && return 0 # Return if already loaded


# Only enable these shell behaviours if we're not being sourced
if ! (return 0 2>/dev/null); then
	set -EuT -o pipefail
	shopt -s inherit_errexit
fi



function check_klone() {
	local domain
	domain="$(hostname -d)" || return 1
	[[ "${domain}" == "hyak.local" ]] || return 1
	slurm_list_clusters --max-count 1 | grep -q klone || return 1
	return 0
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

function klone_slurm_list_partitions() {
	local partitions result
	partitions="$(slurm_list_partitions --cluster klone "$@")" || return 1
	[[ -n "${partitions:-}" ]] || return 0
	result="$(echo "${partitions:-}" | klone_read_qos | sort | uniq)" || return 1
	[[ -n "${result:-}" ]] || return 1
	echo "${result}"
}

function klone_setup_apptainer_cachedir() {
	local parentdir
	local newcachedir
	local abs_apptainer_cachedir
	local add_to_shells=0

	[[ -d "/gscratch/scrubbed" ]] && parentdir="/gscratch/scrubbed/${USER}/.cache"
	while true; do
		case "${1:-}" in
			--parent-dir)
				shift || { log ERROR "$1 requires an argument"; return 1; }
				parentdir="$1" ;;
			--new-cache-dir)
				shift || { log ERROR "$1 requires an argument"; return 1; }
				newcachedir="$1" ;;
			--add-to-shells)
				shift
				add_to_shells=1 ;;
			*) break ;;
		esac
		shift
	done

	abs_apptainer_cachedir="$(realpath "${APPTAINER_CACHEDIR:-}")" || {
		log WARN "Failed to resolve APPTAINER_CACHEDIR to an absolute path"
	}

	case "${abs_apptainer_cachedir:-${APPTAINER_CACHEDIR:-}}" in
		*/gscratch | */gscratch/* | /tmp | /tmp/*) return 0 ;;
		*) ;;
	esac

	[[ -n "${parentdir:-}" ]] || parentdir="$(mktemp -d "${USER}--XXXXXX")" || {
		log WARN "Failed to create temporary directory"
		return 1
	}
	[[ -n "${newcachedir:-}" ]] || newcachedir="${parentdir}/.cache/apptainer"

	mkdir -p "${newcachedir}" || {
		log WARN "Failed to create directory ${newcachedir}"
		return 1
	}
	export APPTAINER_CACHEDIR="${newcachedir:-}"
	log DEBUG "Set APPTAINER_CACHEDIR to ${APPTAINER_CACHEDIR}"

	if [[ "${add_to_shells:-0}" != 0 ]]; then
		if ps T -o 'comm=' --pid "$$" | grep -q zsh; then
			printf "export APPTAINER_CACHEDIR='%q'\n" "${APPTAINER_CACHEDIR}" >>"${HOME}/.zshrc"
		fi
		if ps T -o 'comm=' --pid "$$" | grep -q bash; then
			[[ -w "${HOME}/.bashrc" ]] && printf "export APPTAINER_CACHEDIR='%q'\n" "${APPTAINER_CACHEDIR}" >>"${HOME}/.bashrc"
		fi
	fi

	printf '%q\n' "${APPTAINER_CACHEDIR}"
}


function klone_init() {
	alias slurm_list_partitions=klone_slurm_list_partitions
	log DEBUG "Initialized module 'klone'"
	HYAKVNC_SSH_HOST="${HYAKVNC_SSH_HOST:-klone.hyak.uw.edu}"             # %% Default SSH host to use for connection strings (default: `klone.hyak.uw.edu`)
	HYAKVNC_SLURM_CLUSTER="${HYAKVNC_SLURM_CLUSTER:-${SBATCH_CLUSTERS:-klone}}"              # %% Slurm cluster to use. default: klone
	HYAKVNC_SLURM_MEM="${HYAKVNC_SLURM_MEM:-${SBATCH_MEM:-4G}}"                         # %% Amount of memory to request, in [M]egabytes or [G]igabytes. default: 4G
	HYAKVNC_SLURM_CPUS="${HYAKVNC_SLURM_CPUS:-4}"                                       # %% Number of CPUs to request. default: 4
	HYAKVNC_SLURM_TIMELIMIT="${HYAKVNC_SLURM_TIMELIMIT:-${SBATCH_TIMELIMIT:-12:00:00}}" # %% Time limit for SLURM job. default: 12:00:00

	_HYAKVNC_LIB_KLONE_INITIALIZED=1
	export "${!HYAKVNC_@}"
}

SourcedFiles+=("${BASH_SOURCE[0]}")
_HYAKVNC_LIB_KLONE_LOADED=1