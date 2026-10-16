vec4 a_color0     : COLOR0;
vec3 a_position   : POSITION;
vec2 a_texcoord0  : TEXCOORD0;
vec2 a_texcoord1  : TEXCOORD1;

vec4 i_data0      : TEXCOORD8;
vec4 i_data1      : TEXCOORD7;
vec4 i_data2      : TEXCOORD6;
vec4 i_data3      : TEXCOORD5;

vec4 v_color0     : COLOR0;
vec4 v_color1     : COLOR1;
vec4 v_fog        : COLOR2;
vec4 v_refl       : COLOR3;
centroid vec2 v_texcoord0  : TEXCOORD0;
vec2 v_lightmapUV : TEXCOORD1;
vec4 v_extra      : TEXCOORD3;

// per pixel effects (only used when NL_FRAG_FX is defined, see config.h)
vec4 v_wpos       : TEXCOORD2; // xyz: camera relative position, w: rain factor (overworld, open air)
vec4 v_gpos       : TEXCOORD4; // xyz: wrapped world position, w: flags (1 = lava, +2 = camera underwater)
vec4 v_sun        : TEXCOORD5; // rgb: direct sun/moon light (for face shading), a: unused
