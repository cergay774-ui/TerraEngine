// Расчёт энергосети (без API Minecraft).
// Сеть — связный граф устройств и проводов. Для каждого потребителя заранее (при перестройке
// сети) вычисляется лучший путь от источника: суммарные потери и узкое место по пропускной
// способности. Каждую секунду распределение выполняется по приоритетам.

/**
 * Узел графа.
 * @typedef {{ key: string, relayLoss: number, relayCap: number, neighbors: string[] }} GraphNode
 */

/**
 * Многоисточниковый Дейкстра по потерям. Потери узла учитываются при прохождении ЧЕРЕЗ узел,
 * поэтому устройство, стоящее вплотную к источнику, получает энергию без потерь.
 * @param {Map<string, GraphNode>} graph
 * @param {string[]} sources
 * @param {number} maxLoss
 * @returns {Map<string, {loss: number, cap: number}>}
 */
export function computePaths(graph, sources, maxLoss) {
  /** @type {Map<string, {loss: number, cap: number}>} */
  const best = new Map();
  /** @type {Array<{key: string, loss: number, cap: number, src: boolean}>} */
  const heap = [];
  const push = (e) => {
    heap.push(e);
    let i = heap.length - 1;
    while (i > 0) {
      const p = (i - 1) >> 1;
      if (less(heap[p], heap[i])) break;
      [heap[p], heap[i]] = [heap[i], heap[p]];
      i = p;
    }
  };
  const pop = () => {
    const top = heap[0];
    const last = heap.pop();
    if (heap.length > 0 && last) {
      heap[0] = last;
      let i = 0;
      for (;;) {
        const l = i * 2 + 1;
        const r = l + 1;
        let m = i;
        if (l < heap.length && !less(heap[m], heap[l])) m = l;
        if (r < heap.length && !less(heap[m], heap[r])) m = r;
        if (m === i) break;
        [heap[m], heap[i]] = [heap[i], heap[m]];
        i = m;
      }
    }
    return top;
  };
  for (const s of sources) if (graph.has(s)) push({ key: s, loss: 0, cap: Infinity, src: true });
  while (heap.length > 0) {
    const cur = pop();
    const known = best.get(cur.key);
    if (known && !better(cur, known)) continue;
    best.set(cur.key, { loss: cur.loss, cap: cur.cap });
    const node = graph.get(cur.key);
    if (!node) continue;
    const passLoss = cur.src ? 0 : node.relayLoss;
    const passCap = cur.src ? Infinity : node.relayCap;
    const loss = Math.min(maxLoss, cur.loss + passLoss);
    const cap = Math.min(cur.cap, passCap);
    for (const nb of node.neighbors) {
      const prev = best.get(nb);
      const cand = { key: nb, loss, cap, src: false };
      if (!prev || better(cand, prev)) push(cand);
    }
  }
  return best;
}

function less(a, b) {
  if (a.loss !== b.loss) return a.loss < b.loss;
  return a.cap >= b.cap;
}

function better(a, b) {
  if (a.loss < b.loss - 1e-12) return true;
  if (Math.abs(a.loss - b.loss) <= 1e-12) return a.cap > b.cap;
  return false;
}

/**
 * Распределение энергии в сети за шаг длительностью dt секунд.
 * Все мощности — E/с; энергия = мощность × dt.
 *
 * @param {{
 *   generators: Array<{key: string, available: number, free: boolean}>,
 *   batteries: Array<{key: string, charge: number, capacity: number, rate: number, inLoss: number, inCap: number}>,
 *   consumers: Array<{key: string, demand: number, priority: number, loss: number, cap: number}>,
 * }} net
 * @param {number} dt
 */
export function solveNetwork(net, dt) {
  let freeAvail = 0;
  let fuelAvail = 0;
  for (const g of net.generators) {
    if (g.available <= 0) continue;
    if (g.free) freeAvail += g.available;
    else fuelAvail += g.available;
  }
  let battAvail = 0;
  /** @type {Map<string, number>} */
  const battOffer = new Map();
  for (const b of net.batteries) {
    const offer = Math.max(0, Math.min(b.rate, b.charge / dt));
    battOffer.set(b.key, offer);
    battAvail += offer;
  }

  let free = freeAvail;
  let fuel = fuelAvail;
  let batt = battAvail;
  let demandTotal = 0;
  let delivered = 0;
  let losses = 0;

  /** @type {Map<string, {powered: boolean, reason: string, received: number}>} */
  const consumers = new Map();
  const sorted = [...net.consumers].sort((a, b) => a.priority - b.priority || (a.key < b.key ? -1 : a.key > b.key ? 1 : 0));
  for (const c of sorted) {
    if (c.demand <= 0) {
      consumers.set(c.key, { powered: true, reason: "idle", received: 0 });
      continue;
    }
    demandTotal += c.demand;
    if (c.demand > c.cap + 1e-9) {
      consumers.set(c.key, { powered: false, reason: "line_limit", received: 0 });
      continue;
    }
    const need = c.demand / Math.max(0.05, 1 - c.loss);
    if (free + fuel + batt + 1e-9 < need) {
      consumers.set(c.key, { powered: false, reason: "no_power", received: 0 });
      continue;
    }
    let left = need;
    const takeFree = Math.min(free, left);
    free -= takeFree;
    left -= takeFree;
    const takeFuel = Math.min(fuel, left);
    fuel -= takeFuel;
    left -= takeFuel;
    const takeBatt = Math.min(batt, left);
    batt -= takeBatt;
    left -= takeBatt;
    delivered += c.demand;
    losses += need - c.demand;
    consumers.set(c.key, { powered: true, reason: "ok", received: c.demand });
  }

  // Разряд аккумуляторов пропорционально их предложению.
  const battUsed = battAvail - batt;
  /** @type {Map<string, number>} */
  const battDelta = new Map();
  for (const b of net.batteries) {
    const offer = battOffer.get(b.key) ?? 0;
    const share = battAvail > 0 ? (offer / battAvail) * battUsed : 0;
    battDelta.set(b.key, -share * dt);
  }

  // Зарядка излишком: сначала бесплатная генерация, затем топливная.
  const chargeOrder = [...net.batteries].sort((a, b) => (a.key < b.key ? -1 : 1));
  for (const b of chargeOrder) {
    const current = b.charge + (battDelta.get(b.key) ?? 0);
    const discharged = (battDelta.get(b.key) ?? 0) < 0;
    if (discharged) continue;
    const room = Math.max(0, Math.min(b.rate, b.inCap, (b.capacity - current) / dt));
    if (room <= 0) continue;
    const factor = Math.max(0.05, 1 - b.inLoss);
    const wantSource = room / factor;
    let take = Math.min(free, wantSource);
    free -= take;
    let took = take;
    if (took < wantSource) {
      take = Math.min(fuel, wantSource - took);
      fuel -= take;
      took += take;
    }
    const stored = took * factor;
    losses += took - stored;
    battDelta.set(b.key, (battDelta.get(b.key) ?? 0) + stored * dt);
  }

  // Загрузка генераторов.
  const freeUsed = freeAvail - free;
  const fuelUsed = fuelAvail - fuel;
  /** @type {Map<string, {output: number, load: number}>} */
  const generators = new Map();
  for (const g of net.generators) {
    if (g.available <= 0) {
      generators.set(g.key, { output: 0, load: 0 });
      continue;
    }
    const used = g.free ? freeUsed : fuelUsed;
    const avail = g.free ? freeAvail : fuelAvail;
    const load = avail > 0 ? used / avail : 0;
    generators.set(g.key, { output: g.available * load, load });
  }

  let stored = 0;
  for (const b of net.batteries) stored += b.charge + (battDelta.get(b.key) ?? 0);

  return {
    consumers,
    generators,
    batteries: battDelta,
    stats: {
      available: freeAvail + fuelAvail,
      generation: freeUsed + fuelUsed,
      demand: demandTotal,
      delivered,
      losses,
      batteryOut: battUsed,
      stored,
    },
  };
}
