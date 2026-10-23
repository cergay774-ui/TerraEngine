// Простая растровая "канва" для процедурной пиксельной графики.
import { encodePNG } from "./png.mjs";

/** @typedef {[number, number, number, number]} RGBA */

export function hex(h, a = 255) {
  const v = h.replace("#", "");
  return [parseInt(v.slice(0, 2), 16), parseInt(v.slice(2, 4), 16), parseInt(v.slice(4, 6), 16), a];
}

export function shade(c, f) {
  return [clamp(c[0] * f), clamp(c[1] * f), clamp(c[2] * f), c[3]];
}

export function lighten(c, d) {
  return [clamp(c[0] + d), clamp(c[1] + d), clamp(c[2] + d), c[3]];
}

export function mix(a, b, t) {
  return [clamp(a[0] + (b[0] - a[0]) * t), clamp(a[1] + (b[1] - a[1]) * t), clamp(a[2] + (b[2] - a[2]) * t), clamp(a[3] + (b[3] - a[3]) * t)];
}

function clamp(v) {
  return Math.max(0, Math.min(255, Math.round(v)));
}

/** Детерминированный генератор случайных чисел. */
export function rng(seed) {
  let s = seed >>> 0 || 1;
  return () => {
    s |= 0;
    s = (s + 0x6d2b79f5) | 0;
    let t = Math.imul(s ^ (s >>> 15), 1 | s);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function hashStr(s) {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) h = Math.imul(h ^ s.charCodeAt(i), 16777619);
  return h >>> 0;
}

export class Canvas {
  constructor(w, h) {
    this.w = w;
    this.h = h;
    this.data = new Uint8Array(w * h * 4);
  }
  inside(x, y) {
    return x >= 0 && y >= 0 && x < this.w && y < this.h;
  }
  get(x, y) {
    if (!this.inside(x, y)) return [0, 0, 0, 0];
    const i = (y * this.w + x) * 4;
    return [this.data[i], this.data[i + 1], this.data[i + 2], this.data[i + 3]];
  }
  set(x, y, c) {
    x = Math.round(x);
    y = Math.round(y);
    if (!this.inside(x, y)) return this;
    const i = (y * this.w + x) * 4;
    if (c[3] >= 255 || this.data[i + 3] === 0) {
      this.data[i] = c[0];
      this.data[i + 1] = c[1];
      this.data[i + 2] = c[2];
      this.data[i + 3] = c[3];
    } else {
      const a = c[3] / 255;
      this.data[i] = clamp(this.data[i] * (1 - a) + c[0] * a);
      this.data[i + 1] = clamp(this.data[i + 1] * (1 - a) + c[1] * a);
      this.data[i + 2] = clamp(this.data[i + 2] * (1 - a) + c[2] * a);
      this.data[i + 3] = Math.max(this.data[i + 3], c[3]);
    }
    return this;
  }
  fill(c) {
    for (let y = 0; y < this.h; y++) for (let x = 0; x < this.w; x++) this.set(x, y, c);
    return this;
  }
  rect(x, y, w, h, c) {
    for (let j = y; j < y + h; j++) for (let i = x; i < x + w; i++) this.set(i, j, c);
    return this;
  }
  frame(x, y, w, h, c) {
    for (let i = x; i < x + w; i++) {
      this.set(i, y, c);
      this.set(i, y + h - 1, c);
    }
    for (let j = y; j < y + h; j++) {
      this.set(x, j, c);
      this.set(x + w - 1, j, c);
    }
    return this;
  }
  /** Фаска: светлая верхняя/левая и тёмная нижняя/правая грань. */
  bevel(x, y, w, h, light, dark) {
    for (let i = x; i < x + w; i++) {
      this.set(i, y, light);
      this.set(i, y + h - 1, dark);
    }
    for (let j = y; j < y + h; j++) {
      this.set(x, j, light);
      this.set(x + w - 1, j, dark);
    }
    return this;
  }
  line(x0, y0, x1, y1, c) {
    const dx = Math.abs(x1 - x0);
    const dy = -Math.abs(y1 - y0);
    const sx = x0 < x1 ? 1 : -1;
    const sy = y0 < y1 ? 1 : -1;
    let err = dx + dy;
    for (;;) {
      this.set(x0, y0, c);
      if (x0 === x1 && y0 === y1) break;
      const e2 = 2 * err;
      if (e2 >= dy) {
        err += dy;
        x0 += sx;
      }
      if (e2 <= dx) {
        err += dx;
        y0 += sy;
      }
    }
    return this;
  }
  disc(cx, cy, r, c) {
    for (let y = Math.floor(cy - r); y <= Math.ceil(cy + r); y++)
      for (let x = Math.floor(cx - r); x <= Math.ceil(cx + r); x++) {
        const dx = x + 0.5 - cx;
        const dy = y + 0.5 - cy;
        if (dx * dx + dy * dy <= r * r) this.set(x, y, c);
      }
    return this;
  }
  ring(cx, cy, r0, r1, c) {
    for (let y = Math.floor(cy - r1); y <= Math.ceil(cy + r1); y++)
      for (let x = Math.floor(cx - r1); x <= Math.ceil(cx + r1); x++) {
        const dx = x + 0.5 - cx;
        const dy = y + 0.5 - cy;
        const d = dx * dx + dy * dy;
        if (d <= r1 * r1 && d >= r0 * r0) this.set(x, y, c);
      }
    return this;
  }
  /** Шум яркости по всей канве (только непрозрачные пиксели). */
  noise(seed, amount) {
    const r = rng(seed);
    for (let y = 0; y < this.h; y++)
      for (let x = 0; x < this.w; x++) {
        const c = this.get(x, y);
        if (c[3] === 0) {
          r();
          continue;
        }
        const d = (r() - 0.5) * 2 * amount;
        const i = (y * this.w + x) * 4;
        this.data[i] = clamp(c[0] + d);
        this.data[i + 1] = clamp(c[1] + d);
        this.data[i + 2] = clamp(c[2] + d);
      }
    return this;
  }
  /** Тёмный контур вокруг непрозрачной формы (для иконок предметов). */
  outline(c) {
    const copy = new Uint8Array(this.data);
    const alphaAt = (x, y) => (this.inside(x, y) ? copy[(y * this.w + x) * 4 + 3] : 0);
    for (let y = 0; y < this.h; y++)
      for (let x = 0; x < this.w; x++) {
        if (alphaAt(x, y) > 0) continue;
        if (alphaAt(x + 1, y) || alphaAt(x - 1, y) || alphaAt(x, y + 1) || alphaAt(x, y - 1)) this.set(x, y, c);
      }
    return this;
  }
  /** Вставка другой канвы. */
  blit(src, ox, oy) {
    for (let y = 0; y < src.h; y++) for (let x = 0; x < src.w; x++) {
      const c = src.get(x, y);
      if (c[3] > 0) this.set(ox + x, oy + y, c);
    }
    return this;
  }
  clone() {
    const c = new Canvas(this.w, this.h);
    c.data.set(this.data);
    return c;
  }
  /** Карта MER: для каждого пикселя функция → [m, e, r]. */
  mapPixels(fn) {
    const out = new Canvas(this.w, this.h);
    for (let y = 0; y < this.h; y++) for (let x = 0; x < this.w; x++) out.set(x, y, fn(this.get(x, y), x, y));
    return out;
  }
  png() {
    return encodePNG(this.w, this.h, this.data);
  }
}

/** Вертикальная лента кадров flipbook из массива канв одинакового размера. */
export function strip(frames) {
  const w = frames[0].w;
  const h = frames[0].h;
  const out = new Canvas(w, h * frames.length);
  frames.forEach((f, i) => out.blit(f, 0, i * h));
  return out;
}

/** Масштабирование ближайшим соседом. */
export function scale(src, k) {
  const out = new Canvas(src.w * k, src.h * k);
  for (let y = 0; y < out.h; y++) for (let x = 0; x < out.w; x++) out.set(x, y, src.get(Math.floor(x / k), Math.floor(y / k)));
  return out;
}
