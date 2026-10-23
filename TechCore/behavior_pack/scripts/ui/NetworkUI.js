// Обзор энергосети и распределение приоритетов, а также настройки TechCore.
// При дефиците энергии потребители с более низким приоритетом приостанавливаются первыми.
import { ActionFormData, ModalFormData } from "@minecraft/server-ui";
import { PlayerPermissionLevel } from "@minecraft/server";
import { BLOCKS } from "../data/machines.js";
import { rt, statusText, num, pct, PRIORITY_RU } from "../core/text.js";
import { records, saveNow } from "../systems/Registry.js";
import { networkAt, allNetworks } from "../systems/EnergySystem.js";
import { settings, updateSettings } from "../systems/SettingsSystem.js";
import { live, showForm, itemIcon, tell, machineName } from "./common.js";

/** @typedef {import("@minecraft/server").Player} Player */

const PRIORITY_OPTIONS = ["Высокий", "Средний", "Низкий"];

function statsText(net) {
  if (!net || !net.stats) return "§7Сеть ещё не рассчитана (подождите секунду).§r\n";
  const s = net.stats;
  const lossPct = s.generation > 0 ? s.losses / s.generation : 0;
  return (
    `Выработка: §a${num(s.generation, 1)}§r из доступных ${num(s.available, 1)} E/с\n` +
    `Спрос: §c${num(s.demand, 1)}§r E/с, доставлено ${num(s.delivered, 1)} E/с\n` +
    `Потери в линиях: ${num(s.losses, 2)} E/с (${pct(lossPct)})\n` +
    `Запас в аккумуляторах: ${num(s.stored)} E\n` +
    `Устройств: ${s.devices}, проводов: ${s.wires}, слабейший провод: ${num(s.minWireCap)} E/с\n`
  );
}

/** @param {Player} player @param {string} key */
export async function openNetworkUI(player, key) {
  const rec = live(key);
  if (!rec) return;
  const net = networkAt(key);
  const def = BLOCKS[rec.t];
  const form = new ActionFormData().title("Энергосеть").body(rt(statsText(net), "§7Нажмите на потребителя, чтобы изменить приоритет.§r"));
  const actions = [];
  if (def.role === "consumer") {
    form.button(rt("Приоритет этой машины: ", PRIORITY_RU[rec.pr ?? 2]), "textures/techcore/icons/ui_network");
    actions.push(() => priorityUI(player, key));
  }
  const devices = net ? [...net.devices] : [];
  // Сначала потребители по приоритету, затем генераторы и аккумуляторы.
  devices.sort((a, b) => {
    const ra = records.get(a);
    const rb = records.get(b);
    const ca = BLOCKS[ra?.t]?.role === "consumer" ? 0 : 1;
    const cb = BLOCKS[rb?.t]?.role === "consumer" ? 0 : 1;
    return ca - cb || (ra?.pr ?? 2) - (rb?.pr ?? 2);
  });
  for (const k of devices.slice(0, 40)) {
    const r = records.get(k);
    if (!r) continue;
    const role = BLOCKS[r.t].role;
    const extra = role === "consumer" ? ` [${PRIORITY_RU[r.pr ?? 2]}]` : role === "generator" ? ` +${num(r._gen?.output ?? 0, 1)} E/с` : "";
    form.button(rt(machineName(r.t), `${extra}\n${statusText(r.st)} §8(${r.x}, ${r.y}, ${r.z})`), itemIcon(r.t));
    actions.push(() => (role === "consumer" ? priorityUI(player, k) : openNetworkUI(player, key)));
  }
  const res = await showForm(player, form);
  if (!res || res.selection === undefined) return;
  const fn = actions[res.selection];
  if (fn) await fn();
}

async function priorityUI(player, key) {
  const rec = live(key);
  if (!rec) return;
  const form = new ModalFormData()
    .title("Приоритет энергии")
    .label(rt(machineName(rec.t), `\n§7При нехватке энергии машины низкого приоритета останавливаются первыми.§r`))
    .dropdown("Приоритет", PRIORITY_OPTIONS, { defaultValueIndex: (rec.pr ?? 2) - 1 })
    .submitButton("Сохранить");
  /** @type {any} */
  const res = await showForm(player, form);
  if (!res || !res.formValues) return;
  const cur = live(key);
  if (!cur) return;
  const idx = res.formValues.find((v) => typeof v === "number");
  if (typeof idx === "number") {
    cur.pr = Math.max(1, Math.min(3, idx + 1));
    saveNow(cur);
    tell(player, `§aПриоритет: ${PRIORITY_RU[cur.pr]}`);
  }
}

/** Настройки TechCore (гаечный ключ в воздухе). Изменять могут только операторы. @param {Player} player */
export async function openSettingsUI(player) {
  const nets = allNetworks();
  let machines = 0;
  for (const r of records.values()) if (r._loaded) machines++;
  if (player.playerPermissionLevel < PlayerPermissionLevel.Operator) {
    const form = new ActionFormData()
      .title("TechCore")
      .body(`Загружено устройств: ${machines}. Энергосетей: ${nets.length}.\n§7Настройки доступны операторам мира.§r`)
      .button("Закрыть");
    await showForm(player, form);
    return;
  }
  const form = new ModalFormData()
    .title("Настройки TechCore")
    .label(`Загружено устройств: ${machines}. Энергосетей: ${nets.length}.`)
    .toggle("Звуки машин", { defaultValue: settings.sounds })
    .toggle("Показывать груз на конвейерах (нагрузка на клиент)", { defaultValue: settings.cargo })
    .slider("Радиус анимаций, блоков", 8, 96, { defaultValue: settings.animationRadius, valueStep: 8 })
    .slider("Максимум анимируемых машин", 0, 128, { defaultValue: settings.animationLimit, valueStep: 4 })
    .submitButton("Сохранить");
  /** @type {any} */
  const res = await showForm(player, form);
  if (!res || !res.formValues) return;
  const v = res.formValues.filter((x) => x !== undefined && typeof x !== "string");
  updateSettings({ sounds: !!v[0], cargo: !!v[1], animationRadius: Number(v[2]), animationLimit: Number(v[3]) });
  tell(player, "§aНастройки TechCore сохранены.");
}
