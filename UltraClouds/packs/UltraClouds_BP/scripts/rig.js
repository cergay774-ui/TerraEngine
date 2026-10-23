import { system, world } from "@minecraft/server";
import { ENTITY_ID, PROPS } from "./generated.js";
import { followInterval, toProperties } from "./settings.js";
/**
 * The "sky rig" is one invisible entity per player. Its resource-pack side
 * draws the whole cloud system (see tools/gen_pack.py). The script only has
 * to keep it next to its owner, feed it the settings through synced entity
 * properties, and make it visible to its owner alone.
 */
const OVERWORLD = "minecraft:overworld";
const OWNER_KEY = "ultra_clouds:owner";
/** The rig stays this far below the player so it can never be hit or seen. */
const RIG_DEPTH = 16;
const states = new Map();
function stateOf(player) {
    let st = states.get(player.id);
    if (!st) {
        st = { sent: new Map(), lastOverride: -1e9, lastFollow: -1e9, spawnRetry: 0 };
        states.set(player.id, st);
    }
    return st;
}
function rigLocation(player) {
    const l = player.location;
    return { x: l.x, y: Math.max(l.y - RIG_DEPTH, -60), z: l.z };
}
function valid(e) {
    try {
        return !!e && e.isValid;
    }
    catch {
        return false;
    }
}
/** Find or create the player's rig. Returns undefined outside the overworld. */
export function ensureRig(player, s, ws) {
    const st = stateOf(player);
    if (player.dimension.id !== OVERWORLD || !s.enabled) {
        removeRig(player.id);
        return undefined;
    }
    if (valid(st.rig))
        return st.rig;
    st.rig = undefined;
    st.sent.clear();
    st.shown = undefined;
    if (system.currentTick < st.spawnRetry)
        return undefined;
    try {
        const nearby = player.dimension.getEntities({ type: ENTITY_ID, location: player.location, maxDistance: 96 });
        for (const e of nearby) {
            if (e.getDynamicProperty(OWNER_KEY) === player.id) {
                if (!st.rig)
                    st.rig = e;
                else
                    e.remove();
            }
        }
        if (!st.rig) {
            const rig = player.dimension.spawnEntity(ENTITY_ID, rigLocation(player));
            rig.setDynamicProperty(OWNER_KEY, player.id);
            st.rig = rig;
        }
    }
    catch (e) {
        // chunk not ready yet (joining, teleporting) - try again shortly
        st.spawnRetry = system.currentTick + 20;
        return undefined;
    }
    syncRig(player, s, ws, true);
    return st.rig;
}
export function removeRig(playerId) {
    const st = states.get(playerId);
    if (!st)
        return;
    if (valid(st.rig)) {
        try {
            st.rig.remove();
        }
        catch {
            // already gone
        }
    }
    st.rig = undefined;
    st.sent.clear();
    st.shown = undefined;
}
export function forgetPlayer(playerId) {
    removeRig(playerId);
    states.delete(playerId);
}
/** Push changed property values (and the owner-only visibility override). */
export function syncRig(player, s, ws, force = false) {
    const st = stateOf(player);
    const rig = st.rig;
    if (!valid(rig))
        return;
    const target = toProperties(s, ws);
    for (const key of Object.keys(target)) {
        const value = target[key];
        const prev = st.sent.get(key);
        if (!force && prev !== undefined) {
            if (typeof value === "boolean" ? prev === value : Math.abs(prev - value) < 1e-4)
                continue;
        }
        try {
            rig.setProperty(PROPS[key].id, value);
            st.sent.set(key, value);
        }
        catch (e) {
            console.warn(`[Ultra Clouds] setProperty ${key}=${value} failed: ${e}`);
        }
    }
    // "show" stays false for everybody; only the owner gets an override, so
    // other players never render somebody else's sky.
    const show = s.enabled;
    const now = system.currentTick;
    if (force || st.shown !== show || now - st.lastOverride > 600) {
        try {
            player.setPropertyOverrideForEntity(rig, PROPS.show.id, show);
            st.shown = show;
            st.lastOverride = now;
        }
        catch (e) {
            console.warn(`[Ultra Clouds] visibility override failed: ${e}`);
        }
    }
}
/** Keep the rig under its owner (the client hides the remaining lag). */
export function followRig(player, s) {
    const st = states.get(player.id);
    if (!st || !valid(st.rig))
        return;
    const now = system.currentTick;
    if (now - st.lastFollow < followInterval(s))
        return;
    st.lastFollow = now;
    try {
        st.rig.teleport(rigLocation(player), { rotation: { x: 0, y: 0 } });
    }
    catch {
        st.rig = undefined;
    }
}
/** Remove rigs that lost their owner (left the game, duplicates, old saves). */
export function cleanupOrphans() {
    let rigs = [];
    try {
        rigs = world.getDimension(OVERWORLD).getEntities({ type: ENTITY_ID });
    }
    catch {
        return;
    }
    for (const rig of rigs) {
        const owner = rig.getDynamicProperty(OWNER_KEY);
        const st = typeof owner === "string" ? states.get(owner) : undefined;
        if (!st || !valid(st.rig) || st.rig.id !== rig.id) {
            try {
                rig.remove();
            }
            catch {
                // ignore
            }
        }
    }
}
export function hasRig(player) {
    return valid(states.get(player.id)?.rig);
}
/** Diagnostics for "/clouds debug": rig state and the last values sent. */
export function rigInfo(player) {
    const st = states.get(player.id);
    if (!st || !valid(st.rig))
        return "rig: none";
    const r = st.rig.location;
    const p = player.location;
    const d = Math.hypot(r.x - p.x, r.y - p.y, r.z - p.z);
    const sent = [...st.sent.entries()]
        .map(([k, v]) => `${k}=${typeof v === "number" ? Math.round(v * 1000) / 1000 : v}`)
        .join(" ");
    return `rig: ok, ${d.toFixed(1)} blocks away, shown=${st.shown}\n${sent}`;
}
