// Интеграционные сценарии: настоящие скрипты TechCore на имитации Script API.
// Запуск: node --import ./TechCore/tools/tests/mock/register.mjs --test TechCore/tools/tests/integration.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import * as mc from "@minecraft/server";
import { ui } from "@minecraft/server-ui";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const SCRIPTS = path.join(ROOT, "behavior_pack/scripts");

// Состояния по умолчанию берём из сгенерированных JSON блоков (как движок).
for (const f of fs.readdirSync(path.join(ROOT, "behavior_pack/blocks"))) {
  const b = JSON.parse(fs.readFileSync(path.join(ROOT, "behavior_pack/blocks", f), "utf8"))["minecraft:block"];
  const st = {};
  for (const [k, v] of Object.entries(b.description.states ?? {})) st[k] = Array.isArray(v) ? v[0] : v.values.min;
  const traits = b.description.traits ?? {};
  if (traits["minecraft:placement_direction"]) st["minecraft:cardinal_direction"] = "south";
  if (traits["minecraft:multi_block"]) st["minecraft:multi_block_part"] = 0;
  mc.blockStateDefaults.set(b.description.identifier, st);
}

// Предупреждения/ошибки скриптов фиксируем — тесты требуют их отсутствия.
const logged = [];
const origWarn = console.warn;
const origError = console.error;
console.warn = (...a) => logged.push(["warn", a.join(" ")]);
console.error = (...a) => logged.push(["error", a.join(" ")]);
const origLog = console.log;
console.log = () => {};

await import(path.join(SCRIPTS, "main.js"));
const Registry = await import(path.join(SCRIPTS, "systems/Registry.js"));
const Persistence = await import(path.join(SCRIPTS, "systems/PersistenceSystem.js"));
const Upgrade = await import(path.join(SCRIPTS, "systems/UpgradeSystem.js"));
const Crafting = await import(path.join(SCRIPTS, "systems/CraftingSystem.js"));
const Energy = await import(path.join(SCRIPTS, "systems/EnergySystem.js"));
const { insertFromPlayer, giveSlots, openMachineUI } = await import(path.join(SCRIPTS, "ui/MachineUI.js"));
const { openAssemblerUI } = await import(path.join(SCRIPTS, "ui/AssemblerUI.js"));
const { posKey } = await import(path.join(SCRIPTS, "core/positions.js"));
const slots = await import(path.join(SCRIPTS, "logic/slots.js"));

const OW = mc.world.getDimension("minecraft:overworld");
const player = new mc.Player("Tester", OW);
mc.world._players.push(player);

function comp(typeId) {
  const wires = ["copper_wire", "insulated_wire", "reinforced_wire", "superconductor_wire", "fluid_pipe"];
  return mc.componentRegistry.get(wires.some((w) => typeId.endsWith(w)) ? "techcore:connector" : "techcore:machine");
}

function place(typeId, x, y, z, states = {}) {
  const block = OW.setBlock(x, y, z, typeId, states);
  comp(typeId).onPlace({ block, dimension: OW, previousBlock: new mc.BlockPermutation("minecraft:air") });
  return block;
}

function placeTurbine(typeId, x, y, z, parts) {
  for (let p = 0; p < parts; p++) {
    const b = OW.setBlock(x, y + p, z, typeId, { "minecraft:multi_block_part": p });
    comp(typeId).onPlace({ block: b, dimension: OW, previousBlock: new mc.BlockPermutation("minecraft:air") });
  }
}

function breakBlock(x, y, z) {
  const b = OW.getBlock({ x, y, z });
  const perm = b.permutation;
  OW.setBlock(x, y, z, "minecraft:air");
  comp(perm.type.id).onBreak({ block: OW.getBlock({ x, y, z }), dimension: OW, brokenBlockPermutation: perm });
}

const rec = (x, y, z) => Registry.get(posKey("minecraft:overworld", x, y, z));
/** Прямое изменение записи в тесте (как это сделал бы интерфейс) с пометкой для сохранения. */
function set(x, y, z, patch) {
  const r = rec(x, y, z);
  Object.assign(r, patch);
  Registry.markDirty(r);
  return r;
}
const seconds = (s) => mc.tick(20 * s);
const flush = () => new Promise((r) => setTimeout(r, 0));

function hold(id, n) {
  player.inventory.setItem(0, id ? new mc.ItemStack(id, n) : undefined);
}

function give(id, n) {
  player.inventory.addItem(new mc.ItemStack(id, n));
}

/** Ответ формы: нажать кнопку, текст которой содержит подстроку. */
function press(sub) {
  return (form) => {
    const i = form.buttons.findIndex((b) => JSON.stringify(b.text).includes(sub));
    if (i < 0) throw new Error(`Кнопка "${sub}" не найдена: ${form.buttons.map((b) => JSON.stringify(b.text)).join(" | ")}`);
    return { canceled: false, selection: i };
  };
}

function noWarnings() {
  const bad = logged.filter(([, m]) => m.includes("[TechCore]"));
  assert.deepEqual(bad, [], "скрипты не должны писать предупреждения");
}

mc.startup();
mc.world.afterEvents.worldLoad._fire({});

test("startup registers custom components used by blocks", () => {
  assert.ok(mc.componentRegistry.has("techcore:machine"));
  assert.ok(mc.componentRegistry.has("techcore:connector"));
});

test("coal generator powers an adjacent crusher; items are conserved", () => {
  place("techcore:coal_generator", 0, 64, 0);
  place("techcore:crusher", 1, 64, 0);
  hold("minecraft:coal", 5);
  insertFromPlayer(player, posKey("minecraft:overworld", 0, 64, 0), true);
  assert.equal(slots.countOf(rec(0, 64, 0).fuel, "minecraft:coal"), 5);
  assert.equal(player.inventory.count("minecraft:coal"), 0);
  hold("minecraft:raw_iron", 3);
  insertFromPlayer(player, posKey("minecraft:overworld", 1, 64, 0), true);
  seconds(8);
  const cr = rec(1, 64, 0);
  const dust = slots.countOf(cr.out, "techcore:iron_dust");
  const raw = slots.countOf(cr.in, "minecraft:raw_iron") + slots.countOf(cr.proc, "minecraft:raw_iron");
  assert.equal(dust, 2, "один цикл дробления за 6 с");
  assert.equal(raw, 2, "оставшаяся руда во входе/процессе");
  assert.ok(rec(0, 64, 0).burn > 0 && slots.countOf(rec(0, 64, 0).fuel, "minecraft:coal") === 4, "сожжена одна единица угля");
  assert.equal(OW.getBlock({ x: 1, y: 64, z: 0 }).permutation.getState("techcore:status"), 1, "состояние блока: работает");
  noWarnings();
});

test("player takes results; nothing is lost when inventory has room", () => {
  hold(undefined);
  giveSlots(player, posKey("minecraft:overworld", 1, 64, 0), "out");
  assert.equal(player.inventory.count("techcore:iron_dust"), 2);
  assert.equal(rec(1, 64, 0).out.length, 0);
});

test("copper wire limits throughput and adds losses", () => {
  // Генератор → 3 медных провода → электроплавильня с рецептом 120 E/с (больше 64).
  place("techcore:coal_generator", 0, 64, 10);
  place("techcore:coal_generator", 0, 64, 11);
  set(0, 64, 11, { fuel: [["minecraft:coal_block", 4]] });
  for (let x = 1; x <= 3; x++) place("techcore:copper_wire", x, 64, 10);
  place("techcore:electric_smelter", 4, 64, 10);
  set(0, 64, 10, { fuel: [["minecraft:coal_block", 4]] });
  const sm = set(4, 64, 10, { in: [] });
  sm.in = [["techcore:gold_dust", 1], ["techcore:copper_dust", 1], ["techcore:ender_dust", 2], ["techcore:diamond_dust", 1]];
  seconds(2);
  assert.equal(sm.st, "line_limit");
  assert.ok(OW.getBlock({ x: 2, y: 64, z: 10 }).permutation.getState("techcore:c_e"), "провод соединился визуально");
  // Обычный рецепт (24 E/с) проходит по меди с потерями; одного генератора (24 E/с) с учётом
  // потерь не хватило бы — поэтому их два.
  set(4, 64, 10, { proc: [], r: null, in: [["techcore:iron_dust", 3]] });
  seconds(2);
  assert.equal(sm.st, "working");
  assert.ok(sm._pathLoss > 0.01 && sm._pathLoss < 0.02, `потери пути ${sm._pathLoss}`);
  noWarnings();
});

test("high wind turbine charges a battery and spins its rotor", () => {
  placeTurbine("techcore:wind_turbine_5", 50, 150, 50, 4);
  place("techcore:battery_basic", 51, 150, 50);
  seconds(5);
  const b = rec(51, 150, 50);
  assert.ok(b.ch > 100, `заряд ${b.ch}`);
  const top = OW.getBlock({ x: 50, y: 153, z: 50 });
  assert.ok(top.permutation.getState("techcore:spin") >= 2, "ротор вращается");
  assert.equal(rec(50, 150, 50).st, "working");
  noWarnings();
});

test("assembler: UI loads exact ingredients, crafts the recipe, result is taken", async () => {
  place("techcore:ultimate_assembler", 0, 64, 20);
  const key = posKey("minecraft:overworld", 0, 64, 20);
  hold(undefined);
  give("techcore:iron_plate", 10);
  give("techcore:iron_gear", 3);
  give("minecraft:furnace", 1);
  give("techcore:copper_coil", 2);
  ui.responses.push(press("Рецепты"), press("coal_generator"), press("Загрузить ингредиенты на ×1"), press("Изготовить ×1"));
  await openAssemblerUI(player, key);
  await flush();
  const a = rec(0, 64, 20);
  assert.equal(player.inventory.count("techcore:iron_plate"), 5, "взято ровно 5 пластин");
  assert.equal(player.inventory.count("techcore:iron_gear"), 1);
  assert.equal(player.inventory.count("techcore:copper_coil"), 1);
  assert.equal(a.sel, "coal_generator");
  assert.equal(a.q, 1);
  seconds(14);
  assert.equal(slots.countOf(a.out, "techcore:coal_generator"), 1);
  assert.equal(a.store.length, 0, "ингредиенты израсходованы");
  assert.equal(a.job, null);
  giveSlots(player, key, "out");
  assert.equal(player.inventory.count("techcore:coal_generator"), 1);
  noWarnings();
});

test("assembler: missing ingredients keep the queue waiting; stop returns reserve", () => {
  const a = rec(0, 64, 20);
  a.sel = "machine_casing";
  a.q = 2;
  Crafting.storeAdd(a, "techcore:iron_plate", 12);
  seconds(1);
  assert.ok(a.job, "первое изготовление началось");
  assert.equal(slots.countOf(a.store, "techcore:iron_plate"), 4);
  Crafting.cancelJob(a);
  a.q = 0;
  assert.equal(slots.countOf(a.store, "techcore:iron_plate"), 12, "резерв вернулся");
  a.q = 2;
  seconds(10);
  seconds(1);
  assert.equal(slots.countOf(a.out, "techcore:machine_casing"), 1);
  assert.equal(a.st, "waiting", "на второй корпус не хватает пластин");
});

test("assembler upgrade 0 → 1 consumes requirements and energy, keeps contents", () => {
  const a = rec(0, 64, 20);
  a.q = 0;
  a.store = [];
  a.out = [];
  for (const [id, n] of [["techcore:control_module_1", 1], ["techcore:iron_plate", 8], ["techcore:iron_gear", 4], ["techcore:copper_coil", 4]]) Crafting.storeAdd(a, id, n);
  Crafting.storeAdd(a, "minecraft:diamond", 3);
  // Без энергии модернизация не идёт.
  assert.equal(Upgrade.start(a), null);
  seconds(3);
  assert.equal(a.st, "no_power");
  assert.equal(a.upg.p, 0);
  place("techcore:coal_generator", 1, 64, 20);
  set(1, 64, 20, { fuel: [["minecraft:coal_block", 2]] });
  seconds(62);
  assert.equal(a.tier, 1);
  assert.equal(a.upg, null);
  assert.deepEqual(a.store, [["minecraft:diamond", 3]], "посторонние предметы сохранены");
  assert.equal(OW.getBlock({ x: 0, y: 64, z: 20 }).permutation.getState("techcore:tier"), 1, "внешний вид обновлён");
  assert.equal(Upgrade.start(a), "Не хватает материалов для модернизации.");
  noWarnings();
});

test("persistence round trip restores machine state", () => {
  Persistence.flushDirty();
  const before = JSON.stringify([...Registry.records.values()].map((r) => [r.k, r.t, r.tier, r.store, r.out, r.fuel, r.ch]));
  Registry.records.clear();
  Registry.loadRecords();
  const after = JSON.stringify([...Registry.records.values()].map((r) => [r.k, r.t, r.tier, r.store, r.out, r.fuel, r.ch]));
  assert.equal(after, before);
  seconds(2); // после перезагрузки сети перестраиваются
  noWarnings();
});

test("breaking a tier-1 assembler drops contents and a packed tier-1 assembler", () => {
  const a = rec(0, 64, 20);
  a.out = [["techcore:machine_casing", 2]];
  const dropsBefore = OW.droppedCount("minecraft:diamond");
  // Ванильная добыча роняет блок как предмет Ур-0 — эмулируем.
  OW.spawnItem(new mc.ItemStack("techcore:ultimate_assembler", 1), { x: 0.5, y: 64.5, z: 20.5 });
  breakBlock(0, 64, 20);
  mc.tick(3);
  assert.equal(rec(0, 64, 20), undefined, "запись удалена");
  assert.equal(OW.droppedCount("minecraft:diamond") - dropsBefore, 3);
  assert.equal(OW.droppedCount("techcore:machine_casing"), 2);
  assert.equal(OW.droppedCount("techcore:ultimate_assembler"), 0);
  assert.equal(OW.droppedCount("techcore:assembler_packed_t1"), 1);
  assert.equal(mc.world.getDynamicProperty("tc:m:o:0:64:20"), undefined, "сохранение очищено");
});

test("placing a packed assembler restores its tier", () => {
  hold("techcore:assembler_packed_t1", 1);
  const perm = new mc.BlockPermutation("techcore:ultimate_assembler", mc.blockStateDefaults.get("techcore:ultimate_assembler"));
  const ev = { permutationToPlace: perm, player, face: "Up", cancel: false };
  mc.componentRegistry.get("techcore:machine").beforeOnPlayerPlace(ev);
  assert.equal(ev.permutationToPlace.getState("techcore:tier"), 1);
  place("techcore:ultimate_assembler", 0, 64, 30, { "techcore:tier": 1 });
  assert.equal(rec(0, 64, 30).tier, 1);
});

test("UI action after the machine is broken gives nothing (no duplication)", async () => {
  place("techcore:press", 5, 64, 30);
  const key = posKey("minecraft:overworld", 5, 64, 30);
  rec(5, 64, 30).out = [["techcore:iron_plate", 10]];
  hold(undefined);
  const plates = player.inventory.count("techcore:iron_plate");
  ui.responses.push((form) => {
    breakBlock(5, 64, 30); // кто-то сломал пресс, пока форма открыта
    return press("Забрать результат")(form);
  });
  await openMachineUI(player, key);
  await flush();
  mc.tick(2);
  assert.equal(player.inventory.count("techcore:iron_plate"), plates, "в инвентарь ничего не пришло");
  assert.equal(OW.droppedCount("techcore:iron_plate"), 10, "содержимое выпало ровно один раз");
});

test("conveyor moves items from a chest into a machine without loss", () => {
  const chest = OW.setContainer(10, 64, 40, "minecraft:chest", 27);
  chest.addItem(new mc.ItemStack("minecraft:iron_ingot", 20));
  place("techcore:conveyor", 11, 64, 40, { "minecraft:cardinal_direction": "east" });
  place("techcore:press", 12, 64, 40);
  place("techcore:coal_generator", 12, 64, 41);
  set(12, 64, 41, { fuel: [["minecraft:coal_block", 2]] });
  seconds(6);
  const pr = rec(12, 64, 40);
  const belt = rec(11, 64, 40);
  const total =
    chest.count("minecraft:iron_ingot") +
    (belt.cargo ? belt.cargo[1] : 0) +
    slots.countOf(pr.in, "minecraft:iron_ingot") +
    slots.countOf(pr.proc, "minecraft:iron_ingot") +
    slots.countOf(pr.out, "techcore:iron_plate");
  assert.equal(total, 20, "сумма предметов сохраняется");
  assert.ok(chest.count("minecraft:iron_ingot") < 20, "сундук опустошается");
  assert.ok(slots.countOf(pr.out, "techcore:iron_plate") >= 1, "пресс работает");
  noWarnings();
});

test("wrench rotates a conveyor", () => {
  hold("techcore:wrench", 1);
  const b = OW.getBlock({ x: 11, y: 64, z: 40 });
  mc.componentRegistry.get("techcore:machine").onPlayerInteract({ block: b, dimension: OW, player, face: "Up" });
  assert.equal(rec(11, 64, 40).dir, "south");
  assert.equal(OW.getBlock({ x: 11, y: 64, z: 40 }).permutation.getState("minecraft:cardinal_direction"), "south");
  hold(undefined);
});

test("refinery produces biofuel, pipe delivers it to the biofuel generator", () => {
  place("techcore:coal_generator", 20, 64, 49);
  set(20, 64, 49, { fuel: [["minecraft:coal_block", 2]] });
  place("techcore:fuel_refinery", 20, 64, 50);
  place("techcore:fluid_pipe", 21, 64, 50);
  place("techcore:bio_generator", 22, 64, 50);
  set(20, 64, 50, { in: [["techcore:biomass", 8]] });
  seconds(23);
  const gen = rec(22, 64, 50);
  assert.equal(gen.tank.f, "biofuel");
  assert.ok(gen.tank.a >= 500, `в баке генератора ${gen.tank.a} мБ`);
  noWarnings();
});

test("drill mines natural blocks only and skips containers", () => {
  place("techcore:coal_generator", 30, 64, 59);
  place("techcore:coal_generator", 31, 64, 59);
  set(30, 64, 59, { fuel: [["minecraft:coal_block", 4]] });
  set(31, 64, 59, { fuel: [["minecraft:coal_block", 4]] });
  for (let y = 60; y <= 63; y++) for (let dx = -1; dx <= 1; dx++) for (let dz = -1; dz <= 1; dz++) OW.setBlock(30 + dx, y, 60 + dz, "minecraft:stone");
  OW.setContainer(30, 63, 60, "minecraft:chest", 27);
  place("techcore:drill_rig", 30, 64, 60);
  seconds(30);
  const d = rec(30, 64, 60);
  assert.ok(slots.countOf(d.out, "minecraft:cobblestone") >= 8, `добыто ${slots.countOf(d.out, "minecraft:cobblestone")}`);
  assert.equal(OW.getBlock({ x: 30, y: 63, z: 60 }).typeId, "minecraft:chest", "сундук не разрушен");
  assert.equal(OW.getBlock({ x: 29, y: 63, z: 60 }).typeId, "minecraft:air");
  noWarnings();
});

test("engineer goggles show efficiency and power of the targeted machine", () => {
  player.equipment.Head = new mc.ItemStack("techcore:engineer_goggles", 1);
  player.lookAt = OW.getBlock({ x: 12, y: 64, z: 40 });
  player.actionbar.length = 0;
  mc.tick(10);
  const text = JSON.stringify(player.actionbar.at(-1));
  assert.ok(text.includes("Эффективность"), text);
  assert.ok(text.includes("Потребление"), text);
  assert.ok(text.includes("Сеть"), text);
  player.lookAt = OW.getBlock({ x: 20, y: 64, z: 49 });
  mc.tick(10);
  assert.ok(JSON.stringify(player.actionbar.at(-1)).includes("Выработка"));
  // Без очков HUD не обновляется.
  player.equipment.Head = undefined;
  player.actionbar.length = 0;
  mc.tick(10);
  assert.equal(player.actionbar.length, 0);
  // Во второй руке тоже работает.
  player.equipment.Offhand = new mc.ItemStack("techcore:engineer_goggles", 1);
  mc.tick(10);
  assert.ok(player.actionbar.length > 0);
});

test("priority: low priority machine stops first on deficit", () => {
  // Один угольный генератор (24 E/с) и два потребителя по 16/20 E/с.
  place("techcore:coal_generator", 70, 64, 70);
  set(70, 64, 70, { fuel: [["minecraft:coal_block", 4]] });
  place("techcore:crusher", 71, 64, 70);
  place("techcore:lathe", 69, 64, 70);
  set(71, 64, 70, { in: [["minecraft:raw_iron", 10]] });
  set(69, 64, 70, { in: [["techcore:iron_plate", 10]] });
  set(71, 64, 70, { pr: 3 });
  set(69, 64, 70, { pr: 1 });
  seconds(3);
  assert.equal(rec(69, 64, 70).st, "working");
  assert.equal(rec(71, 64, 70).st, "no_power");
  noWarnings();
});

test("unloaded chunk pauses machines and they resume afterwards", () => {
  const lathe = rec(69, 64, 70);
  OW.unloaded.add(`${Math.floor(69 / 16)},${Math.floor(70 / 16)}`);
  const p = lathe.p;
  seconds(3);
  assert.equal(lathe.p, p, "без загрузки чанка прогресса нет");
  OW.unloaded.clear();
  seconds(3);
  assert.ok(lathe.p !== p || slots.countOf(lathe.out, "techcore:iron_gear") > 0);
});

test("energy networks are rebuilt lazily, not every tick", () => {
  const n1 = Energy.allNetworks();
  seconds(2);
  const n2 = Energy.allNetworks();
  assert.equal(n1, n2, "без изменений топологии используется кэш");
  place("techcore:copper_wire", 72, 64, 70);
  seconds(1);
  assert.notEqual(Energy.allNetworks(), n1);
});

test("generator at the border of an unloaded chunk keeps working (no exceptions)", () => {
  place("techcore:coal_generator", 15, 64, 90);
  place("techcore:crusher", 14, 64, 90);
  set(15, 64, 90, { fuel: [["minecraft:coal_block", 1]] });
  set(14, 64, 90, { in: [["minecraft:raw_iron", 4]] });
  OW.unloaded.add(`1,${Math.floor(90 / 16)}`); // соседний чанк по x=16 выгружен
  seconds(3);
  assert.equal(rec(14, 64, 90).st, "working");
  OW.unloaded.clear();
  noWarnings();
});

test("no warnings or errors were logged by TechCore during the whole run", () => {
  noWarnings();
  console.warn = origWarn;
  console.error = origError;
  console.log = origLog;
});
