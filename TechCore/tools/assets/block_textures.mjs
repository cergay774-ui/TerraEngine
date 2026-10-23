// Процедурные текстуры блоков TechCore (16×16, роторы — 32×32).
// Каждая запись: { canvas, mer: [m, e, r] | Canvas, flip?: {ticks, frames} }.
// mer — значения PBR (металличность, свечение, шероховатость) для Vibrant Visuals.
import { Canvas, hex, shade, lighten, mix, rng, strip } from "./canvas.mjs";

const C = {
  frameDark: hex("#3b4048"),
  frame: hex("#4d535c"),
  panel: hex("#7c848e"),
  panelLight: hex("#a3abb4"),
  steel: hex("#9aa3ad"),
  copper: hex("#b8673c"),
  gold: hex("#d6ab38"),
  black: hex("#17191c"),
  rubber: hex("#26282b"),
  hazardY: hex("#e1b124"),
  hazardK: hex("#24262a"),
  white: hex("#dfe3e6"),
  red: hex("#b3352d"),
  cyan: hex("#38d6e8"),
  green: hex("#4ccf5a"),
  amber: hex("#f0a51e"),
};

const MET = { metal: [190, 0, 110], paint: [40, 0, 170], rubber: [0, 0, 235], glass: [20, 0, 40] };

function base(color, seed, amount = 5) {
  return new Canvas(16, 16).fill(color).noise(seed, amount);
}

function rivets(c, color) {
  for (const [x, y] of [[2, 2], [13, 2], [2, 13], [13, 13]]) {
    c.set(x, y, lighten(color, 40));
    c.set(x + 1, y + 1, shade(color, 0.6));
  }
  return c;
}

function brushed(color, seed) {
  const c = new Canvas(16, 16).fill(color);
  const r = rng(seed);
  for (let y = 0; y < 16; y++) {
    const d = (r() - 0.5) * 14;
    for (let x = 0; x < 16; x++) c.set(x, y, lighten(color, d + (r() - 0.5) * 4));
  }
  return c;
}

function frameTex() {
  const c = base(C.frame, 11, 4);
  c.bevel(0, 0, 16, 16, lighten(C.frame, 22), shade(C.frame, 0.65));
  c.frame(1, 1, 14, 14, shade(C.frame, 0.85));
  return rivets(c, C.frame);
}

function panelTex() {
  const c = brushed(C.panel, 21);
  c.bevel(0, 0, 16, 16, lighten(C.panel, 25), shade(C.panel, 0.7));
  c.rect(3, 7, 10, 1, shade(C.panel, 0.85));
  return rivets(c, C.panel);
}

function ventTex() {
  const c = panelTex();
  for (let y = 3; y < 13; y += 3) {
    c.rect(3, y, 10, 1, C.black);
    c.rect(3, y + 1, 10, 1, lighten(C.panel, 20));
  }
  return c;
}

function steelTex() {
  const c = brushed(C.steel, 31);
  c.bevel(0, 0, 16, 16, lighten(C.steel, 25), shade(C.steel, 0.72));
  return c;
}

function copperTex() {
  const c = brushed(C.copper, 41);
  for (let y = 1; y < 16; y += 3) c.rect(0, y, 16, 1, lighten(C.copper, 28));
  c.bevel(0, 0, 16, 16, lighten(C.copper, 35), shade(C.copper, 0.7));
  return c;
}

function goldTex() {
  const c = brushed(C.gold, 51);
  c.bevel(0, 0, 16, 16, lighten(C.gold, 35), shade(C.gold, 0.7));
  return c;
}

function hazardTex() {
  const c = new Canvas(16, 16);
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) c.set(x, y, Math.floor((x + y) / 4) % 2 === 0 ? C.hazardY : C.hazardK);
  c.noise(61, 6);
  c.bevel(0, 0, 16, 16, lighten(C.hazardY, 10), shade(C.hazardK, 0.8));
  return c;
}

function rubberTex(seed = 71) {
  return base(C.rubber, seed, 4);
}

function screenTex(kind) {
  const c = new Canvas(16, 16).fill(shade(C.frameDark, 0.9));
  c.bevel(0, 0, 16, 16, lighten(C.frameDark, 18), shade(C.frameDark, 0.6));
  const bg = kind === "idle" ? hex("#0d1418") : hex("#071b1f");
  c.rect(2, 2, 12, 10, bg);
  const col = { idle: hex("#2d4148"), ok: C.cyan, warn: C.amber, err: hex("#ff4a3d") }[kind];
  if (kind === "idle") {
    c.rect(3, 4, 4, 1, col);
    c.rect(3, 6, 7, 1, col);
  } else {
    // Строки данных и график
    c.rect(3, 3, 5, 1, col);
    c.rect(3, 5, 8, 1, shade(col, 0.7));
    const pts = [10, 9, 10, 8, 7, 8, 6, 7, 5, 6];
    for (let i = 0; i < pts.length; i++) c.set(3 + i, pts[i] + 1, col);
    if (kind !== "ok") c.rect(11, 3, 2, 2, col);
  }
  // Кнопки под экраном
  c.rect(3, 13, 2, 1, C.green);
  c.rect(6, 13, 2, 1, C.amber);
  c.rect(9, 13, 4, 1, shade(C.panel, 0.7));
  return c;
}

function screenMer(c) {
  return c.mapPixels((p, x, y) => (x >= 2 && x < 14 && y >= 2 && y < 12 && p[1] > 60 ? [0, 200, 60, 255] : [150, 0, 120, 255]));
}

function ledTex(color) {
  const c = panelTex();
  c.rect(4, 4, 8, 8, C.frameDark);
  c.disc(8, 8, 3.2, color ?? hex("#2b2f33"));
  if (color) {
    c.disc(8, 8, 1.6, lighten(color, 60));
    c.set(7, 6, hex("#ffffff"));
  }
  return c;
}

function ledMer(c, lit) {
  return c.mapPixels((p, x, y) => {
    const d = (x + 0.5 - 8) ** 2 + (y + 0.5 - 8) ** 2;
    return lit && d <= 3.2 * 3.2 ? [0, 255, 40, 255] : [150, 0, 120, 255];
  });
}

function glassTex(tint) {
  const c = new Canvas(16, 16).fill(shade(tint, 0.55));
  c.noise(81, 4);
  c.line(3, 12, 12, 3, lighten(tint, 30));
  c.line(5, 13, 13, 5, lighten(tint, 15));
  c.bevel(0, 0, 16, 16, C.steel, shade(C.steel, 0.6));
  return c;
}

// --- Анимации (вертикальные ленты кадров) ---

function fireFrames() {
  const frames = [];
  for (let f = 0; f < 8; f++) {
    const c = new Canvas(16, 16).fill(hex("#1a0d06"));
    const r = rng(100 + f);
    for (let x = 0; x < 16; x++) {
      const h = 6 + Math.floor(r() * 7 + 3 * Math.sin((x + f * 2) * 0.9));
      for (let y = 15; y > 15 - h; y--) {
        const t = (15 - y) / h;
        c.set(x, y, mix(hex("#ffe27a"), hex("#c2380f"), t));
      }
    }
    for (let x = 0; x < 16; x += 4) c.rect(x, 0, 1, 16, hex("#2a2a2a"));
    frames.push(c);
  }
  return frames;
}

function fireOff() {
  const c = new Canvas(16, 16).fill(hex("#151515"));
  c.noise(110, 6);
  c.rect(0, 13, 16, 3, hex("#3a3532"));
  for (let x = 0; x < 16; x += 4) c.rect(x, 0, 1, 16, hex("#2a2a2a"));
  return c;
}

function glowFrames() {
  const frames = [];
  for (let f = 0; f < 6; f++) {
    const c = new Canvas(16, 16);
    const r = rng(200 + f);
    for (let y = 0; y < 16; y++)
      for (let x = 0; x < 16; x++) {
        const v = 0.55 + 0.45 * Math.sin((x * 0.7 + y * 0.4 + f) * 1.1) * 0.5 + r() * 0.2;
        c.set(x, y, mix(hex("#ff6a12"), hex("#ffe08a"), Math.min(1, v)));
      }
    c.bevel(0, 0, 16, 16, C.frameDark, C.frameDark);
    frames.push(c);
  }
  return frames;
}

function glowOff() {
  const c = new Canvas(16, 16).fill(hex("#2a1a14"));
  c.noise(220, 5);
  c.bevel(0, 0, 16, 16, C.frameDark, C.frameDark);
  return c;
}

/** Полосы, сдвигаемые на 1 пиксель за кадр (вращение/движение). */
function stripeFrames(colA, colB, period, dir, count) {
  const frames = [];
  for (let f = 0; f < count; f++) {
    const c = new Canvas(16, 16);
    for (let y = 0; y < 16; y++)
      for (let x = 0; x < 16; x++) {
        const t = dir === "h" ? y + f : dir === "v" ? x + f : x + y + f;
        const k = ((t % period) + period) % period;
        c.set(x, y, k < period / 2 ? colA : colB);
      }
    c.noise(300 + f, 4);
    frames.push(c);
  }
  return frames;
}

function beltFrames() {
  const frames = [];
  for (let f = 0; f < 4; f++) {
    const c = new Canvas(16, 16).fill(C.rubber);
    for (let y = 0; y < 16; y++) if ((y + f) % 4 === 0) c.rect(1, y, 14, 1, lighten(C.rubber, 22));
    c.rect(0, 0, 1, 16, C.steel);
    c.rect(15, 0, 1, 16, C.steel);
    c.noise(400 + f, 3);
    frames.push(c);
  }
  return frames;
}

// --- Ротор ветрогенератора (32×32, прозрачный фон) ---

const ROTOR_STYLE = {
  1: { blade: hex("#9a7040"), tip: hex("#7a5530"), width: 2.6 },
  2: { blade: hex("#b9c0c7"), tip: hex("#8d949b"), width: 2.4 },
  3: { blade: hex("#e3e6e8"), tip: C.red, width: 2.4 },
  4: { blade: hex("#f1f2f3"), tip: C.red, width: 2.2 },
  5: { blade: hex("#2b2e33"), tip: C.cyan, width: 2.2 },
};

function rotorFrame(tier, angleDeg) {
  const st = ROTOR_STYLE[tier];
  const c = new Canvas(32, 32);
  const cx = 16;
  const cy = 16;
  for (let y = 0; y < 32; y++)
    for (let x = 0; x < 32; x++) {
      const dx = x + 0.5 - cx;
      const dy = y + 0.5 - cy;
      const rr = Math.sqrt(dx * dx + dy * dy);
      if (rr > 15.5 || rr < 2) continue;
      const ang = (Math.atan2(dy, dx) * 180) / Math.PI;
      for (let b = 0; b < 3; b++) {
        const a = angleDeg + b * 120;
        let diff = ((ang - a + 540) % 360) - 180;
        // Лопасть сужается к концу; ширина — в пикселях на радиусе rr.
        const halfWidthPx = st.width * (1.2 - rr / 22);
        const dist = Math.abs(Math.sin((diff * Math.PI) / 180) * rr);
        if (Math.abs(diff) < 90 && dist <= halfWidthPx) {
          const col = rr > 12.5 ? st.tip : diff > 0 ? st.blade : shade(st.blade, 0.82);
          c.set(x, y, col);
        }
      }
    }
  c.disc(cx, cy, 2.6, C.steel);
  c.disc(cx, cy, 1.2, shade(C.steel, 0.6));
  return c;
}

function rotorFrames(tier) {
  const frames = [];
  for (let f = 0; f < 8; f++) frames.push(rotorFrame(tier, f * 15));
  return frames;
}

// --- Прочее ---

function accentTex(color) {
  const c = brushed(color, 500 + color[0]);
  c.rect(0, 6, 16, 4, shade(color, 0.8));
  c.rect(0, 7, 16, 2, lighten(color, 30));
  c.bevel(0, 0, 16, 16, lighten(color, 30), shade(color, 0.6));
  return c;
}

function wireTex(core, sheath, band) {
  const c = new Canvas(16, 16).fill(sheath);
  c.noise(600 + core[0], 4);
  c.rect(0, 6, 16, 4, core);
  c.rect(0, 7, 16, 1, lighten(core, 35));
  if (band) for (let x = 0; x < 16; x += 5) c.rect(x, 0, 2, 16, band);
  return c;
}

function pipeTex() {
  const c = brushed(hex("#7d8791"), 700);
  for (let x = 0; x < 16; x += 8) c.rect(x, 0, 2, 16, shade(C.steel, 0.65));
  c.rect(0, 0, 16, 1, lighten(C.steel, 20));
  return c;
}

function crateTex() {
  const c = new Canvas(16, 16).fill(hex("#6b5a3e"));
  c.noise(710, 8);
  c.line(1, 1, 14, 14, hex("#4e412b"));
  c.line(1, 14, 14, 1, hex("#4e412b"));
  c.bevel(0, 0, 16, 16, C.steel, shade(C.steel, 0.55));
  c.frame(1, 1, 14, 14, shade(C.frame, 0.9));
  return rivets(c, C.steel);
}

function cargoTex() {
  const c = new Canvas(16, 16).fill(hex("#8a6d43"));
  c.noise(720, 8);
  c.frame(0, 0, 16, 16, hex("#5a4628"));
  c.rect(0, 7, 16, 2, hex("#5a4628"));
  return c;
}

function insulTex() {
  const c = new Canvas(16, 16).fill(hex("#c9c3b8"));
  c.noise(730, 6);
  for (let y = 0; y < 16; y += 4) c.rect(0, y, 16, 1, hex("#aaa497"));
  for (let y = 0; y < 16; y += 4) c.rect(((y / 4) % 2) * 8, y, 1, 4, hex("#aaa497"));
  return c;
}

function tankPaint(color, seed) {
  const c = brushed(color, seed);
  c.rect(0, 2, 16, 1, lighten(color, 30));
  c.rect(0, 13, 16, 1, shade(color, 0.7));
  return c;
}

const FLUID_COLORS = { 1: hex("#c98a1d"), 2: hex("#d4473e"), 3: hex("#6cbc3a") };

function windowTex(fluid, level) {
  const c = new Canvas(16, 16).fill(C.frame);
  c.bevel(0, 0, 16, 16, lighten(C.frame, 20), shade(C.frame, 0.6));
  c.rect(3, 1, 10, 14, hex("#101418"));
  if (fluid && level > 0) {
    const h = Math.round((14 * level) / 4);
    c.rect(3, 15 - h, 10, h, FLUID_COLORS[fluid]);
    c.rect(3, 15 - h, 10, 1, lighten(FLUID_COLORS[fluid], 40));
  }
  for (let y = 4; y < 15; y += 4) c.rect(3, y, 2, 1, C.white);
  return c;
}

function batteryFront(level) {
  const c = new Canvas(16, 16).fill(C.frameDark);
  c.bevel(0, 0, 16, 16, lighten(C.frameDark, 20), shade(C.frameDark, 0.6));
  for (let i = 0; i < 4; i++) {
    const y = 12 - i * 3;
    c.rect(4, y, 8, 2, i < level ? (level >= 3 ? C.green : level === 2 ? C.amber : hex("#e0603a")) : hex("#262a2e"));
  }
  c.rect(6, 1, 4, 1, C.steel);
  return c;
}

function batteryMer(level) {
  return (c) => c.mapPixels((p, x, y) => (x >= 4 && x < 12 && y >= 3 && y < 14 && p[1] > 90 ? [0, 220, 60, 255] : [150, 0, 120, 255]));
}

function superTex() {
  const c = new Canvas(16, 16).fill(hex("#10343a"));
  c.rect(0, 5, 16, 6, C.cyan);
  c.rect(0, 7, 16, 2, hex("#c8fbff"));
  c.noise(740, 4);
  return c;
}

function coreTex() {
  const c = new Canvas(16, 16).fill(hex("#7cf3ff"));
  c.disc(8, 8, 6, hex("#c8fbff"));
  c.disc(8, 8, 3, hex("#ffffff"));
  c.frame(0, 0, 16, 16, hex("#2a7f8a"));
  return c;
}

const TIER_COLORS = [hex("#6f7f91"), hex("#b8673c"), hex("#d6ab38"), hex("#2fa39a"), hex("#8a5bd1"), hex("#5fe3f0")];

/** Полный набор текстур блоков. */
export function blockTextures() {
  /** @type {Map<string, {canvas: Canvas, mer: any, flip?: {ticks: number[], frames: number}}>} */
  const T = new Map();
  const add = (name, canvas, mer, flip) => T.set(name, { canvas, mer, flip });

  add("frame", frameTex(), MET.metal);
  add("panel", panelTex(), MET.paint);
  add("vent", ventTex(), MET.paint);
  add("steel", steelTex(), MET.metal);
  add("copper", copperTex(), [230, 0, 90]);
  add("gold", goldTex(), [240, 0, 70]);
  add("hazard", hazardTex(), MET.paint);
  add("rubber", rubberTex(), MET.rubber);
  add("insul", insulTex(), [0, 0, 210]);
  add("crate", crateTex(), [40, 0, 200]);
  add("cargo", cargoTex(), [0, 0, 220]);
  add("pipe", pipeTex(), MET.metal);
  add("tank_red", tankPaint(C.red, 750), MET.paint);
  add("tank_white", tankPaint(C.white, 760), MET.paint);
  add("glass_dark", glassTex(hex("#5b7c8c")), MET.glass);
  add("glass_green", glassTex(hex("#5f9c46")), MET.glass);
  add("glass_amber", glassTex(hex("#a7762d")), MET.glass);
  for (const k of ["idle", "ok", "warn", "err"]) {
    const s = screenTex(k);
    add(`screen_${k}`, s, k === "idle" ? MET.paint : screenMer(s));
  }
  const ledOff = ledTex(null);
  add("led_off", ledOff, MET.paint);
  for (const [k, col] of [["green", C.green], ["yellow", C.amber], ["red", hex("#ff4a3d")]]) {
    const l = ledTex(col);
    add(`led_${k}`, l, ledMer(l, true));
  }
  add("fire_off", fireOff(), [0, 0, 230]);
  add("fire_anim", strip(fireFrames()), [0, 255, 200], { ticks: [3], frames: 8 });
  add("glow_off", glowOff(), [0, 0, 220]);
  add("glow_anim", strip(glowFrames()), [0, 230, 180], { ticks: [4], frames: 6 });
  const roller = stripeFrames(hex("#5c636b"), hex("#3a3f45"), 4, "h", 4);
  add("roller", roller[0], MET.metal);
  add("roller_anim", strip(roller), MET.metal, { ticks: [2], frames: 4 });
  const chuck = stripeFrames(hex("#aeb6bf"), hex("#6d757e"), 4, "h", 4);
  add("chuck", chuck[0], MET.metal);
  add("chuck_anim", strip(chuck), MET.metal, { ticks: [1], frames: 4 });
  const drill = stripeFrames(hex("#b7bdc4"), hex("#5d636a"), 4, "d", 4);
  add("drill", drill[0], MET.metal);
  add("drill_anim", strip(drill), MET.metal, { ticks: [1], frames: 4 });
  const belt = beltFrames();
  add("belt", belt[0], MET.rubber);
  add("belt_anim", strip(belt), MET.rubber, { ticks: [3], frames: 4 });
  TIER_COLORS.forEach((col, i) => add(`accent_t${i}`, accentTex(col), i === 5 ? [120, 160, 80] : [200, 0, 90]));
  add("wire_copper", wireTex(C.copper, shade(C.copper, 0.8)), [230, 0, 90]);
  add("wire_insulated", wireTex(C.copper, hex("#1e2124")), [20, 0, 220]);
  add("wire_reinforced", wireTex(C.gold, hex("#5b636c"), C.hazardY), [180, 0, 110]);
  add("wire_super", superTex(), [100, 200, 60]);
  add("core", coreTex(), [0, 255, 40]);
  add("tank_w_0", windowTex(0, 0), MET.glass);
  for (const f of [1, 2, 3]) for (let l = 1; l <= 4; l++) add(`tank_w_${f}_${l}`, windowTex(f, l), MET.glass);
  for (let l = 0; l <= 4; l++) {
    const b = batteryFront(l);
    add(`battery_${l}`, b, l > 0 ? batteryMer(l)(b) : MET.paint);
  }
  for (let t = 1; t <= 5; t++) {
    const frames = rotorFrames(t);
    add(`rotor${t}`, frames[0], [120, 0, 140]);
    // Одна лента кадров используется тремя атласами с разной скоростью.
    add(`rotor${t}_anim`, strip(frames), [120, 0, 140], { ticks: [4, 2, 1], frames: 8 });
  }
  return T;
}

export { TIER_COLORS, C as PALETTE };
