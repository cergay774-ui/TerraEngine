// Тексты интерфейса. Названия предметов выводятся через ключи локализации игры (RawMessage),
// поэтому ванильные и аддонные предметы отображаются на языке клиента.
import { ItemStack } from "@minecraft/server";
import { FLUIDS } from "../data/items.js";

/** @typedef {import("@minecraft/server").RawMessage} RawMessage */

const keyCache = new Map();

/** Ключ локализации предмета (кэшируется). */
export function itemKey(id) {
  let key = keyCache.get(id);
  if (key === undefined) {
    try {
      key = new ItemStack(id, 1).localizationKey;
    } catch {
      key = id;
    }
    keyCache.set(id, key);
  }
  return key;
}

/** @returns {RawMessage} */
export function itemName(id) {
  return { translate: itemKey(id) };
}

/** Название для требования с вариантами: первый вариант + пометка. @returns {RawMessage} */
export function reqName(what) {
  if (Array.isArray(what)) return { rawtext: [itemName(what[0]), { text: " (или аналог)" }] };
  return itemName(what);
}

/** Собирает RawMessage из строк и сообщений. @param {...(string|RawMessage)} parts @returns {RawMessage} */
export function rt(...parts) {
  return { rawtext: parts.map((p) => (typeof p === "string" ? { text: p } : p)) };
}

/** Число с разделением разрядов и фиксированной точностью. */
export function num(v, digits = 0) {
  if (!Number.isFinite(v)) return "—";
  const fixed = v.toFixed(digits);
  const [i, f] = fixed.split(".");
  const grouped = i.replace(/\B(?=(\d{3})+(?!\d))/g, " ");
  return f ? `${grouped}.${f}` : grouped;
}

export function pct(v) {
  return `${Math.round(Math.max(0, v) * 100)}%`;
}

export function seconds(s) {
  s = Math.max(0, Math.ceil(s));
  if (s < 60) return `${s} с`;
  const m = Math.floor(s / 60);
  const r = s % 60;
  return r ? `${m} мин ${r} с` : `${m} мин`;
}

export function fluidName(f) {
  return f && FLUIDS[f] ? FLUIDS[f].ru : "пусто";
}

/** Текстовая полоса прогресса из символов (без эмодзи). */
export function bar(fraction, width = 20) {
  const n = Math.max(0, Math.min(width, Math.round(fraction * width)));
  return `§a${"|".repeat(n)}§8${"|".repeat(width - n)}§r`;
}

// Коды состояний машин и их отображение.
export const STATUS = {
  off: { ru: "Выключено", color: "§7", state: 0 },
  ready: { ru: "Готов", color: "§f", state: 0 },
  working: { ru: "Работает", color: "§a", state: 1 },
  waiting: { ru: "Ожидает ресурсы", color: "§e", state: 2 },
  idle_load: { ru: "Ожидание: нет нагрузки", color: "§e", state: 2 },
  blocked: { ru: "Выход заблокирован", color: "§6", state: 2 },
  no_power: { ru: "Нет энергии", color: "§c", state: 3 },
  line_limit: { ru: "Перегрузка линии", color: "§c", state: 3 },
  no_fuel: { ru: "Нет топлива", color: "§c", state: 3 },
  no_wind: { ru: "Нет ветра", color: "§7", state: 0 },
  overheat: { ru: "Перегрев: мощность ограничена", color: "§6", state: 2 },
  upgrading: { ru: "Модернизация", color: "§b", state: 1 },
  done: { ru: "Бурение завершено", color: "§7", state: 0 },
  charging: { ru: "Зарядка", color: "§a", state: 1 },
  discharging: { ru: "Разрядка", color: "§e", state: 1 },
  full: { ru: "Заряжен", color: "§b", state: 0 },
  empty: { ru: "Разряжен", color: "§7", state: 0 },
};

export function statusText(code) {
  const s = STATUS[code] ?? STATUS.off;
  return `${s.color}${s.ru}§r`;
}

export const PRIORITY_RU = { 1: "Высокий", 2: "Средний", 3: "Низкий" };
