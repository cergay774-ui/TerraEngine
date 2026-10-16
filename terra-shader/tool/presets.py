import tomllib
from dataclasses import dataclass, field
from lazurite.compiler.macro_define import MacroDefine

PRESETS_FILE = 'presets.toml'
DEFINE_PREFIX = 'TS_'


class PresetError(Exception):
    pass


@dataclass
class Preset:
    id: str
    name: str
    memory_tier: int
    params: dict
    defines: list[MacroDefine] = field(default_factory=list)


def _format_value(key: str, value) -> list[tuple[str, str]]:
    name = DEFINE_PREFIX + key.upper()
    if isinstance(value, bool):
        return [(name, '1' if value else '0')]
    if isinstance(value, int):
        return [(name, str(value))]
    if isinstance(value, float):
        # GLSL ES needs float literals with a decimal point
        return [(name, repr(value)), (name + '_ON', '1' if value != 0.0 else '0')]
    raise PresetError(f"'{key}': only bool, int and float values are supported")


def make_defines(params: dict) -> list[MacroDefine]:
    defines = []
    for key in sorted(params):
        for name, value in _format_value(key, params[key]):
            defines.append(MacroDefine(name, value))
    return defines


def load(path: str = PRESETS_FILE) -> tuple[dict, list[Preset]]:
    """Returns (pack config, presets). Every preset has its full parameter set."""
    with open(path, 'rb') as f:
        try:
            config = tomllib.load(f)
        except tomllib.TOMLDecodeError as e:
            raise PresetError(f"{path}: {e.args[0]}")

    for section in ['pack', 'defaults', 'preset']:
        if section not in config:
            raise PresetError(f"{path}: missing [{section}]")

    defaults: dict = config['defaults']
    presets = []
    ids = set()
    for p in config['preset']:
        pid = p.get('id', '')
        if not pid or not pid.replace('_', '').isalnum() or pid != pid.lower():
            raise PresetError(f"preset id '{pid}': use lowercase letters, digits and '_'")
        if pid in ids:
            raise PresetError(f"preset id '{pid}' is used twice")
        ids.add(pid)

        overrides = p.get('params', {})
        for key, value in overrides.items():
            if key not in defaults:
                raise PresetError(f"preset '{pid}': unknown parameter '{key}' (not in [defaults])")
            if type(value) is not type(defaults[key]):
                raise PresetError(
                    f"preset '{pid}': '{key}' must be {type(defaults[key]).__name__} like in [defaults]"
                )
        params = {**defaults, **overrides}
        preset = Preset(pid, p.get('name', pid), int(p.get('memory_tier', 0)), params)
        preset.defines = make_defines(params)
        presets.append(preset)

    if config['pack'].get('default_preset') not in ids:
        raise PresetError("[pack] default_preset must be one of the preset ids")

    # validate formatting of all defaults once
    make_defines(defaults)
    return config, presets


def find(presets: list[Preset], pid: str) -> Preset:
    for p in presets:
        if p.id == pid:
            return p
    raise PresetError(f"unknown preset '{pid}', available: {', '.join(p.id for p in presets)}")
