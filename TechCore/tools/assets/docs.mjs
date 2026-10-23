// Генерация docs/RECIPES.md из игровых данных (чтобы документация не расходилась с игрой).
import fs from "node:fs";
import { ITEMS, FLUIDS } from "../../behavior_pack/scripts/data/items.js";
import { BLOCKS } from "../../behavior_pack/scripts/data/machines.js";
import { ASSEMBLER_RECIPES, CATEGORIES } from "../../behavior_pack/scripts/data/assembler_recipes.js";
import { MACHINE_RECIPES, CRAFTING_TABLE_RECIPES } from "../../behavior_pack/scripts/data/recipes.js";
import { ASSEMBLER_TIERS, UPGRADES } from "../../behavior_pack/scripts/data/progression.js";
import { requirements, patternSize, craftTime } from "../../behavior_pack/scripts/logic/crafting.js";

const VANILLA_RU = {
  diamond: "Алмаз", gold_ingot: "Золотой слиток", iron_ingot: "Железный слиток", copper_ingot: "Медный слиток",
  iron_nugget: "Железный самородок", redstone: "Красная пыль", redstone_block: "Блок красного камня", coal: "Уголь",
  charcoal: "Древесный уголь", raw_iron: "Рудное железо", raw_gold: "Рудное золото", raw_copper: "Рудная медь",
  iron_ore: "Железная руда", deepslate_iron_ore: "Глубинная железная руда", gold_ore: "Золотая руда",
  deepslate_gold_ore: "Глубинная золотая руда", nether_gold_ore: "Незерская золотая руда", copper_ore: "Медная руда",
  deepslate_copper_ore: "Глубинная медная руда", quartz: "Кварц незера", ender_pearl: "Жемчуг Края", flint: "Кремень",
  leather: "Кожа", bucket: "Ведро", stick: "Палка", dried_kelp: "Сушёная ламинария", furnace: "Печь",
  blast_furnace: "Плавильная печь", hopper: "Воронка", piston: "Поршень", anvil: "Наковальня", smooth_stone: "Гладкий камень",
  glass: "Стекло", glass_pane: "Стеклянная панель", chest: "Сундук", composter: "Компостер", iron_bars: "Железная решётка",
  diamond_pickaxe: "Алмазная кирка", sand: "Песок", red_sand: "Красный песок", gravel: "Гравий", cobblestone: "Булыжник",
  oak_planks: "Доски (любые)",
};

function nameRu(id) {
  if (id.startsWith("techcore:")) {
    const it = ITEMS.find((i) => `techcore:${i.id}` === id);
    if (it) return it.ru;
    return BLOCKS[id]?.ru ?? id;
  }
  return VANILLA_RU[id.split(":")[1]] ?? id;
}

function reqRu(what) {
  if (Array.isArray(what)) return what.length > 6 ? `${nameRu(what[0])} или аналог` : what.map(nameRu).join(" / ");
  return nameRu(what);
}

export function writeRecipesDoc(file, info) {
  const L = [];
  L.push("# Рецепты TechCore");
  L.push("");
  L.push("> Файл генерируется автоматически командой `node TechCore/tools/build_assets.mjs` из данных `behavior_pack/scripts/data/*.js`. Не редактируйте вручную.");
  L.push("");
  L.push("## Верстак (3×3)");
  L.push("");
  for (const r of CRAFTING_TABLE_RECIPES) {
    L.push(`### ${nameRu(r.result)} ×${r.count}`);
    L.push("```");
    for (const row of r.pattern) L.push([...row].map((c) => (c === " " ? "·" : c)).join(" "));
    L.push("```");
    for (const [k, v] of Object.entries(r.key)) L.push(`- **${k}** — ${nameRu(v)}`);
    L.push("");
  }

  L.push("## Ультимативный сборщик");
  L.push("");
  L.push("Сетка показывает форму рецепта (ширина × высота). Ингредиенты загружаются во внутреннее хранилище сборщика, количество каждого компонента равно числу ячеек с его буквой. Время указано для уровня, на котором рецепт открывается (на старших уровнях сборка быстрее).");
  L.push("");
  for (const tier of ASSEMBLER_TIERS) {
    const list = ASSEMBLER_RECIPES.filter((r) => r.minTier === tier.tier);
    L.push(`### ${tier.label} — сетка ${tier.grid[0]}×${tier.grid[1]}`);
    L.push("");
    for (const r of list) {
      const [w, h] = patternSize(r);
      const t = craftTime(r, tier);
      L.push(`#### ${nameRu(r.result[0])} ×${r.result[1]} — ${CATEGORIES[r.category]}`);
      L.push(`Размер ${w}×${h}, время ${t} с, энергия ${r.power > 0 ? `${r.power} E/с (всего ${r.power * t} E)` : "не требуется"}.`);
      L.push("```");
      for (const row of r.pattern) L.push([...row].map((c) => (c === "." ? "·" : c)).join(" "));
      L.push("```");
      const counts = new Map(requirements(r).map(([what, n]) => [JSON.stringify(what), n]));
      for (const [k, v] of Object.entries(r.key)) L.push(`- **${k}** — ${reqRu(v)} ×${counts.get(JSON.stringify(v))}`);
      L.push("");
    }
  }

  L.push("## Модернизация сборщика");
  L.push("");
  L.push("| Переход | Сетка | Материалы | Энергия |");
  L.push("|---|---|---|---|");
  for (const [to, up] of Object.entries(UPGRADES)) {
    const g = ASSEMBLER_TIERS[Number(to)].grid;
    L.push(`| Ур-${Number(to) - 1} → Ур-${to} | ${g[0]}×${g[1]} | ${up.items.map(([id, n]) => `${nameRu(id)} ×${n}`).join(", ")} | ${up.power} E/с × ${up.time} с = ${up.power * up.time} E |`);
  }
  L.push("");

  L.push("## Машины");
  L.push("");
  for (const [machine, list] of Object.entries(MACHINE_RECIPES)) {
    const def = BLOCKS[machine];
    L.push(`### ${def.ru}`);
    L.push(`Базовое потребление: ${def.power} E/с. Входных позиций: ${def.inSlots}${def.outSlots ? `, выходных: ${def.outSlots}` : ""}, до ${def.slotCap} шт. в позиции.`);
    L.push("");
    L.push("| Вход | Выход | Время | Энергия |");
    L.push("|---|---|---|---|");
    for (const r of list) {
      const inp = r.in.map(([w, n]) => `${reqRu(w)} ×${n}`).join(" + ");
      const out = r.fluid ? `${FLUIDS[r.fluid.f].ru} ${r.fluid.a} мБ` : r.out.map(([id, n]) => `${nameRu(id)} ×${n}`).join(" + ");
      const p = r.power ?? def.power;
      L.push(`| ${inp} | ${out} | ${r.time} с | ${p} E/с (${p * r.time} E) |`);
    }
    L.push("");
  }
  L.push("## Топливо угольного генератора");
  L.push("");
  L.push(`Номинал генератора: ${info.coalRated} E/с. Время работы на номинале за единицу топлива:`);
  L.push("");
  L.push("- Уголь, древесный уголь — 40 с (960 E)");
  L.push("- Угольная пыль — 20 с (480 E)");
  L.push("- Блок угля — 400 с (9 600 E)");
  L.push("- Огненный стержень — 60 с (1 440 E)");
  L.push("- Блок сушёной ламинарии — 20 с (480 E)");
  L.push("");
  fs.writeFileSync(file, L.join("\n"));
}
