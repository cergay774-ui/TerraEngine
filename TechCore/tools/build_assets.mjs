// Генератор ресурсов TechCore.
// Источник истины — модули данных behavior_pack/scripts/data/*.js (их же использует игра),
// поэтому JSON блоков/предметов, языковые файлы и документация рецептов всегда согласованы.
// Запуск: node TechCore/tools/build_assets.mjs
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { ITEMS } from "../behavior_pack/scripts/data/items.js";
import { BLOCKS } from "../behavior_pack/scripts/data/machines.js";
import { CRAFTING_TABLE_RECIPES } from "../behavior_pack/scripts/data/recipes.js";
import { COAL_GENERATOR } from "../behavior_pack/scripts/data/generators.js";
import { blockTextures } from "./assets/block_textures.mjs";
import { itemTextures, uiIcons } from "./assets/item_textures.mjs";
import { allModels, toGeometry, bounds, materialsOf } from "./assets/models.mjs";
import { BLOCK_CONFIG, blockJson, FORMAT } from "./assets/blocks.mjs";
import { blockIcon, goggleArmor, packIcon } from "./assets/icons.mjs";
import { writeRecipesDoc } from "./assets/docs.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const BP = path.join(ROOT, "behavior_pack");
const RP = path.join(ROOT, "resource_pack");

export const UUIDS = {
  bpHeader: "2b9230b4-94f7-45ec-8aee-1f73342d4eb6",
  bpData: "0e910dc2-fa8c-44cf-bf5d-7b5909e38a6a",
  bpScript: "e7bbd6aa-fce5-4a6a-86eb-8bfdaf6ef1ed",
  rpHeader: "62ef15f6-98d8-45d9-b8a6-881614cb55cd",
  rpResources: "ee4d2f1d-366c-4ffe-852e-2a48d84c1c49",
};
export const VERSION = "1.0.0";
const MIN_ENGINE = "1.26.50";

function write(file, data) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, typeof data === "string" || Buffer.isBuffer(data) ? data : JSON.stringify(data, null, 2) + "\n");
}

function clean(dir) {
  fs.rmSync(dir, { recursive: true, force: true });
  fs.mkdirSync(dir, { recursive: true });
}

const counts = {};
const bump = (k) => (counts[k] = (counts[k] ?? 0) + 1);

// ---------------------------------------------------------------------------
// Текстуры блоков, атлас, flipbook, PBR (Vibrant Visuals)
// ---------------------------------------------------------------------------
clean(path.join(RP, "textures/techcore"));
const blockTex = blockTextures();
const terrain = {};
const flipbooks = [];
const SPEED_SUFFIX = ["slow", "med", "fast"];
for (const [name, t] of blockTex) {
  const rel = `textures/techcore/blocks/${name}`;
  write(path.join(RP, rel + ".png"), t.canvas.png());
  bump("texture");
  const set = { color: name };
  if (Array.isArray(t.mer)) set.metalness_emissive_roughness = t.mer;
  else {
    write(path.join(RP, rel + "_mer.png"), t.mer.png());
    set.metalness_emissive_roughness = `${name}_mer`;
  }
  write(path.join(RP, rel + ".texture_set.json"), { format_version: "1.16.100", "minecraft:texture_set": set });
  if (t.flip && t.flip.ticks.length > 1) {
    // Одна лента — несколько атласов с разной скоростью (ротор: медленно/средне/быстро).
    t.flip.ticks.forEach((ticks, i) => {
      const base = name.replace(/_anim$/, "");
      const atlas = `tc_${base}_${SPEED_SUFFIX[i]}`;
      terrain[atlas] = { textures: rel };
      flipbooks.push({ flipbook_texture: rel, atlas_tile: atlas, ticks_per_frame: ticks, blend_frames: false });
    });
  } else {
    terrain[`tc_${name}`] = { textures: rel };
    if (t.flip) flipbooks.push({ flipbook_texture: rel, atlas_tile: `tc_${name}`, ticks_per_frame: t.flip.ticks[0], blend_frames: false });
  }
}
write(path.join(RP, "textures/terrain_texture.json"), { resource_pack_name: "techcore", texture_name: "atlas.terrain", padding: 8, num_mip_levels: 4, texture_data: terrain });
write(path.join(RP, "textures/flipbook_textures.json"), flipbooks);

// ---------------------------------------------------------------------------
// Модели и блоки
// ---------------------------------------------------------------------------
clean(path.join(RP, "models/blocks"));
clean(path.join(BP, "blocks"));
const models = allModels();
const problems = [];
for (const [name, model] of Object.entries(models)) {
  const b = bounds(model);
  for (let i = 0; i < 3; i++) {
    const size = b.max[i] - b.min[i];
    if (size > 30 + 1e-6) problems.push(`${name}: размер по оси ${i} = ${size} > 30`);
    if (b.min[i] < -30 || b.max[i] > 30) problems.push(`${name}: выход за ±30 по оси ${i}`);
    const lo = i === 1 ? 0 : -8;
    if (b.max[i] <= lo || b.min[i] >= lo + 16) problems.push(`${name}: модель не пересекает блок по оси ${i}`);
  }
  write(path.join(RP, `models/blocks/${name}.geo.json`), toGeometry(model));
  bump("geometry");
}

for (const [name, cfg] of Object.entries(BLOCK_CONFIG)) {
  const model = models[cfg.model];
  if (!model) throw new Error(`Нет модели ${cfg.model}`);
  if (!BLOCKS[`techcore:${name}`]) throw new Error(`Блок ${name} отсутствует в data/machines.js`);
  const mats = materialsOf(model);
  const conf = { ...cfg };
  if (typeof cfg.itemModel === "string") {
    const im = models[cfg.itemModel];
    conf.itemModel = { geometryId: im.id, mats: materialsOf(im) };
  }
  write(path.join(BP, `blocks/${name}.json`), blockJson(name, conf, model, mats));
  bump("block");
}
for (const id of Object.keys(BLOCKS)) if (!BLOCK_CONFIG[id.split(":")[1]]) problems.push(`Нет конфигурации блока ${id}`);

// ---------------------------------------------------------------------------
// Предметы
// ---------------------------------------------------------------------------
clean(path.join(BP, "items"));
const itemTex = itemTextures();
const itemAtlas = {};
for (const it of ITEMS) {
  const id = `techcore:${it.id}`;
  const tex = itemTex.get(it.id);
  if (!tex) {
    problems.push(`Нет иконки для ${id}`);
    continue;
  }
  const rel = `textures/techcore/items/${it.id}`;
  write(path.join(RP, rel + ".png"), tex.png());
  itemAtlas[id] = { textures: rel };
  /** @type {Record<string, any>} */
  const components = {
    "minecraft:icon": id,
    "minecraft:display_name": { value: `item.${id}` },
    "minecraft:max_stack_size": it.stack ?? 64,
  };
  if (it.id === "coal_dust") components["minecraft:fuel"] = { duration: 40 };
  if (it.goggles) {
    components["minecraft:wearable"] = { slot: "slot.armor.head", protection: 1 };
    components["minecraft:allow_off_hand"] = true;
  }
  if (it.id === "wrench") components["minecraft:hand_equipped"] = true;
  if (it.packedTier) {
    components["minecraft:block_placer"] = { block: "techcore:ultimate_assembler" };
    components["minecraft:hover_text_color"] = "aqua";
  }
  const group = it.group === "tool" ? "equipment" : "items";
  write(path.join(BP, `items/${it.id}.json`), {
    format_version: FORMAT,
    "minecraft:item": { description: { identifier: id, menu_category: { category: group } }, components },
  });
  bump("item");
}
write(path.join(RP, "textures/item_texture.json"), { resource_pack_name: "techcore", texture_name: "atlas.items", texture_data: itemAtlas });

// Иконки интерфейса и блоков (для кнопок форм).
for (const [name, c] of uiIcons()) write(path.join(RP, `textures/techcore/icons/${name}.png`), c.png());
for (const name of Object.keys(BLOCK_CONFIG)) {
  write(path.join(RP, `textures/techcore/icons/${name}.png`), blockIcon(name, blockTex).png());
  bump("icon");
}

// Очки инженера: текстура модели брони и attachable.
write(path.join(RP, "textures/techcore/models/engineer_goggles.png"), goggleArmor().png());
write(path.join(RP, "attachables/engineer_goggles.json"), {
  format_version: "1.8.0",
  "minecraft:attachable": {
    description: {
      identifier: "techcore:engineer_goggles",
      materials: { default: "armor", enchanted: "armor_enchanted" },
      textures: {
        default: "textures/techcore/models/engineer_goggles",
        enchanted: "textures/misc/enchanted_actor_glint",
        baby: "textures/techcore/models/engineer_goggles",
      },
      geometry: { default: "geometry.humanoid.armor.helmet", baby: "geometry.humanoid.baby.armor.helmet" },
      scripts: {
        parent_setup: "v.helmet_layer_visible = false;",
        pre_animation: ["v.use_baby_geo = q.is_baby && c.owning_entity->v.use_dedicated_baby_armor;"],
      },
      render_controllers: ["controller.render.armor.v2"],
    },
  },
});

// ---------------------------------------------------------------------------
// Рецепты верстака
// ---------------------------------------------------------------------------
clean(path.join(BP, "recipes"));
for (const r of CRAFTING_TABLE_RECIPES) {
  write(path.join(BP, `recipes/${r.id}.json`), {
    format_version: "1.21.70",
    "minecraft:recipe_shaped": {
      description: { identifier: `techcore:${r.id}` },
      tags: ["crafting_table"],
      pattern: r.pattern,
      key: Object.fromEntries(Object.entries(r.key).map(([k, v]) => [k, { item: v }])),
      unlock: [{ item: r.unlock }],
      result: { item: r.result, count: r.count },
    },
  });
  bump("recipe");
}

// ---------------------------------------------------------------------------
// Языковые файлы
// ---------------------------------------------------------------------------
function lang(field) {
  const lines = [`## TechCore — ${field === "ru" ? "русский" : "English"}`];
  for (const [id, def] of Object.entries(BLOCKS)) lines.push(`tile.${id}.name=${def[field]}`);
  for (const it of ITEMS) lines.push(`item.techcore:${it.id}=${it[field]}`);
  lines.push(`pack.name=TechCore`);
  lines.push(
    field === "ru"
      ? "pack.description=Технологический аддон: машины, энергосети, генераторы, транспорт и Ультимативный сборщик"
      : "pack.description=Tech add-on: machines, power grids, generators, logistics and the Ultimate Assembler",
  );
  return lines.join("\n") + "\n";
}
write(path.join(RP, "texts/ru_RU.lang"), lang("ru"));
write(path.join(RP, "texts/en_US.lang"), lang("en"));
write(path.join(RP, "texts/languages.json"), ["en_US", "ru_RU"]);
write(path.join(BP, "texts/ru_RU.lang"), "pack.name=TechCore\npack.description=Поведение TechCore\n");
write(path.join(BP, "texts/en_US.lang"), "pack.name=TechCore\npack.description=TechCore behavior\n");
write(path.join(BP, "texts/languages.json"), ["en_US", "ru_RU"]);

// ---------------------------------------------------------------------------
// Манифесты и иконки пакетов
// ---------------------------------------------------------------------------
const metadata = { authors: ["TechCore"], license: "MIT", product_type: "addon" };
write(path.join(BP, "manifest.json"), {
  format_version: 3,
  header: {
    name: "pack.name",
    description: "pack.description",
    uuid: UUIDS.bpHeader,
    version: VERSION,
    min_engine_version: MIN_ENGINE,
  },
  modules: [
    { type: "data", uuid: UUIDS.bpData, version: VERSION },
    { type: "script", language: "javascript", entry: "scripts/main.js", uuid: UUIDS.bpScript, version: VERSION },
  ],
  dependencies: [
    { uuid: UUIDS.rpHeader, version: VERSION },
    { module_name: "@minecraft/server", version: "2.10.0" },
    { module_name: "@minecraft/server-ui", version: "2.2.0" },
  ],
  metadata,
});
write(path.join(RP, "manifest.json"), {
  format_version: 3,
  header: {
    name: "pack.name",
    description: "pack.description",
    uuid: UUIDS.rpHeader,
    version: VERSION,
    min_engine_version: MIN_ENGINE,
    pack_scope: "world",
  },
  modules: [{ type: "resources", uuid: UUIDS.rpResources, version: VERSION }],
  dependencies: [{ uuid: UUIDS.bpHeader, version: VERSION }],
  capabilities: ["pbr"],
  metadata,
});
const icon = packIcon(blockTex).png();
write(path.join(BP, "pack_icon.png"), icon);
write(path.join(RP, "pack_icon.png"), icon);

// Документация рецептов генерируется из тех же данных.
writeRecipesDoc(path.join(ROOT, "docs/RECIPES.md"), { coalRated: COAL_GENERATOR.rated });

if (problems.length) {
  console.error("Проблемы генерации:\n" + problems.map((p) => "  - " + p).join("\n"));
  process.exit(1);
}
console.log("Сгенерировано:", counts);
