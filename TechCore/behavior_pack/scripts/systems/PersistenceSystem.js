// Сохранение состояния машин в динамических свойствах мира.
// Одна запись = одно свойство "tc:m:<ключ позиции>" со строкой JSON (лимит строки ~32 КБ).
// Поля, начинающиеся с "_", считаются временными и не сохраняются.
// Изменения копятся в наборе dirty и записываются пакетом каждые CONFIG.saveTickInterval тиков,
// а после операций с предметами — немедленно (saveNow), чтобы аварийное закрытие игры
// не расходилось с инвентарём игрока сильнее, чем позволяет сам движок.
import { world } from "@minecraft/server";
import { log } from "../core/log.js";

const PREFIX = "tc:m:";
const SETTINGS_KEY = "tc:settings";
const MAX_LEN = 32000;

/** @type {Set<any>} */
const dirty = new Set();

// Координаты и ключ восстанавливаются из имени свойства — в JSON их не дублируем.
const DERIVED = new Set(["k", "x", "y", "z"]);

function serialize(rec) {
  return JSON.stringify(rec, function (k, v) {
    if (k.startsWith("_")) return undefined;
    if (this === rec && DERIVED.has(k)) return undefined;
    return v;
  });
}

/** Загружает все записи машин. @returns {Array<{key: string, data: any}>} */
export function loadAll() {
  /** @type {Array<{key: string, data: any}>} */
  const out = [];
  for (const id of world.getDynamicPropertyIds()) {
    if (!id.startsWith(PREFIX)) continue;
    const raw = world.getDynamicProperty(id);
    if (typeof raw !== "string") continue;
    try {
      out.push({ key: id.slice(PREFIX.length), data: JSON.parse(raw) });
    } catch (e) {
      log.warn(`Повреждённая запись ${id} пропущена: ${e}`);
    }
  }
  return out;
}

export function markDirty(rec) {
  dirty.add(rec);
}

/** Немедленная запись одной машины. */
export function saveNow(rec) {
  dirty.delete(rec);
  write(rec);
}

function write(rec) {
  if (rec._removed) return;
  const json = serialize(rec);
  if (json.length > MAX_LEN) {
    log.warn(`Запись ${rec.k} слишком велика (${json.length}), сохранение пропущено`);
    return;
  }
  world.setDynamicProperty(PREFIX + rec.k, json);
}

export function erase(key) {
  world.setDynamicProperty(PREFIX + key, undefined);
}

export function flushDirty() {
  for (const rec of dirty) {
    try {
      write(rec);
    } catch (e) {
      log.warn(`Ошибка сохранения ${rec.k}: ${e}`);
    }
  }
  dirty.clear();
}

export function loadSettings() {
  const raw = world.getDynamicProperty(SETTINGS_KEY);
  if (typeof raw !== "string") return {};
  try {
    return JSON.parse(raw);
  } catch {
    return {};
  }
}

export function saveSettings(obj) {
  world.setDynamicProperty(SETTINGS_KEY, JSON.stringify(obj));
}
