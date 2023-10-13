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

You will also need a VNC Apptainer with TurboVNC server installed. See {{ hyakvnc_apptainer_repo }} for prebuilt containers.

### Download and install

**`hyakvnc` should be installed on the login node of the HYAK Klone cluster.** 

To connect to the login node, you'll need to enter the following command into a terminal window (replacing `your-uw-netid` with your UW NetID) and provide your password when prompted:

```bash
ssh your-uw-netid@klone.hyak.uw.edu
```

After you've connected to the login node, you can download and install `hyakvnc` by running the following command. Copy and paste it into the terminal window where you are connected to the login node and press enter:

```bash
bash <(curl -fsSL {{ raw_script_url }}) install && [[ ":${PATH}:" != *":$HOME/.local/bin:"* ]] && export PATH="$HOME/.local/bin:$PATH" && [-n "${ZSH_VERSION:-}" ] && rehash
```

This will download and install `hyakvnc` to your `~/.local/bin` directory and add it to your `$PATH` so you can run it by typing `hyakvnc` into the terminal window.

#### Installing manually

In a terminal window connected to a login node, enter this command to clone the repository and navigate into the repository directory:

```bash
git clone {{ repo_url }} && cd hyakvnc
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
hyakvnc -d create --container {{ container_registry }}/ubuntu22.04_turbovnc:latest
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
{% include 'usage.inc.md' %}
## Configuration

The following environment variables can be used to override the default settings. Any arguments passed to `hyakvnc create` will override the environment variables.

You can modify the values of these variables by:

- Setting and exporting them in your shell session, e.g. `export HYAKVNC_SLURM_MEM=8G` (which will only affect the current shell session)
- Setting them in your shell's configuration file, e.g. `~/.bashrc` or `~/.zshrc` (which will affect all shell sessions)
- Setting them by prefixing the `hyakvnc` command with the variable assignment, e.g. `HYAKVNC_SLURM_MEM=8G hyakvnc create ...` (which will only affect the current command)
- Setting them in the file `~/.hyakvnc/hyakvnc-config.env` (which will affect all `hyakvnc` commands)

```text
{% include 'config.inc.md' %}
```

## License

`hyakvnc` is licensed under [MIT License](LICENSE).
