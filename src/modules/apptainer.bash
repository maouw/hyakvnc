#!/usr/bin/env bash
set -o pipefail
function m_apptainer_list() {
	local args=(instance list)
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
   
function m_apptainer_stop() { 
	apptainer instance stop -t 2  "$@"
}
    
function m_apptainer_start() {  
	apptainer instance start "$@"
}

declare -Ax m_apptainer_commands=(
	[list]=m_apptainer_list
	[stop]=m_apptainer_stop
	[start]=m_apptainer_start
)