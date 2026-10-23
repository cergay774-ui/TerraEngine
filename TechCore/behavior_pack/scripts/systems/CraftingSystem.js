// Ультимативный сборщик: хранилище ингредиентов, очередь изготовления, авто-режим.
// Ингредиенты резервируются из хранилища в момент запуска изготовления (job.items) и
// возвращаются при отмене или выпадают при разрушении машины — потеря или дублирование
// исключены, т.к. каждая единица всегда находится ровно в одном месте.
import { ASSEMBLER_RECIPES, ASSEMBLER_RECIPE_BY_ID } from "../data/assembler_recipes.js";
import { ASSEMBLER_TIERS, MAX_TIER } from "../data/progression.js";
import * as slots from "../logic/slots.js";
import { requirements, fitsGrid, craftTime } from "../logic/crafting.js";
import { markDirty } from "./Registry.js";
import { registerKind } from "./kinds.js";
import { statusIndex } from "./AnimationSystem.js";
import * as upgrade from "./UpgradeSystem.js";

export const OUT_CAP = 64;

export function tierDef(rec) {
  return ASSEMBLER_TIERS[Math.max(0, Math.min(MAX_TIER, rec.tier | 0))];
}

/** Доступен ли рецепт на уровне сборщика. */
export function recipeAvailable(recipe, tier) {
  return recipe.minTier <= tier && fitsGrid(recipe, ASSEMBLER_TIERS[tier].grid);
}

export function availableRecipes(tier) {
  return ASSEMBLER_RECIPES.filter((r) => recipeAvailable(r, tier));
}

/** Множество предметов, которые сборщик принимает в хранилище на текущем уровне. */
export function acceptedItems(tier) {
  const set = new Set();
  for (const r of availableRecipes(tier)) {
    for (const v of Object.values(r.key)) {
      if (Array.isArray(v)) v.forEach((x) => set.add(x));
      else set.add(v);
    }
  }
  const up = upgrade.nextUpgrade(tier);
  if (up) for (const [id] of up.items) set.add(id);
  return set;
}

/** Сколько единиц id можно положить в хранилище. */
export function storeRoom(rec, id) {
  const td = tierDef(rec);
  if (!acceptedItems(rec.tier).has(id)) return 0;
  return slots.acceptable(rec.store, id, td.storageTypes, td.storageCap);
}

export function storeAdd(rec, id, n) {
  const td = tierDef(rec);
  const added = slots.add(rec.store, id, n, td.storageTypes, td.storageCap);
  if (added > 0) markDirty(rec);
  return added;
}

/** Попытка запустить изготовление выбранного рецепта. */
function tryStartJob(rec) {
  const recipe = ASSEMBLER_RECIPE_BY_ID.get(rec.sel);
  if (!recipe || !recipeAvailable(recipe, rec.tier)) return false;
  const td = tierDef(rec);
  if (!slots.fitsAll(rec.out, [recipe.result], td.outSlots, OUT_CAP)) {
    rec._why = "blocked";
    return false;
  }
  const planned = slots.plan(rec.store, requirements(recipe));
  if (!planned) {
    rec._why = "waiting";
    return false;
  }
  const reserved = [];
  if (!slots.reserve(rec.store, planned, reserved)) return false;
  rec.job = { r: recipe.id, p: 0, items: reserved };
  if (rec.q > 0) rec.q--;
  markDirty(rec);
  return true;
}

/** Отмена текущего изготовления: резерв возвращается в хранилище. */
export function cancelJob(rec) {
  if (!rec.job) return true;
  // Возврат без ограничения ёмкости: эти предметы и так принадлежали хранилищу.
  for (const [id, n] of rec.job.items) slots.add(rec.store, id, n, 1e9, 1e9);
  rec.job = null;
  markDirty(rec);
  return true;
}

registerKind("assembler", {
  init(rec) {
    rec.tier ??= 0;
    rec.store ??= [];
    rec.out ??= [];
    rec.sel ??= null;
    rec.q ??= 0;
    rec.job ??= null;
    rec.upg ??= null;
    rec.st ??= "ready";
    rec.pr ??= 2;
  },
  sanitize(rec) {
    rec.tier = Math.max(0, Math.min(MAX_TIER, Math.floor(Number(rec.tier) || 0)));
    rec.store = slots.sanitize(rec.store);
    rec.out = slots.sanitize(rec.out);
    if (rec.sel && !ASSEMBLER_RECIPE_BY_ID.has(rec.sel)) rec.sel = null;
    if (rec.job) {
      rec.job.items = slots.sanitize(rec.job.items);
      if (!ASSEMBLER_RECIPE_BY_ID.has(rec.job.r)) cancelJob(rec);
      else if (!Number.isFinite(rec.job.p)) rec.job.p = 0;
    }
    upgrade.sanitize(rec);
    if (!Number.isFinite(rec.q)) rec.q = 0;
  },
  contents(rec) {
    const items = [...rec.store, ...rec.out];
    if (rec.job) items.push(...rec.job.items);
    if (rec.upg) items.push(...rec.upg.items);
    return items;
  },
  accept(rec, id) {
    return storeRoom(rec, id);
  },
  insert(rec, id, n) {
    return storeAdd(rec, id, n);
  },
  extract(rec, max) {
    if (rec.out.length === 0) return null;
    const id = rec.out[0][0];
    const n = slots.remove(rec.out, id, max);
    if (n <= 0) return null;
    markDirty(rec);
    return [id, n];
  },
  demand(rec) {
    rec._why = undefined;
    if (rec.upg) return upgrade.demand(rec);
    if (!rec.job && rec.q !== 0 && rec.sel) tryStartJob(rec);
    if (!rec.job) return 0;
    const recipe = ASSEMBLER_RECIPE_BY_ID.get(rec.job.r);
    if (!recipe) return 0;
    if (rec.job.p >= craftTime(recipe, tierDef(rec))) return 0;
    return recipe.power;
  },
  step(rec, env) {
    let st;
    if (rec.upg) st = upgrade.step(rec, env);
    else if (rec.job) {
      const recipe = ASSEMBLER_RECIPE_BY_ID.get(rec.job.r);
      const td = tierDef(rec);
      const time = recipe ? craftTime(recipe, td) : 1;
      if (recipe && rec.job.p < time) {
        const pw = rec._power;
        if (recipe.power <= 0 || (pw && pw.powered)) {
          rec.job.p = Math.min(time, rec.job.p + env.dt);
          st = "working";
        } else st = pw ? pw.reason : "no_power";
        markDirty(rec);
      }
      if (recipe && rec.job.p >= time) {
        if (slots.fitsAll(rec.out, [recipe.result], td.outSlots, OUT_CAP)) {
          slots.add(rec.out, recipe.result[0], recipe.result[1], td.outSlots, OUT_CAP);
          rec.job = null;
          st = "working";
          markDirty(rec);
        } else st = "blocked";
      }
    } else if (rec.sel && rec.q !== 0) st = rec._why ?? "waiting";
    else st = "ready";
    rec._eff = (rec._eff ?? 0) * 0.9 + (st === "working" || st === "upgrading" ? 0.1 : 0);
    if (rec.st !== st) {
      rec.st = st;
      markDirty(rec);
    }
  },
  visual(rec) {
    return { "techcore:tier": rec.tier, "techcore:status": statusIndex(rec.st) };
  },
  info(rec) {
    const lines = [`Уровень: ${tierDef(rec).label}, сетка ${tierDef(rec).grid[0]}×${tierDef(rec).grid[1]}`];
    let use = 0;
    if (rec.upg) {
      const u = upgrade.currentUpgrade(rec);
      lines.push(`Модернизация до Ур-${rec.upg.to}: ${Math.floor((rec.upg.p / u.time) * 100)}%`);
      if (rec.st === "upgrading") use = u.power;
    } else if (rec.job) {
      const recipe = ASSEMBLER_RECIPE_BY_ID.get(rec.job.r);
      if (recipe) {
        lines.push(`Изготовление: ${Math.floor((rec.job.p / craftTime(recipe, tierDef(rec))) * 100)}%`);
        if (rec.st === "working") use = recipe.power;
      }
    }
    return { lines, efficiency: rec._eff ?? 0, powerIn: use, lossPct: rec._pathLoss ?? 0 };
  },
});
