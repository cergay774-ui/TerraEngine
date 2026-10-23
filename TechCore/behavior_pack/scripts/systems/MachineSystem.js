// Главный цикл машин и логика обрабатывающих машин (дробитель, электроплавильня, пресс,
// токарный станок), переработчика топлива и буровой установки.
import { system, world } from "@minecraft/server";
import { BLOCKS } from "../data/machines.js";
import { CONFIG, STEP_SECONDS } from "../data/config.js";
import { MACHINE_RECIPES, findMachineRecipe } from "../data/recipes.js";
import { DRILL, DRILL_DROPS, DRILL_PASSABLE, BITUMEN_HOSTS } from "../data/drill.js";
import * as slots from "../logic/slots.js";
import { emptyTank, sanitizeTank, tankFill, tankRoom } from "../logic/fluids.js";
import { blockAtKey, isLoaded } from "../core/blocks.js";
import { log } from "../core/log.js";
import { records, destroy, markDirty } from "./Registry.js";
import { registerKind, handlerFor } from "./kinds.js";
import * as energy from "./EnergySystem.js";
import * as fluids from "./FuelSystem.js";
import * as animation from "./AnimationSystem.js";

// ---------------------------------------------------------------------------
// Общие функции обрабатывающих машин
// ---------------------------------------------------------------------------

function recipeList(rec) {
  return MACHINE_RECIPES[rec.t] ?? [];
}

function outputFits(rec, recipe, def) {
  if (recipe.fluid) return tankRoom(rec.fl, recipe.fluid.f, def.tank) >= recipe.fluid.a;
  return slots.fitsAll(rec.out, recipe.out, def.outSlots, def.slotCap);
}

/** Пытается начать рецепт: резервирует входы, если выход поместится. */
function tryStart(rec, def) {
  const list = rec.lock ? recipeList(rec).filter((r) => r.id === rec.lock) : recipeList(rec);
  for (const recipe of list) {
    const planned = slots.plan(rec.in, recipe.in);
    if (!planned) continue;
    if (!outputFits(rec, recipe, def)) {
      rec._blockedStart = true;
      continue;
    }
    if (!slots.reserve(rec.in, planned, rec.proc)) continue;
    rec.r = recipe.id;
    rec.p = 0;
    markDirty(rec);
    return recipe;
  }
  return undefined;
}

function finish(rec, recipe, def) {
  if (!outputFits(rec, recipe, def)) return false;
  if (recipe.fluid) tankFill(rec.fl, recipe.fluid.f, recipe.fluid.a, def.tank);
  else for (const [id, n] of recipe.out) slots.add(rec.out, id, n, def.outSlots, def.slotCap);
  rec.proc = [];
  rec.r = null;
  rec.p = 0;
  markDirty(rec);
  return true;
}

/** Множество входных предметов машины (с учётом вариантов). */
const inputCache = new Map();
export function inputIds(machineId) {
  let set = inputCache.get(machineId);
  if (!set) {
    set = new Set();
    for (const r of MACHINE_RECIPES[machineId] ?? []) {
      for (const [what] of r.in) (Array.isArray(what) ? what : [what]).forEach((x) => set.add(x));
    }
    inputCache.set(machineId, set);
  }
  return set;
}

/** Выдача первой позиции из поля слотов. @returns {[string, number] | null} */
export function extractFirst(rec, field, max) {
  const list = rec[field];
  if (!list || list.length === 0) return null;
  const id = list[0][0];
  const n = slots.remove(list, id, max);
  if (n <= 0) return null;
  markDirty(rec);
  return [id, n];
}

function trackEfficiency(rec, working) {
  rec._eff = (rec._eff ?? 0) * 0.9 + (working ? 0.1 : 0);
}

const processorHandler = {
  init(rec) {
    const def = BLOCKS[rec.t];
    rec.in ??= [];
    rec.out ??= [];
    rec.proc ??= [];
    rec.r ??= null;
    rec.p ??= 0;
    rec.st ??= "ready";
    rec.pr ??= def.priority ?? 2;
    rec.lock ??= null;
    if (def.kind === "refinery") rec.fl ??= emptyTank();
  },
  sanitize(rec) {
    rec.in = slots.sanitize(rec.in);
    rec.out = slots.sanitize(rec.out);
    rec.proc = slots.sanitize(rec.proc);
    if (rec.r && !findMachineRecipe(rec.t, rec.r)) {
      // Рецепт удалён из конфигурации — возвращаем зарезервированное во вход.
      const def = BLOCKS[rec.t];
      for (const [id, n] of rec.proc) slots.add(rec.in, id, n, def.inSlots + 8, def.slotCap * 4);
      rec.proc = [];
      rec.r = null;
      rec.p = 0;
    }
    if (rec.lock && !findMachineRecipe(rec.t, rec.lock)) rec.lock = null;
    if (BLOCKS[rec.t].kind === "refinery") rec.fl = sanitizeTank(rec.fl);
  },
  contents(rec) {
    return [...rec.in, ...rec.out, ...rec.proc];
  },
  accept(rec, id) {
    const def = BLOCKS[rec.t];
    if (!inputIds(rec.t).has(id)) return 0;
    return slots.acceptable(rec.in, id, def.inSlots, def.slotCap);
  },
  insert(rec, id, n) {
    const def = BLOCKS[rec.t];
    const a = slots.add(rec.in, id, n, def.inSlots, def.slotCap);
    if (a > 0) markDirty(rec);
    return a;
  },
  extract(rec, max) {
    return extractFirst(rec, "out", max);
  },
  demand(rec) {
    const def = BLOCKS[rec.t];
    rec._blockedStart = false;
    let recipe = rec.r ? findMachineRecipe(rec.t, rec.r) : undefined;
    if (!recipe) recipe = tryStart(rec, def);
    if (!recipe) return 0;
    if (rec.p >= recipe.time) return 0; // готово, ждёт место на выходе
    return recipe.power ?? def.power;
  },
  step(rec, env) {
    const def = BLOCKS[rec.t];
    const recipe = rec.r ? findMachineRecipe(rec.t, rec.r) : undefined;
    let st;
    if (!recipe) {
      st = rec._blockedStart ? "blocked" : rec.in.length > 0 ? "waiting" : "ready";
      trackEfficiency(rec, false);
    } else {
      if (rec.p < recipe.time) {
        const pw = rec._power;
        if (pw && pw.powered) {
          rec.p = Math.min(recipe.time, rec.p + env.dt);
          st = "working";
          markDirty(rec);
        } else st = pw ? pw.reason : "no_power";
        trackEfficiency(rec, st === "working");
      }
      if (rec.p >= recipe.time) {
        if (finish(rec, recipe, def)) {
          st = "working";
          // Сразу пробуем начать следующий цикл, чтобы не терять шаг.
        } else st = "blocked";
      }
    }
    if (st && rec.st !== st) {
      rec.st = st;
      markDirty(rec);
    }
  },
  visual(rec) {
    return { "techcore:status": animation.statusIndex(rec.st) };
  },
  info(rec) {
    const def = BLOCKS[rec.t];
    const recipe = rec.r ? findMachineRecipe(rec.t, rec.r) : undefined;
    const use = rec.st === "working" && recipe ? (recipe.power ?? def.power) : 0;
    const lines = [];
    if (recipe) lines.push(`Процесс: ${Math.floor((rec.p / recipe.time) * 100)}% из ${recipe.time} с`);
    if (def.kind === "refinery") lines.push(`Бак: ${Math.floor(rec.fl.a)} / ${def.tank} мБ`);
    return { lines, efficiency: rec._eff ?? 0, powerIn: use, lossPct: rec._pathLoss ?? 0 };
  },
};

registerKind("processor", processorHandler);
registerKind("refinery", processorHandler);

// ---------------------------------------------------------------------------
// Буровая установка
// ---------------------------------------------------------------------------

const DRILL_OFFSETS = (() => {
  const out = [];
  for (let dz = -DRILL.radius; dz <= DRILL.radius; dz++)
    for (let dx = -DRILL.radius; dx <= DRILL.radius; dx++) out.push([dx, dz]);
  return out;
})();

/** Один шаг поиска и добычи. @returns {"mined"|"blocked"|"done"|"skip"} */
function drillOnce(rec, def) {
  const dim = world.getDimension(rec._dim);
  const minY = dim.heightRange.min;
  for (let scanned = 0; scanned < DRILL.scanPerStep; scanned++) {
    if (rec.dy < minY) return "done";
    const [dx, dz] = DRILL_OFFSETS[rec.di];
    const loc = { x: rec.x + dx, y: rec.dy, z: rec.z + dz };
    const advance = () => {
      rec.di++;
      if (rec.di >= DRILL_OFFSETS.length) {
        rec.di = 0;
        rec.dy--;
      }
    };
    if (!dim.isChunkLoaded(loc)) return "skip";
    const block = dim.getBlock(loc);
    if (!block) return "skip";
    const id = block.typeId;
    const drop = DRILL_DROPS[id];
    if (!drop) {
      advance();
      if (!DRILL_PASSABLE.has(id)) rec.skipped = (rec.skipped ?? 0) + 1;
      continue;
    }
    /** @type {Array<[string, number]>} */
    const items = [drop === "self" ? [id, 1] : [drop[0], drop[1]]];
    if (BITUMEN_HOSTS.has(id) && rec.dy < DRILL.bitumenBelowY && Math.random() < DRILL.bitumenChance) {
      items.push(["techcore:bitumen", 1]);
    }
    if (!slots.fitsAll(rec.out, items, def.outSlots, def.slotCap)) return "blocked";
    block.setType("minecraft:air");
    for (const [iid, n] of items) slots.add(rec.out, iid, n, def.outSlots, def.slotCap);
    rec.mined = (rec.mined ?? 0) + 1;
    advance();
    return "mined";
  }
  return "skip";
}

registerKind("drill", {
  init(rec) {
    rec.out ??= [];
    rec.p ??= 0;
    rec.st ??= "ready";
    rec.pr ??= BLOCKS[rec.t].priority ?? 3;
    rec.dy ??= rec.y - 1;
    rec.di ??= 0;
    rec.on ??= true;
  },
  sanitize(rec) {
    rec.out = slots.sanitize(rec.out);
    if (!Number.isFinite(rec.dy)) rec.dy = rec.y - 1;
    if (!Number.isFinite(rec.di) || rec.di < 0 || rec.di >= DRILL_OFFSETS.length) rec.di = 0;
  },
  contents(rec) {
    return rec.out;
  },
  extract(rec, max) {
    return extractFirst(rec, "out", max);
  },
  demand(rec) {
    const def = BLOCKS[rec.t];
    if (!rec.on || rec.st === "done") return 0;
    if (slots.total(rec.out) >= def.outSlots * def.slotCap) return 0;
    return def.power;
  },
  step(rec, env) {
    const def = BLOCKS[rec.t];
    let st = rec.st;
    if (!rec.on) st = "off";
    else if (rec.st === "done") st = "done";
    else {
      const pw = rec._power;
      if (pw && pw.powered && pw.received > 0) {
        rec.p += env.dt;
        st = "working";
        while (rec.p >= DRILL.secondsPerBlock) {
          const r = drillOnce(rec, def);
          if (r === "blocked") {
            st = "blocked";
            rec.p = DRILL.secondsPerBlock;
            break;
          }
          if (r === "done") {
            st = "done";
            rec.p = 0;
            break;
          }
          rec.p -= DRILL.secondsPerBlock;
          if (r === "skip") break;
        }
        markDirty(rec);
      } else if (slots.total(rec.out) >= def.outSlots * def.slotCap) st = "blocked";
      else st = pw ? pw.reason : "no_power";
    }
    trackEfficiency(rec, st === "working");
    if (rec.st !== st) {
      rec.st = st;
      markDirty(rec);
    }
  },
  visual(rec) {
    return { "techcore:status": animation.statusIndex(rec.st) };
  },
  info(rec) {
    const def = BLOCKS[rec.t];
    return {
      lines: [`Глубина: Y=${rec.dy}`, `Добыто блоков: ${rec.mined ?? 0}`],
      efficiency: rec._eff ?? 0,
      powerIn: rec.st === "working" ? def.power : 0,
      lossPct: rec._pathLoss ?? 0,
    };
  },
});

// ---------------------------------------------------------------------------
// Главный цикл
// ---------------------------------------------------------------------------

let stepCounter = 0;

function makeEnv(rec, dt, tick) {
  let cached;
  let fetched = false;
  return {
    dt,
    tick,
    get block() {
      if (!fetched) {
        cached = blockAtKey(rec.k);
        fetched = true;
      }
      return cached;
    },
  };
}

function machineStep() {
  const dt = STEP_SECONDS;
  const tick = system.currentTick;
  stepCounter++;
  /** @type {Map<string, any>} */
  const envs = new Map();
  const envFor = (rec) => {
    let e = envs.get(rec.k);
    if (!e) {
      e = makeEnv(rec, dt, tick);
      envs.set(rec.k, e);
    }
    return e;
  };

  // 1. Загруженность чанков. Изменение — повод перестроить сети.
  for (const rec of records.values()) {
    const loaded = isLoaded(rec._dim, rec.x, rec.y, rec.z);
    if (rec._loaded !== loaded) {
      rec._loaded = loaded;
      rec._vis = undefined;
      energy.markDirty();
      fluids.markNetworkDirty();
    }
  }

  // 2. Проверка, что блок на месте (раз в 5 шагов, по очереди).
  if (stepCounter % 5 === 0) {
    for (const rec of [...records.values()]) {
      if (!rec._loaded) continue;
      const b = envFor(rec).block;
      if (b && b.typeId !== rec.t) {
        log.warn(`Машина ${rec.t} в ${rec.k} пропала без события разрушения — запись удалена`);
        destroy(rec.k, true);
      }
    }
  }

  // 3. Энергия: запросы потребителей, предложения генераторов, распределение.
  energy.step(envFor, dt);

  // 4. Шаг машин.
  for (const rec of records.values()) {
    if (!rec._loaded) continue;
    const h = handlerFor(rec.t);
    if (!h || !h.step) continue;
    try {
      h.step(rec, envFor(rec));
    } catch (e) {
      log.warn(`Ошибка шага ${rec.t} в ${rec.k}: ${e}`);
    }
  }

  // 5. Жидкости.
  fluids.step(dt);

  // 6. Визуальные состояния и звуки.
  for (const rec of records.values()) {
    if (!rec._loaded) continue;
    animation.syncVisual(rec, envFor(rec));
  }
  animation.playSounds(stepCounter);
}

export function startMachineLoop() {
  system.runInterval(() => {
    try {
      machineStep();
    } catch (e) {
      log.error(`Сбой основного цикла: ${e}`);
    }
  }, CONFIG.machineTickInterval);
}
