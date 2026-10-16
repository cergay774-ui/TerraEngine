import os
import pickle
import platform
import shutil
from rich.console import Console

# Toolchain sources (same as upstream Newb X v16.56). When Minecraft changes the
# material format, upstream publishes new source materials here: update
# NS_DEV_MAT_SRC_URL (and lazurite in requirements.txt), run `build setup`.
CONF_FILE = os.path.join('tool', 'data', '.builder.pkl')
NS_DEV_RELEASE = "https://github.com/devendrn/newb-shader/releases/download/dev/"
NS_DEV_MAT_SRC_URL = NS_DEV_RELEASE + "src-materials-1.26.51.zip"
NS_DEV_SHADERC_URL_PREFIX = NS_DEV_RELEASE + "shaderc-"
SHADERC_PATH = os.path.join('tool', 'data', 'shaderc')
if os.name == 'nt':
    SHADERC_PATH += ".exe"
SRC_MATERIALS_EG_PATH = os.path.join('tool', 'data', 'materials', 'Sky.material.json')

MATERIALS_PATH = os.path.join('src', 'materials')
COMMON_PATH = os.path.join('src', 'common')


def print_styled_error(console: Console, log: str):
    log = log.strip().split('\n')
    for line in log:
        split_line = line.split()
        style = 'dim'
        if not split_line:
            continue
        if split_line[0] == "Command:":
            style = 'dim'
        elif split_line[0] == "Warning:":
            style = 'red'
        elif split_line[0] in ["Error:", ">>>", "cpp:"]:
            style = 'bold red'
        console.print(line, style=style)


def get_materials_path(mats: list[str]):
    all_materials = os.listdir(MATERIALS_PATH)
    material_patterns = []
    for m in mats:
        if m not in all_materials:
            raise FileNotFoundError(m)
        material_patterns.append(os.path.join(MATERIALS_PATH, m))
    return material_patterns


def sync_common_files():
    # every material needs material.json (uniform overrides) and uniforms/.
    # They are kept once in src/common and copied here before each build
    # (upstream uses symlinks, which break on Windows checkouts).
    material_json = os.path.join(COMMON_PATH, 'material.json')
    uniforms = os.path.join(COMMON_PATH, 'uniforms')
    for entry in os.scandir(MATERIALS_PATH):
        if not entry.is_dir():
            continue
        shutil.copyfile(material_json, os.path.join(entry.path, 'material.json'))
        dst = os.path.join(entry.path, 'uniforms')
        if os.path.islink(dst) or os.path.isfile(dst):
            os.remove(dst)
        elif os.path.isdir(dst):
            shutil.rmtree(dst)
        shutil.copytree(uniforms, dst)


def load_conf():
    try:
        with open(CONF_FILE, 'rb') as file:
            conf = pickle.load(file)
            if type(conf) is dict:
                return conf
        return {}
    except Exception:
        return {}


def save_conf(conf):
    with open(CONF_FILE, 'wb') as file:
        pickle.dump(conf, file)


def setup_needed() -> bool:
    conf = load_conf()
    return (
        conf.get("os_name") != platform.system()
        or conf.get("arch") != platform.machine()
        or conf.get("shaderc_url_prefix") != NS_DEV_SHADERC_URL_PREFIX
        or conf.get("mat_src_url") != NS_DEV_MAT_SRC_URL
        or not os.path.exists(SHADERC_PATH)
        or not os.path.exists(SRC_MATERIALS_EG_PATH)
    )
