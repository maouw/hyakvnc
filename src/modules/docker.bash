#!/usr/bin/env bash

function m_docker_list() {
	local filter="${1:-}"
	local args=()
	printf "ID\tCREATED\tSTATUS\tNAME\n"
	args+=("--no-trunc"  --format "{{.ID}}\t{{.CreatedAt}}\t{{.State}}\t{{.Names}}")
	if [[ -n "${filter}" ]]; then
		args+=("--filter=name=^${filter}.+$")
	fi  
	docker ps "${args[@]}"
}

function m_docker_stop() {
	docker stop -t 2  "$@"
}

function m_docker_start() {
	docker start "$@"
}

declare -Ax m_docker_commands=(
	[list]=m_docker_list
	[stop]=m_docker_stop
	[start]=m_docker_start
)