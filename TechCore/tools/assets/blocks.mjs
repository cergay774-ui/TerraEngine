// Описание блоков для генерации BP/blocks/*.json.
// Материалы ссылаются на текстуры атласа "tc_<имя>" (см. block_textures.mjs).
import { WIND_TURBINES } from "../../behavior_pack/scripts/data/generators.js";

export const FORMAT = "1.26.50";

const LED_BY_STATUS = ["led_off", "led_green", "led_yellow", "led_red"];
const SCREEN_BY_STATUS = ["screen_idle", "screen_ok", "screen_warn", "screen_err"];

const ROTATION = { south: 0, east: 90, north: 180, west: -90 };

const COMMON_MATS = {
  frame: "frame",
  panel: "panel",
  vent: "vent",
  steel: "steel",
  copper: "copper",
  gold: "gold",
  hazard: "hazard",
  rubber: "rubber",
  insul: "insul",
  crate: "crate",
  cargo: "cargo",
  pipe: "pipe",
  core: "core",
  tank: "tank_red",
  tank_white: "tank_white",
  glass: "glass_dark",
};

/** Вариант материалов для состояния машины: led, screen, work по статусу. */
function statusMats(work) {
  return (st) => ({
    led: LED_BY_STATUS[st.status ?? 0],
    screen: SCREEN_BY_STATUS[st.status ?? 0],
    ...(work ? { work: st.status === 1 ? work[1] : work[0] } : {}),
  });
}

/**
 * Конфигурация блоков.
 * states: имя → число значений (целые 0..n-1) или "bool".
 * vary: состояния, влияющие на материалы/свет (перебираются в permutations).
 * bones: видимость костей (Molang по состояниям).
 */
export const BLOCK_CONFIG = {
  ultimate_assembler: {
    model: "ultimate_assembler",
    directional: true,
    states: { tier: 6, status: 4, phase: 2 },
    vary: ["tier", "status"],
    mats: (st) => ({ ...statusMats(null)(st), accent: `accent_t${st.tier}`, work: "gold" }),
    light: (st) => (st.tier === 5 ? 6 : st.status === 1 ? 3 : 0),
    bones: {
      head_up: "q.block_state('techcore:phase') == 0",
      head_down: "q.block_state('techcore:phase') == 1",
      piece: "q.block_state('techcore:status') == 1",
      cables: "q.block_state('techcore:tier') >= 1",
      gantry2: "q.block_state('techcore:tier') >= 2",
      crown: "q.block_state('techcore:tier') >= 3",
      caps: "q.block_state('techcore:tier') >= 4",
      core: "q.block_state('techcore:tier') >= 5",
    },
    mapColor: "#5c6470",
  },
  coal_generator: {
    model: "coal_generator",
    directional: true,
    states: { status: 4 },
    vary: ["status"],
    mats: (st) => ({ ...statusMats(null)(st), fire: st.status === 1 || st.status === 2 ? "fire_anim" : "fire_off" }),
    light: (st) => (st.status === 1 ? 7 : 0),
    mapColor: "#4d535c",
  },
  diesel_generator: {
    model: "diesel_generator",
    directional: true,
    states: { status: 4, phase: 2 },
    vary: ["status"],
    mats: statusMats(null),
    bones: { pist_a: "q.block_state('techcore:phase') == 0", pist_b: "q.block_state('techcore:phase') == 1" },
    mapColor: "#6b7178",
  },
  gasoline_generator: {
    model: "gasoline_generator",
    directional: true,
    states: { status: 4, phase: 2 },
    vary: ["status"],
    mats: statusMats(null),
    bones: { pist_a: "q.block_state('techcore:phase') == 0", pist_b: "q.block_state('techcore:phase') == 1" },
    mapColor: "#b3352d",
  },
  bio_generator: {
    model: "bio_generator",
    directional: true,
    states: { status: 4, phase: 2 },
    vary: ["status"],
    mats: (st) => ({ ...statusMats(null)(st), glass: "glass_green" }),
    bones: { pist_a: "q.block_state('techcore:phase') == 0", pist_b: "q.block_state('techcore:phase') == 1" },
    mapColor: "#5f9c46",
  },
  battery_basic: {
    model: "battery_basic",
    directional: true,
    states: { level: 5 },
    vary: ["level"],
    mats: (st) => ({ level: `battery_${st.level}`, accent: "accent_t1" }),
    mapColor: "#3b4048",
  },
  battery_advanced: {
    model: "battery_advanced",
    directional: true,
    states: { level: 5 },
    vary: ["level"],
    mats: (st) => ({ level: `battery_${st.level}`, accent: "accent_t3" }),
    light: () => 4,
    mapColor: "#2fa39a",
  },
  copper_wire: { model: "copper_wire", connector: true, mats: () => ({ wire: "wire_copper" }), mapColor: "#b8673c" },
  insulated_wire: { model: "insulated_wire", connector: true, mats: () => ({ wire: "wire_insulated" }), mapColor: "#1e2124" },
  reinforced_wire: { model: "reinforced_wire", connector: true, mats: () => ({ wire: "wire_reinforced" }), mapColor: "#5b636c" },
  superconductor_wire: { model: "superconductor_wire", connector: true, mats: () => ({ wire: "wire_super" }), light: () => 5, mapColor: "#38d6e8" },
  fluid_pipe: { model: "fluid_pipe", connector: true, mats: () => ({}), mapColor: "#7d8791" },
  drill_rig: {
    model: "drill_rig",
    directional: true,
    states: { status: 4, phase: 2 },
    vary: ["status"],
    mats: statusMats(["drill", "drill_anim"]),
    bones: { drill_up: "q.block_state('techcore:phase') == 0", drill_down: "q.block_state('techcore:phase') == 1" },
    mapColor: "#e1b124",
  },
  crusher: { model: "crusher", directional: true, states: { status: 4 }, vary: ["status"], mats: statusMats(["roller", "roller_anim"]), mapColor: "#7c848e" },
  electric_smelter: {
    model: "electric_smelter",
    directional: true,
    states: { status: 4 },
    vary: ["status"],
    mats: statusMats(["glow_off", "glow_anim"]),
    light: (st) => (st.status === 1 ? 8 : 0),
    mapColor: "#c9c3b8",
  },
  press: {
    model: "press",
    directional: true,
    states: { status: 4, phase: 2 },
    vary: ["status"],
    mats: statusMats(null),
    bones: { head_up: "q.block_state('techcore:phase') == 0", head_down: "q.block_state('techcore:phase') == 1" },
    mapColor: "#4d535c",
  },
  lathe: { model: "lathe", directional: true, states: { status: 4 }, vary: ["status"], mats: statusMats(["chuck", "chuck_anim"]), mapColor: "#9aa3ad" },
  fuel_refinery: {
    model: "fuel_refinery",
    directional: true,
    states: { status: 4 },
    vary: ["status"],
    mats: (st) => ({ ...statusMats(["glow_off", "glow_anim"])(st), window: "glass_amber" }),
    light: (st) => (st.status === 1 ? 6 : 0),
    mapColor: "#dfe3e6",
  },
  conveyor: { model: "conveyor", belt: true, states: { loaded: "bool" }, mats: () => ({ belt: "belt_anim" }), bones: { cargo: "q.block_state('techcore:loaded')" }, mapColor: "#26282b" },
  item_filter: {
    model: "item_filter",
    belt: true,
    states: { loaded: "bool" },
    mats: () => ({ belt: "belt_anim", screen: "screen_ok" }),
    bones: { cargo: "q.block_state('techcore:loaded')" },
    mapColor: "#26282b",
  },
  splitter: { model: "splitter", belt: true, states: { loaded: "bool" }, mats: () => ({ belt: "belt" }), bones: { cargo: "q.block_state('techcore:loaded')" }, mapColor: "#26282b" },
  buffer_crate: { model: "buffer_crate", mats: () => ({}), mapColor: "#6b5a3e" },
  fuel_tank: {
    model: "fuel_tank",
    directional: true,
    states: { fluid: 4, level: 5 },
    vary: ["fluid", "level"],
    mats: (st) => ({ window: st.fluid === 0 || st.level === 0 ? "tank_w_0" : `tank_w_${st.fluid}_${st.level}` }),
    mapColor: "#dfe3e6",
  },
};

for (const [id, spec] of Object.entries(WIND_TURBINES)) {
  const name = id.split(":")[1];
  const t = spec.tier;
  const P = spec.parts;
  const SPIN = [`rotor${t}`, `rotor${t}_slow`, `rotor${t}_med`, `rotor${t}_fast`];
  BLOCK_CONFIG[name] = {
    model: name,
    itemModel: `${name}_item`,
    directional: true,
    multiBlock: P,
    states: { spin: 4 },
    vary: ["spin"],
    renderMethod: "alpha_test",
    mats: (st) => ({ rotor: SPIN[st.spin ?? 0], led: "led_red", tank: "tank_white" }),
    bones: {
      foundation: "q.block_state('minecraft:multi_block_part') == 0",
      mast_mid: `q.block_state('minecraft:multi_block_part') > 0 && q.block_state('minecraft:multi_block_part') < ${P - 1}`,
      mast_top: `q.block_state('minecraft:multi_block_part') == ${P - 1}`,
      nacelle: `q.block_state('minecraft:multi_block_part') == ${P - 1}`,
      rotor: `q.block_state('minecraft:multi_block_part') == ${P - 1}`,
    },
    mapColor: "#dfe3e6",
  };
}

function stateValues(n) {
  return n === "bool" ? [false, true] : { values: { min: 0, max: n - 1 } };
}

function combos(states, vary) {
  let out = [{}];
  for (const k of vary) {
    const n = states[k];
    const vals = n === "bool" ? [false, true] : [...Array(n).keys()];
    out = out.flatMap((c) => vals.map((v) => ({ ...c, [k]: v })));
  }
  return out;
}

function materialInstances(cfg, st, modelMats, renderMethod) {
  const map = { ...COMMON_MATS, ...cfg.mats(st) };
  /** @type {Record<string, any>} */
  const out = { "*": { texture: "tc_frame", render_method: renderMethod } };
  for (const name of modelMats) {
    const tex = map[name];
    if (!tex) throw new Error(`Нет текстуры для материала ${name} в ${cfg.model}`);
    out[name] = { texture: `tc_${tex}`, render_method: renderMethod };
  }
  return out;
}

/**
 * JSON блока.
 * @param {string} name @param {any} cfg @param {any} model @param {Set<string>} modelMats
 */
export function blockJson(name, cfg, model, modelMats) {
  const id = `techcore:${name}`;
  const renderMethod = cfg.renderMethod ?? "opaque";
  /** @type {Record<string, any>} */
  const states = {};
  for (const [k, n] of Object.entries(cfg.states ?? {})) states[`techcore:${k}`] = stateValues(n);
  if (cfg.connector) for (const f of ["n", "s", "e", "w", "u", "d"]) states[`techcore:c_${f}`] = [false, true];

  /** @type {Record<string, any>} */
  const traits = {};
  if (cfg.directional) traits["minecraft:placement_direction"] = { enabled_states: ["minecraft:cardinal_direction"], y_rotation_offset: 180 };
  if (cfg.belt) traits["minecraft:placement_direction"] = { enabled_states: ["minecraft:cardinal_direction"] };
  if (cfg.multiBlock) traits["minecraft:multi_block"] = { enabled_states: ["minecraft:multi_block_part"], direction: "up", parts: cfg.multiBlock };

  /** @type {Record<string, any>} */
  const bones = { ...(cfg.bones ?? {}) };
  if (cfg.connector) {
    for (const [f, b] of [["n", "arm_n"], ["s", "arm_s"], ["e", "arm_e"], ["w", "arm_w"], ["u", "arm_u"], ["d", "arm_d"]]) bones[b] = `q.block_state('techcore:c_${f}')`;
  }

  const vary = cfg.vary ?? [];
  const defaultState = Object.fromEntries(vary.map((k) => [k, cfg.states[k] === "bool" ? false : 0]));

  /** @type {Record<string, any>} */
  const components = {
    "minecraft:geometry": Object.keys(bones).length ? { identifier: model.id, bone_visibility: bones } : model.id,
    "minecraft:material_instances": materialInstances(cfg, defaultState, modelMats, renderMethod),
    "minecraft:destructible_by_mining": { seconds_to_destroy: cfg.connector ? 0.8 : 2.5 },
    "minecraft:destructible_by_explosion": { explosion_resistance: 15 },
    "minecraft:light_dampening": 0,
    "minecraft:map_color": cfg.mapColor,
    "minecraft:movable": { movement_type: "immovable" },
    "minecraft:sound": { sound: "metal" },
    [cfg.connector ? "techcore:connector" : "techcore:machine"]: {},
  };
  if (cfg.light) {
    const l = cfg.light(defaultState);
    if (l > 0) components["minecraft:light_emission"] = l;
  }
  if (cfg.connector) {
    const pipe = name === "fluid_pipe";
    components["minecraft:collision_box"] = pipe ? { origin: [-4, 4, -4], size: [8, 8, 8] } : { origin: [-3, 5, -3], size: [6, 6, 6] };
    components["minecraft:selection_box"] = { origin: [-4, 4, -4], size: [8, 8, 8] };
    const vis = Object.fromEntries(Object.keys(bones).map((b) => [b, b === "arm_e" || b === "arm_w"]));
    components["minecraft:item_visual"] = {
      geometry: { identifier: model.id, bone_visibility: vis },
      material_instances: materialInstances(cfg, {}, modelMats, renderMethod),
    };
  }
  if (cfg.belt) {
    const h = name === "item_filter" ? 13 : name === "splitter" ? 7 : 5;
    components["minecraft:collision_box"] = { origin: [-8, 0, -8], size: [16, name === "splitter" ? 5 : 4, 16] };
    components["minecraft:selection_box"] = { origin: [-8, 0, -8], size: [16, h, 16] };
  }
  if (cfg.itemModel) {
    components["minecraft:item_visual"] = {
      geometry: cfg.itemModel.geometryId,
      material_instances: materialInstances(cfg, defaultState, cfg.itemModel.mats, renderMethod),
    };
  }

  const permutations = [];
  if (cfg.directional || cfg.belt) {
    for (const [dir, rot] of Object.entries(ROTATION)) {
      permutations.push({ condition: `q.block_state('minecraft:cardinal_direction') == '${dir}'`, components: { "minecraft:transformation": { rotation: [0, rot, 0] } } });
    }
  }
  if (cfg.multiBlock) {
    permutations.push({
      condition: "q.block_state('minecraft:multi_block_part') == 0",
      components: { "minecraft:collision_box": { origin: [-6, 0, -6], size: [12, 16, 12] }, "minecraft:selection_box": { origin: [-6, 0, -6], size: [12, 16, 12] } },
    });
    permutations.push({
      condition: "q.block_state('minecraft:multi_block_part') > 0",
      components: { "minecraft:collision_box": { origin: [-3, 0, -3], size: [6, 16, 6] }, "minecraft:selection_box": { origin: [-3, 0, -3], size: [6, 16, 6] } },
    });
  }
  if (vary.length) {
    for (const st of combos(cfg.states, vary)) {
      const cond = vary.map((k) => (cfg.states[k] === "bool" ? `${st[k] ? "" : "!"}q.block_state('techcore:${k}')` : `q.block_state('techcore:${k}') == ${st[k]}`)).join(" && ");
      /** @type {Record<string, any>} */
      const comps = { "minecraft:material_instances": materialInstances(cfg, st, modelMats, renderMethod) };
      if (cfg.light) comps["minecraft:light_emission"] = cfg.light(st);
      permutations.push({ condition: cond, components: comps });
    }
  }

  /** @type {Record<string, any>} */
  const description = { identifier: id, menu_category: { category: "items" } };
  if (Object.keys(states).length) description.states = states;
  if (Object.keys(traits).length) description.traits = traits;
  const block = { description, components };
  if (permutations.length) block.permutations = permutations;
  return { format_version: FORMAT, "minecraft:block": block };
}
