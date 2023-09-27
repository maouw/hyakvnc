import base64
import json
from pathlib import Path
from typing import Union, Dict


class ApptainerInstanceInfo:
    def __init__(
        self,
        pid: int,
        ppid: int,
        name: str,
        user: str,
        image: str,
        userns: bool,
        cgroup: bool,
        ip: str = None,
        logErrPath: Union[str, Path] = None,
        logOutPath: Union[str, Path] = None,
        checkpoint: str = None,
        config: Dict = None,
        instance_path: str = None,
        instance_name: str = None,
    ):
        self.pid = pid
        self.ppid = ppid
        self.name = name
        self.user = user
        self.image = image
        self.userns = userns
        self.cgroup = cgroup
        self.ip = ip
        self.logErrPath = logErrPath
        self.logOutPath = logOutPath
        self.checkpoint = checkpoint
        self.config = config
        self.instance_path = instance_path
        self.instance_name = instance_name

    @staticmethod
    def from_json(path: Union[str, Path], read_config: bool = False) -> "ApptainerInstanceInfo":
        """
        Loads a ApptainerInstanceInfo from a JSON file.
        :param path: path to JSON file
        :param read_config: whether to read the config from the JSON file
        :return: ApptainerInstanceInfo loaded from JSON file
        """
        path = Path(path).expanduser()
        if not path.is_file():
            raise ValueError(f"Invalid path to instance file: {path}")

        try:
            with open(path, "r") as f:
                contents = json.load(f)
                if not read_config:
                    contents.pop("config", None)
                else:
                    contents["config"] = json.loads(base64.b64decode(contents["config"]).decode("utf-8"))
                contents["instance_path"] = str(path)
                contents["instance_name"] = str(path.stem)
                return ApptainerInstanceInfo(**contents)
        except json.JSONDecodeError as e:
            raise ValueError(f"Invalid JSON in instance file: {path}") from e
        except FileNotFoundError as e:
            raise ValueError(f"Could not find instance file: {path}") from e
