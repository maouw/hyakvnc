#!/bin/bash
# # Apptainer utility functions:
set -o pipefail
shopt -s checkwinsize
set -m

function log {
	echo "$*"
}

# ghcr_get_token_for_repo()
# Get a GitHub Container Registry token for a given repository
# Arguments: <url> (required)
# Returns: 0 if successful, 1 if not or if an error occurred
# Prints: The token to stdout
function ghcr_get_size_for_oras_image {
	local url image_ref repo repo_token image_tag manifest layer_size
	command -v curl >/dev/null 2>&1 || {
		log ERROR "curl is not installed!"
		return 1
	}
	command -v python3 >/dev/null 2>&1 || {
		log ERROR "python3 is not installed!"
		return 1
	}

	url="${1:-}"
	[[ -z "${url}" ]] && {
		log ERROR "URL must be specified"
		return 1
	}

	case "${url}" in
	ghcr.io/*)
		image_ref="${url#ghcr.io/}"
		repo="${image_ref%%:*}"
		image_tag="${image_ref##*:}"
		;;
	*) # Not a GitHub Container Registry URL
		log ERROR "URL ${url} is not a GitHub Container Registry URL"
		return 1
		;;
	esac

	repo_token="$(curl -sSL "https://ghcr.io/token?scope=repository:${repo}:pull&service=ghcr.io" | python3 -I -c 'import sys,json; print(json.load(sys.stdin)["token"])' 2>/dev/null || true)"
	[[ -z "${repo_token}" ]] && {
		log ERROR "Failed to get token for repository ${repo}"
		return 1
	}
	
	manifest="$(curl -sSL -H "Accept: application/vnd.oci.image.manifest.v1+json" -H "Authorization: Bearer ${repo_token}" "https://ghcr.io/v2/${repo}/manifests/${image_tag}")"
	[[ -z "${manifest}" ]] && {
		log ERROR "Failed to get manifest for repository ${repo}"
		return 1
	}
	layer_size=$(echo "${manifest}" | python3 -I -c 'import sys,json; v=json.load(sys.stdin); sys.exit(1) if len(v["layers"]) != 1 or not v["layers"][0]["mediaType"].startswith("application/vnd.sylabs.sif.layer") else print(v["layers"][0]["size"])' 2>/dev/null || true)
	[[ -z "${layer_size}" ]] && {
		log ERROR "Failed to get layer size for repository ${repo}"
		return 1
	}

	echo "${layer_size}"
	return 0
}

function progress_bar {
	local current total filled empty cols
	local current="${1:-}"
    local total="${2:-}"
	cols="${3:-}"
	[[ -z "${cols:-}" ]] && cols="$(tput cols)"


	filled=$((current*${cols}/total))
    empty=$((${cols}-filled))

    printf "["
	printf -- '#%.0s' {1..${filled}}
	printf -- ' %.0s' {1..${empty}}
	printf "]"


	for ((i=0;i<${empty};i++)); do
        printf " "
    done
    printf "]\n"
}

function bytes_to_human {
    local bytes=$1
    if [[ ${bytes} -lt 1024 ]]; then
        echo "${bytes}B"
    elif [[ ${bytes} -lt 1048576 ]]; then
        echo $((bytes/1024))"KB"
    elif [[ ${bytes} -lt 1073741824 ]]; then
        echo $((bytes/1048576))"MB"
    else
        echo $((bytes/1073741824))"GB"
    fi
}

function precache_interactive {
	local pid oras_tmp_path total_size current_size
	pid="${1:-}"
	[[ -z "${pid}" ]] && {
		log ERROR "PID must be specified"
		return 1
	}
	total_size="${2:-}"
	[[ -z "${total_size}" ]] && {
		log ERROR "Total size must be specified"
		return 1
	}

	command -v find >/dev/null 2>&1 || {
		log ERROR "find is not installed!"
		return 1
	}

    oras_tmp_path=$(find /proc/$pid/fd -type l -xtype f -lname '*apptainer*/oras/*tmp*' -printf '%l\n' -quit || true)
	[[ -z "${oras_tmp_path}" ]] && {
		log ERROR "Failed to find oras tmp path for PID ${pid}"
		return 1
	}

	while current_size="$(du -sb "${oras_tmp_path}" 2>/dev/null | cut -f1)"; do
		printf "Downloading image: %s / %s\n" "$(bytes_to_human "${current_size}" || true)" "$(bytes_to_human "${total_size}" || true)"
		sleep 1
		printf "\e[1A"
	done
	printf "\n"
}

url="${1:-ghcr.io/maouw/ubuntu22.04_turbovnc:latest}"
tmpfile="$(mktemp --suffix ".ghcr.oras.sif")"
trap 'kill -9 ${pidno}; echo killed ${pidno}; rm -rf "${tmpfile:-}"' EXIT TERM SIGTERM SIGQUIT

apptainer pull -F "${tmpfile}" "oras://${url}" 1>/dev/null 2>/dev/null &
pidno="${!}"
echo "PID: ${pidno}"
sleep 5
size="$(ghcr_get_size_for_oras_image "${url}")"
precache_interactive "${pidno}" "${size}"

wait  "${pidno}"
rm -f "${tmpfile}"
