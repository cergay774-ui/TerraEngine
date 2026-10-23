// Подмена модулей @minecraft/* моками для интеграционных тестов.
import { register } from "node:module";

register(
  "data:text/javascript," +
    encodeURIComponent(`
const map = {
  "@minecraft/server": ${JSON.stringify(new URL("./server.mjs", import.meta.url).href)},
  "@minecraft/server-ui": ${JSON.stringify(new URL("./server-ui.mjs", import.meta.url).href)},
};
export async function resolve(spec, ctx, next) {
  if (map[spec]) return { url: map[spec], shortCircuit: true };
  return next(spec, ctx);
}
`),
);
