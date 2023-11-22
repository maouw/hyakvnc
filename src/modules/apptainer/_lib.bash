#!/usr/bin/env bash
[[ "${_SOURCED_MODULE_LIB_APPTAINER:-0}" != 0  ]] && return 0
(return 0 2>/dev/null) && echo >&2 "ERROR: This script must be sourced, not executed." && exit 1
source "${BASH_SOURCE[0]%/*}/_lib.bash"



function m_apptainer_init_config() {
	HYAKVNC_SSH_HOST="${HYAKVNC_SSH_HOST:-localhost}" # %?% default: localhost
}


m_apptainer_list_remote_images() {
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

function m_apptainer_select_remote_image() {
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

function m_apptainer_describe_sif() {
	local apptainer_bin_path image_path
	apptainer_bin_path="${APPTAINER_BIN:-}"
	[[ -n "${apptainer_bin_path:-}" ]] || apptainer_bin_path=$(command -v apptainer 2>/dev/null || command -v singularity 2>/dev/null || true)
	[[ -n "${apptainer_bin_path:-}" ]] || return 1
	image_path="${1:-}"
	[[ -n "${image_path:-}" ]] || [[ -r "${image_path:-}" ]] || return 1
	"${apptainer_bin_path}" inspect "${image_path}" | sed -E /'^org\.(opencontainers\.image|label-schema)\.(description|title|name|ref\.name|version):/!d; s/^[^:]+:\s*//g;q'
}

function m_apptainer_list_local_images() {
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
function m_apptainer_select_local_image() {
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

function m_apptainer_edit_HYAKVNC_APPTAINER_CONTAINER {
	local height width msg path choice selected_image
	local found_tags=(
		1 'Select a container image from the local filesystem'
		2 'Select a container image from the hyakvnc repository'
		3 'Enter a URL to a container image'
	)

	choice="$(whiptail --title "hyakvnc" --notags --menu "Where should I look for a container?" 0 0 0 "${found_tags[@]}" 3>&1 1>&2 2>&3)" || return 0

	case "${choice:-}" in
		1) selected_image="$(m_apptainer_select_local_image || true)" ;;
		2) selected_image="$(m_apptainer_select_remote_image "${REMOTE_REPO:-}" || true)" ;;
		3) while true; do
			selected_image="$(whiptail --inputbox "Enter the URL to a container image" 0 0 "${selected_image:-"oras://ghcr.io/"}" 3>&1 1>&2 2>&3)" || return 0

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

declare -A m_apptainer_commands=(
	[init_config]=m_apptainer_init_config
	[list]=m_apptainer_list
	[stop]=m_apptainer_stop
	[start]=m_apptainer_start
)
[[ "${_HYAKVNC_M_APPTAINER_LOADED:-0}" != 0 ]] && return 0 # Return if already loaded
_SOURCED_MODULE_LIB_APPTAINER=1

