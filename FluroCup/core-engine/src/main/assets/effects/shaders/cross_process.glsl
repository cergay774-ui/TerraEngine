vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  vec3 x = vec3(smoothstep(0.1, 0.9, c.r), c.g * 1.1 - 0.03, c.b * 0.75 + 0.12);
  c.rgb = mix(c.rgb, clamp(x, 0.0, 1.0), u_intensity);
  return c;
}
