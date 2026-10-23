vec4 effect(vec2 uv) {
  float band = 0.1;
  if (uv.x > band && uv.x < 1.0 - band) return tex(vec2((uv.x - band) / (1.0 - 2.0 * band), uv.y));
  float x = uv.x < band ? uv.x / band : (1.0 - uv.x) / band;
  float y = fract(uv.y * 10.0 + uTime * 0.6) - 0.5;
  float hole = fill(sdBox(vec2(x - 0.5, y * 0.5 * aspect() * 2.0 * band * 10.0), vec2(0.22, 0.18)) - 0.05, 0.02);
  return vec4(mix(u_color, vec3(0.92), hole), 1.0);
}
