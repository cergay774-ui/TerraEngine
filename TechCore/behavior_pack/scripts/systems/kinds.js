// Реестр обработчиков типов машин. Каждая подсистема регистрирует обработчики своих "kind"
// (см. data/machines.js). Так логика остаётся модульной: MachineSystem лишь вызывает
// единый интерфейс, не зная деталей конкретной машины.
import { BLOCKS } from "../data/machines.js";

/**
 * @typedef {Object} StepEnv
 * @property {number} dt              длительность шага, секунды
 * @property {number} tick            текущий игровой тик
 * @property {import("@minecraft/server").Block | undefined} block  блок машины (если чанк загружен)
 */

/**
 * @typedef {Object} KindHandler
 * @property {(rec: any) => void} init                    значения по умолчанию для новой машины
 * @property {(rec: any) => void} sanitize                проверка данных после загрузки
 * @property {(rec: any) => Array<[string, number]>} contents   предметы для выпадения при разрушении
 * @property {(rec: any, env: StepEnv) => number} [demand]       запрос энергии на шаг, E/с (потребители)
 * @property {(rec: any, env: StepEnv) => {available: number, free: boolean}} [supply]  (генераторы)
 * @property {(rec: any) => {charge: number, capacity: number, rate: number}} [storage] (аккумуляторы)
 * @property {(rec: any, env: StepEnv) => void} [step]          шаг после распределения энергии
 * @property {(rec: any) => Record<string, boolean|number|string>} [visual]  состояния блока
 * @property {(rec: any) => {lines: string[], efficiency?: number, powerIn?: number, powerOut?: number, lossPct?: number}} [info]  данные для очков
 * @property {(rec: any) => Array<[number, Record<string, boolean|number|string>]>} [visualParts]  состояния частей мультиблока
 * @property {(rec: any, id: string) => number} [accept]        сколько единиц id машина примет на вход
 * @property {(rec: any, id: string, n: number) => number} [insert]  зачисление на вход, возвращает принятое
 * @property {(rec: any, max: number) => ([string, number] | null)} [extract]  выдача с выхода (для транспорта)
 */

/** @type {Map<string, KindHandler>} */
const handlers = new Map();

/** @param {string} kind @param {KindHandler} handler */
export function registerKind(kind, handler) {
  handlers.set(kind, handler);
}

/** @param {string} typeId @returns {KindHandler | undefined} */
export function handlerFor(typeId) {
  const def = BLOCKS[typeId];
  return def && def.kind ? handlers.get(def.kind) : undefined;
}
