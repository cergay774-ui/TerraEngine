// Модернизация Ультимативного сборщика. Во время модернизации обычные рецепты не выполняются.
// Требования (модуль, материалы, компоненты) берутся из хранилища сборщика и резервируются;
// энергия потребляется на протяжении всего процесса. Состояние сохраняется в записи машины,
// поэтому переживает перезапуск мира.
import { UPGRADES, MAX_TIER } from "../data/progression.js";
import * as slots from "../logic/slots.js";
import { markDirty } from "./Registry.js";

/** Описание модернизации с уровня tier на tier+1 (или undefined на максимуме). */
export function nextUpgrade(tier) {
  return tier < MAX_TIER ? UPGRADES[tier + 1] : undefined;
}

export function currentUpgrade(rec) {
  return UPGRADES[rec.upg.to];
}

export function sanitize(rec) {
  if (!rec.upg) return;
  const to = Math.floor(Number(rec.upg.to));
  if (!UPGRADES[to] || to !== rec.tier + 1) {
    // Несогласованное состояние — вернуть резерв в хранилище.
    for (const [id, n] of slots.sanitize(rec.upg.items)) slots.add(rec.store, id, n, 1e9, 1e9);
    rec.upg = null;
    return;
  }
  rec.upg.items = slots.sanitize(rec.upg.items);
  if (!Number.isFinite(rec.upg.p)) rec.upg.p = 0;
}

/** Недостающее для модернизации: [[id, n], ...]. */
export function missingFor(rec) {
  const up = nextUpgrade(rec.tier);
  if (!up) return [];
  return slots.missing(rec.store, up.items);
}

/**
 * Запуск модернизации. Возвращает текст ошибки или null при успехе.
 * @returns {string | null}
 */
export function start(rec) {
  const up = nextUpgrade(rec.tier);
  if (!up) return "Достигнут максимальный уровень.";
  if (rec.upg) return "Модернизация уже идёт.";
  if (rec.job) return "Дождитесь завершения текущего изготовления или остановите его.";
  const planned = slots.plan(rec.store, up.items);
  if (!planned) return "Не хватает материалов для модернизации.";
  const reserved = [];
  if (!slots.reserve(rec.store, planned, reserved)) return "Не хватает материалов для модернизации.";
  rec.upg = { to: rec.tier + 1, p: 0, items: reserved };
  rec.q = 0;
  markDirty(rec);
  return null;
}

/** Отмена: резерв возвращается в хранилище, прогресс теряется. */
export function cancel(rec) {
  if (!rec.upg) return;
  for (const [id, n] of rec.upg.items) slots.add(rec.store, id, n, 1e9, 1e9);
  rec.upg = null;
  markDirty(rec);
}

export function demand(rec) {
  const up = currentUpgrade(rec);
  return rec.upg.p < up.time ? up.power : 0;
}

/** @returns {string} код состояния */
export function step(rec, env) {
  const up = currentUpgrade(rec);
  const pw = rec._power;
  if (!pw || !pw.powered) {
    markDirty(rec);
    return pw ? pw.reason : "no_power";
  }
  rec.upg.p = Math.min(up.time, rec.upg.p + env.dt);
  markDirty(rec);
  if (rec.upg.p >= up.time) {
    rec.tier = rec.upg.to;
    rec.upg = null;
    rec._justUpgraded = true;
    return "ready";
  }
  return "upgrading";
}
