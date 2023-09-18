from .config import APPTAINER_CONFIGDIR
import json
from pathlib import Path
def get_running_instances(configdir=APPTAINER_CONFIGDIR):
    appdir = Path(APPTAINER_CONFIGDIR).expanduser() / 'instances' / 'app'
    json_files = appdir.rglob('*.json')
    return {jf.parent.relative_to(appdir): json.load(open(jf, 'r')) for jf in json_files}
