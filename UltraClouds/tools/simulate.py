#!/usr/bin/env python3
"""Offline frame simulator for Ultra Clouds.

Executes the real Molang of the resource pack (pre_animation, animation
channels, render controller colours) with tools/molang.py, builds the bone
matrices with Bedrock's conventions and checks the result against an
independent ground-truth projection of the virtual cloud field:

  1. projection: every visible sprite lands where the true 3D cloud would be
     on screen, with the same size
  2. depth: the projected depth grows with the true distance of the cloud, so
     the depth buffer sorts clusters (checked pairwise); pieces of a cluster
     share its depth
  3. rig lag: the picture does not change when the rig lags behind the camera
     (both possible conventions of query.rotation_to_camera are tested; the
     self-calibrating sign must converge)
  4. motion: walking / flying across tile borders never makes a visible
     cloud jump; parallax matches the ground truth
  5. cost: Molang nodes evaluated per frame for every quality tier

It also renders preview images (docs/preview_*.png) with a software
rasteriser that mimics the GPU state of the two passes: a quantised depth
buffer (16 or 24 bit, LESS test), the alpha-tested core pass (discard,
opaque, depth write only for kept pixels), and the blended halo pass (no
discard, depth written for the whole quad), plus the actor shader colour
math (MatColor * texture, overlay lerp, light factor, light multiplier, fog).
Every frame is also rendered with an ideal far-to-near halo order; the
difference measures the artefacts the real draw order can cause (cut halos,
invisible rectangles).  Two alpha-test semantics are tested (texture alpha
times material alpha, and raw texture alpha).

Bedrock conventions used (derived in README "Coordinate conventions"):
  model (geometry/animation) units are 1/16 block, world = (x, y, -z) / 16
  bone rotation (rx, ry, rz) -> Rz(-rz) * Ry(ry) * Rx(-rx), right handed
  camera forward for pitch p / yaw y: (-sin y cos p, -sin p, cos y cos p)
"""
import json
import math
import os
import sys
import time

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import molang  # noqa: E402
import gen_pack as G  # noqa: E402

ROOT = G.ROOT
RP = G.RP
DOCS = os.path.join(ROOT, "docs")

WIDTH, HEIGHT, FOV_Y = 960, 540, 70.0


def rot_x(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def rot_y(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def rot_z(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def bone_rotation(rx, ry, rz):
    return rot_z(math.radians(-rz)) @ rot_y(math.radians(ry)) @ rot_x(math.radians(-rx))


W = np.diag([1.0, 1.0, -1.0])       # model -> world axis flip (yaw 0)


def forward(pitch, yaw):
    p, y = math.radians(pitch), math.radians(yaw)
    return np.array([-math.sin(y) * math.cos(p), -math.sin(p), math.cos(y) * math.cos(p)])


def mc_rotation_to(vec):
    """MC (pitch, yaw) whose forward vector points along vec."""
    x, y, z = vec
    h = math.hypot(x, z)
    yaw = math.degrees(math.atan2(-x, z))
    pitch = math.degrees(math.atan2(-y, h))
    return pitch, yaw


class Camera:
    def __init__(self, pos, pitch, yaw):
        self.pos = np.array(pos, float)
        self.pitch, self.yaw = pitch, yaw
        self.f = forward(pitch, yaw)
        up = np.array([0.0, 1.0, 0.0])
        self.r = np.cross(self.f, up)
        if np.linalg.norm(self.r) < 1e-6:
            self.r = np.array([1.0, 0.0, 0.0])
        self.r /= np.linalg.norm(self.r)
        self.u = np.cross(self.r, self.f)
        self.focal = (HEIGHT / 2) / math.tan(math.radians(FOV_Y / 2))

    def project(self, p):
        d = np.asarray(p) - self.pos
        z = d @ self.f
        if z <= 1e-6:
            return None
        return (WIDTH / 2 + (d @ self.r) / z * self.focal, HEIGHT / 2 - (d @ self.u) / z * self.focal, z)


# ---------------------------------------------------------------------------
# Pack loading
# ---------------------------------------------------------------------------

class Pack:
    def __init__(self):
        ent = json.load(open(os.path.join(RP, "entity", "ultra_clouds_sky.entity.json")))
        self.desc = ent["minecraft:client_entity"]["description"]
        geo = json.load(open(os.path.join(RP, "models", "entity", "ultra_clouds_sky.geo.json")))
        self.bones = geo["minecraft:geometry"][0]["bones"]
        self.bone_by_name = {b["name"]: b for b in self.bones}
        self.anims = json.load(open(os.path.join(RP, "animations", "ultra_clouds_sky.animation.json")))["animations"]
        self.rcs = json.load(open(os.path.join(RP, "render_controllers", "ultra_clouds_sky.render_controllers.json")))["render_controllers"]
        self.init = [molang.parse(e) for e in self.desc["scripts"].get("initialize", [])]
        self.pre = [molang.parse(e) for e in self.desc["scripts"]["pre_animation"]]
        self.animate = [(list(e.keys())[0], molang.parse(list(e.values())[0])) for e in self.desc["scripts"]["animate"]]
        self.channels = {}
        for short, full in self.desc["animations"].items():
            out = {}
            for bone, ch in self.anims[full]["bones"].items():
                out[bone] = {k: [molang.parse(v) for v in (vals if isinstance(vals, list) else [vals] * 3)]
                             for k, vals in ch.items()}
            self.channels[short] = out
        self.rc_order = [(list(e.keys())[0], molang.parse(list(e.values())[0])) for e in self.desc["render_controllers"]]
        self.rc_expr = {}
        for name, rc in self.rcs.items():
            tex = rc["textures"][0]
            mat = rc["materials"][0]["*"].split(".", 1)[1]
            self.rc_expr[name] = {
                "color": {k: molang.parse(v) for k, v in rc["color"].items()},
                "overlay": {k: molang.parse(v) for k, v in rc["overlay_color"].items()},
                "light": molang.parse(rc.get("light_color_multiplier", "1")),
                "vis": [(list(e.keys())[0], e[list(e.keys())[0]] if isinstance(list(e.values())[0], bool) else molang.parse(list(e.values())[0])) for e in rc["part_visibility"]],
                "tex": molang.parse(tex.split("[", 1)[1][:-1]) if "[" in tex else tex.split(".", 1)[1],
                "material": self.desc["materials"][mat],
            }
        self.atlas = {k: np.asarray(Image.open(os.path.join(RP, v + ".png")).convert("RGBA")).astype(np.float32) / 255.0
                      for k, v in self.desc["textures"].items()}


def default_props(**over):
    p = {f"{G.NS}:{n}": (1.0 if d is True else 0.0 if d is False else float(d)) for n, t, r, d in G.PROPS}
    p[f"{G.NS}:show"] = 1.0
    for k, v in over.items():
        p[f"{G.NS}:{k}"] = float(v)
    return p


class Sim:
    """One client: persistent entity variables across frames."""

    def __init__(self, pack, props, convention=1, graphics="fancy"):
        self.pack = pack
        self.props = props
        self.convention = convention       # +1: rotation_to_camera aims at camera, -1: opposite
        self.graphics = graphics
        self.env = molang.Env()
        self.env.strict = True          # record reads of never-set variables
        self.time_of_day = 0.5
        self.moon = 1.0
        for prog in pack.init:          # scripts.initialize: once, at creation
            self.env.run(prog)

    def queries(self, cam, rig_pos):
        d = cam.pos - rig_pos
        dist = float(np.linalg.norm(d))
        rtc = mc_rotation_to(d * self.convention)
        return {
            "q.property": lambda name: self.props.get(name, 0.0),
            "q.delta_time": self.dt,
            "q.camera_rotation": lambda axis: cam.pitch if axis == 0 else cam.yaw,
            "q.rotation_to_camera": lambda axis: rtc[0] if axis == 0 else rtc[1],
            "q.distance_from_camera": dist,
            "q.position": lambda axis: float(rig_pos[int(axis)]),
            "q.graphics_mode_is_any": lambda *modes: 1.0 if self.graphics in modes else 0.0,
            "q.time_of_day": self.time_of_day,
            "q.moon_brightness": self.moon,
            "q.body_y_rotation": 0.0,
        }

    def frame(self, cam, rig_pos, dt=1 / 60):
        self.dt = dt
        env = self.env
        env.queries = self.queries(cam, np.asarray(rig_pos, float))
        env.ops = 0
        for prog in self.pack.pre:
            env.run(prog)
        sprites = []
        playing = [name for name, cond in self.pack.animate if env.run(cond)]
        transforms = {}
        for name in playing:
            for bone, ch in self.pack.channels[name].items():
                vals = {k: [env.run(e) for e in v] for k, v in ch.items()}
                transforms[bone] = vals
        rcs = []
        for rc_name, cond in self.pack.rc_order:
            if not env.run(cond):
                continue
            rce = self.pack.rc_expr[rc_name]
            vis_rules = []
            for pat, c in rce["vis"]:
                v = c if isinstance(c, bool) else bool(env.run(c))
                vis_rules.append((pat, v))
            color = [env.run(rce["color"][k]) for k in "rgba"]
            overlay = [env.run(rce["overlay"][k]) for k in "rgba"]
            tex = rce["tex"] if isinstance(rce["tex"], str) else ["natural", "soft"][int(env.run(rce["tex"]))]
            light = env.run(rce["light"])
            rcs.append((rc_name, vis_rules, color, overlay, tex, rce["material"], light))
        self.last_ops = env.ops
        return transforms, rcs

    def var(self, name):
        return self.env.vars.get(name, 0.0)


def visible(vis_rules, bone):
    v = False
    for pat, val in vis_rules:
        if pat == "*" or (pat.endswith("*") and bone.startswith(pat[:-1])) or pat == bone:
            v = val
    return v


def bone_matrix(tr):
    """4x4 local transform of a bone (pivots are all at the origin)."""
    M = np.eye(4)
    if tr is None:
        return M
    pos = np.array(tr.get("position", [0, 0, 0]), float)
    R = bone_rotation(*tr.get("rotation", [0, 0, 0]))
    S = np.diag(tr.get("scale", [1, 1, 1]))
    M[:3, :3] = R @ S
    M[:3, 3] = pos
    return M


def quad_world(pack, bone, tr, rig_pos, transforms=None):
    """World-space corners of a sprite quad from its animated transform,
    composed with its parent chain (the root carries the camera offset)."""
    cube = pack.bone_by_name[bone]["cubes"][0]
    ox, oy, _ = cube["origin"]
    sx, sy, _ = cube["size"]
    corners = [np.array([ox, oy, 0.0, 1.0]), np.array([ox + sx, oy, 0.0, 1.0]),
               np.array([ox + sx, oy + sy, 0.0, 1.0]), np.array([ox, oy + sy, 0.0, 1.0])]
    M = bone_matrix(tr)
    parent = pack.bone_by_name[bone].get("parent")
    while parent:
        M = bone_matrix((transforms or {}).get(parent)) @ M
        parent = pack.bone_by_name[parent].get("parent")
    out = [np.asarray(rig_pos) + W @ (M @ c)[:3] / 16.0 for c in corners]
    normal = W @ (M[:3, :3] @ np.array([0.0, 0.0, 1.0]))
    return out, normal


# ---------------------------------------------------------------------------
# Ground truth (independent re-implementation of the cloud field)
# ---------------------------------------------------------------------------

def ground_truth(sim, clusters, cam, sprite_names):
    """True world centre + true height of each sprite (no projection)."""
    v = sim.var
    out = {}
    for cl in clusters:
        L = cl.layer
        if L == "ov":
            y = v("v.alt_st") - cam.pos[1]
            for sp in cl.sprites:
                if sp.name not in sprite_names:
                    continue
                hd = y / math.tan(math.radians(sp.el))
                a = math.radians(sp.az + v("v.ov_phi"))
                centre = cam.pos + np.array([hd * math.sin(a), y, hd * math.cos(a)])
                q = min(1.0, max(0.3, 1.6 * math.sin(math.radians(sp.el))))
                h = min(y * sp.height * v("v.ov_vis") * q, 1.8 * abs(y) / max(math.cos(math.radians(cam.pitch)), 0.05))
                out[sp.name] = (centre, h)
            continue
        P = G.LAYERS[L]["P"]
        wx, wz = v(f"v.w{L}x"), v(f"v.w{L}z")
        dx = (cl.bx + wx - cam.pos[0])
        dx -= P * math.floor(dx / P + 0.5)
        dz = (cl.bz + wz - cam.pos[2])
        dz -= P * math.floor(dz / P + 0.5)
        alt = v(f"v.alt_{L}") + cl.yoff
        g = v(f"{cl.var}_g")
        for sp in cl.sprites:
            if sp.name not in sprite_names:
                continue
            centre = cam.pos + np.array([dx + g * sp.ox, alt - cam.pos[1] + g * sp.oy, dz + g * sp.oz])
            h = g * sp.height * (v("v.stormf") if "tower" in sp.flags else 1.0)
            if "base" in sp.flags:
                h *= v(f"{cl.var}_e")
            if L != "cu":
                d = math.sqrt(dx * dx + dz * dz + (alt - cam.pos[1]) ** 2)
                se = abs(alt - cam.pos[1]) / d
                fade = min(1.0, max(0.0, (se - 0.05) * 12))
                h = min(h * fade * min(1.0, max(0.3, 1.6 * se)),
                        1.8 * abs(alt - cam.pos[1]) / max(math.cos(math.radians(cam.pitch)), 0.05))
            out[sp.name] = (centre, h)
    return out


def draw_order(pack, rcs):
    order = []
    for rc_name, vis_rules, color, overlay, tex, material, light in rcs:
        for b in pack.bones[1:]:
            if visible(vis_rules, b["name"]):
                order.append((b["name"], rc_name, color, overlay, tex, material, light))
    return order


def true_distance(sim, clusters_by_name, cam, bone):
    """True camera distance of the cluster (or ceiling sprite) of a bone."""
    v = sim.var
    sp = clusters_by_name[bone]
    if "ceiling" in sp.flags:
        sv = f"v.s{bone}"
        return math.sqrt(v(sv + "_vx") ** 2 + v(sv + "_vy") ** 2 + v(sv + "_vz") ** 2)
    return v(f"{sp.cluster.var}_m") / 0.12


# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

def check_frame(pack, sim, clusters, cam, rig_pos, transforms, rcs, report, tag):
    order = draw_order(pack, rcs)
    names = {o[0] for o in order}
    truth = ground_truth(sim, clusters, cam, names)
    by_name = {sp.name: sp for cl in clusters for sp in cl.sprites}
    max_err = 0.0
    max_size_err = 0.0
    seen = {}
    done = set()
    ceiling = []
    n_vis = 0
    zmin, zfar = sim.var("v.zmin"), sim.var("v.zfar")
    for bone, rc_name, *_ in order:
        tr = transforms.get(bone)
        if tr is None or tr["scale"][0] <= 1e-6 or bone in done:
            continue
        done.add(bone)
        corners, normal = quad_world(pack, bone, tr, rig_pos, transforms)
        centre = sum(corners) / 4
        pc = cam.project(centre)
        if pc is None:
            report["behind"] += 1
            continue
        n_vis += 1
        tc, th = truth[bone]
        pt = cam.project(tc)
        if pt is None:
            report["truth_behind"] += 1
            continue
        if abs(pt[0] - WIDTH / 2) < WIDTH and abs(pt[1] - HEIGHT / 2) < HEIGHT:   # near the screen
            err = math.hypot(pc[0] - pt[0], pc[1] - pt[1])
            max_err = max(max_err, err)
            top = cam.project(centre + (corners[3] - corners[0]) / 2)
            size_render = math.hypot(top[0] - pc[0], top[1] - pc[1]) * 2
            size_truth = th * cam.focal / pt[2]
            if size_truth > 2:
                max_size_err = max(max_size_err, abs(size_render - size_truth) / size_truth)
        # sprite must face the camera (plane parallel to the view plane)
        n = normal / np.linalg.norm(normal)
        report["max_facing_err"] = max(report["max_facing_err"], 1 - abs(n @ cam.f))
        # winding: for an unrotated model these corners give +z while the
        # south face's outside is world -z, so the face is front facing when
        # the camera is on the -geo_n side (matters if a material culls)
        geo_n = np.cross(corners[1] - corners[0], corners[3] - corners[0])
        if geo_n @ (cam.pos - centre) > 0:
            report["back_facing"] += 1
        # compare clusters by their shared depth (pieces carry a tiny bias,
        # ceiling sprites a slot step)
        sp = by_name[bone]
        if "ceiling" in sp.flags:
            # the deck is the lowest layer: at or in front of its true depth
            true_z = zmin * math.exp(-math.log(G.ZMIN_FRAC) * min(1, max(0, math.log(
                max(true_distance(sim, by_name, cam, bone), 80) / 80) / math.log(50))))
            if pc[2] > true_z * 1.001:
                report["ceiling_behind_true_depth"] += 1
            ceiling.append((sp.bias, pc[2]))
            continue
        z_cluster = pc[2] / (1 - G.PIECE_BIAS * sp.bias)
        seen[bone] = (true_distance(sim, by_name, cam, bone), z_cluster, sp)
        if not (zmin * 0.97 <= pc[2] <= zfar * (G.CI_BAND[1] + 0.001 if sp.layer == "ci" else 1.001)):
            report["depth_out_of_range"] += 1
    ceiling.sort()
    report["ceiling_slot_order"] += sum(1 for a, b in zip(ceiling, ceiling[1:]) if b[1] >= a[1])
    # cirrus: fixed slots behind every other cloud, decreasing in draw order
    ci = [(z, sp) for d, z, sp in seen.values() if sp.layer == "ci"]
    other = [z for d, z, sp in seen.values() if sp.layer != "ci"]
    if ci and other and min(z for z, sp in ci) <= max(other):
        report["cirrus_not_behind"] += 1
    ci_order = [z for b in [o[0] for o in order] for z, sp in ci if sp.name == b]
    report["cirrus_slot_order"] += sum(1 for a, b in zip(ci_order, ci_order[1:]) if b >= a)
    # depth must grow with the true distance (clusters 5% apart or more)
    items = [v for v in seen.values() if v[2].layer != "ci"]
    bad = 0
    for i in range(len(items)):
        di, zi, si = items[i]
        for j in range(len(items)):
            dj, zj, sj = items[j]
            if dj > di * 1.05 and zj <= zi:
                bad += 1
    report["depth_order_violations"] += bad
    report["max_screen_err_px"] = max(report["max_screen_err_px"], max_err)
    report["max_size_err"] = max(report["max_size_err"], max_size_err)
    report["visible"] = max(report["visible"], n_vis)
    return order



def screen_positions(pack, cam, rig_pos, transforms, rcs):
    out = {}
    for bone, *_ in draw_order(pack, rcs):
        tr = transforms.get(bone)
        if tr is None or tr["scale"][0] <= 1e-6:
            continue
        corners, _ = quad_world(pack, bone, tr, rig_pos, transforms)
        p = cam.project(sum(corners) / 4)
        top = cam.project((corners[2] + corners[3]) / 2)
        if p and top:
            out[bone] = (p[0], p[1], abs(top[1] - p[1]) * 2)
    return out


# ---------------------------------------------------------------------------
# Preview renderer (mimics the vanilla actor shader)
# ---------------------------------------------------------------------------

def sky_colors(tod, rain):
    """Rough vanilla-like sky gradient for previews (zenith, horizon)."""
    e = -math.cos(tod * 2 * math.pi)
    day = min(1, max(0, (e + 0.1) / 0.35))
    zen = np.array([0.03, 0.04, 0.09]) * (1 - day) + np.array([0.33, 0.55, 0.95]) * day
    hor = np.array([0.05, 0.06, 0.12]) * (1 - day) + np.array([0.68, 0.81, 1.0]) * day
    glow = math.exp(-((e - 0.0) / 0.18) ** 2)
    hor = hor * (1 - glow * 0.7) + np.array([1.0, 0.55, 0.32]) * glow * 0.7
    zen = zen * (1 - glow * 0.3) + np.array([0.35, 0.3, 0.5]) * glow * 0.3
    grey = np.array([0.45, 0.47, 0.5]) * (0.3 + 0.7 * day)
    return zen * (1 - rain * 0.8) + grey * rain * 0.8, hor * (1 - rain * 0.8) + grey * rain * 0.8


class Raster:
    """Software model of the two GPU passes.

    depth_bits: 16 or 24 (unorm, perspective depth with the near plane below)
    alpha_mode: "mat" - alpha test on texture alpha * material alpha,
                "raw" - alpha test on texture alpha only
    halo_order: "pack" - the real draw order, "ideal" - far to near
    """
    NEAR = 0.05

    def __init__(self, depth_bits=16, alpha_mode="mat", halo_order="pack"):
        self.depth_bits, self.alpha_mode, self.halo_order = depth_bits, alpha_mode, halo_order

    def quantise(self, z):
        d = 1.0 - self.NEAR / max(z, self.NEAR)
        return math.floor(d * (2 ** self.depth_bits - 1) + 0.5)


def sky_image(cam, sim, tod, rain, ground):
    zen, hor = sky_colors(tod, rain)
    img = np.zeros((HEIGHT, WIDTH, 3))
    for y in range(HEIGHT):
        ray = cam.f * cam.focal + cam.u * (HEIGHT / 2 - y)
        el = ray[1] / np.linalg.norm(ray)
        t = min(1, max(0, el)) ** 0.6
        img[y, :] = hor * (1 - t) + zen * t
        if ground and el < 0:
            img[y, :] = np.array([0.22, 0.32, 0.18]) * (0.35 + 0.65 * sim.var("v.day_lo")) * 0.9 + hor * 0.1
    return img, hor


def quad_pixels(pack, cam, bone, tr, rig_pos, transforms, atlas):
    """Screen rectangle, point-sampled texture and view depth of a sprite."""
    corners, _ = quad_world(pack, bone, tr, rig_pos, transforms)
    pts = [cam.project(c) for c in corners]
    if any(p is None for p in pts):
        return None
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    x0f, x1f, y0f, y1f = min(xs), max(xs), min(ys), max(ys)
    x0, x1 = max(0, int(math.ceil(x0f - 0.5))), min(WIDTH, int(math.ceil(x1f - 0.5)))
    y0, y1 = max(0, int(math.ceil(y0f - 0.5))), min(HEIGHT, int(math.ceil(y1f - 0.5)))
    if x1 <= x0 or y1 <= y0 or x1f - x0f > 20000:
        return None
    cube = pack.bone_by_name[bone]["cubes"][0]
    u0, v0 = cube["uv"]["south"]["uv"]
    n = atlas.shape[0] // 4
    cell = atlas[v0 * n // 256:(v0 + 256) * n // 256, u0 * n // 256:(u0 + 256) * n // 256]
    # pixel centres -> texel (point sampling, like the entity textures)
    fx = (np.arange(x0, x1) + 0.5 - x0f) / (x1f - x0f)
    fy = (np.arange(y0, y1) + 0.5 - y0f) / (y1f - y0f)
    if pts[0][0] > pts[1][0]:
        fx = 1 - fx
    if pts[0][1] < pts[3][1]:
        fy = 1 - fy
    tx = np.clip((fx * n).astype(int), 0, n - 1)
    ty = np.clip((fy * n).astype(int), 0, n - 1)
    tex = cell[ty[:, None], tx[None, :]]
    return (x0, x1, y0, y1), tex, pts[0][2]


def compose(pack, sim, cam, rig_pos, transforms, rcs, tod, rain=0.0, render_distance=8,
            ground=True, raster=None):
    """Renders one frame; returns the image (HxWx3, linear 0..1)."""
    raster = raster or Raster()
    img, fog_col = sky_image(cam, sim, tod, rain, ground)
    depth = np.full((HEIGHT, WIDTH), 2 ** 62, dtype=np.int64)
    rd = render_distance * 16.0
    fog_start, fog_end = (0.92, 1.0) if rain < 0.5 else (0.23 + 0.69 * (1 - rain), 0.7 + 0.3 * (1 - rain))
    lf = sim.var("v.lf")
    draws = []
    for seq, (bone, rc_name, color, overlay, tex, material, light) in enumerate(draw_order(pack, rcs)):
        tr = transforms.get(bone)
        if tr is None or tr["scale"][0] <= 1e-6:
            continue
        q = quad_pixels(pack, cam, bone, tr, rig_pos, transforms, pack.atlas[tex])
        if q is None:
            continue
        draws.append((seq, material, q, color, overlay, light))
    cores = [d for d in draws if d[1] == "entity_alphatest"]
    halos = [d for d in draws if d[1] != "entity_alphatest"]
    if raster.halo_order == "ideal":
        halos.sort(key=lambda d: (-d[2][2], d[0]))
    for seq, material, ((x0, x1, y0, y1), tex, z), color, overlay, light in cores + halos:
        rgb = tex[..., :3] * np.array(color[:3])
        rgb = rgb * (1 - overlay[3]) + np.array(overlay[:3]) * overlay[3]
        rgb = np.clip(rgb * (lf + 0.35 * overlay[3]) * light, 0, 1)
        fog = min(1, max(0, (z / rd - fog_start) / (fog_end - fog_start)))
        rgb = rgb * (1 - fog) + fog_col * fog
        zq = raster.quantise(z)
        dbuf = depth[y0:y1, x0:x1]
        passed = zq < dbuf
        if material == "entity_alphatest":
            a = tex[..., 3] * (color[3] if raster.alpha_mode == "mat" else 1.0)
            keep = passed & (a >= 0.5)
            img[y0:y1, x0:x1][keep] = rgb[keep]
            dbuf[keep] = zq
        else:
            a = np.clip(tex[..., 3] * color[3], 0, 1)[..., None]
            blended = img[y0:y1, x0:x1] * (1 - a) + rgb * a
            img[y0:y1, x0:x1][passed] = blended[passed]
            dbuf[passed] = zq
    return img


def save_image(img, path):
    Image.fromarray((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").save(path)


def artefacts(pack, sim, cam, rig_pos, transforms, rcs, tod, rain=0.0, ground=True):
    """Differences between the real draw order and an ideal far-to-near halo
    order, for both depth precisions and both alpha-test semantics."""
    out = {}
    worst = None
    for bits in (16, 24):
        for mode in ("mat", "raw"):
            real = compose(pack, sim, cam, rig_pos, transforms, rcs, tod, rain, ground=ground,
                           raster=Raster(bits, mode, "pack"))
            ideal = compose(pack, sim, cam, rig_pos, transforms, rcs, tod, rain, ground=ground,
                            raster=Raster(bits, mode, "ideal"))
            diff = np.abs(real - ideal).max(-1)
            key = f"d{bits}_{mode}"
            out[key] = {"max": round(float(diff.max()), 3),
                        "px_over_0.04": int((diff > 0.04).sum()),
                        "px_over_0.10": int((diff > 0.10).sum())}
            if worst is None or out[key]["px_over_0.04"] > worst[0]:
                worst = (out[key]["px_over_0.04"], key, real, ideal, diff)
    return out, worst


# ---------------------------------------------------------------------------

def run_checks(pack, clusters):
    report = {"depth_order_violations": 0, "depth_out_of_range": 0, "back_facing": 0,
              "cirrus_not_behind": 0, "cirrus_slot_order": 0, "ceiling_behind_true_depth": 0,
              "ceiling_slot_order": 0,
              "max_screen_err_px": 0.0, "max_size_err": 0.0, "behind": 0,
              "truth_behind": 0, "max_facing_err": 0.0, "visible": 0}
    results = {}
    props = default_props(tier=3, detail=3, cu=0.6, st=0.3, ac=0.45, ci=0.6, autoq=0)
    sim = Sim(pack, props)
    base = np.array([1203.0, 72.0, -845.0])
    # warm up smoothing
    cam = Camera(base + [0, 1.62, 0], -20, 30)
    for i in range(240):
        sim.frame(cam, base - [0, 16, 0], dt=1 / 20)
    # 1. static views in many directions, rig directly under the player
    for pitch in (-85, -60, -35, -10, 0, 20):
        for yaw in range(0, 360, 45):
            cam = Camera(base + [0, 1.62, 0], pitch, yaw)
            tr, rcs = sim.frame(cam, base - [0, 16, 0])
            check_frame(pack, sim, clusters, cam, base - [0, 16, 0], tr, rcs, report, "static")
    results["static"] = dict(report)
    # 2. above the cloud deck (mountain / flight)
    high = base + [0, 300, 0]
    for pitch in (-30, 10, 45, 80):
        for yaw in (0, 120, 240):
            cam = Camera(high, pitch, yaw)
            tr, rcs = sim.frame(cam, high - [0, 17.62, 0])
            check_frame(pack, sim, clusters, cam, high - [0, 17.62, 0], tr, rcs, report, "above")
    results["above_clouds"] = {"above": sim.var("v.above"), **report}
    # 3. rig lag invariance, both rotation_to_camera conventions
    lag_report = {}
    for conv in (1, -1):
        s2 = Sim(pack, props, convention=conv)
        cam = Camera(base + [0, 1.62, 0], -25, 70)
        for i in range(240):
            s2.frame(cam, base - [0, 16, 0], dt=1 / 20)
        # walk forward with the rig lagging two ticks behind, to let the sign vote
        pos = base.copy()
        speed = np.array([0.25, 0.0, 0.1])       # blocks per tick
        rig = pos - [0, 16, 0]
        for t in range(400):
            pos = pos + speed / 3                 # 60 fps
            if t % 3 == 0:
                rig = pos - speed * 2 - [0, 16, 0]
            cam = Camera(pos + [0, 1.62, 0], -25, 70)
            s2.frame(cam, rig)
        vote = s2.var("v.vote")
        # compare screen positions: lagging rig vs. rig exactly below the camera
        cam = Camera(pos + [0, 1.62, 0], -25, 70)
        tr_a, rc_a = s2.frame(cam, rig, dt=1e-6)
        sa = screen_positions(pack, cam, rig, tr_a, rc_a)
        exact = pos - [0, 16, 0]
        tr_b, rc_b = s2.frame(cam, exact, dt=1e-6)
        sb = screen_positions(pack, cam, exact, tr_b, rc_b)
        common = set(sa) & set(sb)
        diff = max((math.hypot(sa[k][0] - sb[k][0], sa[k][1] - sb[k][1]) for k in common), default=0)
        lag_report[f"convention_{'aim_at_camera' if conv == 1 else 'opposite'}"] = {
            "vote": round(vote, 3), "max_shift_px": round(diff, 3), "sprites": len(common)}
    results["rig_lag"] = lag_report
    # 4. motion: fly 3000 blocks diagonally (crosses every wrap border)
    s3 = Sim(pack, props)
    pos = base.copy() + [0, 40, 0]
    cam = Camera(pos, -30, 45)
    for i in range(120):
        s3.frame(cam, pos - [0, 17.62, 0], dt=1 / 20)
    prev = None
    max_jump = 0.0
    step = np.array([-1.5, 0.0, 1.5])      # elytra speed per frame
    jumps = 0
    for i in range(1400):
        pos = pos + step
        cam = Camera(pos, -30, 45)
        tr, rcs = s3.frame(cam, pos - [0, 17.62, 0])
        cur = screen_positions(pack, cam, pos - [0, 17.62, 0], tr, rcs)
        if prev:
            for k in set(cur) & set(prev):
                if cur[k][2] < 3 or prev[k][2] < 3:
                    continue      # sprites smaller than 3 px (fading at the field edge)
                if not (0 <= cur[k][0] <= WIDTH and 0 <= cur[k][1] <= HEIGHT):
                    continue
                d = math.hypot(cur[k][0] - prev[k][0], cur[k][1] - prev[k][1])
                if d > max_jump:
                    max_jump = d
                if d > 40:
                    jumps += 1
        prev = cur
    results["motion"] = {"frames": 1400, "distance_blocks": round(1400 * float(np.linalg.norm(step))),
                         "max_frame_to_frame_px": round(max_jump, 2), "jumps_over_40px": jumps}
    # 5. Molang cost per tier (nodes evaluated per frame)
    cost = {}
    for name, tier, detail, lq in (("Performance", 0, 0, 0), ("Balanced", 1, 1, 1), ("High", 2, 2, 2), ("Ultra", 3, 3, 2)):
        s4 = Sim(pack, default_props(tier=tier, detail=detail, lightq=lq, cu=0.5, st=0.2, ac=0.3, ci=0.4, autoq=0))
        cam = Camera(base + [0, 1.62, 0], -30, 10)
        for i in range(3):
            tr, rcs = s4.frame(cam, base - [0, 16, 0])
        cost[name] = {"molang_nodes_per_frame": s4.last_ops, "animated_bones": len(tr),
                      "draw_calls_estimate": sum(math.ceil(sum(1 for b in pack.bones[1:] if visible(r[1], b["name"])) / 8) for r in rcs)}
    results["cost"] = cost
    # 6. reads of entity variables that were never set (a content error that
    #    stops the expression in Bedrock): many settings, weather and views
    undefined = set()
    for over in (dict(tier=0, detail=0, cu=0.3, st=0.0, ac=0.0, ci=0.2),
                 dict(tier=1, detail=1, cu=0.55, st=0.08, ac=0.3, ci=0.4),
                 dict(tier=3, detail=3, cu=1.0, st=0.95, ac=0.8, ci=0.9, rain=1, thunder=1, storm=1),
                 dict(tier=2, detail=2, cu=0.6, st=0.4, ac=0.4, ci=0.5, soft=0)):
        s5 = Sim(pack, default_props(autoq=1, **over))
        for i, (pitch, yaw, y) in enumerate([(-20, 30, 72), (-80, 200, 72), (10, 90, 330), (-35, 300, 72)] * 4):
            cam = Camera(base + [0, y - 72 + 1.62, 0], pitch, yaw)
            s5.frame(cam, base + [0, y - 72 - 16, 0], dt=1 / 20)
        undefined |= s5.env.undefined
    for s_ in (sim, s3):
        undefined |= s_.env.undefined
    results["undefined_variable_reads"] = sorted(undefined)
    return results


PREVIEW_SHOTS = [
    ("noon_realistic", 0.5, dict(cu=0.55, st=0.08, ac=0.3, ci=0.4), 0.0, (-24, 20)),
    ("afternoon_cumulus", 0.6, dict(cu=0.7, st=0.0, ac=0.06, ci=0.1, size=1.25), 0.0, (-18, 200)),
    ("sunset_realistic", 0.735, dict(cu=0.55, st=0.08, ac=0.3, ci=0.45, warm=0.8, atmo=0.85), 0.0, (-14, 90)),
    ("dusk_cirrus", 0.765, dict(cu=0.08, st=0.0, ac=0.2, ci=0.9, warm=0.85, atmo=0.9), 0.0, (-20, 90)),
    ("night_moon", 0.02, dict(cu=0.55, st=0.05, ac=0.3, ci=0.4), 0.0, (-30, 0)),
    ("overcast", 0.45, dict(cu=0.35, st=0.95, ac=0.3, ci=0.0, storm=0.15), 0.0, (-20, 300)),
    ("storm", 0.55, dict(cu=0.72, st=0.8, ac=0.15, ci=0.1, storm=1, rain=1, thunder=1), 1.0, (-12, 150)),
    ("fantasy", 0.7, dict(cu=0.5, st=0.0, ac=0.45, ci=0.55, fantasy=1, soft=2, size=1.35, warm=0.8), 0.0, (-22, 60)),
    ("minimal", 0.42, dict(cu=0.3, st=0.0, ac=0.0, ci=0.22, tier=0, detail=0, lightq=0), 0.0, (-25, 0)),
    ("crisp_dense", 0.55, dict(cu=1.0, st=0.3, ac=0.6, ci=0.6, soft=0), 0.0, (-35, 240)),
    ("zenith_dense", 0.5, dict(cu=1.0, st=0.4, ac=0.8, ci=0.9), 0.0, (-80, 30)),
    ("above_clouds", 0.66, dict(cu=0.65, st=0.4, ac=0.3, ci=0.4), 0.0, (16, 120)),
]


def settle(pack, props, tod, pos, pitch, yaw, frames=160):
    sim = Sim(pack, props)
    sim.time_of_day = tod
    cam = Camera(pos + [0, 1.62, 0], pitch, yaw)
    for i in range(frames):
        tr, rcs = sim.frame(cam, pos - [0, 16, 0], dt=1 / 20)
    return sim, cam, tr, rcs


def previews(pack, clusters, only=None):
    """Preview images (16-bit depth, real draw order) + artefact statistics."""
    os.makedirs(DOCS, exist_ok=True)
    base = np.array([512.0, 70.0, 300.0])
    stats = {}
    for name, tod, over, rain, (pitch, yaw) in PREVIEW_SHOTS:
        if only and name not in only:
            continue
        props = default_props(**{**dict(tier=3, detail=3, lightq=2, autoq=0), **over})
        y = 70.0 if name != "above_clouds" else 330.0
        pos = base + [0, y - base[1], 0]
        sim, cam, tr, rcs = settle(pack, props, tod, pos, pitch, yaw)
        ground = name != "above_clouds"
        img = compose(pack, sim, cam, pos - [0, 16, 0], tr, rcs, tod, rain, ground=ground,
                      raster=Raster(16, "mat", "pack"))
        path = os.path.join(DOCS, f"preview_{name}.png")
        save_image(img, path)
        stats[name], worst = artefacts(pack, sim, cam, pos - [0, 16, 0], tr, rcs, tod, rain, ground)
        if "--diff" in sys.argv and worst and worst[0]:
            save_image(np.concatenate([worst[2], worst[3], np.repeat(worst[4][..., None] * 4, 3, -1)], 0),
                       os.path.join(DOCS, f"artefacts_{name}.png"))
        print("  rendered", os.path.relpath(path, ROOT), json.dumps(stats[name]))
    return stats


def robustness(pack, n=16, seed=5):
    """Random views and random settings: real vs ideal halo order."""
    rng = np.random.default_rng(seed)
    worst = {"px_over_0.04": 0, "px_over_0.10": 0, "max": 0.0}
    rows = []
    for i in range(n):
        over = dict(tier=3, detail=int(rng.integers(1, 4)), lightq=2, autoq=0,
                    cu=float(rng.uniform(0.2, 1.0)), st=float(rng.uniform(0.0, 0.7)),
                    ac=float(rng.uniform(0.0, 0.9)), ci=float(rng.uniform(0.0, 1.0)),
                    size=float(rng.uniform(0.6, 2.0)), soft=int(rng.integers(0, 3)),
                    height=int(rng.integers(140, 320)))
        pos = np.array([rng.uniform(-5000, 5000), rng.uniform(64, 120), rng.uniform(-5000, 5000)])
        pitch, yaw = float(rng.uniform(-88, 5)), float(rng.uniform(0, 360))
        sim, cam, tr, rcs = settle(pack, default_props(**over), float(rng.uniform(0.3, 0.7)), pos, pitch, yaw, 40)
        st, _ = artefacts(pack, sim, cam, pos - [0, 16, 0], tr, rcs, 0.5)
        rows.append({"view": i, "pitch": round(pitch), **{k: v["px_over_0.04"] for k, v in st.items()}})
        for v in st.values():
            for k in worst:
                worst[k] = max(worst[k], v[k])
    return {"views": n, "worst": worst, "per_view_px_over_0.04": rows}


def main():
    t0 = time.time()
    pack = Pack()
    clusters = G.build_field()
    G.order_sprites(clusters)          # assigns the same names as the pack
    results = run_checks(pack, clusters)
    ok = True
    st = results["static"]
    ab = results["above_clouds"]
    for key in ("depth_order_violations", "depth_out_of_range", "back_facing", "cirrus_not_behind",
                "cirrus_slot_order", "ceiling_behind_true_depth", "ceiling_slot_order"):
        if st[key] or ab[key]:
            print(f"FAIL: {key}"); ok = False
    if st["max_screen_err_px"] > 1.0 or ab["max_screen_err_px"] > 1.0:
        print("FAIL: projection error"); ok = False
    if st["max_size_err"] > 0.02:
        print("FAIL: projected size error"); ok = False
    if st["max_facing_err"] > 1e-6:
        print("FAIL: sprites not parallel to the view plane"); ok = False
    for k, r in results["rig_lag"].items():
        if r["max_shift_px"] > 0.5:
            print(f"FAIL: rig lag visible with {k}"); ok = False
    if results["motion"]["jumps_over_40px"]:
        print("FAIL: clouds jump while moving"); ok = False
    if results["undefined_variable_reads"]:
        print(f"FAIL: {len(results['undefined_variable_reads'])} variables read before being set, e.g. "
              f"{results['undefined_variable_reads'][:5]}"); ok = False
    if "--no-preview" not in sys.argv:
        results["previews_artefacts"] = previews(pack, clusters)
    if "--no-robust" not in sys.argv:
        results["robustness"] = robustness(pack)
    print(json.dumps({k: v for k, v in results.items() if k != "robustness"}, indent=1))
    if "robustness" in results:
        print("robustness worst:", results["robustness"]["worst"])
    with open(os.path.join(DOCS, "simulation_results.json"), "w") as f:
        json.dump(results, f, indent=2)
    print(f"{'PASS' if ok else 'FAIL'} ({time.time() - t0:.0f}s)")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
