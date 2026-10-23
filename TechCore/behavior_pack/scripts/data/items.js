// Предметы TechCore (не блоки). Используется и скриптами (названия, проверки),
// и генератором ресурсов tools/build_assets.mjs (JSON предметов, языковые файлы).
// group — группа в творческом инвентаре.

export const ITEMS = [
  // --- Измельчённые материалы ---
  { id: "iron_dust", ru: "Железная пыль", en: "Iron Dust", group: "dust" },
  { id: "gold_dust", ru: "Золотая пыль", en: "Gold Dust", group: "dust" },
  { id: "copper_dust", ru: "Медная пыль", en: "Copper Dust", group: "dust" },
  { id: "coal_dust", ru: "Угольная пыль", en: "Coal Dust", group: "dust", fuelSeconds: 20 },
  { id: "diamond_dust", ru: "Алмазная пыль", en: "Diamond Dust", group: "dust" },
  { id: "quartz_dust", ru: "Кварцевая пыль", en: "Quartz Dust", group: "dust" },
  { id: "ender_dust", ru: "Эндер-пыль", en: "Ender Dust", group: "dust" },
  { id: "biomass", ru: "Биомасса", en: "Biomass", group: "dust" },
  { id: "bitumen", ru: "Битум", en: "Bitumen", group: "dust" },

  // --- Слитки и сплавы ---
  { id: "steel_ingot", ru: "Стальной слиток", en: "Steel Ingot", group: "ingot" },
  { id: "silicon", ru: "Кремний", en: "Silicon", group: "ingot" },
  { id: "carbon_composite", ru: "Углекомпозит", en: "Carbon Composite", group: "ingot" },
  { id: "superconductor_ingot", ru: "Сверхпроводящий слиток", en: "Superconductor Ingot", group: "ingot" },

  // --- Пластины ---
  { id: "iron_plate", ru: "Железная пластина", en: "Iron Plate", group: "plate" },
  { id: "copper_plate", ru: "Медная пластина", en: "Copper Plate", group: "plate" },
  { id: "gold_plate", ru: "Золотая пластина", en: "Gold Plate", group: "plate" },
  { id: "steel_plate", ru: "Стальная пластина", en: "Steel Plate", group: "plate" },

  // --- Точные детали ---
  { id: "iron_gear", ru: "Железная шестерня", en: "Iron Gear", group: "part" },
  { id: "steel_gear", ru: "Стальная шестерня", en: "Steel Gear", group: "part" },
  { id: "steel_shaft", ru: "Стальной вал", en: "Steel Shaft", group: "part" },
  { id: "copper_coil", ru: "Медная катушка", en: "Copper Coil", group: "part" },
  { id: "bearing", ru: "Прецизионный подшипник", en: "Precision Bearing", group: "part" },

  // --- Корпуса и узлы ---
  { id: "machine_casing", ru: "Корпус машины", en: "Machine Casing", group: "component" },
  { id: "steel_casing", ru: "Стальной корпус", en: "Steel Casing", group: "component" },
  { id: "motor", ru: "Электромотор", en: "Electric Motor", group: "component" },
  { id: "engine", ru: "Двигатель внутреннего сгорания", en: "Combustion Engine", group: "component" },
  { id: "fuel_tank_part", ru: "Топливный бак", en: "Fuel Tank Unit", group: "component" },
  { id: "radiator", ru: "Радиатор охлаждения", en: "Cooling Radiator", group: "component" },
  { id: "turbine_blade", ru: "Стальная лопасть", en: "Steel Rotor Blade", group: "component" },
  { id: "composite_blade", ru: "Композитная лопасть", en: "Composite Rotor Blade", group: "component" },
  { id: "battery_cell", ru: "Аккумуляторная ячейка", en: "Battery Cell", group: "component" },

  // --- Электроника ---
  { id: "circuit_basic", ru: "Базовая схема", en: "Basic Circuit", group: "electronics" },
  { id: "circuit_advanced", ru: "Улучшенная схема", en: "Advanced Circuit", group: "electronics" },
  { id: "processor", ru: "Процессор", en: "Processor", group: "electronics" },

  // --- Управляющие модули сборщика ---
  { id: "control_module_1", ru: "Управляющий модуль I", en: "Control Module I", group: "module", stack: 16 },
  { id: "control_module_2", ru: "Управляющий модуль II", en: "Control Module II", group: "module", stack: 16 },
  { id: "control_module_3", ru: "Управляющий модуль III", en: "Control Module III", group: "module", stack: 16 },
  { id: "control_module_4", ru: "Управляющий модуль IV", en: "Control Module IV", group: "module", stack: 16 },
  { id: "control_module_5", ru: "Управляющий модуль V", en: "Control Module V", group: "module", stack: 16 },

  // --- Топливо ---
  { id: "canister", ru: "Пустая канистра", en: "Empty Canister", group: "fuel", stack: 16 },
  { id: "canister_diesel", ru: "Канистра дизельного топлива", en: "Diesel Canister", group: "fuel", stack: 1, fluid: "diesel" },
  { id: "canister_gasoline", ru: "Канистра бензина", en: "Gasoline Canister", group: "fuel", stack: 1, fluid: "gasoline" },
  { id: "canister_biofuel", ru: "Канистра биотоплива", en: "Biofuel Canister", group: "fuel", stack: 1, fluid: "biofuel" },

  // --- Инструменты ---
  { id: "engineer_goggles", ru: "Инженерные очки", en: "Engineer Goggles", group: "tool", stack: 1, goggles: true },
  { id: "wrench", ru: "Гаечный ключ", en: "Wrench", group: "tool", stack: 1 },

  // --- Упакованные сборщики (сохраняют уровень при разборке) ---
  { id: "assembler_packed_t1", ru: "Ультимативный сборщик Ур-1", en: "Ultimate Assembler T1", group: "packed", stack: 1, packedTier: 1 },
  { id: "assembler_packed_t2", ru: "Ультимативный сборщик Ур-2", en: "Ultimate Assembler T2", group: "packed", stack: 1, packedTier: 2 },
  { id: "assembler_packed_t3", ru: "Ультимативный сборщик Ур-3", en: "Ultimate Assembler T3", group: "packed", stack: 1, packedTier: 3 },
  { id: "assembler_packed_t4", ru: "Ультимативный сборщик Ур-4", en: "Ultimate Assembler T4", group: "packed", stack: 1, packedTier: 4 },
  { id: "assembler_packed_t5", ru: "Ультимативный сборщик Ур-5", en: "Ultimate Assembler T5", group: "packed", stack: 1, packedTier: 5 },
];

export const ITEM_BY_ID = new Map(ITEMS.map((it) => [`techcore:${it.id}`, it]));

// Ёмкость канистры в миллибакетах (мБ).
export const CANISTER_VOLUME = 1000;

export const CANISTER_BY_FLUID = {
  diesel: "techcore:canister_diesel",
  gasoline: "techcore:canister_gasoline",
  biofuel: "techcore:canister_biofuel",
};

export const FLUIDS = {
  diesel: { ru: "Дизельное топливо", en: "Diesel" },
  gasoline: { ru: "Бензин", en: "Gasoline" },
  biofuel: { ru: "Биотопливо", en: "Biofuel" },
};

export const PACKED_ASSEMBLER_BY_TIER = ["", ...ITEMS.filter((i) => i.packedTier).map((i) => `techcore:${i.id}`)];
