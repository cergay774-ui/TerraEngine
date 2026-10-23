// Рецепты обрабатывающих машин.
// in    — входы [идентификатор | [варианты...], количество]
// out   — выходы [идентификатор, количество]
// fluid — выход жидкости { f: тип, a: мБ } (только переработчик топлива)
// time  — длительность, секунды
// power — потребление во время работы, E/с (если не задано — значение машины)
// Порядок важен: при авто-выборе берётся первый подходящий рецепт, поэтому
// многокомпонентные рецепты стоят раньше однокомпонентных.

const ORGANIC = [
  "minecraft:wheat",
  "minecraft:wheat_seeds",
  "minecraft:sugar_cane",
  "minecraft:kelp",
  "minecraft:potato",
  "minecraft:carrot",
  "minecraft:beetroot",
  "minecraft:pumpkin",
  "minecraft:melon_slice",
  "minecraft:oak_sapling",
  "minecraft:spruce_sapling",
  "minecraft:birch_sapling",
  "minecraft:jungle_sapling",
  "minecraft:acacia_sapling",
  "minecraft:dark_oak_sapling",
  "minecraft:cherry_sapling",
  "minecraft:oak_leaves",
  "minecraft:spruce_leaves",
  "minecraft:birch_leaves",
  "minecraft:jungle_leaves",
  "minecraft:acacia_leaves",
  "minecraft:dark_oak_leaves",
  "minecraft:short_grass",
  "minecraft:cactus",
];

/**
 * @typedef {Object} MachineRecipe
 * @property {string} id
 * @property {Array<[string | string[], number]>} in
 * @property {Array<[string, number]>} [out]
 * @property {{f: string, a: number}} [fluid]
 * @property {number} time
 * @property {number} [power]
 */

/** @type {Record<string, MachineRecipe[]>} */
export const MACHINE_RECIPES = {
  "techcore:crusher": [
    { id: "crush_raw_iron", in: [["minecraft:raw_iron", 1]], out: [["techcore:iron_dust", 2]], time: 6 },
    { id: "crush_iron_ore", in: [[["minecraft:iron_ore", "minecraft:deepslate_iron_ore"], 1]], out: [["techcore:iron_dust", 2]], time: 6 },
    { id: "crush_raw_gold", in: [["minecraft:raw_gold", 1]], out: [["techcore:gold_dust", 2]], time: 6 },
    { id: "crush_gold_ore", in: [[["minecraft:gold_ore", "minecraft:deepslate_gold_ore", "minecraft:nether_gold_ore"], 1]], out: [["techcore:gold_dust", 2]], time: 6 },
    { id: "crush_raw_copper", in: [["minecraft:raw_copper", 1]], out: [["techcore:copper_dust", 2]], time: 5 },
    { id: "crush_copper_ore", in: [[["minecraft:copper_ore", "minecraft:deepslate_copper_ore"], 1]], out: [["techcore:copper_dust", 3]], time: 6 },
    { id: "crush_coal", in: [[["minecraft:coal", "minecraft:charcoal"], 1]], out: [["techcore:coal_dust", 2]], time: 4 },
    { id: "crush_diamond", in: [["minecraft:diamond", 1]], out: [["techcore:diamond_dust", 1]], time: 10, power: 32 },
    { id: "crush_quartz", in: [["minecraft:quartz", 1]], out: [["techcore:quartz_dust", 2]], time: 5 },
    { id: "crush_ender", in: [["minecraft:ender_pearl", 1]], out: [["techcore:ender_dust", 2]], time: 8, power: 24 },
    { id: "crush_organic", in: [[ORGANIC, 4]], out: [["techcore:biomass", 1]], time: 4, power: 8 },
    { id: "crush_cobble", in: [["minecraft:cobblestone", 1]], out: [["minecraft:gravel", 1]], time: 3, power: 8 },
    { id: "crush_gravel", in: [["minecraft:gravel", 1]], out: [["minecraft:sand", 1]], time: 3, power: 8 },
  ],
  "techcore:electric_smelter": [
    { id: "smelt_superconductor", in: [["techcore:gold_dust", 1], ["techcore:copper_dust", 1], ["techcore:ender_dust", 2], ["techcore:diamond_dust", 1]], out: [["techcore:superconductor_ingot", 2]], time: 30, power: 120 },
    { id: "smelt_carbon", in: [["techcore:coal_dust", 4], ["techcore:silicon", 1]], out: [["techcore:carbon_composite", 1]], time: 20, power: 60 },
    { id: "smelt_steel", in: [["techcore:iron_dust", 2], ["techcore:coal_dust", 1]], out: [["techcore:steel_ingot", 1]], time: 12, power: 40 },
    { id: "smelt_silicon", in: [[["minecraft:sand", "minecraft:red_sand"], 2], ["techcore:coal_dust", 1]], out: [["techcore:silicon", 1]], time: 10, power: 32 },
    { id: "smelt_iron", in: [["techcore:iron_dust", 1]], out: [["minecraft:iron_ingot", 1]], time: 5 },
    { id: "smelt_gold", in: [["techcore:gold_dust", 1]], out: [["minecraft:gold_ingot", 1]], time: 5 },
    { id: "smelt_copper", in: [["techcore:copper_dust", 1]], out: [["minecraft:copper_ingot", 1]], time: 4 },
  ],
  "techcore:press": [
    { id: "press_steel_casing", in: [["techcore:steel_plate", 4]], out: [["techcore:steel_casing", 1]], time: 16, power: 40 },
    { id: "press_machine_casing", in: [["techcore:iron_plate", 4]], out: [["techcore:machine_casing", 1]], time: 10 },
    { id: "press_composite_blade", in: [["techcore:carbon_composite", 3]], out: [["techcore:composite_blade", 1]], time: 20, power: 48 },
    { id: "press_turbine_blade", in: [["techcore:steel_plate", 3]], out: [["techcore:turbine_blade", 1]], time: 12, power: 32 },
    { id: "press_iron_plate", in: [["minecraft:iron_ingot", 1]], out: [["techcore:iron_plate", 1]], time: 4 },
    { id: "press_copper_plate", in: [["minecraft:copper_ingot", 1]], out: [["techcore:copper_plate", 1]], time: 4 },
    { id: "press_gold_plate", in: [["minecraft:gold_ingot", 1]], out: [["techcore:gold_plate", 1]], time: 4 },
    { id: "press_steel_plate", in: [["techcore:steel_ingot", 1]], out: [["techcore:steel_plate", 1]], time: 8, power: 32 },
  ],
  "techcore:lathe": [
    { id: "lathe_bearing", in: [["techcore:steel_ingot", 1], ["techcore:iron_gear", 1]], out: [["techcore:bearing", 2]], time: 12, power: 30 },
    { id: "lathe_iron_gear", in: [["techcore:iron_plate", 1]], out: [["techcore:iron_gear", 2]], time: 5 },
    { id: "lathe_steel_gear", in: [["techcore:steel_plate", 1]], out: [["techcore:steel_gear", 2]], time: 8, power: 28 },
    { id: "lathe_steel_shaft", in: [["techcore:steel_ingot", 1]], out: [["techcore:steel_shaft", 2]], time: 8, power: 28 },
    { id: "lathe_copper_coil", in: [["minecraft:copper_ingot", 1]], out: [["techcore:copper_coil", 2]], time: 6 },
  ],
  "techcore:fuel_refinery": [
    { id: "refine_gasoline", in: [["techcore:bitumen", 1], ["techcore:coal_dust", 2]], fluid: { f: "gasoline", a: 500 }, time: 12 },
    { id: "refine_diesel", in: [["techcore:bitumen", 2]], fluid: { f: "diesel", a: 500 }, time: 15, power: 40 },
    { id: "refine_biofuel", in: [["techcore:biomass", 4]], fluid: { f: "biofuel", a: 500 }, time: 10, power: 20 },
  ],
};

// Ванильные рецепты верстака (генерируются в behavior_pack/recipes).
export const CRAFTING_TABLE_RECIPES = [
  {
    id: "ultimate_assembler",
    // Точный рецепт из ТЗ: алмаз/шестерня/алмаз, золото/алмаз/золото, алмаз/шестерня/алмаз.
    pattern: ["DGD", "IDI", "DGD"],
    key: { D: "minecraft:diamond", G: "techcore:iron_gear", I: "minecraft:gold_ingot" },
    result: "techcore:ultimate_assembler",
    count: 1,
    unlock: "techcore:iron_gear",
  },
  {
    id: "iron_gear",
    pattern: [" I ", "INI", " I "],
    key: { I: "minecraft:iron_ingot", N: "minecraft:iron_nugget" },
    result: "techcore:iron_gear",
    count: 1,
    unlock: "minecraft:iron_ingot",
  },
  {
    id: "iron_plate_manual",
    pattern: ["II"],
    key: { I: "minecraft:iron_ingot" },
    result: "techcore:iron_plate",
    count: 1,
    unlock: "minecraft:iron_ingot",
  },
  {
    id: "copper_plate_manual",
    pattern: ["CC"],
    key: { C: "minecraft:copper_ingot" },
    result: "techcore:copper_plate",
    count: 1,
    unlock: "minecraft:copper_ingot",
  },
  {
    id: "copper_coil_manual",
    pattern: [" C ", "CSC", " C "],
    key: { C: "minecraft:copper_ingot", S: "minecraft:stick" },
    result: "techcore:copper_coil",
    count: 1,
    unlock: "minecraft:copper_ingot",
  },
];

// Поиск рецепта по идентификатору внутри машины.
export function findMachineRecipe(machineId, recipeId) {
  const list = MACHINE_RECIPES[machineId];
  return list ? list.find((r) => r.id === recipeId) : undefined;
}
