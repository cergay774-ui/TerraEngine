vec4 effect(vec2 uv) {
  float on = step(0.5, fract(uTime * u_rate));
  vec4 c = tex(uv);
  c.rgb = mix(c.rgb, vec3(1.0), on * u_intensity);
  return c;
}
