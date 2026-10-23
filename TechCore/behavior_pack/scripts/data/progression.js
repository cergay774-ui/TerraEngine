// Уровни Ультимативного сборщика и стоимость модернизации.
// grid: [ширина, высота] — порядок размеров зафиксирован ТЗ.
// storageTypes — число разных предметов во внутреннем хранилище,
// storageCap   — максимум единиц одного предмета.

/** @type {Array<{tier: number, grid: [number, number], storageTypes: number, storageCap: number, outSlots: number, speed: number, label: string}>} */
export const ASSEMBLER_TIERS = [
  { tier: 0, grid: [4, 4], storageTypes: 12, storageCap: 128, outSlots: 4, speed: 1.0, label: "Ур-0" },
  { tier: 1, grid: [5, 4], storageTypes: 16, storageCap: 192, outSlots: 4, speed: 1.1, label: "Ур-1" },
  { tier: 2, grid: [5, 6], storageTypes: 20, storageCap: 256, outSlots: 6, speed: 1.2, label: "Ур-2" },
  { tier: 3, grid: [7, 7], storageTypes: 24, storageCap: 320, outSlots: 6, speed: 1.35, label: "Ур-3" },
  { tier: 4, grid: [8, 7], storageTypes: 28, storageCap: 384, outSlots: 8, speed: 1.5, label: "Ур-4" },
  { tier: 5, grid: [9, 9], storageTypes: 32, storageCap: 512, outSlots: 8, speed: 1.75, label: "Ур-5" },
];

export const MAX_TIER = ASSEMBLER_TIERS.length - 1;

// Модернизация с уровня (to - 1) на уровень to.
// items — предметы, которые резервируются при запуске (возвращаются при разрушении сборщика),
// power — потребление во время модернизации, E/с; time — длительность, секунды.
/** @type {Record<number, {items: Array<[string, number]>, power: number, time: number}>} */
export const UPGRADES = {
  1: {
    items: [["techcore:control_module_1", 1], ["techcore:iron_plate", 8], ["techcore:iron_gear", 4], ["techcore:copper_coil", 4]],
    power: 20,
    time: 60,
  },
  2: {
    items: [["techcore:control_module_2", 1], ["techcore:steel_plate", 8], ["techcore:steel_shaft", 4], ["techcore:motor", 2], ["techcore:circuit_basic", 4]],
    power: 40,
    time: 90,
  },
  3: {
    items: [["techcore:control_module_3", 1], ["techcore:steel_casing", 4], ["techcore:circuit_advanced", 4], ["techcore:bearing", 4], ["techcore:copper_coil", 8]],
    power: 80,
    time: 120,
  },
  4: {
    items: [["techcore:control_module_4", 1], ["techcore:processor", 2], ["techcore:steel_casing", 6], ["techcore:carbon_composite", 4], ["techcore:gold_plate", 16]],
    power: 160,
    time: 150,
  },
  5: {
    items: [["techcore:control_module_5", 1], ["techcore:processor", 4], ["techcore:superconductor_ingot", 8], ["techcore:carbon_composite", 8], ["techcore:steel_casing", 8]],
    power: 320,
    time: 180,
  },
};

// Этапы прогрессии (для документации и подсказок в интерфейсе).
export const STAGES = {
  1: "Этап I — базовая механика",
  2: "Этап II — электричество",
  3: "Этап III — производство",
  4: "Этап IV — автоматизация",
  5: "Этап V — высокие технологии",
};
