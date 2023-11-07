#! /usr/bin/env bash
# hyakvnc config - Show the current configuration for hyakvnc

# Only enable these shell behaviours if we're not being sourced
if ! (return 0 2>/dev/null); then
	# shellcheck source=_header.bash
	source "${BASH_SOURCE[0]%/*}/_header.bash"
fi

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

! (return 0 2>/dev/null) && cmd_config "$@"
