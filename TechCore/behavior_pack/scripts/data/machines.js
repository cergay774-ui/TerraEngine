// Реестр блоков TechCore: названия, роли в энергосети и параметры машин.
// role: "consumer" | "generator" | "storage" | "wire" | "pipe" | "transport" | "fluid_storage"
// kind: логика обработки (см. systems/*).

export const PRIORITY = { HIGH: 1, NORMAL: 2, LOW: 3 };

export const BLOCKS = {
  // ---------------- Сборщик ----------------
  "techcore:ultimate_assembler": {
    ru: "Ультимативный сборщик",
    en: "Ultimate Assembler",
    role: "consumer",
    kind: "assembler",
    priority: PRIORITY.NORMAL,
    stage: 1,
    sound: { id: "block.smithing_table.use", pitch: 1.3, volume: 0.35 },
  },

  // ---------------- Генераторы ----------------
  "techcore:coal_generator": { ru: "Угольный генератор", en: "Coal Generator", role: "generator", kind: "coal_generator", stage: 1, sound: { id: "fire.fire", pitch: 0.8, volume: 0.6 } },
  "techcore:diesel_generator": { ru: "Дизельный генератор", en: "Diesel Generator", role: "generator", kind: "liquid_generator", stage: 3, fluidRole: "consumer", sound: { id: "mob.irongolem.walk", pitch: 0.6, volume: 0.45 } },
  "techcore:gasoline_generator": { ru: "Бензиновый генератор", en: "Gasoline Generator", role: "generator", kind: "liquid_generator", stage: 3, fluidRole: "consumer", sound: { id: "mob.irongolem.walk", pitch: 1.1, volume: 0.35 } },
  "techcore:bio_generator": { ru: "Биотопливный генератор", en: "Biofuel Generator", role: "generator", kind: "liquid_generator", stage: 3, fluidRole: "consumer", sound: { id: "bubble.pop", pitch: 0.7, volume: 0.5 } },
  "techcore:wind_turbine_1": { ru: "Ветрогенератор I", en: "Wind Turbine I", role: "generator", kind: "wind", stage: 1 },
  "techcore:wind_turbine_2": { ru: "Ветрогенератор II", en: "Wind Turbine II", role: "generator", kind: "wind", stage: 3 },
  "techcore:wind_turbine_3": { ru: "Ветрогенератор III", en: "Wind Turbine III", role: "generator", kind: "wind", stage: 5 },
  "techcore:wind_turbine_4": { ru: "Ветрогенератор IV", en: "Wind Turbine IV", role: "generator", kind: "wind", stage: 5 },
  "techcore:wind_turbine_5": { ru: "Ветрогенератор V", en: "Wind Turbine V", role: "generator", kind: "wind", stage: 5 },

  // ---------------- Хранение энергии ----------------
  "techcore:battery_basic": { ru: "Аккумуляторный блок", en: "Battery Block", role: "storage", kind: "battery", stage: 2 },
  "techcore:battery_advanced": { ru: "Улучшенный аккумулятор", en: "Advanced Battery", role: "storage", kind: "battery", stage: 5 },

  // ---------------- Провода ----------------
  "techcore:copper_wire": { ru: "Медный провод", en: "Copper Wire", role: "wire", stage: 1 },
  "techcore:insulated_wire": { ru: "Изолированный провод", en: "Insulated Wire", role: "wire", stage: 3 },
  "techcore:reinforced_wire": { ru: "Усиленный провод", en: "Reinforced Wire", role: "wire", stage: 5 },
  "techcore:superconductor_wire": { ru: "Сверхпроводящий провод", en: "Superconductor Wire", role: "wire", stage: 5 },

  // ---------------- Производство ----------------
  "techcore:drill_rig": {
    ru: "Буровая установка", en: "Drilling Rig", role: "consumer", kind: "drill", stage: 3, priority: PRIORITY.LOW,
    power: 40, outSlots: 9, slotCap: 64,
    sound: { id: "dig.stone", pitch: 0.7, volume: 0.6 },
  },
  "techcore:crusher": {
    ru: "Дробитель", en: "Crusher", role: "consumer", kind: "processor", stage: 2, priority: PRIORITY.NORMAL,
    power: 16, inSlots: 2, outSlots: 2, slotCap: 64,
    sound: { id: "block.grindstone.use", pitch: 0.8, volume: 0.4 },
  },
  "techcore:electric_smelter": {
    ru: "Электроплавильня", en: "Electric Smelter", role: "consumer", kind: "processor", stage: 2, priority: PRIORITY.NORMAL,
    power: 24, inSlots: 4, outSlots: 2, slotCap: 64,
    sound: { id: "block.blastfurnace.fire_crackle", pitch: 1.0, volume: 0.5 },
  },
  "techcore:press": {
    ru: "Пресс", en: "Press", role: "consumer", kind: "processor", stage: 3, priority: PRIORITY.NORMAL,
    power: 20, inSlots: 2, outSlots: 2, slotCap: 64, animated: true,
    sound: { id: "random.anvil_land", pitch: 1.6, volume: 0.25 },
  },
  "techcore:lathe": {
    ru: "Токарный станок", en: "Lathe", role: "consumer", kind: "processor", stage: 3, priority: PRIORITY.NORMAL,
    power: 20, inSlots: 2, outSlots: 2, slotCap: 64,
    sound: { id: "block.grindstone.use", pitch: 1.5, volume: 0.3 },
  },
  "techcore:fuel_refinery": {
    ru: "Переработчик топлива", en: "Fuel Refinery", role: "consumer", kind: "refinery", stage: 4, priority: PRIORITY.NORMAL,
    power: 30, inSlots: 3, outSlots: 0, slotCap: 64, tank: 4000, fluidRole: "source",
    sound: { id: "bubble.pop", pitch: 0.5, volume: 0.5 },
  },

  // ---------------- Транспорт ----------------
  "techcore:conveyor": { ru: "Конвейер", en: "Conveyor", role: "transport", kind: "conveyor", stage: 4 },
  "techcore:item_filter": { ru: "Фильтр предметов", en: "Item Filter", role: "transport", kind: "filter", stage: 4 },
  "techcore:splitter": { ru: "Разветвитель", en: "Splitter", role: "transport", kind: "splitter", stage: 4 },
  "techcore:buffer_crate": { ru: "Буферный контейнер", en: "Buffer Crate", role: "transport", kind: "buffer", stage: 4, slots: 9, slotCap: 256 },

  // ---------------- Жидкости ----------------
  "techcore:fluid_pipe": { ru: "Топливная труба", en: "Fuel Pipe", role: "pipe", stage: 4 },
  "techcore:fuel_tank": { ru: "Топливный резервуар", en: "Fuel Tank", role: "fluid_storage", kind: "tank", stage: 4, fluidRole: "storage" },
};

export const BLOCK_IDS = Object.keys(BLOCKS);

// Блоки, у которых есть сохраняемое состояние (запись в реестре машин).
export function hasRecord(typeId) {
  const def = BLOCKS[typeId];
  return !!def && def.role !== "wire" && def.role !== "pipe";
}

// Энергетические узлы (участвуют в энергосети).
export function isEnergyNode(typeId) {
  const def = BLOCKS[typeId];
  return !!def && (def.role === "consumer" || def.role === "generator" || def.role === "storage");
}

// Жидкостные узлы (участвуют в трубной сети).
export function isFluidNode(typeId) {
  const def = BLOCKS[typeId];
  return !!def && !!def.fluidRole;
}
