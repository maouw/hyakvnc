#!/usr/bin/env bash
set -EuT -o pipefail
shopt -qs inherit_errexit
source "${BASH_SOURCE[0]%/*}/_lib.bash"
case "${XDEBUG:-}" in 1 | true | on | yes | y | t | enabled | enable | active | activate | 2) set -x ;; *) ;; esac

# help_create()
function help_create() {
	cat <<EOF
Create a VNC session on Hyak

Usage: hyakvnc create [create options...] -c <container> [extra args to pass to apptainer...]

Description:
	Create a VNC session on Hyak.

Options:
	-h, --help	Show this help message and exit
	-c, --container	Path to container image (required)
	-A, --account	Slurm account to use (default: ${HYAKVNC_SLURM_ACCOUNT:-})
	-p, --partition	Slurm partition to use (default: ${HYAKVNC_SLURM_PARTITION:-})
	-C, --cpus	Number of CPUs to request (default: ${HYAKVNC_SLURM_CPUS:-})
	-m, --mem	Amount of memory to request (default: ${HYAKVNC_SLURM_MEM:-})
	-t, --timelimit	Slurm timelimit to use (default: ${HYAKVNC_SLURM_TIMELIMIT:-})
	-g, --gpus	Number of GPUs to request (default: ${HYAKVNC_SLURM_GPUS:-})

Advanced options:
	--no-ghcr-oras-preload	Don't preload ORAS GitHub Container Registry images

Extra arguments:
	Any extra arguments will be passed to apptainer run.
	See 'apptainer run --help' for more information.

Examples:
	# Create a VNC session using the container ~/containers/mycontainer.sif
	hyakvnc create -c ~/containers/mycontainer.sif
	# Create a VNC session using the URL for a container:
	hyakvnc create -c oras://ghcr.io/maouw/hyakvnc_apptainer/ubuntu22.04_turbovnc:latest
	# Use the SLURM account escience, the partition gpu-a40, 4 CPUs, 1GB of memory, 1 GPU, and 1 hour of time:
	hyakvnc create -c ~/containers/mycontainer.sif -A escience -p gpu-a40 -C 4 -m 1G -t 1:00:00 -g 1

EOF
}

# Exit on critical errors:
trap 'log CRITICAL "Command \`$BASH_COMMAND\` exited with code  $?" ; echo; echo "Context:"; pr -tn $0 | tail -n+$((LINENO - 3)) | head -n7; exit 1' ERR

# cleanup_launched_jobs_and_exit()
# Cancel any jobs that were launched and exit
function cleanup_launched_jobs_and_exit() {
	local jobdir jobid
	log WARN "Interrupted. Cleaning up and exiting!"
	if [[ -n "${jobid:=${1:-}}" ]]; then
		log WARN "Cancelling launched job ${jobid}"
		scancel --hurry --full "${jobid}" || log ERROR "scancel failed to cancel job ${jobid}"
		jobdir="${HYAKVNC_DIR}/jobs/${jobid}"
		[[ -d "${jobdir}" ]] && rm -rf "${jobdir}" && log DEBUG "Removed job directory ${jobdir}"
	fi
	kill -TERM %tail 2>/dev/null                      # Stop following the SLURM log file
	trap - SIGINT SIGTERM SIGHUP SIGABRT SIGQUIT EXIT # Remove traps
	exit 1
}

# cmd_create()
function cmd_create() {
	local extra_apptainer_args=()
	local extra_sbatch_args=()
	local apptainer_start_args=()
	local sbatch_args=(--parsable)

	# <TODO> If a job ID was specified, don't launch a new job
	# <TODO> If a job ID was specified, check that the job exists and is running

	[[ $# -eq 0 ]] && { log ERROR "No arguments provided"; help_create; exit 1; }

	while true; do
		case ${1:-} in
		-h | --help | help) # Show help
			shift
			help_create "$@" && exit 0 || exit 1
			;;

		-c | --container) # Path to container image
			[[ -n "${2:-}" ]] || { log ERROR "$1 requires a non-empty option argument"; exit 1; }
			shift
			export HYAKVNC_APPTAINER_CONTAINER="$1"
			shift
			;;
		-A | --account) # Slurm account to use
			[[ -n "${2:-}" ]] || { log ERROR "$1 requires a non-empty option argument"; exit 1; }
			shift
			export HYAKVNC_SLURM_ACCOUNT="$1"
			shift
			;;
		-p | --partition) # Slurm partition to use
			[[ -n "${2:-}" ]] || { log ERROR "$1 requires a non-empty option argument"; exit 1; }
			shift
			export HYAKVNC_SLURM_PARTITION="$1"
			shift
			;;
		-C | --cpus)
			[[ -n "${2:-}" ]] || { log ERROR "$1 requires a non-empty option argument"; exit 1; }
			shift
			export HYAKVNC_SLURM_CPUS="$1"
			shift
			;;
		-m | --mem)
			[[ -n "${2:-}" ]] || { log ERROR "$1 requires a non-empty option argument"; exit 1; }
			shift
			export HYAKVNC_SLURM_MEM="$1"
			shift
			;;
		-t | --timelimit) # Slurm timelimit to use
			[[ -n "${2:-}" ]] || { log ERROR "$1 requires a non-empty option argument"; exit 1; }

			shift
			export HYAKVNC_SLURM_TIMELIMIT="${1:-}"
			shift
			;;
		-g | --gpus) # Number of GPUs to request
			[[ -n "${2:-}" ]] || { log ERROR "$1 requires a non-empty option argument"; exit 1; }
			shift
			export HYAKVNC_SLURM_GPUS="${1:-}"
			shift
			;;
		--no-ghcr-oras-preload) # Don't preload ORAS GitHub Container Registry images
			export HYAKVNC_APPTAINER_GHCR_ORAS_PRELOAD=0
			shift
			;;

		--sbatch-args) # Extra sbatch arguments
			[[ -n "${2:-}" ]] || { log ERROR "$1 requires a non-empty option argument"; exit 1; }
			shift
			while true; do
				case "${1:-}" in
				--) # End of sbatch args
					shift
					break
					;;
				*)
					extra_sbatch_args+=("${1:-}")
					shift
					;;
				esac
			done
			[[ $# -eq 0 ]] && break # Break if no more arguments
			;;
		--apptainer-args)
			[[ -n "${2:-}" ]] || { log ERROR "$1 requires a non-empty option argument"; exit 1; }
			shift
			while true; do
				case "${1:-}" in
				--) # End of Apptainer args
					shift
					break
					;;
				*)
					extra_apptainer_args+=("${1:-}")
					shift
					;;
				esac
				[[ $# -eq 0 ]] && break # Break if no more arguments
			done
			;;
		-*)
			log ERROR "Unknown option: ${1:-}"
			exit 1
			;;
		*)
			break
			;;
		esac
	done

	# Check that container is specified:
	[[ -z "${HYAKVNC_APPTAINER_CONTAINER:-}" ]] && { log ERROR "Container image must be specified"; exit 1; }

	local container_basename container_name

	container_basename="$(basename "${HYAKVNC_APPTAINER_CONTAINER}")"
	[[ -z "${container_basename:-}" ]] && { log ERROR "Failed to get container basename from ${HYAKVNC_APPTAINER_CONTAINER}"; exit 1; }

	case "${HYAKVNC_APPTAINER_CONTAINER}" in

	library://* | docker://* | shub://* | oras://* | http://* | https://*)
		log DEBUG "Container image ${HYAKVNC_APPTAINER_CONTAINER} is a URL"

		# Add a tag if none is specified:
		[[ "${container_basename}" =~ .*:.* ]] || HYAKVNC_APPTAINER_CONTAINER="${HYAKVNC_APPTAINER_CONTAINER}:latest"
		;;

	*)
		# Check that container is specified
		[[ ! -e "${HYAKVNC_APPTAINER_CONTAINER:-}" ]] && { log ERROR "Container image at ${HYAKVNC_APPTAINER_CONTAINER} does not exist	"; exit 1; }

		# Check that the container is readable:
		[[ ! -r "${HYAKVNC_APPTAINER_CONTAINER:-}" ]] && { log ERROR "Container image ${HYAKVNC_APPTAINER_CONTAINER} is not readable"; exit 1; } ;;
	esac

	container_name="${container_basename//\.@(sif|simg|img|sqsh)/}"
	[[ -z "${container_name:-}" ]] && { log ERROR "Failed to get container name from ${container_basename}"; exit 1; }

	# If /gscratch/scrubbed exists (i.e., running on Klone) and APPTAINER_CACHEDIR is not set to a directory under /gscratch or /tmp, warn the user and ask if they want to set it to a directory under /gscratch/scrubbed :
	if [[ -d "/gscratch/scrubbed" ]] && [[ "${APPTAINER_CACHEDIR:-}" != /gscratch/* ]] && [[ "${APPTAINER_CACHEDIR:-}" != /tmp/* ]]; then
		log WARN "APPTAINER_CACHEDIR is not set to a directory under /gscratch or /tmp. This may cause problems with storage space."

		# Check if running interactively:
		if [[ -t 0 ]]; then
			local choice1 choice2 newcachedir
			newcachedir="/gscratch/scrubbed/${USER}/.cache/apptainer"

			while true; do
				read -rp "Would you like to set APPTAINER_CACHEDIR to \"${newcachedir}\" (Recommended)? (y/n): " choice1
				case "${choice1:-}" in
				y | Y)
					log INFO "Creating ${newcachedir}"
					mkdir -p "${newcachedir}" || {
						log WARN "Failed to create directory ${newcachedir}"
						return 1
					}
					choice1=y # Set choice1 to y so we can use it in the next case statement
					export APPTAINER_CACHEDIR="${newcachedir}"
					break
					;;
				n | N)
					log WARN "Not setting APPTAINER_CACHEDIR."
					break

					;;
				*)
					log ERROR "Invalid choice ${choice1:-}."
					;;
				esac
			done

			if [[ "${choice1:-}" == "y" ]]; then

				# Check if the user wants to add the directory to their shell's startup file:
				while true; do
					read -rp "Would you like to add APPTAINER_CACHEDIR to your shell's startup file to persist this setting? (y/n): " choice2
					case "${choice2:-}" in
					y | Y)
						# Check if using ZSH:
						if [[ -n "${ZSH_VERSION:-}" ]]; then
							if [[ -w "${HOME}/.zshenv}" ]]; then
								echo "export APPTAINER_CACHEDIR=\"${newcachedir}\"" >>"${HOME}/.zshenv" && log INFO "Added APPTAINER_CACHEDIR to ~/.zshenv"
							else
								echo "export APPTAINER_CACHEDIR=\"${newcachedir}\"" >>"${ZDOTDIR:-${HOME}}/.zshrc" && log INFO "Added APPTAINER_CACHEDIR to ${ZDOTDIR:-~}/.zshrc"
							fi
						# Check if using Bash:
						elif [[ -n "${BASH_VERSION:-}" ]]; then
							echo "export APPTAINER_CACHEDIR=\"${newcachedir}\"" >>"${HOME}/.bashrc" && log INFO "Added APPTAINER_CACHEDIR to ~/.bashrc"
						# Write to ~/.profile if we can't determine shell type:
						else
							log INFO "Could not determine shell type. Adding APPTAINER_CACHEDIR to ~/.profile."
							echo "export APPTAINER_CACHEDIR=\"${newcachedir}\"" >>"${HOME}/.profile" && log INFO "Added APPTAINER_CACHEDIR to ~/.profile"
						fi
						break
						;;

					n | N)
						log WARN "Not adding APPTAINER_CACHEDIR to your shell's startup file. You may need to do this again in the future."
						break
						;;
					*)
						log ERROR "Invalid choice ${choice2:-}."
						;;
					esac
				done
			fi
		fi
	fi

	# Preload ORAS images if requested:
	if [[ "${HYAKVNC_APPTAINER_GHCR_ORAS_PRELOAD:-1}" == 1 ]]; then
		local oras_cache_dir oras_image_path
		oras_cache_dir="${APPTAINER_CACHEDIR:-${HOME}/.apptainer/cache}/cache/oras"
		if mkdir -p "${oras_cache_dir}"; then
			log INFO "Preloading ORAS image for \"${HYAKVNC_APPTAINER_CONTAINER}\""
			oras_image_path="$(ghcr_get_oras_sif "${HYAKVNC_APPTAINER_CONTAINER}" "${APPTAINER_CACHEDIR}/cache/oras" || true)"
			[[ -z "${oras_image_path:-}" ]] && log ERROR "hyakvnc failed to preload ORAS image for \"${HYAKVNC_APPTAINER_CONTAINER:-}\" on its own. Apptainer will try to download the image by itself. If you don't want to preload ORAS images, use the --no-ghcr-oras-preload option."
		else
			log ERROR "Failed to create Apptainer ORAS cache directory ${oras_cache_dir}."
		fi
	fi

	export HYAKVNC_SLURM_JOB_NAME="${HYAKVNC_SLURM_JOB_PREFIX}${container_name}"
	export SBATCH_JOB_NAME="${HYAKVNC_SLURM_JOB_NAME}"
	log TRACE "Set SBATCH_JOB_NAME to ${SBATCH_JOB_NAME}"

	# Set sbatch arguments or environment variables:
	#   CPUs has to be specified as a sbatch argument because it's not settable by environment variable:
	[[ -n "${HYAKVNC_SLURM_CPUS:-}" ]] && sbatch_args+=(--cpus-per-task "${HYAKVNC_SLURM_CPUS}") && log TRACE "Set --cpus-per-task to ${HYAKVNC_SLURM_CPUS}"
	[[ -n "${HYAKVNC_SLURM_TIMELIMIT:-}" ]] && export SBATCH_TIMELIMIT="${HYAKVNC_SLURM_TIMELIMIT:-}" && log TRACE "Set SBATCH_TIMELIMIT to ${SBATCH_TIMELIMIT}"
	[[ -n "${HYAKVNC_SLURM_JOB_NAME:-}" ]] && export SBATCH_JOB_NAME="${HYAKVNC_SLURM_JOB_NAME}" && log TRACE "Set SBATCH_JOB_NAME to ${SBATCH_JOB_NAME}"
	[[ -n "${HYAKVNC_SLURM_GPUS:-}" ]] && export SBATCH_GPUS="${HYAKVNC_SLURM_GPUS}" && log TRACE "Set SBATCH_GPUS to ${SBATCH_GPUS}"
	[[ -n "${HYAKVNC_SLURM_MEM:-}" ]] && export SBATCH_MEM="${HYAKVNC_SLURM_MEM}" && log TRACE "Set SBATCH_MEM to ${SBATCH_MEM}"
	[[ -n "${HYAKVNC_SLURM_OUTPUT:-}" ]] && export SBATCH_OUTPUT="${HYAKVNC_SLURM_OUTPUT}" && log TRACE "Set SBATCH_OUTPUT to ${SBATCH_OUTPUT}"
	[[ -n "${HYAKVNC_SLURM_ACCOUNT:-}" ]] && export SBATCH_ACCOUNT="${HYAKVNC_SLURM_ACCOUNT}" && log TRACE "Set SBATCH_ACCOUNT to ${SBATCH_ACCOUNT}"
	[[ -n "${HYAKVNC_SLURM_PARTITION:-}" ]] && export SBATCH_PARTITION="${HYAKVNC_SLURM_PARTITION}" && log TRACE "Set SBATCH_PARTITION to ${SBATCH_PARTITION}"

	# Set up the jobs directory:
	local alljobsdir jobdir
	alljobsdir="${HYAKVNC_DIR}/jobs"
	mkdir -p "${alljobsdir}" || { log ERROR "Failed to create directory ${alljobsdir}"; exit 1; }

	mkdir -p "${HYAKVNC_SLURM_OUTPUT_DIR}" || { log ERROR "Failed to create directory ${HYAKVNC_SLURM_OUTPUT_DIR}"; exit 1; }

	apptainer_start_args+=(run --app "${HYAKVNC_APPTAINER_APP_VNCSERVER}")
	apptainer_start_args+=(--writable-tmpfs)

	case "${HYAKVNC_APPTAINER_CLEANENV:-}" in
	1 | true | yes | y | Y | TRUE | YES)
		apptainer_start_args+=("--cleanenv")
		;;
	*) ;;
	esac

	# Final command should look like:
	# sbatch -A escience -c 4 --job-name hyakvnc-x -p gpu-a40 --output sjob2.txt --mem=4G --time=1:00:00 --wrap "mkdir -vp $HOME/.hyakvnc/jobs/\$SLURM_JOB_ID/{tmp,vnc} && apptainer run --app vncserver -B \"$HOME/.hyakvnc/jobs/\$SLURM_JOB_ID/tmp:/tmp\" -B \"$HOME/.hyakvnc/jobs/\$SLURM_JOB_ID/vnc:/vnc\" --cleanenv --writable-tmpfs /mmfs1/home/altan/gdata/containers/ubuntu22.04_turbovnc.sif

	# Add binds to VNC dirs:
	apptainer_start_args+=("--bind" "\"${alljobsdir}/\${SLURM_JOB_ID}/vnc:/vnc\"")
	apptainer_start_args+=("--bind" "\"\${jobtmp}:/tmp\"") # jobtmp will be set by the sbatch script via mktemp()

	# Set up extra bind paths:
	[[ -n "${HYAKVNC_APPTAINER_ADD_BINDPATHS:-}" ]] && apptainer_start_args+=("--bind" "\"${HYAKVNC_APPTAINER_ADD_BINDPATHS}\"")

	# Add extra apptainer arguments:
	apptainer_start_args+=("${extra_apptainer_args[@]}")

	# Add the container path to the apptainer command:
	apptainer_start_args+=("\"${HYAKVNC_APPTAINER_CONTAINER}\"")

	# Add extra arguments to the sbatch command:
	sbatch_args+=("${extra_sbatch_args[@]}")

	# Append necessary arguments to the sbatch command:
	sbatch_args+=(--wrap)
	sbatch_args+=("mkdir -p \"${alljobsdir}/\${SLURM_JOB_ID}/vnc\" && jobtmp=\$(mktemp -d --suffix _hyakvnc_tmp_\${SLURM_JOB_ID}) && echo \"\$jobtmp\" > \"${alljobsdir}/\${SLURM_JOB_ID}/tmpdirname\" && \"${HYAKVNC_APPTAINER_BIN}\" ${apptainer_start_args[*]}")

	# Trap signals to clean up the job if the user exits the script:
	[[ -z "${XNOTRAP:-}" ]] && trap 'cleanup_launched_jobs_and_exit launched_jobid' SIGINT SIGTERM SIGHUP SIGABRT SIGQUIT ERR EXIT

	log DEBUG "Launching job with command: sbatch ${sbatch_args[*]}"

	sbatch_result=$(sbatch "${sbatch_args[@]}") || { log ERROR "Failed to launch job"; exit 1; }

	# Quit if no job ID was returned:
	[[ -z "${sbatch_result:-}" ]] && { log ERROR "Failed to launch job - no result from sbatch"; exit 1; }

	# Parse job ID and cluster from sbatch result (semicolon separated):
	launched_jobid="${sbatch_result%%;*}"
	[[ -z "${launched_jobid:-}" ]] && { log ERROR "Failed to parse job ID for newly launched job"; exit 1; }

	# Add the job ID to the list of launched jobs:
	Launched_JobIDs+=("${launched_jobid}")

	jobdir="${alljobsdir}/${launched_jobid}"
	log DEBUG "Job directory: ${jobdir}"

	# Wait for sbatch job to start running by monitoring the output of squeue:
	log INFO "Waiting for job ${launched_jobid} (\"${HYAKVNC_SLURM_JOB_NAME}\") to start"
	while true; do
		printf -v curtime '%(%s)T' -1
		if ((curtime - starttime > HYAKVNC_SLURM_SUBMIT_TIMEOUT)); then
			log ERROR "Timed out waiting for job ${launched_jobid} to start"
			exit 1
		fi
		sleep 1
		squeue_result=$(squeue --job "${launched_jobid}" --format "%T" --noheader || true)
		case "${squeue_result:-}" in
		SIGNALING | PENDING | CONFIGURING | STAGE_OUT | SUSPENDED | REQUEUE_HOLD | REQUEUE_FED | RESV_DEL_HOLD | STOPPED | RESIZING | REQUEUED)
			log TRACE "Job ${launched_jobid} is in a state that could potentially run: ${squeue_result}"
			sleep 1
			continue
			;;
		RUNNING)
			log DEBUG "Job ${launched_jobid} is ${squeue_result}"
			break
			;;
		*)
			log ERROR "Job ${launched_jobid} is in unexpected state ${squeue_result}"
			exit 1
			;;
		esac
	done

	log TRACE "Waiting for job ${launched_jobid} to create its directory at ${jobdir}"
	printf -v starttime '%(%s)T' -1
	while true; do
		printf -v curtime '%(%s)T' -1
		if ((curtime - starttime > HYAKVNC_DEFAULT_TIMEOUT)); then
			log ERROR "Timed out waiting for job to create its directory at ${jobdir}"
			exit 1
		fi
		sleep 1
		[[ ! -d "${jobdir}" ]] && {
			log TRACE "Job directory does not exist yet"
			continue
		}
		break
	done

	ln -s "${HYAKVNC_SLURM_OUTPUT_DIR}/job-${launched_jobid}.out" "${jobdir}/slurm.log" || log WARN "Could not link ${HYAKVNC_SLURM_OUTPUT_DIR}/job-${launched_jobid}.out" to "${jobdir}/slurm.log"

	if check_log_level "${HYAKVNC_LOG_LEVEL}" DEBUG; then
		echo "Streaming log from ${jobdir}/slurm.log"
		tail -n 1 -f "${jobdir}/slurm.log" --pid=$$ 2>/dev/null | sed --unbuffered 's/^/DEBUG: slurm.log: /' & # Follow the SLURM log file in the background
		tailpid=$!
	fi

	case "${HYAKVNC_APPTAINER_CONTAINER}" in
	library://* | docker://* | shub://* | oras://* | http://* | https://*)
		local protocol="${HYAKVNC_APPTAINER_CONTAINER#*://}"
		if [[ -n "${protocol:-}" ]]; then
			# Wait for the container to start downloading:
			log INFO "Downloading ${HYAKVNC_APPTAINER_CONTAINER}..."
			until grep -q -iE '(Download|cached).*image' "${jobdir}/slurm.log"; do
				sleep 1
			done
			# Wait for the container to stop downloading:
			# shellcheck disable=SC2016
			srun --jobid "${launched_jobid}" --output /dev/null sh -c 'while pgrep -u $USER -fia '"'"'^.*apptainer.*jobs/'"${launched_jobid}"'.*'"${protocol}""'"' | grep -v "^$$"; do sleep 1; done' || log WARN "Couldn't poll for container download process for ${HYAKVNC_APPTAINER_CONTAINER}"
		fi
		;;
	*) ;;
	esac

	log INFO "Waiting for VNC server to start..."
	# Wait for socket to become available:
	log DEBUG "Waiting for job ${launched_jobid} to create its socket file at ${jobdir}/vnc/socket.uds"

	printf -v starttime '%(%s)T' -1
	while true; do
		printf -v curtime '%(%s)T' -1
		if ((curtime - starttime > HYAKVNC_DEFAULT_TIMEOUT)); then
			log ERROR "Timed out waiting for job to open its directories"
			exit 1
		fi
		sleep 1
		[[ ! -d "${jobdir}" ]] && log TRACE "Job directory does not exist yet" && continue
		[[ ! -e "${jobdir}/vnc/socket.uds" ]] && log TRACE "Job socket does not exist yet" && continue
		[[ ! -S "${jobdir}/vnc/socket.uds" ]] && log TRACE "Job socket is not a socket" && continue
		[[ ! -r "${jobdir}/vnc/vnc.log" ]] && log TRACE "VNC log file not readable yet" && continue

		break
	done

	grep -q '^xstartup.turbovnc: Executing' <(timeout "${HYAKVNC_DEFAULT_TIMEOUT}" tail -f "${jobdir}/vnc/vnc.log" || true)

	log INFO "VNC server started"
	# Get details about the Xvnc process:
	print_connection_info -j "${launched_jobid}" || {
		log ERROR "Failed to print connection info for job ${launched_jobid}"
		return 1
	}
	# Stop trapping the signals:
	[[ -z "${XNOTRAP:-}" ]] && trap - SIGINT SIGTERM SIGHUP SIGABRT SIGQUIT ERR EXIT
	kill -9 "${tailpid}" 2>/dev/null # Stop following the SLURM log file
	return 0
}

! (return 0 2>/dev/null) && cmd_create "$@"
