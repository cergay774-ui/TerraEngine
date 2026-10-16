$input v_color0, v_color1, v_fog, v_refl, v_texcoord0, v_lightmapUV, v_extra
#include <newb/config.h>
#ifdef NL_FRAG_FX
  $input v_wpos, v_gpos, v_sun
#endif

#include <bgfx_shader.sh>
#include <newb/main.sh>

uniform vec4 FogColor;
uniform vec4 FogAndDistanceControl;
uniform vec4 ViewPositionAndTime;
uniform vec4 TimeOfDay;
uniform vec4 CameraPosition;

SAMPLER2D_AUTOREG(s_MatTexture);
SAMPLER2D_AUTOREG(s_SeasonsTexture);
SAMPLER2D_AUTOREG(s_LightMapTexture);

// vanilla bakes face direction shading into vertex color
// (top 1.0, bottom 0.5, z faces 0.8, x faces 0.6)
float nlVanillaFaceShade(vec3 n) {
  if (n.y > 0.5) {
    return 1.0;
  }
  if (n.y < -0.5) {
    return 0.5;
  }
  return abs(n.z) > abs(n.x) ? 0.8 : 0.6;
}

void main() {
  #if defined(DEPTH_ONLY_OPAQUE) || defined(DEPTH_ONLY) || defined(INSTANCING)
    gl_FragColor = vec4(1.0,1.0,1.0,1.0);
    return;
  #endif

  #ifdef NL_FRAG_FX
    highp vec3 wPos = v_wpos.xyz;
    vec3 toCam = ViewPositionAndTime.xyz - wPos;
    float camDist = length(toCam);
    vec3 V = toCam/max(camDist, 0.0001);

    // geometric normal from screen space derivatives (computed before any
    // discard / branch), flipped to face the camera: works for any API's
    // derivative direction and for double sided plants
    vec3 geomN = normalize(cross(dFdx(wPos), dFdy(wPos)));
    geomN = dot(geomN, V) < 0.0 ? -geomN : geomN;

    #if TS_EMISSIVE_ON
      // lightmap gradient per block: faces of light sources are evenly lit,
      // faces merely near a light have a gradient
      float lmGrad = length(vec2(dFdx(v_lightmapUV.x), dFdy(v_lightmapUV.x)));
      float posGrad = length(vec2(length(dFdx(wPos)), length(dFdy(wPos))));
      float lmGradPerBlock = lmGrad/max(posGrad, 0.0001);
    #endif

    highp float tRaw = ViewPositionAndTime.w;
    highp float t = nlWrapTime(tRaw);
    bool isLava = mod(v_gpos.w, 2.0) > 0.5;
    bool camUnderwater = v_gpos.w > 1.5;
  #endif

  vec4 diffuse = texture2D(s_MatTexture, v_texcoord0);
  vec4 color = v_color0;

  #if defined(NL_FRAG_FX) && TS_LAVA_FLOW
    // lava flow: wrap the UV inside the lava tile of the atlas and let it flow.
    // Atlas is 64 tiles wide (same assumption as upstream glow leak).
    if (isLava && camDist < 40.0) {
      vec2 texSize = vec2(textureSize(s_MatTexture, 0));
      float tilePx = texSize.x/64.0;
      vec2 tile = vec2(tilePx, tilePx)/texSize;
      vec2 origin = floor(v_texcoord0/tile)*tile;
      vec2 local = (v_texcoord0 - origin)/tile;
      highp vec2 g = v_gpos.xz;
      vec2 warp = NL_LAVA_FLOW_WARP*vec2(
        sin(NL_SNAP_K(NL_TAU*0.25)*g.y + NL_SNAP_W(0.7)*t),
        cos(NL_SNAP_K(NL_TAU*0.25)*g.x - NL_SNAP_W(0.5)*t)
      );
      vec2 flow = vec2(nlScroll(t, NL_LAVA_FLOW_SPEED, 1.0), nlScroll(t, 0.6*NL_LAVA_FLOW_SPEED, 1.0));
      float halfTexel = 0.5/tilePx;
      local = clamp(fract(local + warp + flow), halfTexel, 1.0 - halfTexel);
      diffuse = texture2DLod(s_MatTexture, origin + local*tile, 0.0);
    }
  #endif

  #ifdef ALPHA_TEST
    if (diffuse.a < 0.6) {
      discard;
    }
  #endif

  #if defined(SEASONS) && (defined(OPAQUE) || defined(ALPHA_TEST))
    diffuse.rgb *= mix(vec3(1.0,1.0,1.0), texture2D(s_SeasonsTexture, v_color1.xy).rgb * 2.0, v_color1.z);
  #endif

  vec3 glow = nlGlow(s_MatTexture, v_texcoord0, v_extra.a);

  #if defined(NL_FRAG_FX) && TS_EMISSIVE_ON && !defined(TRANSPARENT)
    // light emitting blocks without glow textures (sea lantern, shroomlight,
    // froglight, lava...): bright texels on evenly lit faces at max block light
    float bright = max(max(diffuse.r, diffuse.g), diffuse.b);
    float emit = smoothstep(NL_EMISSIVE_MIN_LIGHT, 0.88, v_lightmapUV.x);
    emit *= smoothstep(NL_EMISSIVE_MIN_BRIGHT, 0.95, bright);
    emit *= 1.0 - smoothstep(0.015, 0.04, lmGradPerBlock);
    glow += (1.2*TS_EMISSIVE*emit)*diffuse.rgb*diffuse.rgb;
  #endif

  diffuse.rgb *= diffuse.rgb;

  #if defined(NL_FRAG_FX) && TS_LAVA_FLOW
    if (isLava) {
      // hot texels glow and pulse (world locked phase)
      float pulse = 1.0 + NL_LAVA_PULSE*sin(NL_SNAP_W(1.3)*t + NL_SNAP_K(0.5)*(v_gpos.x + v_gpos.z));
      glow += NL_LAVA_GLOW*pulse*diffuse.rgb*smoothstep(0.3, 0.9, diffuse.r);
    }
  #endif

  #if defined(TRANSPARENT) && !(defined(SEASONS) || defined(RENDER_AS_BILLBOARDS))
    if (v_extra.b > 0.9) {
      diffuse.rgb = vec3_splat(1.0 - NL_WATER_TEX_OPACITY*(1.0 - diffuse.b*1.8));
      diffuse.a = color.a;
    }
  #else
    diffuse.a = 1.0;
  #endif

  // linear albedo (texture * vertex tint), used for caustics
  // (for seasons / billboards a_color0 holds other data)
  #if defined(SEASONS) || defined(RENDER_AS_BILLBOARDS)
    vec3 albedo = diffuse.rgb;
  #else
    vec3 albedo = diffuse.rgb*v_color1.rgb;
  #endif

  vec3 lightCol = color.rgb;
  #ifdef NL_FRAG_FX
    float faceShade = nlVanillaFaceShade(geomN);

    #if TS_FACE_SHADING_ON
      // direct sun/moon light shaded by face direction: faces turned to the
      // sun get brighter, faces turned away darker (vanilla shade replaced)
      nl_environment envL;
      envL.end = false;
      envL.nether = false;
      envL.underwater = false;
      envL.rainFactor = 0.0;
      envL.fogCol = FogColor.rgb;
      envL = calculateSunParams(envL, TimeOfDay.x);
      float ndl = dot(geomN, nlMainLightDir(envL));
      float faceSun = 0.45 + 0.55*clamp(1.2*ndl + 0.25, 0.0, 1.0);
      if (v_extra.b > 0.9) {
        faceSun = faceShade; // water: no face shading
      }
      lightCol += v_sun.rgb*mix(1.0, clamp(faceSun/faceShade, 0.5, 1.5), TS_FACE_SHADING);
    #endif

    #if TS_AO_ON && !(defined(TRANSPARENT) || defined(SEASONS) || defined(RENDER_AS_BILLBOARDS))
      // vertex color = face shade * vanilla AO -> isolate AO and strengthen it.
      // Biome tinted blocks (grass, leaves) keep vanilla AO: tint and AO can't be separated.
      bool tinted = v_color1.r != v_color1.g || v_color1.g != v_color1.b;
      float ao = clamp(v_color1.g/faceShade, 0.0, 1.0);
      lightCol *= mix(1.0, ao, tinted ? 0.0 : TS_AO);
    #endif
  #endif

  diffuse.rgb *= lightCol;
  diffuse.rgb += glow;

  #if defined(NL_FRAG_FX) && TS_CAUSTICS == 2 && !defined(TRANSPARENT)
    // per pixel caustics on surfaces while the camera is underwater
    if (camUnderwater && v_lightmapUV.y < 0.9) {
      vec2 lit = v_lightmapUV*v_lightmapUV;
      float caustics = 2.0*nlCaustics(v_gpos.xyz, t);
      diffuse.rgb += albedo*(0.5*NL_CAUSTIC_INTENSITY*caustics*(0.15 + lit.y + 0.7*lit.x))*vec3(0.55, 0.85, 1.0);
    }
  #endif

  if (v_extra.b > 0.9) {
    #if defined(NL_FRAG_FX) && TS_WATER_PER_PIXEL && defined(TRANSPARENT) && !(defined(SEASONS) || defined(RENDER_AS_BILLBOARDS))
      nl_environment env = nlDetectEnvironment(TimeOfDay.x, FogColor.rgb, FogAndDistanceControl.xyz);
      nl_skycolor skycol = nlSkyColors(env);
      vec2 lit = v_lightmapUV*v_lightmapUV;
      diffuse = nlWaterShade(
        diffuse.rgb, diffuse.a, skycol, env, geomN, V, wPos, v_gpos.xyz, CameraPosition.xyz,
        nlTorchColor(env), lit, camDist, t, tRaw
      );
    #else
      diffuse.rgb += v_refl.rgb*v_refl.a;
    #endif
  } else if (v_refl.a > 0.0) {
    // reflective effect (per vertex wet ground) - only on xz plane
    float dy = abs(dFdy(v_extra.g));
    if (dy < 0.0002) {
      float mask = v_refl.a*(clamp(v_extra.r*10.0,8.2,8.8)-7.8);
      diffuse.rgb *= 1.0 - 0.6*mask;
      diffuse.rgb += v_refl.rgb*mask;
    }
  }

  #if defined(NL_FRAG_FX) && (TS_PUDDLES || TS_WET_GROUND) && defined(OPAQUE) && !(defined(SEASONS) || defined(RENDER_AS_BILLBOARDS))
    // rain puddles and wet ground (only computed while it rains)
    if (v_wpos.w > 0.001 && !isLava) {
      nl_environment env = nlDetectEnvironment(TimeOfDay.x, FogColor.rgb, FogAndDistanceControl.xyz);
      nl_skycolor skycol = nlSkyColors(env);
      diffuse.rgb = nlPuddles(
        diffuse.rgb, v_gpos.xyz, wPos, V, geomN, v_lightmapUV, v_wpos.w, camDist,
        skycol, env, nlTorchColor(env), CameraPosition.xyz, t, tRaw
      );
    }
  #endif

  diffuse.rgb = mix(diffuse.rgb, v_fog.rgb, v_fog.a);

  diffuse.rgb = colorCorrection(diffuse.rgb);
  diffuse.rgb = nlDimensionGrade(diffuse.rgb, FogColor.rgb, FogAndDistanceControl.xy, v_fog.a);

  gl_FragColor = diffuse;
}
