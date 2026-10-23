// Настройки мира TechCore, изменяемые в игре (операторами): звуки, визуализация груза
// на конвейерах, радиус и лимит анимаций. Хранятся в динамическом свойстве мира.
import { CONFIG } from "../data/config.js";
import { loadSettings, saveSettings } from "./PersistenceSystem.js";

export const settings = {
  sounds: CONFIG.machineSounds,
  cargo: CONFIG.conveyorCargoVisual,
  animationRadius: CONFIG.animationRadius,
  animationLimit: CONFIG.maxAnimatedMachines,
};

export function initSettings() {
  const saved = loadSettings();
  if (typeof saved.sounds === "boolean") settings.sounds = saved.sounds;
  if (typeof saved.cargo === "boolean") settings.cargo = saved.cargo;
  if (Number.isFinite(saved.animationRadius)) settings.animationRadius = clamp(saved.animationRadius, 8, 96);
  if (Number.isFinite(saved.animationLimit)) settings.animationLimit = clamp(saved.animationLimit, 0, 128);
}

export function updateSettings(patch) {
  Object.assign(settings, patch);
  settings.animationRadius = clamp(settings.animationRadius, 8, 96);
  settings.animationLimit = clamp(settings.animationLimit, 0, 128);
  saveSettings(settings);
}

function clamp(v, a, b) {
  return Math.max(a, Math.min(b, Math.round(v)));
}
