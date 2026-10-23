#!/usr/bin/env python3
"""Упаковка TechCore в .mcpack и .mcaddon с проверкой структуры архивов.

Запуск (из корня репозитория):  python3 TechCore/tools/package.py
Результат: TechCore/dist/TechCore_BP.mcpack, TechCore_RP.mcpack, TechCore.mcaddon
"""
import json
import os
import sys
import zipfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
DIST = os.path.join(ROOT, "dist")
PACKS = {"TechCore_BP": "behavior_pack", "TechCore_RP": "resource_pack"}
# Фиксированная дата делает архивы воспроизводимыми.
STAMP = (2026, 1, 1, 0, 0, 0)


def files_of(folder):
    base = os.path.join(ROOT, folder)
    for dirpath, _, names in os.walk(base):
        for n in sorted(names):
            full = os.path.join(dirpath, n)
            yield full, os.path.relpath(full, base).replace(os.sep, "/")


def add(zf, full, arc):
    info = zipfile.ZipInfo(arc, STAMP)
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = 0o644 << 16
    with open(full, "rb") as fh:
        zf.writestr(info, fh.read())


def check(path, prefixes):
    with zipfile.ZipFile(path) as zf:
        bad = zf.testzip()
        if bad:
            raise SystemExit(f"{path}: повреждён файл {bad}")
        names = set(zf.namelist())
        for p in prefixes:
            manifest = f"{p}manifest.json"
            if manifest not in names:
                raise SystemExit(f"{path}: нет {manifest}")
            json.loads(zf.read(manifest))
            if f"{p}pack_icon.png" not in names:
                raise SystemExit(f"{path}: нет {p}pack_icon.png")
        return len(names)


def main():
    os.makedirs(DIST, exist_ok=True)
    for name, folder in PACKS.items():
        out = os.path.join(DIST, f"{name}.mcpack")
        with zipfile.ZipFile(out, "w") as zf:
            for full, rel in files_of(folder):
                add(zf, full, rel)
        print(f"{out}: {check(out, [''])} файлов")
    out = os.path.join(DIST, "TechCore.mcaddon")
    with zipfile.ZipFile(out, "w") as zf:
        for name, folder in PACKS.items():
            for full, rel in files_of(folder):
                add(zf, full, f"{name}/{rel}")
    print(f"{out}: {check(out, [p + '/' for p in PACKS])} файлов, {os.path.getsize(out) // 1024} КБ")


if __name__ == "__main__":
    sys.exit(main())
