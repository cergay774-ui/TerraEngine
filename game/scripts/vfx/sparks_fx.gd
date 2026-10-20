extends FxModule
## Искры и вспышки событий.
##
## Крит: сноп раскалённых искр из мотора (частицы со своим шейдером: вытянуты по скорости,
##   остывают белый → жёлтый → оранжевый → красный, падают и отскакивают от пола, на полу
##   догорают точками), яркая вспышка-звезда, вспышка света и ударная волна по полу.
## Уровень: золотое кольцо-печать на полу вокруг мотора с бегущими делениями, столб света,
##   золотые звёздочки, поднимающиеся по спирали, волна по полу и тёплый свет.
## Золото: горсть золотых чешуек-монеток: крутятся, ловят блик (звёздочка, когда монетка
##   смотрит в камеру), падают и ложатся на пол.
## Улучшение: голубой вихрь искр вокруг мотора, сходящийся в деталь, кольцо-«сканер»
##   снизу вверх и голубая вспышка в конце.
## Всё создаётся один раз в setup(); в кадре меняются только параметры и положения.
## Шейдеры и помощники отсюда использует heat_fx.gd (через preload).

const NOISE_SIZE := 128

# ---------------------------------------------------------------------
# Шейдеры
# ---------------------------------------------------------------------

# Общие функции частиц: хэш и случайные числа.
const RAND_FN := """
uint hash_u(uint x) {
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	x = (x >> uint(16)) ^ x;
	return x;
}
float rnd(inout uint s) {
	s = hash_u(s + uint(40503));
	return float(s % uint(65536)) / 65535.0;
}
"""

# Искры и чешуйки: вылет из области box вокруг точки узла, гравитация, сопротивление воздуха,
# отскок от пола. Ось Y частицы — по скорости, длина = след (для искр); для чешуек — вращение.
# CUSTOM: x — зерно, y — возраст 0..1, z — число отскоков, w — доля жизни.
const SPARK_PROC := """
shader_type particles;

uniform vec3 box = vec3(1.0, 0.5, 1.0);
uniform vec3 dir = vec3(0.0, 1.0, 0.0);
uniform float spread = 0.5;
uniform float radial = 0.6;
uniform vec2 speed = vec2(6.0, 14.0);
uniform vec3 gravity = vec3(0.0, -24.0, 0.0);
uniform float drag = 0.4;
uniform float floor_y = 0.0;
uniform float bounce = 0.4;
uniform float friction = 0.6;
uniform float life_rand = 0.4;
uniform float streak = 0.05;
uniform float streak_max = 1.5;
uniform float thick = 0.045;
uniform float size_rand = 0.5;
uniform float big_chance = 0.08;
uniform float flake = 0.0;
uniform float spin = 12.0;

RAND_FN

mat3 axis_rot(vec3 a, float ang) {
	float c = cos(ang);
	float s = sin(ang);
	float t = 1.0 - c;
	return mat3(vec3(t * a.x * a.x + c, t * a.x * a.y + s * a.z, t * a.x * a.z - s * a.y),
		vec3(t * a.x * a.y - s * a.z, t * a.y * a.y + c, t * a.y * a.z + s * a.x),
		vec3(t * a.x * a.z + s * a.y, t * a.y * a.z - s * a.x, t * a.z * a.z + c));
}

void start() {
	uint s = hash_u(NUMBER * uint(747796405) + RANDOM_SEED + uint(1));
	vec3 off = (vec3(rnd(s), rnd(s), rnd(s)) * 2.0 - 1.0) * box;
	TRANSFORM = mat4(vec4(thick, 0.0, 0.0, 0.0), vec4(0.0, thick, 0.0, 0.0), vec4(0.0, 0.0, thick, 0.0),
		vec4(EMISSION_TRANSFORM[3].xyz + off, 1.0));
	vec3 rv = vec3(rnd(s), rnd(s), rnd(s)) * 2.0 - 1.0;
	vec2 hor = off.xz / max(length(box.xz), 0.001);
	vec3 d = normalize(dir + rv * spread + vec3(hor.x, 0.0, hor.y) * radial + vec3(0.0, 0.001, 0.0));
	float sp = mix(speed.x, speed.y, pow(rnd(s), 0.8));
	VELOCITY = d * sp;
	float seed = rnd(s);
	CUSTOM = vec4(seed, 0.0, 0.0, 1.0 - life_rand * rnd(s));
	COLOR = vec4(1.0);
}

void process() {
	float life = max(CUSTOM.w, 0.05);
	CUSTOM.y += DELTA / (LIFETIME * life);
	if (CUSTOM.y >= 1.0) {
		ACTIVE = false;
	}
	float seed = CUSTOM.x;
	VELOCITY += gravity * DELTA;
	VELOCITY *= max(0.0, 1.0 - drag * DELTA);
	vec3 p = TRANSFORM[3].xyz;
	bool on_floor = p.y <= floor_y + 0.05;
	if (p.y + VELOCITY.y * DELTA < floor_y && VELOCITY.y < 0.0) {
		float b = bounce * (0.6 + 0.8 * fract(seed * 13.7 + CUSTOM.z * 0.37));
		VELOCITY.y = -VELOCITY.y * b;
		VELOCITY.xz *= friction;
		CUSTOM.z += 1.0;
		if (VELOCITY.y < 0.9) {
			VELOCITY.y = 0.0;
		}
		TRANSFORM[3].y = floor_y + 0.03;
		on_floor = true;
	}
	if (on_floor && VELOCITY.y <= 0.0) {
		VELOCITY.y = 0.0;
		VELOCITY.xz *= max(0.0, 1.0 - 2.2 * DELTA);
		TRANSFORM[3].y = floor_y + 0.03;
	}
	float sz = 1.0 - size_rand * fract(seed * 7.31);
	if (fract(seed * 3.77) < big_chance) {
		sz *= 1.8;
	}
	if (flake < 0.5) {
		float spd = length(VELOCITY);
		vec3 y = spd > 0.001 ? VELOCITY / spd : vec3(0.0, 1.0, 0.0);
		vec3 ref = abs(y.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
		vec3 x = normalize(cross(ref, y));
		vec3 z = cross(x, y);
		float th = thick * sz;
		float L = clamp(spd * streak, th * 1.2, streak_max);
		TRANSFORM[0] = vec4(x * th, 0.0);
		TRANSFORM[1] = vec4(y * L, 0.0);
		TRANSFORM[2] = vec4(z * th, 0.0);
	} else {
		vec3 ax = normalize(vec3(fract(seed * 5.13), fract(seed * 9.71), fract(seed * 3.17)) - 0.5 + 0.001);
		float ang = seed * 6.28 + CUSTOM.y * LIFETIME * life * spin * (0.6 + fract(seed * 2.9));
		mat3 r = axis_rot(ax, ang);
		if (CUSTOM.z > 0.5 && on_floor) {
			r = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, -1.0), vec3(0.0, 1.0, 0.0));
		}
		float s2 = thick * sz;
		TRANSFORM[0] = vec4(r[0] * s2, 0.0);
		TRANSFORM[1] = vec4(r[1] * s2, 0.0);
		TRANSFORM[2] = vec4(r[2] * s2, 0.0);
	}
}
"""

# Спираль: частица идёт по винтовой линии вокруг оси (узел — центр основания), радиус
# меняется от radius.x к radius.y, в конце (converge) стягивается к точке target.
# Ось Y частицы — по направлению движения (для следа), толщина — size.
const HELIX_PROC := """
shader_type particles;
render_mode disable_velocity;

uniform vec3 axis = vec3(0.0, 1.0, 0.0);
uniform vec2 radius = vec2(5.0, 2.0);
uniform float height = 6.0;
uniform float turns = 1.0;
uniform float jitter = 0.3;
uniform float h_rand = 0.2;
uniform vec3 target = vec3(0.0);
uniform float converge = 0.0;
uniform float life_rand = 0.3;
uniform float size = 0.1;
uniform float size_rand = 0.5;
uniform float streak = 0.08;
uniform float streak_max = 1.2;
uniform float ease = 1.0;
uniform float wobble = 0.0;

RAND_FN

vec3 helix_pos(float age, float seed, float a0, vec3 o, vec3 u, vec3 v, vec3 ax) {
	float k = pow(age, ease);
	float a = a0 + k * turns * 6.2831853;
	float r = mix(radius.x, radius.y, k) * (1.0 + (fract(seed * 7.13) - 0.5) * jitter);
	r += sin(age * 9.0 + seed * 30.0) * wobble;
	float h0 = fract(seed * 3.71) * h_rand;
	float h = (h0 + k * (1.0 - h_rand)) * height;
	vec3 p = o + (u * cos(a) + v * sin(a)) * r + ax * h;
	float c = smoothstep(0.55, 1.0, age) * converge;
	return mix(p, target, c * c);
}

void start() {
	uint s = hash_u(NUMBER * uint(747796405) + RANDOM_SEED + uint(7));
	float seed = rnd(s);
	float a0 = rnd(s) * 6.2831853;
	CUSTOM = vec4(seed, 0.0, a0, 1.0 - life_rand * rnd(s));
	TRANSFORM = mat4(vec4(size, 0.0, 0.0, 0.0), vec4(0.0, size, 0.0, 0.0), vec4(0.0, 0.0, size, 0.0),
		vec4(EMISSION_TRANSFORM[3].xyz, 1.0));
	VELOCITY = vec3(0.0);
	COLOR = vec4(1.0);
}

void process() {
	float life = max(CUSTOM.w, 0.05);
	CUSTOM.y += DELTA / (LIFETIME * life);
	if (CUSTOM.y >= 1.0) {
		ACTIVE = false;
	}
	float age = clamp(CUSTOM.y, 0.0, 1.0);
	float seed = CUSTOM.x;
	vec3 ax = normalize(axis);
	vec3 ref = abs(ax.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 u = normalize(cross(ref, ax));
	vec3 v = cross(ax, u);
	vec3 o = EMISSION_TRANSFORM[3].xyz;
	vec3 p = helix_pos(age, seed, CUSTOM.z, o, u, v, ax);
	float da = 0.03;
	vec3 p0 = helix_pos(max(age - da, 0.0), seed, CUSTOM.z, o, u, v, ax);
	vec3 vel = (p - p0) / (da * LIFETIME * life);
	VELOCITY = vel;
	float spd = length(vel);
	vec3 y = spd > 0.001 ? vel / spd : ax;
	vec3 r2 = abs(y.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 x = normalize(cross(r2, y));
	vec3 z = cross(x, y);
	float th = size * (1.0 - size_rand * fract(seed * 5.91));
	float L = clamp(spd * streak, th * 1.2, streak_max);
	TRANSFORM[0] = vec4(x * th, 0.0);
	TRANSFORM[1] = vec4(y * L, 0.0);
	TRANSFORM[2] = vec4(z * th, 0.0);
	TRANSFORM[3] = vec4(p, 1.0);
}
"""

# Искра на экране: лента вдоль скорости, развёрнута к камере. Круглая раскалённая голова,
# хвост сужается и гаснет. Цвет — по возрасту из градиента остывания.
const SPARK_DRAW := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, skip_vertex_transform;

uniform sampler2D ramp : source_color, filter_linear, repeat_disable;
uniform float boost = 3.5;
uniform float intensity = 1.0;

varying vec2 suv;
varying vec4 col;
varying float ln;

void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;
	vec3 ay = MODEL_MATRIX[1].xyz;
	float L = length(ay);
	vec3 dir = ay / max(L, 0.00001);
	float th = max(length(MODEL_MATRIX[0].xyz), 0.0001);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 tc = normalize(cam - o);
	vec3 side = cross(dir, tc);
	float sl = length(side);
	side = sl > 0.001 ? side / sl : INV_VIEW_MATRIX[0].xyz;
	float t = UV.y;
	vec3 p = o + dir * (th - t * (L + th)) + side * (UV.x - 0.5) * 2.0 * th;
	VERTEX = (VIEW_MATRIX * vec4(p, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(tc, 0.0)).xyz);
	suv = vec2(UV.x * 2.0 - 1.0, t * (L + th) / th);
	ln = L / th;
	col = textureLod(ramp, vec2(clamp(INSTANCE_CUSTOM.y, 0.0, 1.0), 0.5), 0.0);
}

void fragment() {
	float x = suv.x;
	float sn = suv.y;
	float head = exp(-((sn - 1.0) * (sn - 1.0) + x * x) * 2.2);
	float k = clamp((sn - 1.0) / max(ln, 0.001), 0.0, 1.0);
	float tail = exp(-x * x * 2.5) * pow(1.0 - k, 1.3) * step(1.0, sn);
	float e = max(head, tail * 0.8);
	vec3 c = mix(col.rgb, vec3(1.0, 0.97, 0.9), head * head * 0.45);
	ALBEDO = c * e * boost * col.a * intensity;
	ALPHA = 1.0;
}
"""

# Звёздочка: билборд с четырьмя лучами, мерцает; цвет по возрасту.
const STAR_DRAW := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, skip_vertex_transform;

uniform sampler2D ramp : source_color, filter_linear, repeat_disable;
uniform float boost = 3.0;
uniform float intensity = 1.0;
uniform float twinkle = 1.0;
uniform float scale = 1.0;

varying vec4 col;
varying float tw;

void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;
	float s = length(MODEL_MATRIX[0].xyz) * scale;
	float seed = INSTANCE_CUSTOM.x;
	float ang = seed * 0.8 - 0.4;
	vec2 v = VERTEX.xy;
	v = vec2(v.x * cos(ang) - v.y * sin(ang), v.x * sin(ang) + v.y * cos(ang));
	vec3 p = o + (INV_VIEW_MATRIX[0].xyz * v.x + INV_VIEW_MATRIX[1].xyz * v.y) * s;
	VERTEX = (VIEW_MATRIX * vec4(p, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
	col = textureLod(ramp, vec2(clamp(INSTANCE_CUSTOM.y, 0.0, 1.0), 0.5), 0.0);
	float w = 0.5 + 0.5 * sin(TIME * (7.0 + seed * 13.0) + seed * 40.0);
	tw = mix(1.0, 0.25 + 0.75 * w * w, twinkle);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r2 = dot(p, p);
	float core = exp(-r2 * 26.0);
	float halo = exp(-r2 * 5.0) * 0.22;
	float rays = exp(-abs(p.x) * 26.0) * max(0.0, 1.0 - abs(p.y)) + exp(-abs(p.y) * 26.0) * max(0.0, 1.0 - abs(p.x));
	vec3 hot = mix(col.rgb, vec3(1.0, 0.98, 0.92), 0.55);
	ALBEDO = (hot * core * 1.6 + col.rgb * (halo + rays * 0.9 * tw)) * boost * col.a * intensity * (0.6 + 0.4 * tw);
	ALPHA = 1.0;
}
"""

# Золотая чешуйка-монетка: диск в плоскости частицы, ярче, когда смотрит в камеру.
const FLAKE_DRAW := """
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 gold : source_color = vec3(1.0, 0.68, 0.16);
uniform float intensity = 1.0;

varying float facing;
varying float fade;

void vertex() {
	vec3 n = normalize(MODEL_MATRIX[2].xyz);
	vec3 o = MODEL_MATRIX[3].xyz;
	vec3 tc = normalize(INV_VIEW_MATRIX[3].xyz - o);
	facing = abs(dot(n, tc));
	fade = 1.0 - smoothstep(0.72, 1.0, INSTANCE_CUSTOM.y);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float d = length(p);
	float disc = 1.0 - smoothstep(0.8, 1.0, d);
	float rim = smoothstep(0.58, 0.8, d) * disc;
	float sheen = pow(facing, 3.0);
	float band = exp(-pow((p.x + p.y) * 1.4 - (facing * 2.0 - 1.0) * 1.6, 2.0) * 3.0);
	vec3 c = gold * (0.3 + 1.5 * sheen) + vec3(1.0, 0.92, 0.7) * (band * 0.5 * sheen + pow(facing, 24.0) * 1.8);
	c = mix(c, c * 1.35 + vec3(0.08, 0.05, 0.0), rim * 0.6);
	ALBEDO = c * intensity;
	ALPHA = disc * fade * intensity;
}
"""

# Блик чешуйки: звёздочка-билборд, вспыхивает, когда монетка повёрнута к камере.
const GLINT_DRAW := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, skip_vertex_transform;

uniform vec3 col : source_color = vec3(1.0, 0.85, 0.5);
uniform float size_k = 5.0;
uniform float sharp = 10.0;
uniform float intensity = 1.0;

varying float glint;

void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;
	vec3 n = normalize(MODEL_MATRIX[2].xyz);
	vec3 tc = normalize(INV_VIEW_MATRIX[3].xyz - o);
	glint = pow(abs(dot(n, tc)), sharp) * (1.0 - smoothstep(0.6, 0.95, INSTANCE_CUSTOM.y));
	float s = length(MODEL_MATRIX[0].xyz) * size_k * step(0.02, glint);
	vec3 p = o + (INV_VIEW_MATRIX[0].xyz * VERTEX.x + INV_VIEW_MATRIX[1].xyz * VERTEX.y) * s + tc * 0.05;
	VERTEX = (VIEW_MATRIX * vec4(p, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r2 = dot(p, p);
	float core = exp(-r2 * 40.0);
	float rays = exp(-abs(p.x) * 32.0) * max(0.0, 1.0 - abs(p.y)) + exp(-abs(p.y) * 32.0) * max(0.0, 1.0 - abs(p.x));
	ALBEDO = (col * rays + vec3(1.0, 0.97, 0.9) * core * 2.0) * glint * 3.0 * intensity;
	ALPHA = 1.0;
}
"""

# Плоская волна / кольцо (на полу или поперёк оси): яркая кромка, мягкое свечение внутри.
const RING_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 col : source_color = vec3(1.0, 0.6, 0.2);
uniform float r = 0.5;
uniform float width = 0.03;
uniform float trail = 0.25;
uniform float power = 0.0;
uniform float seed = 0.0;
uniform float breakup = 0.8;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float d = length(p);
	float ang = atan(p.y, p.x) / 6.2831853;
	float n = texture(noise_tex, vec2(ang * 4.0 + seed, d * 1.2 - r * 1.5)).r;
	float front = exp(-pow((d - r) / width, 2.0));
	float inside = clamp((d - (r - trail)) / max(trail, 0.001), 0.0, 1.0) * step(d, r);
	inside *= inside;
	float nn = mix(1.0, 0.3 + 1.4 * n, breakup);
	float e = front * nn + inside * 0.35 * nn;
	vec3 c = mix(col, vec3(1.0, 0.96, 0.88), front * 0.45);
	ALBEDO = c * e * power * (1.0 - smoothstep(0.9, 1.0, d));
	ALPHA = 1.0;
}
"""

# Печать уровня на полу: двойное кольцо, бегущие деления, дуги, свечение, волна.
const SEAL_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 col : source_color = vec3(1.0, 0.72, 0.25);
uniform float r = 0.5;
uniform float rot = 0.0;
uniform float power = 0.0;
uniform float wave_r = 0.0;
uniform float wave_p = 0.0;

float band(float d, float c, float w) {
	float x = (d - c) / w;
	return exp(-x * x);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float d = length(p);
	float ang = atan(p.y, p.x) / 6.2831853;
	float ri = r * 0.84;
	float main_ring = band(d, r, 0.010);
	float halo = band(d, r, 0.07) * 0.35;
	float ring2 = band(d, ri, 0.006) * 0.8;
	float a2 = fract(ang * 60.0 + rot * 3.0);
	float ticks = (1.0 - smoothstep(0.1, 0.3, abs(a2 - 0.5))) * step(ri + 0.02, d) * step(d, r - 0.02);
	ticks *= 0.55 + 0.45 * step(0.5, fract(ang * 12.0 + rot * 3.0));
	float a3 = fract(ang * 5.0 - rot * 2.0);
	float arcs = band(d, r * 1.09, 0.006) * smoothstep(0.0, 0.04, a3) * (1.0 - smoothstep(0.5, 0.62, a3));
	float a4 = fract(ang * 3.0 + rot * 1.3);
	float arcs2 = band(d, r * 0.72, 0.005) * smoothstep(0.0, 0.06, a4) * (1.0 - smoothstep(0.3, 0.42, a4));
	float disc = (1.0 - smoothstep(0.0, r, d)) * 0.10 + band(d, r * 0.95, 0.12) * 0.12;
	float wave = band(d, wave_r, 0.025 + wave_r * 0.03) * wave_p;
	float e = main_ring * 1.7 + halo + ring2 + ticks * 0.55 + arcs * 0.9 + arcs2 * 0.6 + disc;
	vec3 hot = mix(col, vec3(1.0, 0.95, 0.8), 0.5);
	ALBEDO = (col * e + hot * main_ring * 0.6) * power + col * wave * 1.2;
	ALPHA = 1.0;
}
"""

# Столб света: открытый цилиндр, края ярче (френель), бегущие вверх полосы, гаснет кверху.
const PILLAR_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 col : source_color = vec3(1.0, 0.75, 0.3);
uniform float power = 0.0;
uniform float reveal = 1.0;
uniform float hgt = 16.0;

varying float vy;

void vertex() {
	vy = VERTEX.y / hgt + 0.5;
}

void fragment() {
	float y = clamp(vy, 0.0, 1.0);
	float fres = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	float edge = fres * fres;
	float n = texture(noise_tex, vec2(UV.x * 3.0, y * 0.7 - TIME * 0.55)).r;
	float n2 = texture(noise_tex, vec2(UV.x * 8.0 + 0.3, y * 1.4 - TIME * 1.2)).r;
	float rays = smoothstep(0.42, 0.8, n * 0.55 + n2 * 0.55);
	float vert = pow(1.0 - y, 1.7) * (1.0 - smoothstep(reveal - 0.3, reveal, y));
	float base = exp(-y * 30.0) * 0.6;
	float e = (0.08 + edge * 0.85) * (0.3 + rays * 1.3) * vert + base;
	ALBEDO = col * e * power;
	ALPHA = 1.0;
}
"""

# Вспышка: ядро, ореол, лучи-звезда и горизонтальный блик. Поверх всего (как блик в объективе).
const GLARE_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

uniform vec3 col : source_color = vec3(1.0, 0.6, 0.25);
uniform float power = 0.0;
uniform float rot = 0.0;
uniform float streak = 1.0;

void vertex() {
	mat4 mw = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mw * mat4(vec4(s, 0.0, 0.0, 0.0), vec4(0.0, s, 0.0, 0.0), vec4(0.0, 0.0, s, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float ang = atan(p.y, p.x);
	float core = exp(-r * r * 60.0);
	float halo = max(0.0, exp(-r * r * 7.0) - 0.0009) * 0.55;
	float rays = pow(max(0.0, cos(ang * 2.0 + rot)), 60.0) * 0.9 + pow(max(0.0, cos(ang * 3.0 - rot * 0.7 + 0.5)), 90.0) * 0.5;
	rays *= pow(max(0.0, 1.0 - r), 2.2);
	float an = exp(-p.y * p.y * 900.0) * pow(max(0.0, 1.0 - abs(p.x)), 1.5) * streak;
	vec3 hot = mix(col, vec3(1.0, 0.98, 0.94), 0.75);
	ALBEDO = (col * (halo + rays) + hot * core * 3.0 + mix(col, hot, 0.4) * an * 1.1) * power;
	ALPHA = 1.0;
}
"""

static var _noise: NoiseTexture2D = null
static var _shader_cache: Dictionary = {}

# крит
var _crit: Array = []          # пул из двух снопов: криты бывают чаще, чем живут искры
var _crit_slot: int = 0
var _crit_pm: ShaderMaterial
var _crit_draw: ShaderMaterial
var _crit_glare: MeshInstance3D
var _crit_glare_mat: ShaderMaterial
var _wave: MeshInstance3D
var _wave_mat: ShaderMaterial
var _t_crit: float = -1.0
var _crit_at: Vector3 = Vector3.ZERO
# уровень
var _seal: MeshInstance3D
var _seal_mat: ShaderMaterial
var _pillar: MeshInstance3D
var _pillar_mat: ShaderMaterial
var _rise: GPUParticles3D
var _rise_pm: ShaderMaterial
var _rise_draw: ShaderMaterial
var _t_lvl: float = -1.0
# золото
var _gold: Array = []
var _gold_slot: int = 0
var _gold_pm: ShaderMaterial
var _flake_mat: ShaderMaterial
var _glint_mat: ShaderMaterial
var _t_gold: float = -1.0
# улучшение
var _swirl: GPUParticles3D
var _swirl_pm: ShaderMaterial
var _swirl_draw: ShaderMaterial
var _scan: MeshInstance3D
var _scan_mat: ShaderMaterial
var _t_up: float = -1.0
var _up_target: Vector3 = Vector3.ZERO
# вспышка для золота/улучшения и общий свет
var _aux_glare: MeshInstance3D
var _aux_glare_mat: ShaderMaterial
var _light: OmniLight3D
var _light_e: float = 0.0       # огибающая света: энергия, которую задало последнее событие
var _light_decay: float = 6.0

var _R: float = 6.0             # радиус «пятна» мотора на полу
var _top: Vector3 = Vector3.ZERO
var _warm: bool = false
var _draw_mats: Array = []      # материалы с параметром intensity (для прогрева)


# ---------------------------------------------------------------------
# Ресурсы (общие для всех экранов с мотором)
# ---------------------------------------------------------------------

static func noise_tex() -> NoiseTexture2D:
	if _noise != null:
		return _noise
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = 23
	n.frequency = 0.03
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 4
	var t := NoiseTexture2D.new()
	t.noise = n
	t.width = NOISE_SIZE
	t.height = NOISE_SIZE
	t.seamless = true
	t.generate_mipmaps = true
	_noise = t
	return t


static func shader(key: String, code: String) -> Shader:
	if _shader_cache.has(key):
		return _shader_cache[key]
	var s := Shader.new()
	s.code = code.replace("RAND_FN", RAND_FN)
	_shader_cache[key] = s
	return s


static func make_mat(key: String, code: String, prio: int = 0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader(key, code)
	m.render_priority = prio
	return m


static func ramp(offsets: Array, colors: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 64
	return t


## Базис, у которого ось Z смотрит вдоль dir (плоский квадрат поперёк dir).
static func basis_z(dir: Vector3) -> Basis:
	var z := dir.normalized()
	var ref := Vector3.UP if absf(z.y) < 0.95 else Vector3.RIGHT
	var x := ref.cross(z).normalized()
	var y := z.cross(x).normalized()
	return Basis(x, y, z)


static func make_quad(parent: Node3D, m: Material, size: float = 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(size, size)
	mi.mesh = qm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 4.0
	mi.visible = false
	parent.add_child(mi)
	return mi


## Плоскость на полу (лицом вверх).
static func make_floor_plane(parent: Node3D, m: Material, size: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)
	mi.mesh = pm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	parent.add_child(mi)
	return mi


static func make_particles(parent: Node3D, amount: int, life: float, pm: Material, draw: Material) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(1, amount)
	p.lifetime = life
	p.process_material = pm
	var qm := QuadMesh.new()
	qm.material = draw
	p.draw_pass_1 = qm
	p.local_coords = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-18, -14, -18), Vector3(36, 34, 36))
	p.emitting = false
	p.visible = false
	parent.add_child(p)
	return p


func _glare_mat(col: Color) -> ShaderMaterial:
	var m := make_mat("glare", GLARE_SHADER, 3)
	m.set_shader_parameter("col", col)
	return m


func _count(base: Array) -> int:
	var n: int = base[pq()]
	if q() >= 3:
		n = int(n * 1.4)
	return n


# ---------------------------------------------------------------------
# Создание
# ---------------------------------------------------------------------

func setup() -> void:
	var noise := noise_tex()
	var parts := pq() > 0

	# --- крит: искры ---
	_crit_pm = make_mat("spark_proc", SPARK_PROC)
	_crit_pm.set_shader_parameter("spread", 0.55)
	_crit_pm.set_shader_parameter("radial", 0.9)
	_crit_pm.set_shader_parameter("speed", Vector2(7.0, 17.0))
	_crit_pm.set_shader_parameter("gravity", Vector3(0, -26.0, 0))
	_crit_pm.set_shader_parameter("drag", 0.55)
	_crit_pm.set_shader_parameter("bounce", 0.42)
	_crit_pm.set_shader_parameter("friction", 0.6)
	_crit_pm.set_shader_parameter("life_rand", 0.45)
	_crit_pm.set_shader_parameter("streak", 0.055)
	_crit_pm.set_shader_parameter("streak_max", 1.5)
	_crit_pm.set_shader_parameter("thick", 0.05)
	_crit_pm.set_shader_parameter("size_rand", 0.55)
	_crit_pm.set_shader_parameter("big_chance", 0.08)
	_crit_draw = make_mat("spark_draw", SPARK_DRAW, 1)
	_crit_draw.set_shader_parameter("ramp", ramp([0.0, 0.1, 0.35, 0.62, 0.85, 1.0], [
		Color(1.0, 0.97, 0.86, 1.0), Color(1.0, 0.84, 0.45, 1.0), Color(1.0, 0.55, 0.16, 1.0),
		Color(0.95, 0.3, 0.06, 0.9), Color(0.65, 0.1, 0.02, 0.6), Color(0.3, 0.03, 0.0, 0.0)]))
	_crit_draw.set_shader_parameter("boost", 3.6)
	_draw_mats.append(_crit_draw)
	for i in 2:
		var p := make_particles(self, _count([0, 110, 220]), 1.9, _crit_pm, _crit_draw)
		p.explosiveness = 0.96
		_crit.append(p)
	_crit_glare_mat = _glare_mat(Color(1.0, 0.62, 0.26))
	_crit_glare = make_quad(self, _crit_glare_mat)
	_wave_mat = make_mat("ring", RING_SHADER, 0)
	_wave_mat.set_shader_parameter("noise_tex", noise)
	_wave_mat.set_shader_parameter("col", Color(1.0, 0.55, 0.2))
	_wave = make_floor_plane(self, _wave_mat, 28.0)

	# --- уровень ---
	_seal_mat = make_mat("seal", SEAL_SHADER, 0)
	_seal = make_floor_plane(self, _seal_mat, 1.0)
	if q() >= 1:
		_pillar_mat = make_mat("pillar", PILLAR_SHADER, 0)
		_pillar_mat.set_shader_parameter("noise_tex", noise)
		var cyl := CylinderMesh.new()
		cyl.top_radius = 1.0
		cyl.bottom_radius = 1.0
		cyl.height = 1.0
		cyl.cap_top = false
		cyl.cap_bottom = false
		cyl.radial_segments = 40
		cyl.rings = 1
		_pillar = MeshInstance3D.new()
		_pillar.mesh = cyl
		_pillar.material_override = _pillar_mat
		_pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_pillar.visible = false
		add_child(_pillar)
	_rise_pm = make_mat("helix_proc", HELIX_PROC)
	_rise_pm.set_shader_parameter("turns", 0.35)
	_rise_pm.set_shader_parameter("jitter", 0.35)
	_rise_pm.set_shader_parameter("h_rand", 0.15)
	_rise_pm.set_shader_parameter("life_rand", 0.35)
	_rise_pm.set_shader_parameter("size", 0.2)
	_rise_pm.set_shader_parameter("size_rand", 0.55)
	_rise_pm.set_shader_parameter("ease", 0.75)
	_rise_pm.set_shader_parameter("wobble", 0.25)
	_rise_draw = make_mat("star_draw", STAR_DRAW, 1)
	_rise_draw.set_shader_parameter("ramp", ramp([0.0, 0.08, 0.5, 1.0], [
		Color(1.0, 0.9, 0.6, 0.0), Color(1.0, 0.86, 0.5, 1.0), Color(1.0, 0.72, 0.28, 0.9), Color(1.0, 0.55, 0.12, 0.0)]))
	_rise_draw.set_shader_parameter("boost", 2.6)
	_draw_mats.append(_rise_draw)
	_rise = make_particles(self, _count([0, 70, 140]), 1.9, _rise_pm, _rise_draw)
	_rise.explosiveness = 0.55

	# --- золото: чешуйки-монетки с бликами ---
	_gold_pm = make_mat("spark_proc", SPARK_PROC)
	_gold_pm.set_shader_parameter("box", Vector3(0.6, 0.3, 0.6))
	_gold_pm.set_shader_parameter("spread", 0.5)
	_gold_pm.set_shader_parameter("radial", 0.7)
	_gold_pm.set_shader_parameter("speed", Vector2(6.0, 11.0))
	_gold_pm.set_shader_parameter("gravity", Vector3(0, -19.0, 0))
	_gold_pm.set_shader_parameter("drag", 0.9)
	_gold_pm.set_shader_parameter("bounce", 0.3)
	_gold_pm.set_shader_parameter("friction", 0.5)
	_gold_pm.set_shader_parameter("life_rand", 0.3)
	_gold_pm.set_shader_parameter("thick", 0.24)
	_gold_pm.set_shader_parameter("size_rand", 0.45)
	_gold_pm.set_shader_parameter("big_chance", 0.0)
	_gold_pm.set_shader_parameter("flake", 1.0)
	_gold_pm.set_shader_parameter("spin", 11.0)
	_flake_mat = make_mat("flake_draw", FLAKE_DRAW, 1)
	_glint_mat = make_mat("glint_draw", GLINT_DRAW, 2)
	_draw_mats.append(_flake_mat)
	_draw_mats.append(_glint_mat)
	for i in 2:
		var g := make_particles(self, _count([0, 26, 48]), 1.7, _gold_pm, _flake_mat)
		g.explosiveness = 0.9
		g.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
		var gq := QuadMesh.new()
		gq.material = _glint_mat
		g.draw_passes = 2
		g.draw_pass_2 = gq
		_gold.append(g)

	# --- улучшение: голубой вихрь и «сканер» ---
	_swirl_pm = make_mat("helix_proc", HELIX_PROC)
	_swirl_pm.set_shader_parameter("turns", 1.35)
	_swirl_pm.set_shader_parameter("jitter", 0.25)
	_swirl_pm.set_shader_parameter("h_rand", 0.35)
	_swirl_pm.set_shader_parameter("converge", 1.0)
	_swirl_pm.set_shader_parameter("life_rand", 0.25)
	_swirl_pm.set_shader_parameter("size", 0.055)
	_swirl_pm.set_shader_parameter("size_rand", 0.4)
	_swirl_pm.set_shader_parameter("streak", 0.09)
	_swirl_pm.set_shader_parameter("streak_max", 2.2)
	_swirl_pm.set_shader_parameter("ease", 0.8)
	_swirl_draw = make_mat("spark_draw", SPARK_DRAW, 1)
	_swirl_draw.set_shader_parameter("ramp", ramp([0.0, 0.1, 0.6, 0.85, 1.0], [
		Color(0.55, 0.8, 1.0, 0.0), Color(0.75, 0.92, 1.0, 1.0), Color(0.45, 0.75, 1.0, 1.0),
		Color(0.8, 0.95, 1.0, 1.0), Color(0.6, 0.85, 1.0, 0.0)]))
	_swirl_draw.set_shader_parameter("boost", 3.0)
	_draw_mats.append(_swirl_draw)
	_swirl = make_particles(self, _count([0, 60, 120]), 1.15, _swirl_pm, _swirl_draw)
	_swirl.explosiveness = 0.75
	_scan_mat = make_mat("ring", RING_SHADER, 0)
	_scan_mat.set_shader_parameter("noise_tex", noise)
	_scan_mat.set_shader_parameter("col", Color(0.45, 0.75, 1.0))
	_scan_mat.set_shader_parameter("width", 0.018)
	_scan_mat.set_shader_parameter("trail", 0.5)
	_scan_mat.set_shader_parameter("breakup", 0.35)
	_scan = make_floor_plane(self, _scan_mat, 1.0)

	_aux_glare_mat = _glare_mat(Color(1.0, 0.75, 0.3))
	_aux_glare = make_quad(self, _aux_glare_mat)

	# свет вспышек: лишний источник — только со «Среднего»
	if q() >= 1:
		_light = make_omni(Color(1.0, 0.6, 0.28), 20.0)
		_light.visible = false

	for p in _crit + _gold + [_rise, _swirl]:
		(p as GPUParticles3D).visible = false
	if not parts:
		_draw_mats.clear()


func on_rebuild() -> void:
	var box: AABB = view.fx_bounds()
	var c := box.get_center()
	var fy: float = view.fx_floor_y()
	_R = maxf(box.size.x, box.size.z) * 0.55 + 0.6
	_top = Vector3(c.x, box.end.y - box.size.y * 0.22, c.z)
	_crit_pm.set_shader_parameter("box", Vector3(box.size.x * 0.28, box.size.y * 0.12, box.size.z * 0.28))
	for pm in [_crit_pm, _gold_pm]:
		(pm as ShaderMaterial).set_shader_parameter("floor_y", fy)
	(_seal.mesh as PlaneMesh).size = Vector2(_R * 4.0, _R * 4.0)
	_seal.position = Vector3(c.x, fy + 0.03, c.z)
	_wave.position = Vector3(c.x, fy + 0.04, c.z)
	if _pillar != null:
		var ph := 15.0
		_pillar.scale = Vector3(_R * 0.95, ph, _R * 0.95)
		_pillar.position = Vector3(c.x, fy + ph * 0.5, c.z)
		_pillar_mat.set_shader_parameter("hgt", 1.0)
	_rise.position = Vector3(c.x, fy + 0.1, c.z)
	_rise_pm.set_shader_parameter("radius", Vector2(_R * 1.0, _R * 0.55))
	_rise_pm.set_shader_parameter("height", box.size.y * 1.5 + 2.0)
	_swirl.position = Vector3(c.x, fy + 0.2, c.z)
	_swirl_pm.set_shader_parameter("radius", Vector2(_R * 0.95, _R * 0.45))
	_swirl_pm.set_shader_parameter("height", box.size.y * 1.05)
	(_scan.mesh as PlaneMesh).size = Vector2(_R * 2.3, _R * 2.3)


func warmup(on: bool) -> void:
	_warm = on
	var meshes: Array = [_crit_glare, _wave, _seal, _aux_glare, _scan]
	if _pillar != null:
		meshes.append(_pillar)
	for mi in meshes:
		(mi as MeshInstance3D).visible = on or _active_mesh(mi)
	for m in _draw_mats:
		(m as ShaderMaterial).set_shader_parameter("intensity", 0.0 if on else 1.0)
	if pq() == 0:
		return
	for p in _crit + _gold + [_rise, _swirl]:
		var gp: GPUParticles3D = p
		if on:
			gp.visible = true
			gp.restart()
		elif not _active_particles(gp):
			gp.visible = false
	if on:
		for mi in meshes:
			_set_power(mi, 0.0)


func _set_power(mi: MeshInstance3D, v: float) -> void:
	(mi.material_override as ShaderMaterial).set_shader_parameter("power", v)


func _active_mesh(mi: Node) -> bool:
	if mi == _crit_glare or mi == _wave:
		return _t_crit >= 0.0
	if mi == _seal or mi == _pillar:
		return _t_lvl >= 0.0
	if mi == _scan:
		return _t_up >= 0.0
	if mi == _aux_glare:
		return _t_gold >= 0.0 or _t_up >= 0.0
	return false


func _active_particles(p: GPUParticles3D) -> bool:
	if _crit.has(p):
		return _t_crit >= 0.0
	if _gold.has(p):
		return _t_gold >= 0.0
	if p == _rise:
		return _t_lvl >= 0.0
	if p == _swirl:
		return _t_up >= 0.0
	return false


# ---------------------------------------------------------------------
# События
# ---------------------------------------------------------------------

func on_event(event_name: String, data: Dictionary) -> void:
	match event_name:
		"crit":
			_start_crit()
		"level_up":
			_start_level()
		"gold":
			_start_gold()
		"upgrade":
			_start_upgrade(data)


func _restore_intensity() -> void:
	if _warm:
		_warm = false
		for m in _draw_mats:
			(m as ShaderMaterial).set_shader_parameter("intensity", 1.0)


func _flash_light(pos: Vector3, col: Color, energy: float, decay: float, rng: float) -> void:
	if _light == null:
		return
	if energy < _light_e * 0.6:
		return   # более яркая вспышка ещё не погасла
	_light.position = pos
	_light.light_color = col
	_light.omni_range = rng
	_light_e = energy
	_light_decay = decay
	_light.visible = true


func _start_crit() -> void:
	_restore_intensity()
	_t_crit = 0.0
	_crit_at = _top
	if pq() > 0:
		var p: GPUParticles3D = _crit[_crit_slot]
		_crit_slot = (_crit_slot + 1) % _crit.size()
		p.position = _top
		p.visible = true
		p.restart()
	_crit_glare.position = _top + Vector3(0, 0.6, 0)
	_crit_glare.visible = true
	_wave_mat.set_shader_parameter("seed", randf())
	_wave.visible = q() >= 1 or pq() > 0
	_flash_light(_top + Vector3(0, 1.5, 0), Color(1.0, 0.62, 0.28), 14.0, 7.0, 22.0)


func _start_level() -> void:
	_restore_intensity()
	_t_lvl = 0.0
	_seal.visible = true
	if _pillar != null:
		_pillar.visible = true
	if pq() > 0:
		_rise.visible = true
		_rise.restart()
	var c: Vector3 = _seal.position
	_flash_light(c + Vector3(0, 2.0, 0), Color(1.0, 0.76, 0.32), 7.0, 1.8, 18.0)


func _start_gold() -> void:
	_restore_intensity()
	_t_gold = 0.0
	var at := _top + Vector3(0, 0.8, 0)
	if pq() > 0:
		var g: GPUParticles3D = _gold[_gold_slot]
		_gold_slot = (_gold_slot + 1) % _gold.size()
		g.position = at
		g.visible = true
		g.restart()
	_aux_glare_mat.set_shader_parameter("col", Color(1.0, 0.75, 0.3))
	_aux_glare.position = at
	_aux_glare.visible = true
	if q() >= 2:
		_flash_light(at, Color(1.0, 0.75, 0.35), 5.0, 6.0, 14.0)


func _start_upgrade(data: Dictionary) -> void:
	_restore_intensity()
	_t_up = 0.0
	var target := Vector3.INF
	if data.has("slot"):
		target = view.fx_anchor(str(data.slot))
	if target == Vector3.INF:
		target = _top + Vector3(0, 0.5, 0)
	_up_target = target
	_swirl_pm.set_shader_parameter("target", view.fx_root().to_global(target))
	if pq() > 0:
		_swirl.visible = true
		_swirl.restart()
	_scan.visible = true
	_aux_glare_mat.set_shader_parameter("col", Color(0.45, 0.72, 1.0))
	_aux_glare.position = target
	_aux_glare.visible = true


# ---------------------------------------------------------------------
# Кадр
# ---------------------------------------------------------------------

func update(delta: float, _st: Dictionary) -> void:
	if _warm:
		return
	if _t_crit >= 0.0:
		_t_crit += delta
		_update_crit(_t_crit)
	if _t_lvl >= 0.0:
		_t_lvl += delta
		_update_level(_t_lvl)
	if _t_gold >= 0.0:
		_t_gold += delta
		_update_gold(_t_gold)
	if _t_up >= 0.0:
		_t_up += delta
		_update_upgrade(_t_up)
	if _light != null and _light.visible:
		_light_e *= exp(-delta * _light_decay)
		_light.light_energy = _light_e
		if _light_e < 0.05:
			_light.visible = false
			_light_e = 0.0


func _update_crit(t: float) -> void:
	# вспышка-звезда: мгновенно, гаснет за ~0.3 с
	var g := exp(-t * 9.0)
	_set_power(_crit_glare, 1.5 * g)
	var s := 7.5 * (0.7 + 0.6 * (1.0 - g))
	_crit_glare.scale = Vector3(s, s, s)
	_crit_glare_mat.set_shader_parameter("rot", t * 1.5)
	if t > 0.5:
		_crit_glare.visible = false
	# ударная волна по полу
	var f := t / 0.75
	if f < 1.0:
		var r := 0.05 + 0.9 * (1.0 - pow(1.0 - f, 2.4))
		_wave_mat.set_shader_parameter("r", r)
		_wave_mat.set_shader_parameter("width", 0.012 + 0.035 * f)
		_wave_mat.set_shader_parameter("trail", 0.12 + 0.2 * f)
		_set_power(_wave, 1.8 * pow(1.0 - f, 1.6))
	else:
		_wave.visible = false
	if t > 2.0:
		_t_crit = -1.0
		_wave.visible = false
		_crit_glare.visible = false
		for p in _crit:
			(p as GPUParticles3D).visible = false


func _update_level(t: float) -> void:
	var appear := clampf(t / 0.35, 0.0, 1.0)
	var back := 1.0 + 2.2 * pow(appear - 1.0, 3.0) + 1.2 * pow(appear - 1.0, 2.0)   # «перелёт» в конце
	_seal_mat.set_shader_parameter("r", 0.5 * (0.6 + 0.4 * back))   # кольцо радиуса _R на плоскости 4·_R
	_seal_mat.set_shader_parameter("rot", t * 0.12)
	var fade := 1.0 - smoothstep(1.5, 2.4, t)
	_set_power(_seal, 1.3 * minf(1.0, t / 0.12) * fade)
	var wf := t / 0.6
	_seal_mat.set_shader_parameter("wave_r", 0.25 + wf * 0.75)
	_seal_mat.set_shader_parameter("wave_p", maxf(0.0, 1.0 - wf) * 1.6)
	if _pillar != null:
		_pillar_mat.set_shader_parameter("reveal", minf(1.3, t / 0.35 * 1.3))
		_set_power(_pillar, 0.9 * (1.0 - smoothstep(0.45, 1.7, t)))
		if t > 1.75:
			_pillar.visible = false
	if t > 2.5:
		_t_lvl = -1.0
		_seal.visible = false
		_rise.visible = false
		if _pillar != null:
			_pillar.visible = false


func _update_gold(t: float) -> void:
	if _t_up < 0.0:
		var g := exp(-t * 10.0)
		_set_power(_aux_glare, 1.1 * g)
		var s := 4.0 * (0.8 + 0.4 * (1.0 - g))
		_aux_glare.scale = Vector3(s, s, s)
		_aux_glare_mat.set_shader_parameter("rot", 0.6 + t)
		if t > 0.5:
			_aux_glare.visible = false
	if t > 1.8:
		_t_gold = -1.0
		for g2 in _gold:
			(g2 as GPUParticles3D).visible = false
		if _t_up < 0.0:
			_aux_glare.visible = false


func _update_upgrade(t: float) -> void:
	var box: AABB = view.fx_bounds()
	var f := t / 0.75
	if f < 1.0:
		var e := f * f * (3.0 - 2.0 * f)
		_scan.position = Vector3(_seal.position.x, view.fx_floor_y() + 0.1 + e * box.size.y * 1.05, _seal.position.z)
		_scan_mat.set_shader_parameter("r", 0.82 - 0.25 * e)
		_set_power(_scan, 1.4 * sin(PI * f))
	else:
		_scan.visible = false
	# вспышка «установлено» там, куда сошёлся вихрь
	var k := t - 0.8
	if k > -0.08:
		_aux_glare.visible = true
		var g := exp(-maxf(k, 0.0) * 7.0) * clampf((k + 0.08) / 0.08, 0.0, 1.0)
		_set_power(_aux_glare, 1.3 * g)
		var s := 5.0 * (0.7 + 0.5 * (1.0 - g))
		_aux_glare.scale = Vector3(s, s, s)
		_aux_glare_mat.set_shader_parameter("rot", t * 2.0)
		if k >= 0.0 and k < 0.05 and q() >= 1:
			_flash_light(_up_target, Color(0.5, 0.75, 1.0), 6.0, 6.0, 14.0)
	if t > 1.5:
		_t_up = -1.0
		_scan.visible = false
		_swirl.visible = false
		_aux_glare.visible = false
