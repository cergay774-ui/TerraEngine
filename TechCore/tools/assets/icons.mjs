// Изометрические иконки блоков (для кнопок интерфейса), иконка пакета и текстура очков.
import { Canvas, hex, shade, scale } from "./canvas.mjs";

// Какие текстуры показывать на гранях иконки: [верх, лицевая (слева), боковая (справа)].
const FACES = {
  ultimate_assembler: ["steel", "screen_ok", "vent"],
  coal_generator: ["steel", "fire_off", "vent"],
  diesel_generator: ["frame", "vent", "panel"],
  gasoline_generator: ["tank_red", "panel", "vent"],
  bio_generator: ["frame", "glass_green", "panel"],
  battery_basic: ["steel", "battery_4", "vent"],
  battery_advanced: ["steel", "battery_4", "accent_t3"],
  copper_wire: ["wire_copper", "wire_copper", "wire_copper"],
  insulated_wire: ["wire_insulated", "wire_insulated", "wire_insulated"],
  reinforced_wire: ["wire_reinforced", "wire_reinforced", "wire_reinforced"],
  superconductor_wire: ["wire_super", "wire_super", "wire_super"],
  fluid_pipe: ["pipe", "pipe", "pipe"],
  drill_rig: ["hazard", "drill", "frame"],
  crusher: ["roller", "panel", "vent"],
  electric_smelter: ["copper", "glow_off", "insul"],
  press: ["steel", "hazard", "frame"],
  lathe: ["steel", "chuck", "panel"],
  fuel_refinery: ["hazard", "tank_white", "glass_amber"],
  conveyor: ["belt", "frame", "frame"],
  item_filter: ["belt", "screen_ok", "frame"],
  splitter: ["belt", "hazard", "frame"],
  buffer_crate: ["frame", "crate", "crate"],
  fuel_tank: ["steel", "tank_w_1_3", "tank_white"],
  wind_turbine_1: ["frame", "rotor1", "steel"],
  wind_turbine_2: ["frame", "rotor2", "steel"],
  wind_turbine_3: ["frame", "rotor3", "tank_white"],
  wind_turbine_4: ["frame", "rotor4", "tank_white"],
  wind_turbine_5: ["frame", "rotor5", "tank_white"],
};

function sample(tex, u, v) {
  const c = tex.canvas;
  const w = c.w;
  const frameH = c.w; // ленты flipbook — берём первый кадр
  const x = Math.min(w - 1, Math.max(0, Math.floor((u / 16) * w)));
  const y = Math.min(frameH - 1, Math.max(0, Math.floor((v / 16) * frameH)));
  return c.get(x, y);
}

/** Изометрический куб 32×32. */
export function blockIcon(name, textures) {
  const [top, left, right] = (FACES[name] ?? ["frame", "panel", "panel"]).map((n) => textures.get(n));
  const out = new Canvas(32, 32);
  const fallback = hex("#6b6f75");
  for (let Y = 0; Y < 32; Y++)
    for (let X = 0; X < 32; X++) {
      const px = X + 0.5;
      const py = Y + 0.5;
      // Верх: ромб.
      const a = ((px - 16) * 16) / 15;
      const b = ((py - 1) * 16) / 7.5;
      let u = (a + b) / 2;
      let v = (b - a) / 2;
      if (u >= 0 && u < 16 && v >= 0 && v < 16) {
        const c = top ? sample(top, u, v) : fallback;
        if (c[3] > 0) out.set(X, Y, c);
        continue;
      }
      if (px < 16) {
        u = ((px - 1) * 16) / 15;
        v = py - 8.5 - (u * 7.5) / 16;
        if (u >= 0 && u < 16 && v >= 0 && v < 16) {
          const c = left ? sample(left, u, v) : fallback;
          if (c[3] > 0) out.set(X, Y, shade(c, 0.85));
        }
      } else {
        u = ((px - 16) * 16) / 15;
        v = py - 16 + (u * 7.5) / 16;
        if (u >= 0 && u < 16 && v >= 0 && v < 16) {
          const c = right ? sample(right, u, v) : fallback;
          if (c[3] > 0) out.set(X, Y, shade(c, 0.62));
        }
      }
    }
  return out;
}

/** Иконка пакета 128×128: изометрия сборщика на тёмном фоне. */
export function packIcon(textures) {
  const bg = new Canvas(128, 128).fill(hex("#15181c"));
  for (let y = 0; y < 128; y += 8) for (let x = 0; x < 128; x++) bg.set(x, y, hex("#1c2026"));
  for (let x = 0; x < 128; x += 8) for (let y = 0; y < 128; y++) bg.set(x, y, hex("#1c2026"));
  const iso = scale(blockIcon("ultimate_assembler", textures), 4);
  bg.blit(iso, 0, 0);
  for (let x = 8; x < 120; x++) bg.set(x, 122, hex("#38d6e8"));
  return bg;
}

/**
 * Текстура слоя шлема (64×32) для очков: ремешок вокруг головы и две линзы спереди.
 * Раскладка UV головы брони: правая (0..8, 8..16), перед (8..16, 8..16),
 * левая (16..24, 8..16), зад (24..32, 8..16).
 */
export function goggleArmor() {
  const c = new Canvas(64, 32);
  const strap = hex("#5b4a35");
  const rim = hex("#8a6d43");
  const lens = hex("#38d6e8");
  for (let x = 0; x < 32; x++) {
    c.set(x, 11, strap);
    c.set(x, 12, shade(strap, 0.8));
  }
  for (const x0 of [9, 12]) {
    c.rect(x0, 10, 3, 3, rim);
    c.set(x0 + 1, 11, lens);
  }
  c.set(10, 10, rim);
  c.rect(9, 9, 6, 1, rim);
  return c;
}
