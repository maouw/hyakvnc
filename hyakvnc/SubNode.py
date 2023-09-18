from . import Node
from .config import BASE_VNC_PORT
class SubNode(Node):
    """
    The SubNode class specifies a node requested via Slurm (also known as work
    or interactive node). SubNode class is initialized with the following:
    bool: debug, string: name, string: hostname, int: job_id.

    SubNode class with active VNC session may contain vnc_display_number and
    vnc_port.

    debug: Print and log debug messages if True.
    name: Shortened subnode hostname (e.g. n3000) described inside `/etc/hosts`.
    hostname: Full subnode hostname (e.g. n3000.hyak.local).
    job_id: Slurm Job ID that allocated the node.
    vnc_display_number: X display number used for VNC session.
    vnc_port: vnc_display_number + BASE_VNC_PORT.
    """

    def __init__(self, name, job_id, sing_container, xstartup, debug=False):
        super().__init__(name, sing_container, xstartup, debug)
        self.hostname = f"{name}.hyak.local"
        self.job_id = job_id
        self.vnc_display_number = None
        self.vnc_port = None

    def print_props(self):
        """
        Print properties of SubNode object.
        """
        print("SubNode properties:")
        props = vars(self)
        for item in props:
            msg = f"{item} : {props[item]}"
            print(f"\t{msg}")
            if self.debug:
                logging.debug(msg)

    def run_command(self, command: str, timeout=None):
        """
        Run command (with arguments) on subnode


        Args:
          command:str : command and its arguments to run on subnode
          timeout : [Default: None] timeout length in seconds

        Returns ssh subprocess with stderr->stdout and stdout->PIPE
        """
        assert self.name is not None
        cmd = ["ssh", self.hostname, command]
        if timeout is not None:
            cmd.insert(0, "timeout")
            cmd.insert(1, str(timeout))
        if self.debug:
            msg = f"Running on {self.name}: {cmd}"
            print(msg)
            logging.info(msg)
        return subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

    def list_pids(self):
        """
        Returns list of PIDs of current job_id using
        `scontrol listpids <job_id>`.
        """
        ret = list()
        cmd = f"scontrol listpids {self.job_id}"
        proc = self.run_command(cmd)
        while proc.poll() is None:
            line = str(proc.stdout.readline(), "utf-8").strip()
            if self.debug:
                msg = f"list_pids: {line}"
                logging.debug(msg)
            if "PID" in line:
                pass
            elif re.match("[0-9]+", line):
                pid = int(line.split(" ", 1)[0])
                ret.append(pid)
        return ret

    def check_pid(self, pid: int):
        """
        Returns True if given pid is active in job_id and False otherwise.
        """
        return pid in self.list_pids()

    def get_vnc_pid(self, hostname, display_number):
        """
        Returns pid from file <hostname>:<display_number>.pid or None if file
        does not exist.
        """
        if hostname is None:
            hostname = self.hostname
        if display_number is None:
            display_number = self.vnc_display_number
        assert hostname is not None
        if display_number is not None:
            filepaths = glob.glob(os.path.expanduser(f"~/.vnc/{hostname}*:{display_number}.pid"))
            for path in filepaths:
                try:
                    f = open(path, "r")
                except:
                    pass
                return int(f.readline())
        return None

    def check_vnc(self):
        """
        Returns True if VNC session is active and False otherwise.
        """
        assert self.name is not None
        assert self.job_id is not None
        pid = self.get_vnc_pid(self.hostname, self.vnc_display_number)
        if pid is None:
            pid = self.get_vnc_pid(self.name, self.vnc_display_number)
            if pid is None:
                return False
        if self.debug:
            logging.debug(f"check_vnc: Checking VNC PID {pid}")
        return self.check_pid(pid)

    def start_vnc(self, display_number=None, extra_args="", timeout=20):
        """
        Starts VNC session

        Args:
          display_number: Attempt to acquire specified display number if set.
                          If None, then let vncserver determine display number.
          extra_args: Optional arguments passed to `apptainer exec`
          timeout: timeout length in seconds

        Returns True if VNC session was started successfully and False otherwise
        """
        target = ""
        if display_number is not None:
            target = f":{display_number}"
        vnc_cmd = f"{self.get_sing_exec(extra_args)} vncserver {target} -xstartup {self.xstartup} &"
        if not self.debug:
            print("Starting VNC server...", end="", flush=True)
        proc = self.run_command(vnc_cmd, timeout=timeout)

        # get display number and port number
        while proc.poll() is None:
            line = str(proc.stdout.readline(), "utf-8").strip()

            if line is not None:
                if self.debug:
                    logging.debug(f"start_vnc: {line}")
                if "desktop" in line:
                    # match against the following pattern:
                    # New 'n3000.hyak.local:1 (hansem7)' desktop at :1 on machine n3000.hyak.local
                    # New 'n3000.hyak.local:6 (hansem7)' desktop is n3000.hyak.local:6
                    pattern = re.compile(
                        """
                            (New\s)
                            (\'([^:]+:(?P<display_number>[0-9]+))\s([^\s]+)\s)
                            """,
                        re.VERBOSE,
                    )
                    match = re.match(pattern, line)
                    assert match is not None
                    self.vnc_display_number = int(match.group("display_number"))
                    self.vnc_port = self.vnc_display_number + BASE_VNC_PORT
                    if self.debug:
                        logging.debug(f"Obtained display number: {self.vnc_display_number}")
                        logging.debug(f"Obtained VNC port: {self.vnc_port}")
                    else:
                        print("\x1b[1;32m" + "Success" + "\x1b[0m")
                    return True
        if self.debug:
            logging.error("Failed to start vnc session (Timeout/?)")
        else:
            print("\x1b[1;31m" + "Timed out" + "\x1b[0m")
        return False

    def list_vnc(self):
        """
        Returns a list of active and stale vnc sessions on subnode.
        """
        active = list()
        stale = list()
        cmd = f"{self.get_sing_exec()} vncserver -list"
        # TigerVNC server sessions:
        #
        # X DISPLAY #	PROCESS ID
        #:1		7280 (stale)
        #:12		29 (stale)
        #:2		83704 (stale)
        #:20		30
        #:3		84266 (stale)
        #:4		90576 (stale)
        pattern = re.compile(r":(?P<display_number>\d+)\s+\d+(?P<stale>\s\(stale\))?")
        proc = self.run_command(cmd)
        while proc.poll() is None:
            line = str(proc.stdout.readline(), "utf-8").strip()
            match = re.search(pattern, line)
            if match is not None:
                display_number = match.group("display_number")
                if match.group("stale") is not None:
                    stale.append(display_number)
                else:
                    active.append(display_number)
        return (active, stale)

    def __remove_files__(self, filepaths: list):
        """
        Removes files on subnode and returns True on success and False otherwise.

        Arg:
          filepaths: list of file paths to remove. Each entry must be a file
                     and not a directory.
        """
        cmd = f"rm -f"
        for path in filepaths:
            cmd = f"{cmd} {path}"
        cmd = f"{cmd} &> /dev/null"
        if self.debug:
            logging.debug(f"Calling ssh {self.hostname} {cmd}")
        return subprocess.call(["ssh", self.hostname, cmd]) == 0

    def __listdir__(self, dirpath):
        """
        Returns a list of contents inside directory.
        """
        ret = list()
        cmd = f"test -d {dirpath} && ls -al {dirpath} | tail -n+4"
        pattern = re.compile(
            """
            ([^\s]+\s+){8}
            (?P<name>.*)
            """,
            re.VERBOSE,
        )
        proc = self.run_command(cmd)
        while proc.poll() is None:
            line = str(proc.stdout.readline(), "utf-8").strip()
            match = re.match(pattern, line)
            if match is not None:
                name = match.group("name")
                ret.append(name)
        return ret

    def kill_vnc(self, display_number=None):
        """
        Kill specified VNC session with given display number or all VNC sessions.
        """
        if display_number is None:
            active, stale = self.list_vnc()
            for entry in active:
                if self.debug:
                    logging.debug(f"kill_vnc: active entry: {entry}")
                self.kill_vnc(entry)
            for entry in stale:
                if self.debug:
                    logging.debug(f"kill_vnc: stale entry: {entry}")
                self.kill_vnc(entry)
            # Remove all remaining pid files
            pid_list = glob.glob(os.path.expanduser("~/.vnc/*.pid"))
            for pid_file in pid_list:
                try:
                    os.remove(pid_file)
                except:
                    pass
            # Remove all owned socket files on subnode
            # Note: subnode maintains its own /tmp/ directory
            x11_unix = "/tmp/.X11-unix"
            ice_unix = "/tmp/.ICE-unix"
            file_targets = list()
            for entry in self.__listdir__(x11_unix):
                file_targets.append(f"{x11_unix}/{entry}")
            for entry in self.__listdir__(ice_unix):
                file_targets.append(f"{x11_unix}/{entry}")
            self.__remove_files__(file_targets)
        else:
            assert display_number is not None
            target = f":{display_number}"
            if self.debug:
                print(f"Attempting to kill VNC session {target}")
                logging.debug(f"Attempting to kill VNC session {target}")
            cmd = f"{self.get_sing_exec()} vncserver -kill {target}"
            proc = self.run_command(cmd)
            killed = False
            while proc.poll() is None:
                line = str(proc.stdout.readline(), "utf-8").strip()
                # Failed attempt:
                # Can't kill '29': Operation not permitted
                # Killing Xtigervnc process ID 29...
                # On successful attempt:
                # Killing Xtigervnc process ID 29... success!
                if self.debug:
                    logging.debug(f"kill_vnc: {line}")
                if "success" in line:
                    killed = True
            if self.debug:
                logging.debug(f"kill_vnc: killed? {killed}")
            # Remove target's pid file if present
            try:
                os.remove(os.path.expanduser(f"~/.vnc/{self.hostname}{target}.pid"))
            except:
                pass
            try:
                os.remove(os.path.expanduser(f"~/.vnc/{self.name}{target}.pid"))
            except:
                pass
            # Remove associated /tmp/.X11-unix/<display_number> socket
            socket_file = f"/tmp/.X11-unix/{display_number}"
            self.__remove_files__([socket_file])
