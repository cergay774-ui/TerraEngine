// Виртуальные слоты машин: массив пар [идентификатор, количество].
// Модуль не зависит от API Minecraft и покрыт тестами (tools/tests).
// Все операции либо выполняются полностью, либо не меняют состояние —
// это основа защиты от дублирования и потери предметов.

/** @typedef {[string, number]} Slot */

/** @param {Slot[]} slots @param {string} id */
export function countOf(slots, id) {
  let n = 0;
  for (const s of slots) if (s[0] === id) n += s[1];
  return n;
}

/**
 * Сколько единиц предмета можно принять.
 * @param {Slot[]} slots @param {string} id @param {number} maxSlots @param {number} cap
 */
export function acceptable(slots, id, maxSlots, cap) {
  let room = 0;
  for (const s of slots) if (s[0] === id) room += Math.max(0, cap - s[1]);
  const free = Math.max(0, maxSlots - slots.length);
  return room + free * cap;
}

/**
 * Добавляет до n единиц, возвращает фактически добавленное количество.
 * @param {Slot[]} slots @param {string} id @param {number} n @param {number} maxSlots @param {number} cap
 */
export function add(slots, id, n, maxSlots, cap) {
  let left = Math.max(0, Math.floor(n));
  for (const s of slots) {
    if (left <= 0) break;
    if (s[0] !== id || s[1] >= cap) continue;
    const take = Math.min(cap - s[1], left);
    s[1] += take;
    left -= take;
  }
  while (left > 0 && slots.length < maxSlots) {
    const take = Math.min(cap, left);
    slots.push([id, take]);
    left -= take;
  }
  return Math.floor(n) - left;
}

/**
 * Удаляет до n единиц, возвращает фактически удалённое количество.
 * @param {Slot[]} slots @param {string} id @param {number} n
 */
export function remove(slots, id, n) {
  let left = Math.max(0, Math.floor(n));
  for (let i = slots.length - 1; i >= 0 && left > 0; i--) {
    const s = slots[i];
    if (s[0] !== id) continue;
    const take = Math.min(s[1], left);
    s[1] -= take;
    left -= take;
    if (s[1] <= 0) slots.splice(i, 1);
  }
  return Math.floor(n) - left;
}

/** @param {Slot[]} slots */
export function clone(slots) {
  return slots.map((s) => /** @type {Slot} */ ([s[0], s[1]]));
}

/**
 * Проверяет, что все предметы поместятся одновременно.
 * @param {Slot[]} slots @param {Slot[]} items @param {number} maxSlots @param {number} cap
 */
export function fitsAll(slots, items, maxSlots, cap) {
  const copy = clone(slots);
  for (const [id, n] of items) {
    if (add(copy, id, n, maxSlots, cap) < n) return false;
  }
  return true;
}

/** Общее число предметов. @param {Slot[]} slots */
export function total(slots) {
  let n = 0;
  for (const s of slots) n += s[1];
  return n;
}

/** Объединяет одинаковые предметы в карту id → количество. @param {Slot[]} slots */
export function toMap(slots) {
  /** @type {Map<string, number>} */
  const m = new Map();
  for (const [id, n] of slots) m.set(id, (m.get(id) ?? 0) + n);
  return m;
}

/**
 * Подбирает конкретные предметы под список требований с вариантами.
 * req: [идентификатор | массив вариантов, количество].
 * Возвращает план [[id, n], ...] или null, если не хватает.
 * Варианты учитываются без двойного счёта (план строится на копии).
 * @param {Slot[]} slots @param {Array<[string|string[], number]>} reqs
 * @returns {Slot[] | null}
 */
export function plan(slots, reqs) {
  const avail = toMap(slots);
  /** @type {Slot[]} */
  const result = [];
  for (const [what, need] of reqs) {
    const options = Array.isArray(what) ? what : [what];
    let left = need;
    for (const id of options) {
      if (left <= 0) break;
      const have = avail.get(id) ?? 0;
      if (have <= 0) continue;
      const take = Math.min(have, left);
      avail.set(id, have - take);
      result.push([id, take]);
      left -= take;
    }
    if (left > 0) return null;
  }
  return result;
}

/**
 * Список недостающих позиций: [[требование, не хватает], ...].
 * @param {Slot[]} slots @param {Array<[string|string[], number]>} reqs
 */
export function missing(slots, reqs) {
  const avail = toMap(slots);
  /** @type {Array<[string|string[], number]>} */
  const out = [];
  for (const [what, need] of reqs) {
    const options = Array.isArray(what) ? what : [what];
    let left = need;
    for (const id of options) {
      if (left <= 0) break;
      const have = avail.get(id) ?? 0;
      const take = Math.min(have, left);
      avail.set(id, have - take);
      left -= take;
    }
    if (left > 0) out.push([what, left]);
  }
  return out;
}

/**
 * Атомарно переносит план из slots в отдельный массив (резерв).
 * Возвращает true, если всё перенесено; иначе состояние не меняется.
 * @param {Slot[]} slots @param {Slot[]} planned @param {Slot[]} reserve
 */
export function reserve(slots, planned, reserve) {
  for (const [id, n] of planned) if (countOf(slots, id) < n) return false;
  for (const [id, n] of planned) {
    remove(slots, id, n);
    const existing = reserve.find((s) => s[0] === id);
    if (existing) existing[1] += n;
    else reserve.push([id, n]);
  }
  return true;
}

/** Проверка корректности структуры, пришедшей из сохранения. */
export function sanitize(value) {
  if (!Array.isArray(value)) return [];
  /** @type {Slot[]} */
  const out = [];
  for (const s of value) {
    if (!Array.isArray(s) || typeof s[0] !== "string") continue;
    const n = Math.floor(Number(s[1]));
    if (n > 0 && Number.isFinite(n)) out.push([s[0], n]);
  }
  return out;
}
