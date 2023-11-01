#!/usr/bin/env bash

# shellcheck disable=SC2292
[ -n "${XDEBUG:-}" ] && set -x # Set XDEBUG to print commands as they are executed
# shellcheck disable=SC2292
[ -n "${BASH_VERSION:-}" ] || { echo "Requires Bash"; exit 1; }
set -o pipefail # Use last non-zero exit code in a pipeline
set -o errtrace # Ensure the error trap handler is inherited
set -o nounset  # Exit if an unset variable is used

# shellcheck disable=SC2292
[ -n "${XDEBUG:-}" ] && set -x # Set XDEBUG to print commands as they are executed
# shellcheck disable=SC2292
[ -n "${BASH_VERSION:-}" ] || { echo "Requires Bash"; exit 1; }
set -o pipefail # Use last non-zero exit code in a pipeline
set -o errtrace # Ensure the error trap handler is inherited
set -o nounset  # Exit if an unset variable is used
SCRIPTDIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=_lib.bash
source "${SCRIPTDIR}/_lib.bash"

export REMOTE_REPO=https://github.com/maouw/hyakvnc_apptainer
export TAG_PREFIX='sif-'

function list_remote_images() {
	local height width msg
	command -v whiptail >/dev/null 2>&1 || { echo >&2 "Requires whiptail. Exiting."; exit 1; }
	command -v git >/dev/null 2>&1 || { echo >&2 "Requires git. Exiting."; exit 1; }

	read -r height width < <(stty size || true)
	height="${height:-40}"
	width="${width:-78}"

	height=$((height - 4))
	width=$((width - 4))

	if [[ ! -d "${TAGDIR}" ]]; then
		printf -v msg "Fetching tags from %s..." "${REMOTE_REPO}"
		sleep 1
		TERM=ansi whiptail --infobox "${msg}" 8 "${#msg}" 3>&1 1>&2 2>&3
		git clone --quiet --filter=blob:none --no-tags --bare --config "remote.origin.fetch=\"refs/tags/${TAG_PREFIX:-}*:refs/tags/${TAG_PREFIX:-}*\"" "${REMOTE_REPO}" "${TAGDIR}" || { echo >&2 "Failed to clone repository. Exiting."; exit 1; }
	fi
	git --git-dir="${TAGDIR}" tag -l -n1 --sort=-'*committerdate'
}

function select_remote_image() {
	local height width msg choice
	local found_tags=()
	read -r height width < <(stty size || true)
	height="${height:-40}"
	width="${width:-78}"

	while read -r line; do
		local tag desc
		read -r tag desc <<<"${line}"
		found_tags+=("${tag##"${TAG_PREFIX:-}"}" "${desc}")
	done <<<"$(list_remote_images || true)"

	choice="$(whiptail --title "Menu example" --menu "Choose an option" "${height}" "${width}" $((height - 8)) "${found_tags[@]}" 3>&1 1>&2 2>&3)"
	echo "${choice:-}"
}

export TAGDIR=${TAGDIR:-}
hyakvnc_config() {
	# Check if whiptail is available
	if ! command -v whiptail >/dev/null; then
		echo "whiptail is not installed. Please install it first."
		return 1
	fi
	local height width
	read -r height width < <(stty size || true)
	height="${height:-40}"
	width="${width:-78}"
	local slurm_accounts=(escience '')
	export HYAKVNC_SLURM_ACCOUNT="${HYAKVNC_SLURM_ACCOUNT:-${slurm_accounts[0]}}"
	local slurm_partitions=(gpu-a40 '' gpu-rtx6k '')

	[[ -z "${TAGDIR:-}" ]] && export TAGDIR="$(mktemp --directory --dry-run || true)"

	HYAKVNC_SLURM_PARTITION="${HYAKVNC_SLURM_PARTITION:-${slurm_partitions[0]}}"
	while true; do
		OPTION=$(whiptail --title "HyakVNC Configuration Wizard" --nocancel --menu "Choose an option:" 20 78 10 \
			"1" "Select SLURM container ${HYAKVNC_APPTAINER_CONTAINER:+(${HYAKVNC_APPTAINER_CONTAINER})}" \
			"2" "Set Slurm account ${HYAKVNC_SLURM_ACCOUNT:+(${HYAKVNC_SLURM_ACCOUNT})}" \
			"3" "Set Slurm partition ${HYAKVNC_SLURM_PARTITION:+(${HYAKVNC_SLURM_PARTITION})}" \
			"4" "Set number of CPUs ${HYAKVNC_SLURM_CPUS:+(${HYAKVNC_SLURM_CPUS})}" \
			"5" "Set amount of memory ${HYAKVNC_SLURM_MEM:+(${HYAKVNC_SLURM_MEM})}" \
			"6" "Set Slurm timelimit ${HYAKVNC_SLURM_TIMELIMIT:+(${HYAKVNC_SLURM_TIMELIMIT})}" \
			"7" "Set number of GPUs ${HYAKVNC_SLURM_GPUS:+(${HYAKVNC_SLURM_GPUS})}" \
			"8" "Advanced options" \
			"9" "View and execute command" \
			"10" "Exit" 3>&1 1>&2 2>&3)

		case "${OPTION:-}" in
			1) [[ ! -d "${TAGDIR}" ]] && trap 'rm -rf "${TAGDIR:-}"' EXIT
			HYAKVNC_APPTAINER_CONTAINER="$(select_remote_image || true)"
				;;
			2)
				HYAKVNC_SLURM_ACCOUNT="$(whiptail --title "SLURM Account" --noitem --menu "Choose an account" 16 40 3 \
					"${slurm_accounts[@]}" 3>&1 1>&2 2>&3)" || { echo >&2 "Cancelled. Exiting."; exit 1; }
				;;
			3)
				HYAKVNC_SLURM_PARTITION="$(whiptail --title "SLURM Partition" --noitem --menu "Choose an partition" 16 40 3 \
					"${slurm_partitions[@]}" 3>&1 1>&2 2>&3)" || { echo >&2 "Cancelled. Exiting."; exit 1; }
				;;

			4)
				HYAKVNC_SLURM_CPUS=$(whiptail --inputbox "Enter the number of CPUs to request (current: ${HYAKVNC_SLURM_CPUS:-<NA>}):" 8 78 "${HYAKVNC_SLURM_CPUS}" 3>&1 1>&2 2>&3)
				;;
			5)
				HYAKVNC_SLURM_MEM=$(whiptail --inputbox "Enter the amount of memory to request (current: ${HYAKVNC_SLURM_MEM:-<NA>}):" 8 78 "${HYAKVNC_SLURM_MEM}" 3>&1 1>&2 2>&3)
				;;
			6)
				HYAKVNC_SLURM_TIMELIMIT=$(whiptail --inputbox "Enter the Slurm timelimit to use (current: ${HYAKVNC_SLURM_TIMELIMIT:-<NA>}):" 8 78 "${HYAKVNC_SLURM_TIMELIMIT}" 3>&1 1>&2 2>&3)
				;;
			7)
				HYAKVNC_SLURM_GPUS=$(whiptail --inputbox "Enter the number of GPUs to request (current: ${HYAKVNC_SLURM_GPUS:-<NA>}):" 8 78 "${HYAKVNC_SLURM_GPUS}" 3>&1 1>&2 2>&3)
				;;
			9)
				CMD="echo create -c ${HYAKVNC_APPTAINER_CONTAINER:-}"
				whiptail --msgbox "Generated Command:\n\n${CMD}" 12 78
				if (whiptail --yesno "Execute the command now?" 8 78 3>&1 1>&2 2>&3); then
					msg="$(eval "${CMD}")"
					echo "${msg}"
					echo
					read -r -p "Press enter to return to the menu"
				fi
				;;
			10)
				return 0
				;;
			*) echo "OK, I'll stop"
			return     0
				;;
		esac
	done
}

hyakvnc_config "$@"
