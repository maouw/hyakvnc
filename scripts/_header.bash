#! /usr/bin/env bash

# Common header for all scripts

# shellcheck disable=SC2292
[ "${XDEBUG:-}" = "1" ] && set -x # Set XDEBUG to print commands as they are executed
# shellcheck disable=SC2292
[ -z "${BASH_VERSION:-}" ] || [ "${BASH_VERSINFO:-0}" -lt 4 ] || [ "${BASH_VERSINFO:-0}" = 4 ] && [ "${BASH_VERSINFO[1]:-0}" -lt 4 ] && { echo >&2 "Requires Bash version > 4.x"; exit 1; }
set -o pipefail # Use last non-zero exit code in a pipeline
set -o errtrace # Ensure the error trap handler is inherited
set -o nounset  # Exit if an unset variable is used
# set -o errexit                 # Exit on error
# shopt -qs inherit_errexit      # Ensure subshells exit on error

# Source the library if it hasn't been loaded already
if [[ "${_HYAKVNC_LIB_LOADED:-}" != 1 ]]; then
	# shellcheck source=_lib.bash
	source "${BASH_SOURCE[0]%/*}/_lib.bash"
fi
