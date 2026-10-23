// Интерфейс Ультимативного сборщика.
// Сетка рецепта отображается как схема ячеек с легендой. Предметы не раскладываются игроком
// по ячейкам: Bedrock не позволяет создать произвольную сетку слотов скриптом (см.
// docs/TECHNICAL_LIMITATIONS.md). Вместо этого ингредиенты загружаются во внутреннее
// хранилище, а сетка определяет форму, размер и стоимость рецепта.
import { ActionFormData } from "@minecraft/server-ui";
import { ASSEMBLER_RECIPES, ASSEMBLER_RECIPE_BY_ID, CATEGORIES } from "../data/assembler_recipes.js";
import { ASSEMBLER_TIERS, MAX_TIER } from "../data/progression.js";
import * as slots from "../logic/slots.js";
import { requirements, patternSize, craftTime } from "../logic/crafting.js";
import { takeFromPlayer, giveToPlayer } from "../core/inventory.js";
import { rt, itemName, reqName, statusText, bar, seconds, num } from "../core/text.js";
import { saveNow } from "../systems/Registry.js";
import { networkAt } from "../systems/EnergySystem.js";
import { tierDef, availableRecipes, recipeAvailable, storeRoom, storeAdd, cancelJob, OUT_CAP } from "../systems/CraftingSystem.js";
import * as upgrade from "../systems/UpgradeSystem.js";
import { live, showForm, itemIcon, slotsText, tell, machineName } from "./common.js";
import { giveSlots, insertFromPlayer } from "./MachineUI.js";
import { openNetworkUI } from "./NetworkUI.js";

/** @typedef {import("@minecraft/server").Player} Player */

const ICON = {
  recipes: "textures/techcore/icons/ui_recipes",
  insert: "textures/techcore/icons/ui_insert",
  take: "textures/techcore/icons/ui_take",
  upgrade: "textures/techcore/icons/ui_upgrade",
  network: "textures/techcore/icons/ui_network",
  stop: "textures/techcore/icons/ui_power",
  refresh: "textures/techcore/icons/ui_refresh",
  storage: "textures/techcore/icons/ui_storage",
};

async function run(player, form, actions) {
  const res = await showForm(player, form);
  if (!res || res.selection === undefined) return;
  const fn = actions[res.selection];
  if (fn) await fn();
}

function makeForm(title, body) {
  const form = new ActionFormData().title(title).body(body);
  const actions = [];
  const add = (label, icon, fn) => {
    form.button(label, icon);
    actions.push(fn);
  };
  return { form, actions, add };
}

function energyLine(rec) {
  const pw = rec._power;
  const net = networkAt(rec.k);
  const avail = net && net.stats ? `, свободно в сети ${num(Math.max(0, net.stats.available - net.stats.generation), 1)} из ${num(net.stats.available, 1)} E/с` : ", сеть не подключена";
  if (!pw) return `§7Энергия: нет данных${avail}§r\n`;
  return `§7Энергия: ${pw.powered ? "§aдостаточно" : "§cне хватает"}§7, получено ${num(pw.received, 1)} E/с${avail}§r\n`;
}

// ---------------------------------------------------------------------------
// Главный экран
// ---------------------------------------------------------------------------

/** @param {Player} player @param {string} key */
export async function openAssemblerUI(player, key) {
  const rec = live(key);
  if (!rec) return;
  const td = tierDef(rec);
  const body = [rt(`§l${td.label}§r — сетка ${td.grid[0]}×${td.grid[1]}, скорость ×${td.speed}\n`), rt(`Состояние: ${statusText(rec.st)}\n`, energyLine(rec))];

  if (rec.upg) {
    const u = upgrade.currentUpgrade(rec);
    body.push(rt(`Модернизация до Ур-${rec.upg.to}: ${bar(rec.upg.p / u.time)} ${seconds(u.time - rec.upg.p)}\n`));
  }
  const sel = rec.sel ? ASSEMBLER_RECIPE_BY_ID.get(rec.sel) : undefined;
  if (sel) {
    const [w, h] = patternSize(sel);
    const q = rec.q < 0 ? "авто (непрерывно)" : rec.q > 0 ? `ещё ${rec.q}` : "остановлена";
    body.push(rt("Рецепт: ", itemName(sel.result[0]), ` ×${sel.result[1]}  §7(${w}×${h}, ${seconds(craftTime(sel, td))}, ${sel.power} E/с)§r\nОчередь: ${q}\n`));
    if (!rec.job && rec.q !== 0) {
      const miss = slots.missing(rec.store, requirements(sel));
      if (miss.length > 0) {
        body.push(rt("§eНе хватает:§r\n"));
        for (const [what, n] of miss) body.push(rt("  ", reqName(what), ` §c×${n}§r\n`));
      }
    }
  } else body.push(rt("Рецепт не выбран.\n"));
  if (rec.job) {
    const r = ASSEMBLER_RECIPE_BY_ID.get(rec.job.r);
    if (r) body.push(rt("Изготовление: ", itemName(r.result[0]), `\n${bar(rec.job.p / craftTime(r, td))} ${seconds(craftTime(r, td) - rec.job.p)}\n`));
  }
  body.push(rt(`Хранилище: ${rec.store.length}/${td.storageTypes} позиций, до ${td.storageCap} шт. каждой\n`));
  body.push(rt(`§lВыход§r (${rec.out.length}/${td.outSlots}, до ${OUT_CAP}):\n`), slotsText(rec.out));

  const { form, actions, add } = makeForm(machineName(rec.t), { rawtext: body });
  add("Рецепты", ICON.recipes, () => recipesUI(player, key));
  add("Забрать результат", ICON.take, () => giveSlots(player, key, "out"));
  add("Положить предмет из руки", ICON.insert, () => insertFromPlayer(player, key, true));
  add("Хранилище ингредиентов", ICON.storage, () => storageUI(player, key));
  if (rec.q !== 0 || rec.job) {
    add("Остановить изготовление", ICON.stop, () => {
      const cur = live(key);
      if (!cur) return;
      cur.q = 0;
      cancelJob(cur);
      saveNow(cur);
      tell(player, "§7Очередь остановлена, зарезервированные ингредиенты возвращены в хранилище.");
    });
  }
  add(rec.tier < MAX_TIER ? `Модернизация до Ур-${rec.tier + 1}` : "Модернизация (максимум)", ICON.upgrade, () => upgradeUI(player, key));
  add("Приоритет и сеть", ICON.network, () => openNetworkUI(player, key));
  add("Обновить", ICON.refresh, () => openAssemblerUI(player, key));
  await run(player, form, actions);
}

// ---------------------------------------------------------------------------
// Список рецептов
// ---------------------------------------------------------------------------

async function recipesUI(player, key) {
  const rec = live(key);
  if (!rec) return;
  const avail = availableRecipes(rec.tier);
  const next = rec.tier < MAX_TIER ? ASSEMBLER_RECIPES.filter((r) => r.minTier === rec.tier + 1) : [];
  const { form, actions, add } = makeForm(
    machineName(rec.t),
    rt(`Доступно рецептов: ${avail.length}. Рецепты меньших размеров остаются доступными на старших уровнях.\n§7Серые позиции откроются на Ур-${rec.tier + 1}.§r`),
  );
  for (const cat of Object.keys(CATEGORIES)) {
    for (const r of avail.filter((x) => x.category === cat)) {
      const [w, h] = patternSize(r);
      add(rt(itemName(r.result[0]), ` ×${r.result[1]}\n§8${CATEGORIES[cat]}, ${w}×${h}`), itemIcon(r.result[0]), () => recipeDetailUI(player, key, r.id));
    }
  }
  for (const r of next) {
    const [w, h] = patternSize(r);
    add(rt("§8", itemName(r.result[0]), `\n§8Ур-${r.minTier}, ${w}×${h}`), itemIcon(r.result[0]), () => recipeDetailUI(player, key, r.id));
  }
  await run(player, form, actions);
}

/** Текстовая схема сетки: занятые ячейки — буквы, пустые — точки; рамка показывает сетку уровня. */
function gridText(recipe, grid) {
  const lines = [];
  for (let y = 0; y < grid[1]; y++) {
    let row = "  ";
    for (let x = 0; x < grid[0]; x++) {
      const ch = recipe.pattern[y]?.[x];
      if (ch && ch !== "." && ch !== " ") row += `§b${ch}§r `;
      else if (y < recipe.pattern.length && x < patternSize(recipe)[0]) row += "§7·§r ";
      else row += "§8·§r ";
    }
    lines.push(row);
  }
  return lines.join("\n") + "\n";
}

async function recipeDetailUI(player, key, recipeId) {
  const rec = live(key);
  const recipe = ASSEMBLER_RECIPE_BY_ID.get(recipeId);
  if (!rec || !recipe) return;
  const td = tierDef(rec);
  const ok = recipeAvailable(recipe, rec.tier);
  const [w, h] = patternSize(recipe);
  const shownGrid = ok ? td.grid : ASSEMBLER_TIERS[recipe.minTier].grid;
  const body = [rt("Результат: ", itemName(recipe.result[0]), ` ×${recipe.result[1]}\n`)];
  body.push(rt(`Размер рецепта: ${w}×${h} (сетка Ур-${ok ? rec.tier : recipe.minTier}: ${shownGrid[0]}×${shownGrid[1]})\n`));
  body.push(rt(gridText(recipe, shownGrid)));
  body.push(rt("§lКомпоненты§r (есть в хранилище / нужно):\n"));
  const counts = new Map();
  for (const row of recipe.pattern) for (const ch of row) if (ch !== "." && ch !== " ") counts.set(ch, (counts.get(ch) ?? 0) + 1);
  for (const [ch, n] of counts) {
    const what = recipe.key[ch];
    const options = Array.isArray(what) ? what : [what];
    const have = options.reduce((s, id) => s + slots.countOf(rec.store, id), 0);
    body.push(rt(`  §b${ch}§r — `, reqName(what), ` ${have >= n ? "§a" : "§c"}${have}/${n}§r\n`));
  }
  const time = craftTime(recipe, td);
  body.push(rt(`Время: ${seconds(time)}. Энергия: ${recipe.power > 0 ? `${recipe.power} E/с, всего ${num(recipe.power * time)} E` : "не требуется"}\n`));
  if (!ok) body.push(rt(`§cТребуется сборщик Ур-${recipe.minTier}.§r\n`));

  const { form, actions, add } = makeForm(machineName(rec.t), { rawtext: body });
  if (ok) {
    for (const n of [1, 4, 16]) {
      add(`Изготовить ×${n}`, itemIcon(recipe.result[0]), () => setQueue(player, key, recipeId, n));
    }
    add("Авто-режим (непрерывно)", ICON.recipes, () => setQueue(player, key, recipeId, -1));
    add("Загрузить ингредиенты на ×1", ICON.insert, () => loadIngredients(player, key, recipeId, 1));
    add("Загрузить ингредиенты на ×4", ICON.insert, () => loadIngredients(player, key, recipeId, 4));
  }
  add("Назад к рецептам", ICON.recipes, () => recipesUI(player, key));
  await run(player, form, actions);
}

function setQueue(player, key, recipeId, n) {
  const rec = live(key);
  const recipe = ASSEMBLER_RECIPE_BY_ID.get(recipeId);
  if (!rec || !recipe || !recipeAvailable(recipe, rec.tier)) return;
  if (rec.upg) return tell(player, "§cИдёт модернизация — обычные рецепты недоступны.");
  if (rec.sel !== recipeId && rec.job) cancelJob(rec);
  rec.sel = recipeId;
  rec.q = n;
  saveNow(rec);
  tell(player, n < 0 ? "§aАвто-режим включён." : `§aВ очереди: ${n}.`);
}

/** Загрузка из инвентаря ровно недостающего количества на n изготовлений. */
function loadIngredients(player, key, recipeId, n) {
  const rec = live(key);
  const recipe = ASSEMBLER_RECIPE_BY_ID.get(recipeId);
  if (!rec || !recipe) return;
  // Сколько ещё нужно по каждой группе с учётом уже лежащего в хранилище.
  const need = requirements(recipe).map(([what, c]) => {
    const options = Array.isArray(what) ? what : [what];
    const have = options.reduce((s, id) => s + slots.countOf(rec.store, id), 0);
    return { options, left: Math.max(0, c * n - have) };
  });
  const moved = takeFromPlayer(
    player,
    (id) => {
      const cur = live(key);
      if (!cur) return 0;
      let want = 0;
      for (const g of need) if (g.options.includes(id)) want += g.left;
      return Math.min(want, storeRoom(cur, id));
    },
    (id, c) => {
      const cur = live(key);
      const added = cur ? storeAdd(cur, id, c) : 0;
      if (added < c) giveToPlayer(player, id, c - added);
      let left = added;
      for (const g of need) {
        if (left <= 0) break;
        if (!g.options.includes(id)) continue;
        const take = Math.min(g.left, left);
        g.left -= take;
        left -= take;
      }
    },
  );
  saveNow(rec);
  const still = need.reduce((s, g) => s + g.left, 0);
  tell(player, still > 0 ? `§eЗагружено ${moved}. Ещё не хватает ${still} ед. — см. список компонентов.` : `§aЗагружено ${moved}. Ингредиентов достаточно.`);
  return recipeDetailUI(player, key, recipeId);
}

// ---------------------------------------------------------------------------
// Хранилище
// ---------------------------------------------------------------------------

async function storageUI(player, key) {
  const rec = live(key);
  if (!rec) return;
  const td = tierDef(rec);
  const { form, actions, add } = makeForm(
    machineName(rec.t),
    rt(`Позиций: ${rec.store.length}/${td.storageTypes}. Нажмите на позицию, чтобы забрать её.\n§7Сборщик принимает только компоненты рецептов своего уровня и материалы модернизации.§r`),
  );
  add("Загрузить из инвентаря всё подходящее", ICON.insert, () => insertFromPlayer(player, key, false));
  for (const [id, n] of rec.store) {
    add(rt(itemName(id), ` ×${n}`), itemIcon(id), () => {
      const cur = live(key);
      if (!cur) return;
      const have = slots.countOf(cur.store, id);
      const given = giveToPlayer(player, id, have);
      slots.remove(cur.store, id, given);
      saveNow(cur);
      return storageUI(player, key);
    });
  }
  add("Назад", ICON.refresh, () => openAssemblerUI(player, key));
  await run(player, form, actions);
}

// ---------------------------------------------------------------------------
// Модернизация
// ---------------------------------------------------------------------------

async function upgradeUI(player, key) {
  const rec = live(key);
  if (!rec) return;
  const up = upgrade.nextUpgrade(rec.tier);
  if (!up && !rec.upg) {
    const { form, actions, add } = makeForm(machineName(rec.t), "Сборщик модернизирован до максимального уровня Ур-5 (сетка 9×9).");
    add("Назад", ICON.refresh, () => openAssemblerUI(player, key));
    return run(player, form, actions);
  }
  const target = rec.upg ? rec.upg.to : rec.tier + 1;
  const spec = upgrade.nextUpgrade(target - 1);
  if (!spec) return;
  const ng = ASSEMBLER_TIERS[target].grid;
  const body = [rt(`Ур-${target - 1} → §lУр-${target}§r: сетка ${ng[0]}×${ng[1]}, новые рецепты, хранилище ${ASSEMBLER_TIERS[target].storageTypes} позиций.\n`)];
  body.push(rt(`Энергия: ${spec.power} E/с в течение ${seconds(spec.time)} (всего ${num(spec.power * spec.time)} E)\n`));
  body.push(rt("§7Во время модернизации обычные рецепты не выполняются. Содержимое сборщика сохраняется.§r\n"));
  if (rec.upg) {
    body.push(rt(`Ход: ${bar(rec.upg.p / spec.time)} ${seconds(spec.time - rec.upg.p)}\nСостояние: ${statusText(rec.st)}\n`));
  } else {
    body.push(rt("§lТребуется§r (в хранилище / нужно):\n"));
    for (const [id, n] of spec.items) {
      const have = slots.countOf(rec.store, id);
      body.push(rt("  ", itemName(id), ` ${have >= n ? "§a" : "§c"}${have}/${n}§r\n`));
    }
  }
  const { form, actions, add } = makeForm(machineName(rec.t), { rawtext: body });
  if (!rec.upg) {
    add("Загрузить материалы из инвентаря", ICON.insert, () => {
      const cur = live(key);
      if (!cur) return;
      const need = new Map(spec.items.map(([id, n]) => [id, Math.max(0, n - slots.countOf(cur.store, id))]));
      const moved = takeFromPlayer(
        player,
        (id) => Math.min(need.get(id) ?? 0, storeRoom(cur, id)),
        (id, c) => {
          const added = storeAdd(cur, id, c);
          if (added < c) giveToPlayer(player, id, c - added);
          need.set(id, Math.max(0, (need.get(id) ?? 0) - added));
        },
      );
      saveNow(cur);
      tell(player, `§7Загружено: ${moved}`);
      return upgradeUI(player, key);
    });
    add("Начать модернизацию", ICON.upgrade, () => {
      const cur = live(key);
      if (!cur) return;
      const err = upgrade.start(cur);
      saveNow(cur);
      tell(player, err ? `§c${err}` : `§aМодернизация до Ур-${cur.upg.to} запущена.`);
    });
  } else {
    add("Отменить модернизацию", ICON.stop, () => {
      const cur = live(key);
      if (!cur) return;
      upgrade.cancel(cur);
      saveNow(cur);
      tell(player, "§7Модернизация отменена, материалы возвращены в хранилище.");
    });
  }
  add("Назад", ICON.refresh, () => openAssemblerUI(player, key));
  await run(player, form, actions);
}
