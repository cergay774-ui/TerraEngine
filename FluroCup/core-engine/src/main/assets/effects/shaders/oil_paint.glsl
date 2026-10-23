vec4 effect(vec2 uv) {
  // Kuwahara filter: the average of the calmest of four quadrants.
  vec3 m0 = vec3(0.0); vec3 m1 = vec3(0.0); vec3 m2 = vec3(0.0); vec3 m3 = vec3(0.0);
  vec3 s0 = vec3(0.0); vec3 s1 = vec3(0.0); vec3 s2 = vec3(0.0); vec3 s3 = vec3(0.0);
  for (int j = 0; j < 3; j++) {
    for (int i = 0; i < 3; i++) {
      vec2 o = vec2(float(i), float(j)) * u_radius / 2.0 * px();
      vec3 a = tex(uv - o).rgb;
      vec3 b = tex(uv + vec2(o.x, -o.y)).rgb;
      vec3 c = tex(uv + vec2(-o.x, o.y)).rgb;
      vec3 d = tex(uv + o).rgb;
      m0 += a; s0 += a * a;
      m1 += b; s1 += b * b;
      m2 += c; s2 += c * c;
      m3 += d; s3 += d * d;
    }
  }
  m0 /= 9.0; m1 /= 9.0; m2 /= 9.0; m3 /= 9.0;
  vec3 v0 = abs(s0 / 9.0 - m0 * m0); vec3 v1 = abs(s1 / 9.0 - m1 * m1);
  vec3 v2 = abs(s2 / 9.0 - m2 * m2); vec3 v3 = abs(s3 / 9.0 - m3 * m3);
  float e0 = v0.r + v0.g + v0.b; float e1 = v1.r + v1.g + v1.b;
  float e2 = v2.r + v2.g + v2.b; float e3 = v3.r + v3.g + v3.b;
  vec3 best = m0; float bv = e0;
  if (e1 < bv) { bv = e1; best = m1; }
  if (e2 < bv) { bv = e2; best = m2; }
  if (e3 < bv) { best = m3; }
  vec4 c = tex(uv);
  c.rgb = mix(c.rgb, best, u_intensity);
  return c;
}
