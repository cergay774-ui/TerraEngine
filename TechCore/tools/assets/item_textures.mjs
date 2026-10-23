// Процедурные иконки предметов 16×16 (прозрачный фон, тёмный контур).
import { Canvas, hex, shade, lighten, rng } from "./canvas.mjs";
import { TIER_COLORS } from "./block_textures.mjs";

const OUT = hex("#1b1d21");

function done(c) {
  return c.outline(OUT);
}

function dust(color, seed) {
  const c = new Canvas(16, 16);
  const rows = [[6, 9], [4, 11], [3, 12], [2, 13], [2, 13], [1, 14]];
  rows.forEach(([a, b], i) => {
    for (let x = a; x <= b; x++) c.set(x, 8 + i, color);
  });
  c.rect(5, 7, 5, 1, color);
  const r = rng(seed);
  for (let i = 0; i < 14; i++) {
    const x = 2 + Math.floor(r() * 12);
    const y = 8 + Math.floor(r() * 6);
    if (c.get(x, y)[3]) c.set(x, y, r() > 0.5 ? lighten(color, 45) : shade(color, 0.7));
  }
  for (let x = 6; x <= 9; x++) c.set(x, 8, lighten(color, 35));
  return done(c);
}

function ingot(color) {
  // Классический слиток: светлая верхняя грань-трапеция и тёмная передняя грань.
  const c = new Canvas(16, 16);
  const top = lighten(color, 35);
  for (let y = 0; y < 3; y++) for (let x = 4 - y; x < 12 + y; x++) c.set(x, 5 + y, y === 0 ? lighten(color, 60) : top);
  for (let y = 0; y < 4; y++) for (let x = 1 + Math.max(0, 1 - y); x < 15 - Math.max(0, 1 - y); x++) c.set(x, 8 + y, y === 3 ? shade(color, 0.6) : color);
  c.line(2, 8, 13, 8, lighten(color, 15));
  c.set(5, 9, lighten(color, 70));
  c.set(6, 9, lighten(color, 50));
  return done(c);
}

function plate(color) {
  const c = new Canvas(16, 16);
  c.rect(2, 3, 12, 10, color);
  c.bevel(2, 3, 12, 10, lighten(color, 45), shade(color, 0.6));
  c.line(4, 5, 7, 5, lighten(color, 60));
  c.set(4, 11, shade(color, 0.75));
  c.set(11, 5, shade(color, 0.75));
  return done(c);
}

function gear(color, holeColor) {
  const c = new Canvas(16, 16);
  c.disc(8, 8, 5.2, color);
  for (let i = 0; i < 8; i++) {
    const a = (i * Math.PI) / 4;
    const x = 8 + Math.cos(a) * 6.2;
    const y = 8 + Math.sin(a) * 6.2;
    c.rect(Math.round(x - 1), Math.round(y - 1), 2, 2, color);
  }
  c.ring(8, 8, 3.2, 4.2, shade(color, 0.75));
  c.disc(8, 8, 1.8, holeColor ?? [0, 0, 0, 0]);
  if (!holeColor) for (let y = 6; y <= 9; y++) for (let x = 6; x <= 9; x++) if ((x + 0.5 - 8) ** 2 + (y + 0.5 - 8) ** 2 <= 3.3) c.data[(y * 16 + x) * 4 + 3] = 0;
  c.set(6, 4, lighten(color, 50));
  c.set(5, 5, lighten(color, 50));
  return done(c);
}

function shaft(color) {
  const c = new Canvas(16, 16);
  for (let i = 0; i < 11; i++) {
    c.rect(2 + i, 12 - i, 2, 2, i % 3 === 0 ? lighten(color, 30) : color);
  }
  c.rect(1, 12, 3, 3, shade(color, 0.7));
  c.rect(12, 1, 3, 3, shade(color, 0.7));
  return done(c);
}

function coil() {
  const c = new Canvas(16, 16);
  const cu = hex("#c06e3f");
  c.rect(2, 3, 2, 10, hex("#8d959e"));
  c.rect(12, 3, 2, 10, hex("#8d959e"));
  for (let y = 4; y < 12; y++) c.rect(4, y, 8, 1, y % 2 ? cu : lighten(cu, 30));
  c.rect(7, 1, 2, 3, hex("#5d646c"));
  return done(c);
}

function bearing() {
  const c = new Canvas(16, 16);
  c.ring(8, 8, 4.5, 7, hex("#a8b0b8"));
  c.ring(8, 8, 2, 3.3, hex("#7b838b"));
  for (let i = 0; i < 6; i++) {
    const a = (i * Math.PI) / 3;
    c.disc(8 + Math.cos(a) * 3.9, 8 + Math.sin(a) * 3.9, 1, hex("#e4e8ec"));
  }
  return done(c);
}

function casing(color) {
  const c = new Canvas(16, 16);
  c.rect(2, 2, 12, 12, color);
  c.bevel(2, 2, 12, 12, lighten(color, 40), shade(color, 0.6));
  c.rect(4, 4, 8, 8, shade(color, 0.6));
  c.rect(5, 5, 6, 6, shade(color, 0.8));
  for (const [x, y] of [[3, 3], [12, 3], [3, 12], [12, 12]]) c.set(x, y, lighten(color, 60));
  return done(c);
}

function circuit(board, trace, chip) {
  const c = new Canvas(16, 16);
  c.rect(1, 3, 14, 10, board);
  c.bevel(1, 3, 14, 10, lighten(board, 30), shade(board, 0.6));
  c.line(2, 6, 6, 6, trace);
  c.line(6, 6, 6, 10, trace);
  c.line(10, 5, 14, 5, trace);
  c.line(3, 11, 13, 11, trace);
  c.rect(7, 5, 4, 4, chip);
  c.set(8, 6, lighten(chip, 50));
  return done(c);
}

function processor() {
  const c = new Canvas(16, 16);
  const pin = hex("#d9b23a");
  for (let i = 3; i < 13; i += 2) {
    c.rect(i, 1, 1, 2, pin);
    c.rect(i, 13, 1, 2, pin);
    c.rect(1, i, 2, 1, pin);
    c.rect(13, i, 2, 1, pin);
  }
  c.rect(3, 3, 10, 10, hex("#24272c"));
  c.bevel(3, 3, 10, 10, hex("#40454c"), hex("#121417"));
  c.rect(6, 6, 4, 4, hex("#38d6e8"));
  c.set(6, 6, hex("#c8fbff"));
  return done(c);
}

function motor() {
  const c = new Canvas(16, 16);
  c.rect(2, 4, 9, 8, hex("#4a6b8a"));
  c.bevel(2, 4, 9, 8, hex("#6f93b5"), hex("#2e4559"));
  for (let x = 3; x < 10; x += 2) c.rect(x, 5, 1, 6, hex("#3a556e"));
  c.rect(11, 5, 2, 6, hex("#8d959e"));
  c.rect(13, 7, 2, 2, hex("#c4cbd2"));
  c.rect(4, 12, 5, 2, hex("#3b4048"));
  return done(c);
}

function engine() {
  const c = new Canvas(16, 16);
  c.rect(2, 7, 12, 7, hex("#6b7178"));
  c.bevel(2, 7, 12, 7, hex("#8d949b"), hex("#43484e"));
  for (let i = 0; i < 3; i++) {
    c.rect(3 + i * 4, 3, 3, 4, hex("#9aa2aa"));
    c.rect(3 + i * 4, 2, 3, 1, hex("#c9381f"));
  }
  c.rect(5, 9, 6, 3, hex("#30343a"));
  return done(c);
}

function fuelTankItem() {
  const c = new Canvas(16, 16);
  c.rect(2, 4, 12, 8, hex("#b3352d"));
  c.disc(2.5, 8, 4, hex("#b3352d"));
  c.disc(13.5, 8, 4, hex("#b3352d"));
  c.rect(3, 5, 10, 1, hex("#e06a5e"));
  c.rect(7, 2, 2, 2, hex("#8d959e"));
  c.rect(4, 9, 8, 1, hex("#7d2620"));
  return done(c);
}

function radiator() {
  const c = new Canvas(16, 16);
  c.rect(2, 2, 12, 12, hex("#7d5236"));
  for (let x = 3; x < 13; x += 2) c.rect(x, 3, 1, 10, hex("#d78a55"));
  c.rect(2, 2, 12, 1, hex("#9aa3ad"));
  c.rect(2, 13, 12, 1, hex("#5c636b"));
  return done(c);
}

function blade(color, tip) {
  const c = new Canvas(16, 16);
  for (let i = 0; i < 12; i++) {
    const w = i < 3 ? 3 : i < 9 ? 2 : 1;
    c.rect(2 + i, 13 - i - w + 1, w, w, i > 9 ? tip : i % 4 === 0 ? lighten(color, 25) : color);
  }
  c.rect(1, 13, 3, 2, hex("#5c636b"));
  return done(c);
}

function carbonSheet() {
  const c = new Canvas(16, 16);
  c.rect(2, 2, 12, 12, hex("#25282d"));
  for (let y = 2; y < 14; y++) for (let x = 2; x < 14; x++) if (((x >> 1) + (y >> 1)) % 2 === 0) c.set(x, y, hex("#3a3f46"));
  c.bevel(2, 2, 12, 12, hex("#4c525a"), hex("#15171a"));
  return done(c);
}

function batteryCell() {
  const c = new Canvas(16, 16);
  c.rect(5, 3, 6, 11, hex("#2f6a3a"));
  c.rect(5, 3, 6, 2, hex("#c4cbd2"));
  c.rect(7, 1, 2, 2, hex("#c4cbd2"));
  c.rect(6, 6, 1, 7, hex("#4f9a5c"));
  c.rect(7, 8, 2, 1, hex("#e8f5e9"));
  c.rect(7.5, 7, 1, 3, hex("#e8f5e9"));
  return done(c);
}

// Римские цифры 3×5.
const GLYPH = {
  I: ["#", "#", "#", "#", "#"],
  V: ["#.#", "#.#", "#.#", ".#.", ".#."],
};

function roman(c, n, x0, y0, color) {
  const map = { 1: "I", 2: "II", 3: "III", 4: "IV", 5: "V" };
  let x = x0;
  for (const ch of map[n]) {
    const g = GLYPH[ch];
    g.forEach((row, y) => [...row].forEach((p, dx) => p === "#" && c.set(x + dx, y0 + y, color)));
    x += g[0].length + 1;
  }
}

function controlModule(tier) {
  const c = new Canvas(16, 16);
  const col = TIER_COLORS[tier];
  c.rect(1, 2, 14, 12, hex("#2b3036"));
  c.bevel(1, 2, 14, 12, hex("#4a5058"), hex("#15181b"));
  c.rect(2, 3, 12, 2, col);
  for (let i = 3; i < 13; i += 2) c.set(i, 14, hex("#d9b23a"));
  const width = { 1: 1, 2: 3, 3: 5, 4: 5, 5: 3 }[tier];
  roman(c, tier, Math.floor(8 - width / 2), 7, lighten(col, 40));
  return done(c);
}

function canister(fluidColor) {
  const c = new Canvas(16, 16);
  const body = hex("#5b6b3a");
  c.rect(3, 4, 10, 11, fluidColor ? shade(fluidColor, 0.85) : hex("#7a8189"));
  c.bevel(3, 4, 10, 11, lighten(fluidColor ?? hex("#7a8189"), 30), shade(fluidColor ?? body, 0.6));
  c.rect(4, 1, 5, 3, hex("#3b4048"));
  c.rect(10, 2, 2, 2, hex("#c4cbd2"));
  c.line(4, 6, 11, 13, shade(fluidColor ?? hex("#7a8189"), 0.7));
  c.line(11, 6, 4, 13, shade(fluidColor ?? hex("#7a8189"), 0.7));
  return done(c);
}

function goggles() {
  const c = new Canvas(16, 16);
  c.rect(0, 7, 16, 2, hex("#5b4a35"));
  for (const x of [4, 11]) {
    c.disc(x, 8, 3.5, hex("#8a6d43"));
    c.disc(x, 8, 2.4, hex("#38d6e8"));
    c.set(x - 1, 7, hex("#c8fbff"));
  }
  c.rect(7, 7, 2, 2, hex("#8a6d43"));
  return done(c);
}

function wrench() {
  const c = new Canvas(16, 16);
  const m = hex("#a7afb7");
  for (let i = 0; i < 9; i++) c.rect(2 + i, 13 - i, 2, 2, i % 3 === 0 ? lighten(m, 25) : m);
  c.disc(12, 4, 3.4, m);
  c.rect(12, 1, 3, 3, [0, 0, 0, 0]);
  for (let y = 1; y < 4; y++) for (let x = 12; x < 15; x++) c.data[(y * 16 + x) * 4 + 3] = 0;
  c.disc(3, 13, 1.8, hex("#c9381f"));
  return done(c);
}

function crystal(color) {
  const c = new Canvas(16, 16);
  const pts = [[8, 1], [12, 6], [10, 14], [6, 14], [4, 6]];
  for (let y = 1; y < 15; y++) for (let x = 3; x < 13; x++) {
    let inside = false;
    for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) {
      const [xi, yi] = pts[i];
      const [xj, yj] = pts[j];
      if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
    }
    if (inside) c.set(x, y, x < 8 ? lighten(color, 25) : color);
  }
  c.line(8, 2, 8, 13, shade(color, 0.75));
  return done(c);
}

function lump(color, gloss) {
  const c = new Canvas(16, 16);
  c.disc(7, 9, 5, color);
  c.disc(10, 8, 4, color);
  c.disc(6, 7, 2, lighten(color, gloss));
  return done(c);
}

function biomass() {
  const c = new Canvas(16, 16);
  const g = hex("#5f9c36");
  const r = rng(900);
  for (let i = 0; i < 40; i++) c.set(3 + Math.floor(r() * 10), 5 + Math.floor(r() * 9), r() > 0.5 ? g : shade(g, 0.75));
  c.disc(8, 10, 4, g);
  c.disc(6, 9, 1.5, lighten(g, 40));
  c.noise(901, 10);
  return done(c);
}

function packedAssembler(tier) {
  const c = new Canvas(16, 16);
  c.rect(1, 3, 14, 12, hex("#6b5a3e"));
  c.noise(910, 8);
  c.bevel(1, 3, 14, 12, hex("#9aa3ad"), hex("#3b4048"));
  c.rect(1, 7, 14, 3, TIER_COLORS[tier]);
  const width = { 1: 1, 2: 3, 3: 5, 4: 5, 5: 3 }[tier];
  roman(c, tier, Math.floor(8 - width / 2), 11, hex("#f2f2f2"));
  c.rect(5, 1, 6, 2, hex("#4d535c"));
  return done(c);
}

/** id предмета → канва. */
export function itemTextures() {
  const m = new Map();
  m.set("iron_dust", dust(hex("#cfc8c0"), 1));
  m.set("gold_dust", dust(hex("#e8c247"), 2));
  m.set("copper_dust", dust(hex("#d4804c"), 3));
  m.set("coal_dust", dust(hex("#3a3a3d"), 4));
  m.set("diamond_dust", dust(hex("#6fe3d8"), 5));
  m.set("quartz_dust", dust(hex("#ece6dc"), 6));
  m.set("ender_dust", dust(hex("#2f8f7f"), 7));
  m.set("biomass", biomass());
  m.set("bitumen", lump(hex("#1c1b1a"), 45));
  m.set("steel_ingot", ingot(hex("#8a939c")));
  m.set("silicon", crystal(hex("#6f7d92")));
  m.set("carbon_composite", carbonSheet());
  m.set("superconductor_ingot", ingot(hex("#43c9d9")));
  m.set("iron_plate", plate(hex("#c9ccd0")));
  m.set("copper_plate", plate(hex("#c4743f")));
  m.set("gold_plate", plate(hex("#e2b83e")));
  m.set("steel_plate", plate(hex("#8a939c")));
  m.set("iron_gear", gear(hex("#c3c7cc")));
  m.set("steel_gear", gear(hex("#7f8891")));
  m.set("steel_shaft", shaft(hex("#9aa3ad")));
  m.set("copper_coil", coil());
  m.set("bearing", bearing());
  m.set("machine_casing", casing(hex("#8d949b")));
  m.set("steel_casing", casing(hex("#5c646d")));
  m.set("motor", motor());
  m.set("engine", engine());
  m.set("fuel_tank_part", fuelTankItem());
  m.set("radiator", radiator());
  m.set("turbine_blade", blade(hex("#c9ced3"), hex("#b3352d")));
  m.set("composite_blade", blade(hex("#2b2e33"), hex("#38d6e8")));
  m.set("battery_cell", batteryCell());
  m.set("circuit_basic", circuit(hex("#2e7d3b"), hex("#d9b23a"), hex("#1f2226")));
  m.set("circuit_advanced", circuit(hex("#2d4f9c"), hex("#e7e7e7"), hex("#1f2226")));
  m.set("processor", processor());
  for (let t = 1; t <= 5; t++) m.set(`control_module_${t}`, controlModule(t));
  m.set("canister", canister(null));
  m.set("canister_diesel", canister(hex("#c98a1d")));
  m.set("canister_gasoline", canister(hex("#d4473e")));
  m.set("canister_biofuel", canister(hex("#6cbc3a")));
  m.set("engineer_goggles", goggles());
  m.set("wrench", wrench());
  for (let t = 1; t <= 5; t++) m.set(`assembler_packed_t${t}`, packedAssembler(t));
  return m;
}

/** Иконки кнопок интерфейса. */
export function uiIcons() {
  const m = new Map();
  const ink = hex("#e6e9ec");
  const acc = hex("#38d6e8");
  const box = (c) => {
    c.rect(3, 9, 10, 5, hex("#5c646d"));
    c.bevel(3, 9, 10, 5, hex("#8d949b"), hex("#30343a"));
    return c;
  };
  let c = box(new Canvas(16, 16));
  c.rect(7, 1, 2, 6, acc);
  c.rect(5, 5, 6, 1, acc);
  c.rect(6, 6, 4, 1, acc);
  m.set("ui_insert", done(c));
  c = box(new Canvas(16, 16));
  c.rect(7, 2, 2, 6, hex("#4ccf5a"));
  c.rect(6, 2, 4, 1, hex("#4ccf5a"));
  c.rect(5, 3, 6, 1, hex("#4ccf5a"));
  m.set("ui_take", done(c));
  c = new Canvas(16, 16);
  for (let y = 0; y < 3; y++) for (let x = 0; x < 3; x++) c.rect(2 + x * 4, 2 + y * 4, 3, 3, (x + y) % 2 ? acc : ink);
  m.set("ui_recipes", done(c));
  c = new Canvas(16, 16);
  c.line(3, 3, 12, 8, ink);
  c.line(3, 13, 12, 8, ink);
  c.line(3, 3, 3, 13, ink);
  for (const [x, y] of [[3, 3], [3, 13], [12, 8]]) c.disc(x, y, 2, acc);
  m.set("ui_network", done(c));
  c = new Canvas(16, 16);
  c.ring(8, 8, 3.5, 5.5, ink);
  c.rect(8, 1, 4, 4, [0, 0, 0, 0]);
  for (let y = 1; y < 5; y++) for (let x = 8; x < 13; x++) c.data[(y * 16 + x) * 4 + 3] = 0;
  c.rect(9, 1, 3, 1, acc);
  c.rect(11, 1, 1, 4, acc);
  m.set("ui_refresh", done(c));
  c = new Canvas(16, 16);
  c.ring(8, 8, 3.5, 5.5, acc);
  for (let y = 7; y < 16; y++) for (let x = 0; x < 8; x++) c.data[(y * 16 + x) * 4 + 3] = 0;
  c.rect(1, 6, 5, 1, ink);
  c.rect(3, 4, 1, 5, ink);
  m.set("ui_rotate", done(c));
  c = new Canvas(16, 16);
  c.ring(8, 9, 3.8, 5.6, hex("#ff4a3d"));
  for (let y = 2; y < 7; y++) for (let x = 6; x < 10; x++) c.data[(y * 16 + x) * 4 + 3] = 0;
  c.rect(7, 2, 2, 7, ink);
  m.set("ui_power", done(c));
  c = new Canvas(16, 16);
  for (let k = 0; k < 2; k++) for (let i = 0; i < 5; i++) {
    c.set(8 - i, 4 + i + k * 5, acc);
    c.set(7 + i, 4 + i + k * 5, acc);
    c.set(8 - i, 5 + i + k * 5, acc);
    c.set(7 + i, 5 + i + k * 5, acc);
  }
  m.set("ui_upgrade", done(c));
  c = new Canvas(16, 16);
  c.rect(2, 8, 6, 6, hex("#8a6d43"));
  c.rect(8, 8, 6, 6, hex("#8a6d43"));
  c.rect(5, 2, 6, 6, hex("#a5844f"));
  c.frame(2, 8, 6, 6, hex("#5a4628"));
  c.frame(8, 8, 6, 6, hex("#5a4628"));
  c.frame(5, 2, 6, 6, hex("#5a4628"));
  m.set("ui_storage", done(c));
  return m;
}
