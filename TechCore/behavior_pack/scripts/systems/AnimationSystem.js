// Визуальные состояния машин и лёгкие анимации.
// Блоки Bedrock не поддерживают скелетную анимацию, поэтому используются:
//  1) flipbook-текстуры (вращение роторов, огонь, лента, вращающиеся детали) — работают на GPU
//     и не требуют скриптов, переключаются состоянием блока при смене статуса;
//  2) состояние "techcore:phase" (0/1) для движущихся узлов (головка пресса, поршни, бур),
//     которое меняется не чаще CONFIG.animationTickInterval и только рядом с игроками.
// Состояние блока меняется ТОЛЬКО при реальном изменении, что исключает лишние перестройки чанков.
import { system, world } from "@minecraft/server";
import { BLOCKS } from "../data/machines.js";
import { CONFIG } from "../data/config.js";
import { STATUS } from "../core/text.js";
import { blockAtKey, setStates } from "../core/blocks.js";
import { log } from "../core/log.js";
import { records } from "./Registry.js";
import { handlerFor } from "./kinds.js";
import { settings } from "./SettingsSystem.js";

/** Индекс состояния блока: 0 — выкл/готов, 1 — работа, 2 — ожидание, 3 — ошибка. */
export function statusIndex(code) {
  return (STATUS[code] ?? STATUS.off).state;
}

/**
 * Применяет состояния блока, если изменились.
 * Обработчик может вернуть visual() — состояния основного блока —
 * и visualParts() — массив [смещение по Y, состояния] для частей мультиблока.
 */
export function syncVisual(rec, env) {
  const h = handlerFor(rec.t);
  if (!h || !h.visual) return;
  let states;
  try {
    states = h.visual(rec);
  } catch (e) {
    log.warn(`visual ${rec.t}: ${e}`);
    return;
  }
  const parts = /** @type {any} */ (h).visualParts ? /** @type {any} */ (h).visualParts(rec) : [];
  const sig = JSON.stringify([states, parts]);
  if (rec._vis === sig) return;
  const block = env.block;
  if (!block) return;
  try {
    setStates(block, states);
    for (const [dy, st] of parts) {
      const b = block.above(dy);
      if (b && b.typeId === rec.t) setStates(b, st);
    }
    rec._vis = sig;
  } catch (e) {
    log.debug(`Не удалось обновить состояние ${rec.k}: ${e}`);
  }
}

function nearPlayer(rec, radius) {
  const r2 = radius * radius;
  for (const p of world.getPlayers()) {
    if (p.dimension.id !== rec._dim) continue;
    const dx = p.location.x - rec.x;
    const dy = p.location.y - rec.y;
    const dz = p.location.z - rec.z;
    if (dx * dx + dy * dy + dz * dz <= r2) return true;
  }
  return false;
}

/** Звуки работающих машин рядом с игроками (раз в N секунд, с разносом по позиции). */
export function playSounds(stepCounter) {
  if (!settings.sounds) return;
  const every = Math.max(1, CONFIG.machineSoundIntervalSeconds);
  for (const rec of records.values()) {
    if (!rec._loaded) continue;
    const def = BLOCKS[rec.t];
    if (!def.sound) continue;
    if (statusIndex(rec.st) !== 1) continue;
    if ((stepCounter + Math.abs(rec.x + rec.z)) % every !== 0) continue;
    if (!nearPlayer(rec, CONFIG.machineSoundRadius)) continue;
    try {
      world.getDimension(rec._dim).playSound(def.sound.id, { x: rec.x + 0.5, y: rec.y + 0.5, z: rec.z + 0.5 }, {
        volume: def.sound.volume,
        pitch: def.sound.pitch * (0.95 + Math.random() * 0.1),
      });
    } catch {
      // Неизвестное звуковое событие или выгруженный чанк — звук просто не воспроизводится.
    }
  }
}

// Виды машин с движущимися узлами (состояние techcore:phase).
const PHASED = new Set([
  "techcore:press",
  "techcore:drill_rig",
  "techcore:diesel_generator",
  "techcore:gasoline_generator",
  "techcore:bio_generator",
  "techcore:ultimate_assembler",
]);

function phaseLoop() {
  let budget = settings.animationLimit;
  for (const rec of records.values()) {
    if (budget <= 0) break;
    if (!rec._loaded || !PHASED.has(rec.t)) continue;
    const working = statusIndex(rec.st) === 1;
    const want = working ? (rec._phase ? 0 : 1) : 0;
    if (!working && !rec._phase) continue;
    if (working && !nearPlayer(rec, settings.animationRadius)) continue;
    const block = blockAtKey(rec.k);
    if (!block) continue;
    try {
      setStates(block, { "techcore:phase": want });
      rec._phase = want;
      budget--;
    } catch {
      // блок мог быть заменён — проверка целостности выполнится в основном цикле
    }
  }
}

export function startAnimationLoop() {
  system.runInterval(() => {
    try {
      phaseLoop();
    } catch (e) {
      log.warn(`Сбой цикла анимаций: ${e}`);
    }
  }, CONFIG.animationTickInterval);
}
