// Геометрия блоков TechCore (формат Bedrock geometry, единицы — пиксели блока).
// Ось: x — восток, y — вверх, z — юг. Лицевая сторона машин смотрит на юг (+z); поворот по
// состоянию minecraft:cardinal_direction задаётся компонентом minecraft:transformation
// (south 0°, east 90°, north 180°, west −90°).
// Ограничения блоков: общий габарит ≤ 30×30×30, координаты в пределах ±30 от начала.

/**
 * Куб. m — материал для всех граней или объект по граням.
 * opts.full — грани, на которые натягивается вся текстура (true — все).
 */
export function cube(o, s, m, opts = {}) {
  return { o, s, m, ...opts };
}

export function bone(name, cubes) {
  return { name, cubes };
}

const FACE_DIMS = {
  north: (s) => [s[0], s[1]],
  south: (s) => [s[0], s[1]],
  east: (s) => [s[2], s[1]],
  west: (s) => [s[2], s[1]],
  up: (s) => [s[0], s[2]],
  down: (s) => [s[0], s[2]],
};

function materialFor(m, face) {
  if (typeof m === "string") return m;
  return m[face] ?? m.all ?? "frame";
}

/** Преобразование DSL → JSON геометрии. */
export function toGeometry(model) {
  const bones = model.bones.map((b) => ({
    name: b.name,
    pivot: [0, 0, 0],
    cubes: b.cubes.map((c, ci) => {
      const uv = {};
      for (const face of Object.keys(FACE_DIMS)) {
        if (c.faces && !c.faces.includes(face)) continue;
        const [a, bb] = FACE_DIMS[face](c.s);
        if (a <= 0 || bb <= 0) continue;
        const full = c.full === true || (Array.isArray(c.full) && c.full.includes(face));
        let size;
        let origin;
        if (full) {
          size = [16, 16];
          origin = [0, 0];
        } else {
          size = [Math.min(16, a), Math.min(16, bb)];
          const seed = Math.abs(Math.round(c.o[0] * 7 + c.o[1] * 13 + c.o[2] * 5 + ci * 3));
          origin = [seed % (16 - Math.ceil(size[0]) + 1), (seed >> 2) % (16 - Math.ceil(size[1]) + 1)];
        }
        uv[face] = { uv: origin, uv_size: size, material_instance: materialFor(c.m, face) };
      }
      const out = { origin: c.o, size: c.s, uv };
      if (c.rot) {
        out.rotation = c.rot;
        out.pivot = c.pivot ?? [c.o[0] + c.s[0] / 2, c.o[1] + c.s[1] / 2, c.o[2] + c.s[2] / 2];
      }
      return out;
    }),
  }));
  return {
    format_version: "1.21.0",
    "minecraft:geometry": [
      {
        description: {
          identifier: model.id,
          texture_width: 16,
          texture_height: 16,
          visible_bounds_width: 3,
          visible_bounds_height: 3,
          visible_bounds_offset: [0, 0.75, 0],
        },
        bones,
      },
    ],
  };
}

/** Габариты модели (для проверки ограничений). */
export function bounds(model) {
  const min = [Infinity, Infinity, Infinity];
  const max = [-Infinity, -Infinity, -Infinity];
  for (const b of model.bones)
    for (const c of b.cubes)
      for (let i = 0; i < 3; i++) {
        min[i] = Math.min(min[i], c.o[i]);
        max[i] = Math.max(max[i], c.o[i] + c.s[i]);
      }
  return { min, max };
}

/** Набор материалов, используемых моделью. */
export function materialsOf(model) {
  const set = new Set();
  for (const b of model.bones)
    for (const c of b.cubes) {
      if (typeof c.m === "string") set.add(c.m);
      else Object.values(c.m).forEach((v) => set.add(v));
    }
  return set;
}

const LED = (x, y, z = 7) => cube([x, y, z], [1.5, 1.5, 0.5], "led", { full: true });

// ---------------------------------------------------------------------------
// Ультимативный сборщик
// ---------------------------------------------------------------------------
export const ASSEMBLER = {
  id: "geometry.techcore.ultimate_assembler",
  bones: [
    bone("base", [
      cube([-8, 0, -8], [16, 2, 16], "frame"),
      cube([-7, 2, -7], [14, 8, 14], { all: "panel", east: "vent", west: "vent" }),
      cube([-5, 3.5, 7], [10, 5.5, 0.5], "screen", { full: true }),
      LED(4.5, 2.5),
      cube([-7.5, 2, -7.5], [1, 8, 1], "accent"),
      cube([6.5, 2, -7.5], [1, 8, 1], "accent"),
      cube([-7.5, 2, 6.5], [1, 8, 1], "accent"),
      cube([6.5, 2, 6.5], [1, 8, 1], "accent"),
      cube([-6, 10, -6], [12, 1, 12], "steel"),
      cube([-6, 11, -7], [2, 5, 2], "frame"),
      cube([4, 11, -7], [2, 5, 2], "frame"),
      cube([-6, 15, -5], [12, 1, 2], "steel"),
      cube([-1, 15, -3], [2, 1, 4], "steel"),
    ]),
    bone("head_up", [cube([-1.5, 12.5, 0], [3, 2.5, 3], "accent"), cube([-0.5, 11.5, 1], [1, 1, 1], "steel")]),
    bone("head_down", [cube([-1.5, 11.5, 0], [3, 3.5, 3], "accent"), cube([-0.5, 11, 1], [1, 0.5, 1], "steel")]),
    bone("piece", [cube([-2.5, 11, -0.5], [5, 0.5, 4], "work")]),
    bone("cables", [cube([-8.5, 3, -6], [1, 1, 12], "copper"), cube([7.5, 3, -6], [1, 1, 12], "copper"), cube([-8.5, 6, -6], [1, 1, 12], "copper"), cube([7.5, 6, -6], [1, 1, 12], "copper")]),
    bone("gantry2", [cube([-6, 11, 5], [2, 5, 2], "frame"), cube([4, 11, 5], [2, 5, 2], "frame"), cube([-6, 15, 3], [12, 1, 2], "steel")]),
    bone("crown", [cube([-6.5, 16, -6.5], [13, 1, 13], "panel"), cube([-1, 17, -1], [2, 2, 2], "accent"), cube([-6.5, 17, -6.5], [1, 3, 1], "steel"), cube([5.5, 17, 5.5], [1, 3, 1], "steel")]),
    bone("caps", [cube([-10, 2, -5], [2.5, 7, 3], "accent"), cube([7.5, 2, -5], [2.5, 7, 3], "accent"), cube([-10, 2, 1], [2.5, 7, 3], "accent"), cube([7.5, 2, 1], [2.5, 7, 3], "accent")]),
    bone("core", [cube([-2, 19, -2], [4, 4, 4], "core", { full: true })]),
  ],
};

// ---------------------------------------------------------------------------
// Генераторы
// ---------------------------------------------------------------------------
export const COAL_GENERATOR = {
  id: "geometry.techcore.coal_generator",
  bones: [
    bone("body", [
      cube([-8, 0, -8], [16, 2, 16], "frame"),
      cube([-7, 2, -6], [14, 10, 12], { all: "panel", east: "vent", up: "steel" }),
      cube([-4, 3, 6], [8, 1, 1], "frame"),
      cube([-4, 8, 6], [8, 1, 1], "frame"),
      cube([-4, 4, 6], [1, 4, 1], "frame"),
      cube([3, 4, 6], [1, 4, 1], "frame"),
      cube([-3, 4, 6.2], [6, 4, 0.5], "fire", { full: true }),
      cube([2, 12, -5], [3, 8, 3], "steel"),
      cube([1.5, 20, -5.5], [4, 1, 4], "frame"),
      cube([-8.5, 4, -3], [1.5, 6, 6], "copper"),
      cube([-5, 12, -3], [5, 2, 5], "frame"),
      LED(5, 10),
    ]),
  ],
};

function pistons(name, high) {
  const cubes = [];
  [-3.5, -0.5, 2.5].forEach((x, i) => {
    const up = (i % 2 === 0) === high;
    cubes.push(cube([x, 9, -1.5], [1.5, up ? 3 : 1.5, 1.5], "steel"));
  });
  return bone(name, cubes);
}

export const DIESEL_GENERATOR = {
  id: "geometry.techcore.diesel_generator",
  bones: [
    bone("body", [
      cube([-8, 0, -7], [16, 1, 2], "hazard"),
      cube([-8, 0, 5], [16, 1, 2], "hazard"),
      cube([-7, 1, -7], [14, 1, 14], "steel"),
      cube([-5, 2, -5], [9, 7, 9], { all: "panel", east: "vent", west: "vent" }),
      cube([-6, 2, 4], [12, 8, 2.5], { all: "frame", south: "vent" }),
      cube([-4.5, 9, -2.5], [8, 1, 3.5], "frame"),
      cube([4.5, 8, -5], [2, 9, 2], "steel"),
      cube([4, 15, -5.5], [3, 2, 3], "frame"),
      cube([-8, 2, -5], [3, 5, 8], "tank"),
      LED(4, 7.5, 6.5),
    ]),
    pistons("pist_a", true),
    pistons("pist_b", false),
  ],
};

export const GASOLINE_GENERATOR = {
  id: "geometry.techcore.gasoline_generator",
  bones: [
    bone("body", [
      cube([-7, 0, -7], [1, 11, 1], "frame"),
      cube([6, 0, -7], [1, 11, 1], "frame"),
      cube([-7, 0, 6], [1, 11, 1], "frame"),
      cube([6, 0, 6], [1, 11, 1], "frame"),
      cube([-7, 0, -6], [1, 1, 12], "frame"),
      cube([6, 0, -6], [1, 1, 12], "frame"),
      cube([-7, 11, -7], [14, 1, 1], "frame"),
      cube([-7, 11, 6], [14, 1, 1], "frame"),
      cube([-5, 1, -4], [7, 6, 8], { all: "panel", north: "vent" }),
      cube([2, 1.5, -3], [4, 5, 6], "copper"),
      cube([-5, 7, -4], [10, 3, 8], "tank"),
      cube([-1, 10, -1], [2, 1, 2], "steel"),
      LED(3.5, 3, 3),
    ]),
    bone("pist_a", [cube([-4, 7, 4], [1.5, 2, 1.5], "steel")]),
    bone("pist_b", [cube([-4, 7, 4], [1.5, 1, 1.5], "steel")]),
  ],
};

export const BIO_GENERATOR = {
  id: "geometry.techcore.bio_generator",
  bones: [
    bone("body", [
      cube([-8, 0, -8], [16, 1, 16], "frame"),
      cube([-7, 1, -6], [7, 13, 7], "glass", { full: ["north", "south", "east", "west"] }),
      cube([-7.5, 14, -6.5], [8, 1, 8], "frame"),
      cube([-7.5, 1, -6.5], [8, 1, 8], "frame"),
      cube([1, 1, -5], [6, 7, 10], { all: "panel", east: "vent" }),
      cube([-1, 10, -3], [5, 1, 1], "copper"),
      cube([3, 8, -3], [1, 3, 1], "copper"),
      cube([-6, 1, 3], [5, 4, 4], "tank"),
      LED(4, 5, 5),
    ]),
    bone("pist_a", [cube([3, 8, 2], [2, 2.5, 2], "steel")]),
    bone("pist_b", [cube([3, 8, 2], [2, 1, 2], "steel")]),
  ],
};

/** Ветрогенератор: одна модель с костями частей мультиблока. */
export function windTurbine(tier, parts, rotor) {
  const t = { 1: 2, 2: 3, 3: 3, 4: 4, 5: 4 }[tier];
  const mastMat = tier >= 3 ? "tank" : "steel";
  const half = t / 2;
  const mast = (y0, h) => cube([-half, y0, -half], [t, h, t], mastMat);
  const bandTop = tier >= 4 ? [cube([-half - 0.25, 2, -half - 0.25], [t + 0.5, 1, t + 0.5], "hazard")] : [];
  const r = rotor / 2;
  return {
    id: `geometry.techcore.wind_turbine_${tier}`,
    parts,
    bones: [
      bone("foundation", [cube([-6, 0, -6], [12, 2, 12], "frame"), cube([-4, 2, -4], [8, 1, 8], "hazard"), mast(3, 13)]),
      bone("mast_mid", [mast(0, 16), ...bandTop]),
      bone("mast_top", [mast(0, 6)]),
      bone("nacelle", [
        cube([-2.5, 6, -6], [5, 5, 11], { all: "panel", up: "steel" }),
        cube([-0.5, 7, -9], [1, 4, 3], "panel"),
        cube([-1.5, 7, 5], [3, 3, 2.5], "steel"),
        cube([-1, 11, -3], [2, 0.5, 2], "led", { full: true }),
      ]),
      bone("rotor", [cube([-r, 8.5 - r, 8], [rotor, rotor, 0], "rotor", { full: true, faces: ["south"] })]),
    ],
  };
}

/** Уменьшенная модель ветрогенератора для отображения предмета. */
export function windTurbineItem(tier) {
  return {
    id: `geometry.techcore.wind_turbine_${tier}_item`,
    bones: [
      bone("all", [
        cube([-3, 0, -3], [6, 1, 6], "frame"),
        cube([-0.5, 1, -0.5], [1, 9, 1], tier >= 3 ? "tank" : "steel"),
        cube([-1, 10, -2.5], [2, 2, 4.5], "panel"),
        cube([-6, 5, 2.2], [12, 12, 0], "rotor", { full: true, faces: ["south"] }),
      ]),
    ],
  };
}

// ---------------------------------------------------------------------------
// Аккумуляторы
// ---------------------------------------------------------------------------
export function battery(advanced) {
  const cubes = [
    cube([-7, 0, -7], [14, 15, 14], { all: "frame", east: "vent", west: "vent", up: "steel" }),
    cube([-5, 2, 7], [10, 11, 0.5], "level", { full: true }),
    cube([-5, 15, -2], [2, 2, 2], "copper"),
    cube([3, 15, -2], [2, 2, 2], "copper"),
    cube([-7.5, 4, -7.5], [15, 1, 15], "accent"),
  ];
  if (advanced) {
    for (let z = -6; z <= 4; z += 2.5) {
      cubes.push(cube([-9, 2, z], [2, 11, 1], "steel"));
      cubes.push(cube([7, 2, z], [2, 11, 1], "steel"));
    }
    cubes.push(cube([-1, 15, -1], [2, 3, 2], "core", { full: true }));
  }
  return { id: `geometry.techcore.battery_${advanced ? "advanced" : "basic"}`, bones: [bone("body", cubes)] };
}

// ---------------------------------------------------------------------------
// Провода и трубы
// ---------------------------------------------------------------------------
export function connector(id, size, material, flange) {
  const h = size / 2;
  const arm = (name, o, s) => bone(name, [cube(o, s, material)]);
  const bones = [
    bone("core", [cube([-h, 8 - h, -h], [size, size, size], material)]),
    arm("arm_n", [-h, 8 - h, -8], [size, size, 8 - h]),
    arm("arm_s", [-h, 8 - h, h], [size, size, 8 - h]),
    arm("arm_e", [h, 8 - h, -h], [8 - h, size, size]),
    arm("arm_w", [-8, 8 - h, -h], [8 - h, size, size]),
    arm("arm_u", [-h, 8 + h, -h], [size, 8 - h, size]),
    arm("arm_d", [-h, 0, -h], [size, 8 - h, size]),
  ];
  if (flange) {
    const f = h + 1;
    bones[1].cubes.push(cube([-f, 8 - f, -8], [f * 2, f * 2, 1], flange));
    bones[2].cubes.push(cube([-f, 8 - f, 7], [f * 2, f * 2, 1], flange));
    bones[3].cubes.push(cube([7, 8 - f, -f], [1, f * 2, f * 2], flange));
    bones[4].cubes.push(cube([-8, 8 - f, -f], [1, f * 2, f * 2], flange));
    bones[5].cubes.push(cube([-f, 15, -f], [f * 2, 1, f * 2], flange));
    bones[6].cubes.push(cube([-f, 0, -f], [f * 2, 1, f * 2], flange));
  }
  return { id, bones };
}

// ---------------------------------------------------------------------------
// Производственные машины
// ---------------------------------------------------------------------------
export const DRILL_RIG = {
  id: "geometry.techcore.drill_rig",
  bones: [
    bone("frame", [
      cube([-8, 0, -8], [16, 2, 6], { all: "frame", up: "hazard" }),
      cube([-8, 0, 2], [16, 2, 6], { all: "frame", up: "hazard" }),
      cube([-8, 0, -2], [6, 2, 4], { all: "frame", up: "hazard" }),
      cube([2, 0, -2], [6, 2, 4], { all: "frame", up: "hazard" }),
      cube([-8, 2, -8], [2, 13, 2], "frame"),
      cube([6, 2, -8], [2, 13, 2], "frame"),
      cube([-8, 2, 6], [2, 13, 2], "frame"),
      cube([6, 2, 6], [2, 13, 2], "frame"),
      cube([-8, 15, -8], [16, 1, 2], "steel"),
      cube([-8, 15, 6], [16, 1, 2], "steel"),
      cube([-8, 15, -6], [2, 1, 12], "steel"),
      cube([6, 15, -6], [2, 1, 12], "steel"),
      cube([-3, 15, -3], [6, 6, 6], { all: "panel", south: "vent", up: "steel" }),
      cube([-6, 15.5, -1], [3, 1, 2], "steel"),
      cube([3, 15.5, -1], [3, 1, 2], "steel"),
      LED(1, 19, 3.2),
      cube([-7.5, 8, -7.5], [15, 0.5, 0.5], "hazard"),
      cube([-7.5, 8, 7], [15, 0.5, 0.5], "hazard"),
    ]),
    bone("drill_up", [cube([-1, 5, -1], [2, 10, 2], "work"), cube([-1.5, 3, -1.5], [3, 2, 3], "steel"), cube([-0.5, 2, -0.5], [1, 1, 1], "steel")]),
    bone("drill_down", [cube([-1, 1, -1], [2, 14, 2], "work"), cube([-1.5, -1, -1.5], [3, 2, 3], "steel"), cube([-0.5, -2, -0.5], [1, 1, 1], "steel")]),
  ],
};

export const CRUSHER = {
  id: "geometry.techcore.crusher",
  bones: [
    bone("body", [
      cube([-7, 0, -7], [14, 2, 14], "frame"),
      cube([-7, 2, -7], [14, 7, 14], { all: "panel", west: "vent" }),
      cube([-7, 9, -7], [14, 4, 1], "steel"),
      cube([-7, 9, 6], [14, 4, 1], "steel"),
      cube([-7, 9, -6], [1, 4, 12], "steel"),
      cube([6, 9, -6], [1, 4, 12], "steel"),
      cube([-6, 8.5, -6], [12, 0.5, 12], "frame"),
      cube([-8, 12, -8], [16, 1, 1], "hazard"),
      cube([-8, 12, 7], [16, 1, 1], "hazard"),
      cube([-2, 2, 7], [4, 3, 1.5], "frame"),
      cube([7, 3, -3], [1.5, 5, 6], "copper"),
      LED(4, 7),
    ]),
    bone("rollers", [cube([-5.5, 8.5, -5], [5, 2, 10], "work"), cube([0.5, 8.5, -5], [5, 2, 10], "work")]),
  ],
};

export const ELECTRIC_SMELTER = {
  id: "geometry.techcore.electric_smelter",
  bones: [
    bone("body", [
      cube([-8, 0, -8], [16, 1, 16], "frame"),
      cube([-7, 1, -7], [14, 12, 14], { all: "insul", up: "steel" }),
      cube([-5, 2.5, 7], [10, 7, 0.4], "frame"),
      cube([-4, 3, 7.2], [8, 6, 0.4], "work", { full: true }),
      cube([-1, 13, -1], [2, 5, 2], "steel"),
      cube([-3, 13.5, -3], [6, 1, 6], "copper"),
      cube([-3, 15, -3], [6, 1, 6], "copper"),
      cube([-3, 16.5, -3], [6, 1, 6], "copper"),
      cube([-7.5, 1, -7.5], [1, 12, 1], "frame"),
      cube([6.5, 1, -7.5], [1, 12, 1], "frame"),
      cube([-7.5, 1, 6.5], [1, 12, 1], "frame"),
      cube([6.5, 1, 6.5], [1, 12, 1], "frame"),
      LED(4.5, 10.5),
    ]),
  ],
};

export const PRESS = {
  id: "geometry.techcore.press",
  bones: [
    bone("frame", [
      cube([-7, 0, -7], [14, 3, 14], "frame"),
      cube([-5, 3, -5], [10, 1, 10], "steel"),
      cube([-7, 3, -2.5], [2.5, 13, 5], { all: "frame", south: "panel" }),
      cube([4.5, 3, -2.5], [2.5, 13, 5], { all: "frame", south: "panel" }),
      cube([-7, 15, -3], [14, 1.5, 6], "steel"),
      cube([-2, 16.5, -2], [4, 4, 4], { all: "steel", up: "frame" }),
      cube([-4.5, 7, 2.6], [2, 0.5, 0.5], "hazard"),
      LED(5, 12, 2.6),
    ]),
    bone("head_up", [cube([-1, 10.5, -1], [2, 4.5, 2], "steel"), cube([-4, 9, -4], [8, 1.5, 8], { all: "steel", north: "hazard", south: "hazard", east: "hazard", west: "hazard" })]),
    bone("head_down", [cube([-1, 5.5, -1], [2, 9.5, 2], "steel"), cube([-4, 4, -4], [8, 1.5, 8], { all: "steel", north: "hazard", south: "hazard", east: "hazard", west: "hazard" })]),
  ],
};

export const LATHE = {
  id: "geometry.techcore.lathe",
  bones: [
    bone("body", [
      cube([-7, 0, -4], [2, 6, 8], "frame"),
      cube([5, 0, -4], [2, 6, 8], "frame"),
      cube([-8, 6, -4.5], [16, 2, 9], "steel"),
      cube([-8, 8, -4], [5, 6, 8], { all: "panel", south: "vent" }),
      cube([-3, 9.5, -1.5], [1.5, 3, 3], "steel"),
      cube([5.5, 8, -2.5], [2.5, 5, 5], "panel"),
      cube([4.5, 10, -0.5], [1, 1, 1], "steel"),
      cube([1, 8, 1.5], [2, 3, 2], "frame"),
      cube([1.5, 10.5, 0.5], [1, 1, 1.5], "gold"),
      cube([-8, 5, 4], [16, 1, 0.5], "hazard"),
      LED(-6.5, 12, 4),
    ]),
    bone("spindle", [cube([-1.5, 10, -1], [6, 2, 2], "work")]),
  ],
};

export const FUEL_REFINERY = {
  id: "geometry.techcore.fuel_refinery",
  bones: [
    bone("body", [
      cube([-8, 0, -8], [16, 2, 16], { all: "frame", up: "hazard" }),
      cube([-6, 2, -6], [6, 14, 6], "tank_white"),
      cube([-5.5, 16, -5.5], [5, 3, 5], "steel"),
      cube([-6.5, 6, -6.5], [7, 1, 7], "frame"),
      cube([-6.5, 11, -6.5], [7, 1, 7], "frame"),
      cube([1, 2, 0], [6, 9, 6], { all: "tank", south: "window" }, { full: ["south"] }),
      cube([1, 2, -7], [6, 5, 6], { all: "panel", south: "vent" }),
      cube([1.5, 3, -1.2], [5, 3, 0.4], "work", { full: true }),
      cube([0, 13, -3.5], [4, 1, 1], "copper"),
      cube([3.5, 11, -3.5], [1, 3, 1], "copper"),
      cube([-3.5, 19, -3.5], [1, 3, 1], "steel"),
      LED(-2, 3, 7),
    ]),
  ],
};

// ---------------------------------------------------------------------------
// Транспорт
// ---------------------------------------------------------------------------
function beltBase(extra = []) {
  return [
    cube([-8, 0, -8], [2, 4, 16], "frame"),
    cube([6, 0, -8], [2, 4, 16], "frame"),
    cube([-6, 1.5, -8], [12, 1.5, 16], { all: "rubber", up: "belt" }, { full: ["up"] }),
    cube([-6, 0.5, -8], [12, 1, 1], "steel"),
    cube([-6, 0.5, 7], [12, 1, 1], "hazard"),
    // Шевроны направления (+z) на рельсах
    cube([-7.5, 4, 2], [0.5, 0.3, 2.5], "hazard", { rot: [0, 22.5, 0] }),
    cube([-7, 4, 2], [0.5, 0.3, 2.5], "hazard", { rot: [0, -22.5, 0] }),
    cube([6.5, 4, 2], [0.5, 0.3, 2.5], "hazard", { rot: [0, 22.5, 0] }),
    cube([7, 4, 2], [0.5, 0.3, 2.5], "hazard", { rot: [0, -22.5, 0] }),
    ...extra,
  ];
}

const CARGO = bone("cargo", [cube([-3, 3, -3], [6, 5, 6], "cargo")]);

export const CONVEYOR = { id: "geometry.techcore.conveyor", bones: [bone("belt", beltBase()), CARGO] };

export const ITEM_FILTER = {
  id: "geometry.techcore.item_filter",
  bones: [
    bone("belt", [
      cube([6, 0, -8], [2, 4, 16], "frame"),
      cube([-8, 0, -8], [2, 4, 5], "frame"),
      cube([-8, 0, 3], [2, 4, 5], "frame"),
      cube([-8, 1.5, -3], [2, 1, 6], "hazard"),
      cube([-6, 1.5, -8], [12, 1.5, 16], { all: "rubber", up: "belt" }, { full: ["up"] }),
      cube([-6, 0.5, 7], [12, 1, 1], "hazard"),
      cube([-7, 4, 4], [1, 7, 2], "frame"),
      cube([6, 4, 4], [1, 7, 2], "frame"),
      cube([-7, 11, 4], [14, 2, 2], { all: "frame", south: "screen" }, { full: ["south"] }),
      cube([-5, 10.5, 4.5], [10, 0.5, 1], "steel"),
    ]),
    CARGO,
  ],
};

export const SPLITTER = {
  id: "geometry.techcore.splitter",
  bones: [
    bone("body", [
      cube([-8, 0, -8], [16, 3, 16], { all: "frame", up: "belt" }, { full: ["up"] }),
      cube([-8, 3, -8], [5, 2, 5], "steel"),
      cube([3, 3, -8], [5, 2, 5], "steel"),
      cube([-8, 0, 6], [16, 1, 2], "hazard"),
      cube([-8, 0.5, -3], [1, 1, 6], "hazard"),
      cube([7, 0.5, -3], [1, 1, 6], "hazard"),
      cube([-1, 3, -1], [2, 4, 2], "steel"),
    ]),
    bone("vane_a", [cube([-3, 4, -0.5], [6, 2, 1], "copper")]),
    bone("vane_b", [cube([-0.5, 4, -3], [1, 2, 6], "copper")]),
    CARGO,
  ],
};

export const BUFFER_CRATE = {
  id: "geometry.techcore.buffer_crate",
  bones: [
    bone("body", [
      cube([-7, 0, -7], [14, 13, 14], "crate", { full: true }),
      cube([-7.5, 13, -7.5], [15, 1.5, 15], "frame"),
      cube([-7.5, 0, -7.5], [1.5, 13, 1.5], "steel"),
      cube([6, 0, -7.5], [1.5, 13, 1.5], "steel"),
      cube([-7.5, 0, 6], [1.5, 13, 1.5], "steel"),
      cube([6, 0, 6], [1.5, 13, 1.5], "steel"),
      cube([-2, 14.5, -2], [4, 1, 4], "steel"),
    ]),
  ],
};

export const FUEL_TANK = {
  id: "geometry.techcore.fuel_tank",
  bones: [
    bone("body", [
      cube([-7, 0, -7], [14, 1, 14], "frame"),
      cube([-6, 1, -6], [12, 14, 12], "tank_white"),
      cube([-7, 2, -5], [14, 12, 10], "tank_white"),
      cube([-5, 2, -7], [10, 12, 14], "tank_white"),
      cube([-5, 15, -5], [10, 1, 10], "steel"),
      cube([-1, 16, -1], [2, 1.5, 2], "steel"),
      cube([-2, 3, 7.05], [4, 10, 0.3], "window", { full: true }),
    ]),
  ],
};

/** Все модели: имя → модель. */
export function allModels() {
  const m = {
    ultimate_assembler: ASSEMBLER,
    coal_generator: COAL_GENERATOR,
    diesel_generator: DIESEL_GENERATOR,
    gasoline_generator: GASOLINE_GENERATOR,
    bio_generator: BIO_GENERATOR,
    battery_basic: battery(false),
    battery_advanced: battery(true),
    copper_wire: connector("geometry.techcore.copper_wire", 2, "wire"),
    insulated_wire: connector("geometry.techcore.insulated_wire", 4, "wire"),
    reinforced_wire: connector("geometry.techcore.reinforced_wire", 4, "wire", "steel"),
    superconductor_wire: connector("geometry.techcore.superconductor_wire", 3, "wire", "steel"),
    fluid_pipe: connector("geometry.techcore.fluid_pipe", 6, "pipe", "frame"),
    drill_rig: DRILL_RIG,
    crusher: CRUSHER,
    electric_smelter: ELECTRIC_SMELTER,
    press: PRESS,
    lathe: LATHE,
    fuel_refinery: FUEL_REFINERY,
    conveyor: CONVEYOR,
    item_filter: ITEM_FILTER,
    splitter: SPLITTER,
    buffer_crate: BUFFER_CRATE,
    fuel_tank: FUEL_TANK,
  };
  const spec = { 1: [2, 18], 2: [2, 22], 3: [3, 26], 4: [3, 28], 5: [4, 30] };
  for (let t = 1; t <= 5; t++) {
    m[`wind_turbine_${t}`] = windTurbine(t, spec[t][0], spec[t][1]);
    m[`wind_turbine_${t}_item`] = windTurbineItem(t);
  }
  return m;
}
