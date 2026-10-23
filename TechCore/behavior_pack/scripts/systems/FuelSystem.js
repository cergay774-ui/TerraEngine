// Жидкое топливо: трубные сети, резервуары, канистры.
// Жидкости не имитируют физику Minecraft: объём хранится во внутренних единицах (мБ),
// а перенос по сети ограничен пропускной способностью труб.
import { BLOCKS } from "../data/machines.js";
import { PIPES, FUEL_TANK } from "../data/wires.js";
import { LIQUID_GENERATORS } from "../data/generators.js";
import { CANISTER_BY_FLUID, CANISTER_VOLUME, ITEM_BY_ID, FLUIDS } from "../data/items.js";
import { FACES, offsetKey, parseKey } from "../core/positions.js";
import { blockAt } from "../core/blocks.js";
import { heldItem, swapHeldOne } from "../core/inventory.js";
import { fluidName } from "../core/text.js";
import { distribute, emptyTank, sanitizeTank, tankDrain, tankFill, tankRoom } from "../logic/fluids.js";
import { records, markDirty, saveNow } from "./Registry.js";
import { registerKind } from "./kinds.js";

const PIPE_ID = "techcore:fluid_pipe";
let dirty = true;
/** @type {Array<{nodes: string[], pipes: number}>} */
let networks = [];
/** @type {Map<string, {nodes: string[], pipes: number}>} */
const nodeNet = new Map();

export function markNetworkDirty() {
  dirty = true;
}

function isFluidDevice(key) {
  const r = records.get(key);
  return !!r && r._loaded && !!BLOCKS[r.t]?.fluidRole;
}

function rebuild() {
  networks = [];
  nodeNet.clear();
  const pipeCache = new Map();
  const isPipe = (key) => {
    if (pipeCache.has(key)) return pipeCache.get(key);
    const p = parseKey(key);
    const b = blockAt(p.dim, p.x, p.y, p.z);
    const v = !!b && b.typeId === PIPE_ID;
    pipeCache.set(key, v);
    return v;
  };
  const visited = new Set();
  for (const rec of records.values()) {
    if (!isFluidDevice(rec.k) || visited.has(rec.k)) continue;
    const nodes = [];
    let pipes = 0;
    const queue = [rec.k];
    visited.add(rec.k);
    let qi = 0;
    while (qi < queue.length && queue.length < 4096) {
      const key = queue[qi++];
      if (isFluidDevice(key)) nodes.push(key);
      else pipes++;
      for (const f of FACES) {
        const nk = offsetKey(key, f.dx, f.dy, f.dz);
        if (visited.has(nk)) continue;
        if (isFluidDevice(nk) || isPipe(nk)) {
          visited.add(nk);
          queue.push(nk);
        }
      }
    }
    const net = { nodes, pipes };
    for (const k of nodes) nodeNet.set(k, net);
    networks.push(net);
  }
  dirty = false;
}

export function fluidNetworkOf(key) {
  if (dirty) rebuild();
  return nodeNet.get(key);
}

/** Шаг распределения по всем трубным сетям. */
export function step(dt) {
  if (dirty) rebuild();
  const budget = PIPES[PIPE_ID].throughput * dt;
  for (const net of networks) {
    if (net.nodes.length < 2) continue;
    const sources = [];
    const storages = [];
    const consumers = [];
    for (const k of net.nodes) {
      const rec = records.get(k);
      if (!rec || !rec._loaded) continue;
      const def = BLOCKS[rec.t];
      if (def.fluidRole === "source") sources.push({ key: k, tank: rec.fl, cap: def.tank, rec });
      else if (def.fluidRole === "storage") storages.push({ key: k, tank: rec.tank, cap: FUEL_TANK.capacity, rec });
      else if (def.fluidRole === "consumer") {
        const spec = LIQUID_GENERATORS[rec.t];
        consumers.push({ key: k, tank: rec.tank, cap: spec.tank, accepts: spec.fluid, rec });
      }
    }
    const moved = distribute(sources, storages, consumers, budget);
    if (moved > 0) for (const n of [...sources, ...storages, ...consumers]) markDirty(n.rec);
  }
}

// ---------------------------------------------------------------------------
// Резервуар
// ---------------------------------------------------------------------------

const FLUID_INDEX = { diesel: 1, gasoline: 2, biofuel: 3 };

registerKind("tank", {
  init(rec) {
    rec.tank ??= emptyTank();
    rec.st ??= "ready";
  },
  sanitize(rec) {
    rec.tank = sanitizeTank(rec.tank);
  },
  contents() {
    return [];
  },
  visual(rec) {
    const level = rec.tank.a <= 0 ? 0 : Math.max(1, Math.min(4, Math.ceil((rec.tank.a / FUEL_TANK.capacity) * 4)));
    return { "techcore:fluid": rec.tank.f ? FLUID_INDEX[rec.tank.f] ?? 0 : 0, "techcore:level": level };
  },
  info(rec) {
    return { lines: [`${fluidName(rec.tank.f)}: ${Math.floor(rec.tank.a)} / ${FUEL_TANK.capacity} мБ`] };
  },
});

// ---------------------------------------------------------------------------
// Канистры
// ---------------------------------------------------------------------------

/**
 * Слить канистру из руки в бак. accepts — допустимый тип (или null — любой).
 * @returns {string} сообщение для игрока
 */
export function pourHeldCanister(player, rec, tankField, cap, accepts) {
  const held = heldItem(player);
  const meta = held ? ITEM_BY_ID.get(held.typeId) : undefined;
  if (!held || !meta || !meta.fluid) return "§cВозьмите в руку полную канистру.";
  if (accepts && meta.fluid !== accepts) return `§cЭто устройство принимает только: ${FLUIDS[accepts].ru}.`;
  const tank = rec[tankField];
  if (tankRoom(tank, meta.fluid, cap) < CANISTER_VOLUME) return "§cНедостаточно места в баке или другой тип жидкости.";
  if (!swapHeldOne(player, held.typeId, "techcore:canister")) return "§cНе удалось взять канистру из руки.";
  tankFill(tank, meta.fluid, CANISTER_VOLUME, cap);
  saveNow(rec);
  return `§aЗалито ${CANISTER_VOLUME} мБ: ${FLUIDS[meta.fluid].ru}.`;
}

/** Наполнить пустую канистру из бака. @returns {string} */
export function fillHeldCanister(player, rec, tankField) {
  const held = heldItem(player);
  if (!held || held.typeId !== "techcore:canister") return "§cВозьмите в руку пустую канистру.";
  const tank = rec[tankField];
  if (!tank.f || tank.a < CANISTER_VOLUME) return `§cВ баке меньше ${CANISTER_VOLUME} мБ.`;
  const filled = CANISTER_BY_FLUID[tank.f];
  if (!filled) return "§cЭту жидкость нельзя набрать в канистру.";
  const fluid = tank.f;
  if (!swapHeldOne(player, "techcore:canister", filled)) return "§cНе удалось взять канистру из руки.";
  tankDrain(tank, CANISTER_VOLUME);
  saveNow(rec);
  return `§aКанистра наполнена: ${FLUIDS[fluid].ru}.`;
}
