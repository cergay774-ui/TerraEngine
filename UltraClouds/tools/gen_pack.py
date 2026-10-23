#!/usr/bin/env python3
"""Ultra Clouds - pack generator.

Generates every data-driven file of the resource pack (client entity,
geometry, Molang projection animations, render controllers, texts) and the
behavior pack (entity definition with synced properties, item, manifests).

Run after tools/gen_textures.py (needs tools/atlas_meta.json).

How the sky works (short version, see README for the long one):
  * One invisible entity per player ("sky rig") is kept under the player by
    the script.  Only its owner sees it (per-player property override).
  * The rig's geometry is a flat list of quads ("sprites").  Each sprite
    belongs to a cloud cluster that lives in a virtual, world-anchored,
    wrapping cloud field (several hundred to several thousand blocks wide).
  * Every frame, Molang computes the camera position, the true 3D position
    of each cluster/sprite, and then re-projects the sprite along the view
    ray into the "sky depth" range with a size scaled to keep the exact same
    on-screen size.  This keeps clouds visible at any render distance while
    preserving correct parallax, perspective and motion.
  * The projected depth grows with the true distance of the cluster
    (logarithmic map), so the depth buffer itself sorts the clouds.
  * Every cloud is drawn twice: an alpha-tested core pass (dense inside,
    writes depth only where the cloud is) and a blended halo pass (soft
    edges, drawn after all cores).  Alpha testing is what makes overlaps
    robust: transparent parts of a quad never write depth, so no invisible
    rectangle can cut another cloud, in any draw order and with any depth
    buffer precision (16-bit depth on many phones).
"""
import json
import math
import os
import random
import uuid

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RP = os.path.join(ROOT, "packs", "UltraClouds_RP")
BP = os.path.join(ROOT, "packs", "UltraClouds_BP")
GEN_TS = os.path.join(ROOT, "src", "scripts", "generated.ts")

NS = "ultra_clouds"
ENTITY_ID = f"{NS}:sky"
ITEM_ID = f"{NS}:cloud_settings"
VERSION = [1, 2, 0]
MIN_ENGINE = [1, 26, 50]
SERVER_VERSION = "2.10.0"        # stable @minecraft/server for 1.26.50+
SERVER_UI_VERSION = "2.2.0"      # stable @minecraft/server-ui for 1.26.50+


def stable_uuid(name):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, "https://ultra-clouds.local/" + name))


RP_UUID = stable_uuid("rp-header")
RP_MOD_UUID = stable_uuid("rp-module")
BP_UUID = stable_uuid("bp-header")
BP_MOD_UUID = stable_uuid("bp-data-module")
BP_SCRIPT_UUID = stable_uuid("bp-script-module")

# --------------------------------------------------------------------------
# Synced entity properties (max 32 per entity type)
# (name, type, range/values, default)
# --------------------------------------------------------------------------
PROPS = [
    ("show", "bool", None, False),
    ("tier", "int", [0, 3], 1),
    ("detail", "int", [0, 3], 1),
    ("lightq", "int", [0, 2], 1),
    ("autoq", "bool", None, True),
    ("cu", "float", [0.0, 1.0], 0.45),
    ("st", "float", [0.0, 1.0], 0.1),
    ("ac", "float", [0.0, 1.0], 0.25),
    ("ci", "float", [0.0, 1.0], 0.35),
    ("storm", "float", [0.0, 1.0], 0.0),
    ("fantasy", "float", [0.0, 1.0], 0.0),
    ("size", "float", [0.4, 2.5], 1.0),
    ("height", "int", [100, 450], 200),
    ("wspeed", "float", [0.0, 12.0], 2.0),
    ("wdir", "int", [0, 359], 75),
    ("dist", "float", [0.3, 1.0], 0.85),
    ("depth", "int", [24, 256], 80),
    ("contrast", "float", [0.0, 1.0], 0.55),
    ("soft", "int", [0, 2], 1),
    ("shadow", "float", [0.0, 1.0], 0.5),
    ("bright", "float", [0.4, 1.6], 1.0),
    ("warm", "float", [0.0, 1.0], 0.6),
    ("real", "float", [0.0, 1.0], 0.7),
    ("tod", "float", [0.0, 1.0], 1.0),
    ("wxi", "float", [0.0, 1.0], 0.8),
    ("haze", "float", [0.0, 1.0], 0.2),
    ("atmo", "float", [0.0, 1.0], 0.6),
    ("rain", "float", [0.0, 1.0], 0.0),
    ("thunder", "float", [0.0, 1.0], 0.0),
    ("seed", "int", [0, 4095], 0),
]
assert len(PROPS) <= 32

# --------------------------------------------------------------------------
# Atlas cells (must match tools/gen_textures.py)
# --------------------------------------------------------------------------
META = json.load(open(os.path.join(ROOT, "tools", "atlas_meta.json")))["cells"]
ASPECT = {c["index"]: c["aspect"] for c in META}
PUFFS = [0, 1, 2, 3, 4, 5]
BASES = [6, 7]
SHEETS = [8, 9]                # stratus sheet, dense overcast slab
SLAB = 9
STREAKS = [10, 11]
PATCHES = [12, 13]
TOWER = 14
WISP = 15
TEX = 1024
CELL = 256

# --------------------------------------------------------------------------
# Cloud field definition
# --------------------------------------------------------------------------
# P: wrap period of the layer (blocks); counts: clusters per quality tier
# alt: altitude above the user "height"; size: cluster width range per tier
LAYERS = {
    "cu": dict(P=2048, counts=[36, 26, 22, 24], alt=0.0, yj=16.0,
               size=[(165, 250), (120, 185), (85, 140), (60, 105)]),
    "st": dict(P=2304, counts=[8, 6, 5, 5], alt=-8.0, yj=8.0,
               size=[(560, 820), (480, 720), (420, 640), (380, 560)]),
    "ac": dict(P=2560, counts=[6, 5, 5, 4], alt=170.0, yj=18.0,
               size=[(300, 440), (260, 380), (220, 340), (200, 300)]),
    "ci": dict(P=4096, counts=[5, 4, 3, 3], alt=430.0, yj=45.0,
               size=[(1300, 1800), (1150, 1550), (1050, 1400), (950, 1250)]),
}
# wind multiplier and direction offset (deg) per layer (high clouds are faster)
WIND = {"cu": (1.0, 0.0), "st": (0.9, -8.0), "ac": (1.35, 12.0), "ci": (1.8, 22.0)}
SEED = 777


def fmt(x):
    if isinstance(x, int):
        return str(x)
    s = f"{x:.4f}".rstrip("0").rstrip(".")
    if s in ("-0", ""):
        s = "0"
    return s


def poisson_torus(rng, n, P, min_frac=0.7):
    """Best-candidate sampling on a torus -> evenly spread cluster centres."""
    pts = []
    for i in range(n):
        best, best_d = None, -1.0
        for _ in range(24):
            c = (rng.uniform(0, P), rng.uniform(0, P))
            d = min((min(abs(c[0] - p[0]), P - abs(c[0] - p[0])) ** 2 +
                     min(abs(c[1] - p[1]), P - abs(c[1] - p[1])) ** 2) for p in pts) if pts else 1e18
            if d > best_d:
                best, best_d = c, d
        pts.append(best)
    return pts


class Sprite:
    def __init__(self, layer, rc, cluster, rank, cell, ox, oy, oz, height, flags=()):
        self.layer, self.rc, self.cluster, self.rank = layer, rc, cluster, rank
        self.cell, self.ox, self.oy, self.oz = cell, ox, oy, oz
        self.height = height          # quad height relative to cluster size
        self.flags = set(flags)
        self.name = None
        self.bias = 0              # index among the cluster's pieces of one group


class Cluster:
    def __init__(self, layer, k, tier, bx, bz, size, yoff, rank, phase, omega):
        self.layer, self.k, self.tier = layer, k, tier
        self.bx, self.bz, self.size, self.yoff = bx, bz, size, yoff
        self.rank, self.phase, self.omega = rank, phase, omega
        self.sprites = []

    @property
    def var(self):
        return f"v.c{self.layer}{self.k}"


def puff(rng, exclude=()):
    choices = [c for c in PUFFS if c not in exclude]
    return rng.choice(choices)


def build_field():
    rng = random.Random(SEED)
    clusters = []
    for layer, spec in LAYERS.items():
        P = spec["P"]
        total = sum(spec["counts"])
        centres = poisson_torus(rng, total, P)
        idx = 0
        for tier, count in enumerate(spec["counts"]):
            ranks = [(i + rng.random()) / count for i in range(count)]
            rng.shuffle(ranks)
            for i in range(count):
                bx, bz = centres[idx]
                lo, hi = spec["size"][tier]
                size = rng.uniform(lo, hi)
                cl = Cluster(layer, idx, tier, bx, bz, size,
                             spec["alt"] + rng.uniform(-spec["yj"], spec["yj"]),
                             ranks[i], rng.uniform(0, 360), rng.uniform(0.25, 0.6))
                add_sprites(rng, cl)
                clusters.append(cl)
                idx += 1
    clusters.append(overcast_ceiling(rng))
    return clusters


# Overcast ceiling: sheets that sit on the stratus deck around the camera
# (elevation, azimuth, width in units of the deck height above the camera).
# Fades in only for dense stratus / rain so overcast skies really close up.
# Rings use the dense slab texture and are sized so that neighbouring slabs
# overlap (width >= 1.35 x spacing x cot(elevation)) from ~2 degrees above
# the horizon up to the zenith, with as little overdraw as possible.
OV_RINGS = [(8, 14, 7.2), (24, 10, 3.6), (46, 6, 2.0)]
OV_ZENITH = 3.0
OV_SPRITES = [(el, (360 / n) * (i + 0.5 * (r % 2)), w)
              for r, (el, n, w) in enumerate(OV_RINGS) for i in range(n)] + [(90, 0, OV_ZENITH)]


def overcast_ceiling(rng):
    cl = Cluster("ov", 999, 0, 0.0, 0.0, 1.0, 1000.0, 0.0, 0.0, 0.0)
    for i, (el, az, wf) in enumerate(OV_SPRITES):
        cell = SLAB
        sp = Sprite("ov", "st", cl, 0, cell, 0.0, 0.0, 0.0, wf / ASPECT[cell], flags=("ceiling",))
        n = {el: n for el, n, w in OV_RINGS}.get(el, 1)
        sp.el, sp.az = el, az + rng.uniform(-1, 1) * 25 / n
        sp.ring = [r[0] for r in OV_RINGS].index(el) if el != 90 else len(OV_RINGS)
        cl.sprites.append(sp)
    return cl


def add_sprites(rng, cl):
    L, t = cl.layer, cl.tier
    S = cl.sprites
    if L == "cu":
        c0 = puff(rng)
        h0 = rng.uniform(0.95, 1.05) / ASPECT[c0]          # height for width ~1.0
        S.append(Sprite(L, "cu", cl, 0, c0, 0.0, h0 * 0.5, 0.0, h0))
        cb = rng.choice(BASES)
        hb = 1.02 / ASPECT[cb]
        S.append(Sprite(L, "cb", cl, 0, cb, 0.0, hb * 0.12, rng.uniform(-0.05, 0.05), hb, flags=("base",)))
        side = rng.choice([-1, 1])
        c1 = puff(rng, (c0,))
        h1 = 0.62 / ASPECT[c1]
        S.append(Sprite(L, "cu", cl, 1, c1, side * rng.uniform(0.36, 0.46), h1 * 0.45,
                        rng.uniform(-0.25, 0.25), h1))
        if t <= 2:
            c2 = puff(rng, (c0, c1))
            h2 = 0.52 / ASPECT[c2]
            S.append(Sprite(L, "cu", cl, 2, c2, -side * rng.uniform(0.3, 0.42), h2 * 0.42,
                            rng.uniform(-0.3, 0.3), h2))
        if t <= 1 and cl.k % 3 == 0:
            ht = 1.25                                       # towers are ~1.25 S tall
            S.append(Sprite(L, "cu", cl, 2, TOWER, rng.uniform(-0.1, 0.1), ht * 0.5,
                            rng.uniform(-0.1, 0.1), ht, flags=("tower",)))
        if t <= 1:
            for j in range(2):
                cw = WISP if rng.random() < 0.6 else puff(rng)
                hw = 0.3 / ASPECT[cw]
                S.append(Sprite(L, "cu", cl, 3, cw, (1 if j else -1) * rng.uniform(0.55, 0.7),
                                rng.uniform(0.05, 0.22), rng.uniform(-0.35, 0.35), hw))
    elif L == "st":
        # regular stratus uses the rolled stratocumulus sheet only; the flat
        # slab is reserved for the overcast ceiling
        c0 = c1 = SHEETS[0]
        S.append(Sprite(L, "st", cl, 0, c0, 0.0, 0.0, 0.0, 1.0 / ASPECT[c0]))
        S.append(Sprite(L, "st", cl, 1, c1, rng.uniform(-0.5, 0.5), rng.uniform(-2, 2) / cl.size,
                        rng.uniform(-0.5, 0.5), 0.8 / ASPECT[c1]))
        S.append(Sprite(L, "st", cl, 2, c0, rng.uniform(-0.45, 0.45), rng.uniform(-2, 2) / cl.size,
                        rng.uniform(-0.45, 0.45), 0.65 / ASPECT[c0]))
    elif L == "ac":
        c0 = rng.choice(PATCHES)
        S.append(Sprite(L, "ac", cl, 0, c0, 0.0, 0.0, 0.0, 1.0 / ASPECT[c0]))
        c1 = PATCHES[1] if c0 == PATCHES[0] else PATCHES[0]
        S.append(Sprite(L, "ac", cl, 2, c1, rng.uniform(-0.5, 0.5), rng.uniform(-4, 4) / cl.size,
                        rng.uniform(-0.5, 0.5), 0.65 / ASPECT[c1]))
    elif L == "ci":
        # one streak per formation: thin translucent layers must not overlap
        c0 = rng.choice(STREAKS)
        S.append(Sprite(L, "ci", cl, 0, c0, 0.0, 0.0, 0.0, 1.0 / ASPECT[c0]))


# Render groups.  Every group except cirrus is drawn twice:
#  * core pass  (entity_alphatest): the dense inside of every cloud.  Alpha
#    tested pixels never write depth where the cloud is transparent, so the
#    depth buffer resolves overlaps correctly in any draw order and at any
#    depth precision - no invisible rectangles can cut other clouds.
#  * halo pass (entity_alphablend): the soft outer edge, drawn after all
#    cores.  Its quads write depth, so it is drawn roughly back to front.
# Cirrus is thin and translucent all over: it has no core.  The halo pass of
# the layer clouds (big, overlapping sheets) is split into distance bins
# drawn far to near, so a near sheet never blocks the halo of a far one.
GROUPS = ["ci", "ac", "cu", "cb", "st"]
LOW_GROUP = {"cu", "cb", "st"}
CORE_GROUPS = ["cu", "cb", "st", "ac"]
# depth ties are won by the group drawn first (LESS depth test).  The base
# (shaded underside seen from below) sits just behind the cumulus body, so
# it only shows where it peeks out below and around the body.
CORE_BELOW = ["st", "cu", "cb", "ac"]
CORE_ABOVE = ["cu", "cb", "st", "ac"]
# halo order: wide layer halos first (far bins first), the thin cumulus
# halos last.  A near cumulus drawn before a far stratus sheet would punch a
# hole into the sheet's wide halo; the other way round a far cumulus only
# loses a few pixels of its thin halo where a near sheet covers it.
HALO_ORDER = ["ci", "ac", "st", "cb", "cu"]
# Halo distance bins (bin 0 is the nearest, drawn last).
#  * altocumulus: by the distance / height ratio (count, ln of the ratio
#    covered).  It is always farther than the low layers along the same view
#    ray, so it is drawn first.
#  * low layers (stratus, cumulus, cumulus bases): shared bins of the
#    normalised log distance, drawn bin by bin: stratus, bases, cumulus.
#    The overcast ceiling is drawn after everything (it is the nearest).
LAYER_BINS = {"ac": (3, 1.4)}
# Cirrus (the highest layer, translucent all over) does not use its true
# distance for depth: every cirrus sprite owns a fixed depth slot in a band
# behind all other clouds, strictly decreasing in draw order.  Slots are
# ~2.3% apart, so even a 16-bit depth buffer never lets one cirrus quad cut
# another.  (Lower clouds never project deeper than ~0.84 zfar.)  The band
# ends at 1.19 zfar and the script sets zfar to 0.72 of the sky depth, so
# even cirrus stay at 0.86 of it, in front of the vanilla fog (from 0.92).
CI_BAND = (0.87, 1.19)
LOW_BINS = 6
LOW_LZ = (0.10, 0.68)          # ~120 .. ~950 blocks
# Quads are authored 16 px tall (the size 1.0 used and that the game is known
# to render).  Bones of switched-off quality levels are hidden by
# part_visibility, so their rest pose is never drawn.
GEO_SCALE = 1
PIECE_BIAS = 0.004             # relative depth step between pieces of a cluster
CEIL_STEP = 0.02               # relative depth step between overcast ceiling sprites


def order_sprites(clusters):
    """Bone order inside each group: clusters high first, then by piece rank;
    the overcast ceiling (nearest of all, around the camera) comes last, its
    rings from the horizon up to the zenith, i.e. far to near.

    Pieces of one cluster get a tiny decreasing depth in halo draw order
    (later piece nearer), so on precise depth buffers their halos never cut
    each other; on coarse ones they tie and the piece drawn first wins."""
    groups = {g: [] for g in GROUPS}
    for cl in sorted(clusters, key=lambda c: (c.layer == "ov", -c.yoff, c.layer, c.k)):
        pieces = sorted(cl.sprites, key=lambda s: (HALO_ORDER.index(s.rc), getattr(s, "el", 0),
                                                   s.rank, "tower" in s.flags))
        for i, sp in enumerate(pieces):
            sp.bias = i
            groups[sp.rc].append(sp)
    for g, lst in groups.items():
        for i, sp in enumerate(lst):
            if sp.cluster.layer == "ov":
                # ceiling: ring number first, so the halo pass can pick rings
                sp.name = f"ov{sp.ring}_{i:03d}"
            else:
                sp.name = f"{g}_t{sp.cluster.tier}_{sp.cluster.k:03d}_r{sp.rank}_{i:03d}"
    return groups, sum(len(v) for v in groups.values())


# --------------------------------------------------------------------------
# Resource pack: geometry
# --------------------------------------------------------------------------

def build_geometry(groups):
    bones = [{"name": "root", "pivot": [0, 0, 0]}]
    for g in GROUPS:                           # bone order == draw order per RC
        for sp in groups[g]:
            a = ASPECT[sp.cell]
            w, h = round(16 * a / GEO_SCALE, 6), round(16 / GEO_SCALE, 6)
            col, row = sp.cell % 4, sp.cell // 4
            bones.append({
                "name": sp.name,
                "parent": "root",
                "pivot": [0, 0, 0],
                "cubes": [{
                    "origin": [-w / 2, -h / 2, 0],
                    "size": [w, h, 0],
                    "uv": {"south": {"uv": [col * CELL, row * CELL], "uv_size": [CELL, CELL]}},
                }],
            })
    return {
        "format_version": "1.21.0",
        "minecraft:geometry": [{
            "description": {
                "identifier": "geometry.ultra_clouds.sky",
                "texture_width": TEX,
                "texture_height": TEX,
                "visible_bounds_width": 4096,
                "visible_bounds_height": 4096,
                "visible_bounds_offset": [0, 0, 0],
            },
            "bones": bones,
        }],
    }


# --------------------------------------------------------------------------
# Resource pack: Molang
# --------------------------------------------------------------------------

def prop(name):
    return f"q.property('{NS}:{name}')"


def smooth(var, target, rate):
    """Frame-rate independent exponential approach of v.var to target."""
    return (f"v.{var} = (v.{var} ?? ({target})) + (({target}) - (v.{var} ?? ({target}))) "
            f"* math.clamp(v.dt * {rate}, 0, 1);")


def section(statements):
    """One pre_animation entry.  temp.* variables only live inside a single
    expression, so every entry must be self-contained."""
    return " ".join(statements)


# Longest pre_animation entry 1.0 shipped (and the game is known to run).
# Bigger guarded blocks are split into several entries below this size.
ENTRY_LIMIT = 12000


def guarded(cond, items, limit=ENTRY_LIMIT):
    """Pre_animation entries `(cond) ? { items };`, split so that no entry
    exceeds `limit` characters.  Every item must be self-contained (it sets
    the temp variables it reads), so it can start a new entry."""
    out, cur = [], []
    size = 0
    for it in items:
        if cur and size + len(it) + 1 > limit - len(cond) - 16:
            out.append(f"({cond}) ? {{ " + " ".join(cur) + " };")
            cur, size = [], 0
        cur.append(it)
        size += len(it) + 1
    if cur:
        out.append(f"({cond}) ? {{ " + " ".join(cur) + " };")
    return out


# Depth map: true distance 80..4000 blocks -> view depth zmin..zfar (log).
# Nearer clouds always get a smaller depth (about 1% of depth per 7% of
# distance, coarser than a 16-bit depth buffer resolves at these depths),
# and terrain nearer than zmin (0.44 of the render distance) always covers
# the clouds.
ZMIN_FRAC = 0.55
LD_NEAR = 80.0
LD_FAR = 4000.0


def log_dist(m):
    """Molang: normalised log distance (0 at 80, 1 at 4000 blocks) for a
    cluster whose 0.12 * distance is m."""
    k = 1.0 / math.log(LD_FAR / LD_NEAR)
    return f"math.clamp((math.ln(math.max({m} * 8.3333, 1)) - {fmt(math.log(LD_NEAR))}) * {fmt(k)}, 0, 1)"


def log_depth(m):
    """Molang: 16 * projected depth for a cluster whose 0.12*distance is m."""
    return f"16 * v.zmin * math.exp({log_dist(m)} * {fmt(-math.log(ZMIN_FRAC))})"


def ceil_slot(ov, sp):
    """Depth factor of an overcast ceiling sprite, relative to the true depth
    of the lowest ring (v.ov_d).  Slots shrink by CEIL_STEP per draw slot, so
    every sprite sits at or in front of its true depth (the deck is the
    lowest layer) and no two sprites ever share a depth."""
    return (1 - CEIL_STEP) ** sp.bias


def ci_slot(groups, sp):
    """Depth factor (x zfar) of a cirrus sprite: first drawn = farthest."""
    lst = groups["ci"]
    j = lst.index(sp)
    lo, hi = CI_BAND
    return lo * (hi / lo) ** ((len(lst) - 1 - j) / max(len(lst) - 1, 1))


def pre_animation(clusters, groups, total):
    out = []
    # ---- settings (smoothed so that every change animates in) ------------
    s = ["v.dt = math.clamp(q.delta_time, 0, 0.1);",
         f"v.on = {prop('show')};",
         "v.age = (v.age ?? 0) + v.dt;",
         f"v.p_tier = {prop('tier')}; v.p_detail = {prop('detail')}; v.p_lightq = {prop('lightq')};",
         f"v.p_soft = {prop('soft')}; v.p_autoq = {prop('autoq')}; v.p_seed = {prop('seed')};"]
    for name, rate in [("cu", 0.6), ("st", 0.5), ("ac", 0.5), ("ci", 0.5), ("storm", 0.5),
                       ("fantasy", 0.8), ("size", 1.0), ("height", 1.0), ("dist", 1.5),
                       ("contrast", 2), ("shadow", 2), ("bright", 2), ("warm", 2), ("real", 2),
                       ("tod", 2), ("wxi", 1), ("haze", 0.8), ("atmo", 2), ("rain", 0.12),
                       ("thunder", 0.15), ("wspeed", 1.5), ("depth", 3)]:
        s.append(smooth("p_" + name, prop(name), rate))
    s.append(f"v.p_wdir = math.lerprotate(v.p_wdir ?? {prop('wdir')}, {prop('wdir')}, math.clamp(v.dt * 1.5, 0, 1));")
    out.append(section(s))
    # ---- adaptive quality (client side frame-time measurement) -----------
    # Clouds are a small part of the frame, so this only reacts to real
    # trouble: one step down while the average is below ~20 FPS (never below
    # the Medium cloud count, nothing during the first 20 s after loading),
    # then no change for 90 s; one step back up whenever it runs at ~30 FPS
    # or better (phones locked to 30 FPS recover too).
    s = ["v.ft = (v.ft ?? 0.016) * 0.97 + math.clamp(q.delta_time, 0, 0.25) * 0.03;",
         "v.aq_t = (v.aq_t ?? 0) + v.dt;",
         "v.aq_hold = math.max((v.aq_hold ?? 20) - v.dt, 0);",
         "(v.p_autoq && v.aq_t > 5) ? { v.aq_t = 0; (v.aq_hold <= 0 && v.ft > 0.05) ? { v.aq_cap = math.max(1, (v.aq_cap ?? 3) - 1); v.aq_hold = 90; }; (v.aq_hold <= 0 && v.ft < 0.036) ? { v.aq_cap = math.min(3, (v.aq_cap ?? 3) + 1); }; };",
         "v.tq = v.p_autoq ? math.min(v.p_tier, v.aq_cap ?? 3) : v.p_tier;",
         "v.dq = v.p_autoq ? math.min(v.p_detail, (v.aq_cap ?? 3) + 1) : v.p_detail;"]
    for t in range(4):
        for r in range(4):
            s.append(f"v.g{t}{r} = v.on && v.tq >= {t} && v.dq >= {r};")
    s.append("v.softi = (v.p_soft >= 2) ? 1 : 0; v.fringe = v.on && v.p_soft >= 1;")
    out.append(section(s))
    # ---- camera: orientation, offset from the rig, world position --------
    s = ["v.cp = q.camera_rotation(0); v.cy = q.camera_rotation(1);",
         "t.sp = math.sin(v.cp); t.cc = math.cos(v.cp);",
         "v.fx = -math.sin(v.cy) * t.cc; v.fy = -t.sp; v.fz = math.cos(v.cy) * t.cc;",
         "v.flip = (v.cp < 0) ? -1 : 1;",
         # sheets must not reach below the horizon: on the view plane the
         # horizon lies (world height of the sprite centre) / cos(pitch)
         # below it, so the cap grows when looking up
         f"v.hcap = {fmt(0.1125 * GEO_SCALE)} / math.max(t.cc, 0.05);",
         # lighting normal factor of the vanilla actor shader (Fancy graphics)
         "v.lf = q.graphics_mode_is_any('fancy') ? (0.725 + 0.275 * math.abs(t.sp) + 0.1 * t.cc * t.cc * math.cos(2 * v.cy)) : 1;",
         # camera offset relative to the rig root (rig lags 0-2 ticks behind)
         "t.d = q.distance_from_camera; t.a0 = q.rotation_to_camera(0); t.a1 = q.rotation_to_camera(1);",
         "t.ok = math.abs(math.sin(t.a0)) > 0.3;",
         "t.h = t.ok ? t.d * math.abs(math.cos(t.a0)) : 0;",
         "v.co_y = t.ok ? t.d * math.abs(math.sin(t.a0)) : t.d;",
         # self-calibrating horizontal sign: the camera always leads the rig
         # along the direction of motion
         "t.mx = q.position(0) - (v.px ?? q.position(0)); t.mz = q.position(2) - (v.pz ?? q.position(2));",
         "v.px = q.position(0); v.pz = q.position(2);",
         "t.m2 = t.mx * t.mx + t.mz * t.mz;",
         "(t.ok && t.m2 > 0.0004 && t.m2 < 64 && t.h > 0.05 && t.h < 2.5) ? { v.vote = math.clamp((v.vote ?? 0.6) + (((-math.sin(t.a1) * t.mx + math.cos(t.a1) * t.mz) > 0) ? 0.04 : -0.04), -1, 1); };",
         "t.sg = ((v.vote ?? 0.6) >= 0) ? 1 : -1;",
         "v.co_x = -math.sin(t.a1) * t.h * t.sg; v.co_z = math.cos(t.a1) * t.h * t.sg;",
         "v.cw_x = q.position(0) + v.co_x; v.cw_y = q.position(1) + v.co_y; v.cw_z = q.position(2) + v.co_z;",
         # projection constants
         # in rain the vanilla fog closes in: pull the sky nearer so dark
         # storm clouds stay visible instead of fading into the fog colour
         "v.zfar = v.p_depth * (1 - 0.45 * math.clamp(v.p_rain * v.p_wxi, 0, 1));",
         f"v.zmin = v.zfar * {fmt(ZMIN_FRAC)}; v.zf3 = v.zfar * {3 * GEO_SCALE};",
         "v.above = v.cw_y > (v.p_height + 30);"]
    out.append(section(s))
    # ---- weather & cloud type driven layer state -------------------------
    s = ["v.wet = math.clamp(v.p_rain * v.p_wxi, 0, 1);",
         "v.thd = math.clamp(v.p_thunder * v.p_wxi, 0, 1);",
         "v.stormf = math.clamp(math.max(v.p_storm, v.thd), 0, 1);",
         "v.dark = math.clamp(v.stormf * 0.75 + v.wet * 0.35, 0, 1);",
         "v.d_cu = math.clamp(v.p_cu + v.wet * 0.25 + v.thd * 0.2, 0, 1);",
         "v.d_st = math.clamp(v.p_st + v.wet * 0.75 + v.p_haze * 0.25, 0, 1);",
         "v.d_ac = math.clamp(v.p_ac - v.wet * 0.2, 0, 1);",
         "v.d_ci = math.clamp(v.p_ci - v.wet * 0.3, 0, 1);",
         "v.sz_cu = v.p_size * (1 + 0.35 * v.stormf);",
         "v.sz_st = v.p_size * (1 + 0.2 * v.p_haze) * (0.55 + 0.85 * v.d_st);",
         "v.sz_ac = v.p_size; v.sz_ci = v.p_size;",
         "v.alt_cu = v.p_height - 12 * v.stormf;",
         "v.alt_st = v.p_height - 8 - 45 * v.p_haze - 15 * v.wet;",
         "v.alt_ac = v.p_height + 170; v.alt_ci = v.p_height + 430;"]
    for L, spec in LAYERS.items():
        s.append(f"v.R_{L} = v.p_dist * {fmt(spec['P'] * 0.47)}; v.Ri_{L} = 1 / (v.R_{L} * 0.22);")
    out.append(section(s))
    # ---- wind: integrated per layer, wrapped to the layer period ----------
    s = []
    for L, spec in LAYERS.items():
        P = spec["P"]
        mul, off = WIND[L]
        s.append(f"t.wd = v.p_wdir + {fmt(off)}; t.ws = v.p_wspeed * {fmt(mul)} * v.dt;")
        s.append(f"v.w{L}x = (v.w{L}x ?? (v.p_seed * 37.13)) + math.sin(t.wd) * t.ws; v.w{L}x = v.w{L}x - {P} * math.floor(v.w{L}x / {P});")
        s.append(f"v.w{L}z = (v.w{L}z ?? (v.p_seed * 91.71)) - math.cos(t.wd) * t.ws; v.w{L}z = v.w{L}z - {P} * math.floor(v.w{L}z / {P});")
    out.append(section(s))
    # ---- lighting ----------------------------------------------------------
    out += lighting_sections()
    # ---- layer offsets relative to the camera -----------------------------
    s = []
    for L in LAYERS:
        s.append(f"v.ox_{L} = v.w{L}x - v.cw_x; v.oz_{L} = v.w{L}z - v.cw_z; v.oy_{L} = v.alt_{L} - v.cw_y;")
    out.append(section(s))
    # ---- clusters (per layer and tier), then sprites (per detail rank) -----
    # v.bin_<layer><k> is the cluster's halo distance bin, -1 when the cluster
    # is not drawn (invisible, or its quality tier is off).  The render
    # controllers draw only clusters with a bin, so hidden clouds cost almost
    # nothing.  Everything past the visibility test runs only for visible
    # clusters; their sprites get their final transforms here, so the
    # animation channels are plain variable reads.
    for L, spec in LAYERS.items():
        P = spec["P"]
        for tier in range(4):
            cls = [c for c in clusters if c.layer == L and c.tier == tier]
            if not cls:
                continue
            body = []
            for cl in cls:
                vv = cl.var
                item = []
                body.append(item)
                item.append(f"t.x = {fmt(cl.bx)} + v.ox_{L}; t.x = t.x - {P} * math.floor(t.x / {P} + 0.5);")
                item.append(f"t.z = {fmt(cl.bz)} + v.oz_{L}; t.z = t.z - {P} * math.floor(t.z / {P} + 0.5);")
                item.append(f"{vv}_y = v.oy_{L} + {fmt(cl.yoff)};")
                item.append("t.dh = t.x * t.x + t.z * t.z;")
                # life cycle: the visibility threshold breathes slowly, so
                # clouds form and dissolve over a few minutes
                item.append(f"{vv}_g = math.clamp((v.d_{L} - {fmt(cl.rank)} - 0.06 * math.sin(v.age * {fmt(cl.omega)} + {fmt(cl.phase)})) * 14, 0, 1)"
                            f" * math.clamp((v.R_{L} - math.sqrt(t.dh)) * v.Ri_{L}, 0, 1) * {fmt(cl.size)} * v.sz_{L};")
                item.append(f"v.bin_{L}{cl.k} = -1;")
                vis = [f"{vv}_x = t.x; {vv}_z = t.z;",
                       f"{vv}_f = t.x * v.fx + {vv}_y * v.fy + t.z * v.fz;",
                       f"{vv}_m = 0.12 * math.sqrt(t.dh + {vv}_y * {vv}_y);",
                       # projected depth of the whole cluster (its pieces share it)
                       f"t.lz = {log_dist(vv + '_m')};",
                       f"{vv}_d = 16 * v.zmin * math.exp(t.lz * {fmt(-math.log(ZMIN_FRAC))});"]
                if L == "cu":
                    # sine of the elevation of the cloud seen from the camera:
                    # side view (low) -> body sprites, from below -> flat base
                    vis.append(f"{vv}_e = math.clamp((0.12 * {vv}_y / math.max({vv}_m, 0.001) - 0.3) * 2.2, 0, 1);")
                else:
                    # layer clouds are horizontal sheets: their apparent height
                    # shrinks with the viewing elevation; very low sheets fade
                    # out completely instead of turning into thin lines
                    vis.append(f"t.se = 0.12 * math.abs({vv}_y) / math.max({vv}_m, 0.001);")
                    vis.append(f"{vv}_q = math.clamp(1.6 * t.se, 0.3, 1);")
                    vis.append(f"{vv}_h = math.clamp((t.se - 0.05) * 12, 0, 1);")
                if L == "ci":
                    vis.append(f"v.bin_{L}{cl.k} = 0;")
                elif L not in LAYER_BINS:
                    lo, hi = LOW_LZ
                    vis.append(f"v.bin_{L}{cl.k} = math.min(math.floor(math.clamp((t.lz - {fmt(lo)}) * {fmt(1 / (hi - lo))}, 0, 1) * {LOW_BINS}), {LOW_BINS - 1});")
                else:
                    # distance bin of the halo pass (far bins drawn first)
                    nb, span = LAYER_BINS[L]
                    vis.append(f"v.bin_{L}{cl.k} = math.min(math.floor(math.clamp(math.ln(math.max({vv}_m, 0.001) / math.max(0.12 * math.abs({vv}_y), 0.001)) / {fmt(span)}, 0, 1) * {nb}), {nb - 1});")
                item.append(f"({vv}_g > 0.5) ? {{ " + " ".join(vis) + " };")
            out += guarded(f"v.g{tier}0", [" ".join(it) for it in body])
            # quality tier switched off: its clusters leave the render lists
            out.append(f"(!v.g{tier}0) ? {{ " + " ".join(f"v.bin_{L}{cl.k} = -1;" for cl in cls) + " };")
            for rank in range(4):
                body = []
                for cl in cls:
                    vv = cl.var
                    for sp in cl.sprites:
                        if sp.rank != rank:
                            continue
                        sv = f"v.s{sp.name}"
                        extra = ""
                        if "tower" in sp.flags:
                            extra = " * v.stormf"
                        elif "base" in sp.flags:
                            extra = f" * {vv}_e"
                        elif L != "cu":
                            extra = f" * {vv}_h"
                        depth = f"{vv}_d" if sp.bias == 0 else f"{vv}_d * {fmt(1 - PIECE_BIAS * sp.bias)}"
                        if L == "ci":
                            depth = f"v.zfar * {16 * ci_slot(groups, sp):.4f}"
                        calc = [f"t.f = {vv}_f + {vv}_g * ({fmt(sp.ox)} * v.fx + {fmt(sp.oy)} * v.fy + {fmt(sp.oz)} * v.fz);",
                                f"t.k = (t.f > {vv}_m) ? {depth} / t.f : 0;",
                                f"{sv}_s = math.min(t.k * {vv}_g * {sp.height * GEO_SCALE / 16:.6f}{extra}, v.zf3);"]
                        if L != "cu":
                            # sheets: foreshortened, never reaching below the horizon
                            calc.append(f"{sv}_sy = math.min({sv}_s * {vv}_q, t.k * v.hcap * math.abs({vv}_y));")
                        calc += [f"{sv}_px = ({vv}_x + {vv}_g * {fmt(sp.ox)}) * t.k;",
                                 f"{sv}_py = ({vv}_y + {vv}_g * {fmt(sp.oy)}) * t.k;",
                                 f"{sv}_pz = -({vv}_z + {vv}_g * {fmt(sp.oz)}) * t.k;"]
                        reset = f"{sv}_s = 0;" + (f" {sv}_sy = 0;" if L != "cu" else "")
                        body.append(f"{reset} ({vv}_g > 0.5) ? {{ " + " ".join(calc) + " };")
                if body:
                    out += guarded(f"v.g{tier}{rank}", body)
    # ---- overcast ceiling -------------------------------------------------
    ov = [c for c in clusters if c.layer == "ov"][0]
    body = ["v.ov_y = v.oy_st;",
            "v.ov_vis = (v.above ? 0 : 1) * math.clamp((v.d_st - 0.55) * 2.6, 0, 1);",
            "v.ov_phi = (v.ov_phi ?? 0) + v.p_wspeed * v.dt / math.max(v.ov_y, 20) * 40;"]
    # all ceiling sprites share the zenith depth plus a clear step per draw
    # slot (far rings drawn first), large enough for 16-bit depth buffers
    low = min(sp.el for sp in ov.sprites)
    items = [f"v.ov_d = {log_depth(f'0.12 * v.ov_y * {fmt(1 / math.sin(math.radians(low)))}')};"]
    for sp in ov.sprites:
        sv = f"v.s{sp.name}"
        body.append(f"{sv}_s = 0; {sv}_sy = 0;")
        calc = []
        cot = math.cos(math.radians(sp.el)) / math.sin(math.radians(sp.el))
        q = min(1.0, max(0.3, 1.6 * math.sin(math.radians(sp.el))))
        calc.append(f"t.a = {fmt(sp.az)} + v.ov_phi; t.hd = v.ov_y * {fmt(cot)};")
        calc.append(f"{sv}_vx = t.hd * math.sin(t.a); {sv}_vy = v.ov_y; {sv}_vz = t.hd * math.cos(t.a);")
        calc.append(f"t.f = {sv}_vx * v.fx + {sv}_vy * v.fy + {sv}_vz * v.fz;")
        calc.append(f"t.m = 0.12 * math.sqrt({sv}_vx * {sv}_vx + {sv}_vy * {sv}_vy + {sv}_vz * {sv}_vz);")
        calc.append(f"t.k = (t.f > t.m) ? v.ov_d * {ceil_slot(ov, sp):.4f} / t.f : 0;")
        calc.append(f"{sv}_s = math.min(t.k * v.ov_y * {sp.height * GEO_SCALE / 16:.6f} * v.ov_vis, v.zf3);")
        calc.append(f"{sv}_sy = math.min({sv}_s * {fmt(q)}, t.k * v.hcap * v.ov_y);")
        calc.append(f"{sv}_px = {sv}_vx * t.k; {sv}_py = {sv}_vy * t.k; {sv}_pz = -{sv}_vz * t.k;")
        items.append(" ".join(calc))
    out.append(section(body))
    out += guarded("v.g00 && v.ov_vis > 0.01 && v.ov_y > 5", items)
    return out


def lighting_sections():
    # colours change slowly: recompute them 5 times per second (first frame too)
    s = ["v.lt_t = (v.lt_t ?? 1) + v.dt;"]
    # sun elevation sine: noon 1, sunrise/sunset 0, midnight -1.
    # "time of day influence" pulls everything towards a fixed bright day.
    s.append("v.sun = -math.cos(q.time_of_day * 360);")
    s.append("v.e = math.lerp(0.72, v.sun, v.p_tod);")
    s.append("v.moon = q.moon_brightness;")
    s.append("v.lq = v.p_lightq;")
    # per layer elevation shift: high clouds keep the sun longer after sunset
    for L, shift in (("lo", 0.0), ("ac", 0.035), ("ci", 0.08)):
        s.append(f"t.e = v.e + {shift};")
        s.append(f"t.day = math.clamp((t.e + 0.12) / 0.2, 0, 1); v.day_{L} = t.day * t.day * (3 - 2 * t.day);")
        s.append(f"v.gold_{L} = (t.e > -0.15) ? math.exp(-math.pow((t.e - 0.03) / 0.13, 2)) : 0;")
        s.append(f"v.dusk_{L} = math.exp(-math.pow((t.e + 0.07) / 0.07, 2));")
    s.append("v.warmw = v.p_warm * (0.35 + 0.65 * v.p_atmo) * (1 - 0.7 * v.dark);")
    # night colour: realism 1 -> physically dark, 0 -> lifted, readable
    s.append("t.nl = math.lerp(2.0, 1.0, v.p_real);")
    s.append("v.n_r = (0.07 + 0.07 * v.moon) * t.nl; v.n_g = (0.08 + 0.075 * v.moon) * t.nl; v.n_b = (0.13 + 0.1 * v.moon) * t.nl;")
    # pastel 'fantasy' tint slowly drifting through peach / pink / lavender
    s.append("t.ph = v.age * 3;")
    s.append("v.fa_r = 1.0; v.fa_g = 0.86 + 0.06 * math.sin(t.ph); v.fa_b = 0.9 + 0.08 * math.sin(t.ph + 120);")

    def tint(name, L, day, gold, dusk, under=None, storm_mul=0.55):
        """night -> day, + golden hour, + twilight, * storm, * fantasy, * brightness"""
        out = []
        for ch, i in (("r", 0), ("g", 1), ("b", 2)):
            e = f"math.lerp(v.n_{ch}, {fmt(day[i])}, v.day_{L})"
            e = f"math.lerp({e}, {fmt(gold[i])} * (0.75 + 0.25 * v.day_{L}), v.gold_{L} * v.warmw)"
            e = f"math.lerp({e}, {fmt(dusk[i])}, v.dusk_{L} * v.warmw * 0.85)"
            if under is not None:
                e = f"(v.lq >= 2) ? math.lerp({e}, {fmt(under[i])}, v.gold_{L} * v.warmw * 0.8 * (1 - v.dark)) : ({e})"
            e = f"({e}) * (1 - {storm_mul} * v.dark) * math.lerp(1, v.fa_{ch}, v.p_fantasy * 0.5) * v.p_bright"
            out.append(f"v.{name}_{ch} = {e};")
        return out

    # cumulus tops: lit faces
    s += tint("tu", "lo", (1.0, 1.0, 1.0), (1.0, 0.74, 0.5), (0.78, 0.5, 0.64))
    # cumulus bases: shadow side, warm glow from the low sun at High lighting
    # the low sun of the golden hour lights the bases from the side: less shadow
    s.append("v.shf = (v.lq >= 1) ? math.lerp(1.0, 0.72, v.p_shadow * (1 - 0.7 * v.gold_lo * v.warmw)) : 1.0;")
    s += tint("tb", "lo", (0.95, 0.96, 1.0), (0.95, 0.62, 0.48), (0.62, 0.42, 0.58),
              under=(1.3, 0.78, 0.55), storm_mul=0.62)
    s.append("v.tb_r = v.tb_r * v.shf; v.tb_g = v.tb_g * v.shf; v.tb_b = v.tb_b * v.shf;")
    # stratus deck: grey, darkest in storms
    s += tint("ts", "lo", (0.93, 0.94, 0.97), (0.96, 0.72, 0.56), (0.7, 0.5, 0.62), storm_mul=0.6)
    s.append("t.sh = math.lerp(1.0, 0.82, v.p_shadow); v.ts_r = v.ts_r * t.sh; v.ts_g = v.ts_g * t.sh; v.ts_b = v.ts_b * t.sh;")
    # altocumulus / cirrus: higher, catch more colour
    s += tint("ta", "ac", (1.0, 1.0, 1.0), (1.0, 0.7, 0.52), (0.86, 0.52, 0.68), storm_mul=0.4)
    s += tint("ti", "ci", (1.0, 1.0, 1.0), (1.0, 0.68, 0.55), (0.95, 0.55, 0.75), storm_mul=0.35)
    # lighting quality Low: one shared tint for every layer (cheapest look)
    s.append("(v.lq < 1) ? { v.tb_r = v.tu_r; v.tb_g = v.tu_g; v.tb_b = v.tu_b; v.ta_r = v.tu_r; v.ta_g = v.tu_g; v.ta_b = v.tu_b; v.ti_r = v.tu_r; v.ti_g = v.tu_g; v.ti_b = v.tu_b; };")
    # split every tint into a hue (material colour, brightest channel = 1,
    # so the shader cannot clamp it) and a brightness that goes through
    # light_color_multiplier together with the compensation of the actor
    # shader's directional shading (that shading made 1.0 look grey).  All
    # darkening (night, storm) is in the brightness: the render controller
    # colour is reported to be ignored for non-warden entities
    # (MCPE-183985), light_color_multiplier is not.
    for X in RC_TINT.values():
        s.append(f"v.{X}_l = math.max(math.max(v.{X}_r, v.{X}_g), math.max(v.{X}_b, 0.001));")
        s.append(f"v.{X}_hr = v.{X}_r / v.{X}_l; v.{X}_hg = v.{X}_g / v.{X}_l; v.{X}_hb = v.{X}_b / v.{X}_l;")
    # contrast / haze: overlay towards the layer's mean tone
    s.append("v.oa = math.clamp((1 - v.p_contrast) * 0.34 + v.wet * 0.12 + ((v.p_soft == 0) ? -0.08 : 0), 0, 0.6);")
    s.append("v.alpha_ci = math.clamp(0.82 + 0.18 * v.p_contrast, 0, 1);")
    # temps (t.e, t.day, t.nl, t.ph, t.sh) are used inside this one entry only
    timer, body = s[0], s[1:]
    return [section([timer, "(v.lt_t >= 0.2) ? { v.lt_t = 0; " + " ".join(body) + " };",
                     "v.ol = v.lf + 0.35 * v.oa;"])]


RC_TINT = {"cu": "tu", "cb": "tb", "st": "ts", "ac": "ta", "ci": "ti"}
CORE_ALPHA = 0.55              # alpha test keeps texture alpha >= 0.91


def rc_color(tint, alpha):
    return {
        "color": {"r": f"v.{tint}_hr", "g": f"v.{tint}_hg", "b": f"v.{tint}_hb", "a": alpha},
        "overlay_color": {"r": f"v.{tint}_hr * 0.82", "g": f"v.{tint}_hg * 0.82",
                          "b": f"v.{tint}_hb * 0.84", "a": "v.oa"},
        "light_color_multiplier": f"math.min(v.{tint}_l / v.ol, 2.5)",
    }


def layer_var(sp):
    """Clusters' bin variables are per layer; bases belong to cumulus."""
    return sp.cluster.layer


def cluster_visibility(sprites, g):
    """Core pass: the bones of every cluster that is drawn this frame (its
    bin variable is -1 when it is invisible or its quality tier is off).
    Pieces above the detail level are scaled to zero by their "hide"
    animation."""
    vis = [{"*": False}]
    for t, k, lv in sorted({(sp.cluster.tier, sp.cluster.k, layer_var(sp)) for sp in sprites
                            if sp.cluster.layer != "ov"}):
        vis.append({f"{g}_t{t}_{k:03d}_*": f"v.bin_{lv}{k} >= 0"})
    return vis


def binned_visibility(sprites, g, b):
    """Halo bin b of a group: one rule per cluster."""
    vis = [{"*": False}]
    for t, k, lv in sorted({(sp.cluster.tier, sp.cluster.k, layer_var(sp)) for sp in sprites
                            if sp.cluster.layer != "ov"}):
        vis.append({f"{g}_t{t}_{k:03d}_*": f"v.bin_{lv}{k} == {b}"})
    return vis


def build_render_controllers(groups):
    """Returns (render controller file, ordered entity render controller list)."""
    R = "controller.render.ultra_clouds."
    rcs = {}
    base = {"arrays": {"textures": {"Array.atlas": ["Texture.natural", "Texture.soft"]}},
            "geometry": "Geometry.default",
            "ignore_lighting": True}

    def add(name, g, material, texture, vis, alpha):
        rc = dict(base, materials=[{"*": material}], textures=[texture], part_visibility=vis)
        rc.update(rc_color(RC_TINT[g], alpha))
        rcs[R + name] = rc
        return R + name

    # core pass: alpha tested, natural atlas, opaque.  Variants only change
    # which group wins depth ties (below: lower layers in front).
    core = {}
    for g in CORE_GROUPS:
        for suffix in (("_b", "_a") if g in LOW_GROUP else ("",)):
            core[g + suffix] = add(f"core_{g}{suffix}", g, "Material.core", "Texture.natural",
                                   cluster_visibility(groups[g], g), fmt(CORE_ALPHA))
    # the overcast ceiling is the nearest of all: drawn first, so the GPU can
    # reject the clouds hidden behind it before shading them
    final = [{add("core_ceiling", "st", "Material.core", "Texture.natural", [{"*": False}, {"ov*": True}],
                  fmt(CORE_ALPHA)): "v.on && v.ov_vis > 0.01"}]
    final += [{core[g + "_b"]: "v.on && !v.above"} for g in CORE_BELOW if g in LOW_GROUP]
    final += [{core[g + "_a"]: "v.on && v.above"} for g in CORE_ABOVE if g in LOW_GROUP]
    final += [{core[g]: "v.on"} for g in CORE_BELOW if g not in LOW_GROUP]

    # halo pass: blended, natural or soft atlas, far to near
    soft = "Array.atlas[v.softi]"
    # cirrus has no core: its halo is drawn even with crisp edges
    name = add("halo_ci", "ci", "Material.default", soft, cluster_visibility(groups["ci"], "ci"), "v.alpha_ci")
    final.append({name: "v.on"})
    nb = LAYER_BINS["ac"][0]
    for b in reversed(range(nb)):
        name = add(f"halo_ac{b}", "ac", "Material.default", soft, binned_visibility(groups["ac"], "ac", b), "1")
        final.append({name: "v.fringe"})
    for b in reversed(range(LOW_BINS)):
        for g in ("st", "cb", "cu"):
            name = add(f"halo_{g}{b}", g, "Material.default", soft,
                       binned_visibility(groups[g], g, b), "1")
            final.append({name: "v.fringe"})
    # overcast ceiling, nearest of all: the lowest ring always has soft edges
    # (they meet the horizon); the upper rings only while the deck is still
    # opening up - once it is closed their edges are hidden and skipping them
    # saves the most expensive overdraw of the sky
    name = add("halo_ceiling_low", "st", "Material.default", soft, [{"*": False}, {"ov0_*": True}], "1")
    final.append({name: "v.fringe"})
    upper = [{f"ov{r}_*": True} for r in range(1, len(OV_RINGS) + 1)]
    name = add("halo_ceiling_high", "st", "Material.default", soft, [{"*": False}] + upper, "1")
    final.append({name: "v.fringe && v.ov_vis < 0.97"})
    assert all(list(e)[0] in rcs for e in final) and len(final) == len(rcs)
    return {"format_version": "1.8.0", "render_controllers": rcs}, final


def build_animations(clusters, groups):
    anims = {
        "animation.ultra_clouds.root": {
            "loop": True,
            "bones": {"root": {
                "position": ["16 * v.co_x", "16 * v.co_y", "-16 * v.co_z"],
                "rotation": [0, "-q.body_y_rotation", 0]}},
        }
    }
    names = {"root": "animation.ultra_clouds.root"}
    by_group = {}
    for g in GROUPS:
        for sp in groups[g]:
            by_group.setdefault((sp.cluster.tier, sp.rank), []).append(sp)
    for (tier, rank), sps in sorted(by_group.items()):
        bones = {}
        for sp in sps:
            sv = f"v.s{sp.name}"
            # all transforms were computed in pre_animation (root sits on the
            # camera; the k factors already contain the 16 px/block scale)
            sheet = sp.layer != "cu"
            bones[sp.name] = {
                "position": [f"{sv}_px", f"{sv}_py", f"{sv}_pz"],
                "rotation": ["v.cp", "v.cy", 0],
                "scale": [f"{sv}_s", f"{sv}_sy" if sheet else f"{sv}_s", "v.flip"],
            }
        aname = f"animation.ultra_clouds.t{tier}r{rank}"
        anims[aname] = {"loop": True, "bones": bones}
        names[f"t{tier}r{rank}"] = aname
        if rank > 0:
            # detail level below this rank: the pieces stay drawn by their
            # tier's visibility rule, so they are scaled to nothing
            hname = f"animation.ultra_clouds.x{tier}r{rank}"
            anims[hname] = {"loop": True, "bones": {sp.name: {"scale": 0} for sp in sps}}
            names[f"x{tier}r{rank}"] = hname
    return {"format_version": "1.8.0", "animations": anims}, names


def initialize_script(pre):
    """Molang run once when the entity is created: gives every entity
    variable a value before any frame reads it.  Bedrock stops an expression
    with a content error when it reads a variable that was never set, and
    1.1 did exactly that for clouds that had not been visible yet (only a
    few clouds survived).  Variables read through '??' keep their 'not set
    yet' meaning and are left alone."""
    import molang

    written, guarded = [], set()

    def walk(node):
        if not isinstance(node, tuple):
            return
        if node[0] == "assign":
            name = molang.normalize_name(node[1])
            if name.startswith("v.") and name not in seen:
                seen.add(name)
                written.append(name)
        if node[0] == "bin" and node[1] == "??" and node[2][0] == "var":
            guarded.add(molang.normalize_name(node[2][1]))
        for child in node[1:]:
            if isinstance(child, tuple):
                walk(child)
            elif isinstance(child, list):
                for c in child:
                    walk(c)

    seen = set()
    for expr in pre:
        walk(molang.parse(expr))
    names = [n for n in written if n not in guarded]
    stmts = [f"{n} = {'-1' if n.startswith('v.bin_') else '0'};" for n in names]
    return [" ".join(stmts[i:i + 250]) for i in range(0, len(stmts), 250)]


def build_client_entity(clusters, groups, total, anim_names, rc_order):
    pre = pre_animation(clusters, groups, total)
    animate = [{"root": "v.on"}]
    for key in sorted(k for k in anim_names if k != "root"):
        t, r = int(key[1]), int(key[3])
        animate.append({key: f"v.g{t}{r}" if key[0] == "t" else f"v.g{t}0 && !v.g{t}{r}"})
    return {
        "format_version": "1.10.0",
        "minecraft:client_entity": {
            "description": {
                "identifier": ENTITY_ID,
                "materials": {"default": "entity_alphablend", "core": "entity_alphatest"},
                "textures": {
                    "natural": "textures/ultra_clouds/atlas_natural",
                    "soft": "textures/ultra_clouds/atlas_soft",
                },
                "geometry": {"default": "geometry.ultra_clouds.sky"},
                "animations": anim_names,
                "scripts": {
                    "initialize": initialize_script(pre),
                    "should_update_bones_and_effects_offscreen": True,
                    "should_update_effects_offscreen": True,
                    "pre_animation": pre,
                    "animate": animate,
                },
                "render_controllers": rc_order,
                "enable_attachables": False,
                "hide_armor": True,
            }
        },
    }


# --------------------------------------------------------------------------
# Texts
# --------------------------------------------------------------------------
LANG_RP = {
    "en_US": {
        "pack.name": "Ultra Clouds (Resources)",
        "pack.description": "Volumetric-style sky of cloud impostors with live settings.",
        f"entity.{ENTITY_ID}.name": "Ultra Clouds Sky",
        f"item.{ITEM_ID}": "Cloud Settings",
        f"item.{ITEM_ID}.name": "Cloud Settings",
    },
    "ru_RU": {
        "pack.name": "Ultra Clouds (Ресурсы)",
        "pack.description": "Небо из объёмных облаков-импостеров с настройками в игре.",
        f"entity.{ENTITY_ID}.name": "Небо Ultra Clouds",
        f"item.{ITEM_ID}": "Настройки облаков",
        f"item.{ITEM_ID}.name": "Настройки облаков",
    },
}
LANG_BP = {
    "en_US": {"pack.name": "Ultra Clouds (Behavior)",
              "pack.description": "Settings menu and sky rig logic for Ultra Clouds."},
    "ru_RU": {"pack.name": "Ultra Clouds (Поведение)",
              "pack.description": "Меню настроек и логика неба Ultra Clouds."},
}


def write_lang(base, table, extra=None):
    d = os.path.join(base, "texts")
    os.makedirs(d, exist_ok=True)
    langs = []
    for lang, kv in table.items():
        kv = dict(kv)
        if extra:
            kv.update(extra.get(lang, {}))
        with open(os.path.join(d, f"{lang}.lang"), "w", encoding="utf-8") as f:
            for k, v in kv.items():
                f.write(f"{k}={v}\n")
        langs.append(lang)
    with open(os.path.join(d, "languages.json"), "w") as f:
        json.dump(langs, f, indent=2)


# --------------------------------------------------------------------------
# Manifests & behavior pack data
# --------------------------------------------------------------------------

def rp_manifest():
    return {
        "format_version": 2,
        "header": {
            "name": "pack.name",
            "description": "pack.description",
            "uuid": RP_UUID,
            "version": VERSION,
            "min_engine_version": MIN_ENGINE,
        },
        "modules": [{"type": "resources", "uuid": RP_MOD_UUID, "version": VERSION}],
        "dependencies": [{"uuid": BP_UUID, "version": VERSION}],
        "subpacks": [
            {"folder_name": "keep_vanilla", "name": "Keep vanilla clouds (turn them off in Video settings)", "memory_tier": 0},
            {"folder_name": "lite", "name": "Lite: 512px textures, vanilla clouds hidden", "memory_tier": 0},
            {"folder_name": "standard", "name": "Standard: 1024px textures, vanilla clouds hidden", "memory_tier": 8},
        ],
        "metadata": {"authors": ["M1X"], "product_type": "addon"},
    }


# Pack settings (manifest format 3): the world's settings screen of the
# behavior pack (gear button of the pack, also reachable in game through
# Settings > Behavior Packs).  The script reads them with
# world.getPackSettings() and applies them to every player; /clouds still
# allows personal changes until the owner changes the pack setting again.
#   (type, key, text key, default, extra)
PROFILE_OPTIONS = ["auto", "performance", "balanced", "high", "ultra", "cinematic"]
TYPE_OPTIONS = ["realistic", "cumulus", "cirrus", "overcast", "storm", "fantasy", "minimal", "dynamic"]
SOFT_OPTIONS = ["crisp", "natural", "soft"]
PACK_SETTINGS = [
    ("label", None, "uc.ps.header", None, None),
    ("toggle", "enabled", "uc.enabled", True, None),
    ("dropdown", "profile", "uc.profile", "auto", [("auto", "uc.ps.profile.auto")] +
     [(o, f"uc.profile.{o}") for o in PROFILE_OPTIONS[1:]]),
    ("dropdown", "type", "uc.type", "realistic", [(o, f"uc.type.{o}") for o in TYPE_OPTIONS]),
    ("slider", "amount", "uc.density", 50, (0, 100, 5)),
    ("label", None, "uc.ps.layers", None, None),
    ("slider", "cumulus", "uc.amount.cu", 100, (0, 200, 10)),
    ("slider", "stratus", "uc.amount.st", 100, (0, 200, 10)),
    ("slider", "alto", "uc.amount.ac", 100, (0, 200, 10)),
    ("slider", "cirrus", "uc.amount.ci", 100, (0, 200, 10)),
    ("label", None, "uc.ps.look", None, None),
    ("slider", "size", "uc.size", 100, (50, 200, 5)),
    ("slider", "height", "uc.height", 200, (120, 400, 10)),
    ("slider", "speed", "uc.speed", 20, (0, 100, 5)),
    ("slider", "direction", "uc.dir", 75, (0, 355, 5)),
    ("dropdown", "softness", "uc.softness", "natural", [(o, f"uc.soft.{i}") for i, o in enumerate(SOFT_OPTIONS)]),
    ("slider", "brightness", "uc.bright", 100, (40, 160, 5)),
    ("slider", "warmth", "uc.warm", 60, (0, 100, 5)),
    ("label", None, "uc.ps.perf", None, None),
    ("slider", "sky_depth", "uc.ps.skydepth", 0, (0, 16, 1)),
    ("toggle", "perf_mode", "uc.perf", False, None),
    ("toggle", "auto_quality", "uc.auto", True, None),
    ("label", None, "uc.ps.footer", None, None),
]


def manifest_settings():
    out = []
    for typ, key, text, default, extra in PACK_SETTINGS:
        if typ == "label":
            out.append({"type": "label", "text": text})
            continue
        e = {"type": typ, "name": f"{NS}:{key}", "text": text}
        if typ == "slider":
            e["min"], e["max"], e["step"] = extra
        if typ == "dropdown":
            e["options"] = [{"name": n, "text": t} for n, t in extra]
        e["default"] = default
        out.append(e)
    return out


def bp_manifest():
    v = ".".join(map(str, VERSION))
    return {
        "format_version": 3,
        "header": {
            "name": "pack.name",
            "description": "pack.description",
            "uuid": BP_UUID,
            "version": v,
            "min_engine_version": ".".join(map(str, MIN_ENGINE)),
        },
        "modules": [
            {"type": "data", "uuid": BP_MOD_UUID, "version": v},
            {"type": "script", "language": "javascript", "uuid": BP_SCRIPT_UUID,
             "version": v, "entry": "scripts/main.js"},
        ],
        "dependencies": [
            {"uuid": RP_UUID, "version": v},
            {"module_name": "@minecraft/server", "version": SERVER_VERSION},
            {"module_name": "@minecraft/server-ui", "version": SERVER_UI_VERSION},
        ],
        "settings": manifest_settings(),
        "metadata": {"authors": ["M1X"], "product_type": "addon"},
    }


def bp_entity():
    props = {}
    for name, typ, rng, default in PROPS:
        p = {"type": typ, "default": default, "client_sync": True}
        if rng is not None:
            p["range"] = rng
        props[f"{NS}:{name}"] = p
    return {
        "format_version": "1.26.0",
        "minecraft:entity": {
            "description": {
                "identifier": ENTITY_ID,
                "is_spawnable": False,
                "is_summonable": True,
                "properties": props,
            },
            "components": {
                "minecraft:type_family": {"family": ["ultra_clouds_sky", "inanimate"]},
                "minecraft:collision_box": {"width": 0.01, "height": 0.01},
                "minecraft:physics": {"has_gravity": False, "has_collision": False},
                "minecraft:damage_sensor": {"triggers": [{"cause": "all", "deals_damage": "no"}]},
                "minecraft:dimension_bound": {},
                "minecraft:body_rotation_blocked": {},
                "minecraft:conditional_bandwidth_optimization": {
                    "default_values": {"max_dropped_ticks": 0, "max_optimized_distance": 0.0,
                                       "use_motion_prediction_hints": False}},
            },
            "events": {},
        },
    }


def bp_item():
    """Legacy "Cloud Settings" item of 1.0/1.1.  It is no longer given to
    anybody and is hidden from the creative inventory; the definition stays
    only so that copies in existing worlds are still valid until the script
    removes them from the players' inventories."""
    return {
        "format_version": "1.21.90",
        "minecraft:item": {
            "description": {
                "identifier": ITEM_ID,
                "menu_category": {"category": "none", "is_hidden_in_commands": True},
            },
            "components": {
                "minecraft:icon": "ultra_clouds_settings",
                "minecraft:max_stack_size": 1,
                "minecraft:display_name": {"value": f"item.{ITEM_ID}.name"},
                "minecraft:glint": False,
            },
        },
    }


def generated_ts():
    lines = [
        "// AUTO-GENERATED by tools/gen_pack.py - do not edit by hand.",
        f'export const NS = "{NS}";',
        f'export const ENTITY_ID = "{ENTITY_ID}";',
        f'export const ITEM_ID = "{ITEM_ID}";',
        f'export const VERSION = "{".".join(map(str, VERSION))}";',
        "export interface PropDef { id: string; type: \"bool\" | \"int\" | \"float\"; min: number; max: number; def: number | boolean; }",
        "export const PROPS: Record<string, PropDef> = {",
    ]
    for name, typ, rng, default in PROPS:
        lo, hi = (rng if rng else [0, 1])
        d = "true" if default is True else "false" if default is False else fmt(default)
        lines.append(f'  {name}: {{ id: "{NS}:{name}", type: "{typ}", min: {fmt(lo)}, max: {fmt(hi)}, def: {d} }},')
    lines.append("};")
    lines.append("export interface PackSettingDef { key: string; id: string; type: \"toggle\" | \"slider\" | \"dropdown\"; def: boolean | number | string; min?: number; max?: number; options?: string[]; }")
    lines.append("export const PACK_SETTINGS: PackSettingDef[] = [")
    for typ, key, text, default, extra in PACK_SETTINGS:
        if typ == "label":
            continue
        d = json.dumps(default)
        more = ""
        if typ == "slider":
            more = f", min: {fmt(extra[0])}, max: {fmt(extra[1])}"
        if typ == "dropdown":
            more = f", options: {json.dumps([n for n, t in extra])}"
        lines.append(f'  {{ key: "{key}", id: "{NS}:{key}", type: "{typ}", def: {d}{more} }},')
    lines.append("];")
    return "\n".join(lines) + "\n"


def dump(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(obj, f, indent=2, ensure_ascii=False)
        f.write("\n")


def main():
    clusters = build_field()
    groups, total = order_sprites(clusters)
    geo = build_geometry(groups)
    rcs, rc_order = build_render_controllers(groups)
    anims, anim_names = build_animations(clusters, groups)
    entity = build_client_entity(clusters, groups, total, anim_names, rc_order)

    dump(os.path.join(RP, "manifest.json"), rp_manifest())
    dump(os.path.join(RP, "models", "entity", "ultra_clouds_sky.geo.json"), geo)
    dump(os.path.join(RP, "render_controllers", "ultra_clouds_sky.render_controllers.json"), rcs)
    dump(os.path.join(RP, "animations", "ultra_clouds_sky.animation.json"), anims)
    dump(os.path.join(RP, "entity", "ultra_clouds_sky.entity.json"), entity)
    dump(os.path.join(RP, "textures", "item_texture.json"), {
        "resource_pack_name": "ultra_clouds",
        "texture_name": "atlas.items",
        "texture_data": {"ultra_clouds_settings": {"textures": "textures/ultra_clouds/icon_settings"}},
    })
    ui = json.load(open(os.path.join(ROOT, "tools", "ui_strings.json"), encoding="utf-8"))
    write_lang(RP, LANG_RP, {"en_US": {k: v[0] for k, v in ui.items()},
                             "ru_RU": {k: v[1] for k, v in ui.items()}})
    os.makedirs(os.path.join(RP, "subpacks", "keep_vanilla"), exist_ok=True)
    with open(os.path.join(RP, "subpacks", "keep_vanilla", "README.txt"), "w") as f:
        f.write("This sub-pack intentionally changes nothing: the vanilla cloud layer stays.\n"
                "Turn it off with Settings > Video > Render Clouds if you only want Ultra Clouds.\n")

    dump(os.path.join(BP, "manifest.json"), bp_manifest())
    dump(os.path.join(BP, "entities", "ultra_clouds_sky.json"), bp_entity())
    dump(os.path.join(BP, "items", "cloud_settings.json"), bp_item())
    # the pack settings screen reads its texts from the behavior pack
    write_lang(BP, LANG_BP, {"en_US": {k: v[0] for k, v in ui.items()},
                             "ru_RU": {k: v[1] for k, v in ui.items()}})
    with open(GEN_TS, "w") as f:
        f.write(generated_ts())

    n_sprites = sum(len(c.sprites) for c in clusters)
    print(f"clusters={len(clusters)} sprites={n_sprites} slots={total} bones={len(geo['minecraft:geometry'][0]['bones'])}")
    if "-v" not in os.sys.argv:
        return
    for t in range(4):
        for d in range(4):
            cnt = sum(1 for c in clusters for s in c.sprites if c.tier <= t and s.rank <= d)
            ccount = sum(1 for c in clusters if c.tier <= t)
            print(f"  tier<={t} detail<={d}: clusters={ccount} sprites={cnt}")


if __name__ == "__main__":
    main()
