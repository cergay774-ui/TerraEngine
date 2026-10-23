import { CommandPermissionLevel, CustomCommandParamType, CustomCommandStatus, Player, WeatherType, system, world, } from "@minecraft/server";
import { ITEM_ID, VERSION } from "./generated.js";
import { cleanupOrphans, ensureRig, followRig, forgetPlayer, removeRig, rigInfo, syncRig } from "./rig.js";
import { defaultsFor, hasSavedSettings, loadSettings, saveSettings } from "./settings.js";
import { applyPackSettings, readPackSettings } from "./packsettings.js";
import { forceClassic, openMenu } from "./ui.js";
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
const settings = new Map();
const dirty = new Set();
const unsaved = new Set();
const worldState = { rain: 0, thunder: 0, seed: 0 };
let ready = false;
let packValues = readPackSettings();
let packSignature = JSON.stringify(packValues);
function get(player) {
    let s = settings.get(player.id);
    if (!s) {
        s = loadSettings(player);
        settings.set(player.id, s);
        // world settings changed while this player was away (or first visit)
        if (applyPackSettings(player, s, packValues)) {
            dirty.add(player.id);
            unsaved.add(player.id);
        }
    }
    return s;
}
const host = {
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
function applyWeather(type) {
    worldState.rain = type === WeatherType.Rain || type === WeatherType.Thunder ? 1 : 0;
    worldState.thunder = type === WeatherType.Thunder ? 1 : 0;
    for (const id of settings.keys())
        dirty.add(id);
}
/** Versions 1.0/1.1 handed out a "Cloud Settings" item; settings now live in
 * the pack settings and the /clouds menu, so old copies are taken away. */
function removeLegacyItem(player) {
    try {
        const container = player.getComponent("minecraft:inventory")?.container;
        if (!container)
            return;
        for (let i = 0; i < container.size; i++) {
            if (container.getItem(i)?.typeId === ITEM_ID)
                container.setItem(i);
        }
    }
    catch (e) {
        console.warn(`[Ultra Clouds] could not remove the old settings item: ${e}`);
    }
}
function onFirstSpawn(player) {
    const first = !hasSavedSettings(player);
    const s = get(player);
    if (first) {
        saveSettings(player, s);
        player.sendMessage({ translate: "uc.msg.welcome" });
    }
    removeLegacyItem(player);
    dirty.add(player.id);
}
function status(player) {
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
/** "/clouds debug": everything needed to diagnose a report from a screenshot. */
function debugInfo(player) {
    const s = get(player);
    let device = "device: unknown";
    try {
        const info = player.clientSystemInfo;
        device = `device: platform=${info.platformType} memoryTier=${info.memoryTier} maxRenderDistance=${info.maxRenderDistance}`;
    }
    catch {
        // simulated players have no client info
    }
    player.sendMessage(`[Ultra Clouds ${VERSION}] ${device}\n` +
        `settings: enabled=${s.enabled} profile=${s.profile} type=${s.type} amount=${s.density} ` +
        `layers=${s.cumulusAmount}/${s.stratusAmount}/${s.altoAmount}/${s.cirrusAmount} quality=${s.quality} ` +
        `detail=${s.detail} soft=${s.softness} skyDepth=${s.skyDepth} perf=${s.perfMode} auto=${s.autoQuality}\n` +
        `weather: rain=${worldState.rain} thunder=${worldState.thunder} seed=${worldState.seed} y=${player.location.y.toFixed(1)}\n` +
        rigInfo(player));
}
function runAction(player, action) {
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
        case "status":
            status(player);
            break;
        case "debug":
            debugInfo(player);
            break;
        case "classic":
            forceClassic(player);
            openMenu(host, player);
            break;
        default:
            openMenu(host, player);
    }
}
// ---- commands: /clouds [menu|on|off|toggle|reset|status|debug|classic] ------
system.beforeEvents.startup.subscribe((ev) => {
    const reg = ev.customCommandRegistry;
    reg.registerEnum("ultra_clouds:action", ["menu", "on", "off", "toggle", "reset", "status", "debug", "classic"]);
    reg.registerCommand({
        name: "ultra_clouds:clouds",
        description: "Ultra Clouds: settings menu, or on/off/toggle/reset/status/debug/classic",
        permissionLevel: CommandPermissionLevel.Any,
        cheatsRequired: false,
        optionalParameters: [{ name: "ultra_clouds:action", type: CustomCommandParamType.Enum }],
    }, (origin, action) => {
        const player = origin.sourceEntity;
        if (!(player instanceof Player)) {
            return { status: CustomCommandStatus.Failure, message: "Ultra Clouds: run this command as a player." };
        }
        // command callbacks run in restricted mode: defer the real work
        system.run(() => runAction(player, action));
        return { status: CustomCommandStatus.Success };
    });
});
// ---- world events -------------------------------------------------------------
world.afterEvents.worldLoad.subscribe(() => {
    packValues = readPackSettings();
    packSignature = JSON.stringify(packValues);
    const saved = world.getDynamicProperty(WEATHER_KEY);
    if (typeof saved === "string")
        applyWeather(saved);
    let seed = world.getDynamicProperty(SEED_KEY);
    if (typeof seed !== "number") {
        seed = Math.floor(Math.random() * 4096);
        world.setDynamicProperty(SEED_KEY, seed);
    }
    worldState.seed = seed;
    ready = true;
    for (const p of world.getAllPlayers())
        onFirstSpawn(p);
});
world.afterEvents.playerSpawn.subscribe((ev) => {
    if (!ready)
        return;
    if (ev.initialSpawn)
        onFirstSpawn(ev.player);
    else
        dirty.add(ev.player.id);
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
    }
    else {
        dirty.add(ev.player.id);
    }
});
world.afterEvents.weatherChange.subscribe((ev) => {
    if (ev.dimension !== OVERWORLD)
        return;
    applyWeather(ev.newWeather);
    world.setDynamicProperty(WEATHER_KEY, ev.newWeather);
});
world.afterEvents.itemUse.subscribe((ev) => {
    if (ev.itemStack.typeId === ITEM_ID)
        openMenu(host, ev.source);
});
// ---- main loop -------------------------------------------------------------------
system.runInterval(() => {
    if (!ready)
        return;
    for (const player of world.getAllPlayers()) {
        const s = get(player);
        const rig = ensureRig(player, s, worldState);
        if (!rig)
            continue;
        if (dirty.delete(player.id))
            syncRig(player, s, worldState);
        followRig(player, s);
    }
}, 1);
// slow housekeeping: saves, dynamic type drift, orphan cleanup, override refresh
system.runInterval(() => {
    if (!ready)
        return;
    for (const player of world.getAllPlayers()) {
        const s = get(player);
        if (unsaved.delete(player.id))
            saveSettings(player, s);
        syncRig(player, s, worldState);
    }
    cleanupOrphans();
}, 100);
// pack settings (behavior pack settings screen) can change during the game;
// stable Script API has no change event yet, so compare once a second
system.runInterval(() => {
    if (!ready)
        return;
    const values = readPackSettings();
    const signature = JSON.stringify(values);
    if (signature === packSignature)
        return;
    packValues = values;
    packSignature = signature;
    for (const player of world.getAllPlayers()) {
        if (applyPackSettings(player, get(player), packValues)) {
            dirty.add(player.id);
            unsaved.add(player.id);
        }
    }
}, 20);
// settings saved a little after the last change (sliders send many updates)
system.runInterval(() => {
    if (!ready || unsaved.size === 0)
        return;
    for (const player of world.getAllPlayers()) {
        if (unsaved.delete(player.id))
            saveSettings(player, get(player));
    }
}, 40);
