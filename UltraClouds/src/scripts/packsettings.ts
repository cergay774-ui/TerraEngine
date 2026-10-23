import { Player, world } from "@minecraft/server";
import { PACK_SETTINGS } from "./generated.js";
import { CloudType, ProfileId, Settings, applyProfile, clampSetting, deviceDefaults } from "./settings.js";

/**
 * World settings from the behavior pack's own settings screen (manifest
 * "settings", read with world.getPackSettings()).  They apply to every
 * player; a player's personal /clouds changes stay until the owner changes
 * that pack setting again.  Each player keeps a snapshot of the pack values
 * already applied to them, so only real changes overwrite anything.
 */

export type PackValues = Record<string, boolean | number | string>;

const APPLIED_KEY = "ultra_clouds:pack_applied";

/** Current pack values (defaults for anything missing or malformed). */
export function readPackSettings(): PackValues {
  let raw: Record<string, unknown> = {};
  try {
    raw = world.getPackSettings() as Record<string, unknown>;
  } catch {
    // older game versions: defaults
  }
  const out: PackValues = {};
  for (const def of PACK_SETTINGS) {
    const v = raw[def.id];
    if (def.type === "toggle") {
      out[def.key] = typeof v === "boolean" ? v : (def.def as boolean);
    } else if (def.type === "slider") {
      const n = typeof v === "number" && Number.isFinite(v) ? Math.round(v) : (def.def as number);
      out[def.key] = Math.min(def.max ?? n, Math.max(def.min ?? n, n));
    } else {
      out[def.key] = typeof v === "string" && def.options?.includes(v) ? v : (def.def as string);
    }
  }
  return out;
}

function appliedOf(player: Player): PackValues {
  try {
    const raw = player.getDynamicProperty(APPLIED_KEY);
    if (typeof raw === "string") return JSON.parse(raw) as PackValues;
  } catch {
    // corrupted snapshot: apply everything again
  }
  return {};
}

const SOFTNESS: Record<string, number> = { crisp: 0, natural: 1, soft: 2 };

function setOne(s: Settings, key: string, v: boolean | number | string, player: Player): void {
  switch (key) {
    case "enabled":
      s.enabled = v as boolean;
      break;
    case "type":
      s.type = v as CloudType;
      break;
    case "amount":
      s.density = clampSetting("density", v as number);
      break;
    case "cumulus":
      s.cumulusAmount = clampSetting("cumulusAmount", v as number);
      break;
    case "stratus":
      s.stratusAmount = clampSetting("stratusAmount", v as number);
      break;
    case "alto":
      s.altoAmount = clampSetting("altoAmount", v as number);
      break;
    case "cirrus":
      s.cirrusAmount = clampSetting("cirrusAmount", v as number);
      break;
    case "size":
      s.size = clampSetting("size", v as number);
      break;
    case "height":
      s.height = clampSetting("height", v as number);
      break;
    case "speed":
      s.speed = clampSetting("speed", v as number);
      break;
    case "direction":
      s.direction = clampSetting("direction", v as number);
      break;
    case "softness":
      s.softness = SOFTNESS[v as string] ?? 1;
      break;
    case "brightness":
      s.brightness = clampSetting("brightness", v as number);
      break;
    case "warmth":
      s.warmth = clampSetting("warmth", v as number);
      break;
    case "sky_depth":
      s.skyDepth = (v as number) > 0 ? clampSetting("skyDepth", v as number) : deviceDefaults(player).skyDepth;
      break;
    case "perf_mode":
      s.perfMode = v as boolean;
      break;
    case "auto_quality":
      s.autoQuality = v as boolean;
      break;
  }
}

/**
 * Apply the pack values that changed since they were last applied to this
 * player.  Returns true when the player's settings changed.
 */
export function applyPackSettings(player: Player, s: Settings, values: PackValues): boolean {
  const applied = appliedOf(player);
  const changed = Object.keys(values).filter((k) => applied[k] !== values[k]);
  if (changed.length === 0) return false;
  // the profile first: explicit pack values of the same batch win over it,
  // except on a profile change alone, which sets its own values
  if (changed.includes("profile")) {
    const p = values.profile as string;
    applyProfile(s, p === "auto" ? deviceDefaults(player).profile : (p as ProfileId));
  }
  for (const key of changed) {
    if (key !== "profile") setOne(s, key, values[key], player);
  }
  try {
    player.setDynamicProperty(APPLIED_KEY, JSON.stringify(values));
  } catch (e) {
    console.warn(`[Ultra Clouds] could not store the applied pack settings: ${e}`);
  }
  return true;
}
