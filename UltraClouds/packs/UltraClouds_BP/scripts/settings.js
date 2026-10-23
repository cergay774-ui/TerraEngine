import { MemoryTier, PlatformType, world } from "@minecraft/server";
import { PROPS } from "./generated.js";
export const PROFILE_IDS = ["performance", "balanced", "high", "ultra", "cinematic", "custom"];
export const TYPE_IDS = ["realistic", "cumulus", "cirrus", "overcast", "storm", "fantasy", "minimal", "dynamic"];
/** UI ranges of the numeric settings (also used to sanitise saved data). */
export const RANGES = {
    density: [0, 100, 5],
    cumulusAmount: [0, 200, 10],
    stratusAmount: [0, 200, 10],
    altoAmount: [0, 200, 10],
    cirrusAmount: [0, 200, 10],
    quality: [0, 3, 1],
    detail: [0, 3, 1],
    lightQuality: [0, 2, 1],
    updateRate: [0, 2, 1],
    drawDistance: [30, 100, 5],
    skyDepth: [2, 16, 1],
    size: [50, 200, 5],
    height: [120, 400, 5],
    speed: [0, 100, 5],
    direction: [0, 355, 5],
    softness: [0, 2, 1],
    contrast: [0, 100, 5],
    shadows: [0, 100, 5],
    brightness: [40, 160, 5],
    warmth: [0, 100, 5],
    realism: [0, 100, 5],
    timeInfluence: [0, 100, 5],
    weatherInfluence: [0, 100, 5],
    haze: [0, 100, 5],
    atmosphere: [0, 100, 5],
};
export const SCHEMA_VERSION = 1;
const BASE = {
    v: SCHEMA_VERSION,
    enabled: true,
    profile: "balanced",
    type: "realistic",
    density: 50,
    cumulusAmount: 100,
    stratusAmount: 100,
    altoAmount: 100,
    cirrusAmount: 100,
    quality: 1,
    detail: 1,
    lightQuality: 1,
    updateRate: 1,
    perfMode: false,
    autoQuality: true,
    drawDistance: 80,
    skyDepth: 5,
    size: 100,
    height: 200,
    speed: 20,
    direction: 75,
    softness: 1,
    contrast: 55,
    shadows: 50,
    brightness: 100,
    warmth: 60,
    realism: 70,
    timeInfluence: 100,
    weatherInfluence: 80,
    haze: 20,
    atmosphere: 60,
};
/** Values each profile controls; everything else is left as the player set it. */
export const PROFILES = {
    performance: { quality: 0, detail: 0, lightQuality: 0, updateRate: 2, drawDistance: 60, autoQuality: true, softness: 1, contrast: 55 },
    balanced: { quality: 1, detail: 1, lightQuality: 1, updateRate: 1, drawDistance: 80, autoQuality: true, softness: 1, contrast: 55 },
    high: { quality: 2, detail: 2, lightQuality: 2, updateRate: 0, drawDistance: 90, autoQuality: true, softness: 1, contrast: 60 },
    ultra: { quality: 3, detail: 3, lightQuality: 2, updateRate: 0, drawDistance: 100, autoQuality: false, softness: 1, contrast: 65, realism: 90 },
    cinematic: {
        quality: 2, detail: 3, lightQuality: 2, updateRate: 0, drawDistance: 100, autoQuality: true, softness: 1,
        contrast: 70, warmth: 85, atmosphere: 90, size: 125, speed: 10,
    },
};
export const TYPES = {
    realistic: { cu: 0.55, st: 0.08, ac: 0.3, ci: 0.4, storm: 0, fantasy: 0 },
    cumulus: { cu: 0.72, st: 0.0, ac: 0.08, ci: 0.12, storm: 0, fantasy: 0 },
    cirrus: { cu: 0.06, st: 0.0, ac: 0.18, ci: 0.85, storm: 0, fantasy: 0 },
    overcast: { cu: 0.35, st: 0.95, ac: 0.3, ci: 0.0, storm: 0.15, fantasy: 0 },
    storm: { cu: 0.72, st: 0.8, ac: 0.15, ci: 0.1, storm: 1, fantasy: 0 },
    fantasy: { cu: 0.55, st: 0.0, ac: 0.45, ci: 0.55, storm: 0, fantasy: 1 },
    minimal: { cu: 0.3, st: 0.0, ac: 0.0, ci: 0.22, storm: 0, fantasy: 0 },
};
/** Type cycle of the "dynamic" mode (fair weather heavy, occasional grey days). */
const DYNAMIC_CYCLE = ["realistic", "cumulus", "cirrus", "realistic", "overcast", "cumulus", "fantasy", "minimal"];
function hash(n) {
    let x = (n * 2654435761) >>> 0;
    x ^= x >>> 15;
    x = Math.imul(x, 2246822519) >>> 0;
    x ^= x >>> 13;
    return x >>> 0;
}
/** Smoothly blended layer mix of the dynamic mode for the current world time. */
export function dynamicMix(day, timeOfDay) {
    const a = TYPES[DYNAMIC_CYCLE[hash(day) % DYNAMIC_CYCLE.length]];
    const b = TYPES[DYNAMIC_CYCLE[hash(day + 1) % DYNAMIC_CYCLE.length]];
    const t = Math.min(1, Math.max(0, timeOfDay / 24000));
    const s = t * t * (3 - 2 * t);
    const out = {};
    Object.keys(a).forEach((k) => (out[k] = a[k] + (b[k] - a[k]) * s));
    out.fantasy *= 0.6;
    return out;
}
export function clampSetting(key, value) {
    const [lo, hi] = RANGES[key];
    if (!Number.isFinite(value))
        return BASE[key];
    return Math.min(hi, Math.max(lo, value));
}
/** Profile and sky depth that suit the player's device ("Auto"). */
export function deviceDefaults(player) {
    let profile = "balanced";
    let skyDepth = BASE.skyDepth;
    try {
        if (player) {
            const info = player.clientSystemInfo;
            const mobile = info.platformType === PlatformType.Mobile;
            const tier = info.memoryTier;
            if (tier <= MemoryTier.Low)
                profile = "performance";
            else if (mobile && tier <= MemoryTier.Mid)
                profile = "balanced";
            else if (mobile)
                profile = "high";
            else if (tier >= MemoryTier.SuperHigh)
                profile = "ultra";
            else if (tier >= MemoryTier.High)
                profile = "high";
            // keep the projection inside the fog-free range of typical settings
            skyDepth = Math.max(2, Math.min(info.maxRenderDistance, mobile ? 5 : 8));
        }
    }
    catch {
        // clientSystemInfo can be unavailable for simulated players
    }
    return { profile, skyDepth };
}
/** Device based default (the "automatic quality" first pick). */
export function defaultsFor(player) {
    const s = { ...BASE };
    const d = deviceDefaults(player);
    s.skyDepth = d.skyDepth;
    applyProfile(s, d.profile);
    return s;
}
export function applyProfile(s, profile) {
    s.profile = profile;
    if (profile === "custom")
        return;
    Object.assign(s, PROFILES[profile]);
}
const SETTINGS_KEY = "ultra_clouds:settings";
export function loadSettings(player) {
    const base = defaultsFor(player);
    let raw;
    try {
        raw = player.getDynamicProperty(SETTINGS_KEY);
    }
    catch {
        raw = undefined;
    }
    if (typeof raw !== "string")
        return base;
    try {
        const data = JSON.parse(raw);
        return sanitize({ ...base, ...data });
    }
    catch {
        return base;
    }
}
export function hasSavedSettings(player) {
    try {
        return typeof player.getDynamicProperty(SETTINGS_KEY) === "string";
    }
    catch {
        return false;
    }
}
export function saveSettings(player, s) {
    try {
        player.setDynamicProperty(SETTINGS_KEY, JSON.stringify(s));
    }
    catch (e) {
        console.warn(`[Ultra Clouds] could not save settings: ${e}`);
    }
}
export function sanitize(s) {
    const out = { ...BASE, ...s, v: SCHEMA_VERSION };
    Object.keys(RANGES).forEach((k) => {
        out[k] = clampSetting(k, Number(out[k]));
    });
    out.enabled = Boolean(out.enabled);
    out.perfMode = Boolean(out.perfMode);
    out.autoQuality = Boolean(out.autoQuality);
    if (!PROFILE_IDS.includes(out.profile))
        out.profile = "custom";
    if (!TYPE_IDS.includes(out.type))
        out.type = "realistic";
    return out;
}
/** Target values of the synced entity properties (everything but "show"). */
export function toProperties(s, ws) {
    const perf = s.perfMode;
    let mix;
    if (s.type === "dynamic") {
        mix = dynamicMix(world.getDay(), world.getTimeOfDay());
    }
    else {
        mix = TYPES[s.type];
    }
    const f = s.density / 50;
    const c = (x) => Math.min(1, Math.max(0, x));
    const p = {
        tier: perf ? 0 : s.quality,
        detail: perf ? 0 : s.detail,
        lightq: perf ? 0 : s.lightQuality,
        autoq: perf || s.autoQuality,
        cu: c(mix.cu * f * (s.cumulusAmount / 100)),
        st: c(mix.st * f * (s.stratusAmount / 100)),
        ac: c(mix.ac * f * (s.altoAmount / 100)),
        ci: c(mix.ci * f * (s.cirrusAmount / 100)),
        storm: c(mix.storm),
        fantasy: c(mix.fantasy),
        size: s.size / 100,
        height: s.height,
        wspeed: (s.speed / 100) * 12,
        wdir: s.direction,
        dist: (perf ? Math.min(s.drawDistance, 60) : s.drawDistance) / 100,
        // the farthest clouds (cirrus) project to 1.19 x depth = 0.86 of the sky
        // depth, in front of the vanilla distance fog (it starts at 0.92)
        depth: Math.round(s.skyDepth * 16 * 0.72),
        contrast: s.contrast / 100,
        soft: s.softness,
        shadow: s.shadows / 100,
        bright: s.brightness / 100,
        warm: s.warmth / 100,
        real: s.realism / 100,
        tod: s.timeInfluence / 100,
        wxi: s.weatherInfluence / 100,
        haze: s.haze / 100,
        atmo: s.atmosphere / 100,
        rain: ws.rain,
        thunder: ws.thunder,
        seed: ws.seed,
    };
    // clamp / round to the property definitions so setProperty never throws
    for (const key of Object.keys(p)) {
        const def = PROPS[key];
        const val = p[key];
        if (!def || typeof val === "boolean")
            continue;
        let n = Math.min(def.max, Math.max(def.min, val));
        if (def.type === "int")
            n = Math.round(n);
        p[key] = n;
    }
    return p;
}
export function followInterval(s) {
    if (s.perfMode)
        return 4;
    return [1, 2, 4][s.updateRate] ?? 2;
}
