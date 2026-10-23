// Буровая установка. Бурит колонну 3×3 под собой сверху вниз.
// Добываются ТОЛЬКО природные блоки из списка ниже — постройки, контейнеры и блоки
// других аддонов не разрушаются (блок пропускается).

export const DRILL = {
  // Секунд на один блок (при наличии энергии).
  secondsPerBlock: 3,
  // Радиус колонны (1 → 3×3).
  radius: 1,
  // Шанс битума при бурении каменных пород ниже этой высоты.
  bitumenBelowY: 16,
  bitumenChance: 0.04,
  // Сколько блоков проверять за один шаг, пропуская воздух и чужие блоки.
  scanPerStep: 12,
};

// Блок → выпадение [предмет, количество]. Если значение — строка "self", выпадает сам блок.
/** @type {Record<string, [string, number] | "self">} */
export const DRILL_DROPS = {
  "minecraft:stone": ["minecraft:cobblestone", 1],
  "minecraft:cobblestone": ["minecraft:cobblestone", 1],
  "minecraft:deepslate": ["minecraft:cobbled_deepslate", 1],
  "minecraft:cobbled_deepslate": ["minecraft:cobbled_deepslate", 1],
  "minecraft:granite": "self",
  "minecraft:diorite": "self",
  "minecraft:andesite": "self",
  "minecraft:tuff": "self",
  "minecraft:calcite": "self",
  "minecraft:dirt": ["minecraft:dirt", 1],
  "minecraft:grass_block": ["minecraft:dirt", 1],
  "minecraft:coarse_dirt": "self",
  "minecraft:gravel": "self",
  "minecraft:sand": "self",
  "minecraft:red_sand": "self",
  "minecraft:sandstone": "self",
  "minecraft:clay": ["minecraft:clay_ball", 4],
  "minecraft:netherrack": "self",
  "minecraft:basalt": "self",
  "minecraft:blackstone": "self",
  "minecraft:smooth_basalt": "self",
  "minecraft:dripstone_block": "self",
  "minecraft:coal_ore": ["minecraft:coal", 1],
  "minecraft:deepslate_coal_ore": ["minecraft:coal", 1],
  "minecraft:iron_ore": ["minecraft:raw_iron", 1],
  "minecraft:deepslate_iron_ore": ["minecraft:raw_iron", 1],
  "minecraft:copper_ore": ["minecraft:raw_copper", 3],
  "minecraft:deepslate_copper_ore": ["minecraft:raw_copper", 3],
  "minecraft:gold_ore": ["minecraft:raw_gold", 1],
  "minecraft:deepslate_gold_ore": ["minecraft:raw_gold", 1],
  "minecraft:nether_gold_ore": ["minecraft:gold_nugget", 4],
  "minecraft:redstone_ore": ["minecraft:redstone", 4],
  "minecraft:lit_redstone_ore": ["minecraft:redstone", 4],
  "minecraft:deepslate_redstone_ore": ["minecraft:redstone", 4],
  "minecraft:lit_deepslate_redstone_ore": ["minecraft:redstone", 4],
  "minecraft:lapis_ore": ["minecraft:lapis_lazuli", 4],
  "minecraft:deepslate_lapis_ore": ["minecraft:lapis_lazuli", 4],
  "minecraft:diamond_ore": ["minecraft:diamond", 1],
  "minecraft:deepslate_diamond_ore": ["minecraft:diamond", 1],
  "minecraft:emerald_ore": ["minecraft:emerald", 1],
  "minecraft:deepslate_emerald_ore": ["minecraft:emerald", 1],
  "minecraft:quartz_ore": ["minecraft:quartz", 1],
  "minecraft:ancient_debris": "self",
};

// Породы, при бурении которых возможен битум.
export const BITUMEN_HOSTS = new Set([
  "minecraft:stone",
  "minecraft:deepslate",
  "minecraft:tuff",
  "minecraft:andesite",
  "minecraft:diorite",
  "minecraft:granite",
]);

// Блоки, которые бур может пропускать без остановки (воздух/жидкости и пр.).
export const DRILL_PASSABLE = new Set([
  "minecraft:air",
  "minecraft:cave_air",
  "minecraft:void_air",
  "minecraft:water",
  "minecraft:flowing_water",
  "minecraft:lava",
  "minecraft:flowing_lava",
]);
