#ifndef NOISE_H
#define NOISE_H

#include "utils.h"
#include "time.h"

// functions under [1] are from https://gist.github.com/patriciogonzalezvivo/670c22f3966e662d2f83

// [1] hash function for noise (for highp only)
float rand(highp vec2 n) {
  return fract(sin(dot(n, vec2(12.9898, 4.1414))) * 43758.5453);
}

// 1D noise - used in plants,lantern wave
float noise1D(highp float x) {
  float x0 = floor(x);
  float t0 = x-x0;
  t0 *= t0*(3.0-2.0*t0);
  return mix(fract(sin(x0)*84.85), fract(sin(x0+1.0)*84.85), t0);
}

// simpler rand
float fastRand(vec2 n){
  return fract(37.45*sin(dot(n, vec2(4.36, 8.28))));
}

// used by caustic
float disp(vec3 pos, float t) {
  float n = sin(8.0*PI_HALF*(pos.x+pos.y*pos.z) + 0.7*t);
  pos.y += t + 0.8*n;
  float p = floor(pos.y);
  return (0.8+0.2*n) * mix(fastRand(pos.xz+p), fastRand(pos.xz+p+1.0), pos.y - p);
}

// [1]
float noise2D(vec2 u) {
  vec2 u0 = floor(u);
  vec2 v = u-u0;
  v *= v*(3.0 - 2.0*v);
  float c0 = rand(u0);
  float c1 = rand(u0+vec2(1.0, 0.0));
  float c2 = rand(u0+vec2(1.0, 1.0));
  float c3 = rand(u0+vec2(0.0, 1.0));
  return mix(mix(c0, c3, v.y), mix(c1, c2, v.y), v.x);
}

vec4 mod289(vec4 x) {
  return x - floor(x * (1.0 / 289.0)) * 289.0;
}

vec4 perm(vec4 x) {
  return mod289(((x * 34.0) + 1.0) * x);
}

// [1] used by galaxy
float noise3D(vec3 p){
  vec3 a = floor(p);
  vec3 d = p - a;
  //d = d * d * (3.0 - 2.0 * d);

  vec4 b = a.xxyy + vec4(0.0, 1.0, 0.0, 1.0);
  vec4 k1 = perm(b.xyxy);
  vec4 k2 = perm(k1.xyxy + b.zzww);

  vec4 c = k2 + a.zzzz;
  vec4 k3 = perm(c);
  vec4 k4 = perm(c + 1.0);
  vec4 o1 = fract(k3 / 41.0);
  vec4 o2 = fract(k4 / 41.0);
  vec4 o3 = o2 * d.z + o1 * (1.0 - d.z);
  vec2 o4 = o3.yw * d.x + o3.xz * (1.0 - d.x);

  return o4.y * d.y + o4.x * (1.0 - d.y);
}

float fastVoronoi2(vec2 pos, float f) {
  vec4 p = pos.xyxy;
  p.zw += p.wz*vec2(0.4,0.5);
  p = fract(p) - 0.5;
  p *= p;
  return 1.0-f*min(p.x+p.y, p.z+p.w);
}

float movingNoise2D(vec2 pos, float t, float f) {
  vec2 tpos = 16.0*fract(pos/16.0);
  float nf0 = fastVoronoi2(0.125*pos.xy, 12.0);
  float nf2 = fastVoronoi2(0.04*pos.xy*vec2(0.5,1.0) + 0.5*nf0 + 0.05*t, 2.0);
  float n0 = sin(1.5*nf0*nf0 + pos.x - sin(pos.y) + t);
  float n1 = sin(0.05*(pos.x+pos.y) + 8.0*nf2 + 0.4*t);
  return mix(n0*n0, n1*n1, f);
}

// ---- Terra: sine-free hashes and periodic value noise ----
// hashes by Dave Hoskins (MIT, https://www.shadertoy.com/view/4djSRW)
// stable in highp for coordinates up to a few thousand (world pos is wrapped)
float nlHash12(highp vec2 p) {
  highp vec3 p3 = fract(vec3(p.x, p.y, p.x)*0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y)*p3.z);
}

vec3 nlHash32(highp vec2 p) {
  highp vec3 p3 = fract(vec3(p.x, p.y, p.x)*vec3(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yxz + 33.33);
  return fract((p3.xxy + p3.yzz)*p3.zyx);
}

// value noise [0,1], tiles every `period` lattice cells (period must be a whole number)
float nlNoiseP(highp vec2 p, float period) {
  highp vec2 i = floor(p);
  vec2 f = p - i;
  vec2 u = f*f*(3.0 - 2.0*f);
  highp vec2 i1 = mod(i + 1.0, vec2_splat(period));
  i = mod(i, vec2_splat(period));
  float a = nlHash12(i);
  float b = nlHash12(vec2(i1.x, i.y));
  float c = nlHash12(vec2(i.x, i1.y));
  float d = nlHash12(i1);
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// 3 independent value noise channels from one lattice (cheaper than 3 calls)
vec3 nlNoise3P(highp vec2 p, float period) {
  highp vec2 i = floor(p);
  vec2 f = p - i;
  vec2 u = f*f*(3.0 - 2.0*f);
  highp vec2 i1 = mod(i + 1.0, vec2_splat(period));
  i = mod(i, vec2_splat(period));
  vec3 a = nlHash32(i);
  vec3 b = nlHash32(vec2(i1.x, i.y));
  vec3 c = nlHash32(vec2(i.x, i1.y));
  vec3 d = nlHash32(i1);
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// world-space noise with feature size `cell` blocks, seamless across NL_WORLD_WRAP
// (cell must divide NL_WORLD_WRAP: 1, 2, 4, 8, 16, 32, 64...)
#define nlWorldNoise(p, cell) nlNoiseP((p)/(cell), NL_WORLD_WRAP/(cell))
#define nlWorldNoise3(p, cell) nlNoise3P((p)/(cell), NL_WORLD_WRAP/(cell))

#endif
