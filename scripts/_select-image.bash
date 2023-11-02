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

function ui_screen_dims() {
	local width height
	read -r height width < <(stty size || true)
	[[ -n "${height:-}" ]] || height="$(tput lines)" || height="${LINES:-40}"
	[[ -n "${width:-}" ]] || width="$(tput cols)" || width="${COLUMNS:-78}"
	echo "${height} ${width}"
}

function list_remote_images() {
	local height width msg repo
	command -v whiptail >/dev/null 2>&1 || { echo >&2 "Requires whiptail. Exiting."; exit 1; }
	command -v git >/dev/null 2>&1 || { echo >&2 "Requires git. Exiting."; exit 1; }
	read -r height width < <(ui_screen_dims || true)

	repo="${1:-${REMOTE_REPO:-}}"
	[[ -n "${repo:-}" ]] || return 1

	if [[ ! -d "${TAGDIR}" ]]; then
		printf -v msg "Fetching tags from %s..." "${repo}"
		TERM=ansi whiptail --infobox "${msg}" 7 $(("${#msg}" + 4)) 3>&1 1>&2 2>&3
		git clone --filter=blob:none --no-tags --bare --config "remote.origin.fetch=refs/tags/${TAG_PREFIX:-}*:refs/tags/*" "${repo}" "${TAGDIR}" || { echo >&2 "Failed to clone repository. Exiting."; exit 1; }
	fi
	[[ -d "${TAGDIR}" ]] || return 1
	git --git-dir="${TAGDIR}" tag -l -n1 --sort=-'*committerdate'
}

function select_remote_image() {
	local height width msg choice oras_repo
	local found_tags=()
	read -r height width < <(ui_screen_dims || true)
	oras_repo="${1:-${REMOTE_REPO}}"
	[[ -n "${oras_repo:-}" ]] || return 1
	oras_repo="$(dirname "${oras_repo/https:\/\/github.com/oras://ghcr.io}")"
	while read -r line; do
		local tag desc
		read -r tag desc <<<"${line}"
		found_tags+=("${tag}" "${desc:--}")
	done <<<"$(list_remote_images "${1:-}" || true)"

	choice="$(whiptail --title "hyakvnc" --menu "Select a container image" "${height}" "${width}" $((height - 8)) "${found_tags[@]}" 3>&1 1>&2 2>&3)"
	if [[ -n "${choice:-}" ]]; then
		local cont_name cont_tag
		cont_name="${choice%%#*}"
		cont_tag="${choice##"${cont_name:-}"}"
		cont_tag="${cont_tag:-"#latest"}"
		cont_tag="${cont_tag/"#"/":"}"
		choice="${oras_repo}/${cont_name}${cont_tag}"
	fi
	echo "${choice:-}"
}

function describe_sif() {
	local apptainer_bin_path image_path
	apptainer_bin_path="${APPTAINER_BIN:-}"
	[[ -n "${apptainer_bin_path:-}" ]] || apptainer_bin_path=$(command -v apptainer 2>/dev/null || command -v singularity 2>/dev/null || true)
	[[ -n "${apptainer_bin_path:-}" ]] || return 1
	image_path="${1:-}"
	[[ -n "${image_path:-}" ]] || [[ -r "${image_path:-}" ]] || return 1
	"${apptainer_bin_path}" inspect "${image_path}" | sed -E /'^org\.(opencontainers\.image|label-schema)\.(description|title|name|ref\.name|version):/!d; s/^[^:]+:\s*//g;q'
}

function list_local_images() {
	local path ext
	path="${1:-${PWD}}"
	ext="${2:-}"
	[[ -d "${path}" ]] || return 1
	for file in "${path}"/*"${ext:-}"; do
		[[ -z "${ext:-}" ]] && command -v file >/dev/null 2>&1 && { file --brief "${file}" | grep -qE 'singularity|apptainer' || continue; }
		printf '%s\n' "${file}"
	done
	return 0
}

# shellcheck disable=SC2120
function select_local_image() {
	local height width msg path choice container_dir
	local found_tags=()
	read -r height width < <(ui_screen_dims || true)

	while true; do
		# Enter container directory (default: container directory)
		while true; do
			container_dir="$(whiptail --inputbox "Enter the directory to search for container images:" "${height}" "${width}" \
				"${1:-${HYAKVNC_CONTAINERDIR:-${CONTAINERDIR:-${PWD:-}}}}" \
				3>&1 1>&2 2>&3)" || { return 0; }
			[[ -d "${container_dir:-}" ]] && break
			whiptail --msgbox "Directory does not exist. Please try again." "${height}" "${width}"
		done

		while read -r line; do
			local tag desc
			tag=$(basename "${line}")
			desc="$(describe_sif "${line}" || true)"
			found_tags+=("${tag}" "${desc:--}")
		done <<<"$(list_local_images "${container_dir:-}" || true)"

		choice="$(whiptail --title "hyakvnc" --menu "Select a container image" "${height}" "${width}" $((height - 8)) "${found_tags[@]}" 3>&1 1>&2 2>&3)" || break
		[[ -n "${choice:-}" ]] && break
	done
	echo "${choice:-}"
}
function select_container_image() {
	local height width msg path choice selected_image
	local found_tags=(
		'local' 'Select a container image from the local filesystem'
		'remote' 'Select a container image from the hyakvnc repository'
		'url' 'Enter a URL to a container image'
	)

	read -r height width < <(ui_screen_dims || true)

	choice="$(whiptail --title "hyakvnc" --notags --menu "Where should I look for a container?" "${height}" "${width}" $((height - 8)) "${found_tags[@]}" 3>&1 1>&2 2>&3)" || return 0

	case "${choice:-}" in
		local) selected_image="$(select_local_image || true)" ;;
		remote) selected_image="$(select_remote_image "${REMOTE_REPO:-}" || true)" ;;
		url) while true; do
			selected_image="$(whiptail --inputbox "Enter the URL to a container image" "${height}" "${width}" "${selected_image:-"oras://ghcr.io/"}" 3>&1 1>&2 2>&3)" || return 0

			case "${selected_image:-}" in
				library://*/*/* | docker://* | shub://*/* | oras://*/*/* | http://*/* | https://*/*)
					local cont_name="${selected_image##*/}"
					if [[ -n "${cont_name:-}" ]]; then
						[[ "${cont_name}" =~ .*:.* ]] || selected_image="${cont_name}:latest"
						break
					fi

					;;
				*) ;;
			esac
			whiptail --msgbox "Invalid URL. Please try again." "${height}" "${width}"
		done
			;;
		*) return 0 ;;
	esac

	export HYAKVNC_APPTAINER_CONTAINER="${selected_image:-${HYAKVNC_APPTAINER_CONTAINER:-}}"
	return 0
}

function select_slurm_account() {
	local height width msg choice
	local found_tags=()
	read -r height width < <(ui_screen_dims || true)

	if [[ $# -eq 0 ]]; then
		whiptail --msgbox "No SLURM accounts found!" "${height}" "${width}"
		return 1
	fi

	# Read slurm accounts from arguments array:
	for i in "${@:-}"; do
		[[ -n "${i:-}" ]] && found_tags+=("${i:-}" "")
	done

	choice="$(whiptail --title "hyakvnc	" --menu "Select SLURM account" "${height}" "${width}" $((height - 8)) "${found_tags[@]}" 3>&1 1>&2 2>&3)" || return 1
	export HYAKVNC_SLURM_ACCOUNT="${choice:-${HYAKVNC_SLURM_ACCOUNT:-}}"
	return 0
}

function select_slurm_partition() {
	local height width msg choice
	local found_tags=()
	read -r height width < <(ui_screen_dims || true)
	width=78

	if [[ $# -eq 0 ]]; then
		whiptail --msgbox "No SLURM partitions found!" "${height}" "${width}"
		return 1
	fi

	# Read slurm accounts from arguments array:
	for i in "${@:-}"; do
		[[ -n "${i:-}" ]] && found_tags+=("${i:-}" "")
	done

	choice="$(whiptail --title "hyakvnc	" --menu "Select SLURM partition" "${height}" "${width}" $((height - 8)) "${found_tags[@]}" 3>&1 1>&2 2>&3)" || return 1
	export HYAKVNC_SLURM_PARTITION="${choice:-${HYAKVNC_SLURM_PARTITION:-}}"
	return 0
}

export TAGDIR="${TAGDIR:-}"
hyakvnc_config() {
	# Check if whiptail is available
	if ! command -v whiptail >/dev/null; then
		echo "whiptail is not installed. Please install it first."
		return 1
	fi
	local height width
	read -r height width < <(ui_screen_dims || true)
	local slurm_accounts=(escience '')
	local slurm_partitions=(gpu-a40 '' gpu-rtx6k '')

	[[ -z "${TAGDIR:-}" ]] && TAGDIR="$(mktemp --directory --dry-run || true)" && export TAGDIR
	export HYAKVNC_SLURM_ACCOUNT="${HYAKVNC_SLURM_ACCOUNT:-${slurm_accounts[0]}}"
	HYAKVNC_SLURM_PARTITION="${HYAKVNC_SLURM_PARTITION:-${slurm_partitions[0]}}"
	while true; do
		OPTION=$(whiptail --title "HyakVNC Configuration Wizard" --menu "Choose an option:" "${height}" "${width}" $((height - 8)) \
			"1" "Select SLURM container ${HYAKVNC_APPTAINER_CONTAINER:+(${HYAKVNC_APPTAINER_CONTAINER##*/})}" \
			"2" "Set Slurm account ${HYAKVNC_SLURM_ACCOUNT:+(${HYAKVNC_SLURM_ACCOUNT})}" \
			"3" "Set Slurm partition ${HYAKVNC_SLURM_PARTITION:+(${HYAKVNC_SLURM_PARTITION})}" \
			"4" "Set number of CPUs ${HYAKVNC_SLURM_CPUS:+(${HYAKVNC_SLURM_CPUS})}" \
			"5" "Set amount of memory ${HYAKVNC_SLURM_MEM:+(${HYAKVNC_SLURM_MEM})}" \
			"6" "Set Slurm timelimit ${HYAKVNC_SLURM_TIMELIMIT:+(${HYAKVNC_SLURM_TIMELIMIT})}" \
			"7" "Set number of GPUs ${HYAKVNC_SLURM_GPUS:+(${HYAKVNC_SLURM_GPUS})}" \
			"8" "Advanced options" \
			"9" "Launch Session" \
			"10" "Exit" 3>&1 1>&2 2>&3)

		case "${OPTION:-}" in
			1)
				[[ ! -d "${TAGDIR}" ]] && trap 'rm -rf "${TAGDIR:-}"' EXIT
				select_container_image || true
				;;
			2)
				select_slurm_account escience a || true
				;;
			3)
				select_slurm_partition a b || true
				;;

			4)
				HYAKVNC_SLURM_CPUS=$(whiptail --inputbox "Enter the number of CPUs to request (current: ${HYAKVNC_SLURM_CPUS:-<NA>}):" "${height}" "${width}" "${HYAKVNC_SLURM_CPUS}" 3>&1 1>&2 2>&3)
				;;
			5)
				HYAKVNC_SLURM_MEM=$(whiptail --inputbox "Enter the amount of memory to request	 (current: ${HYAKVNC_SLURM_MEM:-<NA>}):" "${height}" "${width}" "${HYAKVNC_SLURM_MEM}" 3>&1 1>&2 2>&3)
				;;
			6)
				HYAKVNC_SLURM_TIMELIMIT=$(whiptail --inputbox "Enter the Slurm timelimit to use (current: ${HYAKVNC_SLURM_TIMELIMIT:-<NA>}):" "${height}" "${width}" "${HYAKVNC_SLURM_TIMELIMIT}" 3>&1 1>&2 2>&3)
				;;
			7)
				HYAKVNC_SLURM_GPUS=$(whiptail --inputbox "Enter the number of GPUs to request (current: ${HYAKVNC_SLURM_GPUS:-<NA>}):" "${height}" "${width}" "${HYAKVNC_SLURM_GPUS}" 3>&1 1>&2 2>&3)
				;;
			9)
				CMD="echo create -c ${HYAKVNC_APPTAINER_CONTAINER:-}"
				whiptail --msgbox "Generated Command:\n\n${CMD}" "${height}" "${width}"
				if (whiptail --yesno "Execute the command now?" 8 78 3>&1 1>&2 2>&3); then
					msg="$(eval "${CMD}")"
					echo "${msg}"
					echo
					read -r -p "Press enter to return to the menu"
				fi
				;;
			*) echo "OK, I'll stop"
			return 0
				;;
		esac
	done
}

hyakvnc_config "$@"
