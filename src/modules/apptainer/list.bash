#!/usr/bin/env bash
set -EuT -o pipefail
shopt -qs inherit_errexit
# shellcheck source-path=.
source "${BASH_SOURCE[0]%/*}/_lib.bash"
case "${XDEBUG:-}" in 1 | true | on | yes | y | t | enabled | enable | active | activate | 2) set -x ;; *) ;; esac

function m_apptainer_list() {
	local 0a args=(instance list)
	[[ -n "${1:-}" ]] && args+=("${1}?**")
	printf "ID\tCREATED\tSTATUS\tNAME\n"
	local  s 
	s="$(apptainer "${args[@]}")" || return 1
      
	local i=0     
 
	while IFS= read -r; do  
		local pid created state name id rest
		((i++ > 0)) || continue  
		read -r name pid rest <<<"${REPLY}" || return 1
		created="$(date --date "$(ps -p "${pid}" -o  lstart= || true)" '+%F %T %:z %Z')" || return 1
		state="$(ps -p "${pid}" -o state=)" || return 1
		id="${pid}--${name}"
		printf "%s\t%s\t%s\t%s\n" "${id}" "${created}" "${state}" "${name}"  
	done <<<"${s}"
	return 0	
}

! (return 0 2>/dev/null) && m_apptainer_list "$@"
