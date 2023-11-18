#!/usr/bin/env bash

function bar {
	if [[ -t 1 ]]; then
		echo "-t1 bar"
	else
	echo "bar"
	fi
}

! (return 0 2>/dev/null) && bar "$@"
