// Ключи позиций и направления.

const DIM_SHORT = { "minecraft:overworld": "o", "minecraft:nether": "n", "minecraft:the_end": "e" };
const DIM_LONG = { o: "minecraft:overworld", n: "minecraft:nether", e: "minecraft:the_end" };

/** Короткий код измерения (для неизвестных — полный идентификатор). */
export function dimCode(dimId) {
  return DIM_SHORT[dimId] ?? dimId;
}

export function dimFromCode(code) {
  return DIM_LONG[code] ?? code;
}

/** Ключ позиции блока: "o:10:64:-3". */
export function posKey(dimId, x, y, z) {
  return `${dimCode(dimId)}:${x}:${y}:${z}`;
}

/** Ключ блока. @param {import("@minecraft/server").Block} block */
export function blockKey(block) {
  return posKey(block.dimension.id, block.x, block.y, block.z);
}

export function parseKey(key) {
  const parts = key.split(":");
  // Идентификатор измерения может содержать ":" — координаты всегда последние три части.
  const z = Number(parts.pop());
  const y = Number(parts.pop());
  const x = Number(parts.pop());
  const dim = dimFromCode(parts.join(":"));
  return { dim, x, y, z };
}

// Шесть граней. Порядок фиксирован (используется в состояниях соединений).
export const FACES = [
  { name: "n", dx: 0, dy: 0, dz: -1 },
  { name: "s", dx: 0, dy: 0, dz: 1 },
  { name: "e", dx: 1, dy: 0, dz: 0 },
  { name: "w", dx: -1, dy: 0, dz: 0 },
  { name: "u", dx: 0, dy: 1, dz: 0 },
  { name: "d", dx: 0, dy: -1, dz: 0 },
];

// Горизонтальные направления состояния minecraft:cardinal_direction.
export const CARDINAL = {
  north: { dx: 0, dz: -1 },
  south: { dx: 0, dz: 1 },
  east: { dx: 1, dz: 0 },
  west: { dx: -1, dz: 0 },
};

const CW = { north: "east", east: "south", south: "west", west: "north" };
const CCW = { north: "west", west: "south", south: "east", east: "north" };
const OPP = { north: "south", south: "north", east: "west", west: "east" };

export const rotateCW = (d) => CW[d] ?? "south";
export const rotateCCW = (d) => CCW[d] ?? "south";
export const opposite = (d) => OPP[d] ?? "north";

export const DIRECTION_RU = { north: "север", south: "юг", east: "восток", west: "запад" };

export function offsetKey(key, dx, dy, dz) {
  const p = parseKey(key);
  return posKey(p.dim, p.x + dx, p.y + dy, p.z + dz);
}

export function distanceSq(a, b) {
  const dx = a.x - b.x;
  const dy = a.y - b.y;
  const dz = a.z - b.z;
  return dx * dx + dy * dy + dz * dz;
}
