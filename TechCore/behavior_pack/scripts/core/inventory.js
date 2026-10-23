// Безопасные операции с инвентарём игрока и выпадением предметов.
// Каждая операция синхронна (без await между проверкой и изменением), поэтому
// в однопоточном Script API между чтением и записью не может произойти чужое действие.
import { EquipmentSlot, ItemStack } from "@minecraft/server";

/** @typedef {import("@minecraft/server").Player} Player */
/** @typedef {import("@minecraft/server").ItemStack} Stack */

/**
 * Принимаются только "простые" стаки: без имени, описания, зачарований, износа и
 * динамических свойств. Иначе виртуальное хранилище потеряло бы эти данные.
 * @param {Stack | undefined} stack
 */
export function isPlainStack(stack) {
  if (!stack) return false;
  try {
    if (stack.nameTag) return false;
    if (stack.getLore().length > 0) return false;
    if (stack.getDynamicPropertyIds().length > 0) return false;
    const ench = stack.getComponent("minecraft:enchantable");
    if (ench && ench.getEnchantments().length > 0) return false;
    const dur = stack.getComponent("minecraft:durability");
    if (dur && dur.damage > 0) return false;
  } catch {
    return false;
  }
  return true;
}

/** @param {Player} player */
export function playerContainer(player) {
  return player.getComponent("minecraft:inventory")?.container;
}

/**
 * Переносит предметы из инвентаря игрока.
 * accept(id) → сколько единиц можно принять сейчас; commit(id, n) — зачисление.
 * Сначала уменьшается стак игрока, затем вызывается commit — в одном синхронном шаге.
 * @param {Player} player
 * @param {(id: string) => number} accept
 * @param {(id: string, n: number) => void} commit
 * @param {{ onlySelected?: boolean }} [opts]
 * @returns {number} перенесено единиц
 */
export function takeFromPlayer(player, accept, commit, opts = {}) {
  let moved = 0;
  if (opts.onlySelected) {
    const eq = player.getComponent("minecraft:equippable");
    const slot = eq?.getEquipmentSlot(EquipmentSlot.Mainhand);
    if (!slot || !slot.hasItem()) return 0;
    const stack = slot.getItem();
    if (!isPlainStack(stack) || !stack) return 0;
    const n = Math.min(stack.amount, Math.max(0, Math.floor(accept(stack.typeId))));
    if (n <= 0) return 0;
    const id = stack.typeId;
    if (n >= stack.amount) slot.setItem(undefined);
    else slot.amount = stack.amount - n;
    commit(id, n);
    return n;
  }
  const inv = playerContainer(player);
  if (!inv) return 0;
  for (let i = 0; i < inv.size; i++) {
    const stack = inv.getItem(i);
    if (!stack || !isPlainStack(stack)) continue;
    const n = Math.min(stack.amount, Math.max(0, Math.floor(accept(stack.typeId))));
    if (n <= 0) continue;
    const id = stack.typeId;
    if (n >= stack.amount) inv.setItem(i, undefined);
    else {
      stack.amount -= n;
      inv.setItem(i, stack);
    }
    commit(id, n);
    moved += n;
  }
  return moved;
}

/**
 * Выдаёт игроку до n единиц. Возвращает фактически выданное количество —
 * остаток вызывающая сторона обязана оставить в машине.
 * @param {Player} player @param {string} id @param {number} n
 */
export function giveToPlayer(player, id, n) {
  const inv = playerContainer(player);
  if (!inv || n <= 0) return 0;
  let given = 0;
  let max = 64;
  try {
    max = new ItemStack(id, 1).maxAmount;
  } catch {
    return 0;
  }
  while (given < n) {
    const chunk = Math.min(max, n - given);
    const leftover = inv.addItem(new ItemStack(id, chunk));
    const placed = chunk - (leftover ? leftover.amount : 0);
    given += placed;
    if (placed < chunk) break;
  }
  return given;
}

/** Количество предметов id в инвентаре игрока (только простые стаки). @param {Player} player */
export function countInPlayer(player, id) {
  const inv = playerContainer(player);
  if (!inv) return 0;
  let n = 0;
  for (let i = 0; i < inv.size; i++) {
    const s = inv.getItem(i);
    if (s && s.typeId === id && isPlainStack(s)) n += s.amount;
  }
  return n;
}

/** Предмет в основной руке. @param {Player} player */
export function heldItem(player) {
  const eq = player.getComponent("minecraft:equippable");
  return eq?.getEquipment(EquipmentSlot.Mainhand);
}

/**
 * Заменяет один предмет в руке другим (например, полная канистра → пустая).
 * @param {Player} player @param {string} expectId @param {string | undefined} newId
 * @returns {boolean}
 */
export function swapHeldOne(player, expectId, newId) {
  const eq = player.getComponent("minecraft:equippable");
  const slot = eq?.getEquipmentSlot(EquipmentSlot.Mainhand);
  if (!slot || !slot.hasItem()) return false;
  const stack = slot.getItem();
  if (!stack || stack.typeId !== expectId || !isPlainStack(stack)) return false;
  if (stack.amount > 1) {
    slot.amount = stack.amount - 1;
    if (newId && giveToPlayer(player, newId, 1) < 1) {
      player.dimension.spawnItem(new ItemStack(newId, 1), player.location);
    }
  } else {
    slot.setItem(newId ? new ItemStack(newId, 1) : undefined);
  }
  return true;
}

/**
 * Выбрасывает содержимое слотов в мир.
 * @param {import("@minecraft/server").Dimension} dimension
 * @param {import("@minecraft/server").Vector3} location
 * @param {Array<[string, number]>} slots
 */
export function dropSlots(dimension, location, slots) {
  for (const [id, n] of slots) {
    let left = n;
    let max = 64;
    try {
      max = new ItemStack(id, 1).maxAmount;
    } catch {
      continue;
    }
    while (left > 0) {
      const chunk = Math.min(max, left);
      try {
        dimension.spawnItem(new ItemStack(id, chunk), location);
      } catch {
        // Измерение/чанк недоступны — дальнейшее выпадение невозможно.
        return;
      }
      left -= chunk;
    }
  }
}
