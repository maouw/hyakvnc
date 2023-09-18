from .config import APPTAINER_BIN, APPTAINER_BINDPATH
class Node:
    """
    The Node class has the following initial data: bool: debug, string: name.

    debug: Print and log debug messages if True.
    name: Shortened hostname of node.
    """

    def __init__(self, name, sing_container, debug=False):
        self.debug = debug
        self.name = name
        self.sing_container = os.path.abspath(sing_container)

    def get_sing_exec(self, args=""):
        """
        Added before command to execute inside an apptainer (singularity) container.

        Arg:
          args: Optional arguments passed to `apptainer exec`

        Return apptainer exec string
        """
        return f"{APPTAINER_BIN} exec {args} -B {APPTAINER_BINDPATH} {self.sing_container}"
