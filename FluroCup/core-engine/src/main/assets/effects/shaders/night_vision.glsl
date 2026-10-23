vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  float l = luma(c.rgb) * 1.8;
  l += (hash21(uv * uSize + floor(uTime * 30.0)) - 0.5) * 0.2;
  l *= 0.9 + 0.1 * sin(uv.y * uSize.y * 1.2);
  l *= 1.0 - smoothstep(0.35, 0.6, length(toCentered(uv)));
  c.rgb = mix(c.rgb, vec3(0.1, 1.0, 0.2) * clamp(l, 0.0, 1.0), u_intensity);
  return c;
}
