#!/usr/bin/env python3
"""Ultra Clouds - offline cloud sprite generator.

Renders every cloud sprite of the Ultra Clouds atlas with a small volumetric
ray-marcher (numpy only).  The game itself never ray-marches anything: Bedrock
add-ons cannot ship shaders, so the volumetric look is baked here into
impostor sprites that the resource pack later projects onto the sky.

Outputs (relative to the resource pack root):
  textures/ultra_clouds/atlas_natural.png   1024x1024, 4x4 cells of 256 px
  textures/ultra_clouds/atlas_soft.png      same layout, softer edges
  textures/ultra_clouds/icon_settings.png   item icon (32x32)
  pack_icon.png                              resource pack icon (256x256)
plus the "lite" sub-pack (512 px atlases) and the transparent clouds.png
used to hide the vanilla clouds.

Cell layout (row-major, must match tools/gen_pack.py: CELLS):
  0-5  cumulus puffs         6-7  cumulus bases (seen slightly from below)
  8    stratus sheet          9    overcast slab (dense stratus)
  10-11 cirrus streaks
  12-13 altocumulus patches  14 cumulonimbus tower   15 wisp / scud
"""
import os
import sys
import time

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RP = os.path.join(ROOT, "packs", "UltraClouds_RP")
BP = os.path.join(ROOT, "packs", "UltraClouds_BP")

CELL = 256          # atlas cell size in pixels
GRID = 4            # 4x4 cells
CONTENT = 224       # rendered area inside a cell (16 px transparent margin)
DEPTH = 96          # ray-march samples along the view axis

# --------------------------------------------------------------------------
# Noise
# --------------------------------------------------------------------------

class Noise:
    """Seeded 3D/2D value noise with quintic interpolation."""

    def __init__(self, seed):
        rng = np.random.default_rng(seed)
        self.perm = np.concatenate([rng.permutation(256)] * 2).astype(np.int32)
        self.vals = rng.random(256).astype(np.float32)

    def _hash(self, ix, iy, iz):
        p = self.perm
        return self.vals[p[(p[(p[ix & 255] + iy) & 255] + iz) & 255]]

    def noise3(self, x, y, z):
        xi = np.floor(x).astype(np.int32)
        yi = np.floor(y).astype(np.int32)
        zi = np.floor(z).astype(np.int32)
        xf = (x - xi).astype(np.float32)
        yf = (y - yi).astype(np.float32)
        zf = (z - zi).astype(np.float32)
        u = xf * xf * xf * (xf * (xf * 6 - 15) + 10)
        v = yf * yf * yf * (yf * (yf * 6 - 15) + 10)
        w = zf * zf * zf * (zf * (zf * 6 - 15) + 10)
        h = self._hash
        x0 = h(xi, yi, zi) + u * (h(xi + 1, yi, zi) - h(xi, yi, zi))
        x1 = h(xi, yi + 1, zi) + u * (h(xi + 1, yi + 1, zi) - h(xi, yi + 1, zi))
        x2 = h(xi, yi, zi + 1) + u * (h(xi + 1, yi, zi + 1) - h(xi, yi, zi + 1))
        x3 = h(xi, yi + 1, zi + 1) + u * (h(xi + 1, yi + 1, zi + 1) - h(xi, yi + 1, zi + 1))
        y0 = x0 + v * (x1 - x0)
        y1 = x2 + v * (x3 - x2)
        return y0 + w * (y1 - y0)

    def fbm3(self, x, y, z, octaves=5, lac=2.03, gain=0.5, billow=False):
        total = np.zeros_like(x, dtype=np.float32)
        amp, norm, f = 1.0, 0.0, 1.0
        for o in range(octaves):
            n = self.noise3(x * f + o * 17.31, y * f + o * 9.17, z * f + o * 3.71)
            if billow:
                n = 1.0 - np.abs(n * 2.0 - 1.0)
            total += amp * n
            norm += amp
            amp *= gain
            f *= lac
        return total / norm

    def fbm2(self, x, y, octaves=6, lac=2.0, gain=0.5, billow=False):
        return self.fbm3(x, y, np.zeros_like(x) + 0.37, octaves, lac, gain, billow)


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


# --------------------------------------------------------------------------
# Image helpers
# --------------------------------------------------------------------------

def gaussian_blur(img, sigma):
    """Separable gaussian blur over the first two axes (FFT based)."""
    if sigma <= 0:
        return img
    h, w = img.shape[:2]
    r = int(3 * sigma + 1)
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
    k /= k.sum()
    out = img.astype(np.float32)
    pad = [(r, r), (r, r)] + [(0, 0)] * (img.ndim - 2)
    out = np.pad(out, pad, mode="edge")
    # rows
    tmp = np.zeros_like(out)
    for i, kv in enumerate(k):
        tmp += kv * np.roll(out, i - r, axis=0)
    out = np.zeros_like(tmp)
    for i, kv in enumerate(k):
        out += kv * np.roll(tmp, i - r, axis=1)
    return out[r:r + h, r:r + w]


def border_mask(n, margin):
    """1 inside, fading to 0 within `margin` px of each border."""
    t = np.arange(n, dtype=np.float32)
    d = np.minimum(t, n - 1 - t)
    m = smoothstep(0.0, float(margin), d)
    return np.outer(m, m)


def bleed_colors(rgb, alpha):
    """Fill colour of transparent pixels from nearby opaque ones.

    Prevents dark fringes when the GPU filters / mip-maps straight-alpha
    textures."""
    acc = rgb * alpha[..., None]
    out = rgb.copy()
    need = (alpha < 0.05)[..., None]
    # coarse to fine: local fills override the wide ones where they exist
    for sigma in (40, 16, 6, 2):
        bc = gaussian_blur(acc, sigma)
        bw = gaussian_blur(alpha, sigma)
        fill = bc / np.maximum(bw[..., None], 1e-6)
        weight = np.clip(bw * 8.0, 0, 1)[..., None] * need
        out = out * (1 - weight) + fill * weight
    return out


# --------------------------------------------------------------------------
# Volumetric renderer
# --------------------------------------------------------------------------

SUN = np.array([1.00, 0.985, 0.95], np.float32)
SKY = np.array([0.56, 0.64, 0.78], np.float32)
BOUNCE = np.array([0.42, 0.40, 0.38], np.float32)


def raymarch(density, sigma_view=11.0, sigma_light=7.5, ambient=0.55,
             side_light=0.25):
    """density: (H, W, D) array, y down rows (row 0 = top), z = view depth
    (index 0 nearest to the camera).  Returns straight-alpha RGBA float."""
    h, w, d = density.shape
    dy = 2.0 / h
    dz = 1.0 / d
    rho = density.astype(np.float32)
    # optical depth towards the sun (sun high, slightly right and in front)
    tau_top = np.cumsum(rho, axis=0) * dy - rho * dy * 0.5
    tau_side = (np.cumsum(rho[:, ::-1, :], axis=1)[:, ::-1, :]) * (2.0 / w)
    tau_front = np.cumsum(rho, axis=2) * dz
    tau_sun = 0.78 * tau_top + side_light * tau_side + 0.12 * tau_front
    # multi-scatter approximation (several octaves of softened extinction)
    light = np.zeros_like(rho)
    a, b = 1.0, 1.0
    for _ in range(3):
        light += b * np.exp(-sigma_light * a * tau_sun)
        a *= 0.45
        b *= 0.42
    light /= (1.0 + 0.42 + 0.42 ** 2)
    # "powder" darkening of thin outer shell facing away from the sun
    powder = 1.0 - 0.35 * np.exp(-tau_top * 18.0) * (1.0 - np.exp(-rho * 4.0))
    sky_vis = np.exp(-tau_top * 3.0)
    tau_bottom = (np.cumsum(rho[::-1], axis=0)[::-1]) * dy
    bounce = np.exp(-tau_bottom * 4.0)
    radiance = (light[..., None] * powder[..., None] * SUN
                + ambient * (0.22 + 0.78 * sky_vis[..., None]) * SKY
                + 0.18 * bounce[..., None] * BOUNCE)
    ext = 1.0 - np.exp(-sigma_view * rho * dz * 8.0)
    trans = np.cumprod(1.0 - ext, axis=2)
    trans_before = np.concatenate([np.ones((h, w, 1), np.float32), trans[:, :, :-1]], axis=2)
    contrib = trans_before * ext
    col = np.sum(contrib[..., None] * radiance, axis=2)
    alpha = 1.0 - trans[:, :, -1]
    rgb = col / np.maximum(alpha[..., None], 1e-5)
    return rgb, alpha


def grid3(h, w, d, zext=0.6):
    ys = np.linspace(1.0, -1.0, h, dtype=np.float32)       # top row = +y
    xs = np.linspace(-1.0, 1.0, w, dtype=np.float32)
    zs = np.linspace(-zext, zext, d, dtype=np.float32)
    return np.meshgrid(ys, xs, zs, indexing="ij")          # Y, X, Z


def metaballs(Y, X, Z, balls, k=10.0):
    """Smooth union of ellipsoids -> signed 'inside-ness' (positive inside)."""
    acc = np.zeros_like(X)
    for (cx, cy, cz, rx, ry, rz) in balls:
        dist = np.sqrt(((X - cx) / rx) ** 2 + ((Y - cy) / ry) ** 2 + ((Z - cz) / rz) ** 2)
        acc += np.exp(-k * (dist - 1.0))
    return np.log(np.maximum(acc, 1e-12)) / k        # ~ 1 - dist of nearest ball


def _lerp_axis(a, n, axis):
    """Linear resize of one axis of `a` to length n (align corners)."""
    m = a.shape[axis]
    pos = np.linspace(0, m - 1, n, dtype=np.float32)
    i0 = np.floor(pos).astype(np.int32)
    i1 = np.minimum(i0 + 1, m - 1)
    t = (pos - i0).reshape([-1 if d == axis else 1 for d in range(a.ndim)])
    return np.take(a, i0, axis=axis) * (1 - t) + np.take(a, i1, axis=axis) * t


def metaballs_coarse(shape_full, balls, k, zext, warp=None):
    """Evaluate the (smooth) metaball field on a coarse grid and upsample.

    The field is smooth, so a 1/2 resolution grid is visually identical and
    roughly 8x cheaper.  `warp` optionally displaces the lookup position."""
    h, w, d = shape_full
    hc, wc, dc = h // 2, w // 2, max(8, d // 2)
    Yc, Xc, Zc = grid3(hc, wc, dc, zext)
    if warp is not None:
        wy, wx, wz = warp(Yc, Xc, Zc)
        Yc, Xc, Zc = Yc + wy, Xc + wx, Zc + wz
    f = metaballs(Yc, Xc, Zc, balls, k)
    f = _lerp_axis(f, h, 0)
    f = _lerp_axis(f, w, 1)
    f = _lerp_axis(f, d, 2)
    return f.astype(np.float32)


def _surface_bumps(rng, centre, radii, count, rmin, rmax, upper_only=True):
    """Random spheres sitting on the surface of an ellipsoid (cauliflower)."""
    cx, cy, cz = centre
    rx, ry, rz = radii
    out = []
    for _ in range(count):
        theta = rng.uniform(0, 2 * np.pi)
        cphi = rng.uniform(0.05 if upper_only else -0.6, 1.0)     # cos of polar angle
        sphi = np.sqrt(1 - cphi * cphi)
        px = cx + rx * sphi * np.cos(theta) * 0.92
        py = cy + ry * cphi * 0.92
        pz = cz + rz * sphi * np.sin(theta) * 0.92
        r = rng.uniform(rmin, rmax)
        out.append((px, py, pz, r, r, r))
    return out


def cumulus_density(noise, rng, kind="puff", res=176):
    h = w = res
    zext = 0.6
    Y, X, Z = grid3(h, w, 72, zext)
    balls = []
    if kind == "puff":
        base_y = -0.45 + rng.uniform(-0.04, 0.04)
        width = rng.uniform(0.55, 0.8)
        height = rng.uniform(0.55, 0.95)
        domes = []
        for i in range(rng.integers(2, 5)):
            dx = rng.uniform(-width, width) * 0.6
            rx = rng.uniform(0.26, 0.4) * (1.1 - abs(dx) * 0.5)
            ry = rx * rng.uniform(0.9, 1.25) * height / 0.75
            cy = base_y + ry * 0.75 - abs(dx) * 0.25
            domes.append(((dx, cy, rng.uniform(-0.1, 0.1)), (rx, ry, rx * 0.8)))
        for (c, r) in domes:
            balls.append((*c, *r))
            balls += _surface_bumps(rng, c, r, 10, 0.1, 0.19)
            balls += _surface_bumps(rng, c, r, 18, 0.05, 0.1)
        span = max(abs(c[0]) + r[0] for (c, r) in domes)
        bw = min(width, span) * 0.82
        balls.append((0.0, base_y + 0.12, 0.0, bw, 0.13, 0.4))
        balls += _surface_bumps(rng, (0.0, base_y + 0.12, 0.0), (bw, 0.13, 0.4), 7, 0.07, 0.12)
    elif kind == "tower":
        base_y = -0.75
        for i in range(3):                                   # broad lower body
            c = (rng.uniform(-0.3, 0.3), base_y + 0.26, rng.uniform(-0.08, 0.08))
            r = (rng.uniform(0.28, 0.36), 0.27, 0.3)
            balls.append((*c, *r))
            balls += _surface_bumps(rng, c, r, 8, 0.07, 0.13)
        for i in range(4):                                   # rising towers
            t = i / 3.0
            c = (rng.uniform(-0.1, 0.1) + 0.05 * t, base_y + 0.55 + t * 0.55, rng.uniform(-0.06, 0.06))
            r = (0.42 - 0.08 * t, 0.22, 0.32)
            balls.append((*c, *r))
            balls += _surface_bumps(rng, c, r, 9, 0.06, 0.12, upper_only=False)
        for i in range(10):                                  # anvil, widest part
            ax = rng.uniform(-0.6, 0.75)
            c = (ax, 0.6 + rng.uniform(-0.03, 0.03) - 0.07 * abs(ax), rng.uniform(-0.15, 0.15))
            r = (rng.uniform(0.2, 0.3), rng.uniform(0.11, 0.15), rng.uniform(0.22, 0.3))
            balls.append((*c, *r))
            balls += _surface_bumps(rng, c, r, 3, 0.05, 0.09, upper_only=False)
        balls.append((0.1, 0.52, 0.0, 0.5, 0.16, 0.34))
    elif kind == "wisp":
        base_y = -0.45
        for i in range(8):
            cx = rng.uniform(-0.6, 0.6)
            r = rng.uniform(0.12, 0.22)
            c = (cx, rng.uniform(-0.25, 0.05) - 0.2 * abs(cx), rng.uniform(-0.1, 0.1))
            balls.append((*c, r * 1.5, r, r * 1.1))
            balls += _surface_bumps(rng, c, (r * 1.5, r, r * 1.1), 4, 0.04, 0.08)
    off = rng.uniform(0, 100, 3)

    def warp(Yc, Xc, Zc):
        a = 0.07
        return (a * (noise.fbm3(Xc * 3 + off[0], Yc * 3, Zc * 3, octaves=3) - 0.5),
                a * (noise.fbm3(Xc * 3, Yc * 3 + off[1], Zc * 3, octaves=3) - 0.5),
                a * (noise.fbm3(Xc * 3, Yc * 3, Zc * 3 + off[2], octaves=3) - 0.5))

    shape = metaballs_coarse((h, w, 72), balls, 8.0, zext, warp)
    billow = noise.fbm3(X * 5.0 + off[0], Y * 5.0 + off[1], Z * 5.0 + off[2], octaves=4, billow=True)
    fine = noise.fbm3(X * 15 + off[1], Y * 15 + off[2], Z * 15 + off[0], octaves=2)
    if kind == "wisp":
        edge = 1.0 - smoothstep(0.0, 0.15, shape)
        dens = shape + (0.16 + 0.3 * edge) * (billow - 0.62) + 0.14 * (fine - 0.5)
        dens = smoothstep(-0.02, 0.18, dens)
        dens *= smoothstep(base_y - 0.03, base_y + 0.06, Y)
    else:
        # erosion is strongest at the boundary -> crisp cores, wispy fringes
        edge = 1.0 - smoothstep(0.0, 0.18, shape)
        dens = shape + (0.08 + 0.12 * edge) * (billow - 0.62) + (0.03 + 0.07 * edge) * (fine - 0.5)
        dens = smoothstep(-0.05, 0.17, dens) * (0.5 + 0.5 * smoothstep(0.0, 0.25, shape))
        if kind == "tower":
            fib = noise.fbm3(X * 2.0 + off[2], Y * 16.0, Z * 2.0, octaves=3)
            top = smoothstep(0.42, 0.55, Y)
            dens *= 1.0 - top * 0.45 * (1.0 - fib)
        # flat-ish base (condensation level) with a slightly ragged edge
        ragged = 0.05 * (noise.fbm3(X * 7 + 3.1, Z * 7 + 1.7, Y * 0 + 0.5, octaves=3) - 0.5)
        dens *= smoothstep(base_y - 0.03 + ragged, base_y + 0.05 + ragged, Y)
    # rounded sides: the cloud must never touch the volume bounds (flat cuts)
    dens *= 1.0 - smoothstep(0.84, 0.98, np.abs(X) + 0.1 * (billow - 0.5))
    return dens.astype(np.float32)


def upscale(rgb, alpha, size=CONTENT):
    img = to_image(rgb, alpha)
    pm = Image.fromarray((np.clip(rgb * alpha[..., None], 0, 1) * 255 + 0.5).astype(np.uint8), "RGB")
    a = img.getchannel("A").resize((size, size), Image.LANCZOS)
    pm = pm.resize((size, size), Image.LANCZOS)
    a = np.asarray(a).astype(np.float32) / 255.0
    pm = np.asarray(pm).astype(np.float32) / 255.0
    return pm / np.maximum(a[..., None], 1e-3), a


def cloud_base_density(noise, rng, res=CONTENT):
    """Wide flat cumulus base seen obliquely from below."""
    h = w = res
    Y, X, Z = grid3(h, w, DEPTH, zext=0.8)
    shear = 0.55
    Ys = Y + shear * Z          # oblique view: reveals the flat underside
    balls = []
    for i in range(rng.integers(6, 10)):
        cx = rng.uniform(-0.5, 0.5)
        cz = rng.uniform(-0.45, 0.45)
        r = rng.uniform(0.2, 0.3)
        balls.append((cx, -0.05 + rng.uniform(0, 0.25), cz, r * 1.35, r, r * 1.25))
    balls.append((0.0, -0.1, 0.0, 0.72, 0.18, 0.62))
    shape = metaballs(Ys, X, Z, balls, k=8.0)
    off = rng.uniform(0, 100, 3)
    billow = noise.fbm3(X * 2.8 + off[0], Ys * 2.8 + off[1], Z * 2.8 + off[2], octaves=5, billow=True)
    dens = shape + 0.3 * (billow - 0.62)
    dens = smoothstep(-0.04, 0.2, dens)
    dens *= smoothstep(-0.28, -0.18, Ys)
    # rounded sides: the cloud must never touch the volume bounds (flat cuts)
    edge = np.abs(X) + 0.12 * (billow - 0.5)
    dens *= 1.0 - smoothstep(0.78, 0.95, edge)
    return dens.astype(np.float32)


def render_volume(dens, sigma_view=11.0, sigma_light=7.5, ambient=0.55, side=0.25):
    rgb, alpha = raymarch(dens, sigma_view, sigma_light, ambient, side)
    if rgb.shape[0] != CONTENT:
        rgb, alpha = upscale(rgb, alpha)
    return rgb, alpha


# --------------------------------------------------------------------------
# 2D layer sprites (stratus, cirrus, altocumulus)
# --------------------------------------------------------------------------

def coords2(res=CONTENT):
    ys = np.linspace(-1.0, 1.0, res, dtype=np.float32)
    xs = np.linspace(-1.0, 1.0, res, dtype=np.float32)
    return np.meshgrid(ys, xs, indexing="ij")


def _relief_shade(H, strength=3.0):
    """Top-lit shading of a 2D thickness/height field (image row 0 = up)."""
    gy = np.gradient(H, axis=0)
    gx = np.gradient(H, axis=1)
    lit = -gy * strength * H.shape[0] / 64.0 - 0.25 * gx * strength * H.shape[1] / 64.0
    return np.clip(0.5 + lit, 0.0, 1.0)


def _blob_mask(noise, X, Y, off, rx, ry, rough=0.45, freq=1.6):
    warp = noise.fbm2(X * freq + off[0], Y * freq + off[1], octaves=5) - 0.5
    r = np.sqrt((X / rx) ** 2 + (Y / ry) ** 2) + rough * warp
    return 1.0 - smoothstep(0.55, 1.0, r)


def stratus_sprite(noise, rng):
    """Piece of a stratocumulus deck: a wide, flat sheet made of soft,
    elongated rolls with gently darker bases.  The inside stays filled (no
    holes); gaps between rolls open only towards the ragged border."""
    Y, X = coords2()
    off = rng.uniform(0, 100, 4)
    w1 = noise.fbm2(X * 1.3 + off[0], Y * 1.3 + off[1], octaves=5) - 0.5
    w2 = noise.fbm2(X * 3.4 + off[1], Y * 3.4 + off[2], octaves=4) - 0.5
    r = np.sqrt((X / 0.95) ** 2 + (Y / 0.6) ** 2) + 0.45 * w1 + 0.18 * w2
    mask = 1.0 - smoothstep(0.6, 0.98, r)
    wx = X + 0.06 * (noise.fbm2(X * 4 + off[2], Y * 4, octaves=3) - 0.5)
    wy = Y + 0.06 * (noise.fbm2(X * 4, Y * 4 + off[3], octaves=3) - 0.5)
    field = np.zeros_like(X)
    rows = np.linspace(-0.5, 0.5, 5)
    for ry0 in rows:
        x = -1.05 + rng.uniform(0, 0.2)
        while x < 1.05:
            rx = rng.uniform(0.2, 0.32)
            ry = rng.uniform(0.11, 0.16)
            cy = ry0 + rng.uniform(-0.06, 0.06)
            d2 = ((wx - x) / rx) ** 2 + ((wy - cy) / ry) ** 2
            field += rng.uniform(0.75, 1.0) * np.exp(-d2 * 1.4)
            x += rx * rng.uniform(1.1, 1.5)
    field = np.clip(field, 0, 1.2)
    ero = noise.fbm2(X * 8 + off[1], Y * 8 + off[0], octaves=3)
    edge = smoothstep(0.25, 0.85, r)                    # 0 inside, 1 at the border
    thick = mask * (0.62 * (1 - edge) + field * (0.55 + 0.5 * edge)) * (0.9 + 0.25 * (ero - 0.5))
    thick = gaussian_blur(thick, 1.4)
    alpha = np.clip(1.0 - np.exp(-thick * 4.2), 0, 1)
    shade = _relief_shade(gaussian_blur(field * mask, 2.2), 1.9)
    big = noise.fbm2(X * 1.1 + off[1], Y * 1.6 + off[0], octaves=3)
    tone = 0.66 + 0.34 * shade + 0.06 * (big - 0.5)
    tone -= 0.08 * smoothstep(-0.2, 0.7, Y)            # darker underside of the deck
    rgb = np.stack([tone * 0.975, tone * 0.99, tone * 1.03], -1)
    return np.clip(rgb, 0, 1), np.clip(alpha * 0.97, 0, 1)


def slab_sprite(noise, rng):
    """Dense overcast slab: an almost fully opaque, roughly rectangular piece
    of a stratus deck with lumpy rolls and a soft, irregular border.  Used by
    the overcast ceiling, where neighbouring pieces must close the sky with
    little overlap (fewer, smaller quads = less overdraw on phones)."""
    Y, X = coords2()
    off = rng.uniform(0, 100, 4)
    w1 = noise.fbm2(X * 1.6 + off[0], Y * 1.6 + off[1], octaves=5) - 0.5
    w2 = noise.fbm2(X * 4.0 + off[1], Y * 4.0 + off[2], octaves=4) - 0.5
    r = (np.abs(X / 0.9) ** 3 + np.abs(Y / 0.86) ** 3) ** (1 / 3) + 0.3 * w1 + 0.1 * w2
    mask = 1.0 - smoothstep(0.78, 0.99, r)
    rolls = noise.fbm2(X * 2.4 + w1 * 0.9 + off[2], Y * 3.8 + off[3], octaves=5, billow=True)
    big = noise.fbm2(X * 1.2 + off[1], Y * 1.5 + off[0], octaves=3)
    thick = mask * (0.6 + 0.4 * rolls) * (0.8 + 0.4 * big)
    thick = gaussian_blur(thick, 1.2)
    alpha = np.clip(1.0 - np.exp(-thick * 7.0), 0, 1)
    shade = _relief_shade(gaussian_blur(thick, 2.5), 1.4)
    tone = 0.8 + 0.2 * (shade - 0.5) + 0.06 * (big - 0.5)
    # towards the border the tone settles on the mean, so the seams between
    # overlapping slabs of the ceiling do not show
    edge = smoothstep(0.45, 0.85, r)
    tone = tone * (1 - edge) + 0.8 * edge
    rgb = np.stack([tone * 0.975, tone * 0.99, tone * 1.03], -1)
    return np.clip(rgb, 0, 1), alpha


def cirrus_sprite(noise, rng, hooked=False):
    """Long fibrous cirrus streak (wide aspect after cropping)."""
    ys = np.linspace(-1.0, 1.0, CONTENT // 2, dtype=np.float32)
    xs = np.linspace(-1.0, 1.0, CONTENT, dtype=np.float32)
    Y, X = np.meshgrid(ys, xs, indexing="ij")
    off = rng.uniform(0, 100, 2)
    bend = 0.18 * np.sin(X * rng.uniform(1.0, 1.8) + off[0]) + (0.35 * (X + 1) ** 2 * 0.25 if hooked else 0.0)
    Yb = Y - bend
    fib = noise.fbm2(X * 1.1 + off[0], Yb * 9.0 + off[1], octaves=6)
    streak = noise.fbm2(X * 0.8 + off[1], Yb * 2.2 + off[0], octaves=4)
    band = np.exp(-(Yb / 0.55) ** 2)
    ends = 1.0 - smoothstep(0.45, 0.98, np.abs(X) + 0.35 * (streak - 0.5))
    alpha = smoothstep(0.38, 0.74, fib * 0.6 + streak * 0.55) * band * ends
    if hooked:
        tuft = np.exp(-(((X - 0.7) / 0.18) ** 2 + ((Yb + 0.25) / 0.35) ** 2))
        alpha = np.maximum(alpha, tuft * smoothstep(0.3, 0.7, fib) * 0.85)
    alpha = np.clip(alpha * 0.85, 0, 1)
    shade = 0.93 + 0.07 * (fib - 0.5)
    rgb = np.stack([shade * 0.98, shade * 0.99, shade * 1.03], -1)
    return np.clip(rgb, 0, 1), alpha


def alto_sprite(noise, rng):
    """Altocumulus field: irregular, partly merged cloudlets with sky gaps."""
    Y, X = coords2()
    off = rng.uniform(0, 100, 4)
    w1 = noise.fbm2(X * 1.2 + off[0], Y * 1.2 + off[1], octaves=4) - 0.5
    w2 = noise.fbm2(X * 3.1 + off[2], Y * 3.1 + off[3], octaves=3) - 0.5
    r = np.sqrt((X / 0.95) ** 2 + (Y / 0.72) ** 2) + 0.85 * w1 + 0.25 * w2
    mask = 1.0 - smoothstep(0.3, 0.9, r)
    wx = X + 0.05 * (noise.fbm2(X * 5 + off[2], Y * 5, octaves=3) - 0.5)
    wy = Y + 0.05 * (noise.fbm2(X * 5, Y * 5 + off[3], octaves=3) - 0.5)
    pts = []
    for _ in range(2400):
        if len(pts) >= 120:
            break
        c = (rng.uniform(-1, 1), rng.uniform(-1, 1))
        if all((c[0] - p[0]) ** 2 / 1.6 + (c[1] - p[1]) ** 2 > 0.012 for p in pts):
            pts.append(c)
    field = np.zeros_like(X)
    for (px, py) in pts:
        rx = rng.uniform(0.075, 0.13)
        ry = rx * rng.uniform(0.6, 0.85)
        d2 = ((wx - px) / rx) ** 2 + ((wy - py) / ry) ** 2
        field = np.maximum(field, np.exp(-d2 * 1.2))
    ero = noise.fbm2(X * 12 + off[1], Y * 12 + off[0], octaves=3)
    cl = smoothstep(0.22, 0.62, field * (0.8 + 0.5 * (ero - 0.5))) * mask
    thick = gaussian_blur(cl, 1.1)
    alpha = np.clip(1.0 - np.exp(-thick * 3.4), 0, 1)
    shade = _relief_shade(gaussian_blur(thick, 2.4), 2.3)
    tone = 0.68 + 0.34 * shade
    rgb = np.stack([tone * 0.98, tone * 0.99, tone * 1.035], -1)
    return np.clip(rgb, 0, 1), np.clip(alpha * 0.94, 0, 1)


# --------------------------------------------------------------------------
# Atlas assembly
# --------------------------------------------------------------------------

def finish_cell(rgb, alpha, content=CONTENT, cell=CELL, normalize=True):
    """Normalise brightness, crop to the visible cloud, stretch it to fill the
    cell (the true aspect ratio is returned and restored by the quad)."""
    if normalize:
        sel = alpha > 0.35
        if sel.any():
            lum = rgb.mean(-1)
            ref = np.percentile(lum[sel], 98.5)
            rgb = rgb / max(ref, 1e-3) * 0.985
    rgb = np.clip(rgb, 0, 1)
    ys, xs = np.nonzero(alpha > 0.015)
    y0, y1 = max(0, ys.min() - 2), min(alpha.shape[0], ys.max() + 3)
    x0, x1 = max(0, xs.min() - 2), min(alpha.shape[1], xs.max() + 3)
    aspect = (x1 - x0) / float(y1 - y0)
    crop_rgb, crop_a = rgb[y0:y1, x0:x1], alpha[y0:y1, x0:x1]
    pm = Image.fromarray((np.clip(crop_rgb * crop_a[..., None], 0, 1) * 255 + 0.5).astype(np.uint8), "RGB")
    am = Image.fromarray((np.clip(crop_a, 0, 1) * 255 + 0.5).astype(np.uint8), "L")
    # bilinear, not Lanczos: Lanczos rings at the steep core edges, which
    # makes edge texels brighter than the inside (light seams in the sky)
    pm = np.asarray(pm.resize((content, content), Image.BILINEAR)).astype(np.float32) / 255.0
    am = np.asarray(am.resize((content, content), Image.BILINEAR)).astype(np.float32) / 255.0
    rgb = pm / np.maximum(am[..., None], 1e-3)
    pad = (cell - content) // 2
    full_rgb = np.zeros((cell, cell, 3), np.float32)
    full_a = np.zeros((cell, cell), np.float32)
    full_rgb[pad:pad + content, pad:pad + content] = np.clip(rgb, 0, 1)
    full_a[pad:pad + content, pad:pad + content] = am
    full_a *= border_mask(cell, pad + 4)
    full_rgb = bleed_colors(full_rgb, full_a)
    return full_rgb, full_a, float(aspect)


def soften(rgb, alpha, sigma=3.2, gamma=1.25, contrast=0.8):
    pm = rgb * alpha[..., None]
    pm = gaussian_blur(pm, sigma)
    a = gaussian_blur(alpha, sigma)
    rgb2 = pm / np.maximum(a[..., None], 1e-5)
    mean = (rgb2 * a[..., None]).sum((0, 1)) / max(a.sum(), 1e-5)
    rgb2 = mean + (rgb2 - mean) * contrast
    a2 = np.clip(a, 0, 1) ** gamma * 0.97
    rgb2 = bleed_colors(np.clip(rgb2, 0, 1), a2)
    return rgb2, a2


def core_profile(alpha, q_core, halo_max, width=0.12):
    """Give a layer cloud an opaque core with a faint halo.

    The pack draws every cloud twice: an alpha-tested core pass (robust depth,
    no invisible rectangles) and a blended halo pass.  The texture therefore
    needs a dense inside (alpha ~1) that turns steeply into a soft halo whose
    alpha stays below 0.5 (the alpha-test threshold, whatever the material
    colour does to it)."""
    nz = alpha[alpha > 0.02]
    hi = float(np.quantile(nz, 1.0 - q_core))
    lo = max(hi - width, 0.05)
    out = np.where(alpha <= lo, alpha / lo * halo_max,
                   halo_max + (1.0 - halo_max) * smoothstep(lo, hi, alpha))
    return np.clip(out, 0, 1).astype(np.float32)


def to_image(rgb, alpha):
    arr = np.concatenate([np.clip(rgb, 0, 1), np.clip(alpha, 0, 1)[..., None]], -1)
    return Image.fromarray((arr * 255.0 + 0.5).astype(np.uint8), "RGBA")


# (kind, seed offset) for every cell, in atlas order
CELL_JOBS = [("puff", i) for i in range(6)] + [("base", 0), ("base", 1),
             ("stratus", 0), ("slab", 0), ("cirrus", 0), ("cirrus_hook", 0),
             ("alto", 0), ("alto", 1), ("tower", 0), ("wisp", 0)]


def render_cell(job, seed=20261020):
    kind, k = job
    s = seed + 7919 * (CELL_JOBS.index(job) + 1)
    rng = np.random.default_rng(s)
    noise = Noise(s)
    if kind == "puff":
        rgb, a = render_volume(cumulus_density(noise, rng, "puff"))
    elif kind == "base":
        rgb, a = render_volume(cloud_base_density(noise, rng), sigma_view=10.0,
                               sigma_light=5.5, ambient=0.85, side=0.15)
        # skylight and light scattered from the ground: a base seen from
        # below is grey, not as dark as the self-shadowed volume renders it
        rgb = 0.18 + 0.82 * rgb
    elif kind == "tower":
        rgb, a = render_volume(cumulus_density(noise, rng, "tower"), sigma_view=13.0,
                               sigma_light=7.0, ambient=0.6, side=0.3)
    elif kind == "wisp":
        rgb, a = render_volume(cumulus_density(noise, rng, "wisp"), sigma_view=9.0,
                               sigma_light=5.0, ambient=0.7)
    elif kind == "stratus":
        rgb, a = stratus_sprite(noise, rng)
        a = core_profile(a, 0.55, 0.42)
    elif kind == "slab":
        rgb, a = slab_sprite(noise, rng)
        a = core_profile(a, 0.85, 0.42)
        c_rgb, c_a, aspect = finish_cell(rgb, a)
        # edge texels take the colour of the dense inside: no light seams
        # where the slabs of the overcast ceiling overlap
        c_rgb = bleed_colors(c_rgb, (c_a >= 0.985).astype(np.float32))
        return c_rgb, c_a, aspect
    elif kind == "cirrus":
        return finish_cell(*cirrus_sprite(noise, rng, hooked=False), normalize=False)
    elif kind == "cirrus_hook":
        return finish_cell(*cirrus_sprite(noise, rng, hooked=True), normalize=False)
    elif kind == "alto":
        rgb, a = alto_sprite(noise, rng)
        a = core_profile(a, 0.5, 0.42)
    else:
        raise ValueError(kind)
    return finish_cell(rgb, a)


def build_cells():
    from multiprocessing import Pool
    t0 = time.time()
    with Pool(min(4, os.cpu_count() or 1)) as pool:
        cells = pool.map(render_cell, CELL_JOBS)
    print(f"  rendered {len(cells)} cells in {time.time() - t0:.1f}s", flush=True)
    return cells


def assemble(cells, variant="natural"):
    size = CELL * GRID
    rgb = np.zeros((size, size, 3), np.float32)
    alpha = np.zeros((size, size), np.float32)
    for idx, (c_rgb, c_a, _aspect) in enumerate(cells):
        if variant == "soft":
            c_rgb, c_a = soften(c_rgb, c_a)
        r, c = divmod(idx, GRID)
        rgb[r * CELL:(r + 1) * CELL, c * CELL:(c + 1) * CELL] = c_rgb
        alpha[r * CELL:(r + 1) * CELL, c * CELL:(c + 1) * CELL] = c_a
    return rgb, alpha


# --------------------------------------------------------------------------
# Icons
# --------------------------------------------------------------------------

def sky_gradient(h, w, top=(0.30, 0.52, 0.86), bottom=(0.98, 0.72, 0.52)):
    t = np.linspace(0, 1, h, dtype=np.float32)[:, None, None]
    return (1 - t) * np.array(top, np.float32) + t * np.array(bottom, np.float32) + np.zeros((h, w, 3), np.float32)


def composite(dst, src_rgb, src_a, aspect, x, y, scale, tint=(1, 1, 1)):
    img = to_image(src_rgb * np.array(tint, np.float32), src_a)
    size = max(1, int(CELL * scale))
    hgt = max(1, int(size / max(aspect, 0.2)))
    img = img.resize((size, hgt), Image.LANCZOS)
    arr = np.asarray(img).astype(np.float32) / 255.0
    h, w = dst.shape[:2]
    x0, y0 = int(x - size / 2), int(y - hgt / 2)
    xa, ya = max(0, x0), max(0, y0)
    xb, yb = min(w, x0 + size), min(h, y0 + hgt)
    if xa >= xb or ya >= yb:
        return
    s = arr[ya - y0:yb - y0, xa - x0:xb - x0]
    a = s[..., 3:4]
    dst[ya:yb, xa:xb] = dst[ya:yb, xa:xb] * (1 - a) + s[..., :3] * a


def make_pack_icon(cells, path, warm=True):
    h = w = 256
    img = sky_gradient(h, w) if warm else sky_gradient(h, w, (0.25, 0.48, 0.85), (0.70, 0.84, 0.98))
    composite(img, *cells[10], 150, 60, 1.1, (1.0, 0.85, 0.85))
    composite(img, *cells[14], 70, 120, 0.95, (1.0, 0.86, 0.74))
    composite(img, *cells[0], 175, 160, 0.9, (1.0, 0.9, 0.8))
    composite(img, *cells[2], 110, 190, 0.8, (1.0, 0.88, 0.78))
    composite(img, *cells[6], 200, 215, 0.8, (0.95, 0.75, 0.62))
    Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), "RGB").save(path)


def make_item_icon(path):
    # 32x32 pixel-art cloud with a small gear notch (settings)
    s = 32
    yy, xx = np.mgrid[0:s, 0:s].astype(np.float32)
    blobs = [(10, 18, 7), (17, 14, 8.5), (24, 18, 6.5), (16, 21, 8)]
    a = np.zeros((s, s), np.float32)
    for (cx, cy, r) in blobs:
        a = np.maximum(a, ((xx - cx) ** 2 + (yy - cy) ** 2 <= r * r).astype(np.float32))
    a *= (yy <= 25).astype(np.float32)
    shade = np.clip(1.0 - (yy - 8) / 30.0, 0.55, 1.0)
    rgb = np.stack([shade * 0.97, shade * 0.98, shade * 1.0], -1)
    # outline
    edge = np.zeros_like(a)
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        edge = np.maximum(edge, np.roll(np.roll(a, dx, 1), dy, 0))
    outline = (edge > 0) & (a == 0)
    out = np.zeros((s, s, 4), np.float32)
    out[..., :3] = rgb
    out[..., 3] = a
    out[outline] = [0.22, 0.32, 0.48, 1.0]
    # base shadow band
    band = (a > 0) & (yy >= 22)
    out[band, :3] *= 0.82
    Image.fromarray((out * 255).astype(np.uint8), "RGBA").save(path)


def main():
    tex_dir = os.path.join(RP, "textures", "ultra_clouds")
    lite_dir = os.path.join(RP, "subpacks", "lite", "textures", "ultra_clouds")
    os.makedirs(tex_dir, exist_ok=True)
    os.makedirs(lite_dir, exist_ok=True)
    print("Rendering cloud sprites ...")
    cells = build_cells()
    for variant in ("natural", "soft"):
        rgb, a = assemble(cells, variant)
        img = to_image(rgb, a)
        img.save(os.path.join(tex_dir, f"atlas_{variant}.png"), optimize=True)
        img.resize((512, 512), Image.LANCZOS).save(os.path.join(lite_dir, f"atlas_{variant}.png"), optimize=True)
        print(f"  wrote atlas_{variant}.png (+ lite 512px)")
    import json
    meta = {"cells": [{"index": i, "kind": CELL_JOBS[i][0], "aspect": round(c[2], 4)}
                      for i, c in enumerate(cells)]}
    with open(os.path.join(ROOT, "tools", "atlas_meta.json"), "w") as f:
        json.dump(meta, f, indent=1)
    make_item_icon(os.path.join(tex_dir, "icon_settings.png"))
    make_pack_icon(cells, os.path.join(RP, "pack_icon.png"))
    make_pack_icon(cells, os.path.join(BP, "pack_icon.png") if os.path.isdir(BP) else os.path.join(ROOT, "docs", "pack_icon_bp.png"), warm=False)
    # fully transparent vanilla cloud map -> hides the vanilla cloud layer
    for sp in ("standard", "lite"):
        d = os.path.join(RP, "subpacks", sp, "textures", "environment")
        os.makedirs(d, exist_ok=True)
        Image.new("RGBA", (256, 256), (0, 0, 0, 0)).save(os.path.join(d, "clouds.png"))
    print("done")


if __name__ == "__main__":
    sys.exit(main())
