// Логика рецептов Ультимативного сборщика (без API Minecraft).

/**
 * Размер рецепта [ширина, высота] по фактически занятым ячейкам.
 * @param {{pattern: string[]}} recipe
 */
export function patternSize(recipe) {
  const h = recipe.pattern.length;
  let w = 0;
  for (const row of recipe.pattern) w = Math.max(w, row.length);
  return [w, h];
}

/**
 * Помещается ли рецепт в сетку [ширина, высота]. Поворот не допускается:
 * порядок "ширина × высота" зафиксирован ТЗ.
 * @param {{pattern: string[]}} recipe @param {[number, number]} grid
 */
export function fitsGrid(recipe, grid) {
  const [w, h] = patternSize(recipe);
  return w <= grid[0] && h <= grid[1];
}

/**
 * Требования рецепта: суммирует ячейки по буквам.
 * @param {{pattern: string[], key: Record<string, string|string[]>}} recipe
 * @returns {Array<[string|string[], number]>}
 */
export function requirements(recipe) {
  /** @type {Map<string, number>} */
  const counts = new Map();
  for (const row of recipe.pattern) {
    for (const ch of row) {
      if (ch === "." || ch === " ") continue;
      counts.set(ch, (counts.get(ch) ?? 0) + 1);
    }
  }
  /** @type {Array<[string|string[], number]>} */
  const out = [];
  for (const [ch, n] of counts) {
    const item = recipe.key[ch];
    if (item === undefined) throw new Error(`Recipe key '${ch}' is not defined`);
    out.push([item, n]);
  }
  return out;
}

/**
 * Проверка рецепта на корректность (используется тестами и при загрузке).
 * @returns {string[]} список ошибок
 */
export function validateRecipe(recipe, tiers) {
  const errors = [];
  const tier = tiers[recipe.minTier];
  if (!tier) errors.push(`${recipe.id}: unknown minTier ${recipe.minTier}`);
  else if (!fitsGrid(recipe, tier.grid)) {
    const [w, h] = patternSize(recipe);
    errors.push(`${recipe.id}: ${w}x${h} does not fit ${tier.grid[0]}x${tier.grid[1]}`);
  }
  const used = new Set();
  for (const row of recipe.pattern) for (const ch of row) if (ch !== "." && ch !== " ") used.add(ch);
  for (const ch of used) if (!(ch in recipe.key)) errors.push(`${recipe.id}: letter ${ch} has no key`);
  for (const ch of Object.keys(recipe.key)) if (!used.has(ch)) errors.push(`${recipe.id}: key ${ch} unused`);
  if (!Array.isArray(recipe.result) || recipe.result[1] < 1) errors.push(`${recipe.id}: bad result`);
  return errors;
}

/**
 * Время изготовления с учётом скорости уровня (секунды, не меньше 1).
 */
export function craftTime(recipe, tierDef) {
  return Math.max(1, Math.ceil(recipe.time / tierDef.speed));
}
