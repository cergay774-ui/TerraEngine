// Реестр установленных машин TechCore (в памяти) + связь с сохранением.
// Ключ записи — позиция блока; для мультиблоков (ветрогенераторов) — позиция нижней части.
import { system, world } from "@minecraft/server";
import { BLOCKS, hasRecord } from "../data/machines.js";
import { parseKey, posKey } from "../core/positions.js";
import { dropSlots } from "../core/inventory.js";
import { log } from "../core/log.js";
import { handlerFor } from "./kinds.js";
import * as persistence from "./PersistenceSystem.js";

/** @type {Map<string, any>} */
export const records = new Map();

/** Подписчики на изменения топологии (сети энергии, жидкостей, транспорта). */
const topologyListeners = [];

/** @param {(key: string, typeId: string) => void} fn */
export function onTopologyChange(fn) {
  topologyListeners.push(fn);
}

export function notifyTopology(key, typeId) {
  for (const fn of topologyListeners) {
    try {
      fn(key, typeId);
    } catch (e) {
      log.warn(`Ошибка обработчика топологии: ${e}`);
    }
  }
}

function attach(key, data) {
  const p = parseKey(key);
  data.k = key;
  data._dim = p.dim;
  data.x = p.x;
  data.y = p.y;
  data.z = p.z;
  return data;
}

/** Загрузка из мира при старте. */
export function loadRecords() {
  let count = 0;
  for (const { key, data } of persistence.loadAll()) {
    if (!data || typeof data.t !== "string" || !BLOCKS[data.t]) {
      persistence.erase(key);
      continue;
    }
    const rec = attach(key, data);
    const h = handlerFor(rec.t);
    if (h) {
      h.init(rec);
      h.sanitize(rec);
    }
    records.set(key, rec);
    count++;
  }
  log.info(`Загружено машин: ${count}`);
}

export function get(key) {
  return records.get(key);
}

/**
 * Создание записи для нового блока. Если по этой позиции осталась устаревшая запись
 * (блок был удалён без события разрушения), её содержимое выбрасывается — это не дубль,
 * т.к. ранее оно не выпадало.
 * @param {string} typeId @param {string} dimId @param {number} x @param {number} y @param {number} z
 * @param {Record<string, any>} [extra]
 */
export function create(typeId, dimId, x, y, z, extra) {
  if (!hasRecord(typeId)) return undefined;
  const key = posKey(dimId, x, y, z);
  const stale = records.get(key);
  if (stale) destroy(key, true);
  const rec = attach(key, { t: typeId, ...(extra ?? {}) });
  const h = handlerFor(typeId);
  if (h) h.init(rec);
  records.set(key, rec);
  persistence.saveNow(rec);
  notifyTopology(key, typeId);
  return rec;
}

/**
 * Удаление записи с выпадением содержимого.
 * @param {string} key @param {boolean} dropContents
 */
export function destroy(key, dropContents) {
  const rec = records.get(key);
  if (!rec) return;
  records.delete(key);
  rec._removed = true;
  persistence.erase(key);
  if (dropContents) {
    const h = handlerFor(rec.t);
    const items = h ? h.contents(rec) : [];
    if (items.length > 0) {
      const loc = { x: rec.x + 0.5, y: rec.y + 0.5, z: rec.z + 0.5 };
      // Выпадение — в следующем тике: событие разрушения может прийти в ограниченном контексте.
      system.run(() => {
        try {
          dropSlots(world.getDimension(rec._dim), loc, items);
        } catch (e) {
          log.warn(`Не удалось выбросить содержимое ${key}: ${e}`);
        }
      });
    }
  }
  notifyTopology(key, rec.t);
}

export function markDirty(rec) {
  persistence.markDirty(rec);
}

export function saveNow(rec) {
  persistence.saveNow(rec);
}

/** Все записи заданного вида. */
export function* ofKind(kind) {
  for (const rec of records.values()) if (BLOCKS[rec.t]?.kind === kind) yield rec;
}
