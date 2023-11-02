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
	read -r -t 1 height width < <(stty size 2>/dev/null || true) 2>/dev/null || true
	[[ -n "${height:-}" ]] || height="$(tput lines)" || height="${LINES:-40}"
	[[ -n "${width:-}" ]] || width="$(tput cols)" || width="${COLUMNS:-78}"
	((width <= 120)) || width=120 # Limit to 80 characters per line if over 120 characters
	((height <= 40)) || height=40 # Limit to 40 lines if over 40 lines
	((width >= 9)) || width=9 # Set minimum width
	((height >= 7)) || height=7 # Set minimum height
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
		1 'Select a container image from the local filesystem'
		2 'Select a container image from the hyakvnc repository'
		3 'Enter a URL to a container image'
	)

	read -r height width < <(ui_screen_dims || true)

	choice="$(whiptail --title "hyakvnc" --notags --menu "Where should I look for a container?" "${height}" "${width}" $((height - 8)) "${found_tags[@]}" 3>&1 1>&2 2>&3)" || return 0

	case "${choice:-}" in
		1) selected_image="$(select_local_image || true)" ;;
		2) selected_image="$(select_remote_image "${REMOTE_REPO:-}" || true)" ;;
		3) while true; do
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

function ui_whip_error()  {
	local height width
	read -r height width < <(ui_screen_dims || true)
	whiptail --title "hyakvnc - error" --msgbox "${1:-}" "${height}" "${width}"
}

function ui_input_config_var() {
	local height width var_current var_description prelude note result export_result
	local -n var_ref
	read -r height width < <(ui_screen_dims || true)
	while [[ $# -gt 0 ]]; do
		case "${1:-}" in
			--prelude) shift || break; prelude="${1:-}" ;;
			--note) shift || break; note="${1:-}" ;;
			--current) shift || break; var_current="${1:-}" ;;
			--description) shift || break; var_description="${1:-}" ;;
			-x | --export) export_result="${1:-}" ;;
			--whiptail-opts)
				shift || break;
				while [[ $# -gt 0 ]]; do
					[[ "${1:-}" == -- ]] && break
					whiptail_opts+=("${1:-}")
					shift
				done
				;;
			--whiptail-box-opts) shift || break;
			while [[ $# -gt 0 ]]; do
				[[ "${1:-}" == -- ]] && break
				whiptail_box_opts+=("${1:-}")
				shift
			done
				;;
			*) break ;;
		esac
		shift
	done
	[[ -z "${1:-}" ]] && return 1
	var_ref="${1:-}"
	shift
	prelude="${prelude-"Set ${!var_ref}"}"
	var_description="${var_description-"${Hyakvnc_Config_Descriptions["${!var_ref:-}"]:-}"}"
	note="${note:+"\n${note}"}"
	var_current="${var_current:-${var_ref:-}}"
	msg="${prelude:+"${prelude:-}\\n"}${var_description:+"(${var_description})\\n"}${note:+"${note}\\n"}${var_current:+"Current: ${var_current}"}"
	result="$(whiptail --title "hyakvnc Configuration" --inputbox "${msg}" "${height}" "${width}" "${var_current:-}" 3>&1 1>&2 2>&3)" || return 1
	[[ -v result ]] && var_ref="${result:-}" && [[ "${export_result:-}" == 1 ]] && export "${!var_ref}"
	return 0
}

function ui_select_config_var() {
	local height width menu_height var_current var_description prelude note result export_result
	local -n var_ref
	local whiptail_opts=()
	local whiptail_box_opts=()
	local menu_array=()
	read -r height width < <(ui_screen_dims || true)

	while [[ $# -gt 0 ]]; do
		case "${1:-}" in
			--prelude) shift || break; prelude="${1:-}" ;;
			--note) shift || break; note="${1:-}" ;;
			--current) shift || break; var_current="${1:-}" ;;
			--description) shift || break; var_description="${1:-}" ;;
			-x | --export) export_result="${1:-}" ;;
			--whiptail-opts)
				shift || break;
				while [[ $# -gt 0 ]]; do
					[[ "${1:-}" == -- ]] && break
					whiptail_opts+=("${1:-}")
					shift
				done
				;;
			--whiptail-box-opts) shift || break;
			while [[ $# -gt 0 ]]; do
				[[ "${1:-}" == -- ]] && break
				whiptail_box_opts+=("${1:-}")
				shift
			done
				;;
			*) break ;;
		esac
		shift
	done
	while [[ $# -gt 0 ]]; do
		case "${1:-}" in
			--prelude) shift || break; prelude="${1:-}" ;;
			--note) shift || break; note="${1:-}" ;;
			--current) shift || break; var_current="${1:-}" ;;
			--description) shift || break; var_description="${1:-}" ;;
			-x | --export) shift || break; export_result="${1:-}" ;;
			--whiptail-opts)
				shift || break;
				while [[ $# -gt 0 ]]; do
					[[ "${1:-}" == -- ]] && break
					whiptail_opts+=("${1:-}")
					shift
				done
				;;
			--whiptail-box-opts) shift || break;
			while [[ $# -gt 0 ]]; do
				[[ "${1:-}" == -- ]] && break
				whiptail_box_opts+=("${1:-}")
				shift
			done
				;;
			*) break ;;
		esac
		shift
	done
	[[ -z "${1:-}" ]] && return 1
	var_ref="${1:-}"
	shift
	prelude="${prelude-"Set ${!var_ref}"}"
	var_description="${var_description-"${Hyakvnc_Config_Descriptions["${!var_ref:-}"]:-}"}"
	note="${note:+"\n${note}"}"
	var_current="${var_current:-${var_ref:-}}"

	# Read menu tag/item pairs from arguments array:
	local num_values="${#:-0}"
	((num_values % 2 == 0)) || { log ERROR "ui_select_config_var: Invalid number of arguments. Requires an even number of arguments."; return 1; }
	((num_values > 0)) || { log DEBUG "ui_select_config_var: No arguments."; return 1; }
	local num_menu_items=$((num_values / 2))

	while [[ "$#" -gt 0 ]]; do
		menu_array+=("${1:-}")
		shift
		menu_array+=(" ${1:-}") # Add a space to the beginning of the item to pad the menu
		shift
	done

	[[ "${whiptail_opts[*]}" =~ .*--backtitle[[:space:]]* ]] && ((height = height - 2)) && { ((height >= 9)) || height=9; }

	# Set menu height to 1/2 of the number of menu items, or 10, whichever is smaller
	((menu_height = height - 8 - num_menu_items))
	[[ -n "${prelude:-}" ]] && ((menu_height = menu_height - 1))
	[[ -n "${var_description:-}" ]] && ((menu_height = menu_height - 1))
	[[ -n "${note:-}" ]] && ((menu_height = menu_height - 1))
	[[ -n "${var_current:-}" ]] && ((menu_height = menu_height - 1))
	((menu_height >= 4)) || menu_height=4

	# Call whiptail with whiptail_opts and menu_array
	msg="${prelude:+"${prelude:-}\\n"}${var_description:+"(${var_description})\\n"}${note:+"${note}\\n"}${var_current:+"Current: ${var_current}"}"
	result="$(whiptail "${whiptail_opts[@]}" --menu "${msg:-}" "${height}" "${width}" "${menu_height}" "${menu_array[@]}" 3>&1 1>&2 2>&3)" || return 1
	[[ -v result ]] && var_ref="${result:-}" && [[ "${export_result:-}" == 1 ]] && export "${!var_ref}"
	return 0
}

export TAGDIR="${TAGDIR:-}"
hyakvnc_config() {

	# Check if whiptail is available
	check_command whiptail || return 1
	# Exit on critical errors:

	local height width
	read -r height width < <(ui_screen_dims || true)
	local slurm_accounts=(escience '')
	local slurm_partitions=(gpu-a40 '' gpu-rtx6k '')

	[[ -z "${TAGDIR:-}" ]] && TAGDIR="$(mktemp --directory --dry-run || true)" && export TAGDIR
	export HYAKVNC_SLURM_ACCOUNT="${HYAKVNC_SLURM_ACCOUNT:-${slurm_accounts[0]}}"
	HYAKVNC_SLURM_PARTITION="${HYAKVNC_SLURM_PARTITION:-${slurm_partitions[0]}}"

	local -a main_menu_options=(
		1 "Select SLURM container ${HYAKVNC_APPTAINER_CONTAINER:+(${HYAKVNC_APPTAINER_CONTAINER##*/})}"
		2 "Set Slurm account ${HYAKVNC_SLURM_ACCOUNT:+(${HYAKVNC_SLURM_ACCOUNT})}"
		3 "Set Slurm partition ${HYAKVNC_SLURM_PARTITION:+(${HYAKVNC_SLURM_PARTITION})}"
		4 "Set number of CPUs ${HYAKVNC_SLURM_CPUS:+(${HYAKVNC_SLURM_CPUS})}"
		5 "Set amount of memory ${HYAKVNC_SLURM_MEM:+(${HYAKVNC_SLURM_MEM})}"
		6 "Set Slurm timelimit ${HYAKVNC_SLURM_TIMELIMIT:+(${HYAKVNC_SLURM_TIMELIMIT})}"
		7 "Set number of GPUs ${HYAKVNC_SLURM_GPUS:+(${HYAKVNC_SLURM_GPUS})}"
		8 "Add bind paths ${HYAKVNC_APPTAINER_ADD_BINDPATHS:+(${HYAKVNC_APPTAINER_ADD_BINDPATHS})}"
		9 "Advanced options"
		10 "Launch Session"
		11 "Exit"
	)

	while true; do
		local main_menu_choice
		main_menu_choice=$(whiptail --title "HyakVNC Configuration Wizard" --menu "Choose an option:" "${height}" "${width}" $((height - 8)) "${main_menu_options[@]}" 3>&1 1>&2 2>&3)

		case "${main_menu_choice:-}" in
			1)
				[[ ! -d "${TAGDIR}" ]] && trap 'rm -rf "${TAGDIR:-}"' EXIT

				select_container_image && ui_whip_error "No container image selected"
				;;
			2)
				#select_slurm_account 1 escience 2 lo || true
				ui_select_config_var --whiptail-opts --title hyakvnc -- HYAKVNC_SLURM_ACCOUNT 1 escience 2 lo || true
				;;
			3)
				ui_select_config_var --whiptail-opts --title hyakvnc -- HYAKVNC_SLURM_PARTITION 1 a 2 b c 3 || true
				;;

			4)
				ui_input_config_var -x HYAKVNC_SLURM_CPUS || true
				;;
			5)
				ui_input_config_var -x HYAKVNC_SLURM_MEM || true
				;;
			6)
				ui_input_config_var -x HYAKVNC_SLURM_TIMELIMIT || true
				;;
			7)
				ui_input_config_var -x HYAKVNC_SLURM_GPUS || true
				;;
			8)
				ui_input_config_var -x HYAKVNC_APPTAINER_ADD_BINDPATHS || true
				;;

			
				9) # Advanced options
				local -a advanced_options_array=()
				local key i=1
				for key in $(echo "${!Hyakvnc_Config_Descriptions[@]}" | tr ' ' '\n' | sort || true); do
					case "${key:-}" in
						HYAKVNC_SLURM_ACCOUNT | HYAKVNC_SLURM_PARTITION | HYAKVNC_SLURM_CPUS | HYAKVNC_SLURM_MEM | HYAKVNC_SLURM_TIMELIMIT | HYAKVNC_SLURM_GPUS) ;;
						*) advanced_options_array+=("${i}" "${key} ${!key:+(${!key})}")
						((i++))
							;;
					esac
				done
				local advanced_option_choice
				while true; do
					advanced_option_choice="$(whiptail --title "Advanced Option" --menu "Choose an option:" "${height}" "${width}" $((height - 8)) "${advanced_options_array[@]}" 3>&1 1>&2 2>&3)" || break
					[[ -z "${advanced_option_choice:-}" ]] && break
					local var_name="${advanced_options_array[$((advanced_option_choice * 2 - 1))]}"
					var_name="${var_name%% *}"
					ui_input_config_var -x HYAKVNC_SLURM_OUTPUT || exit 1
				done
				;;
			10)
				CMD="echo create -c ${HYAKVNC_APPTAINER_CONTAINER:-}"
				whiptail --msgbox "Generated Command:\n\n${CMD}" "${height}" "${width}"
				if (whiptail --yesno "Execute the command now?" 8 78 3>&1 1>&2 2>&3); then
					msg="$(eval "${CMD}")"
					echo "${msg}"
					echo
					read -r -p "Press enter to return to the menu"
				fi
				;;
			11) return 0 ;;
			*) echo "OK, I'll stop"
			return 0
				;;
		esac

	done
}

hyakvnc_config "$@"
