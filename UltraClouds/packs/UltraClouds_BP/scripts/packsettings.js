import { world } from "@minecraft/server";
import { PACK_SETTINGS } from "./generated.js";
import { applyProfile, clampSetting, deviceDefaults } from "./settings.js";
const APPLIED_KEY = "ultra_clouds:pack_applied";
/** Current pack values (defaults for anything missing or malformed). */
export function readPackSettings() {
    let raw = {};
    try {
        raw = world.getPackSettings();
    }
    catch {
        // older game versions: defaults
    }
    const out = {};
    for (const def of PACK_SETTINGS) {
        const v = raw[def.id];
        if (def.type === "toggle") {
            out[def.key] = typeof v === "boolean" ? v : def.def;
        }
        else if (def.type === "slider") {
            const n = typeof v === "number" && Number.isFinite(v) ? Math.round(v) : def.def;
            out[def.key] = Math.min(def.max ?? n, Math.max(def.min ?? n, n));
        }
        else {
            out[def.key] = typeof v === "string" && def.options?.includes(v) ? v : def.def;
        }
    }
    return out;
}
function appliedOf(player) {
    try {
        const raw = player.getDynamicProperty(APPLIED_KEY);
        if (typeof raw === "string")
            return JSON.parse(raw);
    }
    catch {
        // corrupted snapshot: apply everything again
    }
    return {};
}
const SOFTNESS = { crisp: 0, natural: 1, soft: 2 };
function setOne(s, key, v, player) {
    switch (key) {
        case "enabled":
            s.enabled = v;
            break;
        case "type":
            s.type = v;
            break;
        case "amount":
            s.density = clampSetting("density", v);
            break;
        case "cumulus":
            s.cumulusAmount = clampSetting("cumulusAmount", v);
            break;
        case "stratus":
            s.stratusAmount = clampSetting("stratusAmount", v);
            break;
        case "alto":
            s.altoAmount = clampSetting("altoAmount", v);
            break;
        case "cirrus":
            s.cirrusAmount = clampSetting("cirrusAmount", v);
            break;
        case "size":
            s.size = clampSetting("size", v);
            break;
        case "height":
            s.height = clampSetting("height", v);
            break;
        case "speed":
            s.speed = clampSetting("speed", v);
            break;
        case "direction":
            s.direction = clampSetting("direction", v);
            break;
        case "softness":
            s.softness = SOFTNESS[v] ?? 1;
            break;
        case "brightness":
            s.brightness = clampSetting("brightness", v);
            break;
        case "warmth":
            s.warmth = clampSetting("warmth", v);
            break;
        case "sky_depth":
            s.skyDepth = v > 0 ? clampSetting("skyDepth", v) : deviceDefaults(player).skyDepth;
            break;
        case "perf_mode":
            s.perfMode = v;
            break;
        case "auto_quality":
            s.autoQuality = v;
            break;
    }
}
/**
 * Apply the pack values that changed since they were last applied to this
 * player.  Returns true when the player's settings changed.
 */
export function applyPackSettings(player, s, values) {
    const applied = appliedOf(player);
    const changed = Object.keys(values).filter((k) => applied[k] !== values[k]);
    if (changed.length === 0)
        return false;
    // the profile first: explicit pack values of the same batch win over it,
    // except on a profile change alone, which sets its own values
    if (changed.includes("profile")) {
        const p = values.profile;
        applyProfile(s, p === "auto" ? deviceDefaults(player).profile : p);
    }
    for (const key of changed) {
        if (key !== "profile")
            setOne(s, key, values[key], player);
    }
    try {
        player.setDynamicProperty(APPLIED_KEY, JSON.stringify(values));
    }
    catch (e) {
        console.warn(`[Ultra Clouds] could not store the applied pack settings: ${e}`);
    }
    return true;
}
