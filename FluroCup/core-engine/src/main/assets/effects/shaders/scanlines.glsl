vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  float line = 0.5 + 0.5 * sin(uv.y * uSize.y * PI / u_density);
  c.rgb *= 1.0 - u_strength * 0.6 * line;
  return c;
}
