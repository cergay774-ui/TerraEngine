// Журнал контента. Сообщения видны в логе контента Bedrock (Настройки → Создатель).
import { CONFIG } from "../data/config.js";

export const log = {
  debug(msg) {
    if (CONFIG.debug) console.log(`[TechCore] ${msg}`);
  },
  info(msg) {
    console.log(`[TechCore] ${msg}`);
  },
  warn(msg) {
    console.warn(`[TechCore] ${msg}`);
  },
  error(msg) {
    console.error(`[TechCore] ${msg}`);
  },
};
