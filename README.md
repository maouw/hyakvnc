# hyakvnc

Create and manage VNC Slurm jobs on UW HYAK Klone cluster.

`hyakvnc` allocates resources then starts a VNC session within an Apptainer
environment.

Disclaimer: VNC sessions are time-limited and will expire with all processes
closed. Save often if you can or reserve a session for a generous length of
time.

## Get started

### Prerequisites

Before running `hyakvnc`, you'll need the following:

- SSH client
- VNC client/viewer (TurboVNC viewer is recommended for all platforms)
- HYAK Klone access with compute resources
- VNC Apptainer with TurboVNC server installed and a SCIF app named "vncserver"

### Downloading

Clone the repository:

```bash
git clone https://github.com/maouw/hyakvnc
```

Or downlooad the program directly:

```bash
wget https://raw.githubusercontent.com/maouw/hyakvnc/main/hyakvnc && chmod +x hyakvnc
```

### Usage

`hyakvnc` is command-line tool that only works while on the login node.

You can run it from the directory where you downloaded it like so:

```bash
./hyakvnc
```

#### Installation
You can also install it to your `$PATH` so you can run it from anywhere without prefixing with `./`:

```bash
./hyakvnc install
```

Once you do this, you should be able to run it like this:

```bash 
hyakvnc
```

#### General usage

```text
hyakvnc -- A tool for launching VNC sessions on Hyak.
Usage: hyakvnc [options] [create|status|stop|show|install|help] [options] [args]

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
	install	Install hyakvnc so the "hyakvnc" command can be run from anywhere
	help	Show help for a command
```

#### Create a HyakVNC session

```text
Usage: hyakvnc create [create options...] -c <container> [extra args to pass to apptainer...]

Description:
  Create a VNC session on Hyak.

Options:
  -h, --help     Show this help message and exit
  -c, --container     Path to container image (required)
  -A, --account     Slurm account to use (default: )
  -p, --partition     Slurm partition to use (default: )
  -C, --cpus     Number of CPUs to request (default: 4)
  -m, --mem     Amount of memory to request (default: 4G)
  -t, --timelimit     Slurm timelimit to use (default: 12:00:00)
  -g, --gpus     Number of GPUs to request (default: )

Extra arguments:
  Any extra arguments will be passed to apptainer run.
  See 'apptainer run --help' for more information.

Examples:
  # Create a VNC session using the container ~/containers/mycontainer.sif
  # Use the SLURM account escience, the partition gpu-a40, 4 CPUs, 1GB of memory, 1 GPU, and 1 hour of time
  hyakvnc create -c ~/containers/mycontainer.sif -A escience -p gpu-a40 -C 4 -m 1G -t 1:00:00 -g 1
```

#### Show status of running HyakVNC session(s)

```text
Usage: hyakvnc status [status options...]

Description:
  Check status of VNC session(s) on Hyak.

Options:
  -h, --help     Show this help message and exit
  -d, --debug     Print debug info
  -j, --jobid     Only check status of provided SLURM job ID (optional)

Examples:
  # Check the status of job no. 12345:
  hyakvnc status -j 12345
  # Check the status of all VNC jobs:
  hyakvnc status
```

#### Stop a HyakVNC session

```text
Usage: hyakvnc stop [-a] [<jobids>...]

Description:
  Stop a provided HyakVNC sesssion and clean up its job directory.
  If no job ID is provided, a menu will be shown to select from running jobs.

Options:
  -h, --help     Show this help message and exit
  -n, --no-cancel     Don't cancel the SLURM job
  -a, --all     Stop all jobs

Examples:
  # Stop a VNC session running on job 123456:
  hyakvnc stop 123456
  # Stop a VNC session running on job 123456 and do not cancel the job:
  hyakvnc stop --no-cancel 123456
  # Stop all VNC sessions:
  hyakvnc stop -a
  # Stop all VNC sessions but do not cancel the jobs:
  hyakvnc stop -a -n
```

#### Show connection information for a HyakVNC session

```text
Usage: hyakvnc show <jobid>

Description:
  Show connection information for a HyakVNC sesssion.
  If no job ID is provided, a menu will be shown to select from running jobs.

Options:
  -h, --help     Show this help message and exit

Examples:
  # Show connection information for session running on job 123456:
  hyakvnc show 123456
```

#### Install HyakVNC

```text
Usage: hyakvnc install [install options...]
 
Description:
  Install hyakvnc so the "hyakvnc" command can be run from anywhere.

Options:
  -h, --help			Show this help message and exit
  -i, --install-dir		Directory to install hyakvnc to (default: ~/.local/bin)
  -s, --shell {bash|zsh}	Shell to install hyakvnc for (default: \$SHELL or bash)

Examples:
  # Install
  hyakvnc install
  # Install to ~/bin:
  hyakvnc install -i ~/bin
```

## Quickstart

### Creating a VNC session

1. Start a VNC session with the `hyakvnc create` command followed by arguments to specify the container.

```bash
# Create a VNC container with default settings from a container downloaded from the HyakVNC GitHub Container Registry:
hyakvnc -d create --container oras://ghcr.io/maouw/ubuntu22.04_turbovnc:latest
```

2. If successful, `hyakvnc` should print commands and instructions to connect:

```text
==========
Copy and paste these instructions into a command line terminal on your local machine to connect to the VNC session.
You may need to install a VNC client if you don't already have one.
If you are using Windows or are having trouble, try using the manual connection information.
---------
LINUX TERMINAL (bash/zsh):
ssh -f -o StrictHostKeyChecking=no -L 5901:/mmfs1/home/altan/.hyakvnc/jobs/14940429/vnc/socket.uds -J altan@klone.hyak.uw.edu altan@g3060 sleep 10 && vncviewer localhost:5901

MACOS TERMINAL
ssh -f -o StrictHostKeyChecking=no -L 5901:/mmfs1/home/altan/.hyakvnc/jobs/14940429/vnc/socket.uds -J altan@klone.hyak.uw.edu altan@g3060 sleep 10 && open -b com.turbovnc.vncviewer.VncViewer --args localhost:5901 2>/dev/null || ope
n -b com.realvnc.vncviewer --args localhost:5901 2>/dev/null || open -b com.tigervnc.vncviewer --args localhost:5901 2>/dev/null || No VNC viewer found. Please install one or try entering the connection information manually.

WINDOWS
(See below)

MANUAL CONNECTION INFORMATION
Configure your SSH client to connect to the address g3060 with username altan through the "jump host" (possibly labeled a via, proxy, or gateway host) at the address "klone.hyak.uw.edu".
Enable local port forwarding from port 5901 on your machine ('localhost' or 127.0.0.1) to the socket /mmfs1/home/altan/.hyakvnc/jobs/14940429/vnc/socket.uds on the remote host.
In your VNC client, connect to 'localhost' or 127.0.0.1 on port 5901

==========
```

### Override setting with environment variables

The following environment variables can be used to override the default settings. Any arguments passed to `hyakvnc create` will override the environment variables.

```text
HYAKVNC_DIR - Local directory to store application data (default: ~/.hyakvnc)
HYAKVNC_LOG_LEVEL - Log level to use for interactive output (default: INFO)
HYAKVNC_LOG_FILE_LEVEL - Log level to use for log file output (default: DEBUG)
HYAKVNC_SSH_HOST - Default SSH host to use for connection strings (default: klone.hyak.uw.edu)
HYAKVNC_DEFAULT_TIMEOUT - How long to wait for most commands to complete before timing out (default: 30)
HYAKVNC_VNC_PASSWORD - Password to use for new VNC sessions (default: password)
HYAKVNC_VNC_DISPLAY - VNC display to use (default: :1)
HYAKVNC_MACOS_VNC_VIEWER_BUNDLEIDS - macOS bundle identifiers for VNC viewer executables (default: com.turbovnc.vncviewer, com.realvnc.vncviewer,com.tigervnc.vncviewer)
HYAKVNC_APPTAINER_BIN - Name of apptainer binary (default: apptainer)
HYAKVNC_APPTAINER_CONTAINER - Path to container image
HYAKVNC_APPTAINER_APP_VNCSERVER - Name of app in the container that starts the VNC session (default: vncserver)
HYAKVNC_APPTAINER_APP_VNCKILL - Name of app that cleanly stops the VNC session in the container (default: vnckill)
HYAKVNC_APPTAINER_WRITABLE_TMPFS - Whether to use a writable tmpfs for the container (default: 1)
HYAKVNC_APPTAINER_CLEANENV - Whether to use a clean environment for the container (default: 1)
HYAKVNC_APPTAINER_ADD_BINDPATHS - Bind paths to add to the container
HYAKVNC_APPTAINER_ADD_ENVVARS - Environment variables to add to before invoking apptainer
HYAKVNC_APPTAINER_ADD_ARGS - A_dditional arguments to give apptainer
HYAKVNC_SLURM_JOB_PREFIX - Prefix to use for hyakvnc SLURM job names (default: hyakvnc-)
HYAKVNC_SLURM_SUBMIT_TIMEOUT - How long after submitting via sbatch to wait for the job to start before timing out (default: 120)
HYAKVNC_SLURM_OUTPUT_DIR - Directory to store SLURM output files (default: ~/.hyakvnc/slurm-output)
HYAKVNC_SLURM_ACCOUNT - Slurm account to use (default: (autodetected))
HYAKVNC_SLURM_PARTITION - Slurm partition to use (default: (autodetected))
HYAKVNC_SLURM_CLUSTER - Slurm cluster to use (default: (autodetected))
HYAKVNC_SLURM_GPUS - Number of GPUs to request (default: not set)
HYAKVNC_SLURM_MEM - Amount of memory to request (default: 4G)
HYAKVNC_SLURM_CPUS - Number of CPUs to request (default: 4)
HYAKVNC_SLURM_TIMELIMIT - Time limit for SLURM job (default: 12:00:00)
```

## License

`hyakvnc` is licensed under [MIT License](LICENSE).
