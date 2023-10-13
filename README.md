# hyakvnc

hyakvnc -- A tool for launching VNC sessions on Hyak.

`hyakvnc` allocates resources then starts a VNC session within an Apptainer
environment.

## Installation

### Prerequisites

Before running `hyakvnc`, you'll need the following:

- SSH client
- VNC client/viewer (TurboVNC viewer is recommended for all platforms)
- HYAK Klone access with compute resources

You will also need a VNC Apptainer with TurboVNC server installed. See var_hyakvnc_apptainer_repo for prebuilt containers.

### Download and install

**`hyakvnc` should be installed on the login node of the HYAK Klone cluster.** 

To connect to the login node, you'll need to enter the following command into a terminal window (replacing `your-uw-netid` with your UW NetID) and provide your password when prompted:

```bash
ssh your-uw-netid@klone.hyak.uw.edu
```

After you've connected to the login node, you can download and install `hyakvnc` by running the following command. Copy and paste it into the terminal window where you are connected to the login node and press enter:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/maouw/hyakvnc/main/hyakvnc) install && [[ ":${PATH}:" != *":$HOME/.local/bin:"* ]] && export PATH="$HOME/.local/bin:$PATH" && [-n "${ZSH_VERSION:-}" ] && rehash
```

This will download and install `hyakvnc` to your `~/.local/bin` directory and add it to your `$PATH` so you can run it by typing `hyakvnc` into the terminal window.

#### Installing manually

In a terminal window connected to a login node, enter this command to clone the repository and navigate into the repository directory:

```bash
git clone https://github.com/maouw/hyakvnc && cd hyakvnc
```

Then, run the following command to install `hyakvnc`:

```bash
./hyakvnc install
```

If you prefer, you may continue to use `hyakvnc` from the directory where you cloned it by running `./hyakvnc` from that directory instead of using the command `hyakvnc`.
started

## Quick start

### Creating a VNC session

Start a VNC session with the `hyakvnc create` command followed by arguments to specify the container. In this example, we'll use a basic container for a graphical environment from the HyakVNC GitHub Container Registry:

```bash
hyakvnc -d create --container oras://ghcr.io/maouw/ubuntu22.04_turbovnc:latest
```

If successful, `hyakvnc` should print commands and instructions to connect:

```text
LINUX TERMINAL (bash/zsh):
ssh -f -o StrictHostKeyChecking=no -L 5901:/mmfs1/home/altan/.hyakvnc/jobs/15037283/vnc/socket.uds -J altan@klone.hyak.uw.edu altan@g3050 sleep 10 && vncviewer localhost:5901

MACOS TERMINAL
ssh -f -o StrictHostKeyChecking=no -L 5901:/mmfs1/home/altan/.hyakvnc/jobs/15037283/vnc/socket.uds -J altan@klone.hyak.uw.edu altan@g3050 sleep 10 && open -b com.turbovnc.vncviewer --args localhost:5901 2>/dev/null || open -b com.realvnc.vncviewer --args localhost:5901 2>/dev/null || open -b com.tigervnc.vncviewer --args localhost:5901 2>/dev/null || echo 'No VNC viewer found. Please install one or try entering the connection information manually.'

WINDOWS
(See below)

MANUAL CONNECTION INFORMATION
Configure your SSH client to connect to the address g3050 with username altan through the "jump host" (possibly labeled a via, proxy, or gateway host) at the address "klone.hyak.uw.edu".
Enable local port forwarding from port 5901 on your machine ('localhost' or 127.0.0.1) to the socket /mmfs1/home/altan/.hyakvnc/jobs/15037283/vnc/socket.uds on the remote host.
In your VNC client, connect to 'localhost' or 127.0.0.1 on port 5901

==========
```

## Usage

`hyakvnc` is command-line tool that only works on the login node of the Hyak cluster.

### Create a VNC session on Hyak

```text
Usage: hyakvnc create [create options...] -c <container> [extra args to pass to apptainer...]

Description:
        Create a VNC session on Hyak.

Options:
        -h, --help      Show this help message and exit
        -c, --container Path to container image (required)
        -A, --account   Slurm account to use (default: )
        -p, --partition Slurm partition to use (default: )
        -C, --cpus      Number of CPUs to request (default: 4)
        -m, --mem       Amount of memory to request (default: 4G)
        -t, --timelimit Slurm timelimit to use (default: 12:00:00)
        -g, --gpus      Number of GPUs to request (default: 1)

Extra arguments:
        Any extra arguments will be passed to apptainer run.
        See 'apptainer run --help' for more information.

Examples:
        # Create a VNC session using the container ~/containers/mycontainer.sif
        # Use the SLURM account escience, the partition gpu-a40, 4 CPUs, 1GB of memory, 1 GPU, and 1 hour of time
        hyakvnc create -c ~/containers/mycontainer.sif -A escience -p gpu-a40 -C 4 -m 1G -t 1:00:00 -g 1
```

### Show the status of running HyakVNC sessions

```text
Usage: hyakvnc status [status options...]

Description:
        Check status of VNC session(s) on Hyak.

Options:
        -h, --help      Show this help message and exit
        -d, --debug     Print debug info
        -j, --jobid     Only check status of provided SLURM job ID (optional)

Examples:
        # Check the status of job no. 12345:
        hyakvnc status -j 12345
        # Check the status of all VNC jobs:
        hyakvnc status
```

### Show connection information for a HyakVNC sesssion

```text
Usage: hyakvnc show <jobid>
        
Description:
        Show connection information for a HyakVNC sesssion.
        If no job ID is provided, a menu will be shown to select from running jobs.

Options:
        -h, --help      Show this help message and exit

Examples:
        # Show connection information for session running on job 123456:
        hyakvnc show 123456
```

### Stop a HyakVNC session

```text
Usage: hyakvnc stop [-a] [<jobids>...]
        
Description:
        Stop a provided HyakVNC sesssion and clean up its job directory.
        If no job ID is provided, a menu will be shown to select from running jobs.

Options:
        -h, --help      Show this help message and exit
        -n, --no-cancel Don't cancel the SLURM job
        -a, --all       Stop all jobs

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

### Show the current configuration for hyakvnc

```text
Usage: hyakvnc config [config options...]
        
Description:
        Show the current configuration for hyakvnc, as set in the user configuration file at /home/altan/.hyakvnc/hyakvnc-config.env, in the current environment, or the default values set by hyakvnc.

Options:
        -h, --help              Show this help message and exit

Examples:
        # Show configuration
        hyakvnc config
```

### Install the hyakvnc command

```text
Usage: hyakvnc install [install options...]
        
Description:
        Install hyakvnc so the "hyakvnc" command can be run from anywhere.

Options:
        -h, --help                      Show this help message and exit
        -i, --install-dir               Directory to install hyakvnc to (default: ~/.local/bin)
        -s, --shell [bash|zsh]  Shell to install hyakvnc for (default: $SHELL or bash)

Examples:
        # Install
        hyakvnc install
        # Install to ~/bin:
        hyakvnc install -i ~/bin
```

## Configuration

The following environment variables can be used to override the default settings. Any arguments passed to `hyakvnc create` will override the environment variables.

You can modify the values of these variables by:

- Setting and exporting them in your shell session, e.g. `export HYAKVNC_SLURM_MEM=8G` (which will only affect the current shell session)
- Setting them in your shell's configuration file, e.g. `~/.bashrc` or `~/.zshrc` (which will affect all shell sessions)
- Setting them by prefixing the `hyakvnc` command with the variable assignment, e.g. `HYAKVNC_SLURM_MEM=8G hyakvnc create ...` (which will only affect the current command)
- Setting them in the file `~/.hyakvnc/hyakvnc-config.env` (which will affect all `hyakvnc` commands)

The following variables are available:

- HYAKVNC_DIR: Local directory to store application data (default: `$HOME/.hyakvnc`)
- HYAKVNC_CONFIG_FILE: Configuration file to use (default: `$HYAKVNC_DIR/hyakvnc-config.env`)
- HYAKVNC_LOG_FILE: Log file to use (default: `$HYAKVNC_DIR/hyakvnc.log`)
- HYAKVNC_LOG_LEVEL: Log level to use for interactive output (default: `INFO`)
- HYAKVNC_LOG_FILE_LEVEL: Log level to use for log file output (default: `DEBUG`)
- HYAKVNC_SSH_HOST: Default SSH host to use for connection strings (default: `klone.hyak.uw.edu`)
- HYAKVNC_DEFAULT_TIMEOUT: Seconds to wait for most commands to complete before timing out (default: `30`)
- HYAKVNC_VNC_PASSWORD: Password to use for new VNC sessions (default: `password`)
- HYAKVNC_VNC_DISPLAY: VNC display to use (default: `:1`)
- HYAKVNC_MACOS_VNC_VIEWER_BUNDLEIDS: macOS bundle identifiers for VNC viewer executables (default: `com.turbovnc.vncviewer com.realvnc.vncviewer com.tigervnc.vncviewer`)
- HYAKVNC_APPTAINER_BIN: Name of apptainer binary (default: `apptainer`)
- HYAKVNC_APPTAINER_CONTAINER: Path to container image to use (default: (none; set by `--container` option))
- HYAKVNC_APPTAINER_APP_VNCSERVER: Name of app in the container that starts the VNC session (default: `vncserver`)
- HYAKVNC_APPTAINER_APP_VNCKILL: Name of app that cleanly stops the VNC session in the container (default: `vnckill`)
- HYAKVNC_APPTAINER_WRITABLE_TMPFS: Whether to use a writable tmpfs for the container (default: `1`)
- HYAKVNC_APPTAINER_CLEANENV: Whether to use a clean environment for the container (default: `1`)
- HYAKVNC_APPTAINER_ADD_BINDPATHS: Bind paths to add to the container (default: (none))
- HYAKVNC_APPTAINER_ADD_ENVVARS: Environment variables to add to before invoking apptainer (default: (none))
- HYAKVNC_APPTAINER_ADD_ARGS: Additional arguments to give apptainer (default: (none))
- HYAKVNC_SLURM_JOB_PREFIX: Prefix to use for hyakvnc SLURM job names (default: `hyakvnc-`)
- HYAKVNC_SLURM_SUBMIT_TIMEOUT: Seconds after submitting job to wait for the job to start before timing out (default: `120`)
- HYAKVNC_SLURM_OUTPUT_DIR: Directory to store SLURM output files (default: `$HYAKVNC_DIR/slurm-output`)
- HYAKVNC_SLURM_OUTPUT: Where to send SLURM job output (default: `$HYAKVNC_SLURM_OUTPUT_DIR/job-%j.out`)
- HYAKVNC_SLURM_JOB_NAME: What to name the launched SLURM job (default: (set according to container name))
- HYAKVNC_SLURM_ACCOUNT: Slurm account to use (default: (autodetected))
- HYAKVNC_SLURM_PARTITION: Slurm partition to use (default: (autodetected))
- HYAKVNC_SLURM_CLUSTER: Slurm cluster to use (default: (autodetected))
- HYAKVNC_SLURM_GPUS: Number of GPUs to request (default: (none))
- HYAKVNC_SLURM_MEM: Amount of memory to request, in [M]egabytes or [G]igabytes (default: `4G`)
- HYAKVNC_SLURM_CPUS: Number of CPUs to request (default: `4`)
- HYAKVNC_SLURM_TIMELIMIT: Time limit for SLURM job (default: `12:00:00`)


## License

`hyakvnc` is licensed under [MIT License](LICENSE).
