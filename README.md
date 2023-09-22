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
- VNC client/viewer
  - TigerVNC viewer is recommended for all platforms
- HYAK Klone access with compute resources
- VNC Apptainer with TigerVNC server and a desktop environment
  - Install additional tools and libraries to the container as required by programs running within the VNC session.
- `xstartup` script used to launch a desktop environment
- A Python interpreter (version **3.9** or higher)

### Building

`hyakvnc` is a Python package that can be installed with `pip`. The minimum Python version required is **3.9**. You can check the version of the default Python 3 interpreter with:

```bash
python3 -V
```

As of 2021-09-30, the default Python 3 interpreter on Klone is version 3.6.8. Because `hyakvnc` requires version 3.9 or higher, it is necessary to specify the path to a Python 3.9 or newer interpreter when installing `hyakvnc`. You can list the Python 3 interpreters you have available with:

```bash
compgen -c | grep '^python3\.[[:digit:]]$'
```

At this time, Klone supports Python 3.9, which can be run with the command `python3.9`. The following instructions are written with `python3.9` in mind. If you use another version, such as `python3.11`, you will need to substitute `python3.9` with, e.g., `python3.11` in the instructions.

```bash
python3.9 -m pip install --upgrade --user pip
```

Build and install the package:

```bash
python3.9 -m pip install --user git+https://github.com/uw-psych/hyakvnc
```

Or, clone the repo and install the package locally:

```bash
git clone https://github.com/uw-psych/hyakvnc
python3.9 -m pip install --user .
```

If successful, then `hyakvnc` should be installed to `~/.local/bin/`.

#### Optional dependencies for development

The optional dependency group `[dev]` in `pyroject.toml` includes dependencies useful for development, including [pre-commit](https://pre-commit.com/) hooks that run in order to commit to the `git` repository.
These apply various checks, including running the `black` code formatter before the commit takes place.

To ensure `pre-commit` and other development packages are installed, run:

```bash
python3.9 -m pip install --user '.[dev]'
```

### General usage

`hyakvnc` is command-line tool that only works while on the login node.

### Creating a VNC session

1. Start a VNC session with the `hyakvnc create` command followed by arguments to specify the Slurm account and partition, compute resource needs, reservation time, and paths to a VNC apptainer and xstartup script.

   ```bash
   # Create a xubuntu VNC container with default settings from a container located at ~/code/maouw--hyak_vnc_apptainer/ubuntu22.04_xubuntu/ubuntu22.04_xubuntu.sif
	hyakvnc -d create --container ~/apptainer-test/maouw--hyak_vnc_apptainer/ubuntu22.04_xubuntu/ubuntu22.04_xubuntu.sif
    ```

2. If successful, `hyakvnc` should print a unique port forward command:

   ```text
	OpenSSH string for VNC session:
	  ssh  -f -o StrictHostKeyChecking=no -J klone.hyak.uw.edu g3071 -L 5908:localhost:5908 sleep 10; vncviewer localhost:5908
	OpenSSH string for VNC session using the built-in viewer on macOS:
	 ssh  -f -o StrictHostKeyChecking=no -J klone.hyak.uw.edu g3071 -L 5908:localhost:5908 sleep 10; \
   		open -b com.tigervnc.tigervnc --args localhost:5908 2>/dev/null || \
   		open -b com.realvnc.vncviewer --args localhost:5908 2>/dev/null || \
   		echo 'Cannot find an installed VNC viewer on macOS && echo Please install one from https://www.realvnc.com/en/connect/download/viewer/ or https://tigervnc.org/' && \
   		echo 'Alternatively, try entering the address localhost:{port_on_client} into your VNC application'
   ```

   Copy this port forward command for the following step.

3. Set up port forward between your computer and HYAK login node. On your machine, in a new terminal window, run the the copied command.

   Alternatively, for PuTTY users, navigate to `PuTTY Configuration->Connection->SSH->Tunnels`, then set:
   - source port to `AAAA`
   - destination to `127.0.0.1:BBBB`

   Press `Add`, then connect to Klone as normal. Keep this window open as it
   maintains a connection to the VNC session running on Klone.

4. Connect to the VNC session at instructed address (in this example:
   `localhost:AAAA`)

5. To close all VNC sessions on all SLURM jobs, run the following:

   ```bash
   hyakvnc stop-all
   ```

### Checking active VNC sessions

Print details of active VNC sessions (with the same job name) with the
`hyakvnc status` command.

### Closing active VNC session(s)

To stop a specific VNC job by its job ID, run `hyakvnc stop <job_id>`.

To stop all VNC jobs, run `hyakvnc stop-all`.

### Resetting VNC password

### Override Apptainer bind paths

If present, `hyakvnc` will use the [environment variables](https://tldp.org/LDP/Bash-Beginners-Guide/html/sect_03_02.html)  `APPTAINER_BINDPATH` or `SINGULARITY_BINDPATH` to
determine how paths are mounted in the VNC container environment. If neither is
defined, `hyakvnc` will use its default bindpath.

## License

`hyakvnc` is licensed under [MIT License](LICENSE).
