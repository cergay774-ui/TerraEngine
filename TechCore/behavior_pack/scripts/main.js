// TechCore — точка входа.
// Порядок запуска:
//  1) system.beforeEvents.startup — регистрация кастомных компонентов блоков (ранний режим);
//  2) world.afterEvents.worldLoad — загрузка настроек и записей машин, запуск циклов.
import { system, world } from "@minecraft/server";
import { CONFIG } from "./data/config.js";
import { log } from "./core/log.js";

// Подсистемы регистрируют обработчики видов машин при импорте.
import "./systems/MachineSystem.js";
import "./systems/GeneratorSystem.js";
import "./systems/CraftingSystem.js";
import "./systems/TransportSystem.js";
import "./systems/FuelSystem.js";

import { startMachineLoop } from "./systems/MachineSystem.js";
import { startTransportLoop } from "./systems/TransportSystem.js";
import { startAnimationLoop } from "./systems/AnimationSystem.js";
import { startGogglesLoop } from "./systems/GogglesSystem.js";
import { initWeather } from "./systems/GeneratorSystem.js";
import { initSettings } from "./systems/SettingsSystem.js";
import { loadRecords } from "./systems/Registry.js";
import * as persistence from "./systems/PersistenceSystem.js";
import { registerComponents, markReady } from "./systems/BlockEvents.js";
import { openSettingsUI } from "./ui/NetworkUI.js";

system.beforeEvents.startup.subscribe((event) => {
  registerComponents(event);
});

let started = false;

function start() {
  if (started) return;
  started = true;
  initSettings();
  initWeather();
  loadRecords();
  markReady();

  startMachineLoop();
  startTransportLoop();
  startAnimationLoop();
  startGogglesLoop();

  system.runInterval(() => persistence.flushDirty(), CONFIG.saveTickInterval);
  system.beforeEvents.shutdown.subscribe(() => {
    // При штатном выходе из мира записываем всё несохранённое.
    try {
      persistence.flushDirty();
    } catch {
      // в ограниченном режиме запись может быть недоступна — данные уже сохранены периодически
    }
  });

  // Гаечный ключ в воздухе — обзор и настройки TechCore.
  world.afterEvents.itemUse.subscribe((e) => {
    if (e.itemStack.typeId !== "techcore:wrench") return;
    // Нажатие ключом по блоку TechCore обрабатывает сам блок (поворот/интерфейс).
    const hit = e.source.getBlockFromViewDirection({ maxDistance: 7 });
    if (hit && hit.block.typeId.startsWith("techcore:")) return;
    system.run(() => openSettingsUI(e.source));
  });

  log.info("TechCore запущен");
}

world.afterEvents.worldLoad.subscribe(() => start());
