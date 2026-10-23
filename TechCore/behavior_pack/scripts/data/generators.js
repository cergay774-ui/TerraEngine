// Генераторы. Все значения — игровые (не физические) и предназначены для балансировки.
// rated     — номинальная мощность, E/с.
// heat      — модель нагрева (см. logic/heat.js): gain — прирост тепла в секунду при 100% нагрузке,
//             cooling — базовое охлаждение в секунду, coolantBonus — доп. охлаждение от каждого
//             соседнего блока воды/льда/снега, limit — порог перегрева (0..100),
//             recover — порог возврата к полной мощности, throttle — доля мощности при перегреве.

export const WIND_TURBINES = {
  "techcore:wind_turbine_1": { tier: 1, rated: 10, parts: 2, rotor: 18 },
  "techcore:wind_turbine_2": { tier: 2, rated: 18, parts: 2, rotor: 22 },
  "techcore:wind_turbine_3": { tier: 3, rated: 30, parts: 3, rotor: 26 },
  "techcore:wind_turbine_4": { tier: 4, rated: 48, parts: 3, rotor: 28 },
  "techcore:wind_turbine_5": { tier: 5, rated: 75, parts: 4, rotor: 30 },
};

// Игровая модель ветра (см. logic/wind.js и docs/BALANCE.md).
export const WIND_MODEL = {
  // Высотный множитель: линейно от minFactor на minY до 1.0 на fullY, выше — до maxFactor на capY.
  minY: 50,
  fullY: 140,
  capY: 200,
  minFactor: 0.25,
  maxFactor: 1.15,
  // Погода (по событиям смены погоды в Overworld).
  weather: { Clear: 1.0, Rain: 1.25, Thunder: 1.5 },
  // Порывы: детерминированная синусоида ±gustAmplitude.
  gustAmplitude: 0.12,
  gustPeriodSeconds: 47,
  // Затенение ротора: проверяется кольцо 5×5 вокруг ротора (без центра) на трёх уровнях.
  obstructionCheckSeconds: 30,
  obstructionPenalty: 1.6,
  minObstructionFactor: 0.15,
  // Измерения: в Незере ветра нет, в Энде — ровный слабый поток.
  dimensionFactor: { "minecraft:overworld": 1.0, "minecraft:nether": 0.0, "minecraft:the_end": 0.6 },
  // Предел выработки относительно номинала (шторм на высоте).
  outputCap: 1.25,
};

// Твердотопливный генератор.
export const COAL_GENERATOR = {
  rated: 24,
  // Секунды работы на номинале за единицу топлива.
  fuels: {
    "minecraft:coal": 40,
    "minecraft:charcoal": 40,
    "techcore:coal_dust": 20,
    "minecraft:coal_block": 400,
    "minecraft:blaze_rod": 60,
    "minecraft:dried_kelp_block": 20,
  },
  fuelSlotCap: 64,
  heat: { gain: 1.2, cooling: 0.6, coolantBonus: 0.5, limit: 85, recover: 60, throttle: 0.5 },
};

// Жидкотопливные генераторы. burn — расход мБ/с при 100% нагрузке.
export const LIQUID_GENERATORS = {
  "techcore:diesel_generator": {
    fluid: "diesel",
    rated: 120,
    burn: 2,
    tank: 4000,
    heat: { gain: 2.0, cooling: 1.4, coolantBonus: 0.6, limit: 90, recover: 65, throttle: 0.4 },
  },
  "techcore:gasoline_generator": {
    fluid: "gasoline",
    rated: 60,
    burn: 1.5,
    tank: 4000,
    heat: { gain: 1.3, cooling: 1.0, coolantBonus: 0.5, limit: 90, recover: 65, throttle: 0.5 },
  },
  "techcore:bio_generator": {
    fluid: "biofuel",
    rated: 45,
    burn: 2,
    tank: 4000,
    heat: { gain: 0.8, cooling: 0.8, coolantBonus: 0.4, limit: 90, recover: 65, throttle: 0.6 },
  },
};

// Блоки, которые считаются охладителем для генераторов (соседство по граням).
export const COOLANT_BLOCKS = new Set([
  "minecraft:water",
  "minecraft:flowing_water",
  "minecraft:ice",
  "minecraft:packed_ice",
  "minecraft:blue_ice",
  "minecraft:snow",
  "minecraft:powder_snow",
]);

// Аккумуляторы.
export const BATTERIES = {
  "techcore:battery_basic": { capacity: 20000, rate: 100 },
  "techcore:battery_advanced": { capacity: 200000, rate: 600 },
};
