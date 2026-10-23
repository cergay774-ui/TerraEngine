// Общие помощники интерфейса (формы @minecraft/server-ui).
// Правило безопасности: после ответа формы запись машины перечитывается по ключу (live),
// и все проверки повторяются — пока форма была открыта, машину могли сломать, а предметы
// мог забрать другой игрок.
import { system } from "@minecraft/server";
import { FormCancelationReason } from "@minecraft/server-ui";
import { ITEM_BY_ID } from "../data/items.js";
import { BLOCKS } from "../data/machines.js";
import { itemName, rt } from "../core/text.js";
import { records } from "../systems/Registry.js";

/** @typedef {import("@minecraft/server").Player} Player */
/** @typedef {import("@minecraft/server").RawMessage} RawMessage */

/** Актуальная запись машины или undefined, если её больше нет. */
export function live(key) {
  const r = records.get(key);
  return r && !r._removed ? r : undefined;
}

/**
 * Показ формы с повтором, если игрок занят (например, ещё открыт экран взаимодействия).
 * @template T
 * @param {Player} player
 * @param {{ show: (p: Player) => Promise<T> }} form
 * @returns {Promise<T | undefined>}
 */
export async function showForm(player, form) {
  for (let attempt = 0; attempt < 10; attempt++) {
    /** @type {any} */
    const res = await form.show(player);
    if (res.canceled && res.cancelationReason === FormCancelationReason.UserBusy) {
      await system.waitTicks(4);
      continue;
    }
    if (res.canceled) return undefined;
    return res;
  }
  return undefined;
}

/** Путь к иконке предмета для кнопок формы. */
export function itemIcon(id) {
  if (!id) return undefined;
  const short = id.slice(id.indexOf(":") + 1);
  if (id.startsWith("techcore:")) {
    if (ITEM_BY_ID.has(id)) return `textures/techcore/items/${short}`;
    if (BLOCKS[id]) return `textures/techcore/icons/${short}`;
    return undefined;
  }
  return VANILLA_ICONS[short];
}

// Иконки ванильных предметов, используемых в рецептах (пути ванильного пакета ресурсов).
const VANILLA_ICONS = {
  diamond: "textures/items/diamond",
  gold_ingot: "textures/items/gold_ingot",
  iron_ingot: "textures/items/iron_ingot",
  copper_ingot: "textures/items/copper_ingot",
  iron_nugget: "textures/items/iron_nugget",
  redstone: "textures/items/redstone_dust",
  coal: "textures/items/coal",
  charcoal: "textures/items/charcoal",
  raw_iron: "textures/items/raw_iron",
  raw_gold: "textures/items/raw_gold",
  raw_copper: "textures/items/raw_copper",
  quartz: "textures/items/quartz",
  ender_pearl: "textures/items/ender_pearl",
  flint: "textures/items/flint",
  leather: "textures/items/leather",
  bucket: "textures/items/bucket_empty",
  stick: "textures/items/stick",
  dried_kelp: "textures/items/dried_kelp",
  wheat: "textures/items/wheat",
  blaze_rod: "textures/items/blaze_rod",
  diamond_pickaxe: "textures/items/diamond_pickaxe",
  emerald: "textures/items/emerald",
  lapis_lazuli: "textures/items/dye_powder_blue",
  clay_ball: "textures/items/clay_ball",
  gold_nugget: "textures/items/gold_nugget",
  cobblestone: "textures/blocks/cobblestone",
  sand: "textures/blocks/sand",
  gravel: "textures/blocks/gravel",
  glass: "textures/blocks/glass",
};

/**
 * Строки содержимого слотов: "  Название ×N".
 * @param {Array<[string, number]>} list
 * @returns {RawMessage}
 */
export function slotsText(list, emptyText = "  пусто") {
  if (!list || list.length === 0) return rt(`§7${emptyText}§r\n`);
  const parts = [];
  for (const [id, n] of list) parts.push(rt("  ", itemName(id), ` §7×${n}§r\n`));
  return { rawtext: parts };
}

/** Короткое уведомление игроку. @param {Player} player @param {string | RawMessage} text */
export function tell(player, text) {
  player.sendMessage(text);
}

/** Название машины по типу. @returns {RawMessage} */
export function machineName(typeId) {
  return { translate: `tile.${typeId}.name` };
}
