import os
import shutil
import hashlib
from importlib import import_module, metadata
from rich.console import Console
from lazurite.compiler.macro_define import MacroDefine
import presets as presets_mod
from util import print_styled_error, get_materials_path, sync_common_files, MATERIALS_PATH, SHADERC_PATH

console = Console()
lp = import_module('lazurite.project.project')


class BuildError(Exception):
    pass


CACHE_PATH = os.path.join('build', 'cache')
_sources_digest = None
used_cache_files = set()


def prune_cache():
    # drop cached materials of old sources / removed presets
    if not os.path.isdir(CACHE_PATH):
        return
    for name in os.listdir(CACHE_PATH):
        if name not in used_cache_files:
            os.remove(os.path.join(CACHE_PATH, name))


def _digest_sources() -> str:
    # everything that can change a compiled material besides the defines
    global _sources_digest
    if _sources_digest is None:
        h = hashlib.sha256(metadata.version('lazurite').encode())
        for root in ['src', 'include', os.path.join('tool', 'data', 'materials')]:
            for dirpath, dirnames, filenames in os.walk(root):
                dirnames.sort()
                for name in sorted(filenames):
                    path = os.path.join(dirpath, name)
                    h.update(path.replace(os.sep, '/').encode())
                    with open(path, 'rb') as f:
                        h.update(f.read())
        _sources_digest = h.hexdigest()
    return _sources_digest


def compile_materials(
    profile: str, materials: list[str], defines: list[MacroDefine], output_path: str, log=None, cache=True
):
    """Compiles `materials` for `profile` with `defines` into output_path/*.material.bin.
    Results are cached in build/cache by (sources, profile, material, defines)."""
    try:
        get_materials_path(materials)
    except FileNotFoundError as e:
        raise BuildError(f"material '{e.args[0]}' does not exist in {MATERIALS_PATH}")

    os.makedirs(output_path, exist_ok=True)
    os.makedirs(CACHE_PATH, exist_ok=True)

    if log is not None:
        lp.print = log

    define_str = ';'.join(d.format_bgfx() for d in defines)
    for material in materials:
        key = hashlib.sha256(f"{_digest_sources()}|{profile}|{material}|{define_str}".encode()).hexdigest()[:32]
        cached = os.path.join(CACHE_PATH, f"{material}-{key}.material.bin")
        target = os.path.join(output_path, f"{material}.material.bin")
        used_cache_files.add(os.path.basename(cached))
        if cache and os.path.exists(cached):
            shutil.copyfile(cached, target)
            continue
        try:
            lp.compile(
                project_path=MATERIALS_PATH,
                profiles=[profile],
                output_folder=output_path,
                material_patterns=[os.path.join(MATERIALS_PATH, material)],
                shaderc_path=SHADERC_PATH,
                defines=defines,
            )
        except Exception as e:
            raise BuildError(e.args[0] if e.args else str(e))
        shutil.copyfile(target, cached)


def run(args):
    """`build mats`: compile some materials of one preset (for quick testing)"""
    try:
        config, presets = presets_mod.load()
        preset = presets_mod.find(presets, args.s or config['pack']['default_preset'])
    except presets_mod.PresetError as e:
        console.print(f"Error: {e}", style="bold red")
        exit(1)

    materials = args.m or config['pack']['materials']
    output_path = os.path.join('build', args.p, preset.id)
    if os.path.exists(output_path):
        shutil.rmtree(output_path)

    sync_common_files()
    console.print(f"[bold]Preset[/] {preset.id}: " + " ".join(d.format_bgfx() for d in preset.defines), style="dim")

    with console.status("[bold green]Building...") as status:
        def log(m):
            status.update(f"[bold green]Building {m}")
            console.print(f"  {m}", style="cyan")
        try:
            compile_materials(args.p, materials, preset.defines, output_path, log)
        except BuildError as e:
            print_styled_error(console, str(e))
            exit(1)

    console.print(f"Done: {output_path}", style="bold green")
