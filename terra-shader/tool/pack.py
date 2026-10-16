import os
import json
import shutil
import filecmp
from importlib import metadata
from rich.console import Console
import presets as presets_mod
from build import compile_materials, prune_cache, BuildError
from util import print_styled_error, sync_common_files

console = Console()

LOADER_NOTE = {
    'android': "Android: MB Loader only",
    'windows': "Windows: BetterRenderDragon / Wyvern only",
    'ios': "iOS: Minecraft with Hynis only",
    'multiplatform': "MB Loader (Android) / BetterRenderDragon, Wyvern (Windows)",
}


def create_manifest(pack: dict, presets: list, profile: str) -> dict:
    version = pack['version']
    version_str = '.'.join(str(v) for v in version)
    description = pack['description'].strip('\n')
    description = description.replace('%w', LOADER_NOTE[profile]).replace('%v', f"v{version_str}-{profile}")
    return {
        'format_version': 2,
        'header': {
            'name': pack['name'],
            'description': description,
            'uuid': pack['header_uuid'],
            'version': version,
            'min_engine_version': pack['min_engine_version'],
        },
        'modules': [
            {
                'type': 'resources',
                'uuid': pack['module_uuid'],
                'version': version,
            }
        ],
        'subpacks': [
            {'folder_name': p.id, 'name': p.name, 'memory_tier': p.memory_tier}
            for p in presets
        ],
        'metadata': {
            'authors': pack['authors'],
            'url': pack['url'],
            'license': pack.get('license', 'MIT'),
        },
    }


def write_manifest(path: str, manifest: dict):
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)
        f.write('\n')


def _build_profile(profile: str, config: dict, presets: list, zip_pack: bool):
    pack = config['pack']
    materials = pack['materials']
    default = presets_mod.find(presets, pack['default_preset'])
    version_str = '.'.join(str(v) for v in pack['version'])

    pack_dir = os.path.join('build', f'pack-{profile}')
    tmp_dir = os.path.join('build', f'tmp-{profile}')
    for d in [pack_dir, tmp_dir]:
        if os.path.exists(d):
            shutil.rmtree(d)
    shutil.copytree('assets', pack_dir)

    console.print(f"\n~ [bold]Profile[/] [cyan]{profile}[/]")

    # 1. compile every preset separately
    with console.status("") as status:
        for preset in presets:
            out = os.path.join(tmp_dir, preset.id)

            def log(m, pid=preset.id):
                status.update(f"[bold green]Building[/] [dim]\\[{pid}][/] {m}")

            try:
                compile_materials(profile, materials, preset.defines, out, log)
            except BuildError as e:
                status.stop()
                console.print(f"  [{preset.id}] [red]failed")
                print_styled_error(console, str(e))
                exit(1)
            console.print(f"  [dim]\\[{preset.id}][/] compiled [green]{len(materials)} materials")

    # 2. default preset goes to the pack root
    root_mats = os.path.join(pack_dir, 'renderer', 'materials')
    shutil.copytree(os.path.join(tmp_dir, default.id), root_mats)

    # 3. subpacks only keep materials that differ from the root
    total = 0
    for preset in presets:
        sub_mats = os.path.join(pack_dir, 'subpacks', preset.id, 'renderer', 'materials')
        os.makedirs(os.path.join(pack_dir, 'subpacks', preset.id), exist_ok=True)
        src = os.path.join(tmp_dir, preset.id)
        kept = []
        for name in sorted(os.listdir(src)):
            a = os.path.join(src, name)
            b = os.path.join(root_mats, name)
            if os.path.exists(b) and filecmp.cmp(a, b, shallow=False):
                continue
            os.makedirs(sub_mats, exist_ok=True)
            shutil.copyfile(a, os.path.join(sub_mats, name))
            kept.append(name.split('.')[0])
        total += len(kept)
        note = ', '.join(kept) if kept else 'same as root'
        console.print(f"  [dim]subpack[/] {preset.id}: [dim]{note}")

    shutil.rmtree(tmp_dir)

    # 4. manifest + texts
    write_manifest(os.path.join(pack_dir, 'manifest.json'), create_manifest(pack, presets, profile))
    authors = ', '.join(pack['authors'])
    with open(os.path.join(pack_dir, 'COPYRIGHT.txt'), 'w', encoding='utf-8') as f:
        f.write(config.get('info', {}).get('copyright', '').replace('%a', authors).lstrip('\n'))
    with open(os.path.join(pack_dir, 'PRESETS.txt'), 'w', encoding='utf-8') as f:
        for preset in presets:
            f.write(f"[{preset.id}] {preset.name}\n")
            f.write(' '.join(d.format_bgfx() for d in preset.defines) + '\n\n')

    if zip_pack:
        archive = os.path.join('build', f"terra-shader-{version_str}-{profile}.mcpack")
        if os.path.exists(archive):
            os.remove(archive)
        shutil.make_archive(pack_dir, 'zip', pack_dir)
        os.replace(pack_dir + '.zip', archive)
        console.print(f"  [bold green]=>[/] {archive}")
    else:
        console.print(f"  [bold green]=>[/] {pack_dir}")


def run(args):
    try:
        config, presets = presets_mod.load()
    except presets_mod.PresetError as e:
        console.print(f"Error: {e}", style="bold red")
        exit(1)

    if args.v:
        if args.v.isdigit():
            config['pack']['version'][2] = int(args.v)
        else:
            console.print(f"[yellow]Ignoring invalid version number '{args.v}'")

    pack = config['pack']
    console.print("  [bold green]Terra Shader pack builder[/]")
    console.print(f"  [dim]lazurite {metadata.version('lazurite')}, "
                  f"version {'.'.join(str(v) for v in pack['version'])}, "
                  f"presets: {', '.join(p.id for p in presets)} (root: {pack['default_preset']})")

    sync_common_files()
    for profile in args.p:
        _build_profile(profile, config, presets, not args.no_zip)
    if set(args.p) >= {'android', 'windows'} or os.name != 'nt':
        prune_cache()


def run_manifest(args):
    """`build manifest`: write manifest.json (for the repo / checking) without compiling"""
    try:
        config, presets = presets_mod.load()
    except presets_mod.PresetError as e:
        console.print(f"Error: {e}", style="bold red")
        exit(1)
    write_manifest(args.o, create_manifest(config['pack'], presets, args.p))
    console.print(f"Written {args.o}", style="bold green")
