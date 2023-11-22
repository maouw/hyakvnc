#! /usr/bin/env bash
# shellcheck disable=SC2292

[[ -n "${XDEBUG:-}" ]] && [[ "${XDEBUG^^}" =~ ^(1|TRUE|ON|YES)$ ]] && { PS4=':${LINENO}+'; set -x; }
set -o pipefail -o errtrace  -o functrace
shopt -qs inherit_errexit || true
shopt -qs lastpipe || true
shopt -qs extglob || true
shopt -qs nullglob || true

SCRIPTDIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=/dev/null
source "${SCRIPTDIR}/_lib.bash"


function tui_main_menu() {
	local -n actions
	[[ -n "${1:-}" ]] && actions="$1"
	[[ -R actions ]] || { unset actions; local -A actions=(); }
	while true; do
		local -i n_sessions
		n_sessions="$("${actions[count_active]:-default_action_count_active}")"
		local -a main_menu=(
			"list" "Active Sessions (${n_sessions:-0})"
			"launch" "Launch Session"
			"config" "Configuration"
			"help" "Help"
		)
		local option retval
		option="$(whiptail --title "${FUNCNAME[0]}" --notags --menu "Choose an option" 0 0 0 "${main_menu[@]}" 3>&1 1>&2 2>&3)"
		retval="${?}"; [[ -z "${option:-}" ]] || ((retval != 0)) && return "${retval}"
		case "${option:=}" in
			list | launch | config | help) "${actions[${option}]:-default_action_${option}}"; continue ;;
			exit) return "${actions[${option}]:-default_action_${option}}" ;;
			*) whiptail --title "${FUNCNAME[0]}" --msgbox "Selected option: ${option:-}" 0 0 3>&1 1>&2 2>&3 ;;

		esac

	done
}

function default_action_count_active() {
	echo 0
}
function default_action_list() {
	while true; do
		local -a menu=()
		local -a items=("session one" "session two" "session three");
		local -i i=1
		local item
		for item in "${items[@]}"; do
			menu+=("${i}" "${item}")
			((i++))
		done
		local option retval
		option="$(whiptail --title "${FUNCNAME[0]}" --notags --menu "Choose an option" 0 0 0 "${menu[@]}" 3>&1 1>&2 2>&3)"
		retval="${?}"; [[ -z "${option:-}" ]] || ((retval != 0)) && return "${retval}"
		whiptail --title "${FUNCNAME[0]}" --msgbox "Selected option: ${option:-}" 0 0 3>&1 1>&2 2>&3

	done

}

function default_action_launch() {
	local option retval
	option="$(whiptail --title "${FUNCNAME[0]}" --msgbox "Launch" 0 0 3>&1 1>&2 2>&3)"
	retval="${?}"; [[ -z "${option:-}" ]] || ((retval != 0)) && return "${retval}"
	whiptail --title "${FUNCNAME[0]}" --msgbox "Selected option: ${option:-}" 0 0 3>&1 1>&2 2>&3
	log TRACE "Selected option: ${option}"
}

function default_action_config() {
	while true; do
		local -a menu=(
			"general" "General"
			"session" "Session"
			"advanced" "Advanced"
			"var" "Variable"
		)
		local option retval
		option="$(whiptail --title "${FUNCNAME[0]}" --notags --menu "Choose an option" 0 0 0 "${menu[@]}" 3>&1 1>&2 2>&3)"
		retval="${?}"; [[ -z "${option:-}" ]] || ((retval != 0)) && return "${retval}"
		case "${option:=}" in
			var)
				"${actions[${option}]:-default_action_config_var}" var ;;
			exit) return "${actions[${option}]:-default_action_${option}}" ;;
			*) log ERROR "Invalid option: ${option}"; return 1 ;;
		esac
	done
}

function default_action_help() {
	while true; do
		local -a menu=(
			"help:general" "General"
			"help:session" "Session"
			"help:advanced" "Advanced"
		)
		local option retval
		option="$(whiptail --title "${FUNCNAME[0]}" --notags --menu "Choose an option" 0 0 0 "${menu[@]}" 3>&1 1>&2 2>&3)"
		retval="${?}"; [[ -z "${option:-}" ]] || ((retval != 0)) && return "${retval}"
		whiptail --title "${FUNCNAME[0]}" --msgbox "Selected option: ${option:-}" 0 0 3>&1 1>&2 2>&3
	done

}

function default_action_exit() {
	local option retval
	option="$(whiptail --title "Exit" --msgbox "Exit" 0 0 3>&1 1>&2 2>&3)"
	retval="${?}"; [[ -z "${option:-}" ]] || ((retval != 0)) && return "${retval}"
	whiptail --title "${FUNCNAME[0]}" --msgbox "Selected option: ${option:-}" 0 0 3>&1 1>&2 2>&3
	return 0
}

function tui_log() {
	local level
	log "$@"
	level="${1:-INFO}"
	shift
	whiptail --title "${level}" --msgbox "${*:-}" 0 0 3>&1 1>&2 2>&3
	retval="${?}"; [[ -z "${option:-}" ]] || ((retval != 0)) && return "${retval}"
}



do_parse_options() {
	# do_parse_options a b c d 
	local -n __do_parse_options_options_ref="$1"
	local -n __do_parse_options_parsed_options_ref="$2"
	local __do_parse_options_param
	local -A __do_parse_options_short_to_long=()
	local -A __do_parse_options_types=()
	# [ -v 'array[i]' ];

	shift 2
	local ____do_parse_options_options_ref_key
	for ____do_parse_options_options_ref_key in "${!__do_parse_options_options_ref[@]}"; do
		__do_parse_options_types["${____do_parse_options_options_ref_key}"]="${____do_parse_options_options_ref_key}"
	done

	while (($# > 0)); do
		local __do_parse_options_param="$1"
		case "${1:-}" in
			--?*= | -?*=)
				set -- "${1%%=*}" "${1#*=}" "${@:2}"
				continue
				;;
			--?*)
				[[ -v '__do_parse_options_types[${1}]' ]] || { log ERROR "Unknown option \"$1\""; return 1; }
				local __do_parse_options_param="$1"
				local __do_parse_options_type="${__do_parse_options_options_ref[${__do_parse_options_param}]}"
				shift || { log ERROR "$1 requires an argument"; return 1; }
				case "${__do_parse_options_type:-}" in
					--) __do_parse_options_parsed_options_ref["${__do_parse_options_param}"]="$1" ;;
					-b) 
					while (($# > 0)) ; do
				 			case "${1:---}" in
				 				--) shift; break ;;
				 				?*) __do_parse_options_parsed_options_ref["${__do_parse_options_param}"]+=("$1") ;;
				 				*) break ;;
				 			esac
				 			shift
					done
					;;
					*) __do_parse_options_parsed_options_ref["${__do_parse_options_param}"]="$1" ;;
				esac
			
				# param="${param#-}" param="${param//-/_}" param="p_${param}"
				# local -n __tui_config_multi_param_ref="${param}"
				# [[ -R "${__tui_config_multi_param_ref}" ]] || { log ERROR "Unknown option \"$1\""; return 1; }
				# case "${!__tui_config_multi_param_ref@a}" in
	
				# 	*i*)
				# 		echo "Using integer"
				# 		__tui_config_multi_param_ref=1;;
				# *a* | *A*)
				# 		while (($# > 0)) ; do
				# 			case "${1:---}" in
				# 				--) shift; break ;;
				# 				?*) __tui_config_multi_param_ref+=("$1") ;;
				# 				*) break ;;
				# 			esac
				# 			shift
				# 		done
				# 		continue
				# 		;;
				# 	*) 	shift || { log ERROR "$1 requires an argument"; return 1; }

				# 		__tui_config_multi_param_ref="$1" ;;
				;;
			?*) log ERROR "Unknown option \"${1:-}\""; return 1 ;;
			*) break ;;
		esac
		shift
	done
}
 
		msg_lines+="\nDefault value: ${var_default_meta_str}"
		[[ -n "${p_var_type:-}" ]] && msg_lines+="\nType: ${p_var_type}"
		[[ -n "${p_var_options:-}" ]] && msg_lines+="\nOptions: ${p_var_options}"

		if [[ -n "${p_var_desc:-}" ]]; then
			msg_lines+="\nDescription:"
			local i=0
			local line lines
			lines="$(echo -e "${p_var_desc:-}" | sed 's/^/  /' || echo -e "${p_var_desc:-}")"
			msg_lines+="\n${lines}"
		fi

		local -a menu=(
			"modify" "Modify"
			"reset" "Reset"
			"info" "Info"
		)
		local option retval
		option=$(whiptail --title "${title}" --notags --menu "${msg_lines}" 0 0 0 "${menu[@]}" 3>&1 1>&2 2>&3)
		retval="${?}"; [[ -z "${option:-}" ]] || ((retval != 0)) && return "${retval}"
		set -x
		case "${option:=}" in

			modify)

				if [[ -R p_var_selections_ref ]]; then
					echo "selections: ${p_var_selections_ref[*]}"
					local -a selection_menu=()
					local -i i=0
					local selection
					local state

					if [[ "${var_opt_multi:-0}" == "0" ]]; then
						for selection in "${p_var_selections_ref[@]}"; do
							selection_menu+=("$((i++))" "${selection}")
						done
						new_value="$(whiptail --title "${title}" --notags --menu "Choose an option" 0 0 0 "${selection_menu[@]}" 3>&1 1>&2 2>&3)"
						retval="${?}"; ((retval != 0)) && return "${retval}"
						p_var_ref="${p_var_selections_ref[${new_value}]:-}"
					else
						local -A selection_states=()
						for selection in "${p_var_ref[@]}"; do
							selection_states["${selection}"]=1
						done

						declare -p selection_states
						for selection in "${p_var_selections_ref[@]}"; do
							selection_states["${selection}"]="${selection_states[${selection}]:-0}"
							selection_menu+=("$((i++))" "${selection}" "${selection_states[${selection}]:-0}")
						done

						declare -p selection_states
						declare -p selection_menu
						local -a new_values=()
						new_value="$(whiptail --title "${title}" --notags --checklist "Choose an option" 0 0 0 "${selection_menu[@]}" 3>&1 1>&2 2>&3)"
						retval="${?}"; ((retval != 0)) && return "${retval}"
						new_value="${new_value//\"/}"
						local selection_i
						declare -p "${!p_var_selections_ref}"
						for selection_i in ${new_value}; do
							selection_i="${selection_i// /}"
							[[ -n "${selection_i:-}" ]] && selection="${p_var_selections_ref[${selection_i}]:-}" && [[ -n "${selection-}" ]] && new_values+=("${selection:-}")
						done
						declare -p new_values
						if [[ "${#new_values[@]}" == "0" ]]; then
							p_var_ref=('\0')
						else
							p_var_ref=("${new_values[@]}")
						fi
						declare -p "${!p_var_ref}"
					fi

					set +x
					continue
				else

					new_value="$(whiptail --title "${title}" --inputbox "Enter new value" 0 0 "${p_var_ref:-}" 3>&1 1>&2 2>&3)"
					retval="${?}"; ((retval != 0)) && return "${retval}"
					# shellcheck disable=SC2178
					p_var_ref="${new_value}"
				fi
				;;
			reset)
				if whiptail --title "${title}" --yesno "Reset ${!p_var_ref} to ${var_default_meta_str}?\nCurrent value: ${p_var_ref:-'**unset**'}" 0 0 "${p_var_ref:-}" 3>&1 1>&2 2>&3; then
					# shellcheck disable=SC2178
					p_var_ref="${p_var_default:-}"
				fi
				;;
			info)
				whiptail --title "${title}" --msgbox "Info" 0 0 3>&1 1>&2 2>&3
				;;
			*) ;;
		esac
	done
	reutrn 0
}

## \! (return 0 2>/dev/null) && tui_main_menu "$@"
shopt -qs xpg_echo

foo() {
	local somevar='somevalue'
	#	default_action_config_var --var-ref somevar --var-desc 'a description of somevar\ninfo' --var-options asxc --var-type string
	#	tui_log INFO "somevar: ${somevar}"
	echo "somevar: ${somevar}"

	local someselvar='two'
	local -a someselvar_selections=(one two three four)
	#	default_action_config_var --var-ref someselvar --var-desc 'a description of someselvar\ninfo' --var-options asxc --var-selections-ref someselvar_selections
	#	tui_log INFO "someselvar: ${someselvar}"
	echo "someselvar: ${someselvar}"

	local -a someselvars=(one four)
	local -p someselvars
	default_action_config_var --var-ref someselvars --var-desc 'a description of someselvars\ninfo' --var-options asxmc --var-selections-ref someselvar_selections
	#	tui_log INFO "someselvars: ${someselvars[*]}"
	echo "someselvars: ${someselvars[*]}"
}

if ! (return 0 2>/dev/null); then
	#tui_config_multi "$@"
	declare -A options=(
		['--choices']='--' ['--states']='--' ['--title']='' ['--use-title']='-b'
	)
	declare -A parsed_options=(
		[--choices]=''
		[--states]=''
		[--title]=''
		[--use_title]=0
	)
	set -x
	tui_config_multi --choices one two three -- --states one three --
fi