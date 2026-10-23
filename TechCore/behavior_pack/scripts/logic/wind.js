// Игровая аппроксимация ветра (без API Minecraft).
// Bedrock не предоставляет скорость ветра, поэтому используется документированная модель:
// высота × погода × измерение × затенение × порывы. См. docs/BALANCE.md.

/**
 * @param {{ y: number, weather: string, dimension: string, obstruction: number, timeSeconds: number, seed: number }} p
 * @param {typeof import("../data/generators.js").WIND_MODEL} m
 * @returns {number} множитель номинальной мощности (0..outputCap)
 */
export function windFactor(p, m) {
  const dim = m.dimensionFactor[p.dimension] ?? 1;
  if (dim <= 0) return 0;
  let h;
  if (p.y <= m.minY) h = m.minFactor;
  else if (p.y <= m.fullY) h = m.minFactor + ((p.y - m.minY) / (m.fullY - m.minY)) * (1 - m.minFactor);
  else h = 1 + Math.min(1, (p.y - m.fullY) / Math.max(1, m.capY - m.fullY)) * (m.maxFactor - 1);
  // Погода существует только в Overworld.
  const w = p.dimension === "minecraft:overworld" ? (m.weather[p.weather] ?? 1) : 1;
  const phase = (p.seed % 1000) / 1000;
  const gust = 1 + m.gustAmplitude * Math.sin((p.timeSeconds / m.gustPeriodSeconds + phase) * Math.PI * 2);
  const f = h * w * dim * gust * p.obstruction;
  return Math.max(0, Math.min(m.outputCap, f));
}

/**
 * Множитель затенения по числу твёрдых блоков вокруг ротора.
 * @param {number} solid @param {number} checked
 */
export function obstructionFactor(solid, checked, m) {
  if (checked <= 0) return 1;
  return Math.max(m.minObstructionFactor, 1 - (solid / checked) * m.obstructionPenalty);
}

/** Детерминированное зерно из координат. */
export function positionSeed(x, y, z) {
  let h = (x * 73856093) ^ (y * 19349663) ^ (z * 83492791);
  h = Math.abs(h | 0);
  return h;
}

/** Состояние вращения ротора по доле мощности: 0 — стоп, 1 — медленно, 2 — средне, 3 — быстро. */
export function spinState(fraction) {
  if (fraction < 0.05) return 0;
  if (fraction < 0.45) return 1;
  if (fraction < 0.85) return 2;
  return 3;
}
