// Упрощённая имитация @minecraft/server для интеграционных тестов в Node.
// Реализует только то, что использует TechCore. Это НЕ замена проверки в игре:
// мок проверяет логику скриптов (энергия, крафт, сохранение, предметы), а не движок.

export const EquipmentSlot = { Head: "Head", Chest: "Chest", Legs: "Legs", Feet: "Feet", Mainhand: "Mainhand", Offhand: "Offhand" };
export const WeatherType = { Clear: "Clear", Rain: "Rain", Thunder: "Thunder" };
export const PlayerPermissionLevel = { Visitor: 0, Member: 1, Operator: 2, Custom: 3 };
export const GameMode = { survival: "survival", creative: "creative" };

const STACK1 = new Set(["techcore:engineer_goggles", "techcore:wrench", "techcore:canister_diesel", "techcore:canister_gasoline", "techcore:canister_biofuel", "minecraft:diamond_pickaxe", "minecraft:bucket"]);

export class ItemStack {
  constructor(type, amount = 1) {
    if (typeof type !== "string" || !type.includes(":")) throw new Error(`Invalid item ${type}`);
    this.typeId = type;
    this.amount = amount;
    this.nameTag = undefined;
    this._lore = [];
  }
  get maxAmount() {
    return STACK1.has(this.typeId) || this.typeId.startsWith("techcore:assembler_packed") ? 1 : this.typeId.startsWith("techcore:canister") ? 16 : 64;
  }
  get localizationKey() {
    return this.typeId.startsWith("techcore:") ? `item.${this.typeId}` : `item.${this.typeId.split(":")[1]}.name`;
  }
  getLore() {
    return this._lore;
  }
  getDynamicPropertyIds() {
    return [];
  }
  getComponent() {
    return undefined;
  }
  clone() {
    const s = new ItemStack(this.typeId, this.amount);
    s.nameTag = this.nameTag;
    return s;
  }
}

export class Container {
  constructor(size) {
    this.size = size;
    this.slots = new Array(size).fill(undefined);
  }
  getItem(i) {
    return this.slots[i] ? this.slots[i].clone() : undefined;
  }
  setItem(i, s) {
    this.slots[i] = s && s.amount > 0 ? s.clone() : undefined;
  }
  addItem(stack) {
    let left = stack.amount;
    for (let i = 0; i < this.size && left > 0; i++) {
      const s = this.slots[i];
      if (s && s.typeId === stack.typeId && s.amount < s.maxAmount) {
        const t = Math.min(left, s.maxAmount - s.amount);
        s.amount += t;
        left -= t;
      }
    }
    for (let i = 0; i < this.size && left > 0; i++) {
      if (!this.slots[i]) {
        const t = Math.min(left, stack.maxAmount);
        this.slots[i] = new ItemStack(stack.typeId, t);
        left -= t;
      }
    }
    return left > 0 ? new ItemStack(stack.typeId, left) : undefined;
  }
  count(id) {
    return this.slots.reduce((n, s) => n + (s && s.typeId === id ? s.amount : 0), 0);
  }
}

export class BlockPermutation {
  constructor(typeId, states = {}) {
    this.type = { id: typeId };
    this._states = { ...states };
  }
  getAllStates() {
    return { ...this._states };
  }
  getState(n) {
    return this._states[n];
  }
  withState(n, v) {
    if (!(n in this._states)) throw new Error(`State ${n} not on ${this.type.id}`);
    return new BlockPermutation(this.type.id, { ...this._states, [n]: v });
  }
}

// Описание состояний блоков берётся из сгенерированных JSON (как в движке).
export const blockStateDefaults = new Map();

function defaultStates(typeId) {
  return { ...(blockStateDefaults.get(typeId) ?? {}) };
}

export class Block {
  constructor(dim, x, y, z) {
    this.dimension = dim;
    this.x = x;
    this.y = y;
    this.z = z;
    this.location = { x, y, z };
  }
  get _cell() {
    return this.dimension._cells.get(`${this.x},${this.y},${this.z}`) ?? { perm: new BlockPermutation("minecraft:air") };
  }
  get isValid() {
    return true;
  }
  get typeId() {
    return this._cell.perm.type.id;
  }
  get permutation() {
    return this._cell.perm;
  }
  get isAir() {
    return this.typeId === "minecraft:air";
  }
  get isLiquid() {
    return this.typeId.includes("water") || this.typeId.includes("lava");
  }
  setPermutation(p) {
    const cell = this.dimension._cells.get(`${this.x},${this.y},${this.z}`);
    if (!cell) throw new Error("no block");
    cell.perm = p;
    this.dimension._permChanges++;
  }
  setType(t) {
    this.dimension.setBlock(this.x, this.y, this.z, t);
  }
  offset(o) {
    return this.dimension.getBlock({ x: this.x + o.x, y: this.y + o.y, z: this.z + o.z });
  }
  above(n = 1) {
    return this.offset({ x: 0, y: n, z: 0 });
  }
  below(n = 1) {
    return this.offset({ x: 0, y: -n, z: 0 });
  }
  center() {
    return { x: this.x + 0.5, y: this.y + 0.5, z: this.z + 0.5 };
  }
  getComponent(name) {
    if (name === "minecraft:inventory" && this._cell.container) return { container: this._cell.container };
    return undefined;
  }
}

export class Dimension {
  constructor(id) {
    this.id = id;
    this._cells = new Map();
    this.heightRange = { min: -64, max: 320 };
    this.spawned = [];
    this.sounds = [];
    this._permChanges = 0;
    this.unloaded = new Set();
  }
  setBlock(x, y, z, typeId, states) {
    if (typeId === "minecraft:air") this._cells.delete(`${x},${y},${z}`);
    else this._cells.set(`${x},${y},${z}`, { perm: new BlockPermutation(typeId, { ...defaultStates(typeId), ...(states ?? {}) }) });
    return new Block(this, x, y, z);
  }
  setContainer(x, y, z, typeId, size) {
    this.setBlock(x, y, z, typeId);
    const c = new Container(size);
    this._cells.get(`${x},${y},${z}`).container = c;
    return c;
  }
  isChunkLoaded(loc) {
    return !this.unloaded.has(`${Math.floor(loc.x / 16)},${Math.floor(loc.z / 16)}`);
  }
  getBlock(loc) {
    if (!this.isChunkLoaded(loc)) throw new Error("LocationInUnloadedChunkError");
    return new Block(this, Math.floor(loc.x), Math.floor(loc.y), Math.floor(loc.z));
  }
  spawnItem(stack, location) {
    const e = { typeId: "minecraft:item", location, stack: stack.clone(), removed: false };
    e.getComponent = (n) => (n === "minecraft:item" ? { itemStack: e.stack } : undefined);
    e.remove = () => {
      e.removed = true;
    };
    this.spawned.push(e);
    return e;
  }
  getEntities(opts) {
    return this.spawned.filter((e) => !e.removed && (!opts?.type || e.typeId === opts.type));
  }
  playSound(id, location, opts) {
    this.sounds.push({ id, location, opts });
  }
  droppedCount(id) {
    return this.spawned.filter((e) => !e.removed && e.stack.typeId === id).reduce((n, e) => n + e.stack.amount, 0);
  }
}

function signal() {
  const subs = [];
  return {
    subscribe(fn) {
      subs.push(fn);
      return fn;
    },
    unsubscribe(fn) {
      const i = subs.indexOf(fn);
      if (i >= 0) subs.splice(i, 1);
    },
    _fire(e) {
      for (const s of [...subs]) s(e);
    },
  };
}

export class Player {
  constructor(name, dim) {
    this.name = name;
    this.dimension = dim;
    this.location = { x: 0, y: 64, z: 0 };
    this.inventory = new Container(36);
    this.equipment = {};
    this.messages = [];
    this.actionbar = [];
    this.lookAt = undefined;
    this.playerPermissionLevel = PlayerPermissionLevel.Operator;
    this.onScreenDisplay = { setActionBar: (t) => this.actionbar.push(t) };
  }
  getComponent(name) {
    if (name === "minecraft:inventory") return { container: this.inventory };
    if (name === "minecraft:equippable") {
      const self = this;
      return {
        getEquipment: (slot) => (slot === EquipmentSlot.Mainhand ? self.inventory.getItem(0) : self.equipment[slot]),
        getEquipmentSlot: (slot) => ({
          hasItem: () => !!self.inventory.slots[0],
          getItem: () => self.inventory.getItem(0),
          setItem: (s) => self.inventory.setItem(0, s),
          get amount() {
            return self.inventory.slots[0]?.amount ?? 0;
          },
          set amount(v) {
            self.inventory.slots[0].amount = v;
          },
          get typeId() {
            return self.inventory.slots[0]?.typeId;
          },
        }),
      };
    }
    return undefined;
  }
  sendMessage(m) {
    this.messages.push(m);
  }
  getBlockFromViewDirection() {
    return this.lookAt ? { block: this.lookAt, face: "North", faceLocation: { x: 0.5, y: 0.5, z: 0 } } : undefined;
  }
}

const dims = {
  "minecraft:overworld": new Dimension("minecraft:overworld"),
  "minecraft:nether": new Dimension("minecraft:nether"),
  "minecraft:the_end": new Dimension("minecraft:the_end"),
};

const dynamic = new Map();

export const world = {
  _players: [],
  getDimension: (id) => dims[id.includes(":") ? id : `minecraft:${id}`],
  getPlayers: () => world._players,
  getDynamicProperty: (k) => dynamic.get(k),
  setDynamicProperty: (k, v) => (v === undefined ? dynamic.delete(k) : dynamic.set(k, v)),
  getDynamicPropertyIds: () => [...dynamic.keys()],
  _dynamic: dynamic,
  afterEvents: { worldLoad: signal(), weatherChange: signal(), itemUse: signal() },
  beforeEvents: {},
};

const intervals = [];
const timeouts = [];
export const componentRegistry = new Map();

export const system = {
  currentTick: 0,
  beforeEvents: { startup: signal(), shutdown: signal() },
  runInterval(fn, every) {
    intervals.push({ fn, every, next: system.currentTick + every });
    return intervals.length;
  },
  run(fn) {
    timeouts.push({ fn, at: system.currentTick + 1 });
    return 0;
  },
  runTimeout(fn, t = 1) {
    timeouts.push({ fn, at: system.currentTick + Math.max(1, t) });
    return 0;
  },
  waitTicks(t) {
    return new Promise((res) => timeouts.push({ fn: res, at: system.currentTick + t }));
  },
};

/** Прогон n тиков. */
export function tick(n = 1) {
  for (let i = 0; i < n; i++) {
    system.currentTick++;
    for (const t of timeouts.filter((t) => t.at <= system.currentTick)) {
      timeouts.splice(timeouts.indexOf(t), 1);
      t.fn();
    }
    for (const iv of intervals) {
      if (system.currentTick >= iv.next) {
        iv.next += iv.every;
        iv.fn();
      }
    }
  }
}

export function startup() {
  system.beforeEvents.startup._fire({
    blockComponentRegistry: { registerCustomComponent: (name, c) => componentRegistry.set(name, c) },
    itemComponentRegistry: { registerCustomComponent: () => {} },
  });
}

export { dims };
