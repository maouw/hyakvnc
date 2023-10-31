#! /usr/bin/env bash
# hyakvnc config - Show the current configuration for hyakvnc

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

# help_config()
function help_config() {
	cat <<EOF
Show the current configuration for hyakvnc

Usage: hyakvnc config [config options...]
	
Description:
	Show the current configuration for hyakvnc, as set in the user configuration file at ${HYAKVNC_CONFIG_FILE}, in the current environment, or the default values set by hyakvnc.

Options:
	-h, --help		Show this help message and exit

Examples:
	# Show configuration
	hyakvnc config
EOF
}

# cmd_config()
function cmd_config() {
	# Parse arguments:
	while true; do
		case "${1:-}" in
			-h | --help)
				help_config
				return 0
				;;
			-*)
				help log ERROR "Unknown option for config: ${1:-}\n"
				return 1
				;;
			*)
				break
				;;
		esac
	done
	export -p | sed -E 's/^declare\s+-x\s+//; /^HYAKVNC_/!d'
	return 0
}

cmd_config "$@"
