#! /usr/bin/env bash
# hyakvnc update - Update hyaknc

# Only enable these shell behaviours if we're not being sourced
if ! (return 0 2>/dev/null); then
	# shellcheck source=_header.bash
	source "${BASH_SOURCE[0]%/*}/_header.bash"
fi

# ## Update functions:

# hyakvnc_pull_updates()
# Pull updates from the hyakvnc git repository
# Arguments: None
# Returns: 0 if successfuly updated, 1 if not or if an error occurred
function hyakvnc_pull_updates() {
	local cur_branch
	[[ -z "${HYAKVNC_REPO_DIR:-}" ]] && {
		log ERROR "HYAKVNC_REPO_DIR is not set. Can't pull updates."
		return 1
	}
	cur_branch="$(git -C "${HYAKVNC_REPO_DIR}" branch --show-current 2>&1 || true)"
	[[ -z "${cur_branch}" ]] && {
		log ERROR "Couldn't determine current branch. Can't pull updates."
		return 1
	}

	[[ "${cur_branch}" != "main" ]] && {
		log WARN "Current branch is ${cur_branch}, not main. Be warned that this branch may not be up to date."
	}

	log INFO "Updating hyakvnc..."
	git -C "${HYAKVNC_REPO_DIR}" pull --quiet origin "${cur_branch}" || {
		log WARN "Couldn't apply updates"
		return 0
	}

	log INFO "Successfully updated hyakvnc."
	return 0
}

# hyakvnc_check_updates()
# Check if a hyakvnc update is available
# Arguments: None
# Returns: 0 if an update is available, 1 if none or if an error occurred
function hyakvnc_check_updates() {
	log DEBUG "Checking for updates... "
	# Check if git is installed:
	check_command git ERROR || return 1

	# Check if git is available and that the git directory is a valid git repository:
	git -C "${HYAKVNC_REPO_DIR}" tag >/dev/null 2>&1 || {
		log ERROR "Configured git directory ${HYAKVNC_REPO_DIR} doesn't seem to be a valid git repository. Can't check for updates"
		return 1
	}

	local cur_branch
	cur_branch="$(git -C "${HYAKVNC_REPO_DIR}" branch --show-current 2>&1 || true)"
	[[ -z "${cur_branch}" ]] && {
		log ERROR "Couldn't determine current branch. Can't pull updates."
		return 1
	}

	[[ "${cur_branch}" != "main" ]] && {
		log WARN "Current branch is ${cur_branch}, not main. Be warned that this branch may not be up to date."
	}

	local cur_date
	cur_date="$(git -C "${HYAKVNC_REPO_DIR}" show -s --format=%cd --date=human-local "${cur_branch}" || echo ???)"
	log INFO "The installed version was published ${cur_date}"

	touch "${HYAKVNC_REPO_DIR}/.last_update_check"

	# Get hash of local HEAD:
	if [[ "$(git -C "${HYAKVNC_REPO_DIR}" rev-parse "${cur_branch}" || true)" == "$(git -C "${HYAKVNC_REPO_DIR}" ls-remote --heads --refs origin "${cur_branch}" | cut -f1 || true)" ]]; then
		log INFO "hyakvnc is up to date."
		return 1
	fi

	git -C "${HYAKVNC_REPO_DIR}" fetch --quiet origin "${cur_branch}" || {
		log DEBUG "Failed to fetch from remote"
		return 1
	}

	local nchanges
	nchanges="$(git -C "${HYAKVNC_REPO_DIR}" rev-list HEAD...origin/"${cur_branch}" --count || echo 0)"
	if [[ "${nchanges}" -gt 0 ]]; then
		local new_date
		new_date="$(git -C "${HYAKVNC_REPO_DIR}" show -s --format=%cd --date=human-local origin/"${cur_branch}" || echo ???)"
		log INFO "Found ${nchanges} updates. Most recent: ${new_date}"
		return 0
	fi
	return 1
}

# hyakvnc_autoupdate()
# Unless updates were checked recenetly per $HYAKVNC_CHECK_UPDATE_FREQUENCY,
# 	check if a hyakvnc update is available. If running interactively, prompt
#	to apply update (or disable prompt in the future). If not running interactively,
#	apply the update.
# Arguments: None
# Returns: 0 if an update is available and the user wants to update, 1 if none or if an error occurred
# shellcheck disable=SC2120
function hyakvnc_autoupdate() {
	if [[ "${HYAKVNC_CHECK_UPDATE_FREQUENCY:-0}" == "-1" ]]; then
		log DEBUG "Skipping update check"
		return 1
	fi

	if [[ "${HYAKVNC_CHECK_UPDATE_FREQUENCY:-0}" != "0" ]]; then
		local update_frequency_unit="${HYAKVNC_CHECK_UPDATE_FREQUENCY:0-1}"
		local update_frequency_value="${HYAKVNC_CHECK_UPDATE_FREQUENCY:0:-1}"
		local find_m_arg=()

		case "${update_frequency_unit:=d}" in
		d)
			find_m_arg+=(-mtime "+${update_frequency_value:=0}")
			;;
		m)
			find_m_arg+=(-mmin "+${update_frequency_value:=0}")
			;;
		*)
			log ERROR "Invalid update frequency unit: ${update_frequency_unit}. Please use [d]ays or [m]inutes."
			return 1
			;;
		esac

		log DEBUG "Checking if ${HYAKVNC_REPO_DIR}/.last_update_check is older than ${update_frequency_value}${update_frequency_unit}..."

		if [[ -r "${HYAKVNC_REPO_DIR}/.last_update_check" ]] && [[ -z $(find "${HYAKVNC_REPO_DIR}/.last_update_check" -type f "${find_m_arg[@]}" -print || true) ]]; then
			log DEBUG "Skipping update check because the last check was less than ${update_frequency_value}${update_frequency_unit} ago."
			return 1
		fi

		log DEBUG "Checking for updates because the last check was more than ${update_frequency_value}${update_frequency_unit} ago."
	fi

	hyakvnc_check_updates || {
		log DEBUG "No updates found."
		return 1
	}

	if [[ -t 0 ]]; then # Check if we're running interactively
		while true; do     # Ask user if they want to update
			local choice
			read -r -p "Would you like to update hyakvnc? [y/n] [x to disable]: " choice
			case "${choice}" in
			y | Y | yes | Yes)
				log INFO "Updating hyakvnc..."
				hyakvnc_pull_updates || {
					log WARN "Didn't update hyakvnc"
					return 1
				}
				log INFO "Successfully updated hyakvnc. Restarting..."
				echo
				unset _HYAKVNC_LIB_LOADED
				exec "${0}" "${@}" # Restart hyakvnc
				;;
			n | N | no | No)
				log INFO "Not updating hyakvnc"
				return 1
				;;
			x | X)
				log INFO "Disabling update checks"
				export HYAKVNC_CHECK_UPDATE_FREQUENCY="-1"
				if [[ -n "${HYAKVNC_CONFIG_FILE:-}" ]]; then
					touch "${HYAKVNC_CONFIG_FILE}" && echo 'HYAKVNC_CHECK_UPDATE_FREQUENCY=-1' >>"${HYAKVNC_CONFIG_FILE}"
					log INFO "Set HYAKVNC_CHECK_UPDATE_FREQUENCY=-1 in ${HYAKVNC_CONFIG_FILE}"
				fi
				return 1
				;;
			*)
				echo "Please enter y, n, or x"
				;;
			esac
		done
	else
		hyakvnc_pull_updates || {
			log INFO "Didn't update hyakvnc"
			return 1
		}
	fi
	return 0
}

# help_update()
function help_update() {
	cat <<EOF
Update hyakvnc

Usage: hyakvnc update [update options...]
	
Description:
	Update hyakvnc.

Options:
	-h, --help		Show this help message and exit
	--autoupdate	Automatically check for updates and apply them if available
	--

Examples:
	# Update hyakvnc
	hyakvnc update
EOF
}

# cmd_update()
function cmd_update() {
	while true; do
		case "${1:-}" in
		-h | --help)
			help_update
			exit 0
			;;
		-*)
			log ERROR "Unknown option for ${FUNCNAME#cmd_}: ${1:-}"
			return 1
			;;
		*) break ;;
		esac
		shift
	done

	log INFO "Checking for updates..."
	if ! hyakvnc_check_updates; then
		log INFO "No updates to apply."
	else
		log INFO "Applying updates..."
		if ! hyakvnc_pull_updates; then
			log WARN "No updates applied."
			exit 1
		else
			log INFO "Update complete."
		fi
	fi
	exit 0
}

# If we're not being sourced, run cmd_update():
! (return 0 2>/dev/null) && cmd_update "$@"
