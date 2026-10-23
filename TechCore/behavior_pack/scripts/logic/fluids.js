// Резервуары и распределение жидкостей (без API Minecraft).
// Жидкость хранится во внутренних единицах — миллибакетах (мБ). Резервуар держит один тип.

/** @typedef {{ f: string | null, a: number }} Tank */

/** @returns {Tank} */
export function emptyTank() {
  return { f: null, a: 0 };
}

/** Сколько мБ жидкости f можно принять. @param {Tank} t */
export function tankRoom(t, f, cap) {
  if (t.f !== null && t.f !== f && t.a > 0) return 0;
  return Math.max(0, cap - t.a);
}

/** Заливает до amount, возвращает принятое. @param {Tank} t */
export function tankFill(t, f, amount, cap) {
  const take = Math.min(tankRoom(t, f, cap), Math.max(0, amount));
  if (take <= 0) return 0;
  t.f = f;
  t.a += take;
  return take;
}

/** Сливает до amount, возвращает слитое. @param {Tank} t */
export function tankDrain(t, amount) {
  const take = Math.min(t.a, Math.max(0, amount));
  t.a -= take;
  if (t.a <= 1e-6) {
    t.a = 0;
    t.f = null;
  }
  return take;
}

/** Нормализация значения из сохранения. */
export function sanitizeTank(v) {
  if (!v || typeof v !== "object") return emptyTank();
  const a = Number(v.a);
  if (!Number.isFinite(a) || a <= 0 || typeof v.f !== "string") return emptyTank();
  return { f: v.f, a };
}

/**
 * Один шаг распределения в трубной сети.
 * sources   — производители (выход переработчика), отдают в первую очередь;
 * storages  — резервуары: отдают потребителям и принимают излишек источников;
 * consumers — генераторы, принимают только свой тип топлива.
 * Суммарный перенос ограничен budget (мБ за шаг).
 * Все узлы: { key, tank, cap, accepts?: string }
 * Возвращает перенесённый объём.
 */
export function distribute(sources, storages, consumers, budget) {
  let left = budget;
  let moved = 0;
  const pull = (list, f, want) => {
    let got = 0;
    for (const n of list) {
      if (got >= want) break;
      if (n.tank.f !== f || n.tank.a <= 0) continue;
      got += tankDrain(n.tank, want - got);
    }
    return got;
  };
  // 1) Потребители берут сначала у источников, затем у резервуаров.
  for (const c of consumers) {
    if (left <= 0) break;
    const f = c.accepts;
    if (!f) continue;
    const room = Math.min(tankRoom(c.tank, f, c.cap), left);
    if (room <= 0) continue;
    let got = pull(sources, f, room);
    if (got < room) got += pull(storages, f, room - got);
    if (got > 0) {
      tankFill(c.tank, f, got, c.cap);
      left -= got;
      moved += got;
    }
  }
  // 2) Излишек источников уходит в резервуары.
  for (const s of sources) {
    if (left <= 0) break;
    if (!s.tank.f || s.tank.a <= 0) continue;
    for (const st of storages) {
      if (left <= 0 || s.tank.a <= 0) break;
      const f = s.tank.f;
      if (!f) break;
      const room = Math.min(tankRoom(st.tank, f, st.cap), left, s.tank.a);
      if (room <= 0) continue;
      const got = tankDrain(s.tank, room);
      tankFill(st.tank, f, got, st.cap);
      left -= got;
      moved += got;
    }
  }
  return moved;
}
