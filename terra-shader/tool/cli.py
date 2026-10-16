import argparse
import os
from rich.console import Console
from util import setup_needed

console = Console()
PROFILES = ['android', 'windows', 'ios', 'multiplatform']


def default_profiles():
    # Direct3D (windows) shaders can only be compiled on Windows
    return ['android', 'windows'] if os.name == 'nt' else ['android']


def ensure_setup():
    if setup_needed():
        import setup
        console.print("Toolchain missing or outdated, running setup...", style="yellow")
        setup.run(argparse.Namespace(reset=False))


def main():
    parser = argparse.ArgumentParser(
        prog='build',
        description="Terra Shader builder (Lazurite wrapper). Without a command: build all presets into .mcpack",
        epilog="Presets: presets.toml, shader options: src/newb/config.h"
    )
    subparsers = parser.add_subparsers(help='sub-command', dest='subcommand')

    pack_parser = subparsers.add_parser('pack', help="build the full pack with all presets (default)")
    mats_parser = subparsers.add_parser('mats', help="build materials of one preset (quick test)")
    setup_parser = subparsers.add_parser('setup', help="download shaderc and source materials")
    manifest_parser = subparsers.add_parser('manifest', help="write manifest.json from presets.toml")

    pack_parser.add_argument('-p', choices=PROFILES, nargs='+', default=default_profiles(),
                             help="build profiles (default: android, + windows on Windows)")
    pack_parser.add_argument('--no-zip', action='store_true', help="don't make .mcpack archive")
    pack_parser.add_argument('-v', default="", help="patch version number, eg: 3")

    mats_parser.add_argument('-p', choices=PROFILES, default=default_profiles()[-1], help="build profile")
    mats_parser.add_argument('-m', default=[], nargs='+', help="materials (eg: RenderChunk Sky), default: all")
    mats_parser.add_argument('-s', default="", help="preset id from presets.toml (eg: high), default: default_preset")

    setup_parser.add_argument('--reset', action='store_true', help="reset all data")

    manifest_parser.add_argument('-p', choices=PROFILES, default='multiplatform', help="profile for description text")
    manifest_parser.add_argument('-o', default='manifest.json', help="output file")

    args = parser.parse_args()

    if args.subcommand == 'setup':
        import setup
        setup.run(args)
    elif args.subcommand == 'manifest':
        import pack
        pack.run_manifest(args)
    elif args.subcommand == 'mats':
        ensure_setup()
        import build
        build.run(args)
    else:
        if args.subcommand is None:
            args = pack_parser.parse_args([])
        ensure_setup()
        import pack
        pack.run(args)
