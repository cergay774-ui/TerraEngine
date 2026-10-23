// Кастомные компоненты блоков (Custom Components V2) и связанные события мира.
// techcore:machine   — блоки с сохраняемым состоянием (машины, генераторы, транспорт);
// techcore:connector — провода и трубы.
import { system, world, ItemStack, EquipmentSlot } from "@minecraft/server";
import { BLOCKS, isEnergyNode, isFluidNode } from "../data/machines.js";
import { PACKED_ASSEMBLER_BY_TIER } from "../data/items.js";
import { posKey } from "../core/positions.js";
import { multiPart, stateOf, withStates } from "../core/blocks.js";
import { log } from "../core/log.js";
import * as registry from "./Registry.js";
import * as energy from "./EnergySystem.js";
import * as fluids from "./FuelSystem.js";
import { refreshAround } from "./ConnectionSystem.js";
import { readDirection, rotateBelt } from "./TransportSystem.js";
import { openMachineUI } from "../ui/MachineUI.js";

const ASSEMBLER = "techcore:ultimate_assembler";
const BELTS = new Set(["conveyor", "filter", "splitter"]);

let ready = false;
/** События, пришедшие до загрузки записей мира. */
const pending = [];

export function markReady() {
  ready = true;
  for (const fn of pending.splice(0)) {
    try {
      fn();
    } catch (e) {
      log.warn(`Отложенное событие: ${e}`);
    }
  }
}

function whenReady(fn) {
  if (ready) fn();
  else pending.push(fn);
}

function topologyChanged(typeId) {
  if (isEnergyNode(typeId) || BLOCKS[typeId]?.role === "wire") energy.markDirty();
  if (isFluidNode(typeId) || BLOCKS[typeId]?.role === "pipe") fluids.markNetworkDirty();
}

/** Создание записи при установке блока. @param {import("@minecraft/server").Block} block */
function registerPlaced(block) {
  const typeId = block.typeId;
  const def = BLOCKS[typeId];
  if (!def) return;
  if (multiPart(block.permutation) !== 0) return; // верхние части мультиблока
  /** @type {Record<string, any>} */
  const extra = {};
  if (BELTS.has(def.kind)) extra.dir = readDirection(block);
  if (typeId === ASSEMBLER) {
    const t = stateOf(block.permutation, "techcore:tier");
    extra.tier = typeof t === "number" ? t : 0;
  }
  registry.create(typeId, block.dimension.id, block.x, block.y, block.z, extra);
  topologyChanged(typeId);
}

/**
 * После разрушения сборщика уровня 1+ ванильная добыча даёт предмет Ур-0. Заменяем ровно один
 * такой выпавший предмет упакованным сборщиком нужного уровня (если предмет выпал —
 * в творческом режиме добычи нет, и заменять нечего).
 */
function replaceAssemblerDrop(dimId, x, y, z, tier) {
  system.runTimeout(() => {
    try {
      const dim = world.getDimension(dimId);
      const items = dim.getEntities({ type: "minecraft:item", location: { x: x + 0.5, y: y + 0.5, z: z + 0.5 }, maxDistance: 2.5 });
      for (const e of items) {
        const comp = e.getComponent("minecraft:item");
        const stack = comp?.itemStack;
        if (!stack || stack.typeId !== ASSEMBLER) continue;
        const loc = e.location;
        if (stack.amount > 1) {
          // Чужие сборщики в той же точке: оставляем лишние как есть.
          e.remove();
          dim.spawnItem(new ItemStack(ASSEMBLER, stack.amount - 1), loc);
        } else e.remove();
        dim.spawnItem(new ItemStack(PACKED_ASSEMBLER_BY_TIER[tier], 1), loc);
        return;
      }
    } catch (e) {
      log.warn(`Замена выпадения сборщика: ${e}`);
    }
  }, 1);
}

export function registerComponents(registryEvent) {
  registryEvent.blockComponentRegistry.registerCustomComponent("techcore:machine", {
    beforeOnPlayerPlace(e) {
      // Упакованный сборщик сохраняет уровень: подставляем состояние techcore:tier.
      if (e.permutationToPlace.type.id !== ASSEMBLER || !e.player) return;
      const eq = e.player.getComponent("minecraft:equippable");
      const held = eq?.getEquipment(EquipmentSlot.Mainhand);
      const tier = held ? PACKED_ASSEMBLER_BY_TIER.indexOf(held.typeId) : -1;
      if (tier > 0) e.permutationToPlace = withStates(e.permutationToPlace, { "techcore:tier": tier });
    },
    onPlace(e) {
      const block = e.block;
      whenReady(() => {
        if (!block.isValid) return;
        registerPlaced(block);
        refreshAround(block.dimension.id, block.x, block.y, block.z);
      });
    },
    onBreak(e) {
      const perm = e.brokenBlockPermutation;
      const typeId = perm.type.id;
      const { x, y, z } = e.block;
      const dimId = e.dimension.id;
      const part = multiPart(perm);
      whenReady(() => {
        const key = posKey(dimId, x, y - part, z);
        const rec = registry.get(key);
        const tier = rec && rec.t === ASSEMBLER ? rec.tier | 0 : 0;
        registry.destroy(key, true);
        topologyChanged(typeId);
        system.run(() => refreshAround(dimId, x, y, z));
        if (tier > 0) replaceAssemblerDrop(dimId, x, y, z, tier);
      });
    },
    onPlayerInteract(e) {
      const player = e.player;
      if (!player) return;
      const block = e.block;
      const part = multiPart(block.permutation);
      const key = posKey(block.dimension.id, block.x, block.y - part, block.z);
      const rec = registry.get(key);
      if (!rec) {
        player.sendMessage("§eМашина ещё не зарегистрирована. Повторите через секунду.");
        return;
      }
      const eq = player.getComponent("minecraft:equippable");
      const held = eq?.getEquipment(EquipmentSlot.Mainhand);
      if (held?.typeId === "techcore:wrench" && BELTS.has(BLOCKS[rec.t].kind)) {
        rotateBelt(rec);
        player.sendMessage(`§7Направление: ${rec.dir}`);
        return;
      }
      system.run(() => openMachineUI(player, key));
    },
  });

  registryEvent.blockComponentRegistry.registerCustomComponent("techcore:connector", {
    onPlace(e) {
      const b = e.block;
      const dimId = b.dimension.id;
      const { x, y, z } = b;
      const typeId = b.typeId;
      whenReady(() => {
        refreshAround(dimId, x, y, z);
        topologyChanged(typeId);
      });
    },
    onBreak(e) {
      const typeId = e.brokenBlockPermutation.type.id;
      const dimId = e.dimension.id;
      const { x, y, z } = e.block;
      whenReady(() => {
        system.run(() => refreshAround(dimId, x, y, z));
        topologyChanged(typeId);
      });
    },
  });
}
