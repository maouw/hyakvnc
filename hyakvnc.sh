#! /usr/bin/env bash

HYAKVNC_VERSION="0.3.0"
if [ -n "${XDEBUG:-}" ]; then
	set -x
fi

# hyakvnc - A script to launch VNC sessions on Hyak

# = Preferences and settings:
# == App preferences:
HYAKVNC_LOG_PATH="${HYAKVNC_LOG_PATH:-$HOME/.hyakvnc.log}"
HYAKVNC_LOG_LEVEL="${HYAKVNC_LOG_LEVEL:-INFO}"
HYAKVNC_DIR="${HYAKVNC_DIR:-$HOME/.hyakvnc}"
HYAKVNC_CONFIG_DIR="${HYAKVNC_CONFIG_DIR:-$HOME/.config/hyakvnc}"
HYAKVNC_SSH_HOST="${HYAKVNC_SSH_HOST:-klone.hyak.uw.edu}"
HYAKVNC_VNC_PASSWORD="${HYAKVNC_VNC_PASSWORD:-password}"
HYAKVNC_VNC_DISPLAY="${HYAKVNC_VNC_DISPLAY:-:1}"

HYAKVNC_STANDARD_TIMEOUT="${HYAKVNC_STANDARD_TIMEOUT:-30}" # How long to wait for a command to complete before timing out

# === macOS bundle identifiers for VNC viewer executables:
HYAKVNC_MACOS_VNC_VIEWER_BUNDLEIDS="${HYAKVNC_MACOS_VNC_VIEWER_BUNDLEIDS:-com.turbovnc.vncviewer.VncViewer com.realvnc.vncviewer com.tigervnc.vncviewer}"

# == Apptainer preferences:
HYAKVNC_CONTAINER="${HYAKVNC_CONTAINER:-}"                                       # Path to container image
HYAKVNC_APPTAINER_BIN="${HYAKVNC_APPTAINER_BIN:-apptainer}"                      # Name of apptainer binary
HYAKVNC_APPTAINER_CONFIG_DIR="${HYAKVNC_APPTAINER_CONFIG_DIR:-$HOME/.apptainer}" # Path to apptainer config directory

HYAKVNC_APPTAINER_WRITABLE_TMPFS="${HYAKVNC_APPTAINER_WRITABLE_TMPFS:-${APPTAINER_WRITABLE_TMPFS:-1}}" # Whether to use a writable tmpfs for the container
HYAKVNC_APPTAINER_CLEANENV="${HYAKVNC_APPTAINER_CLEANENV:-${APPTAINER_CLEANENV:-1}}"                   # Whether to use a clean environment for the container
HYAKVNC_SET_APPTAINER_BIND_PATHS="${HYAKVNC_SET_APPTAINER_BIND_PATHS:-}"                               # Bind paths to set for the container
HYAKVNC_SET_APPTAINER_ARGS="${HYAKVNC_SET_APPTAINER_ARGS:-}"                                           # Environment variables to set for the container
HYAKVNC_APPTAINER_VNC_APP_NAME="${HYAKVNC_APPTAINER_VNC_APP_NAME:-vncserver}"                          # Name of the VNC app in the container (the %appstart section)

# == Slurm preferences:
HYAKVNC_SLURM_JOB_PREFIX="${HYAKVNC_SLURM_JOB_PREFIX:-hyakvnc-}"
HYAKVNC_SBATCH_POST_TIMEOUT="${HYAKVNC_SBATCH_POST_TIMEOUT:-120}"                   # How long after submitting via sbatch to wait for the job to start before timing out
HYAKVNC_SLURM_OUTPUT="${HYAKVNC_SLURM_OUTPUT:-${SBATCH_OUTPUT:-}}"                  # Where to send sbatch output
HYAKVNC_SLURM_JOB_NAME="${HYAKVNC_SLURM_JOB_NAME:-${SBATCH_JOB_NAME:-}}"            # Name of the sbatch job
HYAKVNC_SLURM_ACCOUNT="${HYAKVNC_SLURM_ACCOUNT:-${SBATCH_ACCOUNT:-}}"               # Slurm account to use
HYAKVNC_SLURM_PARTITION="${HYAKVNC_SLURM_PARTITION:-${SBATCH_PARTITION:-}}"         # Slurm partition to use
HYAKVNC_SLURM_CLUSTER="${HYAKVNC_SLURM_CLUSTER:-${SBATCH_CLUSTERS:-}}"              # Slurm cluster to use
HYAKVNC_SLURM_GRES="${HYAKVNC_SLURM_GRES:-${SBATCH_GRES:-}}"                        # Number of GPUs to request
HYAKVNC_SLURM_MEM="${HYAKVNC_SLURM_MEM:-${SBATCH_MEM:-2G}}"                         # Amount of memory to request
HYAKVNC_SLURM_CPUS="${HYAKVNC_SLURM_CPUS:-4}"                                       # Number of CPUs to request
HYAKVNC_SLURM_TIMELIMIT="${HYAKVNC_SLURM_TIMELIMIT:-${SBATCH_TIMELIMIT:-12:00:00}}" # Slurm timelimit to use

# = Global variables:
LAUNCHED_JOBIDS=() # Array of launched jobs

# = Utility functions:

declare -A log_levels=(["OFF"]=0 ["FATAL"]=1 ["ERROR"]=2 ["WARN"]=3 ["INFO"]=4 ["DEBUG"]=5 ["TRACE"]=6 ["ALL"]=100)
declare -A log_level_colors=(["FATAL"]=5 ["ERROR"]=1 ["WARN"]=3 ["INFO"]=4 ["DEBUG"]=6 ["TRACE"]=2)

function log {
	local level levelno colorno curlevelno funcname
	[ $# -lt 1 ] && return 1
	local level=${1:-}
	shift
	HYAKVNC_LOG_LEVEL="${HYAKVNC_LOG_LEVEL:-INFO}"
	[ -z "${level}" ] && echo "${FUNCNAME[0]}(): log level" && return 1
	levelno="${log_levels[${level}]}"
	[ -z "${levelno}" ] && echo >&2 "Unknown log level: ${level}" && return 1
	curlevelno="${log_levels[${HYAKVNC_LOG_LEVEL}]}"
	[ -z "${curlevelno}" ] && echo >&2 "Unknown log level: ${HYAKVNC_LOG_LEVEL}" && return 1
	curlevelno="${curlevelno:-${log_levels[INFO]}}"
	[ "${curlevelno}" -lt "${levelno}" ] && return 0
	colorno="${log_level_colors[${level}]}"
	[ -z "${colorno}" ] && colorno=0
	funcname=""
	# [ "${levelno}" -ge "${log_level_colors[DEBUG]}" ] && funcname="${FUNCNAME[1]}() - "

	# If we're in a terminal, use colors:
	tput setaf "$colorno" 2>/dev/null
	(printf "%s: %s" "${level}" "${funcname}" >&2) 2> >(tee -a "${HYAKVNC_LOG_PATH:-/dev/null}")
	tput sgr0 2>/dev/null
	(printf "%s\n" "${*}" >&2) 2> >(tee -a "${HYAKVNC_LOG_PATH:-/dev/null}")
}

# get_default_slurm_cluster()
# Get the default SLURM cluster
function get_default_slurm_cluster {
	local cluster
	# Get the default cluster:
	cluster=$(sacctmgr show cluster -nPs format=Cluster)
	[ -z "${cluster}" ] && log ERROR "Failed to get default cluster" && return 1
	echo "${cluster}"
}

# get_default_slurm_account()
# Get the default SLURM account
function get_default_slurm_account {
	local account
	# Get the default account:
	account=$(sacctmgr show user -nPs "${USER}" format=defaultaccount | grep -o -m 1 -E '\S+') || { log ERROR "Failed to get default account" && return 1; }
	echo "${account}"
}

# get_slurm_partitions()
# Gets the SLURM partitions for the specified user and account on the specified cluster
function get_slurm_partitions {
	local partitions
	partitions=$(sacctmgr show -nPs user "${1}" format=qos where account="${2}" cluster="${3}" | grep -o -m 1 -E '\S+' | tr ',' ' ') || { log ERROR "Failed to get SLURM partitions" && return 1; }
	# Remove the account prefix from the partitions and return
	echo "${partitions//${2:-}-/}" && return 0
}

# get_default_slurm_partition()
# Gets the SLURM partitions for the specified user and account on the specified cluster
function get_default_slurm_partition {
	local partition partitions
	partitions=$(get_slurm_partitions "${1}" "${2}" "${3}") || { log ERROR "Failed to get SLURM partitions" && return 1; }
	[ -z "${partitions}" ] && log ERROR "Failed to get default SLURM partition" && return 1
	partition="${partitions% *}"
	[ -z "${partition}" ] && log ERROR "Failed to get default SLURM partition" && return 1
	echo "${partition}" && return 0
}

# expand_slurm_node_range()
# Expand a SLURM node range to a list of nodes
function expand_slurm_node_range {
	[ -z "${1:-}" ] && return 1
	result=$(scontrol show hostnames --oneliner "${1}" | grep -oE '^.+$' | tr ' ' '\n') || return 1
	echo "${result}" && return 0
}

# get_slurm_job_info()
# Get info about a SLURM job, given a list of job IDs
function get_slurm_job_info {
	[ $# -eq 0 ] && log ERROR "User or Job ID must be specified" && return 1

	local user="${1:-${USER}}"
	[ -z "${user}" ] && log ERROR "User must be specified" && return 1
	shift
	local squeue_format_fields='%i %j %a %P %u %T %M %l %C %m %D %N'
	squeue_format_fields="${squeue_format_fields// /\t}" # Replace spaces with tab
	local squeue_args=(--noheader --user "${user}" --format "${squeue_format_fields}")

	local jobids="${*:-}"
	if [ -n "${jobids}" ]; then
		jobids="${jobids//,/ }" # Replace commas with spaces
		squeue_args+=(--job "${jobids}")
	fi
	squeue "${squeue_args[@]}"
}

# get_squeue_job_status
# Get the status of a SLURM job, given a job ID
function get_squeue_job_status {
	local jobid="${1:-}"
	[ -z "${jobid}" ] && log ERROR "Job ID must be specified" && return 1
	squeue -j "${1}" -h -o '%T' || { log ERROR "Failed to get status for job ${jobid}" && return 1; }
}

# stop_hyakvnc_session
# Stop a Hyak VNC session, given a job ID
function stop_hyakvnc_session {
	local jobid should_cancel no_rm
	while true; do
		case ${1:-} in
		-c | --cancel)
			shift
			should_cancel=1
			;;
		--no-rm) # Don't remove the job directory
			shift
			no_rm=1
			;;
		*)
			jobid="${1:-}"
			break
			;;
		esac
	done

	[ -z "${jobid}" ] && log ERROR "Job ID must be specified" && return 1
	log DEBUG "Stopping VNC session for job ${jobid}"
	local jobdir pid
	jobdir="${HYAKVNC_DIR}/jobs/${jobid}"
	if [ -d "${jobdir}" ]; then
		local pidfile
		for pidfile in "${jobdir}/vnc/"*"${HYAKVNC_VNC_DISPLAY}".pid; do
			if [ -e "${pidfile}" ]; then
				read -r pid <"${pidfile}"
				[ -z "${pid}" ] && log WARN "Failed to get pid from ${pidfile}" && break
				srun --jobid "${jobid}" kill "${pid}" || log WARN "Failed to stop VNC process for job ${jobid} with pid ${pid}"
				break
			fi
		done
		[ -n "${no_rm}" ] || rm -rf "${jobdir}/vnc" && log DEBUG "Removed VNC directory ${jobdir}/vnc"
	else
		log WARN "Job directory ${jobdir} does not exist"
	fi

	if [ -n "${should_cancel}" ]; then
		log INFO "Cancelling job ${jobid}"
		scancel "${jobid}" || log ERROR "Failed to cancel job ${jobid}"
	fi
	return 0
}

# print_connection_info()
# Print connection instructions for a job, given job ID
# Arguments: -j | --jobid <jobid> (required) [ -p | --viewer-port <viewer_port> ] [ -n |--node <node> ] [ -s | --ssh-host <ssh_host> ]
#
# The generated connection string should look like this, depending on the the OS:
# ssh -f -L 6111:'/mmfs1/home/altan/.hyakvnc/jobs/14930429/socket.uds' -J altan@klone.hyak.uw.edu altan@g3071 sleep 10; vncviewer localhost:6111
function print_connection_info {
	local jobid jobdir node socket_path viewer_port launch_hostname ssh_host
	viewer_port="${HYAKVNC_LOCALHOST_PORT:-5901}"
	ssh_host="${HYAKVNC_SSH_HOST:-klone.hyak.uw.edu}"

	# Parse arguments:
	while true; do
		case ${1:-} in
		-j | --jobid)
			shift
			jobid="${1:-}"
			shift
			;;
		-p | --viewer-port)
			shift
			viewer_port="${1:-viewer_port}"
			shift
			;;
		-n | --node)
			shift
			node="${1:-}"
			shift
			;;
		-s | --ssh-host)
			shift
			ssh_host="${1:-}"
			shift
			;;
		-*)
			log ERROR "Unknown option for print_connection_info: ${1:-}\n"
			return 1
			;;
		*)
			break
			;;
		esac
	done

	# Check arguments:
	[ -z "${jobid}" ] && log ERROR "Job ID must be specified" && return 1
	[ -z "${viewer_port}" ] && log ERROR "Viewer port must be specified" && return 1
	[ -z "${ssh_host}" ] && log ERROR "SSH host must be specified" && return 1

	jobdir="${HYAKVNC_DIR}/jobs/${jobid}"
	[ -d "${jobdir}" ] || { log ERROR "Job directory ${jobdir} does not exist" && return 1; }

	socket_path="${HYAKVNC_DIR}/jobs/${jobid}/socket.uds"
	[ -e "${socket_path}" ] || { log ERROR "Socket file ${socket_path} does not exist" && return 1; }
	[ -S "${socket_path}" ] || { log ERROR "Socket file ${socket_path} is not a socket" && return 1; }

	[ -n "$node" ] || node=$(squeue -h -j "${jobid}" -o '%N' | grep -o -m 1 -E '\S+') || log DEBUG "Failed to get node for job ${jobid} from squeue"

	if [ -r "${HYAKVNC_DIR}/jobs/${jobid}/hostname" ] && read -r launch_hostname <"${HYAKVNC_DIR}/jobs/${jobid}/hostname" && [ -n "$launch_hostname" ]; then
		[ node != "${launch_hostname}" ] && log WARN "Node for ${jobid} from hostname file (${launch_hostname}) does not match node from squeue (${node}). Was the job restarted?"
		[ -z "${node}" ] && log DEBUG "Node for ${jobid} from squeue is blank. Setting to ${launch_hostname}" && node="${launch_hostname}"
	else
		log WARN "Failed to get originally launched node for job ${jobid} from ${HYAKVNC_DIR}/jobs/${jobid}/hostname"
	fi

	[ -z "${node}" ] && log ERROR "No node identified for job ${jobid}" && return 1

	# Print connection instruction header:

	# Print connection instructions:

	local ssh_args
	ssh_args=()
	ssh_args+=("-o StrictHostKeyChecking=no")
	ssh_args+=("-L" "${viewer_port}:${socket_path}")
	ssh_args+=("-J" "${USER}@${HYAKVNC_SSH_HOST}")
	ssh_args+=("${USER}@${node}")

	cat <<EOF
Copy and paste these instructions into a command line terminal on your local machine to connect to the VNC session.
You may need to install a VNC client if you don't already have one.
If you are using Windows or are having trouble, try using the manual connection information.
EOF

	echo "LINUX TERMINAL (bash/zsh):"
	echo "ssh -f ${ssh_args[*]} sleep 10 && vncviewer localhost:${viewer_port}"
	echo

	echo "MACOS TERMINAL"
	printf "ssh -f %s sleep 10 && " "${ssh_args[*]}"
	# Print a command to open a VNC viewer for each bundle ID:
	for bundleid in ${HYAKVNC_MACOS_VNC_VIEWER_BUNDLEIDS}; do
		printf "open -b %s --args localhost:%s 2>/dev/null || " "${bundleid}" "${viewer_port}"
	done
	# And finally, print a command to warn the user if no VNC viewer was found:
	printf "No VNC viewer found. Please install one or try entering the connection information manually.\n"
	echo

	echo "WINDOWS"
	echo "(See below)"
	echo

	echo "MANUAL CONNECTION INFORMATION"
	echo "Configure your SSH client to connect to the address ${node} with username ${USER} through the \"jump host\" (possibly labeled a via, proxy, or gateway host) at the address \"${HYAKVNC_SSH_HOST}\"."
	echo "Enable local port forwarding from port ${viewer_port} on your machine ('localhost' or 127.0.0.1) to the socket ${socket_path} on the remote host."
	echo "In your VNC client, connect to 'localhost' or 127.0.0.1 on port ${viewer_port}"
	echo
}

# cleanup_launched_jobs_and_exit()
# Cancel any jobs that were launched and exit
function cleanup_launched_jobs_and_exit {
	local jobdir jobid
	trap - SIGINT SIGTSTP SIGTERM SIGHUP SIGABRT SIGQUIT
	# Cancel any jobs that were launched:
	for jobid in "${LAUNCHED_JOBIDS[@]}"; do
		jobdir="${HYAKVNC_DIR}/jobs/${jobid}"
		log WARN "Cancelling launched job ${jobid}"
		scancel "${jobid}" || log ERROR "Failed to cancel job ${jobid}"
		[ -d "${jobdir}" ] && rm -rf "${jobdir}" && log DEBUG "Removed job directory ${jobdir}"
	done
	exit 1
}

# = Commands
function help_create {
	cat <<EOF
Usage: hyakvnc create [create options...] -c <container> [extra args to pass to apptainer...]

Description:
  Create a VNC session on Hyak.

Options:
  -h, --help	Show this help message and exit
  -c, --container	Path to container image (required)
  -j, --jobid	Don't launch a new job; instead, attach to this SLURM job ID (optional)
  -A, --account	Slurm account to use (default: ${HYAKVNC_SLURM_ACCOUNT})
  -p, --partition	Slurm partition to use (default: ${HYAKVNC_SLURM_PARTITION})
  -C, --cpus	Number of CPUs to request (default: ${HYAKVNC_SLURM_CPUS})
  -m, --mem	Amount of memory to request (default: ${HYAKVNC_SLURM_MEM})
  -t, --timelimit	Slurm timelimit to use (default: ${HYAKVNC_SLURM_TIMELIMIT})
  -g, --gpus	Number of GPUs to request (default: ${HYAKVNC_SLURM_GRES})

Extra arguments:
  Any extra arguments will be passed to apptainer run.
  See 'apptainer run --help' for more information.

Examples:
  # Create a VNC session using the container ~/containers/mycontainer.sif
  # Use the SLURM account escience, the partition gpu-a40, 4 CPUs, 1GB of memory, 1 GPU, and 1 hour of time
  hyakvnc create -c ~/containers/mycontainer.sif -A escience -p gpu-a40 -C 4 -m 1G -t 1:00:00 -g 1
EOF
}

# create
function cmd_create {
	local apptainer_start_args=()
	local sbatch_args=(--parsable)
	local container_basename container_name start
	while true; do
		case ${1:-} in
		-h | --help)
			help_create
			return 0
			;;
		-d | --debug) # Debug mode
			shift
			export HYAKVNC_LOG_LEVEL="DEBUG"
			;;
		-c | --container)
			shift
			[ -z "${1:-}" ] && log ERROR "-c | --container requires a non-empty option argument" && exit 1
			export HYAKVNC_CONTAINER="${1:-}"
			shift
			;;
		-A | --account)
			[ -z "${1:-}" ] && log ERROR "-A | --account requires a non-empty option argument" && exit 1
			shift
			export HYAKVNC_SLURM_ACCOUNT="${1:-}"
			shift
			;;
		-p | --partition)
			shift
			[ -z "${1:-}" ] && log ERROR "-p | --partition requires a non-empty option argument" && exit 1
			export HYAKVNC_SLURM_PARTITION="${1:-}"
			shift
			;;
		-C | --cpus)
			shift
			[ -z "${1:-}" ] && log ERROR "--cpus requires a non-empty option argument" && exit 1
			export HYAKVNC_SLURM_CPUS="${1:-}"
			shift
			;;
		-m | --mem)
			shift
			[ -z "${1:-}" ] && log ERROR "--mem requires a non-empty option argument" && exit 1
			export HYAKVNC_SLURM_MEM="${1:-}"
			shift
			;;
		-t | --timelimit)
			shift
			[ -z "${1:-}" ] && log ERROR "--mem requires a non-empty option argument" && exit 1
			export HYAKVNC_SLURM_TIMELIMIT="${1:-}"
			shift
			;;
		-g | --gpus)
			shift
			export HYAKVNC_SBATCH_GRES="${1:-}"
			shift
			;;
		-j | --jobid) # Job ID to attach to (optional)
			shift
			export HYAKVNC_ATTACH_TO_SLURM_JOB_ID="${1:-}"
			shift
			log ERROR "Option not implemented yet" && exit 1
			;;
		--) # Args to pass to Apptainer
			shift
			if [ -z "${HYAKVNC_APPTAINER_ARGS:-}" ]; then
				export HYAKVNC_APPTAINER_ARGS="${HYAKVNC_APPTAINER_ARGS:-} ${*:-}"
			else
				export HYAKVNC_APPTAINER_ARGS="${*:-}"
			fi
			break
			;;
		-*)
			log ERROR "Unknown option: ${1:-}\n" && exit 1
			;;
		*)
			break
			;;
		esac
	done

	# Check that container is specified
	[ -z "${HYAKVNC_CONTAINER}" ] && log ERROR "Container image must be specified" && exit 1

	# <TODO> add support for containers from URLs like docker:// or oras://
	# For now, just support files:
	[ ! -e "${HYAKVNC_CONTAINER}" ] && log ERROR "Container image at ${HYAKVNC_CONTAINER} does not exist	" && exit 1
	# Check that the container is readable:
	[ ! -r "${HYAKVNC_CONTAINER}" ] && log ERROR "Container image ${HYAKVNC_CONTAINER} is not readable" && exit 1
	container_basename="$(basename "${HYAKVNC_CONTAINER}")"
	[ -z "$container_basename" ] && log ERROR "Failed to get container basename from ${HYAKVNC_CONTAINER}" && exit 1
	container_name="${container_basename%.*}"
	[ -z "$container_name" ] && log ERROR "Failed to get container name from ${container_basename}" && exit 1

	log INFO "Creating HyakVNC job for container ${container_basename}"

	[ -z "${HYAKVNC_SLURM_JOB_NAME}" ] && export HYAKVNC_SLURM_JOB_NAME="${HYAKVNC_SLURM_JOB_PREFIX}${container_name}" && log TRACE "Set HYAKVNC_SLURM_JOB_NAME to ${HYAKVNC_SLURM_JOB_NAME}"

	# Set sbatch arugments or environment variables:
	#   CPUs has to be specified as a sbatch argument because it's not settable by environment variable:
	[ -n "${HYAKVNC_SLURM_CPUS}" ] && sbatch_args+=(--cpus-per-task "${HYAKVNC_SLURM_CPUS}") && log TRACE "Set --cpus-per-task to ${HYAKVNC_SLURM_CPUS}"

	export HYAKVNC_SLURM_ACCOUNT="${HYAKVNC_SLURM_ACCOUNT:-$(get_default_slurm_account)}"
	export HYAKVNC_SLURM_CLUSTER="${HYAKVNC_SLURM_CLUSTER:-$(get_default_slurm_cluster)}"
	export HYAKVNC_SLURM_PARTITION="${HYAKVNC_SLURM_PARTITION:-$(get_default_slurm_partition "${USER}" "${HYAKVNC_SLURM_ACCOUNT}" "${HYAKVNC_SLURM_CLUSTER}")}"

	[ -n "${HYAKVNC_SLURM_ACCOUNT}" ] && export SBATCH_ACCOUNT="${HYAKVNC_SLURM_ACCOUNT}" && log TRACE "Set SBATCH_ACCOUNT to ${SBATCH_ACCOUNT}"
	[ -n "${HYAKVNC_SLURM_PARTITION}" ] && export SBATCH_PARTITION="${HYAKVNC_SLURM_PARTITION}" && log TRACE "Set SBATCH_PARTITION to ${SBATCH_PARTITION}"
	[ -n "${HYAKVNC_SLURM_CLUSTER}" ] && export SBATCH_CLUSTERS="${HYAKVNC_SLURM_CLUSTER}" && log TRACE "Set SBATCH_CLUSTERS to ${SBATCH_CLUSTERS}"
	[ -n "${HYAKVNC_SLURM_TIMELIMIT}" ] && export SBATCH_TIMELIMIT="${HYAKVNC_SLURM_TIMELIMIT}" && log TRACE "Set SBATCH_TIMELIMIT to ${SBATCH_TIMELIMIT}"
	[ -n "${HYAKVNC_SLURM_JOB_NAME}" ] && export SBATCH_JOB_NAME="${HYAKVNC_SLURM_JOB_NAME}" && log TRACE "Set SBATCH_JOB_NAME to ${SBATCH_JOB_NAME}"
	[ -n "${HYAKVNC_SLURM_GRES}" ] && export SBATCH_GRES="${HYAKVNC_SLURM_GRES}" && log TRACE "Set SBATCH_GRES to ${SBATCH_GRES}"
	[ -n "${HYAKVNC_SLURM_MEM}" ] && export SBATCH_MEM="${HYAKVNC_SLURM_MEM}" && log TRACE "Set SBATCH_MEM to ${SBATCH_MEM}"
	[ -n "${HYAKVNC_SLURM_OUTPUT}" ] && export SBATCH_OUTPUT="${HYAKVNC_SLURM_OUTPUT}" && log TRACE "Set SBATCH_OUTPUT to ${SBATCH_OUTPUT}"

	local alljobsdir jobdir
	alljobsdir="${HYAKVNC_DIR}/jobs"
	mkdir -p "${alljobsdir}" || { log ERROR "Failed to create directory ${alljobsdir}" && exit 1; }

	apptainer_start_args+=("run" "--app" "${HYAKVNC_APPTAINER_VNC_APP_NAME}")
	apptainer_start_args+=("--writable-tmpfs")
	case "${HYAKVNC_APPTAINER_CLEANENV}" in
	1 | true | yes | y | Y | TRUE | YES)
		apptainer_start_args+=("--cleanenv")
		;;
	esac

	apptainer_start_args+=("--bind" "\"${alljobsdir}/\${SLURM_JOB_ID}:/vnc\"")
	apptainer_start_args+=("--bind" "\"${alljobsdir}\${SLURM_JOB_ID}/tmp:/tmp\"")
	# Set up extra bind paths:
	[ -n "${HYAKVNC_SET_APPTAINER_BIND_PATHS:-}" ] && apptainer_start_args+=("--bind" "\"${HYAKVNC_SET_APPTAINER_BIND_PATHS}\"")

	apptainer_start_args+=("\"${HYAKVNC_CONTAINER}\"")

	# Final command should look like:
	# sbatch -A escience -c 4 --job-name hyakvnc-x -p gpu-a40 --output sjob2.txt --mem=4G --time=1:00:00 --wrap "mkdir -vp $HOME/.hyakvnc/jobs/\$SLURM_JOB_ID/{tmp,vnc} && apptainer run --app vncserver -B \"$HOME/.hyakvnc/jobs/\$SLURM_JOB_ID/tmp:/tmp\" -B \"$HOME/.hyakvnc/jobs/\$SLURM_JOB_ID/vnc:/vnc\" --cleanenv --writable-tmpfs /mmfs1/home/altan/gdata/containers/ubuntu22.04_turbovnc.sif
	# <TODO> If a job ID was specified, don't launch a new job
	# <TODO> If a job ID was specified, check that the job exists and is running

	sbatch_args+=(--wrap)
	sbatch_args+=("mkdir -vp \"${alljobsdir}/\${SLURM_JOB_ID}/{tmp,vnc}\" && \"${HYAKVNC_APPTAINER_BIN}\" run ${apptainer_start_args[*]}")

	# Trap signals to clean up the job if the user exits the script:
	if [ -z "${XNOTRAP:-}" ]; then
		trap cleanup_launched_jobs_and_exit SIGINT SIGTSTP SIGTERM SIGHUP SIGABRT SIGQUIT
	fi

	log DEBUG "Launching job with command: sbatch ${sbatch_args[*]}"
	sbatch_result=$(sbatch "${sbatch_args[@]}") || { log ERROR "Failed to launch job" && exit 1; }
	# Quit if no job ID was returned:
	[ -z "${sbatch_result:-}" ] && log ERROR "Failed to launch job" && exit 1

	# Parse job ID and cluster from sbatch result (semicolon separated):
	launched_jobid="${sbatch_result%%;*}"
	[ -z "${launched_jobid:-}" ] && log ERROR "Failed to get job ID for job" && exit 1

	# Add the job ID to the list of launched jobs:
	LAUNCHED_JOBIDS+=("${launched_jobid}")

	jobdir="${alljobsdir}/${launched_jobid}"

	# Wait for sbatch job to start running by monitoring the output of squeue:
	start=$EPOCHSECONDS
	while true; do
		if ((EPOCHSECONDS - start > HYAKVNC_SBATCH_POST_TIMEOUT)); then
			log ERROR "Timed out waiting for job to start" && exit 1
		fi
		sleep
		squeue_result=$(squeue --job "${launched_jobid}" --format "%T" --noheader)
		case "${squeue_result:-}" in
		SIGNALING | PENDING | CONFIGURING | STAGE_OUT | SUSPENDED | REQUEUE_HOLD | REQUEUE_FED | RESV_DEL_HOLD | STOPPED | RESIZING | REQUEUED)
			log TRACE "Job ${launched_jobid} is in a state that could potentially run: ${squeue_result}"
			sleep 1
			continue
			;;
		RUNNING)
			log DEBUG "Job ${launched_jobid} is ${squeue_result}"
			sleep 1
			[ ! -d "${jobdir}" ] && log TRACE "Job directory does not exist yet" && continue
			sleep 1
			[ ! -e "${jobdir}/vnc/socket.uds" ] && log TRACE "Job socket does not exist yet" && continue
			sleep 1
			[ ! -S "${jobdir}/vnc/socket.uds" ] && log TRACE "Job socket is not a socket" && continue
			sleep 1
			break
			;;
		*) log ERROR "Job ${launched_jobid} is in unexpected state ${squeue_result}" && exit 1 ;;
		esac
	done

	# Get details about the Xvnc process:
	cmd_show "${launched_jobid}" || { log ERROR "Failed to get Xvnc process info for job ${launched_jobid}" && exit 1; }
	# Stop trapping the signals:
	if [ -z "${XNOTRAP:-}" ]; then
		trap - SIGINT SIGTSTP SIGTERM SIGHUP SIGABRT SIGQUIT
	fi
	return 0
}

function help_status {
	cat <<EOF
Usage: hyakvnc status [status options...]

Description:
  Check status of VNC session(s) on Hyak.

Options:
  -h, --help	Show this help message and exit
  -d, --debug	Print debug info
  -j, --jobid	Only check status of provided SLURM job ID (optional)

Examples:
  # Check the status of job no. 12345:
  hyakvnc status -j 12345
  # Check the status of all VNC jobs:
  hyakvnc status
EOF
}

function cmd_status {
	local account running_jobid running_jobids
	while true; do
		case ${1:-} in
		-h | --help)
			help_status
			return 0
			;;
		-d | --debug) # Debug mode
			shift
			export HYAKVNC_LOG_LEVEL=DEBUG
			;;
		-j | --jobid) # Job ID to attach to (optional)
			shift
			running_jobid="${1:-}"
			shift
			;;
		-*)
			log ERROR "Unknown option: ${1:-}\n" && exit 1
			;;
		*)
			break
			;;
		esac
	done
	# Loop over directories in ${HYAKVNC_DIR}/jobs
	squeue_args=(--me --states=RUNNING --noheader --format '%j %i')
	[ -n "${running_jobid:-}" ] && squeue_args+=(--job "${running_jobid}")
	running_jobids=$(squeue "${squeue_args[@]}" | grep -E "^${HYAKVNC_SLURM_JOB_PREFIX}" | grep -oE '[0-9]+$') || { log WARN "Found no running job IDs with names that match the set job name prefix ${HYAKVNC_SLURM_JOB_PREFIX}" && return 1; }
	[ -z "${running_jobids:}" ] && log WARN "Found no running job IDs with names that match the prefix ${HYAKVNC_SLURM_JOB_PREFIX}" && return 1
	
	for running_jobid in ${running_jobids:-}; do
		local running_job_node jobdir
		running_job_node=$(squeue --job "${running_jobid}" --format "%N" --noheader) || { log WARN "Failed to get node for job ${running_jobid}" && continue; }
		[ -z "${running_job_node}" ] && log WARN "Failed to get node for job ${running_jobid}" && continue
		jobdir="${HYAKVNC_DIR}/jobs/${running_jobid}"
		[ ! -d "${jobdir}" ] && log WARN "Job directory ${jobdir} does not exist" && continue
		[ ! -e "${jobdir}/vnc/socket.uds" ] && log WARN "Job socket not found at ${jobdir}/vnc/socket.uds" && continue
		[ ! -S "${jobdir}/vnc/socket.uds" ] && log WARN "Job socket at ${jobdir}/vnc/socket.uds is not a socket" && continue
		echo "Job ${running_jobid} is running on ${running_job_node} on node ${running_job_node}"
	done
}

function help_stop {
	cat <<EOF
Usage: hyakvnc stop [-a] [<jobids>...]
	
Description:
  Stop a provided HyakVNC sesssion and clean up its job directory

Options:
  -h, --help	Show this help message and exit
  -c, --cancel	Also cancel the SLURM job
  -a, --all	Stop all jobs

Examples:
  # Stop a VNC session running on job 123456:
  hyakvnc stop 123456
  # Stop a VNC session running on job 123456 and also cancel the job:
  hyakvnc stop -c 123456
  # Stop all VNC sessions:
  hyakvnc stop -a
  # Stop all VNC sessions and also cancel the jobs:
  hyakvnc stop -a -c
EOF
}

function cmd_stop {
	local jobids all jobid should_cancel stop_hyakvnc_session_args
	stop_hyakvnc_session_args=()
	# Parse arguments:
	while true; do
		case ${1:-} in
		-h | --help)
			help_stop
			return 0
			;;
		-d | --debug) # Debug mode
			shift
			export HYAKVNC_LOG_LEVEL=DEBUG
			;;
		-a | --all)
			shift
			all=1
			;;
		-c | --cancel)
			shift
			stop_hyakvnc_session_args+=(--cancel)
			;;
		-*)
			log ERROR "Unknown option for stop: ${1:-}\n"
			return 1
			;;
		*)
			jobids="${*:-}"
			break
			;;
		esac
	done

	if [ -n "$all" ]; then
		jobids=$(squeue --me --format '%j %i' --noheader | grep -E "^${HYAKVNC_SLURM_JOB_PREFIX}" | grep -oE '[0-9]+$') || log WARN "Found no running job IDs with names that match the prefix ${HYAKVNC_SLURM_JOB_PREFIX}"
	fi

	[ -z "${jobids}" ] && log ERROR "Must specify running job IDs" && exit 1

	# Cancel any jobs that were launched:
	for jobid in ${jobids}; do
		stop_hyakvnc_session "${stop_hyakvnc_session_args[@]}" "${jobid}" && log INFO "Stopped job ${jobid}"
	done
	return 0
}

function help_show {
	cat <<EOF
Usage: hyakvnc show <jobid>
 
Description:
  Show connection information for a HyakVNC sesssion

Options:
  -h, --help	Show this help message and exit

Examples:
  # Show connection information for session running on job 123456:
  hyakvnc show 123456
EOF
}
function cmd_show {
	local jobid
	# Parse arguments:
	while true; do
		case "${1:-}" in
		-h | --help)
			help_show
			return 0
			;;
		-d | --debug) # Debug mode
			shift
			export HYAKVNC_LOG_LEVEL=DEBUG
			;;
		-*)
			log ERROR "Unknown option for show: ${1:-}\n"
			return 1
			;;
		*)
			jobid="${*-}"
			shift
			break
			;;
		esac
	done
	[ -z "${jobid}" ] && log ERROR "Must specify running job IDs" && exit 1

	running_jobids=$(squeue --job "${jobid}" --noheader --format '%j %i' | grep -E "^${HYAKVNC_SLURM_JOB_PREFIX}" | grep -oE '[0-9]+$') || { log WARN "Found no running job for job ${jobid} with names that match the prefix ${HYAKVNC_SLURM_JOB_PREFIX}" && return 1; }

	print_connection_info "$jobid" || { log ERROR "Failed to print connection info for job ${jobid}" && return 1; }
	return 0
}

function cmd_help {
	while true; do
		case "${1:-}" in
		create)
			shift
			help_create "$@"

			return 0
			;;
		status)
			shift
			help_status "$@"
			return 0
			;;
		stop)
			shift
			help_stop "$@"
			return 0
			;;
		show)
			shift
			help_show "$@"
			return 0
			;;
		*)
			break
			;;
		esac
	done

	cat <<EOF
HyakVNC -- A tool for launching VNC sessions on Hyak $0
Usage: hyakvnc [options] [create|status|stop|show|help] [options] [args]

Description:
	Stop a provided HyakVNC sesssion and clean up its job directory

Options:
	-h, --help	Show this help message and exit
	-d, --debug	Also cancel the SLURM job
	-V, --version	Print version information and exit

Available commands:
	create	Create a new VNC session
	status	Check status of VNC session(s)
	stop	Stop a VNC session
	show	Show connection information for a VNC session
	help	Show help for a command
EOF
}

# = Main script:
# Initalize directories:
mkdir -p "${HYAKVNC_DIR}/jobs" || (log ERROR "Failed to create HYAKVNC jobs directory ${HYAKVNC_DIR}/jobs" && exit 1)
mkdir -p "${HYAKVNC_DIR}/pids" || (log ERROR "Failed to create HYAKVNC PIDs directory ${HYAKVNC_DIR}/pids" && exit 1)

# Parse first argument as action:

# If the first argument is a function in this file, set it to the action:

while true; do
	case "${1:-}" in
	-h | --help | help)
		shift
		cmd_help "$@"
		exit 0
		;;
	-d | --debug) # Debug mode
		shift
		export HYAKVNC_LOG_LEVEL=DEBUG
		;;
	-V | --version)
		shift
		echo "HyakVNC version ${HYAKVNC_VERSION}"
		exit 0
		;;
	create)
		shift
		cmd_create "$@"
		exit 0
		;;
	status)
		shift
		cmd_status "$@"
		exit 0
		;;
	stop)
		shift
		cmd_stop "$@"
		exit 0
		;;
	show)
		shift
		cmd_show "$@"
		exit 0
		;;
	*)
		log ERROR "Unknown command: ${1:-}"
		echo
		cmd_help
		exit 1
		;;
	esac
done
