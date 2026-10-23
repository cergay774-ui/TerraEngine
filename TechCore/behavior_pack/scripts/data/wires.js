// Проводники энергии и трубы.
// capacity — максимальная мощность, которую путь через этот провод может доставить потребителю, E/с.
// loss     — доля энергии, теряемая на каждом блоке провода.

export const WIRES = {
  "techcore:copper_wire": { capacity: 64, loss: 0.004 },
  "techcore:insulated_wire": { capacity: 256, loss: 0.0015 },
  "techcore:reinforced_wire": { capacity: 1024, loss: 0.0005 },
  "techcore:superconductor_wire": { capacity: 8192, loss: 0.00005 },
};

export const PIPES = {
  // Пропускная способность одной трубной сети, мБ/с.
  "techcore:fluid_pipe": { throughput: 200 },
};

// Внутренний резервуар (блок).
export const FUEL_TANK = { capacity: 16000 };
