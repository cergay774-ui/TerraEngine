// Рецепты Ультимативного сборщика.
// pattern — строки сетки (ширина × высота), "." — пустая ячейка.
// key     — буква → идентификатор предмета или массив допустимых вариантов.
// minTier — минимальный уровень сборщика; рецепт обязан помещаться в сетку этого уровня.
// power   — E/с во время сборки (0 — энергия не требуется), time — секунды (до учёта скорости уровня).
// Ингредиенты берутся из внутреннего хранилища сборщика по количеству ячеек с буквой;
// положение ячеек задаёт форму рецепта (размер и отображение), а не размещение предметов игроком
// (см. docs/TECHNICAL_LIMITATIONS.md, раздел «Сетка крафта»).

const PLANKS = [
  "minecraft:oak_planks",
  "minecraft:spruce_planks",
  "minecraft:birch_planks",
  "minecraft:jungle_planks",
  "minecraft:acacia_planks",
  "minecraft:dark_oak_planks",
  "minecraft:mangrove_planks",
  "minecraft:cherry_planks",
  "minecraft:bamboo_planks",
  "minecraft:crimson_planks",
  "minecraft:warped_planks",
];

export const CATEGORIES = {
  energy: "Энергетика",
  machines: "Машины",
  components: "Компоненты",
  transport: "Транспорт и жидкости",
  tools: "Инструменты",
  modules: "Управляющие модули",
};

/**
 * @typedef {Object} AssemblerRecipe
 * @property {string} id
 * @property {number} minTier
 * @property {string} category
 * @property {number} power
 * @property {number} time
 * @property {string[]} pattern
 * @property {Record<string, string | string[]>} key
 * @property {[string, number]} result
 */

/** @type {AssemblerRecipe[]} */
export const ASSEMBLER_RECIPES = [
  // ======================= Ур-0 (4×4) =======================
  {
    id: "copper_wire", minTier: 0, category: "energy", power: 0, time: 4,
    pattern: ["CCCC"],
    key: { C: "minecraft:copper_ingot" },
    result: ["techcore:copper_wire", 8],
  },
  {
    id: "coal_generator", minTier: 0, category: "energy", power: 0, time: 12,
    pattern: ["PPP", "GFG", "PCP"],
    key: { P: "techcore:iron_plate", G: "techcore:iron_gear", F: "minecraft:furnace", C: "techcore:copper_coil" },
    result: ["techcore:coal_generator", 1],
  },
  {
    id: "wind_turbine_1", minTier: 0, category: "energy", power: 0, time: 15,
    pattern: ["W..W", ".GG.", "WCCW", ".II."],
    key: { W: PLANKS, G: "techcore:iron_gear", C: "techcore:copper_coil", I: "minecraft:iron_ingot" },
    result: ["techcore:wind_turbine_1", 1],
  },
  {
    id: "machine_casing", minTier: 0, category: "components", power: 0, time: 8,
    pattern: ["PPP", "P.P", "PPP"],
    key: { P: "techcore:iron_plate" },
    result: ["techcore:machine_casing", 1],
  },
  {
    id: "battery_cell", minTier: 0, category: "components", power: 0, time: 5,
    pattern: ["C", "R", "C"],
    key: { C: "techcore:copper_plate", R: "minecraft:redstone" },
    result: ["techcore:battery_cell", 2],
  },
  {
    id: "battery_basic", minTier: 0, category: "energy", power: 0, time: 20,
    pattern: ["PBP", "BMB", "PCP"],
    key: { P: "techcore:iron_plate", B: "techcore:battery_cell", M: "techcore:machine_casing", C: "techcore:copper_coil" },
    result: ["techcore:battery_basic", 1],
  },
  {
    id: "crusher", minTier: 0, category: "machines", power: 0, time: 20,
    pattern: ["PHP", "GMG", "PFP"],
    key: { P: "techcore:iron_plate", H: "minecraft:hopper", G: "techcore:iron_gear", M: "techcore:machine_casing", F: "minecraft:flint" },
    result: ["techcore:crusher", 1],
  },
  {
    id: "electric_smelter", minTier: 0, category: "machines", power: 0, time: 20,
    pattern: ["PCP", "CFC", "PMP"],
    key: { P: "techcore:iron_plate", C: "techcore:copper_coil", F: "minecraft:blast_furnace", M: "techcore:machine_casing" },
    result: ["techcore:electric_smelter", 1],
  },
  {
    id: "wrench", minTier: 0, category: "tools", power: 0, time: 3,
    pattern: ["I.I", ".I.", ".I."],
    key: { I: "minecraft:iron_ingot" },
    result: ["techcore:wrench", 1],
  },
  {
    id: "engineer_goggles", minTier: 0, category: "tools", power: 0, time: 6,
    pattern: ["LIIL", "GRRG"],
    key: { L: "minecraft:leather", I: "minecraft:iron_ingot", G: "minecraft:glass_pane", R: "minecraft:redstone" },
    result: ["techcore:engineer_goggles", 1],
  },
  {
    id: "control_module_1", minTier: 0, category: "modules", power: 0, time: 30,
    pattern: ["PRRP", "CGGC", "CGGC", "PDDP"],
    key: { P: "techcore:iron_plate", R: "minecraft:redstone", C: "techcore:copper_coil", G: "minecraft:gold_ingot", D: "minecraft:diamond" },
    result: ["techcore:control_module_1", 1],
  },

  // ======================= Ур-1 (5×4) =======================
  {
    id: "press", minTier: 1, category: "machines", power: 10, time: 30,
    pattern: ["PHHHP", "P.A.P", "GPMPG"],
    key: { P: "techcore:iron_plate", H: "minecraft:piston", A: "minecraft:anvil", G: "techcore:iron_gear", M: "techcore:machine_casing" },
    result: ["techcore:press", 1],
  },
  {
    id: "lathe", minTier: 1, category: "machines", power: 10, time: 30,
    pattern: ["PG.GP", "SCMCS", "PPPPP"],
    key: { P: "techcore:iron_plate", G: "techcore:iron_gear", S: "minecraft:smooth_stone", C: "techcore:copper_coil", M: "techcore:machine_casing" },
    result: ["techcore:lathe", 1],
  },
  {
    id: "insulated_wire", minTier: 1, category: "energy", power: 4, time: 6,
    pattern: ["WWWW", "KKKK"],
    key: { W: "techcore:copper_wire", K: "minecraft:dried_kelp" },
    result: ["techcore:insulated_wire", 4],
  },
  {
    id: "circuit_basic", minTier: 1, category: "components", power: 12, time: 12,
    pattern: ["PWWP", "RSSR", "PWWP"],
    key: { P: "techcore:iron_plate", W: "techcore:copper_plate", R: "minecraft:redstone", S: "techcore:silicon" },
    result: ["techcore:circuit_basic", 2],
  },
  {
    id: "motor", minTier: 1, category: "components", power: 12, time: 15,
    pattern: ["PCCP", "GSSG", "PCCP"],
    key: { P: "techcore:iron_plate", C: "techcore:copper_coil", G: "techcore:iron_gear", S: "techcore:steel_shaft" },
    result: ["techcore:motor", 1],
  },
  {
    id: "canister", minTier: 1, category: "transport", power: 4, time: 6,
    pattern: ["P.P", "PBP", "PPP"],
    key: { P: "techcore:iron_plate", B: "minecraft:bucket" },
    result: ["techcore:canister", 2],
  },
  {
    id: "control_module_2", minTier: 1, category: "modules", power: 24, time: 45,
    pattern: ["PRRRP", "CQQQC", "CQGQC", "PSDSP"],
    key: {
      P: "techcore:iron_plate", R: "minecraft:redstone", C: "techcore:copper_coil", Q: "techcore:circuit_basic",
      G: "techcore:gold_plate", S: "techcore:steel_plate", D: "minecraft:diamond",
    },
    result: ["techcore:control_module_2", 1],
  },

  // ======================= Ур-2 (5×6) =======================
  {
    id: "fuel_refinery", minTier: 2, category: "machines", power: 30, time: 60,
    pattern: [".SPS.", ".PGP.", ".PGP.", "TPGPT", "CMMMC", "SSSSS"],
    key: {
      S: "techcore:steel_plate", P: "techcore:iron_plate", G: "minecraft:glass", T: "techcore:fuel_tank_part",
      C: "techcore:circuit_basic", M: "techcore:machine_casing",
    },
    result: ["techcore:fuel_refinery", 1],
  },
  {
    id: "engine", minTier: 2, category: "components", power: 32, time: 45,
    pattern: ["S.S.S", "PHPHP", "GBMBG", "SCSCS"],
    key: {
      S: "techcore:steel_plate", P: "minecraft:piston", H: "techcore:steel_shaft", G: "techcore:steel_gear",
      B: "techcore:bearing", M: "techcore:machine_casing", C: "techcore:copper_coil",
    },
    result: ["techcore:engine", 1],
  },
  {
    id: "fuel_tank_part", minTier: 2, category: "components", power: 16, time: 15,
    pattern: ["S.S", "SBS", "SSS"],
    key: { S: "techcore:steel_plate", B: "minecraft:bucket" },
    result: ["techcore:fuel_tank_part", 1],
  },
  {
    id: "radiator", minTier: 2, category: "components", power: 16, time: 15,
    pattern: ["CCCCC", "PIPIP", "CCCCC"],
    key: { C: "techcore:copper_plate", P: "techcore:iron_plate", I: "minecraft:iron_bars" },
    result: ["techcore:radiator", 1],
  },
  {
    id: "diesel_generator", minTier: 2, category: "energy", power: 40, time: 60,
    pattern: ["RSSSR", "TSESC", "PMMMP"],
    key: {
      R: "techcore:radiator", S: "techcore:steel_plate", T: "techcore:fuel_tank_part", E: "techcore:engine",
      C: "techcore:circuit_basic", P: "techcore:iron_plate", M: "techcore:machine_casing",
    },
    result: ["techcore:diesel_generator", 1],
  },
  {
    id: "gasoline_generator", minTier: 2, category: "energy", power: 24, time: 40,
    pattern: ["PTP", "XMX", "PKP"],
    key: { P: "techcore:iron_plate", T: "techcore:fuel_tank_part", X: "minecraft:piston", M: "techcore:motor", K: "techcore:machine_casing" },
    result: ["techcore:gasoline_generator", 1],
  },
  {
    id: "bio_generator", minTier: 2, category: "energy", power: 20, time: 40,
    pattern: ["GTG", "GCG", "XMX", "PKP"],
    key: {
      G: "minecraft:glass", T: "techcore:fuel_tank_part", C: "minecraft:composter", X: "minecraft:piston",
      M: "techcore:motor", P: "techcore:iron_plate", K: "techcore:machine_casing",
    },
    result: ["techcore:bio_generator", 1],
  },
  {
    id: "fuel_tank", minTier: 2, category: "transport", power: 16, time: 25,
    pattern: ["SGS", "S.S", "SGS", "SSS"],
    key: { S: "techcore:steel_plate", G: "minecraft:glass" },
    result: ["techcore:fuel_tank", 1],
  },
  {
    id: "fluid_pipe", minTier: 2, category: "transport", power: 8, time: 8,
    pattern: ["SSS"],
    key: { S: "techcore:steel_plate" },
    result: ["techcore:fluid_pipe", 8],
  },
  {
    id: "conveyor", minTier: 2, category: "transport", power: 12, time: 20,
    pattern: ["RRRRR", "GPMPG"],
    key: { R: "minecraft:dried_kelp", G: "techcore:iron_gear", P: "techcore:iron_plate", M: "techcore:motor" },
    result: ["techcore:conveyor", 4],
  },
  {
    id: "item_filter", minTier: 2, category: "transport", power: 8, time: 10,
    pattern: ["PHP", "PKP", "PQP"],
    key: { P: "techcore:iron_plate", H: "minecraft:hopper", K: "techcore:conveyor", Q: "techcore:circuit_basic" },
    result: ["techcore:item_filter", 1],
  },
  {
    id: "splitter", minTier: 2, category: "transport", power: 8, time: 10,
    pattern: ["PGP", "KQK", "PPP"],
    key: { P: "techcore:iron_plate", G: "techcore:iron_gear", K: "techcore:conveyor", Q: "techcore:circuit_basic" },
    result: ["techcore:splitter", 1],
  },
  {
    id: "buffer_crate", minTier: 2, category: "transport", power: 8, time: 12,
    pattern: ["PSP", "SCS", "PSP"],
    key: { P: "techcore:iron_plate", S: "techcore:steel_plate", C: "minecraft:chest" },
    result: ["techcore:buffer_crate", 1],
  },
  {
    id: "wind_turbine_2", minTier: 2, category: "energy", power: 20, time: 45,
    pattern: ["B...B", ".B.B.", "..H..", ".GMG.", "..S..", ".PSP."],
    key: {
      B: "techcore:steel_plate", H: "techcore:bearing", G: "techcore:iron_gear", M: "techcore:motor",
      S: "techcore:steel_shaft", P: "techcore:iron_plate",
    },
    result: ["techcore:wind_turbine_2", 1],
  },
  {
    id: "drill_rig", minTier: 2, category: "machines", power: 30, time: 60,
    pattern: ["PPKPP", "P.Q.P", "P.M.P", "P.H.P", "P.D.P", "SSSSS"],
    key: {
      P: "techcore:iron_plate", K: "techcore:machine_casing", Q: "techcore:circuit_basic", M: "techcore:motor",
      H: "techcore:steel_shaft", D: "minecraft:diamond_pickaxe", S: "techcore:steel_plate",
    },
    result: ["techcore:drill_rig", 1],
  },
  {
    id: "circuit_advanced", minTier: 2, category: "components", power: 24, time: 20,
    pattern: ["PGGGP", "QXSXQ", "PGGGP"],
    key: { P: "techcore:copper_plate", G: "techcore:gold_plate", Q: "techcore:circuit_basic", X: "techcore:quartz_dust", S: "techcore:silicon" },
    result: ["techcore:circuit_advanced", 2],
  },
  {
    id: "control_module_3", minTier: 2, category: "modules", power: 40, time: 60,
    pattern: ["SRRRS", "CA.AC", "C.B.C", "CA.AC", "SDGDS"],
    key: {
      S: "techcore:steel_plate", R: "minecraft:redstone", C: "techcore:copper_coil", A: "techcore:circuit_advanced",
      B: "techcore:steel_casing", D: "minecraft:diamond", G: "techcore:gold_plate",
    },
    result: ["techcore:control_module_3", 1],
  },

  // ======================= Ур-3 (7×7) =======================
  {
    id: "wind_turbine_3", minTier: 3, category: "energy", power: 40, time: 60,
    pattern: ["T.....T", ".T...T.", "..THT..", "...M...", "..GSG..", "...S...", ".PPSPP."],
    key: {
      T: "techcore:turbine_blade", H: "techcore:bearing", M: "techcore:motor", G: "techcore:steel_gear",
      S: "techcore:steel_shaft", P: "techcore:steel_plate",
    },
    result: ["techcore:wind_turbine_3", 1],
  },
  {
    id: "reinforced_wire", minTier: 3, category: "energy", power: 24, time: 15,
    pattern: ["SGSG", "IIII", "SGSG"],
    key: { S: "techcore:steel_plate", G: "techcore:gold_plate", I: "techcore:insulated_wire" },
    result: ["techcore:reinforced_wire", 4],
  },
  {
    id: "battery_advanced", minTier: 3, category: "energy", power: 60, time: 90,
    pattern: ["SBBBS", "BQCQB", "BCKCB", "BQCQB", "SBBBS"],
    key: {
      S: "techcore:steel_plate", B: "techcore:battery_cell", Q: "techcore:circuit_advanced", C: "techcore:copper_coil",
      K: "techcore:steel_casing",
    },
    result: ["techcore:battery_advanced", 1],
  },
  {
    id: "processor", minTier: 3, category: "components", power: 80, time: 60,
    pattern: ["G.X.G", ".QSQ.", "XSDSX", ".QSQ.", "G.X.G"],
    key: {
      G: "techcore:gold_plate", X: "techcore:quartz_dust", Q: "techcore:circuit_advanced", S: "techcore:silicon",
      D: "techcore:diamond_dust",
    },
    result: ["techcore:processor", 1],
  },
  {
    id: "control_module_4", minTier: 3, category: "modules", power: 80, time: 90,
    pattern: ["SRRRRRS", "R.QPQ.R", "RX.D.XR", "RPDKDPR", "RX.D.XR", "R.QPQ.R", "SRRRRRS"],
    key: {
      S: "techcore:steel_plate", R: "minecraft:redstone", Q: "techcore:circuit_advanced", P: "techcore:gold_plate",
      X: "techcore:quartz_dust", D: "minecraft:diamond", K: "techcore:processor",
    },
    result: ["techcore:control_module_4", 1],
  },

  // ======================= Ур-4 (8×7) =======================
  {
    id: "wind_turbine_4", minTier: 4, category: "energy", power: 60, time: 80,
    pattern: ["T......T", ".T....T.", "..T..T..", "...HH...", "..GMMG..", "...SS...", ".PPSSPP."],
    key: {
      T: "techcore:turbine_blade", H: "techcore:bearing", G: "techcore:steel_gear", M: "techcore:motor",
      S: "techcore:steel_shaft", P: "techcore:steel_plate",
    },
    result: ["techcore:wind_turbine_4", 1],
  },
  {
    id: "control_module_5", minTier: 4, category: "modules", power: 120, time: 120,
    pattern: ["SUUUUUUS", "U.PQQP.U", "UX.DD.XU", "UQDKKDQU", "UX.DD.XU", "U.PQQP.U", "SUUUUUUS"],
    key: {
      S: "techcore:steel_plate", U: "minecraft:redstone_block", P: "techcore:processor", Q: "techcore:circuit_advanced",
      X: "techcore:quartz_dust", D: "techcore:diamond_dust", K: "techcore:superconductor_ingot",
    },
    result: ["techcore:control_module_5", 1],
  },

  // ======================= Ур-5 (9×9) =======================
  {
    id: "wind_turbine_5", minTier: 5, category: "energy", power: 120, time: 120,
    pattern: ["C.......C", ".C.....C.", "..C...C..", "...CHC...", "....Q....", "...GMG...", "....S....", "...PSP...", "..PPSPP.."],
    key: {
      C: "techcore:composite_blade", H: "techcore:bearing", Q: "techcore:processor", G: "techcore:steel_gear",
      M: "techcore:motor", S: "techcore:steel_shaft", P: "techcore:steel_plate",
    },
    result: ["techcore:wind_turbine_5", 1],
  },
  {
    id: "superconductor_wire", minTier: 5, category: "energy", power: 100, time: 40,
    pattern: ["R.R.R.R.", "UUUUUUUU", "R.R.R.R."],
    key: { R: "techcore:reinforced_wire", U: "techcore:superconductor_ingot" },
    result: ["techcore:superconductor_wire", 8],
  },
];

export const ASSEMBLER_RECIPE_BY_ID = new Map(ASSEMBLER_RECIPES.map((r) => [r.id, r]));
