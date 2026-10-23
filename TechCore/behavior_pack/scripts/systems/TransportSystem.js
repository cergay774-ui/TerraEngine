// Транспорт предметов: конвейеры, фильтры, разветвители, буферные контейнеры.
// Предметы на ленте — это данные записи (cargo), а не сущности. Каждая партия за один шаг
// перемещается не более чем на один блок (метка mv), перенос выполняется атомарно:
// сначала приёмник подтверждает, сколько примет, затем количество списывается у источника.
import { system, world } from "@minecraft/server";
import { BLOCKS } from "../data/machines.js";
import { CONFIG } from "../data/config.js";
import * as slots from "../logic/slots.js";
import { CARDINAL, opposite, rotateCW, rotateCCW, posKey } from "../core/positions.js";
import { blockAt, setStates, stateOf } from "../core/blocks.js";
import { isPlainStack } from "../core/inventory.js";
import { log } from "../core/log.js";
import { records, markDirty } from "./Registry.js";
import { registerKind, handlerFor } from "./kinds.js";
import { settings } from "./SettingsSystem.js";
import { ItemStack } from "@minecraft/server";

const BELT_KINDS = new Set(["conveyor", "filter", "splitter"]);

// Ванильные контейнеры, с которыми работает транспорт. Печи и варочные стойки исключены,
// т.к. у них есть слоты топлива/ингредиентов, которые нельзя опустошать вслепую.
const VANILLA_CONTAINERS = new Set([
  "minecraft:chest",
  "minecraft:trapped_chest",
  "minecraft:barrel",
  "minecraft:hopper",
  "minecraft:undyed_shulker_box",
  ...["white", "orange", "magenta", "light_blue", "yellow", "lime", "pink", "gray", "light_gray", "cyan", "purple", "blue", "brown", "green", "red", "black"].map(
    (c) => `minecraft:${c}_shulker_box`,
  ),
]);

function neighborKey(rec, dir) {
  const d = CARDINAL[dir];
  return posKey(rec._dim, rec.x + d.dx, rec.y, rec.z + d.dz);
}

function neighborPos(rec, dir) {
  const d = CARDINAL[dir];
  return { x: rec.x + d.dx, y: rec.y, z: rec.z + d.dz };
}

/** Контейнер ванильного блока, если он поддерживается. */
function vanillaContainer(rec, dir) {
  const p = neighborPos(rec, dir);
  const b = blockAt(rec._dim, p.x, p.y, p.z);
  if (!b || !VANILLA_CONTAINERS.has(b.typeId)) return undefined;
  try {
    return b.getComponent("minecraft:inventory")?.container;
  } catch {
    return undefined;
  }
}

/**
 * Передача партии в соседний блок по направлению dir. Возвращает принятое количество.
 * @param {any} rec @param {string} dir @param {string} id @param {number} n @param {number} tick
 */
function pushTo(rec, dir, id, n, tick) {
  const key = neighborKey(rec, dir);
  const target = records.get(key);
  if (target) {
    if (!target._loaded) return 0;
    const kind = BLOCKS[target.t].kind;
    if (BELT_KINDS.has(kind)) {
      if (target.cargo) return 0;
      // Лента, направленная прямо навстречу, не принимает (исключает "пинг-понг").
      if (target.dir === opposite(dir)) return 0;
      target.cargo = [id, n];
      target.mv = tick;
      markDirty(target);
      return n;
    }
    const h = handlerFor(target.t);
    if (!h || !h.accept || !h.insert) return 0;
    const room = Math.min(n, h.accept(target, id));
    if (room <= 0) return 0;
    return h.insert(target, id, room);
  }
  const cont = vanillaContainer(rec, dir);
  if (!cont) return 0;
  try {
    const left = cont.addItem(new ItemStack(id, n));
    return n - (left ? left.amount : 0);
  } catch {
    return 0;
  }
}

/** Забор партии из блока позади ленты. @returns {[string, number] | null} */
function pullFrom(rec, dir, max) {
  const key = neighborKey(rec, dir);
  const src = records.get(key);
  if (src) {
    if (!src._loaded) return null;
    if (BELT_KINDS.has(BLOCKS[src.t].kind)) return null; // ленты передают сами
    const h = handlerFor(src.t);
    if (!h || !h.extract) return null;
    return h.extract(src, max);
  }
  const cont = vanillaContainer(rec, dir);
  if (!cont) return null;
  for (let i = 0; i < cont.size; i++) {
    const s = cont.getItem(i);
    if (!s || !isPlainStack(s)) continue;
    const take = Math.min(max, s.amount);
    const id = s.typeId;
    if (take >= s.amount) cont.setItem(i, undefined);
    else {
      s.amount -= take;
      cont.setItem(i, s);
    }
    return [id, take];
  }
  return null;
}

function filterMatches(rec, id) {
  const inList = rec.list.includes(id);
  return rec.mode === "black" ? !inList : inList;
}

function beltStep(rec, tick) {
  const kind = BLOCKS[rec.t].kind;
  // Забор, если лента пуста.
  if (!rec.cargo) {
    const got = pullFrom(rec, opposite(rec.dir), CONFIG.conveyorPacketSize);
    if (got) {
      rec.cargo = got;
      rec.mv = tick;
      markDirty(rec);
    }
    return;
  }
  if (rec.mv === tick) return;
  const [id, n] = rec.cargo;
  /** @type {string[]} */
  let order;
  if (kind === "filter") order = filterMatches(rec, id) ? [rec.dir] : [rotateCW(rec.dir)];
  else if (kind === "splitter") {
    const outs = [rotateCCW(rec.dir), rec.dir, rotateCW(rec.dir)];
    const start = (rec.rr ?? 0) % 3;
    order = [outs[start], outs[(start + 1) % 3], outs[(start + 2) % 3]];
  } else order = [rec.dir];
  for (let i = 0; i < order.length; i++) {
    const accepted = pushTo(rec, order[i], id, n, tick);
    if (accepted <= 0) continue;
    rec.thr = (rec.thr ?? 0) + accepted;
    if (accepted >= n) rec.cargo = null;
    else rec.cargo = [id, n - accepted];
    if (kind === "splitter") rec.rr = ((rec.rr ?? 0) + i + 1) % 3;
    markDirty(rec);
    return;
  }
}

function nearPlayer(rec, radius) {
  const r2 = radius * radius;
  for (const p of world.getPlayers()) {
    if (p.dimension.id !== rec._dim) continue;
    const dx = p.location.x - rec.x;
    const dz = p.location.z - rec.z;
    const dy = p.location.y - rec.y;
    if (dx * dx + dy * dy + dz * dz <= r2) return true;
  }
  return false;
}

function syncCargo(rec) {
  const want = !!rec.cargo && settings.cargo && nearPlayer(rec, CONFIG.conveyorCargoRadius);
  if (rec._cargoVis === want) return;
  const b = blockAt(rec._dim, rec.x, rec.y, rec.z);
  if (!b || b.typeId !== rec.t) return;
  try {
    setStates(b, { "techcore:loaded": want });
    rec._cargoVis = want;
  } catch {
    // блок заменён — проверка целостности в основном цикле
  }
}

let transportTick = 0;

function transportLoop() {
  transportTick++;
  const tick = system.currentTick;
  for (const rec of records.values()) {
    if (!rec._loaded) continue;
    const kind = BLOCKS[rec.t]?.kind;
    if (!BELT_KINDS.has(kind)) continue;
    try {
      beltStep(rec, tick);
      syncCargo(rec);
    } catch (e) {
      log.debug(`Транспорт ${rec.k}: ${e}`);
    }
  }
  // Пропускная способность: скользящее окно ~1 минута.
  if (transportTick % Math.round(1200 / CONFIG.transportTickInterval) === 0) {
    for (const rec of records.values()) {
      if (rec.thr !== undefined) {
        rec._thrMin = rec.thr;
        rec.thr = 0;
      }
    }
  }
}

export function startTransportLoop() {
  system.runInterval(() => {
    try {
      transportLoop();
    } catch (e) {
      log.warn(`Сбой транспорта: ${e}`);
    }
  }, CONFIG.transportTickInterval);
}

/** Направление ленты из состояния блока. */
export function readDirection(block) {
  const d = stateOf(block.permutation, "minecraft:cardinal_direction");
  return typeof d === "string" && CARDINAL[d] ? d : "south";
}

/** Поворот ленты по часовой стрелке (гаечный ключ). */
export function rotateBelt(rec) {
  rec.dir = rotateCW(rec.dir);
  const b = blockAt(rec._dim, rec.x, rec.y, rec.z);
  if (b) setStates(b, { "minecraft:cardinal_direction": rec.dir });
  markDirty(rec);
}

// ---------------------------------------------------------------------------
// Обработчики видов
// ---------------------------------------------------------------------------

const beltHandler = {
  init(rec) {
    rec.cargo ??= null;
    rec.dir ??= "south";
    if (BLOCKS[rec.t].kind === "filter") {
      rec.list ??= [];
      rec.mode ??= "white";
    }
    if (BLOCKS[rec.t].kind === "splitter") rec.rr ??= 0;
  },
  sanitize(rec) {
    if (rec.cargo) {
      const s = slots.sanitize([rec.cargo]);
      rec.cargo = s.length ? s[0] : null;
    }
    if (!CARDINAL[rec.dir]) rec.dir = "south";
    if (rec.list) rec.list = rec.list.filter((x) => typeof x === "string").slice(0, 9);
  },
  contents(rec) {
    return rec.cargo ? [rec.cargo] : [];
  },
  info(rec) {
    const lines = [`Направление: ${rec.dir}`, `Пропускная способность: ${rec._thrMin ?? 0} предм./мин`];
    if (rec.list) lines.push(`Фильтр (${rec.mode === "black" ? "чёрный" : "белый"} список): ${rec.list.length} поз.`);
    return { lines };
  },
};

registerKind("conveyor", beltHandler);
registerKind("filter", beltHandler);
registerKind("splitter", beltHandler);

registerKind("buffer", {
  init(rec) {
    rec.store ??= [];
  },
  sanitize(rec) {
    rec.store = slots.sanitize(rec.store);
  },
  contents(rec) {
    return rec.store;
  },
  accept(rec, id) {
    const def = BLOCKS[rec.t];
    return slots.acceptable(rec.store, id, def.slots, def.slotCap);
  },
  insert(rec, id, n) {
    const def = BLOCKS[rec.t];
    const a = slots.add(rec.store, id, n, def.slots, def.slotCap);
    if (a > 0) markDirty(rec);
    return a;
  },
  extract(rec, max) {
    if (rec.store.length === 0) return null;
    const id = rec.store[0][0];
    const n = slots.remove(rec.store, id, max);
    markDirty(rec);
    return n > 0 ? [id, n] : null;
  },
  info(rec) {
    const def = BLOCKS[rec.t];
    return { lines: [`Заполнено: ${slots.total(rec.store)} / ${def.slots * def.slotCap}, позиций ${rec.store.length}/${def.slots}`] };
  },
});
