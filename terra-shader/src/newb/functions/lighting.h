#ifndef LIGHTING_H
#define LIGHTING_H

#include "detection.h"
#include "sky.h"
#include "utils.h"
#include "noise.h"
#include "clouds.h"

vec3 sunLightTint(float dayFactor, float duskFactor, float rain) {
  float nightFactor = step(dayFactor, 0.0);
  float dawnFactor = 1.0-dayFactor*dayFactor;
  dawnFactor *= dawnFactor*dawnFactor;
  dawnFactor *= mix(1.0, dawnFactor*dawnFactor, nightFactor);
  vec3 tint = mix(NL_NOON_SUNLIGHT_COL, NL_NIGHT_MOONLIGHT_COL, nightFactor);
  tint = mix(tint, mix(NL_DAWN_SUNLIGHT_COL, NL_DUSK_SUNLIGHT_COL, duskFactor), dawnFactor);
  tint = mix(tint, vec3_splat(dot(tint, vec3_splat(0.33))), rain);
  return tint;
}

vec3 nlTorchColor(nl_environment env) {
  if (env.underwater) {
    return NL_UNDERWATER_TORCH_COL;
  } else if (env.end) {
    return NL_END_TORCH_COL;
  } else if (env.nether) {
    return NL_NETHER_TORCH_COL;
  }
  return NL_OVERWORLD_TORCH_COL;
}

// directLight: part of the result that comes from the sun/moon (used for
// per pixel face shading). t: raw (unwrapped) time, cloud shadow must match sky clouds.
vec3 nlLighting(
  sampler2D tex, nl_skycolor skycol, nl_environment env, vec3 wPos, out vec3 torchColor, out vec3 directLight, vec3 COLOR,
  vec2 uv1, vec2 lit, bool isTree, float shade, highp float t, float renderdistance, float TIME_OF_DAY, vec3 CAMERA_POS
) {
  vec3 light;
  directLight = vec3(0.0, 0.0, 0.0);

  torchColor = nlTorchColor(env);

  float torchAttenuation = (NL_TORCHLIGHT_INTENSITY*uv1.x)/(0.5-0.45*lit.x);

  #ifdef NL_BLINKING_TORCH
    torchAttenuation *= 1.0 - 0.19*noise1D(t*8.0);
  #endif

  vec3 torchLight = torchColor*torchAttenuation;
  float gameBrightness = texelFetch(tex, ivec2(0,0), 0).g;
  float lum = 0.0;

  if (env.nether || env.end) {
    // nether & end lighting

    light = env.end ? NL_END_AMBIENT : NL_NETHER_AMBIENT;
    light *= gameBrightness;

    lum = luminance(light);
    light += skycol.horizon/(1.0+lum);

  } else {
    // overworld lighting
    float nightFactor = step(env.dayFactor, 0.0);
    float dawnFactor = 1.0-env.dayFactor*env.dayFactor;
    dawnFactor *= dawnFactor*dawnFactor;
    dawnFactor *= mix(1.0, dawnFactor*dawnFactor, nightFactor);
    float nightIntensity = 1.0-(0.5+0.5*env.dayFactor);
    nightIntensity *= nightIntensity;

    float sunLightAttenuation = clamp(0.5*(((2.0*step(TIME_OF_DAY, 0.5)-1.0)*(wPos.x*cos(NL_SUN_PATH_YAW)+wPos.y*sin(NL_SUN_PATH_YAW))/renderdistance) + 1.0), 0.0, 1.0);
    sunLightAttenuation = mix(1.0, sunLightAttenuation*sunLightAttenuation, dawnFactor);
    sunLightAttenuation *= 1.0-0.4*env.rainFactor;

    // shadow cast by sun light: soft edge from the skylight lightmap
    float shadow = smoothstep(0.93 - NL_SHADOW_SOFTNESS, 0.93, uv1.y);
    shadow = max(shadow, (1.0 - NL_SHADOW_INTENSITY + (0.6*NL_SHADOW_INTENSITY*nightIntensity))*lit.y);
    shadow *= shade > 0.8 ? 1.0 : 0.8;
    #if defined(NL_CLOUD_SHADOW) && (NL_CLOUD_TYPE == 1 || NL_CLOUD_TYPE == 2)
      vec3 mainLightDir = env.sunDir.y > 0.0 ? env.sunDir : env.moonDir;
      vec3 gPos = wPos + CAMERA_POS;
      float cloudRelativeHeight = gPos.y-187.0;
      vec2 projectionOffset = cloudRelativeHeight*mainLightDir.xz/mainLightDir.y;
      vec2 projectedPos = gPos.xz + projectionOffset;
      float cloudFade = smoothstep(1.0, 0.5, length(0.002*(wPos.xz + projectionOffset)));
      cloudFade *= (1.0-dawnFactor*dawnFactor)*clamp(-0.12*(cloudRelativeHeight-7.0), 0.0, 1.0);
      float cmask;
      #if NL_CLOUD_TYPE == 1
        // shadow cast by simple clouds
        cmask = cloudNoise2D(projectedPos*NL_CLOUD1_SCALE, t, env.rainFactor)*cloudFade;
      #elif NL_CLOUD_TYPE == 2
        // shadow cast by rounded clouds  
        projectedPos = NL_CLOUD2_SCALE * (projectedPos + vec2(1.0, 0.5) * (t * NL_CLOUD2_VELOCITY));
        cmask = cloudDf(vec3(projectedPos.x, 0.5, projectedPos.y), env.rainFactor, NL_CLOUD2_SHAPE)*cloudFade;
      #endif
      shadow *= 0.3 + 0.7*smoothstep(0.6, 0.0, cmask);
    #endif

    // direct light from top
    light = (NL_SUNLIGHT_INTENSITY*shadow*sunLightAttenuation)*sunLightTint(env.dayFactor, env.duskFactor, env.rainFactor);
    directLight = light;

    // sky ambient
    lum = luminance(light);
    light += (skycol.horizon + skycol.zenith)*(uv1.y/(1.0+lum));

  }

  // torch light
  lum = luminance(light);
  light += torchLight/(1.0+lum);

  // game min brightness
  if (!(env.nether || env.end)) {
    lum = luminance(light);
    light += vec3_splat(gameBrightness*(NL_MIN_LIGHTING_BOOST/(1.0+lum)));
  }

  // darken at crevices
  float k = COLOR.g > 0.35 ? 1.0 : 0.8;

  // brighten tree leaves
  if (isTree) {
    k *= 1.25;
  }

  directLight *= k;
  return light*k;
}

// caustics pattern [0,1]: thin bright moving lines, world locked and exactly
// periodic (space: NL_WORLD_WRAP, time: NL_TIME_LOOP). gPos: wrapped world pos, t: wrapped time
float nlCaustics(highp vec3 gPos, highp float t) {
  highp vec2 p = gPos.xz + 0.35*gPos.yy;
  float w1 = NL_SNAP_W(0.9*NL_WATER_WAVE_SPEED);
  float w2 = NL_SNAP_W(1.3*NL_WATER_WAVE_SPEED);
  highp vec2 q = p + 0.5*vec2(sin(NL_SNAP_K(1.1)*p.y + w1*t), sin(NL_SNAP_K(1.3)*p.x - w2*t));
  float v = sin(NL_SNAP_K(1.9)*q.x + sin(NL_SNAP_K(2.3)*q.y + w2*t));
  v += sin(NL_SNAP_K(2.1)*q.y + sin(NL_SNAP_K(1.7)*q.x - w1*t));
  float c = 1.0 - 0.5*abs(v);
  c *= c;
  c *= c;
  return c*c;
}

// gPos: wrapped world pos, t: wrapped time
void nlUnderwaterLighting(inout vec3 light, inout vec4 pos, vec2 lit, vec2 uv1, highp vec3 gPos, vec3 cPos, highp float t, vec3 horizonCol) {
  if (uv1.y < 0.9) {
    #if TS_CAUSTICS == 1
      float caustics = 2.0*nlCaustics(gPos, t);
    #else
      float caustics = 0.0; // per pixel caustics (TS_CAUSTICS == 2) are added in fragment
    #endif
    light += NL_UNDERWATER_BRIGHTNESS + NL_CAUSTIC_INTENSITY*caustics*(0.15 + lit.y + lit.x*0.7);
  }
  light *= mix(normalize(horizonCol), vec3_splat(0.6), lit.y*0.6);
  #ifdef NL_UNDERWATER_WAVE
    // light wobble of the whole view, phase is world locked
    pos.xy += NL_UNDERWATER_WAVE*min(0.05*pos.z,0.6)*sin(NL_SNAP_W(1.2)*t + dot(cPos,vec3_splat(PI_HALF)));
  #endif
}

vec3 nlEntityLighting(nl_skycolor skycol, nl_environment env, vec3 pos, vec4 normal, vec3 wPos, mat4 world, vec4 tileLightCol, vec4 overlayCol, vec3 horizonEdgeCol, float t, float TIME_OF_DAY, float renderdistance, vec3 CAMERA_POS) {
  float l = tileLightCol.b;
  float tl = tileLightCol.r;
  float lum;
  vec3 light;
  if (env.nether || env.end) {
    tl = max(tl-0.6, 0.0);
    tl *= 21.0*tl;

    // nether & end lighting
    light = env.end ? NL_END_AMBIENT : NL_NETHER_AMBIENT;
    light *= min(tileLightCol.b, 0.25);

    lum = luminance(light);
    light += skycol.horizon/(1.0+lum);
  } else {
    tl = max(tl-0.08, 0.0);
    tl *= 4.0*tl;

    float nightFactor = step(env.dayFactor, 0.0);
    float dawnFactor = 1.0-env.dayFactor*env.dayFactor;
    dawnFactor *= dawnFactor*dawnFactor;
    dawnFactor *= mix(1.0, dawnFactor*dawnFactor, nightFactor);
    float nightIntensity = 1.0-(0.5+0.5*env.dayFactor);
    nightIntensity *= nightIntensity;

    float sunLightAttenuation = clamp(0.5*(((2.0*step(TIME_OF_DAY, 0.5)-1.0)*(wPos.x*cos(NL_SUN_PATH_YAW)+wPos.y*sin(NL_SUN_PATH_YAW))/renderdistance) + 1.0), 0.0, 1.0);
    sunLightAttenuation = mix(1.0, sunLightAttenuation*sunLightAttenuation, dawnFactor);
    sunLightAttenuation *= 1.0-0.5*env.rainFactor;

    // direct light from top
    light = (NL_SUNLIGHT_INTENSITY*l*sunLightAttenuation)*sunLightTint(env.dayFactor, env.duskFactor, env.rainFactor);
    vec3 N = normalize(mul(world, normal)).xyz;
    light *= 0.9 + max(N.y, 0.0);

    // sky ambient
    lum = luminance(light);
    light += (skycol.horizon + skycol.zenith)*(l/(1.0+lum));
  }

  // torch light
  vec3 torchColor;
  if (env.underwater) {
    torchColor = NL_UNDERWATER_TORCH_COL;
  } else if (env.end) {
    torchColor = NL_END_TORCH_COL;
  } else if (env.nether) {
    torchColor = NL_NETHER_TORCH_COL;
  } else {
    torchColor = NL_OVERWORLD_TORCH_COL;
  }

  lum = luminance(light);
  light += torchColor*(smoothstep(0.1, 0.0, tileLightCol.b-tileLightCol.r)*NL_TORCHLIGHT_INTENSITY*tl/(1.0+lum));

  // game min brightness
  lum = luminance(light);
  if (!(env.nether || env.end)) {
    lum = luminance(light);
    light += vec3_splat(min(tileLightCol.r, 0.15)*(NL_MIN_LIGHTING_BOOST/(1.0+lum)));
  }

  if (env.underwater) {
    vec3 gPos = wPos + CAMERA_POS;
    float caustics = 0.2 + 0.2*sin(dot(gPos, vec3(1.8, 2.4, 2.1)) + 0.8*t);
    light += 0.8*NL_UNDERWATER_BRIGHTNESS + NL_CAUSTIC_INTENSITY*caustics*(0.1 + tl);
    light *= mix(normalize(skycol.horizon), vec3_splat(0.5), tileLightCol.b*0.2);
  }

  lum = luminance(light);
  light += vec3_splat(overlayCol.a*(1.5/(1.0+lum)));

  return light;
}

float nlEntityEdgeHighlight(vec4 edgemap) {
  #ifdef NL_ENTITY_EDGE_HIGHLIGHT
    vec2 len = min(abs(edgemap.xy),abs(edgemap.zw));
    len *= len;
    len *= len;
    float ambient = len.x + len.y*(1.0-len.x);
    return NL_ENTITY_BRIGHTNESS + ambient*NL_ENTITY_EDGE_HIGHLIGHT;
  #else
    return 1.0;
  #endif
}

vec4 nlEntityEdgeHighlightPreprocess(vec2 texcoord) {
  vec4 edgeMap = fract(vec4(texcoord*128.0, texcoord*256.0));
  return 2.0*step(edgeMap, vec4_splat(0.5)) - 1.0;
}

// lava crust noise: slow flowing dark crust + pulsing glow.
// gPos: wrapped world pos, t: wrapped time. Returns rgb multiplier, a = noise
vec4 nlLavaNoise(highp vec3 gPos, highp float t) {
  highp vec2 p = gPos.xz;
  // slow flow: scroll two noise layers in different directions (seamless at wraps)
  highp vec2 flow1 = vec2(nlScroll(t, 0.35*NL_LAVA_NOISE_SPEED, 8.0), nlScroll(t, 0.2*NL_LAVA_NOISE_SPEED, 8.0));
  highp vec2 flow2 = vec2(nlScroll(t, -0.25*NL_LAVA_NOISE_SPEED, 4.0), nlScroll(t, 0.4*NL_LAVA_NOISE_SPEED, 4.0));
  float n = 0.65*nlWorldNoise(p + flow1, 8.0) + 0.35*nlWorldNoise(p + flow2, 4.0);
  n = smoothstep(0.25, 0.85, n);
  float pulse = 1.0 + NL_LAVA_PULSE*sin(NL_SNAP_W(0.9)*t + NL_TAU*nlWorldNoise(p, 16.0));
  vec3 col = mix(vec3(0.7, 0.4, 0.0)*smoothstep(-0.1, 0.5, n), vec3_splat(1.5), n*n)*pulse;
  return vec4(col, n);
}

#endif
