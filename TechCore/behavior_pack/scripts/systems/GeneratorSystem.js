// Генераторы и аккумуляторы.
import { world, WeatherType } from "@minecraft/server";
import { WIND_TURBINES, WIND_MODEL, COAL_GENERATOR, LIQUID_GENERATORS, COOLANT_BLOCKS, BATTERIES } from "../data/generators.js";
import * as slots from "../logic/slots.js";
import { windFactor, obstructionFactor, positionSeed, spinState } from "../logic/wind.js";
import { stepHeat, heatThrottle } from "../logic/heat.js";
import { emptyTank, sanitizeTank, tankDrain } from "../logic/fluids.js";
import { FACES } from "../core/positions.js";
import { safeOffset } from "../core/blocks.js";
import { fluidName } from "../core/text.js";
import { markDirty } from "./Registry.js";
import { registerKind } from "./kinds.js";
import { statusIndex } from "./AnimationSystem.js";

// ---------------------------------------------------------------------------
// Погода: Script API не даёт прямого чтения текущей погоды в стабильной версии,
// поэтому она отслеживается по событиям смены погоды и сохраняется в мире.
// ---------------------------------------------------------------------------
const WEATHER_KEY = "tc:weather";
let weather = "Clear";

export function initWeather() {
  const saved = world.getDynamicProperty(WEATHER_KEY);
  if (typeof saved === "string") weather = saved;
  world.afterEvents.weatherChange.subscribe((e) => {
    if (e.dimension !== "minecraft:overworld" && e.dimension !== "overworld") return;
    weather = e.newWeather === WeatherType.Thunder ? "Thunder" : e.newWeather === WeatherType.Rain ? "Rain" : "Clear";
    world.setDynamicProperty(WEATHER_KEY, weather);
  });
}

export function currentWeather() {
  return weather;
}

const WEATHER_RU = { Clear: "ясно", Rain: "дождь", Thunder: "гроза" };

// ---------------------------------------------------------------------------
// Ветрогенераторы
// ---------------------------------------------------------------------------

function measureObstruction(rec, block) {
  const spec = WIND_TURBINES[rec.t];
  const rotorY = spec.parts - 1;
  let solid = 0;
  let checked = 0;
  for (let dy = -1; dy <= 1; dy++) {
    for (let dx = -2; dx <= 2; dx++) {
      for (let dz = -2; dz <= 2; dz++) {
        if (dx === 0 && dz === 0) continue;
        const b = safeOffset(block, dx, rotorY + dy, dz);
        if (!b) continue;
        checked++;
        if (!b.isAir && !b.isLiquid) solid++;
      }
    }
  }
  return obstructionFactor(solid, checked, WIND_MODEL);
}

registerKind("wind", {
  init(rec) {
    rec.st ??= "ready";
    rec.obs ??= 1;
  },
  sanitize(rec) {
    if (!Number.isFinite(rec.obs)) rec.obs = 1;
  },
  contents() {
    return [];
  },
  supply(rec, env) {
    const spec = WIND_TURBINES[rec.t];
    if (env.block && (rec._obsAt === undefined || env.tick - rec._obsAt >= WIND_MODEL.obstructionCheckSeconds * 20)) {
      rec.obs = measureObstruction(rec, env.block);
      rec._obsAt = env.tick;
    }
    const f = windFactor(
      {
        y: rec.y + spec.parts - 1,
        weather,
        dimension: rec._dim,
        obstruction: rec.obs,
        timeSeconds: env.tick / 20,
        seed: positionSeed(rec.x, rec.y, rec.z),
      },
      WIND_MODEL,
    );
    rec._wind = f;
    rec._avail = spec.rated * f;
    return { available: rec._avail, free: true };
  },
  step(rec) {
    const g = rec._gen ?? { output: 0, load: 0 };
    let st;
    if ((rec._avail ?? 0) <= 0.01) st = "no_wind";
    else if (g.load < 0.01) st = "idle_load";
    else st = "working";
    if (rec.st !== st) {
      rec.st = st;
      markDirty(rec);
    }
  },
  visual() {
    return {};
  },
  visualParts(rec) {
    const spec = WIND_TURBINES[rec.t];
    // Ротор вращается от ветра, даже без нагрузки (холостой ход).
    return [[spec.parts - 1, { "techcore:spin": spinState(rec._wind ?? 0) }]];
  },
  info(rec) {
    const spec = WIND_TURBINES[rec.t];
    const out = rec._gen?.output ?? 0;
    return {
      lines: [
        `Ветер: ${Math.round((rec._wind ?? 0) * 100)}% (высота Y=${rec.y + spec.parts - 1}, ${WEATHER_RU[weather] ?? weather})`,
        `Затенение ротора: ${Math.round((1 - (rec.obs ?? 1)) * 100)}%`,
        `Доступно: ${(rec._avail ?? 0).toFixed(1)} E/с из ${spec.rated}`,
      ],
      efficiency: out / spec.rated,
      powerOut: out,
    };
  },
});

// ---------------------------------------------------------------------------
// Охлаждение: соседние блоки воды/льда/снега
// ---------------------------------------------------------------------------

function countCoolants(block) {
  let n = 0;
  for (const f of FACES) {
    const b = safeOffset(block, f.dx, f.dy, f.dz);
    if (b && COOLANT_BLOCKS.has(b.typeId)) n++;
  }
  return n;
}

function updateCoolants(rec, env) {
  if (env.block && (rec._coolAt === undefined || env.tick - rec._coolAt >= 200)) {
    rec._cool = countCoolants(env.block);
    rec._coolAt = env.tick;
  }
  return rec._cool ?? 0;
}

// ---------------------------------------------------------------------------
// Угольный генератор
// ---------------------------------------------------------------------------

export function coalFuelSeconds(id) {
  return COAL_GENERATOR.fuels[id] ?? 0;
}

registerKind("coal_generator", {
  init(rec) {
    rec.fuel ??= [];
    rec.burn ??= 0;
    rec.heat ??= 0;
    rec.oh ??= false;
    rec.st ??= "no_fuel";
  },
  sanitize(rec) {
    rec.fuel = slots.sanitize(rec.fuel).filter(([id]) => coalFuelSeconds(id) > 0);
    if (!Number.isFinite(rec.burn) || rec.burn < 0) rec.burn = 0;
    if (!Number.isFinite(rec.heat)) rec.heat = 0;
  },
  contents(rec) {
    return rec.fuel;
  },
  accept(rec, id) {
    if (coalFuelSeconds(id) <= 0) return 0;
    return slots.acceptable(rec.fuel, id, 2, COAL_GENERATOR.fuelSlotCap);
  },
  insert(rec, id, n) {
    if (coalFuelSeconds(id) <= 0) return 0;
    const a = slots.add(rec.fuel, id, n, 2, COAL_GENERATOR.fuelSlotCap);
    if (a > 0) markDirty(rec);
    return a;
  },
  supply(rec, env) {
    updateCoolants(rec, env);
    const hasFuel = rec.burn > 0 || rec.fuel.length > 0;
    const thr = heatThrottle({ heat: rec.heat, overheated: rec.oh }, COAL_GENERATOR.heat);
    return { available: hasFuel ? COAL_GENERATOR.rated * thr : 0, free: false };
  },
  step(rec, env) {
    const g = rec._gen ?? { output: 0, load: 0 };
    // Расход в "секундах номинала": при нагрузке 50% топливо горит вдвое дольше.
    const need = (g.output / COAL_GENERATOR.rated) * env.dt;
    while (rec.burn < need && rec.fuel.length > 0) {
      const id = rec.fuel[0][0];
      slots.remove(rec.fuel, id, 1);
      rec.burn += coalFuelSeconds(id);
    }
    rec.burn = Math.max(0, rec.burn - need);
    const load = g.output / COAL_GENERATOR.rated;
    const h = stepHeat({ heat: rec.heat, overheated: rec.oh }, load, rec._cool ?? 0, COAL_GENERATOR.heat, env.dt);
    rec.heat = h.heat;
    rec.oh = h.overheated;
    let st;
    if (rec.burn <= 0 && rec.fuel.length === 0) st = "no_fuel";
    else if (g.output < 0.01) st = "idle_load";
    else if (rec.oh) st = "overheat";
    else st = "working";
    if (rec.st !== st) rec.st = st;
    if (g.output > 0 || rec.heat > 0) markDirty(rec);
  },
  visual(rec) {
    return { "techcore:status": statusIndex(rec.st) };
  },
  info(rec) {
    const out = rec._gen?.output ?? 0;
    const items = rec.fuel.reduce((s, [, n]) => s + n, 0);
    return {
      lines: [`Топливо: ${items} шт., горение ${Math.ceil(rec.burn)} с`, `Нагрев: ${Math.round(rec.heat)}%  Охладителей рядом: ${rec._cool ?? 0}`],
      efficiency: out / COAL_GENERATOR.rated,
      powerOut: out,
    };
  },
});

// ---------------------------------------------------------------------------
// Жидкотопливные генераторы
// ---------------------------------------------------------------------------

registerKind("liquid_generator", {
  init(rec) {
    rec.tank ??= emptyTank();
    rec.heat ??= 0;
    rec.oh ??= false;
    rec.st ??= "no_fuel";
  },
  sanitize(rec) {
    rec.tank = sanitizeTank(rec.tank);
    const spec = LIQUID_GENERATORS[rec.t];
    if (rec.tank.f && rec.tank.f !== spec.fluid) rec.tank = emptyTank();
    if (!Number.isFinite(rec.heat)) rec.heat = 0;
  },
  contents() {
    // Жидкость не может быть выброшена предметом — при разрушении теряется (см. ограничения).
    return [];
  },
  supply(rec, env) {
    const spec = LIQUID_GENERATORS[rec.t];
    updateCoolants(rec, env);
    const thr = heatThrottle({ heat: rec.heat, overheated: rec.oh }, spec.heat);
    // Ограничение остатком топлива в баке на этот шаг.
    const fuelLimited = Math.min(1, rec.tank.a / Math.max(1e-6, spec.burn * env.dt));
    return { available: spec.rated * thr * fuelLimited, free: false };
  },
  step(rec, env) {
    const spec = LIQUID_GENERATORS[rec.t];
    const g = rec._gen ?? { output: 0, load: 0 };
    const load = g.output / spec.rated;
    tankDrain(rec.tank, spec.burn * load * env.dt);
    const h = stepHeat({ heat: rec.heat, overheated: rec.oh }, load, rec._cool ?? 0, spec.heat, env.dt);
    rec.heat = h.heat;
    rec.oh = h.overheated;
    let st;
    if (rec.tank.a <= 0) st = "no_fuel";
    else if (g.output < 0.01) st = "idle_load";
    else if (rec.oh) st = "overheat";
    else st = "working";
    rec.st = st;
    if (g.output > 0 || rec.heat > 0) markDirty(rec);
  },
  visual(rec) {
    return { "techcore:status": statusIndex(rec.st) };
  },
  info(rec) {
    const spec = LIQUID_GENERATORS[rec.t];
    const out = rec._gen?.output ?? 0;
    return {
      lines: [
        `Топливо: ${fluidName(spec.fluid)} ${Math.floor(rec.tank.a)} / ${spec.tank} мБ`,
        `Расход: ${(spec.burn * (out / spec.rated)).toFixed(2)} мБ/с  Нагрев: ${Math.round(rec.heat)}%`,
      ],
      efficiency: out / spec.rated,
      powerOut: out,
    };
  },
});

// ---------------------------------------------------------------------------
// Аккумуляторы
// ---------------------------------------------------------------------------

registerKind("battery", {
  init(rec) {
    rec.ch ??= 0;
    rec.st ??= "empty";
  },
  sanitize(rec) {
    const spec = BATTERIES[rec.t];
    if (!Number.isFinite(rec.ch) || rec.ch < 0) rec.ch = 0;
    rec.ch = Math.min(spec.capacity, rec.ch);
  },
  contents() {
    return [];
  },
  storage(rec) {
    const spec = BATTERIES[rec.t];
    return { charge: rec.ch, capacity: spec.capacity, rate: spec.rate };
  },
  step(rec, env) {
    const spec = BATTERIES[rec.t];
    const d = rec._battDelta ?? 0;
    rec.ch = Math.max(0, Math.min(spec.capacity, rec.ch + d));
    rec._rate = d / env.dt;
    let st;
    if (d > 0.01) st = "charging";
    else if (d < -0.01) st = "discharging";
    else if (rec.ch >= spec.capacity - 0.5) st = "full";
    else if (rec.ch <= 0.5) st = "empty";
    else st = "ready";
    rec.st = st;
    if (Math.abs(d) > 0) markDirty(rec);
  },
  visual(rec) {
    const spec = BATTERIES[rec.t];
    return { "techcore:level": Math.min(4, Math.floor((rec.ch / spec.capacity) * 5)) };
  },
  info(rec) {
    const spec = BATTERIES[rec.t];
    const r = rec._rate ?? 0;
    return {
      lines: [`Заряд: ${Math.floor(rec.ch)} / ${spec.capacity} E (${Math.round((rec.ch / spec.capacity) * 100)}%)`, `Макс. скорость: ${spec.rate} E/с`],
      efficiency: Math.abs(r) / spec.rate,
      powerIn: r > 0 ? r : 0,
      powerOut: r < 0 ? -r : 0,
    };
  },
});

