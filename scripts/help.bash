#! /usr/bin/env bash
# hyakvnc help - Show help for a command

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

COMMANDS="create status stop show config update install help"

TITLE="hyakvnc -- A tool for launching VNC sessions on Hyak."

# show_usage()
function show_usage() {
	local isinstalled
	isinstalled=$(command -v hyakvnc || echo '')
	[[ -n "${isinstalled:-}" ]] && isinstalled=" (is already installed!)"

	cat <<EOF
Usage: hyakvnc [hyakvnc options] [${COMMANDS// /|}] [command options] [args...]

Description:
	Stop a provided HyakVNC sesssion and clean up its job directory

Options:
	-h, --help		Show this help message and exit
	-d, --debug		Print debugging information
	-V, --version	Print version information and exit

Available commands:
	create	Create a new VNC session
	status	Check status of VNC session(s)
	stop	Stop a VNC session
	show	Show connection information for a VNC session
	config	Show current configuration for hyakvnc
	update	Update hyakvnc
	install	Install hyakvnc so the "hyakvnc" command can be run from anywhere.${isinstalled:-}
	help	Show help for a command

See 'hyakvnc help <command>' for more information on a specific command.

EOF
}

# help_help()
function help_help() {
	cat <<EOF
Show help for a command
Usage: hyakvnc [hyakvnc options] help <command>

Description:
	Show help for a command in hyakvnc

Options:
	-h, --help		Show this help message and exit
	-u, --usage		Print only usage information
	-V, --version	Print version information and exit
EOF
}

# cmd_help()
function cmd_help() {
	local action_to_help
	[[ $# == 0 ]] && {
		echo "${TITLE}"
		show_usage "$@"
		exit 0
	}

	while true; do
		case ${1:-} in
			-h | --help)
				help_help
				exit 0
				;;
			-u | --usage)
				shift
				show_usage "$@"
				exit 0
				;;
			*) break ;;
		esac
	done

	if [[ -r "${SCRIPTDIR}/${1:-}.bash" ]]; then
		action_to_help="${1:-}"
		shift
		"${SCRIPTDIR}/${action_to_help}.bash" --help "$@"

	else
		log ERROR "Can't show help for unknown command: \"${1:-}\". Available commands: ${COMMANDS}"
		echo
		show_usage "$@"
		exit 1
	fi

}

cmd_help "$@"
