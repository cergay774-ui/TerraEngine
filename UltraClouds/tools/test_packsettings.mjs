// Unit test of the behavior pack settings logic (scripts/packsettings.js and
// scripts/settings.js as compiled into the pack), run under Node.js with a
// minimal stand-in for the parts of @minecraft/server these modules use.
// Run after `tsc`:  node tools/test_packsettings.mjs
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const SCRIPTS = path.join(ROOT, "packs", "UltraClouds_BP", "scripts");
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "uc-packsettings-"));

try {
  for (const f of ["generated.js", "settings.js", "packsettings.js"]) {
    fs.copyFileSync(path.join(SCRIPTS, f), path.join(tmp, f));
  }
  fs.writeFileSync(path.join(tmp, "package.json"), '{"type": "module"}');
  const stub = path.join(tmp, "node_modules", "@minecraft", "server");
  fs.mkdirSync(stub, { recursive: true });
  fs.writeFileSync(path.join(stub, "package.json"), '{"name": "@minecraft/server", "type": "module", "main": "index.js"}');
  fs.writeFileSync(
    path.join(stub, "index.js"),
    `export const MemoryTier = { SuperLow: 0, Low: 1, Mid: 2, High: 3, SuperHigh: 4 };
export const PlatformType = { Console: "Console", Desktop: "Desktop", Mobile: "Mobile" };
export const state = { pack: {}, fail: false };
export const world = {
  getPackSettings: () => {
    if (state.fail) throw new Error("getPackSettings unavailable");
    return state.pack;
  },
  getDay: () => 3,
  getTimeOfDay: () => 6000,
};
`,
  );

  const { state } = await import(pathToFileURL(path.join(stub, "index.js")).href);
  const { readPackSettings, applyPackSettings } = await import(pathToFileURL(path.join(tmp, "packsettings.js")).href);
  const { loadSettings, toProperties } = await import(pathToFileURL(path.join(tmp, "settings.js")).href);
  const { PROPS, PACK_SETTINGS } = await import(pathToFileURL(path.join(tmp, "generated.js")).href);

  const store = new Map();
  const player = {
    clientSystemInfo: { platformType: "Mobile", memoryTier: 2, maxRenderDistance: 12 },
    getDynamicProperty: (k) => store.get(k),
    setDynamicProperty: (k, v) => store.set(k, v),
  };
  const ws = { rain: 0, thunder: 0, seed: 1 };
  const checkProps = (s) => {
    const p = toProperties(s, ws);
    for (const [key, def] of Object.entries(PROPS)) {
      if (key === "show") continue; // set per viewer by rig.ts, not here
      const v = p[key];
      assert.ok(v !== undefined, `property ${key} is set`);
      if (def.type !== "bool") assert.ok(v >= def.min && v <= def.max, `property ${key}=${v} in [${def.min}, ${def.max}]`);
    }
    return p;
  };

  // device defaults: a mid-range phone
  const s = loadSettings(player);
  assert.equal(s.profile, "balanced");
  assert.equal(s.skyDepth, 5);

  // the pack screen untouched: defaults apply once, then nothing changes
  let v = readPackSettings();
  assert.equal(Object.keys(v).length, PACK_SETTINGS.filter((d) => d.type !== "label").length);
  assert.equal(applyPackSettings(player, s, v), true);
  assert.equal(s.type, "realistic");
  assert.equal(s.density, 50);
  assert.equal(s.cumulusAmount, 100);
  assert.equal(s.skyDepth, 5, "sky depth 0 = device default");
  assert.equal(applyPackSettings(player, s, readPackSettings()), false, "same values: no change");

  // a personal /clouds change survives while the pack value stays the same
  s.density = 80;
  assert.equal(applyPackSettings(player, s, readPackSettings()), false);
  assert.equal(s.density, 80);

  // the owner changes pack values: they win, malformed values fall back
  state.pack = {
    "ultra_clouds:amount": 30.000001,
    "ultra_clouds:type": "storm",
    "ultra_clouds:profile": "ultra",
    "ultra_clouds:cumulus": 200,
    "ultra_clouds:softness": "bogus",
    "other:x": 5,
  };
  v = readPackSettings();
  assert.equal(v.amount, 30);
  assert.equal(v.softness, "natural");
  assert.equal("other:x" in v, false);
  assert.equal(applyPackSettings(player, s, v), true);
  assert.equal(s.profile, "ultra");
  assert.equal(s.type, "storm");
  assert.equal(s.density, 30, "explicit amount wins over the profile");
  assert.equal(s.cumulusAmount, 200);
  assert.equal(s.softness, 1);
  let p = checkProps(s);
  assert.equal(p.tier, 3);

  // switches and the sky depth
  state.pack = { "ultra_clouds:sky_depth": 9, "ultra_clouds:enabled": false };
  assert.equal(applyPackSettings(player, s, readPackSettings()), true);
  assert.equal(s.enabled, false);
  assert.equal(s.skyDepth, 9);
  p = checkProps(s);
  assert.equal(p.depth, Math.round(9 * 16 * 0.72));

  // a corrupted snapshot re-applies everything instead of failing
  store.set("ultra_clouds:pack_applied", "{not json");
  assert.equal(applyPackSettings(player, s, readPackSettings()), true);

  // the API throwing (older game): defaults, no exception
  state.fail = true;
  assert.equal(readPackSettings().amount, 50);
  state.fail = false;

  console.log("pack settings test: OK");
} finally {
  fs.rmSync(tmp, { recursive: true, force: true });
}
