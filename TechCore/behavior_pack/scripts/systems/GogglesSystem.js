// Инженерные очки. Bedrock не позволяет добавить в инвентарь новый слот, поэтому очки
// носятся в штатном отдельном слоте шлема (slot.armor.head) или во второй руке.
// Пока очки надеты, при наведении на блок TechCore в строке действия отображаются
// эффективность, потребление/выработка энергии и состояние сети.
import { system, world, EquipmentSlot } from "@minecraft/server";
import { BLOCKS } from "../data/machines.js";
import { WIRES, PIPES } from "../data/wires.js";
import { CONFIG } from "../data/config.js";
import { posKey } from "../core/positions.js";
import { multiPart } from "../core/blocks.js";
import { statusText, num, pct } from "../core/text.js";
import { log } from "../core/log.js";
import { records } from "./Registry.js";
import { handlerFor } from "./kinds.js";
import { networkAt } from "./EnergySystem.js";
import { fluidNetworkOf } from "./FuelSystem.js";

const GOGGLES = "techcore:engineer_goggles";

/** @param {import("@minecraft/server").Player} player */
export function wearsGoggles(player) {
  const eq = player.getComponent("minecraft:equippable");
  if (!eq) return false;
  return eq.getEquipment(EquipmentSlot.Head)?.typeId === GOGGLES || eq.getEquipment(EquipmentSlot.Offhand)?.typeId === GOGGLES;
}

function networkLine(net) {
  if (!net || !net.stats) return "§7Сеть: нет данных§r";
  const s = net.stats;
  const lossPct = s.generation > 0 ? s.losses / s.generation : 0;
  return `§7Сеть: §f${num(s.generation, 1)}§7/${num(s.available, 1)} E/с выработка, §f${num(s.demand, 1)}§7 E/с спрос, потери §f${pct(lossPct)}§7, запас §f${num(s.stored)}§7 E§r`;
}

/** Текст для блока под взглядом. @returns {import("@minecraft/server").RawMessage | undefined} */
export function describeBlock(block) {
  const typeId = block.typeId;
  const def = BLOCKS[typeId];
  if (!def) return undefined;
  const name = { translate: `tile.${typeId}.name` };

  if (def.role === "wire") {
    const w = WIRES[typeId];
    const net = networkAt(posKey(block.dimension.id, block.x, block.y, block.z));
    return {
      rawtext: [
        { text: "§l" },
        name,
        { text: `§r\n§7Пропускная способность: §f${w.capacity} E/с§7, потери: §f${(w.loss * 100).toFixed(3)}%/блок\n` },
        { text: networkLine(net) },
      ],
    };
  }
  if (def.role === "pipe") {
    const net = fluidNetworkOf(posKey(block.dimension.id, block.x, block.y, block.z));
    return {
      rawtext: [{ text: "§l" }, name, { text: `§r\n§7Пропускная способность: §f${PIPES[typeId].throughput} мБ/с§7, узлов в сети: §f${net ? net.nodes.length : 0}` }],
    };
  }

  const part = multiPart(block.permutation);
  const key = posKey(block.dimension.id, block.x, block.y - part, block.z);
  const rec = records.get(key);
  if (!rec) return { rawtext: [name, { text: "\n§7Нет данных (машина регистрируется)" }] };
  const h = handlerFor(rec.t);
  const info = h && h.info ? h.info(rec) : { lines: [] };
  const parts = [{ text: "§l" }, name, { text: `§r  ${statusText(rec.st)}\n` }];

  const eff = info.efficiency;
  let energyLine = "";
  if (def.role === "generator") {
    energyLine = `§7Эффективность: §f${pct(eff ?? 0)}§7  Выработка: §a${num(info.powerOut ?? 0, 1)} E/с`;
  } else if (def.role === "consumer") {
    energyLine = `§7Эффективность: §f${pct(eff ?? 0)}§7  Потребление: §c${num(info.powerIn ?? 0, 1)} E/с`;
    if (info.lossPct) energyLine += `§7  Потери линии: §f${(info.lossPct * 100).toFixed(1)}%`;
  } else if (def.role === "storage") {
    energyLine = `§7Загрузка: §f${pct(eff ?? 0)}§7  Вход: §a${num(info.powerIn ?? 0, 1)}§7  Выход: §c${num(info.powerOut ?? 0, 1)} E/с`;
  }
  if (energyLine) parts.push({ text: `${energyLine}§r\n` });
  for (const line of info.lines.slice(0, 3)) parts.push({ text: `§7${line}§r\n` });
  if (def.role === "generator" || def.role === "consumer" || def.role === "storage") parts.push({ text: networkLine(networkAt(key)) });
  return { rawtext: parts };
}

function gogglesLoop() {
  for (const player of world.getPlayers()) {
    if (!wearsGoggles(player)) continue;
    let hit;
    try {
      hit = player.getBlockFromViewDirection({ maxDistance: CONFIG.gogglesRange, includeLiquidBlocks: false, includePassableBlocks: true });
    } catch {
      continue;
    }
    if (!hit || !hit.block.typeId.startsWith("techcore:")) continue;
    const text = describeBlock(hit.block);
    if (text) player.onScreenDisplay.setActionBar(text);
  }
}

export function startGogglesLoop() {
  system.runInterval(() => {
    try {
      gogglesLoop();
    } catch (e) {
      log.debug(`Очки: ${e}`);
    }
  }, CONFIG.gogglesTickInterval);
}
