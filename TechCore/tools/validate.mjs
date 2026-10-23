// Структурная проверка пакетов TechCore (без запуска Minecraft).
// Проверяет: JSON, манифесты и UUID, ссылки блоков на геометрию/кости/материалы/текстуры,
// состояния в Molang-условиях, предметы и иконки, языковые ключи, рецепты, flipbook и PBR,
// импорты скриптов, пути к иконкам интерфейса и регистрацию кастомных компонентов.
// Запуск: node TechCore/tools/validate.mjs
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { readPNGHeader } from "./assets/png.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const BP = path.join(ROOT, "behavior_pack");
const RP = path.join(ROOT, "resource_pack");

const errors = [];
const warnings = [];
const err = (m) => errors.push(m);
const warn = (m) => warnings.push(m);

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else out.push(p);
  }
  return out;
}

function readJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (e) {
    err(`JSON: ${path.relative(ROOT, file)}: ${e.message}`);
    return null;
  }
}

const exists = (p) => fs.existsSync(p);

// --- Все JSON корректны ---
for (const f of [...walk(BP), ...walk(RP)]) if (f.endsWith(".json")) readJson(f);

// --- Манифесты ---
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const bpm = readJson(path.join(BP, "manifest.json"));
const rpm = readJson(path.join(RP, "manifest.json"));
const uuids = [bpm.header.uuid, rpm.header.uuid, ...bpm.modules.map((m) => m.uuid), ...rpm.modules.map((m) => m.uuid)];
for (const u of uuids) if (!UUID_RE.test(u)) err(`UUID не v4: ${u}`);
if (new Set(uuids).size !== uuids.length) err("UUID повторяются");
if (!bpm.dependencies.some((d) => d.uuid === rpm.header.uuid)) err("BP не зависит от RP");
if (!rpm.dependencies.some((d) => d.uuid === bpm.header.uuid)) err("RP не зависит от BP");
const scriptModule = bpm.modules.find((m) => m.type === "script");
if (!scriptModule || !exists(path.join(BP, scriptModule.entry))) err(`Нет точки входа скрипта ${scriptModule?.entry}`);
for (const d of bpm.dependencies) if (d.module_name && !["@minecraft/server", "@minecraft/server-ui"].includes(d.module_name)) err(`Неожиданный модуль ${d.module_name}`);
if (!rpm.capabilities?.includes("pbr")) warn("RP без capability pbr (Vibrant Visuals будет использовать значения по умолчанию)");

// --- Языки ---
function readLang(file) {
  const map = new Map();
  for (const line of fs.readFileSync(file, "utf8").split(/\r?\n/)) {
    if (!line || line.startsWith("##")) continue;
    const i = line.indexOf("=");
    if (i > 0) map.set(line.slice(0, i), line.slice(i + 1));
  }
  return map;
}
const langs = { en: readLang(path.join(RP, "texts/en_US.lang")), ru: readLang(path.join(RP, "texts/ru_RU.lang")) };

// --- Атлас блоков и текстуры ---
const terrain = readJson(path.join(RP, "textures/terrain_texture.json")).texture_data;
for (const [k, v] of Object.entries(terrain)) {
  const png = path.join(RP, v.textures + ".png");
  if (!exists(png)) err(`terrain_texture ${k}: нет файла ${v.textures}.png`);
}
const flip = readJson(path.join(RP, "textures/flipbook_textures.json"));
for (const f of flip) {
  if (!terrain[f.atlas_tile]) err(`flipbook: нет атласа ${f.atlas_tile}`);
  const p = path.join(RP, f.flipbook_texture + ".png");
  if (!exists(p)) err(`flipbook: нет файла ${f.flipbook_texture}`);
  else {
    const { width, height } = readPNGHeader(fs.readFileSync(p));
    if (height % width !== 0 || height === width) err(`flipbook ${f.atlas_tile}: высота ${height} не кратна ширине ${width}`);
  }
}
for (const f of walk(path.join(RP, "textures/techcore"))) {
  if (f.endsWith(".png")) {
    const { width, height } = readPNGHeader(fs.readFileSync(f));
    if (width & (width - 1)) warn(`${path.relative(RP, f)}: ширина ${width} не степень двойки`);
    if (height % width !== 0 && !f.includes("/models/")) err(`${path.relative(RP, f)}: размеры ${width}×${height}`);
  }
  if (f.endsWith(".texture_set.json")) {
    const ts = readJson(f)["minecraft:texture_set"];
    const dir = path.dirname(f);
    if (!exists(path.join(dir, ts.color + ".png"))) err(`texture_set ${f}: нет ${ts.color}.png`);
    const mer = ts.metalness_emissive_roughness;
    if (typeof mer === "string" && !exists(path.join(dir, mer + ".png"))) err(`texture_set ${f}: нет ${mer}.png`);
    if (Array.isArray(mer) && (mer.length !== 3 || mer.some((x) => x < 0 || x > 255))) err(`texture_set ${f}: неверный MER`);
  }
}

// --- Геометрия ---
const geometries = new Map();
for (const f of walk(path.join(RP, "models"))) {
  if (!f.endsWith(".json")) continue;
  const d = readJson(f);
  for (const g of d["minecraft:geometry"]) {
    const id = g.description.identifier;
    if (geometries.has(id)) err(`Геометрия ${id} определена дважды`);
    const bones = new Set();
    const mats = new Set();
    const min = [Infinity, Infinity, Infinity];
    const max = [-Infinity, -Infinity, -Infinity];
    for (const b of g.bones) {
      bones.add(b.name);
      for (const c of b.cubes ?? []) {
        for (const face of Object.values(c.uv)) {
          mats.add(face.material_instance ?? "*");
          const [u, v] = face.uv;
          const [su, sv] = face.uv_size;
          if (u < 0 || v < 0 || u + su > 16.0001 || v + sv > 16.0001) err(`${id}: UV за пределами текстуры`);
        }
        for (let i = 0; i < 3; i++) {
          min[i] = Math.min(min[i], c.origin[i]);
          max[i] = Math.max(max[i], c.origin[i] + c.size[i]);
        }
      }
    }
    for (let i = 0; i < 3; i++) if (max[i] - min[i] > 30.0001) err(`${id}: габарит ${max[i] - min[i]} > 30`);
    geometries.set(id, { bones, mats });
  }
}

// --- Блоки ---
const scriptsText = walk(path.join(BP, "scripts"))
  .filter((f) => f.endsWith(".js"))
  .map((f) => fs.readFileSync(f, "utf8"))
  .join("\n");
const registered = new Set([...scriptsText.matchAll(/registerCustomComponent\(\s*"([^"]+)"/g)].map((m) => m[1]));
const blockIds = new Set();
const TRAIT_STATES = { "minecraft:placement_direction": ["minecraft:cardinal_direction"], "minecraft:multi_block": ["minecraft:multi_block_part"] };

function statesIn(expr) {
  return [...String(expr).matchAll(/q\.block_state\('([^']+)'\)/g)].map((m) => m[1]);
}

for (const f of walk(path.join(BP, "blocks"))) {
  const d = readJson(f);
  const b = d["minecraft:block"];
  const id = b.description.identifier;
  blockIds.add(id);
  const states = new Set(Object.keys(b.description.states ?? {}));
  for (const [t, v] of Object.entries(b.description.traits ?? {})) for (const s of v.enabled_states ?? TRAIT_STATES[t] ?? []) states.add(s);
  let perms = 1;
  for (const v of Object.values(b.description.states ?? {})) perms *= Array.isArray(v) ? v.length : v.values.max - v.values.min + 1;
  if (perms > 65536) err(`${id}: ${perms} перестановок > 65536`);

  const checkComponents = (comps, where) => {
    const g = comps["minecraft:geometry"];
    if (g) {
      const gid = typeof g === "string" ? g : g.identifier;
      const geo = geometries.get(gid);
      if (!geo && !gid.startsWith("minecraft:")) err(`${id} ${where}: нет геометрии ${gid}`);
      if (geo && typeof g === "object") {
        for (const [bone, cond] of Object.entries(g.bone_visibility ?? {})) {
          if (!geo.bones.has(bone)) err(`${id}: кость ${bone} отсутствует в ${gid}`);
          for (const s of statesIn(cond)) if (!states.has(s)) err(`${id}: состояние ${s} в видимости кости не объявлено`);
        }
      }
    }
    const mi = comps["minecraft:material_instances"];
    if (mi) {
      const methods = new Set();
      for (const [name, inst] of Object.entries(mi)) {
        if (typeof inst === "string") continue;
        if (!terrain[inst.texture]) err(`${id} ${where}: материал ${name} → нет текстуры ${inst.texture}`);
        methods.add(inst.render_method ?? "opaque");
      }
      if (methods.size > 1) err(`${id} ${where}: разные render_method у материалов`);
    }
    for (const [k] of Object.entries(comps)) {
      if (!k.startsWith("minecraft:") && !registered.has(k)) err(`${id}: кастомный компонент ${k} не зарегистрирован в скриптах`);
    }
    const iv = comps["minecraft:item_visual"];
    if (iv) {
      const gid = typeof iv.geometry === "string" ? iv.geometry : iv.geometry.identifier;
      if (!geometries.has(gid)) err(`${id}: item_visual → нет геометрии ${gid}`);
      else for (const m of geometries.get(gid).mats) if (!iv.material_instances[m] && !iv.material_instances["*"]) err(`${id}: item_visual без материала ${m}`);
    }
  };
  checkComponents(b.components, "components");
  // Материалы, используемые геометрией, должны быть определены.
  const baseGeo = b.components["minecraft:geometry"];
  const baseGid = typeof baseGeo === "string" ? baseGeo : baseGeo?.identifier;
  const geoMats = geometries.get(baseGid)?.mats ?? new Set();
  const checkMats = (mi, where) => {
    if (!mi) return;
    for (const m of geoMats) if (!mi[m]) err(`${id} ${where}: геометрия использует материал ${m}, он не определён`);
  };
  checkMats(b.components["minecraft:material_instances"], "components");
  for (const [i, p] of (b.permutations ?? []).entries()) {
    for (const s of statesIn(p.condition)) if (!states.has(s)) err(`${id}: состояние ${s} в permutations[${i}] не объявлено`);
    checkComponents(p.components, `permutations[${i}]`);
    checkMats(p.components["minecraft:material_instances"], `permutations[${i}]`);
  }
  if (!langs.en.has(`tile.${id}.name`) || !langs.ru.has(`tile.${id}.name`)) err(`${id}: нет названия в языковых файлах`);
}

// --- Предметы ---
const itemAtlas = readJson(path.join(RP, "textures/item_texture.json")).texture_data;
const itemIds = new Set();
for (const f of walk(path.join(BP, "items"))) {
  const d = readJson(f)["minecraft:item"];
  const id = d.description.identifier;
  itemIds.add(id);
  const icon = d.components["minecraft:icon"];
  if (!itemAtlas[icon]) err(`${id}: нет иконки ${icon}`);
  else if (!exists(path.join(RP, itemAtlas[icon].textures + ".png"))) err(`${id}: нет файла иконки`);
  const key = d.components["minecraft:display_name"]?.value ?? `item.${id}`;
  if (!langs.en.has(key) || !langs.ru.has(key)) err(`${id}: нет перевода ${key}`);
  const placer = d.components["minecraft:block_placer"];
  if (placer && !blockIds.has(placer.block)) err(`${id}: block_placer → неизвестный блок ${placer.block}`);
  if (d.components["minecraft:wearable"] && !exists(path.join(RP, "attachables", `${id.split(":")[1]}.json`))) err(`${id}: носимый предмет без attachable`);
}

// --- Рецепты ---
for (const f of walk(path.join(BP, "recipes"))) {
  const r = readJson(f)["minecraft:recipe_shaped"];
  const ids = [...Object.values(r.key).map((k) => k.item), r.result.item];
  for (const i of ids) if (i.startsWith("techcore:") && !itemIds.has(i) && !blockIds.has(i)) err(`${f}: неизвестный ${i}`);
  const letters = new Set(r.pattern.join("").replace(/ /g, ""));
  for (const l of letters) if (!r.key[l]) err(`${f}: буква ${l} без ключа`);
}

// --- Attachable ---
for (const f of walk(path.join(RP, "attachables"))) {
  const a = readJson(f)["minecraft:attachable"].description;
  for (const t of Object.values(a.textures)) if (t.startsWith("textures/techcore") && !exists(path.join(RP, t + ".png"))) err(`${f}: нет текстуры ${t}`);
  if (!itemIds.has(a.identifier)) err(`${f}: нет предмета ${a.identifier}`);
}

// --- Скрипты: импорты и пути к ресурсам ---
for (const f of walk(path.join(BP, "scripts"))) {
  if (!f.endsWith(".js")) continue;
  const src = fs.readFileSync(f, "utf8");
  for (const m of src.matchAll(/(?:import|export)\s[^"']*?from\s+["']([^"']+)["']|import\s+["']([^"']+)["']/g)) {
    const spec = m[1] ?? m[2];
    if (spec.startsWith("@minecraft/")) {
      if (!["@minecraft/server", "@minecraft/server-ui"].includes(spec)) err(`${path.relative(ROOT, f)}: модуль ${spec} не объявлен в манифесте`);
      continue;
    }
    if (!spec.endsWith(".js")) err(`${path.relative(ROOT, f)}: импорт без расширения .js: ${spec}`);
    if (!exists(path.resolve(path.dirname(f), spec))) err(`${path.relative(ROOT, f)}: не найден импорт ${spec}`);
  }
  // Пути, склеиваемые динамически ("..._" + тип), проверяются по каждому варианту ниже.
  for (const m of src.matchAll(/"(textures\/techcore\/[a-z0-9_/]+)"(?!\s*\+)/g)) {
    if (!exists(path.join(RP, m[1] + ".png"))) err(`${path.relative(ROOT, f)}: нет текстуры ${m[1]}`);
  }
}
for (const name of ["ui_insert", "ui_take", "ui_recipes", "ui_network", "ui_refresh", "ui_rotate", "ui_power", "ui_upgrade", "ui_storage"])
  if (!exists(path.join(RP, `textures/techcore/icons/${name}.png`))) err(`нет иконки ${name}`);
for (const id of blockIds) if (!exists(path.join(RP, `textures/techcore/icons/${id.split(":")[1]}.png`))) err(`нет иконки блока ${id}`);
for (const f of ["diesel", "gasoline", "biofuel"]) if (!exists(path.join(RP, `textures/techcore/items/canister_${f}.png`))) err(`нет иконки канистры ${f}`);
for (const id of itemIds) if (!exists(path.join(RP, `textures/techcore/items/${id.split(":")[1]}.png`))) err(`нет иконки предмета ${id}`);

// --- Пустые файлы ---
for (const f of [...walk(BP), ...walk(RP)]) if (fs.statSync(f).size === 0) err(`Пустой файл ${path.relative(ROOT, f)}`);

console.log(`Блоков: ${blockIds.size}, предметов: ${itemIds.size}, геометрий: ${geometries.size}, атласов: ${Object.keys(terrain).length}, flipbook: ${flip.length}`);
for (const w of warnings) console.log("ПРЕДУПРЕЖДЕНИЕ:", w);
if (errors.length) {
  console.error(`ОШИБКИ (${errors.length}):\n` + errors.map((e) => "  - " + e).join("\n"));
  process.exit(1);
}
console.log("Структурная проверка пройдена.");
