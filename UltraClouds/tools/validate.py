#!/usr/bin/env python3
"""Static validation of the Ultra Clouds packs (no game required).

Checks:
  * every JSON file parses; manifests are consistent (UUIDs, dependencies,
    script module versions, sub-pack folders)
  * every Molang expression (pre_animation, animation channels, render
    controller fields and conditions) parses with tools/molang.py
  * only queries / math functions from the official 1.26.50 Molang list are
    used, with valid argument counts
  * every variable that is read is also written somewhere (or protected by ??)
  * temp.* variables are never read in a different expression than the one
    that writes them
  * bones referenced by animations exist; every part_visibility pattern
    matches bones; render controllers / animations / textures referenced by
    the client entity exist
  * q.property names exist in the behavior pack entity, client_sync is on,
    and the property count limit (32) is respected
  * translation keys used by the scripts exist in every language file
"""
import glob
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import molang  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RP = os.path.join(ROOT, "packs", "UltraClouds_RP")
BP = os.path.join(ROOT, "packs", "UltraClouds_BP")
SIG = json.load(open(os.path.join(ROOT, "tools", "data", "molang_signatures.json")))

errors = []
warnings = []
stats = {"expressions": 0, "json_files": 0}


def err(msg):
    errors.append(msg)


def load(path):
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        stats["json_files"] += 1
        return data
    except Exception as e:
        err(f"JSON error in {os.path.relpath(path, ROOT)}: {e}")
        return None


def check_json_files():
    for base in (RP, BP):
        for path in glob.glob(os.path.join(base, "**", "*.json"), recursive=True):
            load(path)


# ----------------------------------------------------------------------------
# Molang
# ----------------------------------------------------------------------------
written_vars = set()
read_vars = []      # (name, guarded, where)
used_props = set()


def analyse(expr, where, allow_temps_from=None):
    stats["expressions"] += 1
    try:
        ast = molang.parse(expr)
    except molang.MolangError as e:
        err(f"Molang parse error in {where}: {e}")
        return None
    temps_written = set()
    temps_read = []

    def visit(node, guarded=False):
        k = node[0]
        if k == "assign":
            name = molang.normalize_name(node[1])
            if name.startswith("v."):
                written_vars.add(name)
            elif name.startswith("t."):
                temps_written.add(name)
            visit(node[2])
            return
        if k == "var":
            name = molang.normalize_name(node[1])
            if name.startswith("v."):
                read_vars.append((name, guarded, where))
            elif name.startswith("t."):
                temps_read.append(name)
            elif name.startswith("q."):
                check_query(name, 0, where)
            elif name != "math.pi":
                err(f"unknown identifier {name} in {where}")
            return
        if k == "bin" and node[1] == "??":
            visit(node[2], guarded=True)
            visit(node[3])
            return
        if k == "call":
            name = molang.normalize_name(node[1])
            if name.startswith("q."):
                check_query(name, len(node[2]), where)
                if name == "q.property" and node[2] and node[2][0][0] == "str":
                    used_props.add(node[2][0][1])
            else:
                full = name
                if full not in SIG["math"]:
                    err(f"unknown math function {full} in {where}")
                else:
                    lo, hi = SIG["math"][full]
                    if not (lo <= len(node[2]) <= hi):
                        err(f"{full} takes {lo}-{hi} args, got {len(node[2])} in {where}")
                if full not in molang.MATH:
                    warnings.append(f"interpreter lacks {full}")
            for a in node[2]:
                visit(a)
            return
        for child in node[1:]:
            if isinstance(child, tuple):
                visit(child, guarded)
            elif isinstance(child, list):
                for c in child:
                    if isinstance(c, tuple):
                        visit(c, guarded)

    visit(ast)
    for t in temps_read:
        if t not in temps_written:
            err(f"temp variable {t} read but not written in the same expression ({where})")
    return ast


def check_query(name, nargs, where):
    full = "query." + name[2:]
    if full not in SIG["queries"]:
        err(f"unknown query {full} in {where}")
        return
    lo, hi = SIG["queries"][full]
    if not (lo <= nargs <= hi):
        err(f"{full} takes {lo}-{hi} args, got {nargs} in {where}")


def is_molang(v):
    return isinstance(v, str) or isinstance(v, (int, float))


def check_rp():
    ent = load(os.path.join(RP, "entity", "ultra_clouds_sky.entity.json"))
    geo = load(os.path.join(RP, "models", "entity", "ultra_clouds_sky.geo.json"))
    anims = load(os.path.join(RP, "animations", "ultra_clouds_sky.animation.json"))
    rcs = load(os.path.join(RP, "render_controllers", "ultra_clouds_sky.render_controllers.json"))
    if not all((ent, geo, anims, rcs)):
        return None
    desc = ent["minecraft:client_entity"]["description"]
    geo_desc = geo["minecraft:geometry"][0]["description"]
    bones = {b["name"] for b in geo["minecraft:geometry"][0]["bones"]}
    if desc["geometry"]["default"] != geo_desc["identifier"]:
        err("client entity geometry identifier mismatch")
    for key, path in desc["textures"].items():
        if not os.path.exists(os.path.join(RP, path + ".png")):
            err(f"texture {path} missing")
    # parents exist and precede children (draw order relies on list order)
    seen = set()
    for b in geo["minecraft:geometry"][0]["bones"]:
        if "parent" in b and b["parent"] not in seen:
            err(f"bone {b['name']} parent {b['parent']} missing/after child")
        seen.add(b["name"])
    # scripts
    scripts = desc["scripts"]
    for i, e in enumerate(scripts.get("pre_animation", [])):
        analyse(e, f"pre_animation[{i}]")
    for entry in scripts.get("animate", []):
        for name, cond in entry.items():
            if name not in desc["animations"]:
                err(f"animate references unknown animation {name}")
            analyse(cond, f"animate condition {name}")
    for short, full in desc["animations"].items():
        if full not in anims["animations"]:
            err(f"animation {full} not defined")
    # animations
    for aname, a in anims["animations"].items():
        for bone, ch in a.get("bones", {}).items():
            if bone not in bones:
                err(f"animation {aname} targets missing bone {bone}")
            for cname, vals in ch.items():
                for i, v in enumerate(vals if isinstance(vals, list) else [vals]):
                    if is_molang(v):
                        analyse(v, f"{aname}/{bone}/{cname}[{i}]")
    # render controllers
    for entry in desc["render_controllers"]:
        for name, cond in entry.items():
            if name not in rcs["render_controllers"]:
                err(f"client entity references unknown render controller {name}")
            analyse(cond, f"render controller condition {name}")
    for name, rc in rcs["render_controllers"].items():
        for field in ("color", "overlay_color"):
            for ch, v in rc.get(field, {}).items():
                analyse(v, f"{name}/{field}.{ch}")
        for entry in rc.get("part_visibility", []):
            for pat, cond in entry.items():
                if not isinstance(cond, bool):
                    analyse(cond, f"{name}/part_visibility {pat}")
                regex = re.compile("^" + re.escape(pat).replace(r"\*", ".*") + "$")
                if not any(regex.match(b) for b in bones):
                    err(f"{name}: part_visibility pattern {pat} matches no bone")
        for t in rc.get("textures", []):
            m = re.match(r"Array\.(\w+)\[(.*)\]$", t)
            if m:
                analyse(m.group(2), f"{name}/textures index")
                arr = rc["arrays"]["textures"].get("Array." + m.group(1))
                if not arr:
                    err(f"{name}: texture array {m.group(1)} missing")
                for tex in arr or []:
                    if tex.split(".", 1)[1] not in desc["textures"]:
                        err(f"{name}: {tex} not declared in the client entity")
    # UV inside texture
    tw, th = geo_desc["texture_width"], geo_desc["texture_height"]
    for b in geo["minecraft:geometry"][0]["bones"]:
        for c in b.get("cubes", []):
            for face, uv in c["uv"].items():
                u, v = uv["uv"]
                w, h = uv["uv_size"]
                if not (0 <= u and u + w <= tw and 0 <= v and v + h <= th):
                    err(f"bone {b['name']} UV outside texture")
    return desc


def check_variables():
    # a read is fine if it is written somewhere in the entity scripts or is
    # null-coalesced (??) - Molang returns 0.0 for missing variables anyway,
    # but an unwritten variable almost always means a typo.
    for name, guarded, where in read_vars:
        if name not in written_vars and not guarded:
            err(f"variable {name} is read in {where} but never written")


def check_bp(rp_desc):
    ent = load(os.path.join(BP, "entities", "ultra_clouds_sky.json"))
    if not ent:
        return
    desc = ent["minecraft:entity"]["description"]
    props = desc.get("properties", {})
    if len(props) > 32:
        err(f"{len(props)} entity properties (limit 32)")
    for name, p in props.items():
        if not p.get("client_sync"):
            err(f"property {name} is not client_sync")
        if p["type"] in ("int", "float"):
            lo, hi = p["range"]
            if not (lo <= p["default"] <= hi):
                err(f"property {name} default outside range")
    for name in used_props:
        if name not in props:
            err(f"q.property('{name}') has no definition in the behavior pack")
    if rp_desc and rp_desc["identifier"] != desc["identifier"]:
        err("RP/BP entity identifier mismatch")
    item = load(os.path.join(BP, "items", "cloud_settings.json"))
    tex = load(os.path.join(RP, "textures", "item_texture.json"))
    if item and tex:
        icon = item["minecraft:item"]["components"]["minecraft:icon"]
        if icon not in tex["texture_data"]:
            err(f"item icon {icon} missing from item_texture.json")
        for k, v in tex["texture_data"].items():
            if not os.path.exists(os.path.join(RP, v["textures"] + ".png")):
                err(f"item texture {v['textures']} missing")


def check_manifests():
    rp = load(os.path.join(RP, "manifest.json"))
    bp = load(os.path.join(BP, "manifest.json"))
    if not rp or not bp:
        return
    uuids = [rp["header"]["uuid"], bp["header"]["uuid"]] + [m["uuid"] for m in rp["modules"] + bp["modules"]]
    if len(set(uuids)) != len(uuids):
        err("duplicate UUIDs in manifests")
    deps = {d.get("uuid") for d in bp["dependencies"]}
    if rp["header"]["uuid"] not in deps:
        err("behavior pack does not depend on the resource pack")
    if bp["header"]["uuid"] not in {d.get("uuid") for d in rp.get("dependencies", [])}:
        err("resource pack does not depend on the behavior pack")
    for sp in rp.get("subpacks", []):
        if not os.path.isdir(os.path.join(RP, "subpacks", sp["folder_name"])):
            err(f"sub-pack folder {sp['folder_name']} missing")
    script = [m for m in bp["modules"] if m["type"] == "script"]
    if not script or not os.path.exists(os.path.join(BP, script[0]["entry"])):
        err("script entry file missing")
    mods = {d.get("module_name"): d.get("version") for d in bp["dependencies"] if "module_name" in d}
    for name in ("@minecraft/server", "@minecraft/server-ui"):
        pkg = os.path.join(ROOT, "node_modules", *name.split("/"), "package.json")
        if os.path.exists(pkg):
            ver = json.load(open(pkg))["version"]
            if ver != mods.get(name):
                err(f"manifest uses {name} {mods.get(name)} but scripts were type-checked against {ver}")
    # subpacks that hide the vanilla clouds must contain a fully transparent map
    try:
        from PIL import Image
        for sp in ("standard", "lite"):
            im = Image.open(os.path.join(RP, "subpacks", sp, "textures", "environment", "clouds.png")).convert("RGBA")
            if im.getextrema()[3][1] != 0:
                err(f"{sp}/clouds.png is not fully transparent")
    except Exception as e:
        err(f"cannot check clouds.png: {e}")


def check_lang():
    keys_used = set()
    for path in glob.glob(os.path.join(ROOT, "src", "scripts", "*.ts")):
        src = open(path, encoding="utf-8").read()
        keys_used |= set(re.findall(r'"(uc\.[a-z0-9_.]+)"', src))
        # template keys: `${c.text}.d`, `uc.profile.${...}` ...
    for path in glob.glob(os.path.join(ROOT, "src", "scripts", "*.ts")):
        src = open(path, encoding="utf-8").read()
        for m in re.findall(r'text: "(uc\.[a-z0-9_.]+)"', src):
            keys_used.add(m + ".d")
    keys_used |= {f"uc.profile.{p}" for p in ("performance", "balanced", "high", "ultra", "cinematic", "custom")}
    keys_used |= {f"uc.type.{t}" for t in ("realistic", "cumulus", "cirrus", "overcast", "storm", "fantasy", "minimal", "dynamic")}
    keys_used |= {f"uc.q.{i}" for i in range(4)}
    for lang in ("en_US", "ru_RU"):
        path = os.path.join(RP, "texts", f"{lang}.lang")
        have = set()
        for line in open(path, encoding="utf-8"):
            if "=" in line:
                have.add(line.split("=", 1)[0].strip())
        for k in sorted(keys_used):
            if k not in have:
                err(f"{lang}.lang is missing {k}")


def main():
    check_json_files()
    desc = check_rp()
    check_variables()
    check_bp(desc)
    check_manifests()
    check_lang()
    print(f"validated {stats['json_files']} JSON files, {stats['expressions']} Molang expressions, "
          f"{len(written_vars)} entity variables, {len(used_props)} properties")
    for w in sorted(set(warnings)):
        print("warning:", w)
    if errors:
        for e in errors[:200]:
            print("ERROR:", e)
        print(f"{len(errors)} error(s)")
        return 1
    print("OK - no errors")
    return 0


if __name__ == "__main__":
    sys.exit(main())
