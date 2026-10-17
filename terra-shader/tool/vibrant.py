import os
import copy
import json
import shutil
import tomllib
from urllib.request import urlopen
from rich.console import Console
from pack import write_manifest

"""
Terra Vibrant: resource pack for Vibrant Visuals (no shaders, no loader).
Builds build/terra-vibrant-<version>.mcpack from vibrant/vibrant.toml + vibrant/pack/.
"""

console = Console()

VIBRANT_DIR = 'vibrant'
CONFIG_FILE = os.path.join(VIBRANT_DIR, 'vibrant.toml')
STATIC_DIR = os.path.join(VIBRANT_DIR, 'pack')
BIOME_LIST = os.path.join(VIBRANT_DIR, 'biomes.txt')
SAMPLES_RAW = "https://raw.githubusercontent.com/Mojang/bedrock-samples/{tag}/resource_pack/biomes/{name}.client_biome.json"
SAMPLES_API = "https://api.github.com/repos/Mojang/bedrock-samples/contents/resource_pack/biomes?ref={tag}"

# client_biome component name and field for each settable identifier
COMPONENTS = {
    'lighting': ('minecraft:lighting_identifier', 'lighting_identifier'),
    'atmosphere': ('minecraft:atmosphere_identifier', 'atmosphere_identifier'),
    'color_grading': ('minecraft:color_grading_identifier', 'color_grading_identifier'),
    'water': ('minecraft:water_identifier', 'water_identifier'),
    'fog': ('minecraft:fog_appearance', 'fog_identifier'),
}

# documented value ranges (WaterCustomization.md)
WATER_RANGES = {
    'particle_concentrations': {'cdom': (0.0, 15.0), 'chlorophyll': (0.0, 10.0), 'suspended_sediment': (0.0, 300.0)},
    'waves': {
        'depth': (0.0, 3.0), 'direction_increment': (0.0, 360.0), 'frequency': (0.01, 3.0),
        'frequency_scaling': (0.0, 2.0), 'mix': (0.0, 1.0), 'octaves': (1, 30), 'pull': (-1.0, 1.0),
        'sampleWidth': (0.01, 1.0), 'shape': (1.0, 10.0), 'speed': (0.01, 10.0), 'speed_scaling': (0.0, 2.0),
    },
    'caustics': {'frame_length': (0.01, 5.0), 'power': (1, 6), 'scale': (0.1, 5.0)},
}


# documented ranges (ColorGradingToneMappingCustomization.md, LightingCustomization.md)
GRADING_RANGES = {'contrast': (0.0, 4.0), 'gain': (0.0, 10.0), 'gamma': (0.0, 4.0), 'offset': (-1.0, 1.0),
                  'saturation': (0.0, 10.0), 'shadowsMax': (0.1, 1.0), 'highlightsMin': (1.0, 4.0)}
TONE_MAPPERS = {'reinhard', 'reinhard_luma', 'reinhard_luminance', 'hable', 'aces', 'generic'}


class VibrantError(Exception):
    pass


def _in_range(where, value, rng):
    values = value if isinstance(value, list) else [value]
    for v in values:
        if not (rng[0] <= v <= rng[1]):
            raise VibrantError(f"{where} = {value} is outside {rng[0]}..{rng[1]}")


def validate_static(pack_dir: str):
    """Checks color grading and lighting values against the documented ranges"""
    operators = set()
    for root, _, files in os.walk(pack_dir):
        for f in files:
            if not f.endswith('.json'):
                continue
            path = os.path.join(root, f)
            data = _load_json(path)
            cg = data.get('minecraft:color_grading_settings')
            if cg:
                for part in ['midtones', 'highlights', 'shadows']:
                    for k, v in cg.get('color_grading', {}).get(part, {}).items():
                        if k in GRADING_RANGES:
                            _in_range(f"{f}: {part}.{k}", v, GRADING_RANGES[k])
                temp = cg.get('color_grading', {}).get('temperature', {})
                if 'temperature' in temp:
                    _in_range(f"{f}: temperature", temp['temperature'], (1000.0, 15000.0))
                op = cg.get('tone_mapping', {}).get('operator')
                if op is not None:
                    if op not in TONE_MAPPERS:
                        raise VibrantError(f"{f}: unknown tone mapping operator '{op}'")
                    operators.add(op)
            ls = data.get('minecraft:lighting_settings')
            if ls:
                sky = ls.get('sky', {}).get('intensity')
                for v in (sky.values() if isinstance(sky, dict) else [sky] if sky is not None else []):
                    _in_range(f"{f}: sky.intensity", v, (0.1, 1.0))
                amb = ls.get('ambient', {}).get('illuminance')
                for v in (amb.values() if isinstance(amb, dict) else [amb] if amb is not None else []):
                    _in_range(f"{f}: ambient.illuminance", v, (0.0, 5.0))
    if len(operators) > 1:
        raise VibrantError(f"all color grading files must use one tone mapping operator, found {sorted(operators)}")


def _load_json(path):
    try:
        import pyjson5  # comments are allowed in Minecraft JSON
        with open(path, encoding='utf-8') as f:
            return pyjson5.load(f)
    except ImportError:
        with open(path, encoding='utf-8') as f:
            return json.load(f)


def _dump(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write('\n')


def _biome_names(tag: str) -> list[str]:
    # listing needs the GitHub API; fall back to the committed list
    try:
        with urlopen(SAMPLES_API.format(tag=tag), timeout=20) as r:
            entries = json.load(r)
        names = sorted(e['name'][:-len('.client_biome.json')] for e in entries
                       if e['name'].endswith('.client_biome.json'))
        if names:
            with open(BIOME_LIST, 'w') as f:
                f.write('\n'.join(names) + '\n')
            return names
    except Exception:
        pass
    with open(BIOME_LIST) as f:
        return [ln.strip() for ln in f if ln.strip()]


def fetch_vanilla_biomes(tag: str) -> str:
    """Downloads vanilla client_biome files once into tool/data/vanilla/<tag>/biomes"""
    cache = os.path.join('tool', 'data', 'vanilla', tag, 'biomes')
    done = os.path.join(cache, '.complete')
    if os.path.exists(done):
        return cache
    os.makedirs(cache, exist_ok=True)
    names = _biome_names(tag)
    with console.status(f"Downloading vanilla biomes ({tag})...") as status:
        for i, name in enumerate(names):
            status.update(f"Downloading vanilla biomes ({tag}) {i + 1}/{len(names)}")
            path = os.path.join(cache, f"{name}.client_biome.json")
            if os.path.exists(path):
                continue
            with urlopen(SAMPLES_RAW.format(tag=tag, name=name), timeout=30) as r:
                data = r.read()
            with open(path, 'wb') as f:
                f.write(data)
    open(done, 'w').close()
    return cache


def _check_ranges(where: str, section: str, values: dict):
    for key, value in values.items():
        rng = WATER_RANGES.get(section, {}).get(key)
        if rng and not (rng[0] <= value <= rng[1]):
            raise VibrantError(f"{where}: {section}.{key} = {value} is outside {rng[0]}..{rng[1]}")


def make_water(config: dict, preset: dict) -> dict[str, dict]:
    """water/<body>.json files for one preset"""
    base = config['water']['base']
    files = {}
    for body, settings in config['water']['body'].items():
        s = {'description': {'identifier': f"terra:{body}"}}
        merged = copy.deepcopy(base)
        for k, v in settings.items():
            merged[k] = v
        waves = {**merged.get('waves', {}), **preset.get('waves', {})}
        if not waves.get('enabled', False):
            waves = {'enabled': False}
        merged['waves'] = waves
        for section in ['particle_concentrations', 'waves', 'caustics']:
            if section in merged:
                _check_ranges(f"water {body} ({preset['id']})", section, merged[section])
                s[section] = merged[section]
        if 'biome_water_color_contribution' in merged:
            s['biome_water_color_contribution'] = merged['biome_water_color_contribution']
        files[f"terra_{body}.json"] = {'format_version': '1.26.0', 'minecraft:water_settings': s}
    return files


def make_biomes(config: dict, vanilla_dir: str) -> dict[str, dict]:
    """Vanilla client_biome files with our identifiers; only changed biomes are returned"""
    replace: dict = config['biomes'].get('replace', {})
    per_biome: dict = config['biomes'].get('set', {})
    available = {f[:-len('.client_biome.json')] for f in os.listdir(vanilla_dir) if f.endswith('.client_biome.json')}
    for name in per_biome:
        if name not in available:
            raise VibrantError(f"[biomes.set.{name}]: no such vanilla biome in {vanilla_dir}")

    out = {}
    for name in sorted(available):
        data = _load_json(os.path.join(vanilla_dir, f"{name}.client_biome.json"))
        components = data.get('minecraft:client_biome', {}).get('components', {})
        changed = False
        for comp_name, field in COMPONENTS.values():
            comp = components.get(comp_name)
            if isinstance(comp, dict) and comp.get(field) in replace:
                comp[field] = replace[comp[field]]
                changed = True
        for key, ident in per_biome.get(name, {}).items():
            if key not in COMPONENTS:
                raise VibrantError(f"[biomes.set.{name}]: unknown key '{key}', use one of {', '.join(COMPONENTS)}")
            comp_name, field = COMPONENTS[key]
            components.setdefault(comp_name, {})[field] = ident
            changed = True
        if changed:
            out[f"{name}.client_biome.json"] = data
    return out


def _defined_identifiers(pack_dir: str) -> set[str]:
    ids = set()
    for root, _, files in os.walk(pack_dir):
        for f in files:
            if not f.endswith('.json') or root.endswith('biomes'):
                continue
            try:
                data = _load_json(os.path.join(root, f))
            except Exception:
                continue
            for v in data.values():
                if isinstance(v, dict) and isinstance(v.get('description'), dict):
                    ids.add(v['description'].get('identifier'))
    return ids


def build(zip_pack: bool = True, version_patch: str = ""):
    with open(CONFIG_FILE, 'rb') as f:
        try:
            config = tomllib.load(f)
        except tomllib.TOMLDecodeError as e:
            raise VibrantError(f"{CONFIG_FILE}: {e.args[0]}")

    pack = config['pack']
    if version_patch.isdigit():
        pack['version'][2] = int(version_patch)
    version_str = '.'.join(str(v) for v in pack['version'])
    presets = config['preset']
    ids = [p['id'] for p in presets]
    if pack['default_preset'] not in ids:
        raise VibrantError("[pack] default_preset must be one of the preset ids")

    console.print(f"\n~ [bold]Terra Vibrant[/] [dim]{version_str}, vanilla biomes {pack['samples_tag']}")
    pack_dir = os.path.join('build', 'pack-vibrant')
    if os.path.exists(pack_dir):
        shutil.rmtree(pack_dir)
    shutil.copytree(STATIC_DIR, pack_dir)
    shutil.copyfile(os.path.join('assets', 'pack_icon.png'), os.path.join(pack_dir, 'pack_icon.png'))
    validate_static(pack_dir)

    # water: root = default preset, subpacks = only their water files
    default = next(p for p in presets if p['id'] == pack['default_preset'])
    for name, data in make_water(config, default).items():
        _dump(os.path.join(pack_dir, 'water', name), data)
    for p in presets:
        sub = os.path.join(pack_dir, 'subpacks', p['id'])
        os.makedirs(sub, exist_ok=True)
        if p is not default:
            for name, data in make_water(config, p).items():
                _dump(os.path.join(sub, 'water', name), data)

    # biomes
    vanilla = fetch_vanilla_biomes(pack['samples_tag'])
    biomes = make_biomes(config, vanilla)
    for name, data in biomes.items():
        _dump(os.path.join(pack_dir, 'biomes', name), data)
    console.print(f"  biomes: [green]{len(biomes)}[/] vanilla client_biome files rewritten")

    # every terra:* identifier used by biomes must be defined in the pack
    defined = _defined_identifiers(pack_dir)
    used = set(config['biomes'].get('replace', {}).values())
    for settings in config['biomes'].get('set', {}).values():
        used |= {v for k, v in settings.items() if k != 'fog'}
    missing = sorted(i for i in used if i.startswith('terra:') and i not in defined)
    if missing:
        raise VibrantError(f"identifiers used by biomes but not defined in vibrant/pack: {', '.join(missing)}")

    manifest = {
        'format_version': 2,
        'header': {
            'name': pack['name'],
            'description': pack['description'].strip('\n').replace('%v', f"v{version_str}"),
            'uuid': pack['header_uuid'],
            'version': pack['version'],
            'min_engine_version': pack['min_engine_version'],
        },
        'modules': [{'type': 'resources', 'uuid': pack['module_uuid'], 'version': pack['version']}],
        'subpacks': [{'folder_name': p['id'], 'name': p['name'], 'memory_tier': 0} for p in presets],
        'capabilities': ['pbr'],
        'metadata': {'authors': pack['authors'], 'url': pack['url'], 'license': pack.get('license', 'MIT')},
    }
    write_manifest(os.path.join(pack_dir, 'manifest.json'), manifest)

    if zip_pack:
        archive = os.path.join('build', f"terra-vibrant-{version_str}.mcpack")
        if os.path.exists(archive):
            os.remove(archive)
        shutil.make_archive(pack_dir, 'zip', pack_dir)
        os.replace(pack_dir + '.zip', archive)
        console.print(f"  [bold green]=>[/] {archive}")
    else:
        console.print(f"  [bold green]=>[/] {pack_dir}")


def run(args):
    try:
        build(not args.no_zip, args.v)
    except VibrantError as e:
        console.print(f"Error: {e}", style="bold red")
        exit(1)
