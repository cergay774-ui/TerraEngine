// Юнит-тесты логики TechCore, не зависящей от API Minecraft.
// Запуск: node --test TechCore/tools/tests/
import { test } from "node:test";
import assert from "node:assert/strict";

import * as slots from "../../behavior_pack/scripts/logic/slots.js";
import { requirements, fitsGrid, patternSize, validateRecipe, craftTime } from "../../behavior_pack/scripts/logic/crafting.js";
import { computePaths, solveNetwork } from "../../behavior_pack/scripts/logic/energy.js";
import { windFactor, obstructionFactor, spinState } from "../../behavior_pack/scripts/logic/wind.js";
import { stepHeat } from "../../behavior_pack/scripts/logic/heat.js";
import { distribute, emptyTank, tankFill, tankDrain, tankRoom } from "../../behavior_pack/scripts/logic/fluids.js";
import { WIND_MODEL, COAL_GENERATOR } from "../../behavior_pack/scripts/data/generators.js";
import { ASSEMBLER_TIERS } from "../../behavior_pack/scripts/data/progression.js";

test("slots: add respects types and per-type cap", () => {
  const s = [];
  assert.equal(slots.add(s, "a", 100, 2, 64), 100);
  assert.deepEqual(s, [["a", 64], ["a", 36]]);
  assert.equal(slots.add(s, "b", 10, 2, 64), 0, "no free slot for a new type");
  assert.equal(slots.acceptable(s, "a", 2, 64), 28);
  assert.equal(slots.add(s, "a", 50, 2, 64), 28);
  assert.equal(slots.countOf(s, "a"), 128);
});

test("slots: remove never goes negative and cleans empty slots", () => {
  const s = [["a", 5], ["b", 3]];
  assert.equal(slots.remove(s, "a", 10), 5);
  assert.deepEqual(s, [["b", 3]]);
  assert.equal(slots.remove(s, "c", 1), 0);
});

test("slots: plan with alternatives does not double count", () => {
  const s = [["oak", 2], ["spruce", 3]];
  const p = slots.plan(s, [[["oak", "spruce"], 4]]);
  assert.deepEqual(p, [["oak", 2], ["spruce", 2]]);
  assert.equal(slots.plan(s, [[["oak", "spruce"], 4], ["oak", 1]]), null, "oak already used by the first requirement");
  assert.deepEqual(slots.missing(s, [[["oak", "spruce"], 7]]), [[["oak", "spruce"], 2]]);
});

test("slots: reserve is atomic", () => {
  const s = [["a", 2], ["b", 1]];
  const res = [];
  assert.equal(slots.reserve(s, [["a", 2], ["b", 2]], res), false);
  assert.deepEqual(s, [["a", 2], ["b", 1]], "state unchanged on failure");
  assert.deepEqual(res, []);
  assert.equal(slots.reserve(s, [["a", 2], ["b", 1]], res), true);
  assert.deepEqual(s, []);
  assert.deepEqual(res, [["a", 2], ["b", 1]]);
});

test("slots: total item count is conserved through reserve/return", () => {
  const store = [["x", 40], ["y", 7]];
  const before = slots.total(store);
  const res = [];
  slots.reserve(store, slots.plan(store, [["x", 13], ["y", 7]]), res);
  for (const [id, n] of res) slots.add(store, id, n, 99, 999);
  assert.equal(slots.total(store), before);
});

test("slots: fitsAll simulates without mutating", () => {
  const s = [["a", 60]];
  assert.equal(slots.fitsAll(s, [["a", 4]], 1, 64), true);
  assert.equal(slots.fitsAll(s, [["a", 5]], 1, 64), false);
  assert.deepEqual(s, [["a", 60]]);
});

test("slots: sanitize drops malformed entries", () => {
  assert.deepEqual(slots.sanitize([["a", 2], ["b", -1], [3, 4], "x", ["c", "5"]]), [["a", 2], ["c", 5]]);
  assert.deepEqual(slots.sanitize(null), []);
});

test("crafting: requirements and size", () => {
  const r = { id: "t", minTier: 0, pattern: ["DGD", "IDI", "DGD"], key: { D: "d", G: "g", I: "i" }, result: ["x", 1] };
  assert.deepEqual(requirements(r), [["d", 5], ["g", 2], ["i", 2]]);
  assert.deepEqual(patternSize(r), [3, 3]);
  assert.equal(fitsGrid(r, [4, 4]), true);
  assert.equal(fitsGrid({ pattern: ["AAAAA"] }, [4, 4]), false);
  assert.equal(fitsGrid({ pattern: ["A", "A", "A", "A", "A"] }, [5, 4]), false, "height must fit, no rotation");
  assert.equal(fitsGrid({ pattern: ["AAAAA", "AAAAA", "AAAAA", "AAAAA"] }, [5, 4]), true);
  assert.deepEqual(validateRecipe(r, ASSEMBLER_TIERS), []);
});

test("crafting: tier speed shortens time, never below 1 s", () => {
  assert.equal(craftTime({ time: 10 }, { speed: 1 }), 10);
  assert.equal(craftTime({ time: 10 }, { speed: 1.75 }), 6);
  assert.equal(craftTime({ time: 1 }, { speed: 1.75 }), 1);
});

function graphOf(edges, wires = {}) {
  const g = new Map();
  const ensure = (k) => {
    if (!g.has(k)) g.set(k, { key: k, relayLoss: wires[k]?.loss ?? 0.002, relayCap: wires[k]?.cap ?? 1024, neighbors: [] });
    return g.get(k);
  };
  for (const [a, b] of edges) {
    ensure(a).neighbors.push(b);
    ensure(b).neighbors.push(a);
  }
  return g;
}

test("energy: path loss accumulates over wires and bottleneck is the weakest wire", () => {
  const wires = { w1: { loss: 0.01, cap: 64 }, w2: { loss: 0.01, cap: 256 } };
  const g = graphOf([["gen", "w1"], ["w1", "w2"], ["w2", "m"]], wires);
  const p = computePaths(g, ["gen"], 0.6);
  assert.ok(Math.abs(p.get("m").loss - 0.02) < 1e-9);
  assert.equal(p.get("m").cap, 64);
});

test("energy: direct adjacency has no loss and no line limit", () => {
  const g = graphOf([["gen", "m"]]);
  const p = computePaths(g, ["gen"], 0.6);
  assert.equal(p.get("m").loss, 0);
  assert.equal(p.get("m").cap, Infinity);
});

test("energy: low priority machines stop first on deficit", () => {
  const res = solveNetwork(
    {
      generators: [{ key: "g", available: 30, free: false }],
      batteries: [],
      consumers: [
        { key: "low", demand: 20, priority: 3, loss: 0, cap: Infinity },
        { key: "high", demand: 20, priority: 1, loss: 0, cap: Infinity },
      ],
    },
    1,
  );
  assert.equal(res.consumers.get("high").powered, true);
  assert.equal(res.consumers.get("low").powered, false);
  assert.equal(res.consumers.get("low").reason, "no_power");
  assert.ok(Math.abs(res.generators.get("g").load - 20 / 30) < 1e-9, "fuel generator throttles to load");
});

test("energy: line limit is reported separately", () => {
  const res = solveNetwork({ generators: [{ key: "g", available: 500, free: true }], batteries: [], consumers: [{ key: "m", demand: 100, priority: 2, loss: 0, cap: 64 }] }, 1);
  assert.equal(res.consumers.get("m").reason, "line_limit");
});

test("energy: losses increase source draw", () => {
  const res = solveNetwork({ generators: [{ key: "g", available: 100, free: true }], batteries: [], consumers: [{ key: "m", demand: 50, priority: 2, loss: 0.5, cap: Infinity }] }, 1);
  assert.equal(res.consumers.get("m").powered, true);
  assert.ok(Math.abs(res.stats.generation - 100) < 1e-9);
  assert.ok(Math.abs(res.stats.losses - 50) < 1e-9);
});

test("energy: battery charges from surplus and discharges on deficit, within rate", () => {
  const charge = solveNetwork(
    { generators: [{ key: "g", available: 100, free: true }], batteries: [{ key: "b", charge: 0, capacity: 1000, rate: 60, inLoss: 0, inCap: Infinity }], consumers: [] },
    1,
  );
  assert.equal(charge.batteries.get("b"), 60);
  const dis = solveNetwork(
    {
      generators: [],
      batteries: [{ key: "b", charge: 500, capacity: 1000, rate: 60, inLoss: 0, inCap: Infinity }],
      consumers: [{ key: "m", demand: 40, priority: 2, loss: 0, cap: Infinity }],
    },
    1,
  );
  assert.equal(dis.consumers.get("m").powered, true);
  assert.equal(dis.batteries.get("b"), -40);
  const tooMuch = solveNetwork(
    {
      generators: [],
      batteries: [{ key: "b", charge: 500, capacity: 1000, rate: 60, inLoss: 0, inCap: Infinity }],
      consumers: [{ key: "m", demand: 80, priority: 2, loss: 0, cap: Infinity }],
    },
    1,
  );
  assert.equal(tooMuch.consumers.get("m").powered, false);
  assert.equal(tooMuch.batteries.get("b"), 0);
});

test("energy: free generation is used before fuel", () => {
  const res = solveNetwork(
    {
      generators: [
        { key: "wind", available: 10, free: true },
        { key: "coal", available: 24, free: false },
      ],
      batteries: [],
      consumers: [{ key: "m", demand: 16, priority: 2, loss: 0, cap: Infinity }],
    },
    1,
  );
  assert.equal(res.generators.get("wind").output, 10);
  assert.ok(Math.abs(res.generators.get("coal").output - 6) < 1e-9);
});

test("energy: generators idle when there is no demand", () => {
  const res = solveNetwork({ generators: [{ key: "coal", available: 24, free: false }], batteries: [], consumers: [] }, 1);
  assert.equal(res.generators.get("coal").output, 0);
});

test("wind: height, weather and dimension", () => {
  const base = { weather: "Clear", dimension: "minecraft:overworld", obstruction: 1, timeSeconds: 0, seed: 0 };
  const low = windFactor({ ...base, y: 40 }, WIND_MODEL);
  const mid = windFactor({ ...base, y: 140 }, WIND_MODEL);
  const storm = windFactor({ ...base, y: 140, weather: "Thunder" }, WIND_MODEL);
  assert.ok(low < mid);
  assert.ok(storm > mid);
  assert.ok(storm <= WIND_MODEL.outputCap);
  assert.equal(windFactor({ ...base, y: 100, dimension: "minecraft:nether" }, WIND_MODEL), 0);
  assert.equal(windFactor({ ...base, y: 100, weather: "Thunder", dimension: "minecraft:the_end" }, WIND_MODEL), windFactor({ ...base, y: 100, dimension: "minecraft:the_end" }, WIND_MODEL));
  assert.ok(obstructionFactor(72, 72, WIND_MODEL) >= WIND_MODEL.minObstructionFactor);
  assert.equal(obstructionFactor(0, 72, WIND_MODEL), 1);
  assert.equal(spinState(0), 0);
  assert.equal(spinState(1), 3);
});

test("heat: throttles at limit and recovers with hysteresis, never above 100", () => {
  const def = COAL_GENERATOR.heat;
  let st = { heat: 0, overheated: false };
  let t = 0;
  while (!st.overheated && t < 10000) {
    st = stepHeat(st, 1, 0, def, 1);
    t++;
  }
  assert.ok(st.overheated);
  assert.ok(t > 60, "overheat must not happen in the first minute");
  st = stepHeat(st, 0, 2, def, 1);
  assert.ok(st.overheated, "hysteresis keeps throttle until recover threshold");
  for (let i = 0; i < 200; i++) st = stepHeat(st, 0, 2, def, 1);
  assert.equal(st.overheated, false);
  const cooled = stepHeat({ heat: 0, overheated: false }, 1, 2, def, 1);
  assert.equal(cooled.heat, 0, "two coolant blocks fully compensate coal generator");
});

test("fluids: tanks keep one fluid type", () => {
  const t = emptyTank();
  assert.equal(tankFill(t, "diesel", 300, 1000), 300);
  assert.equal(tankRoom(t, "gasoline", 1000), 0);
  assert.equal(tankFill(t, "gasoline", 100, 1000), 0);
  assert.equal(tankDrain(t, 500), 300);
  assert.deepEqual(t, { f: null, a: 0 });
});

test("fluids: distribute feeds matching consumers first, then stores surplus, within budget", () => {
  const src = { tank: { f: "diesel", a: 1000 }, cap: 4000 };
  const store = { tank: emptyTank(), cap: 16000 };
  const gen = { tank: emptyTank(), cap: 4000, accepts: "diesel" };
  const wrong = { tank: emptyTank(), cap: 4000, accepts: "biofuel" };
  const moved = distribute([src], [store], [wrong, gen], 600);
  assert.equal(moved, 600);
  assert.equal(gen.tank.a, 600);
  assert.equal(wrong.tank.a, 0);
  assert.equal(store.tank.a, 0, "budget exhausted by the consumer");
  const total = src.tank.a + store.tank.a + gen.tank.a;
  assert.equal(total, 1000, "volume conserved");
});
