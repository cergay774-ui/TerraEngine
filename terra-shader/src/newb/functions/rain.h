#ifndef RAIN_H
#define RAIN_H

#include "clouds.h"
#include "detection.h"
#include "noise.h"
#include "sky.h"
#include "water.h"

// t: wrapped time
float nlWindblow(vec3 pos, float t){
  vec2 p = pos.xy/(1.0+pos.z);
  float val = sin(4.0*p.x + 2.0*p.y + NL_SNAP_W(2.0)*t + 3.0*p.y*p.x)*sin(p.y*2.0 + NL_SNAP_W(0.2)*t);
  val += sin(p.y - p.x + NL_SNAP_W(0.2)*t);
  return 0.25*val*val;
}

// Per vertex wet ground + sky reflection (cheap fallback, used when TS_PUDDLES is off).
// t: raw time (cloud reflection must match sky clouds)
vec4 nlRefl(
  inout vec4 color, nl_skycolor skycol, nl_environment env, vec3 viewDir, vec3 wPos, vec3 tiledCpos,
  vec3 CAMERA_POS, vec3 torchColor, vec2 lit, float camDist, float renderDist, highp float t
) {
  vec4 wetRefl = vec4(0.0,0.0,0.0,0.0);

  #ifndef NL_GROUND_REFL
  if (env.rainFactor > 0.0) {
  #endif

    float wetness = lit.y*lit.y;

    // clip reflection when far (better performance)
    float endDist = renderDist*0.6;
    if (camDist < endDist) {
      float cosR = max(viewDir.y, 0.0);
      float puddles = max(1.0 - NL_GROUND_RAIN_PUDDLES*fastRand(tiledCpos.xz), 0.0);

      #ifndef NL_GROUND_REFL
        wetness *= puddles;
        float reflective = wetness*env.rainFactor*NL_GROUND_RAIN_WETNESS;
      #else
        float reflective = NL_GROUND_REFL;
        if (!env.end && !env.nether) {
          // only multiply with wetness in overworld
          reflective *= wetness;
        } 

        wetness *= puddles;
        reflective = mix(reflective, wetness, env.rainFactor);
      #endif

      if (wPos.y < 0.0) {
        viewDir.y = -viewDir.y;
        wetRefl.rgb = nlRenderSky(skycol, env, viewDir, t, false);

        #ifdef NL_CLOUD_AURORA_REFLECTION
          vec4 cloudRefl = nlCloudAuroraReflection(skycol, env, viewDir, wPos, CAMERA_POS, t);
          wetRefl.rgb = mix(wetRefl.rgb, cloudRefl.rgb, cloudRefl.a);
        #endif

        // torch light
        wetRefl.rgb += torchColor*lit.x*NL_TORCHLIGHT_INTENSITY;

        wetRefl.a = calculateFresnel(cosR, 0.03)*reflective;
        wetRefl.a *= clamp(2.0-2.0*camDist/endDist, 0.0, 1.0); // fade out before clip
      }
    }

    // darken wet parts
    color.rgb *= 1.0 - 0.4*wetness*env.rainFactor;

  #ifndef NL_GROUND_REFL
  }
  #endif

  return wetRefl;
}

/*
  RAIN PUDDLES (TS_PUDDLES, per pixel)

  - Rain: env.rainFactor, detected from fog parameters (upstream Newb).
  - Where: only up-facing surfaces (geometric normal from screen derivatives)
    under open sky (skylight lightmap at maximum), so it stays dry under roofs.
  - Shape: a "height field" of world noise in three scales plus a large
    regional term. Puddles are the parts of the field above a water level
    that rises with rain intensity. Because every local maximum of the field
    has a different height, every puddle has its own threshold: puddles
    appear one by one as rain gets stronger and dry out one by one (shrinking
    from the edges) while the game fades the rain out.
  - Everything is world locked (wrapped world position, periodic noise).
  - Inside: Fresnel sky reflection (+ optional clouds), animated drop rings.
    Around: darkened wet rim. Lighting: reflection is masked by skylight,
    torch light is reflected, nothing is emissive by itself.
*/

#if TS_PUDDLES

// puddle height field [~0,1]. p: wrapped world xz
// (NL_PUDDLE_SIZE must be 0.5, 1.0 or 2.0 to stay seamless across NL_WORLD_WRAP)
float nlPuddleField(highp vec2 p) {
  float n = 0.55*nlWorldNoise(p, 8.0*NL_PUDDLE_SIZE);
  n += 0.30*nlWorldNoise(p + 31.0, 4.0*NL_PUDDLE_SIZE);
  n += 0.15*nlWorldNoise(p + 57.0, 2.0*NL_PUDDLE_SIZE);
  float region = nlWorldNoise(p + 101.0, 32.0*NL_PUDDLE_SIZE);
  return 0.8*n + 0.35*region - 0.15;
}

// x: puddle mask, y: wet rim mask
vec2 nlPuddleMask(highp vec2 p, float rain) {
  // water level: rises quickly with rain, falls with it -> gradual drying
  float level = smoothstep(0.05, 0.7, rain);
  float thr = mix(0.86, 0.80 - 0.6*NL_PUDDLE_COVERAGE, level);
  float h = nlPuddleField(p);
  float puddle = smoothstep(thr, thr + 0.025, h)*step(0.001, level);
  float rim = smoothstep(thr - NL_PUDDLE_WET_EDGE, thr, h)*level;
  return vec2(puddle, rim);
}

#if TS_PUDDLE_RIPPLES
// one layer of drop rings on a 1 block grid, returns xz normal offset
vec2 nlRippleLayer(highp vec2 p, highp float t, float rain, float seed) {
  highp vec2 cell = floor(p);
  vec3 h = nlHash32(mod(cell, vec2_splat(NL_WORLD_WRAP)) + seed);
  vec2 d = (p - cell) - (0.3 + 0.4*h.xy); // drop center stays inside the cell
  float r = length(d);

  // drop cycle, speed snapped so the time wrap is seamless
  float phase = fract(t*NL_SNAP_F(NL_PUDDLE_RIPPLE_SPEED) + h.z);
  float radius = 0.3*phase;
  float x = 30.0*(r - radius);
  float fade = (1.0 - phase)*(1.0 - phase);
  float wave = sin(3.0*x)*exp(-x*x)*fade;

  // fewer drops in light rain
  float dropOn = step(fract(7.31*h.x + 3.17*h.y), rain);
  return (d/max(r, 0.001))*(wave*dropOn);
}

vec2 nlRipples(highp vec2 p, highp float t, float rain) {
  vec2 n = nlRippleLayer(p, t, rain, 0.0);
  n += nlRippleLayer(p + vec2(0.5, 0.37), t, rain, 17.0);
  return NL_PUDDLE_RIPPLE_STRENGTH*n;
}
#endif // TS_PUDDLE_RIPPLES

#endif // TS_PUDDLES

#if TS_PUDDLES || TS_WET_GROUND
/*
  Wet ground (TS_WET_GROUND) and puddles (TS_PUDDLES), per pixel.
  diffuse: lit surface color (linear, before fog)
  gPos: wrapped world pos, wPos: camera relative pos, V: to camera
  geomN: geometric normal, uv1: lightmap uv, rain: rainFactor (0 outside overworld)
  t: wrapped time, tRaw: raw time
*/
vec3 nlPuddles(
  vec3 diffuse, highp vec3 gPos, highp vec3 wPos, vec3 V, vec3 geomN, vec2 uv1, float rain, float camDist,
  nl_skycolor skycol, nl_environment env, vec3 torchColor, vec3 CAMERA_POS, highp float t, highp float tRaw
) {
  float skyOpen = smoothstep(NL_PUDDLE_MIN_SKYLIGHT - 0.04, NL_PUDDLE_MIN_SKYLIGHT + 0.02, uv1.y);
  float exposure = rain*skyOpen;

  // all exposed faces get a bit darker in rain (walls too)
  #if TS_WET_GROUND
    diffuse *= 1.0 - 0.35*NL_PUDDLE_DARKEN*NL_GROUND_RAIN_WETNESS*exposure;
  #endif

  #if TS_PUDDLES
  float up = smoothstep(0.9, 0.98, geomN.y);
  float dist = smoothstep(TS_PUDDLE_DIST, 0.75*TS_PUDDLE_DIST, camDist);
  if (exposure*up*dist < 0.002) {
    return diffuse;
  }

  vec2 m = nlPuddleMask(gPos.xz, rain);
  float puddle = m.x*skyOpen*up*dist;
  float rim = m.y*skyOpen*up;

  // wet darkened rim (and the ground under the water)
  diffuse *= 1.0 - NL_PUDDLE_DARKEN*max(rim, puddle);

  if (puddle > 0.001) {
    vec3 N = vec3(0.0, 1.0, 0.0);
    #if TS_PUDDLE_RIPPLES
      vec2 rip = nlRipples(gPos.xz, t, rain);
      N = normalize(vec3(rip.x, 1.0, rip.y));
    #endif

    vec3 R = reflect(-V, N);
    vec3 refl = nlSkyReflection(skycol, env, R, wPos, CAMERA_POS, tRaw, 0.1, TS_PUDDLE_CLOUD_REFL != 0);
    refl = min(refl, vec3_splat(8.0));
    refl *= uv1.y*uv1.y;                                        // follows skylight
    refl += torchColor*(0.5*NL_TORCHLIGHT_INTENSITY*uv1.x*uv1.x*uv1.x); // torches reflect

    float F = calculateFresnel(max(dot(N, V), 0.0), 0.02);
    diffuse = mix(diffuse, refl, F*puddle);
  }
  #endif // TS_PUDDLES

  return diffuse;
}
#endif // TS_PUDDLES || TS_WET_GROUND

#endif
