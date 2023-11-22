#!/usr/bin/env bash
set -EuT -o pipefail
shopt -qs inherit_errexit
source "${BASH_SOURCE[0]%/*}/_lib.bash"
case "${XDEBUG:-}" in 1 | true | on | yes | y | t | enabled | enable | active | activate | 2) set -x ;; *) ;; esac

function m_apptainer_create() {  
	apptainer instance start "$@"
}

! (return 0 2>/dev/null) && m_apptainer_create "$@"
