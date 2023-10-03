#! /usr/bin/env bash

# hyakvnc - A script to launch VNC sessions on Hyak

# = Preferences and settings:
# == App preferences:
HYAKVNC_LOG_PATH="${HYAKVNC_LOG_PATH:-$HOME/.hyakvnc.log}"
HYAKVNC_LOG_LEVEL="${HYAKVNC_LOG_LEVEL:-1}"
HYAKVNC_DIR="${HYAKVNC_DIR:-$HOME/.hyakvnc}"
HYAKVNC_CONFIG_DIR="${HYAKVNC_CONFIG_DIR:-$HOME/.config/hyakvnc}"
HYAKVNC_JOB_PREFIX="${HYAKVNC_JOB_PREFIX:-hyakvnc}"
HYAKVNC_SSH_HOST="${HYAKVNC_SSH_HOST:-klone.hyak.uw.edu}"
HYAKVNC_VNC_PASSWORD="${HYAKVNC_VNC_PASSWORD:-password}"
HYAKVNC_STANDARD_TIMEOUT="${HYAKVNC_STANDARD_TIMEOUT:-30}" # How long to wait for a command to complete before timing out


# === macOS bundle identifiers for VNC viewer executables:
HYAKVNC_MACOS_VNC_VIEWER_BUNDLEIDS="${HYAKVNC_MACOS_VNC_VIEWER_BUNDLEIDS:-com.turbovnc.vncviewer.VncViewer com.realvnc.vncviewer com.tigervnc.vncviewer}"

# == Apptainer preferences:
HYAKVNC_CONTAINER="${HYAKVNC_CONTAINER:-}" # Path to container image
HYAKVNC_APPTAINER_BIN="${HYAKVNC_APPTAINER_BIN:-apptainer}" # Name of apptainer binary
HYAKVNC_APPTAINER_CONFIG_DIR="${HYAKVNC_APPTAINER_CONFIG_DIR:-$HOME/.apptainer}" # Path to apptainer config directory
HYAKVNC_APPTAINER_INSTANCE_PREFIX="${HYAKVNC_APPTAINER_INSTANCE_PREFIX:-hyakvnc}" # Prefix for apptainer instance names
HYAKVNC_APPTAINER_WRITABLE_TMPFS="${HYAKVNC_APPTAINER_WRITABLE_TMPFS:-${APPTAINER_WRITABLE_TMPFS:-1}}" # Whether to use a writable tmpfs for the container
HYAKVNC_APPTAINER_CLEANENV="${HYAKVNC_APPTAINER_CLEANENV:-${APPAINER_CLEANENV:-1}}" # Whether to use a clean environment for the container
HYAKVNC_SET_APPTAINER_BIND_PATHS="${HYAKVNC_SET_APPTAINER_BIND_PATHS:-}" # Bind paths to set for the container
HYAKVNC_SET_APPTAINER_ENV_VARS="${HYAKVNC_SET_APPTAINER_ENV_VARS:-}" # Environment variables to set for the container
HYAKVNC_APPTAINER_VNC_APP_NAME="${HYAKVNC_APPTAINER_VNC_APP_NAME:-vncserver}" # Name of the VNC app in the container (the %appstart section)

# == Slurm preferences:
HYAKVNC_SBATCH_POST_TIMEOUT="${HYAKVNC_SBATCH_POST_TIMEOUT:-120}" # How long after submitting via sbatch to wait for the job to start before timing out
HYAKVNC_SBATCH_OUTPUT_PATH="${HYAKVNC_SBATCH_OUTPUT_PATH:-/dev/null}" # Where to send sbatch output
HYAKVNC_SBATCH_JOB_NAME="${HYAKVNC_SBATCH_JOB_NAME:-}" # Name of the sbatch job
HYAKVNC_SLURM_ACCOUNT="${HYAKVNC_SLURM_ACCOUNT:-${SBATCH_ACCOUNT}}}" # Slurm account to use
HYAKVNC_SLURM_PARTITION="${HYAKVNC_SLURM_PARTITION:-}" # Slurm partition to use
HYAKVNC_SLURM_CLUSTER="${HYAKVNC_SLURM_CLUSTER:-${SBATCH_CLUSTERS}}" # Slurm cluster to use
HYAKVNC_SLURM_GPUS="${HYAKVNC_SLURM_GPUS:-${SBATCH_GPUS}}" # Number of GPUs to request
HYAKVNC_SLURM_MEM="${HYAKVNC_SLURM_MEM:-${SBATCH_MEM:-2G}}" # Amount of memory to request
HYAKVNC_SLURM_CPUS="${HYAKVNC_SLURM_CPUS:-${SLURM_CPUS_PER_TASK:-2}}" # Number of CPUs to request
HYAKVNC_SLURM_TIMELIMIT="${HYAKVNC_SLURM_TIMELIMIT:-${SBATCH_TIMELIMIT}}" # Slurm timelimit to use


# = Utility functions:

# == log - Log a message, given a level and a message
function log {
	LEVEL="${1:-}"
	MESSAGE="${2:-}"
	[ -z "${MESSAGE}" ] && return 0

	shift
	shift

	# if level is symbolic, get a numeric value
	case "$LEVEL" in
	OFF) LEVNUM=0 ;;
	TRACE) LEVNUM=1 ;;
	DEBUG) LEVNUM=2 ;;
	INFO) LEVNUM=3 ;;
	WARN) LEVNUM=4 ;;
	ERROR) LEVNUM=5 ;;
	CRITICAL) LEVNUM=6 ;;
	[0-6]) LEVNUM="$LEVEL" ;;
	*) LEVNUM=3 ;; # default to INFO
	esac

	case "$LEVEL" in
	1 | t | trace | T | TRACE)
		if [ "$LEVNUM" -ge "${HYAKVNC_LOG_LEVEL}" ]; then
			tput -Txterm setaf 2 2>/dev/null
			printf "TRACE: %s\n" "${MESSAGE}" 1>&2
			tput -Txterm sgr0 2>/dev/null

		fi
		;;
	2 | d | debug | D | DEBUG)
		if [ "$LEVNUM" -ge "${HYAKVNC_LOG_LEVEL}" ]; then
			tput -Txterm setaf 6 2>/dev/null
			printf "DEBUG: %s\n" "${MESSAGE}" 1>&2
			tput -Txterm sgr0 2>/dev/null

		fi
		;;

	3 | i | info | I | INFO)
		if [ "$LEVNUM" -ge "${HYAKVNC_LOG_LEVEL}" ]; then
			tput -Txterm setaf 4 2>/dev/null
			printf "INFO: %s\n" "${MESSAGE}" 1>&2
			tput -Txterm sgr0 2>/dev/null

		fi
		;;
	4 | w | warn | warning | W | WARN | WARNING)
		if [ "$LEVNUM" -ge "${HYAKVNC_LOG_LEVEL}" ]; then
			tput -Txterm setaf 3 2>/dev/null
			printf "WARNING: %s\n" "${MESSAGE}" 1>&2
			tput -Txterm sgr0 2>/dev/null
		fi

		;;

	5 | e | error | E | ERROR)
		if [ "$LEVNUM" -ge "${HYAKVNC_LOG_LEVEL}" ]; then
			tput -Txterm setaf 1 2>/dev/null
			printf "ERROR: %s\n" "${MESSAGE}" 1>&2
			tput -Txterm sgr0 2>/dev/null
		fi
		;;
	6 | c | critical | C | CRITICAL)
		if [ "$LEVNUM" -ge "${HYAKVNC_LOG_LEVEL}" ]; then
			tput -Txterm setaf 1 2>/dev/null
			printf "CRITICAL: %s\n" "${MESSAGE}" 1>&2
			tput -Txterm sgr0 2>/dev/null
		fi
		;;
	esac

	return 0
}




# Get Xvnc process info for a job, given job ID, cluster, and either PID or PID file:
function xvnc_ps_for_job {
	local jobid cluster ppid ppidfile
	# Parse arguments:
	while true; do
		case ${1:-} in
		-j | --jobid)
			shift
			jobid="${1:-}"
			shift
			;;
		-c | --cluster)
			shift
			cluster="${1:-}"
			shift
			;;
		-P | --ppid)
			shift
			ppid="${1:-}"
			shift
			;;
		-f | --ppid-file)
			shift
			ppidfile="${1:-}"
			shift
			;;
		-*)
			log ERROR "Unknown option for get_vnc_port_from_job: ${1:-}\n"
			return 1
			;;
		*)
			break
			;;
		esac
		[ -z "${jobid:-}" ] && log ERROR "Job ID must be specified" && return 1
		[ -z "${cluster:-}" ] && log ERROR "Cluster must be specified" && return 1
		if [ -z "${ppid:-}" ]; then 
			[ -z "${ppidfile:-}" ] && log ERROR "Parent PID or PID file must be specified" && return 1
			[ -e "${ppidfile:-}" ] && log ERROR "Parent PID file not found at expected location ${ppidfile}" && return 1
			read -r ppid <"${ppidfile}" || log ERROR "Failed to read parent PID from ${ppidfile}" && return 1
			[ -z "${ppid:-}" ] && log ERROR "Parent PID file at ${ppidfile} is empty" && return 1
		fi
	done

	# Get the VNC port from the job:
	result=$(srun --jobid $qs --quiet --error /dev/null sh -c "pgrep --parent ${qs} --exact Xvnc --list-full || echo")
	[ -z "${result}" ] && log WARNING "Failed to get VNC port from job ${jobid}" && return 1
	echo "${result}"
}

# Check if a port is open on a job, given job ID, cluster, port, and optionally a PID:
function check_slurmjob_port_open {
	local jobid cluster port pid
	# Parse arguments:
	while true; do
		case ${1:-} in
		-j | --jobid)
			shift
			jobid="${1:-}"
			shift
			;;
		-c | --cluster)
			shift
			cluster="${1:-}"
			shift
			;;
		-p | --port)
			shift
			port="${1:-}"
			shift
			;;
		--pid)
			shift
			pid="${1:-}"
			shift
			;;
		-*)
			log ERROR "Unknown option for check_slurmjob_port_open: ${1:-}\n"
			return 1
			;;
		*)
			break
			;;
		esac
		[ -z "${jobid:-}" ] && log ERROR "Job ID must be specified" && return 1
		[ -z "${cluster:-}" ] && log ERROR "Cluster must be specified" && return 1
		[ -z "${port:-}" ] &&  log ERROR "Port must be specified" && return 1
	done

	# Use fuser to check if the port is open on the job:
	result=$(srun --jobid "${jobid}" --clusters "${cluster}" --quiet --error /dev/null sh -c "fuser -s -n tcp ${port} || echo")
	[ -z "${result}" ] && return 1
	
	# If a PID was specified, check that the PID is in the list of PIDs using the port:
	if [ -n "${pid}" ]; then 
		echo "${result}" | grep -oE "\b${pid}\b" && return 0 || return 1
	fi
	return 0
}

# Print connection instructions for a job, given job ID, port, \
# and (optional) port to open on the client:
function print_connection_info {
	local node port viewer_port
	# Parse arguments:
	while true; do
		case ${1:-} in
		-n | --node)
			shift
			node="${1:-}"
			shift
			;;
		-p | --port)
			shift
			port="${1:-}"
			shift
			;;
		--viewer-port)
		shift
		viewer_port="${1:-}"
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
		[ -z "${node:-}" ] && log ERROR "Node must be specified" && return 1
		[ -z "${port:-}" ] && log ERROR "Port must be specified" && return 1
		viewer_port="${viewer_port:-${HYAKVNC_VNC_VIEWER_PORT:-${port}}}"

		echo "Copy and paste these instructions into a command line terminal on your local machine to connect to the VNC session."
		echo "You may need to install a VNC client if you don't already have one."
		echo "If you are using Windows or are having trouble, try using the manual connection information."
		echo
		local base_connect_string="ssh -o StrictHostKeyChecking=no -J ${USER}@${HYAKVNC_SSH_HOST} ${node} -L ${viewer_port}:localhost:${port} sleep 10; vncviewer localhost:${viewer_port}"
		echo "Linux terminal (bash/zsh):"
		echo "${base_connect_string}"
		echo 

		echo "macOS terminal:"
		printf "${base_connect_string} "
		for bundleid in "${HYAKVNC_MACOS_VNC_VIEWER_BUNDLEIDS}"; do
			printf "open -b "${bundleid}" --args localhost:${viewer_port} 2>/dev/null || "
		done
		printf " || echo 'No VNC viewer found. Please install one or try entering the connection information manually.'"
		echo
		
		echo "Windows:"
		echo "(See below)"
		echo
		
		echo "Manual connection information:"
		echo "Configure your SSH client to connect to the address ${node} with username ${USER} through the \"jump host\" '${HYAKVNC_SSH_PORT}'."
		echo "Enable local port forwarding from port ${viewer_port} on your machine ('localhost' or 127.0.0.1) to port ${port} on the remote host."
		echo "In your VNC client, connect to 'localhost' or 127.0.0.1 on port ${viewer_port}"
		echo
}

function cmd_create {
	log INFO "Creating VNC job"
	while true; do
		case ${1:-} in
		-h | --help | help)
			help_create
			return 0
			;;
		-c | --container)
			shift
			export HYAKVNC_CONTAINER="${1:-}"
			shift
			;;
		-A | --account)
			shift
			export HYAKVNC_SLURM_ACCOUNT="${1:-}"
			shift
			;;
		-p | --partition)
			shift
			export HYAKVNC_SLURM_PARTITION="${1:-}"
			shift
			;;
		-C | --cpus)
			shift
			export HYAKVNC_SLURM_CPUS="${1:-}"
			shift
			;;
		-m | --mem)
			shift
			export HYAKVNC_SLURM_MEM="${1:-}"
			shift
			;;
		-t | --timelimit)
			shift
			export HYAKVNC_SLURM_TIMELIMIT="${1:-}"
			shift
			;;
		-g | --gpus)
			shift
			export HYAKVNC_SLURM_GPUS="${1:-}"
			shift
			;;
		-*)
			log ERROR "Unknown option: ${1:-}\n"
			exit 1
			;;
		*)
			break
			;;
		esac
	done

	# Check that container is specified
	[ -z "${HYAKVNC_CONTAINER:-}" ] && log ERROR "Container image must be specified" && exit 1
	[ ! -e "${HYAKVNC_CONTAINER:-}" ] && log ERROR "Container image must be a file" && exit 1

	container_basename="${HYAKVNC_CONTAINER##*/}"
	container_name="${container_basename%.*}" 

	[ HYAKVNC_APPTAINER_WRITABLE_TMPFS = "0" ] && appt_writable_tmpfs_arg="" || appt_writable_tmpfs_arg="--writable-tmpfs"
	[ HYAKVNC_APPTAINER_CLEANENV = "0" ] && appt_cleanenv_arg="--no-cleanenv" || appt_cleanenv_arg="--cleanenv"

	
	sbatch_result=$(sbatch \
		--parsable \
		--job-name "${HYAKVNC_JOB_PREFIX}" \
		--output "${HYAKVNC_SBATCH_OUTPUT_PATH}" \
		--time "${HYAKVNC_SLURM_TIMELIMIT}" \
		--account "${HYAKVNC_SLURM_ACCOUNT}" \
		--clusters "${HYAKVNC_SLURM_CLUSTER}" \
		---partition "${HYAKVNC_SLURM_PARTITION}" \
		--cpus-per-task "${HYAKVNC_SLURM_CPUS}" \
		--mem "${HYAKVNC_SLURM_MEM}" \
		--gres "${HYAKVNC_SLURM_GPUS}" \
		---wrap \
		"\"${HYAKVNC_APPTAINER_BIN}\" instance start --app \"${HYAKVNC_APPTAINER_APP_NAME}\" ${appt_writable_tmpfs_arg} ${appt_cleanenv_arg} --pid-file \"${HYAKVNC_DIR}/pids/\$SLURM_JOBID.pid\" \"${HYAKVNC_CONTAINER}\" \"${HYAKVNC_APPTAINER_INSTANCE_PREFIX}\"-\${SLURM_JOB_ID}-${container_name}\""
		) || log ERROR "Failed to launch job" && exit 1

	# Trap signals to clean up the job if the user exits the script:
	trap "cleanup_jobs_and_exit ${}"  SIGINT SIGTSTP SIGTERM SIGHUP SIGABRT SIGQUIT
	

	
	# Quit if no job ID was returned:
	[ -z "${sbatch_result:-}" ] && log ERROR "Failed to launch job" && exit 1

	# Parse job ID and cluster from sbatch result (semicolon separated):
	launched_jobid="${sbatch_result%%;*}"
	launched_cluster="${sbatch_result##*;}"
	[ -z "${launched_jobid:-}" ] && log ERROR "Failed to launch job" && exit 1


	# Wait for sbatch job to start running by monitoring the output of squeue:
	start=$EPOCHSECONDS
	while true; do
		if (( EPOCHSECONDS-start > HYAKVNC_SBATCH_POST_TIMEOUT )); then
			log ERROR "Timed out waiting for job to start" && exit 1
		fi

		squeue_result=$(squeue --job "${launched_jobid}" --clusters "${launched_cluster}" --format "%T" --noheader)
		case "${squeue_result:-}" in
		SIGNALING | PENDING | CONFIGURING | STAGE_OUT | SUSPENDED | REQUEUE_HOLD | REQUEUE_FED | PENDING | RESV_DEL_HOLD | STOPPED | RESIZING | REQUEUED)
			log TRACE "Job ${launched_jobid} is ${squeue_result}"
			sleep 1
			continue
			;;
		RUNNING)
			log DEBUG "Job ${launched_jobid} is ${squeue_result}"
			break
			;;
		*) log ERROR "Job ${launched_jobid} is in unexpected state ${squeue_result}" && exit 1 ;;
		esac
	done

	# Identify the node the job is running on:
	[ -z "${job_nodelist:=$(squeue --job "${launched_jobid}" --clusters "${launched_cluster}" --format "%N" --noheader)}" ] && log ERROR "Failed to get job nodes" && exit 1
	# Expand the job nodelist:
	[ -z "${job_nodes:=$(scontrol show hostnames "${job_nodelist}" 2>/dev/null)}" ] && log ERROR "Failed to get job nodes for nodelist ${job_nodelist}" && exit 1
	# Get the first node in the list:
	[ -z "${job_node:=${job_nodes%% *}}" ] && log ERROR "Failed to parse job node from nodelist ${job_node}" && exit 1

	# Find the PID file for the apptainer instance:
	launched_ppid_file="${HYAKVNC_DIR}/pids/${launched_jobid}.pid"

	# Wait for the PID file to be created:
	start=$EPOCHSECONDS
	until [ -r "${launched_ppid_file}" ]; do
		(( EPOCHSECONDS-start > HYAKVNC_STANDARD_TIMEOUT )) && log ERROR "Timed out waiting for Xvnc pidfile to be created at ${launched_ppid_file}" && exit 1
	done

	# Set up the job directory:
	jobdir="${HYAKVNC_DIR}/jobs/${launched_jobid}"
	mkdir -p "${jobdir}" || log ERROR "Failed to create job directory ${jobdir}" && exit 1

	# Get details about the Xvnc process:
	xvnc_ps=$(xvnc_ps_for_job --jobid "${launched_jobid}" --cluster "${launched_cluster}" --ppid-file "${launched_ppid_file}") || log ERROR "Failed to get Xvnc process info for job" && exit 1
	[ -z "${xvnc_ps}" ] && log ERROR "Failed to get Xvnc process from job" && exit 1

	# Get the port and hostname:display part from the Xvnc process info.
	# The process info looks like this: '4280 /opt/TurboVNC/bin/Xvnc :1 -desktop TurboVNC: g3050:1 () -auth ...'
	xvnc_port=$(echo "${xvnc_ps}" | grep -oE 'rfbport[[:space:]]+[0-9]+' | grep -oE '[0-9]+') || log ERROR "Failed to get VNC port from job" && exit 1
	xvnc_name=$(echo "${xvnc_ps}" | grep -oE 'TurboVNC: .*:[0-9]+ \(\)' | cut -d' ' -f2) || log ERROR "Failed to get Xvnc PID file from job" && exit 1
	
	# Look for the PID file for the Xvnc process in the ~/.vnc directory:
	[ -e "${xvnc_pidfile:=${HOME}/.vnc/${xvnc_name}.pid}" ] || log ERROR "Xvnc PID file doesn't exist at ${xvnc_pidfile}" && exit 1
	xvnc_pid=$(grep -m1 -oE '^[0-9]+' "${vnc_pidfile}") || log ERROR "Failed to get VNC PID from job" && exit 1
	xvnc_host="${xvnc_name%%:*}"

	# The Xvnc process should be leaving a PID file named in the format "job_node:DISPLAY.pid". If it's not, this could be a problem:
	[ xvnc_host != "${job_node}" ] && log WARNING "Xvnc on ${xvnc_name} doesn't appear to be running on the same node (${launched_job_node}) as the job" 
	
	# Wait for port to be open on the job node for the Xvnc process:
	start=$EPOCHSECONDS
	while true; do
			if (( EPOCHSECONDS-start > HYAKVNC_STANDARD_TIMEOUT )); then
			log ERROR "Timed out waiting for port "${xvnc_port}" to be open"
			break
		fi
		
		check_slurmjob_port_open -j "${launched_jobid}" -c "${launched_cluster}" -p "${xvnc_port}" --pid "${xvnc_pid}" && break
		sleep 1
	fi

	# Write metadata:
	echo "${xvnc_ps}" > "${jobdir}/xvnc_ps.txt"
	echo "${xvnc_name}" > "${jobdir}/xvnc_name.txt"
	echo "${xvnc_port}" > "${jobdir}/xvnc_port.txt"
	echo "${xvnc_pidfile}" > "${jobdir}/xvnc_pidfile.txt"
	echo "${xvnc_pid}" > "${jobdir}/xvnc_pid.txt"
	echo "${launched_ppid_file}" > "${jobdir}/instance_ppid_file.txt"
	echo "${launched_jobid}" > "${jobdir}/jobid.txt"
	echo "${launched_cluster}" > "${jobdir}/cluster.txt"
	
	# Print connection strings:
	print_connection_info --node "${xvnc_host}" --port "${xvnc_port}" --viewer-port "${HYAKVNC_VNC_VIEWER_PORT}" || log ERROR "Failed to print connection info" && exit 1
	
	# Stop trapping the signals:
	trap - SIGINT SIGTSTP SIGTERM SIGHUP SIGABRT SIGQUIT
	return 0
}

function help_status {
	echo "Usage: hyakvnc status [options] [command]"
}

function cmd_status {
	log INFO "Checking status of VNC jobs"
	# Loop over directories in ${HYAKVNC_DIR}/jobs
	for d in "${HYAKVNC_DIR}"/jobs/*; do
		[ -e "$d" ] || continue
		[ -d "$d" ] || continue
		jobid=$(cat "${d}/jobid.txt") || log WARNING "Failed to read job ID from ${d}/jobid.txt" && continue
		cluster=$(cat "${d}/cluster.txt") || log WARNING "Failed to read cluster from ${d}/cluster.txt" && continue
		xvnc_port=$(cat "${d}/xvnc_port.txt") || log WARNING "Failed to read VNC port from ${d}/xvnc_port.txt" && continue
		xvnc_pid=$(cat "${d}/xvnc_pid.txt") || log WARNING "Failed to read VNC port from ${d}/xvnc_port.txt" && continue

		# Check if the job is still running:
		if check_slurmjob_port_open -j "${launched_jobid}" -c "${launched_cluster}" -p "${xvnc_port}" --pid "${xvnc_pid}"; then
			log INFO "Job ${jobid} is running on ${cluster} with VNC port ${xvnc_port}"
		else
			log WARNING "Job ${jobid} is not running"
		fi
	done
}


function usage_cmd_stop {
	echo "Usage: hyakvnc stop [options] [command]"
}

function cmd_stop {
	log INFO "Stopping VNC job"
		local jobid cluster ppid ppidfile
	# Parse arguments:
	while true; do
		case ${1:-} in
		-j | --jobid)
			shift
			jobid="${1:-}"
			shift
			;;
		-c | --cluster)
			shift
			cluster="${1:-}"
			shift
			;;
		-*)
			log ERROR "Unknown option for cmd_stop: ${1:-}\n"
			return 1
			;;
		*)
			break
			;;
		esac
		[ -z "${jobid:-}" ] && log ERROR "Job ID must be specified" && return 1
		[ -z "${cluster:-}" ] && log ERROR "Cluster must be specified" && return 1

		${srun 
	done

	# Get the VNC port from the job:
	result=$(srun --jobid $qs --quiet --error /dev/null sh -c "pgrep --parent ${qs} --exact Xvnc --list-full || echo")
	[ -z "${result}" ] && log WARNING "Failed to get VNC port from job ${jobid}" && return 1
	echo "${result}"
}

function cmd_stop_all {
}

function cmd_help {
		while true; do
		case ${1:-} in
		create)
			shift
			help_create "$@"
			break
			;;
		status)
			shift
			help_status "$@"
			break
			;;
		stop)
			shift
			help_stop "$@"
			break
			;;
		stop-all)
			shift
			help_stop_all "$@"
			pid="${1:-}"
			shift
			;;
		show)
			shift
			help_show "$@"
			break
			;;
		*)
			break
			;;
		esac
	done

	echo "Usage: hyakvnc [options] [create|status|stop|stop-all|show] [options] [args]"
}


function help_create {
	echo "Usage: hyakvnc create [options] [command]"
}


# = Main script:
# Initalize directories:
mkdir -p "${HYAKVNC_DIR}/jobs" || log ERROR "Failed to create HYAKVNC jobs directory ${HYAKVNC_DIR}/jobs" && exit 1
mkdir -p "${HYAKVNC_DIR}/pids" || log ERROR "Failed to create HYAKVNC PIDs directory ${HYAKVNC_DIR}/pids" && exit 1

# Parse first argument as action:
action=help
# Look in the functions dictionary for any action starting with cmd_:
for f in $(compgen -A function); do case "$f" in cmd_${f}) action=${f}; shift; break ;; esac; done

# Launch the command:
cmd_${action} "$@"