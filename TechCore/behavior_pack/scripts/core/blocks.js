// Работа с блоками и состояниями. Пользовательские состояния TechCore отсутствуют в
// типах ванильных данных, поэтому доступ к ним собран здесь в одном месте.
import { world } from "@minecraft/server";
import { parseKey } from "./positions.js";

/** @typedef {import("@minecraft/server").Block} Block */
/** @typedef {import("@minecraft/server").BlockPermutation} BlockPermutation */

/** @param {BlockPermutation} perm @param {string} name */
export function stateOf(perm, name) {
  return perm.getAllStates()[name];
}

/**
 * Возвращает перестановку с несколькими изменёнными состояниями.
 * @param {BlockPermutation} perm @param {Record<string, boolean|number|string>} states
 */
export function withStates(perm, states) {
  /** @type {any} */
  let p = perm;
  const current = perm.getAllStates();
  for (const [k, v] of Object.entries(states)) {
    if (!(k in current) || current[k] === v) continue;
    p = p.withState(k, v);
  }
  return /** @type {BlockPermutation} */ (p);
}

/**
 * Устанавливает состояния блока, только если они реально изменились.
 * @param {Block} block @param {Record<string, boolean|number|string>} states
 * @returns {boolean} были ли изменения
 */
export function setStates(block, states) {
  const perm = block.permutation;
  const next = withStates(perm, states);
  if (next === perm) return false;
  block.setPermutation(next);
  return true;
}

/**
 * Блок по ключу, если чанк загружен. Никогда не бросает исключение.
 * @param {string} key
 * @returns {Block | undefined}
 */
export function blockAtKey(key) {
  const p = parseKey(key);
  return blockAt(p.dim, p.x, p.y, p.z);
}

/** @returns {Block | undefined} */
export function blockAt(dimId, x, y, z) {
  try {
    const dim = world.getDimension(dimId);
    const loc = { x, y, z };
    if (!dim.isChunkLoaded(loc)) return undefined;
    const b = dim.getBlock(loc);
    return b && b.isValid ? b : undefined;
  } catch {
    return undefined;
  }
}

/**
 * Соседний блок со смещением; undefined, если чанк не загружен (offset в этом случае бросает исключение).
 * @param {Block} block
 * @returns {Block | undefined}
 */
export function safeOffset(block, dx, dy, dz) {
  return blockAt(block.dimension.id, block.x + dx, block.y + dy, block.z + dz);
}

/** Загружен ли чанк позиции. */
export function isLoaded(dimId, x, y, z) {
  try {
    return world.getDimension(dimId).isChunkLoaded({ x, y, z });
  } catch {
    return false;
  }
}

/** Часть мультиблока (0 для обычных блоков). @param {BlockPermutation} perm */
export function multiPart(perm) {
  const v = stateOf(perm, "minecraft:multi_block_part");
  return typeof v === "number" ? v : 0;
}
