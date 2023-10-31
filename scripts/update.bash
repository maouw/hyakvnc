#! /usr/bin/env bash

# hyakvnc update - Update hyaknc

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

# help_update()
function help_update() {
	cat <<EOF
Update hyakvnc

Usage: hyakvnc update [update options...]
	
Description:
	Update hyakvnc.

Options:
	-h, --help			Show this help message and exit

Examples:
	# Update hyakvnc
	hyakvnc update
EOF
}

# cmd_update()
function cmd_update() {
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
}

cmd_update "$@"
