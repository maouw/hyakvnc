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

# Check Bash version greater than 4:
if [[ "${BASH_VERSINFO:-0}" -lt 4 ]]; then
	echo "Requires Bash version > 4.x"
	exit 1
fi

# Check Bash version 4.4 or greater:
case "${BASH_VERSION:-0}" in
	4*) if [[ "${BASH_VERSINFO[1]:-0}" -lt 4 ]]; then
		echo "Requires Bash version > 4.x"
		exit 1
	fi ;;

	*) ;;
esac

REMOTE_REPO=https://github.com/maouw/hyakvnc_apptainer
TAG_FILTER='*.sif'
git  ls-remote --tags --refs

function main() {
	local height width tagdir found_tags
	command -v whiptail >/dev/null 2>&1 || { echo >&2 "Requires whiptail. Exiting."; exit 1; }
	command -v git >/dev/null 2>&1 || { echo >&2 "Requires git. Exiting."; exit 1; }

	tagdir="$(mktemp -d hyakvnc-hyakvnc_apptainer_repo_XXXXXX)" || { echo >&2 "Failed to create temporary directory. Exiting."; exit 1; }

	found_tags=()

	git clone --no-tags --bare --config remote.origin.fetch='refs/tags/sif*:refs/tags/sif*' "$REMOTE_REPO" "$tagdir" || { echo >&2 "Failed to clone repository. Exiting."; exit 1; }

	while read -r line; do
		local tag desc
		read tag desc <<<"$line"
		echo "tag: $tag desc: $desc"
		found_tags+=("$tag" "$desc")
	done <<<"$(git --git-dir="${tagdir}" tag -l -n)" #) | sed -E 's/(^\S*)\s*(.*)/\1 \2/' || true)"

	read -r height width < <(stty size)

	choice="$(whiptail --title "Menu example" --menu "Choose an option" "$height" "$width" $((height - 10)) \
		"${found_tags[@]}" 3>&1 1>&2 2>&3)" || { echo >&2 "Cancelled. Exiting."; exit 1; }
	echo "$choice"
}
main "$@"
