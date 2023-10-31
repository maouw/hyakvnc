#! /usr/bin/env bash
# hyakvnc install - Install the hyakvnc command

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

# help_install()
function help_install() {
	cat <<EOF
Install the hyakvnc command

Usage: hyakvnc install [install options...]
	
Description:
	Install hyakvnc so the "hyakvnc" command can be run from anywhere.

Options:
	-h, --help			Show this help message and exit
	-i, --install-dir		Directory to install hyakvnc to (default: ~/.local/bin)
	-s, --shell [bash|zsh]	Shell to install hyakvnc for (default: \$SHELL or bash)

Examples:
	# Install
	hyakvnc install
	# Install to ~/bin:
	hyakvnc install -i ~/bin
EOF
}

# cmd_install()
function cmd_install() {
	local install_dir thisfile myshell shellrcpath

	if [[ $# -eq 0 ]]; then
		log ERROR "No arguments provided"
		help_install
		exit 1
	fi

	thisfile="${BASH_SOURCE[0]:-$0}"
	[[ -z "${thisfile:-}" ]] && {
		log ERROR "Failed to get script name"
		return 1
	}
	install_dir="${HOME}/.local/bin"

	# Parse arguments:
	while true; do
		case "${1:-}" in
			-h | --help)
				help_install
				return 0
				;;
			-i | --install-dir)
				shift
				[[ -z "${1:-}" ]] && {
					log ERROR "-i | --install-dir requires a non-empty option argument"
					return 1
				}
				install_dir="${1:-}"
				shift
				;;
			-s | --shell)
				shift
				[[ -z "${1:-}" ]] && {
					log ERROR "-s | --shell requires a non-empty option argument"
					return 1
				}
				myshell="${1:-}"
				shift
				;;
			-*)
				log ERROR "Unknown option for install: ${1:-}\n"
				return 1
				;;
			*)
				break
				;;
		esac
	done
	mkdir -p "${install_dir}" || {
		log ERROR "Failed to create install directory ${install_dir}"
		exit 1
	}
	[[ ! -d "${install_dir}" ]] && {
		log ERROR "Install directory ${install_dir} does not exist"
		return 1
	}
	[[ ! -w "${install_dir}" ]] && {
		log ERROR "Install directory ${install_dir} is not writable"
		return 1
	}

	cp "${thisfile}" "${install_dir}/hyakvnc" || {
		log ERROR "Failed to copy ${thisfile} to ${install_dir}/hyakvnc"
		return 1
	}
	chmod +x "${install_dir}/hyakvnc" || {
		log ERROR "Failed to make ${install_dir}/hyakvnc executable"
		return 1
	}

	myshell=$(basename "${myshell:-${SHELL:-bash}}")

	case "${myshell}" in
		bash)
			shellrcpath="${HOME}/.bashrc"
			;;
		zsh)
			shellrcpath="${ZDOTDIR:-${HOME}}/.zshrc"
			;;
		*)
			log ERROR "Unsupported shell ${myshell}"
			return 1
			;;
	esac

	# Add install directory to PATH if it's not already there
	if [[ ":${PATH}:" != *":${install_dir}:"* ]]; then
		if [[ ${install_dir} == "${HOME}/.local/bin" ]]; then
			echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >>"${shellrcpath}" && echo "Added \$HOME/.local/bin to PATH in ${shellrcpath}"
		else
			echo "export PATH=\"${install_dir}:\$PATH\"" >>"${shellrcpath}" && echo "Added ${install_dir} to PATH in ${shellrcpath}"
		fi
		echo "Run 'source ${shellrcpath}' to update your PATH"
	fi

	echo "Installed hyakvnc to ${install_dir}/hyakvnc"
	[[ "${myshell}" == "zsh" ]] && echo "Run 'rehash' to update your PATH"
}

cmd_install "$@"
