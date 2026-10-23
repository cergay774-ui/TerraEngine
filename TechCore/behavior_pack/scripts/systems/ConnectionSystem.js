// Визуальные соединения проводов и труб: состояния techcore:c_n/s/e/w/u/d включают
// соответствующие "рукава" модели. Пересчитываются только при установке/разрушении блоков рядом.
import { BLOCKS, isEnergyNode, isFluidNode } from "../data/machines.js";
import { WIRES } from "../data/wires.js";
import { FACES } from "../core/positions.js";
import { blockAt, multiPart, safeOffset, setStates } from "../core/blocks.js";

const PIPE_ID = "techcore:fluid_pipe";

/** @param {import("@minecraft/server").Block} b */
function connectsEnergy(b) {
  if (!b) return false;
  if (WIRES[b.typeId]) return true;
  return isEnergyNode(b.typeId) && multiPart(b.permutation) === 0;
}

/** @param {import("@minecraft/server").Block} b */
function connectsFluid(b) {
  if (!b) return false;
  return b.typeId === PIPE_ID || isFluidNode(b.typeId);
}

/** Пересчёт состояний одного соединителя. @param {import("@minecraft/server").Block} block */
export function updateConnector(block) {
  const isWire = !!WIRES[block.typeId];
  const isPipe = block.typeId === PIPE_ID;
  if (!isWire && !isPipe) return;
  /** @type {Record<string, boolean>} */
  const states = {};
  for (const f of FACES) {
    const nb = safeOffset(block, f.dx, f.dy, f.dz);
    states[`techcore:c_${f.name}`] = nb ? (isWire ? connectsEnergy(nb) : connectsFluid(nb)) : false;
  }
  setStates(block, states);
}

/** Пересчёт блока и шести соседей. */
export function refreshAround(dimId, x, y, z) {
  const self = blockAt(dimId, x, y, z);
  if (self) updateConnector(self);
  for (const f of FACES) {
    const b = blockAt(dimId, x + f.dx, y + f.dy, z + f.dz);
    if (b && BLOCKS[b.typeId] && (BLOCKS[b.typeId].role === "wire" || BLOCKS[b.typeId].role === "pipe")) updateConnector(b);
  }
}
