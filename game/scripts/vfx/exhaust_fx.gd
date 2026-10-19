extends FxModule
## Выхлоп: живое пламя из трубы, хлопки, дым, свет от пламени.
##
## Пламя — лента, повёрнутая к камере вокруг оси струи (цилиндрический билборд в вершинном
## шейдере); в пиксельном шейдере — бегущий шум, белое ядро → оранжевый → прозрачный красный
## край. В турбо пламя синее, длинное и ровное, с «алмазами» скачков уплотнения.
## Хлопок: вспышка-звезда, огненные шары, искры (вытянуты по скорости, отскакивают от пола),
## клуб тёмного дыма и вспышка света. Дым — мягкие клубы из шумовой текстуры: светлый
## обычно, густой чёрный при перегреве/дизеле. На отсечке — плевки пламени и искры.
## Всё создаётся один раз в setup(), в кадре меняются только параметры и положения.

const NOISE_SIZE := 128

# Общая часть шейдеров огня: цвет по «жару» h (0 — край, 1 — белое ядро).
const FIRE_FN := """
vec3 fire_ramp(float h, vec3 mid) {
	vec3 edge = mid * vec3(0.95, 0.36, 0.30);
	vec3 hot = mix(mid, vec3(1.0, 0.96, 0.88), 0.82);
	vec3 c = mix(edge, mid, smoothstep(0.10, 0.50, h));
	return mix(c, hot, smoothstep(0.50, 0.92, h));
}
"""

# Язык пламени: лента вдоль оси Y узла, развёрнута к камере.
const FLAME_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, skip_vertex_transform;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 col_mid : source_color = vec3(1.0, 0.55, 0.15);
uniform float flame_len = 2.0;
uniform float flame_w = 0.8;
uniform float power = 1.0;
uniform float turbo = 0.0;
uniform float lift = 0.10;
uniform float seed = 0.0;
uniform float energy = 1.0;

varying vec2 fuv;

FIRE_FN

float tri(float x) { return 1.0 - abs(fract(x) * 2.0 - 1.0); }

void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;
	vec3 ax = normalize(MODEL_MATRIX[1].xyz);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	float t = UV.y;
	float back = flame_w * 0.18;
	vec3 p = o + ax * mix(-back, flame_len, t) + vec3(0.0, 1.0, 0.0) * (t * t * flame_len * lift);
	vec3 tc = normalize(cam - p);
	vec3 side = normalize(cross(ax, tc) + vec3(0.0, 1e-4, 0.0));
	p += side * (UV.x - 0.5) * flame_w;
	VERTEX = (VIEW_MATRIX * vec4(p, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(tc, 0.0)).xyz);
	fuv = vec2((UV.x - 0.5) * 2.0, t);
}

void fragment() {
	float u = fuv.x;
	float t = clamp(fuv.y, 0.0, 1.0);
	float spd = mix(2.6, 5.0, turbo);
	float n1 = texture(noise_tex, vec2(u * 0.22 + seed, t * flame_len * 0.10 - TIME * spd * 0.22)).r;
	float n2 = texture(noise_tex, vec2(u * 0.55 - seed * 1.7, t * flame_len * 0.30 - TIME * spd * 0.75)).r;
	float calm = 1.0 - 0.75 * turbo;
	// волна по ширине и рваный край
	float wob = (n1 - 0.5) * 0.9 * t * calm;
	float w = (0.48 + 0.52 * smoothstep(0.0, 0.2, t)) * pow(1.0 - t, mix(0.7, 0.5, turbo));
	float d = abs(u + wob) / max(w, 1e-3);
	float rag = (n2 - 0.5) * (0.35 + 0.9 * t) * calm;
	float body = 1.0 - smoothstep(0.45, 1.0, d + rag);
	float tip = 1.0 - smoothstep(0.45, 1.0, t + (n1 - 0.5) * 0.45 * calm);
	float core = (1.0 - smoothstep(0.0, 0.5, d)) * (1.0 - smoothstep(0.0, mix(0.45, 0.25, turbo), t));
	float h = body * tip * (0.35 + 0.65 * pow(1.0 - t, 0.8)) + core * 0.45 + (n2 - 0.5) * 0.12;
	h = clamp(h, 0.0, 1.0);
	vec3 c = fire_ramp(h, col_mid);
	float a = clamp(h * 1.7, 0.0, 1.0) * body * tip;
	// форсаж: синяя оболочка прозрачнее, внутри — ряд ярких ромбов
	float k = t * 6.5 - 0.15;
	float dw = 0.42 * tri(k) * (1.0 - smoothstep(0.15, 0.95, t));
	float diamonds = (1.0 - smoothstep(0.6, 1.0, abs(u) / max(w * dw, 1e-3))) * step(0.5, k);
	diamonds *= turbo * (1.0 - smoothstep(0.35, 0.9, t)) * (0.85 + 0.3 * n2);
	a *= mix(1.0, 0.8, turbo);
	vec3 dcol = mix(vec3(1.0, 0.92, 0.95), col_mid, 0.25);
	vec3 outc = c * (0.55 + 2.1 * h) * a + dcol * diamonds * 2.6;
	ALBEDO = outc * power * energy;
	ALPHA = 1.0;
}
"""

# Светящееся жерло трубы / мягкий ореол (сферический билборд).
const GLOW_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 col : source_color = vec3(1.0, 0.55, 0.15);
uniform float power = 0.0;
uniform float core_k = 1.0;

void vertex() {
	mat4 mw = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mw * mat4(vec4(s, 0.0, 0.0, 0.0), vec4(0.0, s, 0.0, 0.0), vec4(0.0, 0.0, s, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r2 = dot(p, p);
	float halo = max(0.0, exp(-r2 * 4.5) - 0.011);
	float core = exp(-r2 * 26.0);
	vec3 hot = mix(col, vec3(1.0, 0.97, 0.9), 0.8);
	ALBEDO = (col * halo * 1.1 + hot * core * 2.2 * core_k) * power;
	ALPHA = 1.0;
}
"""

# Вспышка хлопка: ядро, ореол и лучи-звезда.
const FLASH_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 col : source_color = vec3(1.0, 0.55, 0.15);
uniform float power = 0.0;
uniform float rot = 0.0;

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
	float halo = max(0.0, exp(-r * r * 7.0) - 0.001);
	float core = exp(-r * r * 45.0);
	float rays = pow(max(0.0, cos(ang * 3.0 + rot)), 28.0) + 0.6 * pow(max(0.0, cos(ang * 4.0 - rot * 1.7 + 0.7)), 44.0);
	rays *= max(0.0, 1.0 - r) * max(0.0, 1.0 - r);
	vec3 hot = mix(col, vec3(1.0, 0.97, 0.9), 0.75);
	ALBEDO = (col * halo * 1.4 + hot * core * 3.0 + hot * rays * 1.6) * power;
	ALPHA = 1.0;
}
"""

# Искра: полоска вдоль скорости частицы (ось Y частицы — по скорости, particle_flag_align_y).
const SPARK_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, skip_vertex_transform;

uniform float streak = 0.5;
uniform float thick = 0.05;
uniform float boost = 3.0;

varying vec2 suv;

void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;
	vec3 ay = MODEL_MATRIX[1].xyz;
	float sc = length(ay);
	vec3 dir = ay / max(sc, 1e-4);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 tc = normalize(cam - o);
	vec3 side = normalize(cross(dir, tc) + vec3(0.0, 1e-4, 0.0));
	float age = INSTANCE_CUSTOM.y;
	float L = streak * sc * (1.0 - 0.65 * age) + thick * 2.0;
	vec3 p = o + dir * (VERTEX.y - 0.5) * L + side * VERTEX.x * 2.0 * thick * sc;
	VERTEX = (VIEW_MATRIX * vec4(p, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(tc, 0.0)).xyz);
	suv = vec2(UV.x * 2.0 - 1.0, UV.y);
}

void fragment() {
	float across = 1.0 - suv.x * suv.x;
	float along = mix(1.0, 0.15, suv.y);
	float s = across * along;
	ALBEDO = COLOR.rgb * boost * s * COLOR.a;
	ALPHA = 1.0;
}
"""

# Огненный шар хлопка: билборд с шумом, остывает с возрастом частицы.
const BALL_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 col_mid : source_color = vec3(1.0, 0.55, 0.15);
uniform float energy = 1.0;

varying vec4 cust;
varying float seed;

FIRE_FN

void vertex() {
	float a = INSTANCE_CUSTOM.x;
	float c = cos(a);
	float s = sin(a);
	mat4 mw = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	mw = mw * mat4(vec4(c, -s, 0.0, 0.0), vec4(s, c, 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	float sc = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mw * mat4(vec4(sc, 0.0, 0.0, 0.0), vec4(0.0, sc, 0.0, 0.0), vec4(0.0, 0.0, sc, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	cust = INSTANCE_CUSTOM;
	seed = fract(float(INSTANCE_ID) * 0.6180339);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float age = cust.y;
	float n = texture(noise_tex, UV * 0.45 + vec2(seed, seed * 1.9) + vec2(0.0, age * 0.35)).r;
	float n2 = texture(noise_tex, UV * 1.1 - vec2(seed * 2.3, age * 0.6)).r;
	float h = (1.0 - r) * 1.45 + (n - 0.5) * 1.1 + (n2 - 0.5) * 0.5 - age * 1.05;
	h = clamp(h, 0.0, 1.0);
	float a = smoothstep(0.02, 0.3, h) * (1.0 - smoothstep(0.75, 1.0, r));
	vec3 col = fire_ramp(h, col_mid);
	ALBEDO = col * (0.5 + 2.0 * h) * a * COLOR.a * energy;
	ALPHA = 1.0;
}
"""

# Дым: мягкие клубы из шумовой текстуры, сверху светлее (подсветка сверху), у трубы
# подкрашены пламенем.
const SMOKE_SHADER := """
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 col_light : source_color = vec3(0.62, 0.63, 0.66);
uniform vec3 col_dark : source_color = vec3(0.035, 0.035, 0.04);
uniform float dark = 0.0;
uniform float density = 1.0;
uniform vec3 glow_col : source_color = vec3(1.0, 0.5, 0.15);
uniform float glow = 0.0;

varying vec4 cust;
varying float vy;
varying float seed;

void vertex() {
	float a = INSTANCE_CUSTOM.x;
	float c = cos(a);
	float s = sin(a);
	mat4 mw = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	mw = mw * mat4(vec4(c, -s, 0.0, 0.0), vec4(s, c, 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	float sc = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mw * mat4(vec4(sc, 0.0, 0.0, 0.0), vec4(0.0, sc, 0.0, 0.0), vec4(0.0, 0.0, sc, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	vy = (-s * VERTEX.x + c * VERTEX.y) * 2.0;
	cust = INSTANCE_CUSTOM;
	seed = fract(float(INSTANCE_ID) * 0.7548776);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float age = cust.y;
	vec2 off = vec2(seed, seed * 1.618);
	float n1 = texture(noise_tex, UV * 0.42 + off + vec2(0.0, -age * 0.18)).r;
	float n2 = texture(noise_tex, UV * 1.05 + off.yx - vec2(age * 0.3, 0.0)).r;
	float n = n1 * 0.65 + n2 * 0.35;
	float mask = 1.0 - smoothstep(0.25, 1.0, r + (n - 0.5) * 0.9);
	float dens = clamp(mask * (0.4 + n * 1.1) - 0.12, 0.0, 1.0);
	float top = clamp(vy * 0.5 + 0.5, 0.0, 1.0);
	float shade = 0.62 + 0.38 * top + (n2 - 0.5) * 0.3;
	vec3 base = mix(col_light, col_dark, dark) * shade;
	float g = glow * (1.0 - smoothstep(0.0, 0.3, age)) * (1.0 - top * 0.6);
	ALBEDO = base + glow_col * g * 1.2;
	ALPHA = clamp(dens * COLOR.a * density, 0.0, 1.0);
}
"""

static var _noise: NoiseTexture2D = null
static var _shader_cache: Dictionary = {}

var _flame: MeshInstance3D
var _flame_mat: ShaderMaterial
var _mouth: MeshInstance3D
var _mouth_mat: ShaderMaterial
var _flash: MeshInstance3D
var _flash_mat: ShaderMaterial
var _light: OmniLight3D
var _smoke: GPUParticles3D
var _smoke_pm: ParticleProcessMaterial
var _smoke_mat: ShaderMaterial
var _ball_mat: ShaderMaterial
var _sparks: Array = []        # пул из двух выстрелов искр: хлопки идут чаще, чем живут искры
var _balls: Array = []
var _puffs: Array = []
var _limit_sparks: GPUParticles3D
var _collider: GPUParticlesCollisionBox3D
var _slot: int = 0

var _col := Color(1.0, 0.55, 0.15)
var _rev: float = 0.0
var _pop: float = 0.0
var _pop_k: float = 1.0
var _flash_t: float = 0.0
var _flash_rot: float = 0.0
var _spit: float = 0.0
var _turbo: float = 0.0
var _dark: float = 0.0
var _thick: float = 0.0
var _limit_t: float = 0.0
var _last_pop: float = -1.0
var _time: float = 0.0
var _jit: float = 0.5
var _warm: bool = false
var _smoke_v: float = -1.0


# ---------------------------------------------------------------------
# Ресурсы (общие для всех экранов с мотором)
# ---------------------------------------------------------------------

static func _noise_tex() -> NoiseTexture2D:
	if _noise != null:
		return _noise
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = 11
	n.frequency = 0.035
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


static func _shader(key: String, code: String) -> Shader:
	if _shader_cache.has(key):
		return _shader_cache[key]
	var s := Shader.new()
	s.code = code.replace("FIRE_FN", FIRE_FN)
	_shader_cache[key] = s
	return s


func _mat(key: String, code: String, prio: int = 0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader(key, code)
	m.render_priority = prio
	return m


## Базис, у которого ось Y смотрит вдоль dir.
static func _basis_y(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var ref := Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


static func _curve(points: Array) -> CurveTexture:
	var c := Curve.new()
	for p in points:
		c.add_point(p)
	var t := CurveTexture.new()
	t.curve = c
	t.width = 64
	return t


static func _ramp(offsets: Array, colors: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 64
	return t


func _quad(m: Material, size: float = 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(size, size)
	mi.mesh = qm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 2.0
	add_child(mi)
	return mi


func _particles(amount: int, life: float, pm: ParticleProcessMaterial, mat: Material) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(1, amount)
	p.lifetime = life
	p.process_material = pm
	var qm := QuadMesh.new()
	qm.material = mat
	p.draw_pass_1 = qm
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-14, -14, -14), Vector3(28, 28, 28))
	p.emitting = false
	add_child(p)
	return p


# ---------------------------------------------------------------------
# Создание
# ---------------------------------------------------------------------

func setup() -> void:
	var n := pq()
	var hi := q() >= 2
	var noise := _noise_tex()

	# язык пламени: лента 2×13 вершин, форма задаётся шейдером
	_flame_mat = _mat("flame", FLAME_SHADER, 2)
	_flame_mat.set_shader_parameter("noise_tex", noise)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := 12
	for i in rows + 1:
		var v := float(i) / rows
		for k in 2:
			st.set_uv(Vector2(k, v))
			st.add_vertex(Vector3(k - 0.5, v, 0))
	for i in rows:
		var a := i * 2
		st.add_index(a)
		st.add_index(a + 1)
		st.add_index(a + 2)
		st.add_index(a + 1)
		st.add_index(a + 3)
		st.add_index(a + 2)
	_flame = MeshInstance3D.new()
	_flame.mesh = st.commit()
	_flame.material_override = _flame_mat
	_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flame.custom_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 16, 16))
	_flame.visible = false
	add_child(_flame)

	_mouth_mat = _mat("glow", GLOW_SHADER, 3)
	_mouth = _quad(_mouth_mat)
	_mouth.visible = false
	_flash_mat = _mat("flash", FLASH_SHADER, 4)
	_flash = _quad(_flash_mat)
	_flash.visible = false

	_light = make_omni(Color(1.0, 0.5, 0.15), 10.0)
	_light.light_specular = 0.6
	_light.omni_attenuation = 1.4

	# дым
	_smoke_mat = _mat("smoke", SMOKE_SHADER, -2)
	_smoke_mat.set_shader_parameter("noise_tex", noise)
	_smoke_pm = ParticleProcessMaterial.new()
	_smoke_pm.direction = Vector3(0, 1, 0)
	_smoke_pm.spread = 14.0
	_smoke_pm.initial_velocity_min = 1.0
	_smoke_pm.initial_velocity_max = 2.0
	_smoke_pm.damping_min = 1.6
	_smoke_pm.damping_max = 2.4
	_smoke_pm.gravity = Vector3(0, 0.9, 0)
	_smoke_pm.angle_min = -180.0
	_smoke_pm.angle_max = 180.0
	_smoke_pm.angular_velocity_min = -25.0
	_smoke_pm.angular_velocity_max = 25.0
	_smoke_pm.scale_min = 0.7
	_smoke_pm.scale_max = 1.1
	_smoke_pm.scale_curve = _curve([Vector2(0, 0.35), Vector2(0.4, 0.75), Vector2(1, 1.0)])
	_smoke_pm.color_ramp = _ramp([0.0, 0.12, 0.55, 1.0], [Color(1, 1, 1, 0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0)])
	_smoke_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_smoke_pm.emission_sphere_radius = 0.12
	_smoke_pm.lifetime_randomness = 0.3
	if n >= 1:
		_smoke_pm.turbulence_enabled = true
		_smoke_pm.turbulence_noise_strength = 1.2
		_smoke_pm.turbulence_noise_scale = 4.0
		_smoke_pm.turbulence_influence_min = 0.04
		_smoke_pm.turbulence_influence_max = 0.1
	_smoke = _particles([10, 28, 56][n], 2.6, _smoke_pm, _smoke_mat)
	(_smoke.draw_pass_1 as QuadMesh).size = Vector2(2.6, 2.6)

	# огненные шары хлопка
	_ball_mat = _mat("ball", BALL_SHADER, 1)
	_ball_mat.set_shader_parameter("noise_tex", noise)
	var bpm := ParticleProcessMaterial.new()
	bpm.direction = Vector3(0, 1, 0)
	bpm.spread = 9.0
	bpm.initial_velocity_min = 3.0
	bpm.initial_velocity_max = 10.0
	bpm.damping_min = 9.0
	bpm.damping_max = 14.0
	bpm.gravity = Vector3(0, 1.5, 0)
	bpm.angle_min = -180.0
	bpm.angle_max = 180.0
	bpm.angular_velocity_min = -90.0
	bpm.angular_velocity_max = 90.0
	bpm.scale_min = 0.6
	bpm.scale_max = 1.1
	bpm.scale_curve = _curve([Vector2(0, 0.45), Vector2(0.25, 1.0), Vector2(1, 1.25)])
	bpm.color_ramp = _ramp([0.0, 0.6, 1.0], [Color(1, 1, 1, 1), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
	bpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	bpm.emission_sphere_radius = 0.15
	bpm.lifetime_randomness = 0.35
	for i in 2:
		var b := _particles([4, 7, 10][n], 0.45, bpm, _ball_mat)
		(b.draw_pass_1 as QuadMesh).size = Vector2(1.5, 1.5)
		b.one_shot = true
		b.explosiveness = 0.85
		_balls.append(b)

	# искры хлопка: вытянуты по скорости, падают, на «Высоком» отскакивают от пола
	var spark_mat := _mat("spark", SPARK_SHADER, 1)
	var spm := ParticleProcessMaterial.new()
	spm.direction = Vector3(0, 1, 0)
	spm.spread = 22.0
	spm.initial_velocity_min = 7.0
	spm.initial_velocity_max = 15.0
	spm.damping_min = 1.0
	spm.damping_max = 3.0
	spm.gravity = Vector3(0, -16, 0)
	spm.particle_flag_align_y = true
	spm.scale_min = 0.6
	spm.scale_max = 1.2
	spm.color_ramp = _ramp([0.0, 0.25, 0.7, 1.0], [Color(1.0, 0.95, 0.8, 1), Color(1.0, 0.75, 0.3, 1), Color(1.0, 0.35, 0.08, 0.8), Color(0.8, 0.1, 0.02, 0)])
	spm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	spm.emission_sphere_radius = 0.15
	spm.lifetime_randomness = 0.45
	var bounce := hi and not compat()
	if bounce:
		spm.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
		spm.collision_bounce = 0.35
		spm.collision_friction = 0.3
	for i in 2:
		var s := _particles([0, 22, 44][n], 0.9, spm, spark_mat)
		s.one_shot = true
		s.explosiveness = 0.92
		if bounce:
			s.collision_base_size = 0.02
		s.visible = n > 0
		_sparks.append(s)
	if bounce:
		_collider = GPUParticlesCollisionBox3D.new()
		_collider.size = Vector3(80, 2, 80)
		_collider.position = Vector3(0, view.fx_floor_y() - 1.0, 0)
		add_child(_collider)

	# клуб тёмного дыма после хлопка
	var ppm := ParticleProcessMaterial.new()
	ppm.direction = Vector3(0, 1, 0)
	ppm.spread = 20.0
	ppm.initial_velocity_min = 2.0
	ppm.initial_velocity_max = 5.0
	ppm.damping_min = 4.0
	ppm.damping_max = 6.0
	ppm.gravity = Vector3(0, 1.4, 0)
	ppm.angle_min = -180.0
	ppm.angle_max = 180.0
	ppm.angular_velocity_min = -40.0
	ppm.angular_velocity_max = 40.0
	ppm.scale_min = 0.6
	ppm.scale_max = 1.0
	ppm.scale_curve = _curve([Vector2(0, 0.3), Vector2(0.5, 0.8), Vector2(1, 1.1)])
	ppm.color_ramp = _ramp([0.0, 0.1, 1.0], [Color(1, 1, 1, 0), Color(1, 1, 1, 0.85), Color(1, 1, 1, 0)])
	ppm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	ppm.emission_sphere_radius = 0.25
	var puff_mat: ShaderMaterial = _smoke_mat.duplicate()
	puff_mat.set_shader_parameter("dark", 0.75)
	puff_mat.set_shader_parameter("density", 0.9)
	for i in 2:
		var p := _particles([0, 6, 10][n], 1.4, ppm, puff_mat)
		(p.draw_pass_1 as QuadMesh).size = Vector2(2.2, 2.2)
		p.one_shot = true
		p.explosiveness = 0.8
		p.visible = n > 0
		_puffs.append(p)

	# искры отсечки: мелкие, пока обороты бьются об ограничитель
	var lpm: ParticleProcessMaterial = spm.duplicate()
	lpm.initial_velocity_min = 4.0
	lpm.initial_velocity_max = 9.0
	lpm.spread = 16.0
	lpm.scale_min = 0.4
	lpm.scale_max = 0.8
	_limit_sparks = _particles([0, 10, 20][n], 0.5, lpm, spark_mat)
	_limit_sparks.visible = n > 0


# ---------------------------------------------------------------------
# События
# ---------------------------------------------------------------------

func on_event(event_name: String, _data: Dictionary) -> void:
	match event_name:
		"pop":
			_do_pop(1.0)
		"turbo_start":
			_do_pop(1.35)
		"limiter":
			_spit = maxf(_spit, 0.7 + 0.3 * randf())
			_limit_t = 0.25


func _do_pop(k: float) -> void:
	# «turbo_start» и следующий за ним «pop» приходят в одном кадре — второй не дублируем
	if _time - _last_pop < 0.06:
		_pop_k = maxf(_pop_k, k)
		return
	_last_pop = _time
	_pop = 1.0
	_pop_k = k
	_flash_t = 1.0
	_flash_rot = randf() * TAU
	_slot = (_slot + 1) % 2
	var b: GPUParticles3D = _balls[_slot]
	b.restart()
	b.emitting = true
	if pq() > 0:
		var s: GPUParticles3D = _sparks[_slot]
		s.restart()
		s.emitting = true
		var p: GPUParticles3D = _puffs[_slot]
		p.restart()
		p.emitting = true


func warmup(on: bool) -> void:
	_warm = on
	if on:
		for arr in [_balls, _sparks, _puffs]:
			for p in arr:
				p.restart()
				p.emitting = true
		_limit_sparks.emitting = true
		_smoke.emitting = true


# ---------------------------------------------------------------------
# Кадр
# ---------------------------------------------------------------------

func update(delta: float, st: Dictionary) -> void:
	_time += delta
	var tail: Vector3 = view.fx_tail()
	var dir: Vector3 = view.fx_tail_dir()
	var b := _basis_y(dir)
	var ratio: float = st.ratio
	var throttle: bool = st.throttle
	var demo: bool = st.demo
	var fc: Color = st.flame_col
	_col = _col.lerp(fc, 1.0 - exp(-delta * 8.0))
	_turbo = move_toward(_turbo, 1.0 if st.turbo else 0.0, delta * 3.0)
	var want_rev := smoothstep(0.3, 1.0, ratio) if throttle else 0.0
	if demo:
		want_rev = smoothstep(0.7, 1.1, ratio) * 0.5
	_rev = lerpf(_rev, want_rev, 1.0 - exp(-delta * 6.0))
	_pop = maxf(0.0, _pop - delta * 3.0)
	_flash_t = maxf(0.0, _flash_t - delta * 7.0)
	_spit = maxf(0.0, _spit - delta * 9.0)
	_limit_t = maxf(0.0, _limit_t - delta)

	# сила пламени: газ — небольшой язык, хлопок — большой выстрел, турбо — длинный форсаж
	var pop_f := pow(_pop, 0.55) * _pop_k
	var turbo_f := _turbo * (0.8 if throttle else 0.3)
	var f := maxf(maxf(_rev * 0.3, turbo_f), maxf(pop_f, _spit * 0.42))
	_jit = lerpf(_jit, randf(), 0.55)
	var flick := 0.86 + 0.28 * _jit
	var show := f > 0.01 or _warm
	_flame.visible = show
	var col3 := Vector3(_col.r, _col.g, _col.b)
	if show:
		var fl := (0.5 + 3.3 * f + 0.8 * pop_f) * flick * (1.0 + 0.2 * _turbo)
		var fw := (0.55 + 0.75 * f + 0.25 * pop_f) * (0.92 + 0.16 * _jit)
		_flame.transform = Transform3D(b, tail)
		_flame_mat.set_shader_parameter("flame_len", fl)
		_flame_mat.set_shader_parameter("flame_w", fw)
		_flame_mat.set_shader_parameter("power", maxf(0.05, clampf(0.35 + f, 0.0, 1.3) * (0.9 + 0.2 * _jit)))
		_flame_mat.set_shader_parameter("turbo", _turbo)
		_flame_mat.set_shader_parameter("col_mid", col3)

	# жерло трубы: светится от пламени и нагрева
	var mouth_p := 0.12 * _rev + 0.9 * f + 0.25 * float(st.heat) * float(throttle)
	_mouth.visible = mouth_p > 0.01 or _warm
	if _mouth.visible:
		_mouth.position = tail + dir * 0.15
		_mouth.scale = Vector3.ONE * (0.9 + 1.3 * f)
		_mouth_mat.set_shader_parameter("col", col3)
		_mouth_mat.set_shader_parameter("power", mouth_p * flick)

	# вспышка хлопка
	_flash.visible = _flash_t > 0.0 or _warm
	if _flash.visible:
		var e := _flash_t * _flash_t
		_flash.position = tail + dir * 0.7
		_flash.scale = Vector3.ONE * (2.2 + 2.6 * (1.0 - _flash_t)) * _pop_k
		_flash_mat.set_shader_parameter("col", col3)
		_flash_mat.set_shader_parameter("power", e * 1.4)
		_flash_mat.set_shader_parameter("rot", _flash_rot + (1.0 - _flash_t) * 0.6)

	# огонь и искры хлопка вылетают из трубы
	var xf := Transform3D(b, tail)
	for arr in [_balls, _sparks, _puffs]:
		for p in arr:
			p.transform = xf
	_ball_mat.set_shader_parameter("col_mid", col3)

	# свет от пламени
	var le := (1.2 * _rev + 2.5 * _turbo * (1.0 if throttle else 0.4) + 9.0 * _flash_t * _flash_t + 4.0 * pop_f + 2.0 * _spit) * flick
	_light.visible = q() >= 1 and (le > 0.03 or _warm)
	if _light.visible:
		_light.position = tail + dir * 1.4 + Vector3(0, 0.4, 0)
		_light.light_color = _col
		_light.light_energy = le
		_light.omni_range = 7.0 + 5.0 * minf(1.0, f)

	# дым
	var black: bool = st.black
	_dark = move_toward(_dark, 1.0 if black else 0.0, delta * 1.5)
	var want_thick := clampf(0.25 + 0.75 * ratio * (1.0 if throttle else 0.5), 0.0, 1.0)
	if black:
		want_thick = 1.0
	_thick = lerpf(_thick, want_thick, 1.0 - exp(-delta * 3.0))
	_smoke.transform = xf
	_smoke.emitting = true
	_smoke.amount_ratio = clampf(0.35 + 0.65 * _thick, 0.05, 1.0)
	var v := snappedf(1.0 + 3.5 * ratio * (1.0 if throttle else 0.4), 0.1)
	if v != _smoke_v:
		_smoke_v = v
		_smoke_pm.initial_velocity_min = v * 0.7
		_smoke_pm.initial_velocity_max = v * 1.2
	_smoke_mat.set_shader_parameter("dark", _dark)
	_smoke_mat.set_shader_parameter("density", lerpf(0.32, 0.55, _thick) + 0.4 * _dark)
	_smoke_mat.set_shader_parameter("glow_col", col3)
	_smoke_mat.set_shader_parameter("glow", minf(1.0, f * 1.4))

	# отсечка
	_limit_sparks.transform = xf
	_limit_sparks.emitting = (_limit_t > 0.0 and pq() > 0) or _warm
