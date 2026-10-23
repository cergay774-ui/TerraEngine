// Модель нагрева генераторов (без API Minecraft).
// Тепло растёт пропорционально нагрузке и рассеивается базовым охлаждением плюс бонусом
// за соседние охладители (вода, лёд, снег). При достижении порога генератор не ломается,
// а ограничивает мощность до восстановления — охлаждение остаётся выгодной, но не
// обязательной механикой.

/**
 * @param {{heat: number, overheated: boolean}} state
 * @param {number} load доля нагрузки 0..1 за прошедший шаг
 * @param {number} coolants число соседних охладителей
 * @param {{gain: number, cooling: number, coolantBonus: number, limit: number, recover: number, throttle: number}} def
 * @param {number} dt секунды
 */
export function stepHeat(state, load, coolants, def, dt) {
  const cooling = def.cooling + def.coolantBonus * Math.min(6, coolants);
  let heat = state.heat + (def.gain * load - cooling) * dt;
  heat = Math.max(0, Math.min(100, heat));
  let overheated = state.overheated;
  if (!overheated && heat >= def.limit) overheated = true;
  else if (overheated && heat <= def.recover) overheated = false;
  return { heat, overheated };
}

/** Множитель доступной мощности с учётом перегрева. */
export function heatThrottle(state, def) {
  return state.overheated ? def.throttle : 1;
}

/** Равновесная температура при полной нагрузке (для подсказок в интерфейсе). */
export function equilibriumNote(coolants, def) {
  const cooling = def.cooling + def.coolantBonus * Math.min(6, coolants);
  return cooling >= def.gain ? "stable" : "heating";
}
