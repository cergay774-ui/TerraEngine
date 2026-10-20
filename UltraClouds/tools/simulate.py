#!/usr/bin/env python3
"""Offline frame simulator for Ultra Clouds.

Executes the real Molang of the resource pack (pre_animation, animation
channels, render controller colours) with tools/molang.py, builds the bone
matrices with Bedrock's conventions and checks the result against an
independent ground-truth projection of the virtual cloud field:

  1. projection: every visible sprite lands where the true 3D cloud would be
     on screen, with the same size
  2. draw order: view depth strictly decreases along the draw order (painter's
     algorithm works whether or not the material writes depth)
  3. rig lag: the picture does not change when the rig lags behind the camera
     (both possible conventions of query.rotation_to_camera are tested; the
     self-calibrating sign must converge)
  4. motion: walking / flying across tile borders never makes a visible
     cloud jump; parallax matches the ground truth
  5. cost: Molang nodes evaluated per frame for every quality tier

It also renders preview images (docs/preview_*.png) with a software
compositor that mimics the actor shader (MatColor * texture, overlay lerp,
light factor, fog).

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
        self.pre = [molang.parse(e) for e in self.desc["scripts"]["pre_animation"]]
        self.animate = [(list(e.keys())[0], molang.parse(list(e.values())[0])) for e in self.desc["scripts"]["animate"]]
        self.channels = {}
        for short, full in self.desc["animations"].items():
            out = {}
            for bone, ch in self.anims[full]["bones"].items():
                out[bone] = {k: [molang.parse(v) for v in vals] for k, vals in ch.items()}
            self.channels[short] = out
        self.rc_order = [(list(e.keys())[0], molang.parse(list(e.values())[0])) for e in self.desc["render_controllers"]]
        self.rc_expr = {}
        for name, rc in self.rcs.items():
            self.rc_expr[name] = {
                "color": {k: molang.parse(v) for k, v in rc["color"].items()},
                "overlay": {k: molang.parse(v) for k, v in rc["overlay_color"].items()},
                "vis": [(list(e.keys())[0], e[list(e.keys())[0]] if isinstance(list(e.values())[0], bool) else molang.parse(list(e.values())[0])) for e in rc["part_visibility"]],
                "tex": molang.parse(rc["textures"][0].split("[", 1)[1][:-1]),
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
        self.time_of_day = 0.5
        self.moon = 1.0

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
            tex = ["natural", "soft"][int(env.run(rce["tex"]))]
            rcs.append((rc_name, vis_rules, color, overlay, tex))
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
                q = min(1.0, max(0.06, 1.6 * math.sin(math.radians(sp.el))))
                h = min(y * sp.height * v("v.ov_vis") * q, 1.8 * abs(y))
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
                h = min(h * min(1.0, max(0.06, 1.6 * abs(alt - cam.pos[1]) / d)), 1.8 * abs(alt - cam.pos[1]))
            out[sp.name] = (centre, h)
    return out


def draw_order(pack, rcs):
    order = []
    for rc_name, vis_rules, color, overlay, tex in rcs:
        for b in pack.bones[1:]:
            if visible(vis_rules, b["name"]):
                order.append((b["name"], rc_name, color, overlay, tex))
    return order


# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

def check_frame(pack, sim, clusters, cam, rig_pos, transforms, rcs, report, tag):
    order = draw_order(pack, rcs)
    names = {o[0] for o in order}
    truth = ground_truth(sim, clusters, cam, names)
    max_err = 0.0
    max_size_err = 0.0
    depths = []
    n_vis = 0
    for bone, rc_name, *_ in order:
        tr = transforms.get(bone)
        if tr is None or tr["scale"][0] <= 1e-6:
            continue
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
        depths.append(pc[2])
    viol = sum(1 for a, b in zip(depths, depths[1:]) if b >= a - 1e-6)
    report["order_violations"] += viol
    report["max_screen_err_px"] = max(report["max_screen_err_px"], max_err)
    report["max_size_err"] = max(report["max_size_err"], max_size_err)
    report["visible"] = max(report["visible"], n_vis)
    report["depth_range"] = (min(depths), max(depths)) if depths else (0, 0)
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


def render(pack, sim, cam, rig_pos, transforms, rcs, path, tod, rain=0.0, render_distance=8, ground=True):
    zen, hor = sky_colors(tod, rain)
    ys = np.arange(HEIGHT)[:, None]
    img = np.zeros((HEIGHT, WIDTH, 3))
    # sky by view elevation
    for y in range(HEIGHT):
        ray = cam.f * cam.focal + cam.u * (HEIGHT / 2 - y)
        el = ray[1] / np.linalg.norm(ray)
        t = min(1, max(0, el)) ** 0.6
        img[y, :] = hor * (1 - t) + zen * t
        if ground and el < 0:
            img[y, :] = np.array([0.22, 0.32, 0.18]) * (0.35 + 0.65 * sim.var("v.day_lo")) * 0.9 + hor * 0.1
    fog_col = hor
    rd = render_distance * 16.0
    fog_start, fog_end = (0.92, 1.0) if rain < 0.5 else (0.23 + 0.69 * (1 - rain), 0.7 + 0.3 * (1 - rain))
    for bone, rc_name, color, overlay, tex in draw_order(pack, rcs):
        tr = transforms.get(bone)
        if tr is None or tr["scale"][0] <= 1e-6:
            continue
        corners, _ = quad_world(pack, bone, tr, rig_pos, transforms)
        pts = [cam.project(c) for c in corners]
        if any(p is None for p in pts):
            continue
        xs = [p[0] for p in pts]
        ysq = [p[1] for p in pts]
        x0, x1, y0, y1 = int(min(xs)), int(max(xs)), int(min(ysq)), int(max(ysq))
        if x1 < 0 or y1 < 0 or x0 >= WIDTH or y0 >= HEIGHT or x1 - x0 < 1 or y1 - y0 < 1:
            continue
        cube = pack.bone_by_name[bone]["cubes"][0]
        u, v = cube["uv"]["south"]["uv"]
        cell = pack.atlas[tex][v:v + 256, u:u + 256]
        w, h = x1 - x0, y1 - y0
        if w > 4000 or h > 4000:
            continue
        cell_img = Image.fromarray((cell * 255).astype(np.uint8), "RGBA").resize((w, h), Image.BILINEAR)
        c = np.asarray(cell_img).astype(np.float32) / 255.0
        # quad orientation: our image row 0 is the top of the cell
        if pts[0][1] < pts[3][1]:
            c = c[::-1]
        if pts[0][0] > pts[1][0]:
            c = c[:, ::-1]
        cx0, cy0 = max(0, x0), max(0, y0)
        cx1, cy1 = min(WIDTH, x1), min(HEIGHT, y1)
        sub = c[cy0 - y0:cy1 - y0, cx0 - x0:cx1 - x0]
        rgb = sub[..., :3] * np.array(color[:3])
        rgb = rgb * (1 - overlay[3]) + np.array(overlay[:3]) * overlay[3]
        light = sim.var("v.lf") + 0.35 * overlay[3]
        rgb = rgb * light
        depth = pts[0][2]
        fog = min(1, max(0, (depth / rd - fog_start) / (fog_end - fog_start)))
        rgb = rgb * (1 - fog) + fog_col * fog
        a = sub[..., 3:4] * color[3]
        img[cy0:cy1, cx0:cx1] = img[cy0:cy1, cx0:cx1] * (1 - a) + np.clip(rgb, 0, 1) * a
    Image.fromarray((np.clip(img, 0, 1) ** (1 / 1.0) * 255).astype(np.uint8), "RGB").save(path)


# ---------------------------------------------------------------------------

def run_checks(pack, clusters):
    report = {"order_violations": 0, "max_screen_err_px": 0.0, "max_size_err": 0.0, "behind": 0,
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
    return results


def previews(pack, clusters, only=None):
    os.makedirs(DOCS, exist_ok=True)
    base = np.array([512.0, 70.0, 300.0])
    shots = [
        ("noon_realistic", 0.5, dict(cu=0.45, st=0.08, ac=0.25, ci=0.35), 0.0, (-24, 20)),
        ("afternoon_cumulus", 0.6, dict(cu=0.7, st=0.0, ac=0.06, ci=0.1, size=1.25), 0.0, (-18, 200)),
        ("sunset_realistic", 0.735, dict(cu=0.45, st=0.08, ac=0.3, ci=0.45, warm=0.8, atmo=0.85), 0.0, (-14, 90)),
        ("dusk_cirrus", 0.765, dict(cu=0.08, st=0.0, ac=0.2, ci=0.9, warm=0.85, atmo=0.9), 0.0, (-20, 90)),
        ("night_moon", 0.02, dict(cu=0.4, st=0.05, ac=0.25, ci=0.3), 0.0, (-30, 0)),
        ("overcast", 0.45, dict(cu=0.35, st=0.95, ac=0.3, ci=0.0, storm=0.15), 0.0, (-20, 300)),
        ("storm", 0.55, dict(cu=0.72, st=0.8, ac=0.15, ci=0.1, storm=1, rain=1, thunder=1), 1.0, (-12, 150)),
        ("fantasy", 0.7, dict(cu=0.5, st=0.0, ac=0.45, ci=0.55, fantasy=1, soft=2, size=1.35, warm=0.8), 0.0, (-22, 60)),
        ("minimal", 0.42, dict(cu=0.3, st=0.0, ac=0.0, ci=0.22, tier=0, detail=0, lightq=0), 0.0, (-25, 0)),
        ("above_clouds", 0.66, dict(cu=0.65, st=0.4, ac=0.3, ci=0.4), 0.0, (16, 120)),
    ]
    out = []
    for name, tod, over, rain, (pitch, yaw) in shots:
        if only and name not in only:
            continue
        props = default_props(**{**dict(tier=3, detail=3, lightq=2, autoq=0), **over})
        sim = Sim(pack, props)
        sim.time_of_day = tod
        y = 70.0 if name != "above_clouds" else 330.0
        pos = base + [0, y - base[1], 0]
        cam = Camera(pos + [0, 1.62, 0], pitch, yaw)
        for i in range(160):
            tr, rcs = sim.frame(cam, pos - [0, 16, 0], dt=1 / 20)
        path = os.path.join(DOCS, f"preview_{name}.png")
        render(pack, sim, cam, pos - [0, 16, 0], tr, rcs, path, tod, rain=rain, ground=(name != "above_clouds"))
        out.append(path)
        print("  rendered", os.path.relpath(path, ROOT))
    return out


def main():
    t0 = time.time()
    pack = Pack()
    clusters = G.build_field()
    G.order_sprites(clusters)          # assigns the same names as the pack
    results = run_checks(pack, clusters)
    print(json.dumps(results, indent=2))
    ok = True
    st = results["static"]
    if st["order_violations"] or results["above_clouds"]["order_violations"]:
        print("FAIL: draw order is not depth ordered"); ok = False
    if st["max_screen_err_px"] > 1.0 or results["above_clouds"]["max_screen_err_px"] > 1.0:
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
    if "--no-preview" not in sys.argv:
        previews(pack, clusters)
    with open(os.path.join(DOCS, "simulation_results.json"), "w") as f:
        json.dump(results, f, indent=2)
    print(f"{'PASS' if ok else 'FAIL'} ({time.time() - t0:.0f}s)")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
