import { system } from "@minecraft/server";
import { ActionFormData, CustomForm, DataDrivenScreenClosedReason, FormCancelationReason, ModalFormData, ObservableBoolean, ObservableNumber, } from "@minecraft/server-ui";
import { PROFILE_IDS, RANGES, TYPE_IDS, applyProfile, clampSetting, } from "./settings.js";
const tr = (key) => ({ translate: key });
const PAGES = {
    main: [
        { kind: "toggle", key: "enabled", text: "uc.enabled" },
        { kind: "choice", key: "profile", text: "uc.profile", items: PROFILE_IDS.map((p) => `uc.profile.${p}`) },
        { kind: "choice", key: "type", text: "uc.type", items: TYPE_IDS.map((t) => `uc.type.${t}`) },
        { kind: "slider", key: "density", text: "uc.density" },
    ],
    quality: [
        { kind: "choiceNum", key: "quality", text: "uc.quality", items: ["uc.q.0", "uc.q.1", "uc.q.2", "uc.q.3"] },
        { kind: "choiceNum", key: "detail", text: "uc.detail", items: ["uc.det.0", "uc.det.1", "uc.det.2", "uc.det.3"] },
        { kind: "choiceNum", key: "lightQuality", text: "uc.lightq", items: ["uc.lq.0", "uc.lq.1", "uc.lq.2"] },
        { kind: "choiceNum", key: "updateRate", text: "uc.rate", items: ["uc.rate.0", "uc.rate.1", "uc.rate.2"] },
        { kind: "toggle", key: "perfMode", text: "uc.perf" },
        { kind: "toggle", key: "autoQuality", text: "uc.auto" },
        { kind: "slider", key: "drawDistance", text: "uc.drawdist" },
        { kind: "slider", key: "skyDepth", text: "uc.skydepth" },
    ],
    shape: [
        { kind: "slider", key: "size", text: "uc.size" },
        { kind: "slider", key: "height", text: "uc.height" },
        { kind: "slider", key: "speed", text: "uc.speed" },
        { kind: "slider", key: "direction", text: "uc.dir" },
        { kind: "choiceNum", key: "softness", text: "uc.softness", items: ["uc.soft.0", "uc.soft.1", "uc.soft.2"] },
        { kind: "slider", key: "contrast", text: "uc.contrast" },
        { kind: "slider", key: "shadows", text: "uc.shadow" },
    ],
    light: [
        { kind: "slider", key: "brightness", text: "uc.bright" },
        { kind: "slider", key: "warmth", text: "uc.warm" },
        { kind: "slider", key: "realism", text: "uc.real" },
        { kind: "slider", key: "timeInfluence", text: "uc.tod" },
        { kind: "slider", key: "weatherInfluence", text: "uc.wxi" },
        { kind: "slider", key: "haze", text: "uc.haze" },
        { kind: "slider", key: "atmosphere", text: "uc.atmo" },
    ],
};
const SUB_PAGES = [
    { page: "quality", button: "uc.btn.quality", title: "uc.page.quality" },
    { page: "shape", button: "uc.btn.shape", title: "uc.page.shape" },
    { page: "light", button: "uc.btn.light", title: "uc.page.light" },
];
/** Settings that belong to the profiles: editing one makes the profile Custom. */
const PROFILE_KEYS = new Set([
    "quality", "detail", "lightQuality", "updateRate", "drawDistance", "autoQuality", "softness",
    "contrast", "realism", "warmth", "atmosphere", "size", "speed",
]);
/** Players that asked for the classic (non live) menu or whose client lacks it. */
const classicOnly = new Set();
export function forceClassic(player) {
    classicOnly.add(player.id);
}
function setValue(host, player, c, raw) {
    const s = host.get(player);
    switch (c.kind) {
        case "toggle":
            s[c.key] = Boolean(raw);
            break;
        case "slider":
        case "choiceNum":
            s[c.key] = clampSetting(c.key, Number(raw));
            break;
        case "choice":
            if (c.key === "profile") {
                applyProfile(s, PROFILE_IDS[Number(raw)] ?? "custom");
            }
            else {
                s.type = TYPE_IDS[Number(raw)] ?? s.type;
            }
            break;
    }
    if (c.key !== "profile" && PROFILE_KEYS.has(c.key))
        s.profile = "custom";
    host.changed(player);
}
function currentIndex(s, c) {
    if (c.kind === "choice") {
        return c.key === "profile" ? PROFILE_IDS.indexOf(s.profile) : TYPE_IDS.indexOf(s.type);
    }
    if (c.kind === "choiceNum")
        return s[c.key];
    return 0;
}
// --------------------------------------------------------------------------
// Live menu (data-driven UI): every control applies while the menu is open
// --------------------------------------------------------------------------
function showLive(host, player, page, attempt = 0) {
    const s = host.get(player);
    const title = page === "main" ? "uc.title" : SUB_PAGES.find((p) => p.page === page).title;
    const form = new CustomForm(player, tr(title));
    if (page === "main")
        form.label(tr("uc.main.desc"));
    for (const c of PAGES[page]) {
        const desc = { description: tr(`${c.text}.d`) };
        if (c.kind === "toggle") {
            const o = new ObservableBoolean(s[c.key], { clientWritable: true });
            o.subscribe((v) => system.run(() => setValue(host, player, c, v)));
            form.toggle(tr(c.text), o, desc);
        }
        else if (c.kind === "slider") {
            const [lo, hi, step] = RANGES[c.key];
            const o = new ObservableNumber(s[c.key], { clientWritable: true });
            o.subscribe((v) => system.run(() => setValue(host, player, c, v)));
            form.slider(tr(c.text), o, lo, hi, { ...desc, step });
        }
        else {
            const o = new ObservableNumber(Math.max(0, currentIndex(s, c)), { clientWritable: true });
            o.subscribe((v) => system.run(() => setValue(host, player, c, v)));
            form.dropdown(tr(c.text), o, c.items.map((k, i) => ({ label: tr(k), value: i })), desc);
        }
    }
    form.divider();
    const go = (next) => {
        try {
            form.close();
        }
        catch {
            // already closed
        }
        if (next === "close")
            return;
        system.runTimeout(() => {
            if (next === "reset") {
                host.reset(player);
                openMenu(host, player, "main");
            }
            else {
                openMenu(host, player, next);
            }
        }, 2);
    };
    if (page === "main") {
        for (const sp of SUB_PAGES)
            form.button(tr(sp.button), () => go(sp.page));
        form.button(tr("uc.btn.reset"), () => go("reset"));
    }
    else {
        form.button(tr("uc.btn.back"), () => go("main"));
    }
    form.closeButton();
    form.show().then((reason) => {
        if (reason === DataDrivenScreenClosedReason.UserBusy)
            retry(host, player, page, attempt);
    }, () => {
        // the client cannot display data-driven screens: use the classic menu
        classicOnly.add(player.id);
        showClassic(host, player, page);
    });
}
function retry(host, player, page, attempt) {
    if (attempt === 2)
        player.sendMessage(tr("uc.msg.busy"));
    if (attempt > 40)
        return;
    system.runTimeout(() => {
        if (player.isValid)
            openMenu(host, player, page, attempt + 1);
    }, 10);
}
// --------------------------------------------------------------------------
// Classic menu (ActionForm + ModalForm): applies on "Apply"
// --------------------------------------------------------------------------
function showClassic(host, player, page, attempt = 0) {
    if (page === "main") {
        const s = host.get(player);
        const form = new ActionFormData().title(tr("uc.title")).body(tr("uc.main.desc"));
        form.button({ rawtext: [tr("uc.enabled"), { text: ": " }, tr(s.enabled ? "uc.state.on" : "uc.state.off")] });
        form.button(tr("uc.profile"));
        for (const sp of SUB_PAGES)
            form.button(tr(sp.button));
        form.button(tr("uc.btn.reset"));
        form.button(tr("uc.btn.close"));
        form.show(player).then((r) => {
            if (r.canceled) {
                if (r.cancelationReason === FormCancelationReason.UserBusy)
                    retryClassic(host, player, page, attempt);
                return;
            }
            const i = r.selection ?? -1;
            if (i === 0) {
                s.enabled = !s.enabled;
                host.changed(player);
                showClassic(host, player, "main");
            }
            else if (i === 1) {
                showClassicPage(host, player, PAGES.main.slice(1), "uc.title", "main");
            }
            else if (i >= 2 && i < 2 + SUB_PAGES.length) {
                const sp = SUB_PAGES[i - 2];
                showClassicPage(host, player, PAGES[sp.page], sp.title, sp.page);
            }
            else if (i === 2 + SUB_PAGES.length) {
                host.reset(player);
                showClassic(host, player, "main");
            }
        });
    }
    else {
        const sp = SUB_PAGES.find((p) => p.page === page);
        showClassicPage(host, player, PAGES[page], sp.title, page);
    }
}
function showClassicPage(host, player, controls, title, page, attempt = 0) {
    const s = host.get(player);
    const form = new ModalFormData().title(tr(title));
    for (const c of controls) {
        const tooltip = tr(`${c.text}.d`);
        if (c.kind === "toggle") {
            form.toggle(tr(c.text), { defaultValue: s[c.key], tooltip });
        }
        else if (c.kind === "slider") {
            const [lo, hi, step] = RANGES[c.key];
            form.slider(tr(c.text), lo, hi, { valueStep: step, defaultValue: s[c.key], tooltip });
        }
        else {
            form.dropdown(tr(c.text), c.items.map((k) => tr(k)), { defaultValueIndex: Math.max(0, currentIndex(s, c)), tooltip });
        }
    }
    form.submitButton(tr("uc.btn.apply"));
    form.show(player).then((r) => {
        if (r.canceled) {
            if (r.cancelationReason === FormCancelationReason.UserBusy) {
                if (attempt < 40)
                    system.runTimeout(() => showClassicPage(host, player, controls, title, page, attempt + 1), 10);
            }
            else {
                showClassic(host, player, "main");
            }
            return;
        }
        const values = r.formValues ?? [];
        // apply profile first so that explicit values on the same page win
        const order = controls.map((c, i) => ({ c, v: values[i] })).sort((a, b) => (a.c.key === "profile" ? -1 : b.c.key === "profile" ? 1 : 0));
        for (const { c, v } of order) {
            if (v === undefined || typeof v === "string")
                continue;
            const cur = c.kind === "toggle" ? s[c.key] : c.kind === "slider" ? s[c.key] : currentIndex(s, c);
            if (cur !== v)
                setValue(host, player, c, v);
        }
        showClassic(host, player, "main");
    });
}
function retryClassic(host, player, page, attempt) {
    if (attempt === 2)
        player.sendMessage(tr("uc.msg.busy"));
    if (attempt > 40)
        return;
    system.runTimeout(() => {
        if (player.isValid)
            showClassic(host, player, page, attempt + 1);
    }, 10);
}
// --------------------------------------------------------------------------
export function openMenu(host, player, page = "main", attempt = 0) {
    if (!player.isValid)
        return;
    if (classicOnly.has(player.id)) {
        showClassic(host, player, page, attempt);
        return;
    }
    try {
        showLive(host, player, page, attempt);
    }
    catch (e) {
        console.warn(`[Ultra Clouds] live menu unavailable, using classic forms: ${e}`);
        classicOnly.add(player.id);
        showClassic(host, player, page, attempt);
    }
}
