// Энергосистема: построение локальных сетей и распределение энергии.
// Сети перестраиваются только при изменении топологии (установка/разрушение узла или провода,
// загрузка/выгрузка чанка с машиной), а не каждый тик. Сам расчёт распределения — O(узлов сети).
import { BLOCKS, isEnergyNode } from "../data/machines.js";
import { WIRES } from "../data/wires.js";
import { CONFIG } from "../data/config.js";
import { FACES, offsetKey, parseKey } from "../core/positions.js";
import { blockAt } from "../core/blocks.js";
import { computePaths, solveNetwork } from "../logic/energy.js";
import { log } from "../core/log.js";
import { records } from "./Registry.js";
import { handlerFor } from "./kinds.js";

/**
 * @typedef {Object} Network
 * @property {number} id
 * @property {string[]} devices
 * @property {Set<string>} wires
 * @property {Map<string, {loss: number, cap: number}>} paths
 * @property {Map<string, {loss: number, cap: number}>} chargePaths
 * @property {number} minWireCap
 * @property {any} stats
 */

let dirty = true;
let nextId = 1;
/** @type {Network[]} */
let networks = [];
/** @type {Map<string, Network>} ключ узла/провода → сеть */
const nodeNet = new Map();

export function markDirty() {
  dirty = true;
}

/** Сеть, в которую входит позиция (устройство или провод). */
export function networkAt(key) {
  return nodeNet.get(key);
}

/** Тип провода по ключу (только при загруженном чанке). */
function wireTypeAt(key, cache) {
  if (cache.has(key)) return cache.get(key);
  const p = parseKey(key);
  const b = blockAt(p.dim, p.x, p.y, p.z);
  const t = b && WIRES[b.typeId] ? b.typeId : null;
  cache.set(key, t);
  return t;
}

function isDevice(key) {
  const r = records.get(key);
  return !!r && r._loaded && isEnergyNode(r.t);
}

function rebuild() {
  networks = [];
  nodeNet.clear();
  /** @type {Map<string, string | null>} */
  const wireCache = new Map();
  /** @type {Set<string>} */
  const visited = new Set();
  for (const rec of records.values()) {
    if (!rec._loaded || !isEnergyNode(rec.t) || visited.has(rec.k)) continue;
    /** @type {Map<string, import("../logic/energy.js").GraphNode>} */
    const graph = new Map();
    const devices = [];
    const wires = new Set();
    let minWireCap = Infinity;
    const queue = [rec.k];
    visited.add(rec.k);
    let qi = 0;
    while (qi < queue.length) {
      const key = queue[qi++];
      const dev = isDevice(key);
      const wt = dev ? null : wireTypeAt(key, wireCache);
      if (dev) devices.push(key);
      else if (wt) {
        wires.add(key);
        minWireCap = Math.min(minWireCap, WIRES[wt].capacity);
      }
      const neighbors = [];
      for (const f of FACES) {
        const nk = offsetKey(key, f.dx, f.dy, f.dz);
        if (isDevice(nk) || wireTypeAt(nk, wireCache)) {
          neighbors.push(nk);
          if (!visited.has(nk) && queue.length < CONFIG.maxNetworkNodes) {
            visited.add(nk);
            queue.push(nk);
          }
        }
      }
      graph.set(key, {
        key,
        relayLoss: dev ? CONFIG.directLinkLoss : WIRES[/** @type {string} */ (wt)].loss,
        relayCap: dev ? CONFIG.directLinkCapacity : WIRES[/** @type {string} */ (wt)].capacity,
        neighbors,
      });
    }
    const sources = [];
    const gens = [];
    for (const k of devices) {
      const role = BLOCKS[records.get(k).t].role;
      if (role === "generator") {
        sources.push(k);
        gens.push(k);
      } else if (role === "storage") sources.push(k);
    }
    /** @type {Network} */
    const net = {
      id: nextId++,
      devices,
      wires,
      paths: computePaths(graph, sources, CONFIG.maxPathLoss),
      chargePaths: computePaths(graph, gens, CONFIG.maxPathLoss),
      minWireCap: minWireCap === Infinity ? CONFIG.directLinkCapacity : minWireCap,
      stats: null,
    };
    for (const k of devices) nodeNet.set(k, net);
    for (const k of wires) nodeNet.set(k, net);
    networks.push(net);
  }
  dirty = false;
  log.debug(`Энергосети перестроены: ${networks.length}`);
}

/**
 * Шаг энергосистемы. Вызывается MachineSystem после сбора запросов.
 * @param {(rec: any) => import("./kinds.js").StepEnv} envFor
 * @param {number} dt
 */
export function step(envFor, dt) {
  if (dirty) rebuild();
  for (const net of networks) {
    const generators = [];
    const batteries = [];
    const consumers = [];
    for (const k of net.devices) {
      const rec = records.get(k);
      if (!rec || !rec._loaded) continue;
      const def = BLOCKS[rec.t];
      const h = handlerFor(rec.t);
      if (!h) continue;
      const env = envFor(rec);
      try {
        if (def.role === "generator" && h.supply) {
          const s = h.supply(rec, env);
          generators.push({ key: k, available: s.available, free: s.free });
        } else if (def.role === "storage" && h.storage) {
          const s = h.storage(rec);
          const cp = net.chargePaths.get(k) ?? { loss: 0, cap: 0 };
          batteries.push({ key: k, charge: s.charge, capacity: s.capacity, rate: s.rate, inLoss: cp.loss, inCap: cp.cap });
        } else if (def.role === "consumer" && h.demand) {
          const demand = h.demand(rec, env);
          // Если в сети нет источников, пути нет: ограничения линии не применяются,
          // а распределение само вернёт "нет энергии".
          const p = net.paths.get(k) ?? { loss: 0, cap: Infinity };
          consumers.push({ key: k, demand, priority: rec.pr ?? 2, loss: p.loss, cap: p.cap });
          rec._pathLoss = p.loss;
        }
      } catch (e) {
        // Ошибка одного устройства не должна останавливать всю сеть.
        log.warn(`Энергия ${rec.t} в ${k}: ${e}`);
      }
    }
    const res = solveNetwork({ generators, batteries, consumers }, dt);
    for (const [k, r] of res.consumers) {
      const rec = records.get(k);
      if (!rec) continue;
      rec._power = r;
      rec._recv = r.received;
    }
    for (const [k, g] of res.generators) {
      const rec = records.get(k);
      if (rec) rec._gen = g;
    }
    for (const [k, d] of res.batteries) {
      const rec = records.get(k);
      if (rec) rec._battDelta = d;
    }
    net.stats = { ...res.stats, devices: net.devices.length, wires: net.wires.size, minWireCap: net.minWireCap };
  }
}

/** Список сетей (для интерфейса обзора). */
export function allNetworks() {
  if (dirty) rebuild();
  return networks;
}
