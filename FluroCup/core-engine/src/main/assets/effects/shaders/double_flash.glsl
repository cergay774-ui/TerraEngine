vec4 effect(vec2 uv) {
  float f = max(exp(-abs(uProgress - 0.1) * 30.0), exp(-abs(uProgress - 0.35) * 30.0)) * u_intensity;
  vec4 c = tex(uv);
  c.rgb = mix(c.rgb, vec3(1.0), f);
  return c;
}
