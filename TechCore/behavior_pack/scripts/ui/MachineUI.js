// Интерфейсы машин (кроме Ультимативного сборщика — см. AssemblerUI.js).
// Единый стиль: заголовок — название машины, тело — состояние, энергия, прогресс, слоты;
// крупные кнопки действий (удобно на сенсорном экране).
import { ActionFormData } from "@minecraft/server-ui";
import { BLOCKS } from "../data/machines.js";
import { MACHINE_RECIPES, findMachineRecipe } from "../data/recipes.js";
import { COAL_GENERATOR, LIQUID_GENERATORS, WIND_TURBINES, BATTERIES } from "../data/generators.js";
import { FUEL_TANK } from "../data/wires.js";
import * as slots from "../logic/slots.js";
import { takeFromPlayer, giveToPlayer, heldItem } from "../core/inventory.js";
import { rt, itemName, reqName, statusText, bar, num, seconds, fluidName, PRIORITY_RU } from "../core/text.js";
import { DIRECTION_RU } from "../core/positions.js";
import { handlerFor } from "../systems/kinds.js";
import { saveNow, markDirty } from "../systems/Registry.js";
import { pourHeldCanister, fillHeldCanister } from "../systems/FuelSystem.js";
import { rotateBelt } from "../systems/TransportSystem.js";
import { live, showForm, itemIcon, slotsText, tell, machineName } from "./common.js";
import { openAssemblerUI } from "./AssemblerUI.js";
import { openNetworkUI } from "./NetworkUI.js";

/** @typedef {import("@minecraft/server").Player} Player */

const ICON = {
  insert: "textures/techcore/icons/ui_insert",
  take: "textures/techcore/icons/ui_take",
  recipes: "textures/techcore/icons/ui_recipes",
  network: "textures/techcore/icons/ui_network",
  refresh: "textures/techcore/icons/ui_refresh",
  rotate: "textures/techcore/icons/ui_rotate",
  power: "textures/techcore/icons/ui_power",
};

/** Открывает интерфейс машины по ключу позиции. @param {Player} player @param {string} key */
export function openMachineUI(player, key) {
  const rec = live(key);
  if (!rec) return;
  const kind = BLOCKS[rec.t].kind;
  switch (kind) {
    case "assembler":
      return openAssemblerUI(player, key);
    case "processor":
    case "refinery":
      return processorUI(player, key);
    case "drill":
      return drillUI(player, key);
    case "coal_generator":
    case "liquid_generator":
    case "wind":
      return generatorUI(player, key);
    case "battery":
      return batteryUI(player, key);
    case "tank":
      return tankUI(player, key);
    case "buffer":
      return bufferUI(player, key);
    case "conveyor":
    case "filter":
    case "splitter":
      return beltUI(player, key);
  }
}

// ---------------------------------------------------------------------------
// Общие действия
// ---------------------------------------------------------------------------

/** Положить предметы через accept/insert обработчика. */
export function insertFromPlayer(player, key, onlySelected) {
  const rec = live(key);
  if (!rec) return 0;
  const h = handlerFor(rec.t);
  if (!h || !h.accept || !h.insert) return 0;
  const moved = takeFromPlayer(
    player,
    (id) => (live(key) ? /** @type {any} */ (h).accept(rec, id) : 0),
    (id, n) => {
      const added = /** @type {any} */ (h).insert(rec, id, n);
      // accept() уже подтвердил место, поэтому added === n; страховка от расхождения:
      if (added < n) giveToPlayer(player, id, n - added);
    },
    { onlySelected },
  );
  if (moved > 0) saveNow(rec);
  tell(player, moved > 0 ? `§aЗагружено предметов: ${moved}` : "§eНет подходящих предметов или нет места.");
  return moved;
}

/** Выдать игроку содержимое поля слотов записи. */
export function giveSlots(player, key, field) {
  const rec = live(key);
  if (!rec) return;
  const list = rec[field];
  if (!list || list.length === 0) {
    tell(player, "§7Пусто.");
    return;
  }
  let total = 0;
  let left = 0;
  for (const [id, n] of slots.clone(list)) {
    const given = giveToPlayer(player, id, n);
    slots.remove(list, id, given);
    total += given;
    left += n - given;
  }
  markDirty(rec);
  saveNow(rec);
  tell(player, left > 0 ? `§eПолучено ${total}, не поместилось ${left} — остаток в машине.` : `§aПолучено предметов: ${total}`);
}

function energyLine(rec) {
  const pw = rec._power;
  const pr = PRIORITY_RU[rec.pr ?? 2];
  if (!pw) return `§7Энергия: нет данных  Приоритет: ${pr}§r\n`;
  const loss = rec._pathLoss ? `, потери линии ${(rec._pathLoss * 100).toFixed(1)}%` : "";
  return `§7Энергия: ${pw.powered ? "§aдостаточно" : "§cне хватает"}§7 (получено ${num(pw.received, 1)} E/с${loss})  Приоритет: ${pr}§r\n`;
}

async function runActions(player, form, actions) {
  const res = await showForm(player, form);
  if (!res || res.selection === undefined) return;
  const fn = actions[res.selection];
  if (fn) await fn();
}

// ---------------------------------------------------------------------------
// Обрабатывающие машины и переработчик топлива
// ---------------------------------------------------------------------------

function recipeLabel(recipe, def) {
  const parts = [];
  recipe.in.forEach(([what, n], i) => {
    if (i > 0) parts.push(" + ");
    parts.push(`${n} `, reqName(what));
  });
  parts.push(" → ");
  if (recipe.fluid) parts.push(`${recipe.fluid.a} мБ ${fluidName(recipe.fluid.f)}`);
  else
    recipe.out.forEach(([id, n], i) => {
      if (i > 0) parts.push(" + ");
      parts.push(`${n} `, itemName(id));
    });
  parts.push(`\n§8${recipe.time} с, ${recipe.power ?? def.power} E/с`);
  return rt(...parts);
}

async function processorUI(player, key) {
  const rec = live(key);
  if (!rec) return;
  const def = BLOCKS[rec.t];
  const recipe = rec.r ? findMachineRecipe(rec.t, rec.r) : undefined;
  const body = [rt(`Состояние: ${statusText(rec.st)}\n`), rt(energyLine(rec))];
  if (recipe) body.push(rt("Процесс: ", recipeLabel(recipe, def), `\n${bar(rec.p / recipe.time)} ${seconds(recipe.time - rec.p)}\n`));
  body.push(rt(`Режим рецепта: ${rec.lock ? "фиксированный" : "автовыбор"}\n`));
  body.push(rt(`§lВход§r (${rec.in.length}/${def.inSlots}):\n`), slotsText(rec.in));
  if (def.kind === "refinery") body.push(rt(`§lВыходной бак§r: ${fluidName(rec.fl.f)} ${Math.floor(rec.fl.a)} / ${def.tank} мБ\n`));
  else body.push(rt(`§lВыход§r (${rec.out.length}/${def.outSlots}):\n`), slotsText(rec.out));

  const form = new ActionFormData().title(machineName(rec.t)).body({ rawtext: body });
  const actions = [];
  const add = (label, icon, fn) => {
    form.button(label, icon);
    actions.push(fn);
  };
  add("Положить предмет из руки", ICON.insert, () => insertFromPlayer(player, key, true));
  add("Загрузить подходящее из инвентаря", ICON.insert, () => insertFromPlayer(player, key, false));
  if (def.kind === "refinery") add("Наполнить канистру (в руке)", "textures/techcore/items/canister", () => tell(player, fillHeldCanister(player, rec, "fl")));
  else add("Забрать результат", ICON.take, () => giveSlots(player, key, "out"));
  add("Извлечь входные материалы", ICON.take, () => giveSlots(player, key, "in"));
  add("Рецепты и режим", ICON.recipes, () => recipeModeUI(player, key));
  add("Приоритет и сеть", ICON.network, () => openNetworkUI(player, key));
  add("Обновить", ICON.refresh, () => processorUI(player, key));
  await runActions(player, form, actions);
}

async function recipeModeUI(player, key) {
  const rec = live(key);
  if (!rec) return;
  const def = BLOCKS[rec.t];
  const list = MACHINE_RECIPES[rec.t] ?? [];
  const form = new ActionFormData()
    .title(machineName(rec.t))
    .body("Автовыбор берёт первый рецепт, для которого хватает материалов. Фиксированный режим выполняет только выбранный рецепт.");
  form.button(rec.lock ? "Автовыбор" : "§2Автовыбор (текущий)", ICON.recipes);
  for (const r of list) {
    const out = r.out ? r.out[0][0] : undefined;
    form.button(rt(rec.lock === r.id ? "§2" : "", recipeLabel(r, def)), itemIcon(out) ?? "textures/techcore/items/canister_" + (r.fluid?.f ?? "diesel"));
  }
  const res = await showForm(player, form);
  if (!res || res.selection === undefined) return;
  const cur = live(key);
  if (!cur) return;
  cur.lock = res.selection === 0 ? null : list[res.selection - 1].id;
  saveNow(cur);
  return processorUI(player, key);
}

// ---------------------------------------------------------------------------
// Буровая установка
// ---------------------------------------------------------------------------

async function drillUI(player, key) {
  const rec = live(key);
  if (!rec) return;
  const def = BLOCKS[rec.t];
  const body = [
    rt(`Состояние: ${statusText(rec.st)}\n`, energyLine(rec)),
    rt(`Текущая глубина: Y=${rec.dy}. Добыто блоков: ${rec.mined ?? 0}. Пропущено чужих/искусственных: ${rec.skipped ?? 0}.\n`),
    rt("§7Бур добывает только природные блоки колонны 3×3 под собой; постройки и контейнеры пропускаются.§r\n"),
    rt(`§lДобыча§r (${rec.out.length}/${def.outSlots}):\n`),
    slotsText(rec.out),
  ];
  const form = new ActionFormData().title(machineName(rec.t)).body({ rawtext: body });
  const actions = [];
  const add = (label, icon, fn) => {
    form.button(label, icon);
    actions.push(fn);
  };
  add("Забрать добычу", ICON.take, () => giveSlots(player, key, "out"));
  add(rec.on ? "Остановить бурение" : "Запустить бурение", ICON.power, () => {
    const cur = live(key);
    if (!cur) return;
    cur.on = !cur.on;
    saveNow(cur);
  });
  add("Приоритет и сеть", ICON.network, () => openNetworkUI(player, key));
  add("Обновить", ICON.refresh, () => drillUI(player, key));
  await runActions(player, form, actions);
}

// ---------------------------------------------------------------------------
// Генераторы
// ---------------------------------------------------------------------------

async function generatorUI(player, key) {
  const rec = live(key);
  if (!rec) return;
  const def = BLOCKS[rec.t];
  const h = handlerFor(rec.t);
  const info = h && h.info ? h.info(rec) : { lines: [] };
  const body = [rt(`Состояние: ${statusText(rec.st)}\n`)];
  let rated = 0;
  if (def.kind === "coal_generator") rated = COAL_GENERATOR.rated;
  else if (def.kind === "liquid_generator") rated = LIQUID_GENERATORS[rec.t].rated;
  else rated = WIND_TURBINES[rec.t].rated;
  const out = rec._gen?.output ?? 0;
  body.push(rt(`Выработка: §a${num(out, 1)}§r / ${rated} E/с (номинал)\n${bar(out / rated)}\n`));
  for (const line of info.lines) body.push(rt(`${line}\n`));
  if (def.kind === "coal_generator") {
    body.push(rt("§lТопливо в бункере§r:\n"), slotsText(rec.fuel));
    body.push(rt("§7Подсказка: вода, лёд или снег по соседству ускоряют охлаждение. При перегреве мощность снижается, поломок нет.§r\n"));
  }
  if (def.kind === "liquid_generator") body.push(rt("§7Топливо подаётся трубами из резервуара/переработчика или вручную канистрой.§r\n"));
  if (def.kind === "wind") body.push(rt("§7Выработка зависит от высоты, погоды и свободного пространства вокруг ротора (5×5).§r\n"));

  const form = new ActionFormData().title(machineName(rec.t)).body({ rawtext: body });
  const actions = [];
  const add = (label, icon, fn) => {
    form.button(label, icon);
    actions.push(fn);
  };
  if (def.kind === "coal_generator") {
    add("Добавить топливо из руки", ICON.insert, () => insertFromPlayer(player, key, true));
    add("Загрузить всё топливо из инвентаря", ICON.insert, () => insertFromPlayer(player, key, false));
    add("Извлечь топливо", ICON.take, () => giveSlots(player, key, "fuel"));
  }
  if (def.kind === "liquid_generator") {
    const spec = LIQUID_GENERATORS[rec.t];
    add("Залить канистру из руки", "textures/techcore/items/canister_" + spec.fluid, () => {
      const cur = live(key);
      if (cur) tell(player, pourHeldCanister(player, cur, "tank", spec.tank, spec.fluid));
    });
  }
  add("Сеть", ICON.network, () => openNetworkUI(player, key));
  add("Обновить", ICON.refresh, () => generatorUI(player, key));
  await runActions(player, form, actions);
}

async function batteryUI(player, key) {
  const rec = live(key);
  if (!rec) return;
  const spec = BATTERIES[rec.t];
  const rate = rec._rate ?? 0;
  const body = rt(
    `Состояние: ${statusText(rec.st)}\n`,
    `Заряд: ${num(rec.ch)} / ${num(spec.capacity)} E\n${bar(rec.ch / spec.capacity)}\n`,
    `Текущий поток: ${rate >= 0 ? "§a+" : "§c"}${num(rate, 1)}§r E/с (предел ${spec.rate} E/с)\n`,
    "§7Аккумулятор заряжается излишком генерации и отдаёт энергию при дефиците.§r",
  );
  const form = new ActionFormData().title(machineName(rec.t)).body(body);
  const actions = [];
  form.button("Сеть", ICON.network);
  actions.push(() => openNetworkUI(player, key));
  form.button("Обновить", ICON.refresh);
  actions.push(() => batteryUI(player, key));
  await runActions(player, form, actions);
}

// ---------------------------------------------------------------------------
// Резервуар, буфер, транспорт
// ---------------------------------------------------------------------------

async function tankUI(player, key) {
  const rec = live(key);
  if (!rec) return;
  const body = rt(
    `Содержимое: ${fluidName(rec.tank.f)}\n`,
    `${Math.floor(rec.tank.a)} / ${FUEL_TANK.capacity} мБ\n${bar(rec.tank.a / FUEL_TANK.capacity)}\n`,
    "§7Резервуар принимает излишек переработчика по трубам и отдаёт топливо генераторам.§r",
  );
  const form = new ActionFormData().title(machineName(rec.t)).body(body);
  const actions = [];
  form.button("Наполнить канистру (в руке)", "textures/techcore/items/canister");
  actions.push(() => {
    const cur = live(key);
    if (cur) tell(player, fillHeldCanister(player, cur, "tank"));
  });
  form.button("Слить канистру (в руке)", "textures/techcore/items/canister_diesel");
  actions.push(() => {
    const cur = live(key);
    if (cur) tell(player, pourHeldCanister(player, cur, "tank", FUEL_TANK.capacity, null));
  });
  form.button("Обновить", ICON.refresh);
  actions.push(() => tankUI(player, key));
  await runActions(player, form, actions);
}

async function bufferUI(player, key) {
  const rec = live(key);
  if (!rec) return;
  const def = BLOCKS[rec.t];
  const form = new ActionFormData()
    .title(machineName(rec.t))
    .body(rt(`Занято позиций: ${rec.store.length}/${def.slots}, всего ${slots.total(rec.store)} / ${def.slots * def.slotCap}\n`, "§7Нажмите на позицию, чтобы забрать её целиком.§r"));
  const actions = [];
  form.button("Положить предмет из руки", ICON.insert);
  actions.push(() => insertFromPlayer(player, key, true));
  for (const [id, n] of rec.store) {
    form.button(rt(itemName(id), ` ×${n}`), itemIcon(id));
    actions.push(() => {
      const cur = live(key);
      if (!cur) return;
      const have = slots.countOf(cur.store, id);
      const given = giveToPlayer(player, id, have);
      slots.remove(cur.store, id, given);
      saveNow(cur);
      if (given < have) tell(player, "§eНе всё поместилось в инвентарь.");
    });
  }
  await runActions(player, form, actions);
}

async function beltUI(player, key) {
  const rec = live(key);
  if (!rec) return;
  const kind = BLOCKS[rec.t].kind;
  const body = [rt(`Направление: ${DIRECTION_RU[rec.dir] ?? rec.dir}\n`)];
  body.push(rec.cargo ? rt("Груз: ", itemName(rec.cargo[0]), ` ×${rec.cargo[1]}\n`) : rt("Груз: нет\n"));
  if (kind === "filter") {
    body.push(rt(`Режим: ${rec.mode === "black" ? "чёрный список (пропускает всё, кроме списка)" : "белый список (пропускает только список)"}\n`));
    body.push(rt("Подходящие предметы идут вперёд, остальные — вправо.\nСписок:\n"), slotsText(rec.list.map((id) => [id, 1]), "  пусто"));
  }
  if (kind === "splitter") body.push(rt("Распределяет поток по очереди: влево, вперёд, вправо (только на свободные выходы).\n"));
  body.push(rt("§7Гаечный ключ: нажмите им на ленту, чтобы повернуть её.§r"));
  const form = new ActionFormData().title(machineName(rec.t)).body({ rawtext: body });
  const actions = [];
  const add = (label, icon, fn) => {
    form.button(label, icon);
    actions.push(fn);
  };
  add("Повернуть по часовой", ICON.rotate, () => {
    const cur = live(key);
    if (cur) rotateBelt(cur);
  });
  add("Забрать груз", ICON.take, () => {
    const cur = live(key);
    if (!cur || !cur.cargo) return;
    const [id, n] = cur.cargo;
    const given = giveToPlayer(player, id, n);
    cur.cargo = given >= n ? null : [id, n - given];
    saveNow(cur);
  });
  if (kind === "filter") {
    add("Добавить в фильтр предмет из руки", ICON.insert, () => {
      const cur = live(key);
      const held = heldItem(player);
      if (!cur || !held) return tell(player, "§eВозьмите предмет в руку.");
      if (cur.list.includes(held.typeId)) return tell(player, "§7Уже в списке.");
      if (cur.list.length >= 9) return tell(player, "§cВ фильтре не больше 9 позиций.");
      cur.list.push(held.typeId);
      saveNow(cur);
    });
    add("Очистить фильтр", ICON.take, () => {
      const cur = live(key);
      if (!cur) return;
      cur.list = [];
      saveNow(cur);
    });
    add(rec.mode === "black" ? "Режим: сделать белым списком" : "Режим: сделать чёрным списком", ICON.recipes, () => {
      const cur = live(key);
      if (!cur) return;
      cur.mode = cur.mode === "black" ? "white" : "black";
      saveNow(cur);
    });
  }
  await runActions(player, form, actions);
}
