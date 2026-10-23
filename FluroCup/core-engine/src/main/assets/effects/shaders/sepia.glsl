vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  vec3 s = vec3(dot(c.rgb, vec3(0.393, 0.769, 0.189)), dot(c.rgb, vec3(0.349, 0.686, 0.168)), dot(c.rgb, vec3(0.272, 0.534, 0.131)));
  c.rgb = mix(c.rgb, clamp(s, 0.0, 1.0), u_intensity);
  return c;
}
