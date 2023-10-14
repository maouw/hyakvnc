# hyakvnc
<!-- markdownlint-disable-file -->
hyakvnc -- A tool for launching VNC sessions on Hyak.

`hyakvnc` allocates resources then starts a VNC session within an Apptainer
environment.

## Prerequisites

Before running `hyakvnc`, you'll need the following:

- A Linux, macOS, or Windows machine
- The OpenSSH client (usually included with Linux and macOS, and available for Windows via [WSL2](https://learn.microsoft.com/en-us/windows/wsl/install) or [Cygwin](https://www.cs.odu.edu/~zeil/cs252/latest/Public/loggingin/cygwin.mmd.html) [note that the Windows 10+ built-in OpenSSH client will not work])
- A VNC client/viewer ([TurboVNC viewer](https://www.turbovnc.org) is recommended for all platforms)
- HYAK Klone access with compute resources
- A private SSH key on your local machine which has been added to the authorized keys on the login node of the HYAK Klone cluster (see below)
- A HyakVNC-compatible Apptainer container image in a directory on Hyak or the URL to one (e.g,., `{{ container_registry }}/ubuntu22.04_turbovnc:latest`)

Follow the instructions below to set up your machine correctly:

### Installing OpenSSH and TurboVNC

#### Linux

If you are using Linux, OpenSSH is probably installed already -- if not, you can install it via `apt-get install openssh-client` on Debian/Ubuntu or `yum install openssh-clients` on RHEL/CentOS/Rocky/Fedora. To open a terminal window, search for "Terminal" in your desktop environment's application launcher. 

To install TurboVNC, download the latest version from [here](https://sourceforge.net/projects/turbovnc/files). On Debian/Ubuntu, you will need to download the file ending with `arm64.deb`. On RHEL/CentOS/Rocky/Fedora, you will need to download the file ending with `x86_64.rpm`. Then, install it by running `sudo dpkg -i <filename>` on Debian/Ubuntu or `sudo rpm -i <filename>` on RHEL/CentOS/Rocky/Fedora.

#### macOS

If you're on macOS, OpenSSH will already be installed. To open a terminal window, open `/Applications/Utilities/Terminal.app` or search for "Terminal" in Launchpad or Spotlight.

To install TurboVNC, download the latest version from [here](https://sourceforge.net/projects/turbovnc/files). On an M1 Mac (newer), you will need to download the file ending with `arm64.dmg`. On an Intel Mac (older), you will need the file ending with `x86_64.dmg`. Then, open the `.dmg` file and launch the installer inside.

#### Windows

Windows needs a little more setup. You'll need to install a terminal emulator as well as the OpenSSH client. The easiest way to do this is to install [WSL2](https://learn.microsoft.com/en-us/windows/wsl/install) (recommended for Windows versions 10+, comes with the OpenSSH client already installed) or [Cygwin](https://www.cs.odu.edu/~zeil/cs252/latest/Public/loggingin/cygwin.mmd.html) (not recommended, needs additional setup). See the links for instructions on how to install these. You can start a terminal window by searching for "Terminal" in the Start menu.

To install TurboVNC, download the latest version from [here](https://sourceforge.net/projects/turbovnc/files). You will need the file ending with `x64.exe`. Run the program to install TurboVNC.

### Setting up SSH keys to connect to Hyak compute nodes

Before you are allowed to connect to a compute node where your VNC session will be running, you must add your SSH public key to the authorized keys on the login node of the HYAK Klone cluster.

If you don't, you will receive an error like this when you try to connect:

```text
Permission denied (publickey,gssapi-keyex,gssapi-with-mic)
```

To set this up quickly on Linux, macOS, or Windows (WSL2/Cygwin), open a new terminal window on your machine and enter the following 2 commands before you try again. Replace `your-uw-netid` with your UW NetID:

```bash
[ ! -r ~/.ssh/id_rsa ] && ssh-keygen -t rsa -b 4096 -N '' -C "your-uw-netid@uw.edu" -f ~/.ssh/id_rsa
ssh-copy-id -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa "your-uw-netid"@klone.hyak.uw.edu
```

Sew https://hyak.uw.edu/docs/setup/intracluster-keys for more information.

### Finding a HyakVNC-compatible container image

You'll need to find a HyakVNC-compatible container image to run your VNC session in. The following images are provided by us and can be used with `hyakvnc` by copying and pasting the URL into the `hyakvnc create` command:

- `{{ container_registry }}/ubuntu22.04_turbovnc:latest` -- Ubuntu 22.04 with TurboVNC
- `{{ container_registry }}/ubuntu22.04_turbovnc:latest` -- Ubuntu 22.04 with TurboVNC and Freesurfer

## Installing `hyakvnc`

`hyakvnc` should be installed on the login node of the HYAK Klone cluster.

To connect to the login node, you'll need to enter the following command into a terminal window (replacing `your-uw-netid` with your UW NetID) and provide your password when prompted:

```bash
ssh your-uw-netid@klone.hyak.uw.edu
```

### Quick install

After you've connected to the login node, you can download and install `hyakvnc` by running the following command. Copy and paste it into the terminal window where you are connected to the login node and press enter:

```bash
bash <(curl -fsSL {{ raw_script_url }}) install && [[ ":${PATH}:" != *":$HOME/.local/bin:"* ]] && export PATH="$HOME/.local/bin:$PATH" && [-n "${ZSH_VERSION:-}" ] && rehash
```

This will download and install `hyakvnc` to your `~/.local/bin` directory and add it to your `$PATH` so you can run it by typing `hyakvnc` into the terminal window.

### Installing manually

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

## Getting started

### Creating a VNC session

Start a VNC session with the `hyakvnc create` command followed by arguments to specify the container. In this example, we'll use a basic container for a graphical environment from the HyakVNC GitHub Container Registry:

```bash
hyakvnc create --container {{ container_registry }}/ubuntu22.04_turbovnc:latest
```

It may take a few minutes to download the container if you're running it the first time. If successful, `hyakvnc` should print commands and instructions to connect:

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

The following variables are available:

{% include 'config.inc.md' %}
## License

`hyakvnc` is licensed under [MIT License](LICENSE).
