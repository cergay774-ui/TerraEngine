#!/usr/bin/env python3
"""Build the installable archives.

dist/UltraClouds.mcaddon      - both packs, double-click to import
dist/UltraClouds_RP.mcpack    - resource pack only
dist/UltraClouds_BP.mcpack    - behavior pack only

Archives are deterministic (fixed timestamps, sorted entries).
"""
import os
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PACKS = os.path.join(ROOT, "packs")
DIST = os.path.join(ROOT, "dist")
STAMP = (2026, 10, 20, 12, 0, 0)


def files_of(pack_dir):
    out = []
    for base, dirs, files in os.walk(pack_dir):
        dirs.sort()
        for f in sorted(files):
            if f.startswith(".") or f.endswith((".map", ".tsbuildinfo")):
                continue
            out.append(os.path.join(base, f))
    return out


def add(zf, path, arcname):
    info = zipfile.ZipInfo(arcname.replace(os.sep, "/"), STAMP)
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = 0o644 << 16
    with open(path, "rb") as f:
        zf.writestr(info, f.read())


def build_pack(name):
    src = os.path.join(PACKS, name)
    out = os.path.join(DIST, f"{name}.mcpack")
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
        for path in files_of(src):
            add(zf, path, os.path.relpath(path, src))
    return out


def main():
    os.makedirs(DIST, exist_ok=True)
    built = [build_pack("UltraClouds_RP"), build_pack("UltraClouds_BP")]
    addon = os.path.join(DIST, "UltraClouds.mcaddon")
    with zipfile.ZipFile(addon, "w", zipfile.ZIP_DEFLATED) as zf:
        for name in ("UltraClouds_BP", "UltraClouds_RP"):
            src = os.path.join(PACKS, name)
            for path in files_of(src):
                add(zf, path, os.path.join(name, os.path.relpath(path, src)))
    built.append(addon)
    for p in built:
        with zipfile.ZipFile(p) as zf:
            bad = zf.testzip()
            assert bad is None, f"corrupt entry {bad} in {p}"
            n = len(zf.namelist())
        print(f"{os.path.relpath(p, ROOT)}: {os.path.getsize(p) / 1024:.0f} KiB, {n} files")


if __name__ == "__main__":
    main()
