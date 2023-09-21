import base64
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Optional, Union
import logging
from . import logger


@dataclass
class ApptainerInstanceInfo:
    pid: int
    ppid: int
    name: str
    user: str
    image: str
    userns: bool
    cgroup: bool
    ip: Optional[str] = None
    logErrPath: Optional[str] = None
    logOutPath: Optional[str] = None
    checkpoint: Optional[str] = None
    config: Optional[dict] = None
    instance_path: Optional[str] = None
    instance_name: Optional[str] = None

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

        with open(path, "r") as f:
            contents = json.load(f)
            if not read_config:
                contents.pop("config", None)
            else:
                contents['config'] = json.loads(base64.b64decode(contents['config']).decode('utf-8'))
            contents['instance_path'] = str(path)
            contents['instance_name'] = str(path.stem)
            return ApptainerInstanceInfo(**contents)
