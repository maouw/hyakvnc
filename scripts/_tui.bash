#!/usr/bin/env bash

# Only enable these shell behaviours if we're not being sourced
if ! (return 0 2>/dev/null); then
	# shellcheck source=_header.bash
	source "${BASH_SOURCE[0]%/*}/_header.bash"
fi

# Source the library if it hasn't been loaded already
if [[ "${_HYAKVNC_LIB_LOADED:-}" != 1 ]]; then
	# shellcheck source=_lib.bash
	source "${BASH_SOURCE[0]%/*}/_lib.bash"
fi

modified_args=()

export REMOTE_REPO=https://github.com/maouw/hyakvnc_apptainer
export TAG_PREFIX='sif-'

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

	choice="$(whiptail --title "hyakvnc" --menu "Select a container image" 0 0 0 "${found_tags[@]}" 3>&1 1>&2 2>&3)"
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
			container_dir="$(whiptail --inputbox "Enter the directory to search for container images:" 0 0 \
				"${1:-${HYAKVNC_CONTAINERDIR:-${CONTAINERDIR:-${PWD:-}}}}" \
				3>&1 1>&2 2>&3)" || { return 0; }
			[[ -d "${container_dir:-}" ]] && break
			whiptail --msgbox "Directory does not exist. Please try again." 0 0
		done

		while read -r line; do
			local tag desc
			tag=$(basename "${line}")
			desc="$(describe_sif "${line}" || true)"
			found_tags+=("${tag}" "${desc:--}")
		done <<<"$(list_local_images "${container_dir:-}" || true)"

		choice="$(whiptail --title "hyakvnc" --menu "Select a container image" 0 0 $((height - 8)) "${found_tags[@]}" 3>&1 1>&2 2>&3)" || break
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

	choice="$(whiptail --title "hyakvnc" --notags --menu "Where should I look for a container?" 0 0 0 "${found_tags[@]}" 3>&1 1>&2 2>&3)" || return 0

	case "${choice:-}" in
		1) selected_image="$(select_local_image || true)" ;;
		2) selected_image="$(select_remote_image "${REMOTE_REPO:-}" || true)" ;;
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
			whiptail --msgbox "Invalid URL. Please try again." 0 0
		done
			;;
		*) return 0 ;;
	esac

	export HYAKVNC_APPTAINER_CONTAINER="${selected_image:-${HYAKVNC_APPTAINER_CONTAINER:-}}"
	return 0
}

function ui_whip_error() {
	local height width
	read -r height width < <(ui_screen_dims || true)
	whiptail --title "hyakvnc - error" --msgbox "${1:-}" 0 0
}

function ui_input_config_var() {
	local height width var_current var_description prelude note result export_result as_default
	local -n var_ref
	read -r height width < <(ui_screen_dims || true)
	while [[ $# -gt 0 ]]; do
		case "${1:-}" in
			--prelude) shift || break; prelude="${1:-}" ;;
			--note) shift || break; note="${1:-}" ;;
			--current) shift || break; var_current="${1:-}" ;;
			--description) shift || break; var_description="${1:-}" ;;
			-x | --export) export_result="${1:-}" ;;
			--default) as_default="${1:-}" ;;
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

	local input_str=""
	#var_current="${var_current:-${!var_ref:-}}"
	var_current="${var_current:-${var_ref:-}}"

	# if [[ "${as_default:-0}" == "0" ]]; then
	# 	input_str="<default>"
	# else
	# 	input_str="${var_current:-<default>}"
	# fi
	msg="${prelude:+"${prelude:-}\\n"}${var_description:+"(${var_description})\\n"}${note:+"${note}\\n"}${var_current:+"Current: ${var_current}"}"
	result="$(whiptail --title "hyakvnc Configuration" --inputbox "${msg}" 0 0 "${input_str:-}" 3>&1 1>&2 2>&3)" || return 1
	# if [[ "${result:-<default>}" ==  "<default>" ]] ; then
	# 	result=
	# fi
	var_ref="${result:-}" && [[ "${export_result:-}" == 1 ]] && export "${!var_ref}"
	return 0
}

function ui_select_config_var() {
	local var_current var_description prelude note result export_result as_default
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
			--default)  as_default="${1:-}" ;;
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

	menu_array+=("<default>" "Reset to default value")
	((num_menu_items++))
	menu_array+=("<" "Return to previous menu")
	((num_menu_items++))

	# Set menu height to 1/2 of the number of menu items, or 10, whichever is smaller
	# ((menu_height = height - 8 - num_menu_items))
	# [[ -n "${prelude:-}" ]] && ((menu_height = menu_height - 1))
	# [[ -n "${var_description:-}" ]] && ((menu_height = menu_height - 1))
	# [[ -n "${note:-}" ]] && ((menu_height = menu_height - 1))
	# [[ -n "${var_current:-}" ]] && ((menu_height = menu_height - 1))
	# ((menu_height >= 4)) || menu_height=4

	# Call whiptail with whiptail_opts and menu_array
	msg="${prelude:+"${prelude:-}\\n"}${var_description:+"(${var_description})\\n"}${note:+"${note}\\n"}${var_current:+"Current: ${var_current}"}"

	result="$(whiptail "${whiptail_opts[@]}" --menu "${msg:-}" 0 0 0 "${menu_array[@]}" 3>&1 1>&2 2>&3)" || return 1
	[[ "${result:-<default>}" == "<default>" ]] && result=
	[[ -v result ]] && var_ref="${result:-}" && [[ "${export_result:-}" == 1 ]] && export "${!var_ref}"
	return 0
}

function ui_select_slurm_partition() {
	local current_account="${HYAKVNC_SLURM_ACCOUNT:-}"
	local current_partition="${HYAKVNC_SLURM_PARTITION:-}"
	local available_partitions=()
	local whiptail_opts=()
	local whiptail_box_opts=()
	local menu_array=()

	while [[ $# -gt 0 ]]; do
		case "${1:-}" in
			--prelude) shift || break; prelude="${1:-}" ;;
			--note) shift || break; note="${1:-}" ;;
			--current) shift || break; var_current="${1:-}" ;;
			--description) shift || break; var_description="${1:-}" ;;
			-x | --export) export_result="${1:-}" ;;
			--account) shift || break; current_account="${1:-}" ;;
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

	local listed_partitions=()
	if [[ "${HYAKVNC_MODE:-local}" == "slurm" ]]; then
		listed_partitions=($(slurm_list_partitions "${current_account:-}" || true))
	else
		listed_partitions+=("local")
	fi

	[[ "${#listed_partitions}" == 0 ]] && { ui_whip_error "No partitions available for account ${current_account:-}"; return 1; }
	local partitions_menu=()
	local p i=1
	for p in "${listed_partitions[@]}"; do
		partitions_menu+=("${i}" "${p}")
		((i++))
	done

	[[ "${#partitions_menu}" == 0 ]] && { ui_whip_error "No partitions available for account ${current_account:-}"; return 1; }

	[[ -n "${partitions_menu:-}" ]] || { ui_whip_error "No partitions available for account ${current_account:-}"; return 1; }
	ui_select_config_var --default -x --whiptail-opts --title hyakvnc -- HYAKVNC_SLURM_PARTITION "${partitions_menu[@]}" || true

}

export TAGDIR="${TAGDIR:-}"

hyakvnc_tui_main() {
	check_command whiptail || return 1
	local -a main_menu_options=(
		1 "Create a hyakvnc session"
		2 "Manage running hyakvnc sessions"
		3 "Configure hyakvnc"
		4 "Update hyakvnc"
		"<" "Exit"
	)
	local main_menu_choice-
	while true; do
		main_menu_choice="$(whiptail --title "hyakvnc" --menu "Choose an option:" 0 0 0 "${main_menu_options[@]}" 3>&1 1>&2 2>&3 || true)"
		case "${main_menu_choice:-}" in
			1)
				hyakvnc_tui_create || { ui_whip_error "Failed to create hyakvnc session"; continue; }
				;;
			2)
				hyakvnc_tui_manage || { ui_whip_error "Failed to list hyakvnc sessions"; continue; }
				;;
			3) hyakvnc_tui_configure || { ui_whip_error "Failed to list hyakvnc sessions"; continue; }
				;;
			4) hyakvnc_tui_update || { ui_whip_error "Did not update hyakvnc"; continue; }
				;;
			*) break ;;
		esac
	done
	return 0
}

ui_advanced_config() {
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
	advanced_options_array+=(0 "Back")
	((i++))

	local advanced_option_choice
	while true; do
		advanced_option_choice="$(whiptail --title "Advanced Option" --menu "Choose an option:" 0 0 0 "${advanced_options_array[@]}" 3>&1 1>&2 2>&3)" || break
		[[ -z "${advanced_option_choice:-}" ]] && break
		local var_name="${advanced_options_array[$((advanced_option_choice * 2 - 1))]}"
		var_name="${var_name%% *}"
		ui_input_config_var -x HYAKVNC_SLURM_OUTPUT || exit 1
	done

}
function ui_save_config() {
	echo
}

hyakvnc_tui_configure() {
	# Check if whiptail is available
	check_command whiptail || return 1
	# Exit on critical errors:

	local slurm_accounts=(escience '')
	local slurm_partitions=(gpu-a40 '' gpu-rtx6k '')

	[[ -z "${TAGDIR:-}" ]] && TAGDIR="$(mktemp --directory --dry-run || true)" && export TAGDIR
	export HYAKVNC_SLURM_ACCOUNT="${HYAKVNC_SLURM_ACCOUNT:-${slurm_accounts[0]}}"
	HYAKVNC_SLURM_PARTITION="${HYAKVNC_SLURM_PARTITION:-${slurm_partitions[0]}}"

	while true; do

		local -a main_menu_options=(
			1 "Select default SLURM container ${HYAKVNC_APPTAINER_CONTAINER:+(${HYAKVNC_APPTAINER_CONTAINER##*/})}"
			2 "Set default Slurm account ${HYAKVNC_SLURM_ACCOUNT:+(${HYAKVNC_SLURM_ACCOUNT})}"
			3 "Set default Slurm partition ${HYAKVNC_SLURM_PARTITION:+(${HYAKVNC_SLURM_PARTITION})}"
			4 "Set default number of CPUs ${HYAKVNC_SLURM_CPUS:+(${HYAKVNC_SLURM_CPUS})}"
			5 "Set default amount of memory ${HYAKVNC_SLURM_MEM:+(${HYAKVNC_SLURM_MEM})}"
			6 "Set default Slurm timelimit ${HYAKVNC_SLURM_TIMELIMIT:+(${HYAKVNC_SLURM_TIMELIMIT})}"
			7 "Set default number of GPUs ${HYAKVNC_SLURM_GPUS:+(${HYAKVNC_SLURM_GPUS})}"
			8 "Add default bind paths ${HYAKVNC_APPTAINER_ADD_BINDPATHS:+(${HYAKVNC_APPTAINER_ADD_BINDPATHS})}"
			9 "Advanced options"
			10 "Save configuration"
			"<" "Exit"
		)

		local main_menu_choice
		main_menu_choice=$(whiptail --title "hyakvnc configuration" --menu "Choose an option:" 0 0 0 "${main_menu_options[@]}" 3>&1 1>&2 2>&3)

		case "${main_menu_choice:-}" in
			1)
				[[ ! -d "${TAGDIR}" ]] && trap 'rm -rf "${TAGDIR:-}"' EXIT
				select_container_image || { ui_whip_error "No container image selected"; continue; }
				;;
			2) ui_input_config_var -x --default HYAKVNC_SLURM_ACCOUNT || { ui_whip_error "No SLURM account selected"; continue; }

				;;
			3) ui_select_slurm_partition --account "${HYAKVNC_SLURM_ACCOUNT:-}" -x --default || ui_whip_error "No SLURM partition selected"
			continue
			#ui_select_config_var --whiptail-opts --title hyakvnc -- HYAKVNC_SLURM_PARTITION 1 a 2 b c 3 || true
				;;

			4)
				ui_input_config_var -x --default HYAKVNC_SLURM_CPUS || true; continue
				;;
			5)
				ui_input_config_var -x --default HYAKVNC_SLURM_MEM || true; continue
				;;
			6)
				ui_input_config_var -x --default HYAKVNC_SLURM_TIMELIMIT || true; continue
				;;
			7)
				ui_input_config_var -x --default HYAKVNC_SLURM_GPUS || true; continue
				;;
			8)
				ui_input_config_var -x --default HYAKVNC_APPTAINER_ADD_BINDPATHS || true
				;;
			9) # Advanced options
				ui_advanced_config || true
				;;
			10) ui_save_config || true ;;
				# 			CMD="echo create -c ${HYAKVNC_APPTAINER_CONTAINER:-}"
				# 			whiptail --msgbox "Generated Command:\n\n${CMD}" 0 0
				# 			if (whiptail --yesno "Execute		10 "Save configuration"
				# the command now?" 8 78 3>&1 1>&2 2>&3); then
				# 				msg="$(eval "${CMD}")"
				# 				echo "${msg}"
				# 				echo
				# 				read -r -p "Press enter to return to the menu"
				# 			fi
				# 			;;
			*) echo "Exiting"
			return 0
				;;
		esac

	done
}

function hyakvnc_tui_create() {
	echo
}
! (return 0 2>/dev/null) && hyakvnc_tui_main "$@"
