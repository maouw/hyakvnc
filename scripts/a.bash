#!/usr/bin/env bash
source "b.bash"

	declare -A DICT

function filldict {
	local -n dict
	dict="${1}"
	dict["a"]="1"
	dict["b"]="2"
	
	dict["c"]="3"
}

function foo {
	echo "foo"
	v="$(bar || true)"
	echo "v: $v"

	filldict DICT
	for k in "${!DICT[@]}"; do
		echo "$k: ${DICT[$k]}"
	done
	echo "${!DICT[@]}"
}
foo

echo "${!DICT[@]}"