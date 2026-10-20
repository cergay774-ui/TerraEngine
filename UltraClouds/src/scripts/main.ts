import {
  CommandPermissionLevel,
  CustomCommandParamType,
  CustomCommandStatus,
  ItemStack,
  Player,
  WeatherType,
  system,
  world,
} from "@minecraft/server";
import { ITEM_ID } from "./generated.js";
import { cleanupOrphans, ensureRig, followRig, forgetPlayer, removeRig, syncRig } from "./rig.js";
import { Settings, WorldState, defaultsFor, hasSavedSettings, loadSettings, saveSettings } from "./settings.js";
import { MenuHost, forceClassic, openMenu } from "./ui.js";

/**
 * Ultra Clouds - behavior pack entry point.
 *
 * Work done here is deliberately tiny: one teleport per player every 1-4
 * ticks plus property updates when something changes. All per-frame cloud
 * math runs on the client inside the resource pack (Molang).
 */

const OVERWORLD = "minecraft:overworld";
const WEATHER_KEY = "ultra_clouds:weather";
const SEED_KEY = "ultra_clouds:seed";
const ITEM_GIVEN_KEY = "ultra_clouds:item_given";

const settings = new Map<string, Settings>();
const dirty = new Set<string>();
const unsaved = new Set<string>();
const worldState: WorldState = { rain: 0, thunder: 0, seed: 0 };
let ready = false;

function get(player: Player): Settings {
  let s = settings.get(player.id);
  if (!s) {
    s = loadSettings(player);
    settings.set(player.id, s);
  }
  return s;
}

const host: MenuHost = {
  get,
  changed(player) {
    dirty.add(player.id);
    unsaved.add(player.id);
  },
  reset(player) {
    const s = defaultsFor(player);
    settings.set(player.id, s);
    dirty.add(player.id);
    unsaved.add(player.id);
    player.sendMessage({ translate: "uc.msg.reset" });
  },
};

function applyWeather(type: WeatherType | string): void {
  worldState.rain = type === WeatherType.Rain || type === WeatherType.Thunder ? 1 : 0;
  worldState.thunder = type === WeatherType.Thunder ? 1 : 0;
  for (const id of settings.keys()) dirty.add(id);
}

function giveItem(player: Player): void {
  try {
    const inv = player.getComponent("minecraft:inventory");
    inv?.container.addItem(new ItemStack(ITEM_ID, 1));
    player.sendMessage({ translate: "uc.msg.item" });
  } catch (e) {
    console.warn(`[Ultra Clouds] could not give the settings item: ${e}`);
  }
}

function onFirstSpawn(player: Player): void {
  const first = !hasSavedSettings(player);
  const s = get(player);
  if (first) {
    saveSettings(player, s);
    player.sendMessage({ translate: "uc.msg.welcome" });
  }
  if (player.getDynamicProperty(ITEM_GIVEN_KEY) !== true) {
    player.setDynamicProperty(ITEM_GIVEN_KEY, true);
    giveItem(player);
  }
  dirty.add(player.id);
}

function status(player: Player): void {
  const s = get(player);
  player.sendMessage({
    translate: "uc.msg.status",
    with: {
      rawtext: [
        { translate: s.enabled ? "uc.state.on" : "uc.state.off" },
        { translate: `uc.profile.${s.profile}` },
        { translate: `uc.q.${s.perfMode ? 0 : s.quality}` },
      ],
    },
  });
}

function runAction(player: Player, action: string | undefined): void {
  const s = get(player);
  switch (action) {
    case "on":
    case "off":
      s.enabled = action === "on";
      host.changed(player);
      player.sendMessage({ translate: s.enabled ? "uc.msg.on" : "uc.msg.off" });
      break;
    case "toggle":
      s.enabled = !s.enabled;
      host.changed(player);
      player.sendMessage({ translate: s.enabled ? "uc.msg.on" : "uc.msg.off" });
      break;
    case "reset":
      host.reset(player);
      break;
    case "item":
      giveItem(player);
      break;
    case "status":
      status(player);
      break;
    case "classic":
      forceClassic(player);
      openMenu(host, player);
      break;
    default:
      openMenu(host, player);
  }
}

// ---- commands: /clouds [menu|on|off|toggle|reset|item|status|classic] -------
system.beforeEvents.startup.subscribe((ev) => {
  const reg = ev.customCommandRegistry;
  reg.registerEnum("ultra_clouds:action", ["menu", "on", "off", "toggle", "reset", "item", "status", "classic"]);
  reg.registerCommand(
    {
      name: "ultra_clouds:clouds",
      description: "Ultra Clouds: settings menu, or on/off/toggle/reset/item/status/classic",
      permissionLevel: CommandPermissionLevel.Any,
      cheatsRequired: false,
      optionalParameters: [{ name: "ultra_clouds:action", type: CustomCommandParamType.Enum }],
    },
    (origin, action?: string) => {
      const player = origin.sourceEntity;
      if (!(player instanceof Player)) {
        return { status: CustomCommandStatus.Failure, message: "Ultra Clouds: run this command as a player." };
      }
      // command callbacks run in restricted mode: defer the real work
      system.run(() => runAction(player, action));
      return { status: CustomCommandStatus.Success };
    }
  );
});

// ---- world events -------------------------------------------------------------
world.afterEvents.worldLoad.subscribe(() => {
  const saved = world.getDynamicProperty(WEATHER_KEY);
  if (typeof saved === "string") applyWeather(saved);
  let seed = world.getDynamicProperty(SEED_KEY);
  if (typeof seed !== "number") {
    seed = Math.floor(Math.random() * 4096);
    world.setDynamicProperty(SEED_KEY, seed);
  }
  worldState.seed = seed;
  ready = true;
  for (const p of world.getAllPlayers()) onFirstSpawn(p);
});

world.afterEvents.playerSpawn.subscribe((ev) => {
  if (!ready) return;
  if (ev.initialSpawn) onFirstSpawn(ev.player);
  else dirty.add(ev.player.id);
});

world.afterEvents.playerLeave.subscribe((ev) => {
  // settings were saved at most 2 s ago (see the 40 tick saver below)
  forgetPlayer(ev.playerId);
  settings.delete(ev.playerId);
  dirty.delete(ev.playerId);
  unsaved.delete(ev.playerId);
});

world.afterEvents.playerDimensionChange.subscribe((ev) => {
  if (ev.toDimension.id !== OVERWORLD) {
    removeRig(ev.player.id);
  } else {
    dirty.add(ev.player.id);
  }
});

world.afterEvents.weatherChange.subscribe((ev) => {
  if (ev.dimension !== OVERWORLD) return;
  applyWeather(ev.newWeather);
  world.setDynamicProperty(WEATHER_KEY, ev.newWeather);
});

world.afterEvents.itemUse.subscribe((ev) => {
  if (ev.itemStack.typeId === ITEM_ID) openMenu(host, ev.source);
});

// ---- main loop -------------------------------------------------------------------
system.runInterval(() => {
  if (!ready) return;
  for (const player of world.getAllPlayers()) {
    const s = get(player);
    const rig = ensureRig(player, s, worldState);
    if (!rig) continue;
    if (dirty.delete(player.id)) syncRig(player, s, worldState);
    followRig(player, s);
  }
}, 1);

// slow housekeeping: saves, dynamic type drift, orphan cleanup, override refresh
system.runInterval(() => {
  if (!ready) return;
  for (const player of world.getAllPlayers()) {
    const s = get(player);
    if (unsaved.delete(player.id)) saveSettings(player, s);
    syncRig(player, s, worldState);
  }
  cleanupOrphans();
}, 100);

// settings saved a little after the last change (sliders send many updates)
system.runInterval(() => {
  if (!ready || unsaved.size === 0) return;
  for (const player of world.getAllPlayers()) {
    if (unsaved.delete(player.id)) saveSettings(player, get(player));
  }
}, 40);
