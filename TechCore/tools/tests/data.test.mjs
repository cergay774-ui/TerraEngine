// Проверка согласованности игровых данных: рецепты помещаются в сетки уровней,
// все идентификаторы TechCore существуют, прогрессия не содержит "дыр".
import { test } from "node:test";
import assert from "node:assert/strict";

import { ITEMS } from "../../behavior_pack/scripts/data/items.js";
import { BLOCKS } from "../../behavior_pack/scripts/data/machines.js";
import { ASSEMBLER_RECIPES } from "../../behavior_pack/scripts/data/assembler_recipes.js";
import { MACHINE_RECIPES, CRAFTING_TABLE_RECIPES } from "../../behavior_pack/scripts/data/recipes.js";
import { ASSEMBLER_TIERS, UPGRADES, MAX_TIER } from "../../behavior_pack/scripts/data/progression.js";
import { WIND_TURBINES } from "../../behavior_pack/scripts/data/generators.js";
import { validateRecipe, requirements } from "../../behavior_pack/scripts/logic/crafting.js";

const known = new Set([...ITEMS.map((i) => `techcore:${i.id}`), ...Object.keys(BLOCKS)]);

function idsOf(what) {
  return Array.isArray(what) ? what : [what];
}

function checkId(id, where) {
  if (id.startsWith("techcore:")) assert.ok(known.has(id), `${where}: unknown ${id}`);
  else assert.ok(id.startsWith("minecraft:"), `${where}: bad namespace ${id}`);
}

test("tier grids match the specification exactly (width x height)", () => {
  assert.deepEqual(
    ASSEMBLER_TIERS.map((t) => t.grid),
    [
      [4, 4],
      [5, 4],
      [5, 6],
      [7, 7],
      [8, 7],
      [9, 9],
    ],
  );
});

test("every assembler recipe fits its tier grid and is well-formed", () => {
  const ids = new Set();
  for (const r of ASSEMBLER_RECIPES) {
    assert.ok(!ids.has(r.id), `duplicate recipe ${r.id}`);
    ids.add(r.id);
    assert.deepEqual(validateRecipe(r, ASSEMBLER_TIERS), [], r.id);
    checkId(r.result[0], r.id);
    for (const v of Object.values(r.key)) for (const id of idsOf(v)) checkId(id, r.id);
  }
});

test("every tier has at least one recipe that needs its larger grid", () => {
  for (let t = 1; t <= MAX_TIER; t++) {
    const prev = ASSEMBLER_TIERS[t - 1].grid;
    const needs = ASSEMBLER_RECIPES.filter((r) => r.minTier === t);
    assert.ok(needs.length > 0, `tier ${t} has no recipes`);
  }
  assert.ok(ASSEMBLER_RECIPES.some((r) => r.pattern.length === 9 && r.pattern[0].length === 9), "a 9x9 recipe exists");
});

test("machine recipes reference existing items", () => {
  for (const [machine, list] of Object.entries(MACHINE_RECIPES)) {
    assert.ok(BLOCKS[machine], machine);
    for (const r of list) {
      for (const [what] of r.in) for (const id of idsOf(what)) checkId(id, r.id);
      for (const [id] of r.out ?? []) checkId(id, r.id);
      assert.ok(r.out || r.fluid, `${r.id}: no output`);
      assert.ok(r.time > 0, r.id);
    }
  }
});

test("upgrade requirements exist and the control module of each stage is craftable earlier", () => {
  for (let to = 1; to <= MAX_TIER; to++) {
    const up = UPGRADES[to];
    assert.ok(up, `upgrade ${to}`);
    for (const [id] of up.items) checkId(id, `upgrade ${to}`);
    const module = `techcore:control_module_${to}`;
    assert.ok(up.items.some(([id]) => id === module), `upgrade ${to} needs ${module}`);
    const rec = ASSEMBLER_RECIPES.find((r) => r.result[0] === module);
    assert.ok(rec && rec.minTier <= to - 1, `${module} must be craftable on tier ${to - 1}`);
  }
});

test("first crafting-table recipe matches the specification", () => {
  const r = CRAFTING_TABLE_RECIPES.find((x) => x.result === "techcore:ultimate_assembler");
  assert.ok(r);
  const counts = {};
  for (const row of r.pattern) for (const ch of row) counts[r.key[ch]] = (counts[r.key[ch]] ?? 0) + 1;
  assert.deepEqual(counts, { "minecraft:diamond": 5, "techcore:iron_gear": 2, "minecraft:gold_ingot": 2 });
  assert.deepEqual(r.pattern, ["DGD", "IDI", "DGD"]);
});

test("every TechCore item and block can be obtained", () => {
  const producible = new Set();
  for (const r of ASSEMBLER_RECIPES) producible.add(r.result[0]);
  for (const list of Object.values(MACHINE_RECIPES)) for (const r of list) for (const [id] of r.out ?? []) producible.add(id);
  for (const r of CRAFTING_TABLE_RECIPES) producible.add(r.result);
  const special = new Set([
    "techcore:bitumen", // буровая установка
    "techcore:canister_diesel",
    "techcore:canister_gasoline",
    "techcore:canister_biofuel", // наполнение канистр
    "techcore:assembler_packed_t1",
    "techcore:assembler_packed_t2",
    "techcore:assembler_packed_t3",
    "techcore:assembler_packed_t4",
    "techcore:assembler_packed_t5", // разборка модернизированного сборщика
  ]);
  for (const id of known) assert.ok(producible.has(id) || special.has(id), `${id} cannot be obtained`);
});

test("every ingredient used by the assembler is obtainable or vanilla", () => {
  const producible = new Set([...ASSEMBLER_RECIPES.map((r) => r.result[0]), ...CRAFTING_TABLE_RECIPES.map((r) => r.result)]);
  for (const list of Object.values(MACHINE_RECIPES)) for (const r of list) for (const [id] of r.out ?? []) producible.add(id);
  for (const r of ASSEMBLER_RECIPES) {
    for (const [what] of requirements(r)) {
      for (const id of idsOf(what)) if (id.startsWith("techcore:")) assert.ok(producible.has(id), `${r.id} needs unobtainable ${id}`);
    }
  }
});

test("no TechCore ingredient is first available on a later tier than the recipe using it", () => {
  // Тир, на котором предмет впервые можно получить (машинные рецепты — по тиру, где доступна машина).
  const firstTier = new Map();
  const set = (id, t) => {
    if (!firstTier.has(id) || firstTier.get(id) > t) firstTier.set(id, t);
  };
  for (const r of CRAFTING_TABLE_RECIPES) set(r.result, 0);
  for (let pass = 0; pass < 6; pass++) {
    for (const r of ASSEMBLER_RECIPES) set(r.result[0], r.minTier);
    for (const [machine, list] of Object.entries(MACHINE_RECIPES)) {
      const mt = firstTier.get(machine);
      if (mt === undefined) continue;
      for (const rr of list) for (const [id] of rr.out ?? []) set(id, mt);
    }
  }
  set("techcore:bitumen", firstTier.get("techcore:drill_rig"));
  for (const r of ASSEMBLER_RECIPES) {
    for (const [what] of requirements(r)) {
      for (const id of idsOf(what)) {
        if (!id.startsWith("techcore:")) continue;
        assert.ok(firstTier.get(id) <= r.minTier, `${r.id} (tier ${r.minTier}) needs ${id} first available on tier ${firstTier.get(id)}`);
      }
    }
  }
});

test("wind turbines have the specified ratings", () => {
  assert.deepEqual(
    Object.values(WIND_TURBINES).map((w) => w.rated),
    [10, 18, 30, 48, 75],
  );
});
