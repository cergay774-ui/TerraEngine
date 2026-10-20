extends FxModule
## Нагрев и турбо.
##
## Перегрев: из головки мотора поднимается пар — мягкие клубы-завитки (шум в шейдере, сверху
##   светлее, снизу подсвечены жаром), гуще с нагревом; в момент перегрева — выброс пара
##   столбом, по мотору летят угольки, красно-оранжевый свет дышит. При остывании всё
##   плавно стихает, а в момент восстановления — последний мягкий выдох пара.
## Турбо: голубой ореол у крыльчатки, два энергетических кольца поперёк оси турбины
##   (бегущие «кометы», электрическое дрожание), голубые штрихи воздуха, закрученные
##   вихрем в фильтр, голубой свет; на старте турбо — вспышка и кольцевая волна.
## Всё создаётся один раз в setup(); в кадре меняются только параметры и положения.

const SP := preload("res://scripts/vfx/sparks_fx.gd")

# Пар: клуб-завиток, повёрнутый билборд (угол — INSTANCE_CUSTOM.x, возраст — .y).
const STEAM_SHADER := """
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 col_lit : source_color = vec3(0.88, 0.9, 0.94);
uniform vec3 col_shade : source_color = vec3(0.36, 0.38, 0.44);
uniform vec3 warm : source_color = vec3(1.0, 0.4, 0.14);
uniform float warm_k = 0.0;
uniform float density = 0.5;
uniform float intensity = 1.0;

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
	float n1 = texture(noise_tex, UV * 0.32 + off + vec2(0.0, age * 0.22)).r;
	float n2 = texture(noise_tex, UV * 0.75 + off.yx + vec2(n1 * 0.35, -age * 0.35)).r;
	float wisp = n1 * 0.6 + n2 * 0.4;
	float mask = 1.0 - smoothstep(0.2, 1.0, r + (0.5 - wisp) * 1.0);
	float dens = smoothstep(0.05, 0.75, mask * (0.25 + wisp * 1.15));
	dens *= 1.0 - age * 0.45;
	float top = clamp(vy * 0.5 + 0.5, 0.0, 1.0);
	vec3 c = mix(col_shade, col_lit, clamp(0.3 + top * 0.6 + (wisp - 0.5) * 0.9, 0.0, 1.0));
	c += warm * warm_k * (1.0 - top * 0.7) * (1.0 - smoothstep(0.0, 0.6, age));
	ALBEDO = c;
	ALPHA = clamp(dens * COLOR.a * density, 0.0, 1.0) * intensity;
}
"""

# Ореол: билборд, придвинутый к камере (чтобы не резался корпусом турбины).
const HALO_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, skip_vertex_transform;

uniform vec3 col : source_color = vec3(0.35, 0.6, 1.0);
uniform float power = 0.0;
uniform float pull = 1.0;
uniform float core_k = 1.0;

void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 tc = normalize(INV_VIEW_MATRIX[3].xyz - o);
	vec3 p = o + tc * pull + (INV_VIEW_MATRIX[0].xyz * VERTEX.x + INV_VIEW_MATRIX[1].xyz * VERTEX.y) * s;
	VERTEX = (VIEW_MATRIX * vec4(p, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r2 = dot(p, p);
	float halo = max(0.0, exp(-r2 * 3.2) - 0.04);
	float core = exp(-r2 * 26.0);
	float flick = 0.88 + 0.12 * sin(TIME * 47.0) * sin(TIME * 29.0);
	vec3 hot = mix(col, vec3(0.92, 0.97, 1.0), 0.65);
	ALBEDO = (col * halo * 0.85 + hot * core * 1.3 * core_k) * power * flick;
	ALPHA = 1.0;
}
"""

# Энергетическое кольцо поперёк оси турбины: бегущие «кометы», дрожание, мягкое свечение.
const TURBO_RING := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 col : source_color = vec3(0.35, 0.62, 1.0);
uniform float power = 0.0;
uniform float r = 0.7;
uniform float spin = 2.5;
uniform float arcs = 3.0;
uniform float seed = 0.0;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float d = length(p);
	float ang = atan(p.y, p.x) / 6.2831853;
	float n = texture(noise_tex, vec2(ang * 3.0 + TIME * 1.7 + seed, d * 0.8 - TIME * 0.9)).r;
	float jit = (n - 0.5) * 0.07;
	float x = (d - r - jit) / 0.022;
	float band = exp(-x * x);
	float y = (d - r) / 0.13;
	float glow = exp(-y * y) * 0.22;
	float a = fract(ang * arcs - TIME * spin + seed);
	float comet = pow(a, 5.0) * (1.0 - smoothstep(0.96, 1.0, a));
	float z = (d - r) / 0.007;
	float thin = exp(-z * z) * 0.3;
	vec3 hot = mix(col, vec3(0.9, 0.97, 1.0), 0.7);
	float e = band * (0.18 + comet * 2.4) * (0.55 + 0.9 * n) + glow * (0.5 + comet) + thin;
	ALBEDO = mix(col, hot, clamp(comet * band, 0.0, 1.0)) * e * power * (1.0 - smoothstep(0.92, 1.0, d));
	ALPHA = 1.0;
}
"""

# пар и угольки
var _steam: GPUParticles3D
var _steam_mat: ShaderMaterial
var _vent: GPUParticles3D
var _vent_mat: ShaderMaterial
var _embers: GPUParticles3D
var _ember_draw: ShaderMaterial
var _heat_light: OmniLight3D
# турбо
var _turbo_light: OmniLight3D
var _halo: MeshInstance3D
var _halo_mat: ShaderMaterial
var _ring_a: MeshInstance3D
var _ring_b: MeshInstance3D
var _ring_a_mat: ShaderMaterial
var _ring_b_mat: ShaderMaterial
var _vortex: GPUParticles3D
var _vortex_pm: ShaderMaterial
var _vortex_draw: ShaderMaterial
var _kick_glare: MeshInstance3D
var _kick_glare_mat: ShaderMaterial
var _pulse: MeshInstance3D
var _pulse_mat: ShaderMaterial

var _warm: bool = false
var _hot: float = 0.0          # сглаженный «пар» 0..1
var _ember_k: float = 0.0
var _tb: float = 0.0           # сглаженное турбо 0..1
var _kick: float = 0.0         # вспышка старта турбо 1 → 0
var _vent_t: float = -1.0
var _flare: float = 0.0        # всплеск света в момент перегрева
var _k: float = 1.0            # масштаб мотора (единиц корня на единицу модели)
var _axis: Vector3 = Vector3.RIGHT
var _turb: Vector3 = Vector3.INF
var _head: Vector3 = Vector3.ZERO
var _time: float = 0.0
var _intensity_mats: Array = []


func setup() -> void:
	var noise := SP.noise_tex()
	var n := pq()
	var hi := q() >= 2

	# --- пар ---
	_steam_mat = SP.make_mat("steam", STEAM_SHADER, 0)
	_steam_mat.set_shader_parameter("noise_tex", noise)
	_steam_mat.set_shader_parameter("density", 0.55)
	_steam_mat.set_shader_parameter("warm_k", 0.6)
	_intensity_mats.append(_steam_mat)
	var spm := ParticleProcessMaterial.new()
	spm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	spm.emission_box_extents = Vector3(1.5, 0.2, 1.0)
	spm.direction = Vector3(0, 1, 0)
	spm.spread = 14.0
	spm.initial_velocity_min = 1.4
	spm.initial_velocity_max = 3.0
	spm.gravity = Vector3(0.35, 1.1, 0.0)
	spm.damping_min = 0.4
	spm.damping_max = 0.9
	spm.angle_min = -180.0
	spm.angle_max = 180.0
	spm.angular_velocity_min = -40.0
	spm.angular_velocity_max = 40.0
	spm.scale_min = 0.75
	spm.scale_max = 1.25
	spm.scale_curve = _curve([Vector2(0, 0.3), Vector2(0.35, 0.75), Vector2(1, 1.45)])
	spm.color_ramp = SP.ramp([0.0, 0.12, 0.55, 1.0], [Color(1, 1, 1, 0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
	spm.lifetime_randomness = 0.3
	if hi and not compat():
		spm.turbulence_enabled = true
		spm.turbulence_noise_strength = 1.4
		spm.turbulence_noise_scale = 5.0
		spm.turbulence_noise_speed_random = 0.4
		spm.turbulence_influence_min = 0.04
		spm.turbulence_influence_max = 0.12
	_steam = _particles(_count([0, 22, 38]), 2.4, spm, _steam_mat, 2.6)
	_steam.one_shot = false
	_steam.explosiveness = 0.0
	_steam.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH

	# --- выброс пара в момент перегрева ---
	_vent_mat = _steam_mat.duplicate()
	_vent_mat.set_shader_parameter("density", 0.8)
	_vent_mat.set_shader_parameter("warm_k", 1.0)
	_intensity_mats.append(_vent_mat)
	var vpm := ParticleProcessMaterial.new()
	vpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	vpm.emission_sphere_radius = 0.5
	vpm.direction = Vector3(0, 1, 0)
	vpm.spread = 22.0
	vpm.initial_velocity_min = 6.0
	vpm.initial_velocity_max = 11.0
	vpm.damping_min = 5.0
	vpm.damping_max = 8.0
	vpm.gravity = Vector3(0.3, 1.2, 0.0)
	vpm.angle_min = -180.0
	vpm.angle_max = 180.0
	vpm.angular_velocity_min = -60.0
	vpm.angular_velocity_max = 60.0
	vpm.scale_min = 0.7
	vpm.scale_max = 1.2
	vpm.scale_curve = _curve([Vector2(0, 0.25), Vector2(0.3, 0.9), Vector2(1, 1.6)])
	vpm.color_ramp = SP.ramp([0.0, 0.06, 0.5, 1.0], [Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0)])
	vpm.lifetime_randomness = 0.35
	_vent = _particles(_count([0, 12, 20]), 1.9, vpm, _vent_mat, 3.0)
	_vent.explosiveness = 0.75
	_vent.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH

	# --- угольки ---
	_ember_draw = SP.make_mat("star_draw", SP.STAR_DRAW, 1)
	_ember_draw.set_shader_parameter("ramp", SP.ramp([0.0, 0.1, 0.55, 1.0], [
		Color(1.0, 0.8, 0.4, 0.0), Color(1.0, 0.6, 0.2, 1.0), Color(0.95, 0.3, 0.06, 0.85), Color(0.5, 0.06, 0.01, 0.0)]))
	_ember_draw.set_shader_parameter("boost", 2.6)
	_ember_draw.set_shader_parameter("twinkle", 1.0)
	_intensity_mats.append(_ember_draw)
	var epm := ParticleProcessMaterial.new()
	epm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	epm.emission_box_extents = Vector3(2.0, 1.0, 1.5)
	epm.direction = Vector3(0, 1, 0)
	epm.spread = 35.0
	epm.initial_velocity_min = 0.8
	epm.initial_velocity_max = 2.4
	epm.gravity = Vector3(0.2, 0.9, 0.0)
	epm.damping_min = 0.2
	epm.damping_max = 0.6
	epm.scale_min = 0.16
	epm.scale_max = 0.32
	epm.lifetime_randomness = 0.4
	if hi and not compat():
		epm.turbulence_enabled = true
		epm.turbulence_noise_strength = 2.5
		epm.turbulence_noise_scale = 3.0
		epm.turbulence_influence_min = 0.08
		epm.turbulence_influence_max = 0.2
	_embers = _particles(_count([0, 14, 30]), 1.8, epm, _ember_draw, 1.0)
	_embers.one_shot = false
	_embers.explosiveness = 0.0

	if q() >= 1:
		_heat_light = make_omni(Color(1.0, 0.32, 0.08), 13.0)
		_heat_light.visible = false

	# --- турбо ---
	_turbo_light = make_omni(Color(0.3, 0.55, 1.0), 16.0)
	_turbo_light.visible = false
	_halo_mat = SP.make_mat("turbo_halo", HALO_SHADER, 2)
	_halo = SP.make_quad(self, _halo_mat)
	if q() >= 1:
		_ring_a_mat = SP.make_mat("turbo_ring", TURBO_RING, 1)
		_ring_a_mat.set_shader_parameter("noise_tex", noise)
		_ring_a = SP.make_quad(self, _ring_a_mat)
		_ring_b_mat = _ring_a_mat.duplicate()
		_ring_b_mat.set_shader_parameter("spin", -3.4)
		_ring_b_mat.set_shader_parameter("arcs", 2.0)
		_ring_b_mat.set_shader_parameter("seed", 0.37)
		_ring_b = SP.make_quad(self, _ring_b_mat)
	_vortex_pm = SP.make_mat("helix_proc", SP.HELIX_PROC)
	_vortex_pm.set_shader_parameter("turns", 1.2)
	_vortex_pm.set_shader_parameter("jitter", 0.5)
	_vortex_pm.set_shader_parameter("h_rand", 0.1)
	_vortex_pm.set_shader_parameter("life_rand", 0.3)
	_vortex_pm.set_shader_parameter("size_rand", 0.4)
	_vortex_pm.set_shader_parameter("streak", 0.07)
	_vortex_pm.set_shader_parameter("ease", 1.6)
	_vortex_draw = SP.make_mat("spark_draw", SP.SPARK_DRAW, 1)
	_vortex_draw.set_shader_parameter("ramp", SP.ramp([0.0, 0.25, 0.75, 1.0], [
		Color(0.4, 0.65, 1.0, 0.0), Color(0.55, 0.8, 1.0, 0.9), Color(0.75, 0.9, 1.0, 1.0), Color(0.85, 0.95, 1.0, 0.0)]))
	_vortex_draw.set_shader_parameter("boost", 2.4)
	_intensity_mats.append(_vortex_draw)
	_vortex = _particles(_count([0, 36, 80]), 0.75, _vortex_pm, _vortex_draw, 1.0)
	_vortex.one_shot = false
	_vortex.explosiveness = 0.0
	_kick_glare_mat = SP.make_mat("glare", SP.GLARE_SHADER, 3)
	_kick_glare_mat.set_shader_parameter("col", Color(0.4, 0.66, 1.0))
	_kick_glare = SP.make_quad(self, _kick_glare_mat)
	_pulse_mat = SP.make_mat("ring", SP.RING_SHADER, 1)
	_pulse_mat.set_shader_parameter("noise_tex", noise)
	_pulse_mat.set_shader_parameter("col", Color(0.4, 0.68, 1.0))
	_pulse_mat.set_shader_parameter("breakup", 0.5)
	_pulse = SP.make_quad(self, _pulse_mat)
	if n == 0:
		_intensity_mats = [_steam_mat]


func _count(base: Array) -> int:
	var c: int = base[pq()]
	if q() >= 3:
		c = int(c * 1.4)
	return c


func _curve(points: Array) -> CurveTexture:
	var c := Curve.new()
	c.max_value = 2.0
	for p in points:
		c.add_point(p)
	var t := CurveTexture.new()
	t.curve = c
	t.width = 64
	return t


func _particles(amount: int, life: float, pm: Material, draw: Material, size: float) -> GPUParticles3D:
	var p := SP.make_particles(self, amount, life, pm, draw)
	(p.draw_pass_1 as QuadMesh).size = Vector2(size, size)
	return p


func on_rebuild() -> void:
	var box: AABB = view.fx_bounds()
	var c := box.get_center()
	_k = (view.fx_point(Vector3(1, 0, 0)) - view.fx_point(Vector3.ZERO)).length()
	_axis = view.fx_dir(Vector3(1, 0, 0))
	var head: Vector3 = view.fx_anchor("head")
	if head == Vector3.INF:
		head = Vector3(c.x, box.end.y, c.z)
	_head = Vector3(head.x, maxf(head.y, box.end.y - box.size.y * 0.2), head.z)
	_steam.position = _head
	(_steam.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(box.size.x * 0.22, 0.25, box.size.z * 0.18)
	_vent.position = _head + Vector3(0, 0.3, 0)
	_embers.position = Vector3(c.x, box.position.y + box.size.y * 0.7, c.z)
	(_embers.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(box.size.x * 0.32, box.size.y * 0.2, box.size.z * 0.3)
	if _heat_light != null:
		_heat_light.position = Vector3(c.x, box.end.y + 0.5, c.z + box.size.z * 0.2)
	_turb = view.fx_turbine()
	if _turb != Vector3.INF:
		var comp := _turb + _axis * 1.2 * _k
		var mouth := _turb + _axis * 4.0 * _k
		_halo.position = comp
		_halo.scale = Vector3.ONE * 6.5 * _k
		_halo_mat.set_shader_parameter("pull", 1.6 * _k)
		var bz := SP.basis_z(_axis)
		if _ring_a != null:
			_ring_a.transform = Transform3D(bz.scaled(Vector3.ONE * 4.4 * _k), comp)
			_ring_a_mat.set_shader_parameter("r", 0.72)
			_ring_b.transform = Transform3D(bz.scaled(Vector3.ONE * 3.6 * _k), mouth)
			_ring_b_mat.set_shader_parameter("r", 0.7)
		_pulse.transform = Transform3D(bz.scaled(Vector3.ONE * 16.0 * _k), comp)
		_kick_glare.position = comp
		_turbo_light.position = comp + Vector3(0, 0.6 * _k, 0)
		_vortex.position = _turb + _axis * 5.6 * _k
		_vortex_pm.set_shader_parameter("axis", -_axis)
		_vortex_pm.set_shader_parameter("radius", Vector2(2.6 * _k, 0.45 * _k))
		_vortex_pm.set_shader_parameter("height", 4.2 * _k)
		_vortex_pm.set_shader_parameter("size", 0.05)


func warmup(on: bool) -> void:
	_warm = on
	for m in _intensity_mats:
		(m as ShaderMaterial).set_shader_parameter("intensity", 0.0 if on else 1.0)
	var meshes: Array = [_halo, _kick_glare, _pulse]
	if _ring_a != null:
		meshes.append(_ring_a)
		meshes.append(_ring_b)
	for mi in meshes:
		var m: MeshInstance3D = mi
		if on:
			m.visible = true
			(m.material_override as ShaderMaterial).set_shader_parameter("power", 0.0)
		else:
			m.visible = false
	if pq() > 0:
		for p in [_steam, _vent, _embers, _vortex]:
			var gp: GPUParticles3D = p
			if on:
				gp.visible = true
				gp.restart()
			else:
				gp.emitting = false
				gp.visible = false
	if not on:
		_hot = 0.0
		_ember_k = 0.0
		_tb = 0.0


func on_event(event_name: String, _data: Dictionary) -> void:
	match event_name:
		"turbo_start":
			_kick = 1.0
		"exhausted":
			_flare = 1.0
			_vent_t = 0.0
			if pq() > 0:
				_vent.visible = true
				_vent.amount_ratio = 1.0
				_vent.restart()
		"recovered":
			# последний мягкий выдох пара
			if pq() > 0 and _hot > 0.1:
				_vent_t = 0.0
				_vent.visible = true
				_vent.amount_ratio = 0.5
				_vent.restart()


func update(delta: float, st: Dictionary) -> void:
	if _warm:
		return
	_time += delta
	var heat: float = st.heat
	var exhausted: bool = st.exhausted
	# --- пар ---
	var want := smoothstep(0.62, 0.95, heat)
	if exhausted:
		want = maxf(want, 1.0)
	if st.demo:
		want = 0.0
	_hot = lerpf(_hot, want, 1.0 - exp(-delta * (3.0 if want > _hot else 1.2)))
	var parts := pq() > 0
	var steam_on := parts and _hot > 0.03
	if steam_on:
		_steam.visible = true
		_steam.amount_ratio = clampf(0.25 + _hot * 0.75, 0.0, 1.0)
		_steam_mat.set_shader_parameter("density", 0.25 + 0.4 * _hot)
	if _steam.emitting != steam_on:
		_steam.emitting = steam_on
	if not steam_on and _steam.visible and _hot < 0.005:
		_steam.visible = false
	# угольки — только в настоящий перегрев
	var ew := 1.0 if exhausted else smoothstep(0.85, 1.0, heat) * 0.5
	_ember_k = lerpf(_ember_k, ew, 1.0 - exp(-delta * 2.5))
	var ember_on: bool = parts and _ember_k > 0.05 and not st.demo
	if ember_on:
		_embers.visible = true
		_embers.amount_ratio = clampf(_ember_k, 0.1, 1.0)
	if _embers.emitting != ember_on:
		_embers.emitting = ember_on
	if not ember_on and _embers.visible and _ember_k < 0.01:
		_embers.visible = false
	if _vent_t >= 0.0:
		_vent_t += delta
		if _vent_t > 2.2:
			_vent_t = -1.0
			_vent.visible = false
	# --- красный свет перегрева: дышит и мерцает ---
	_flare = maxf(0.0, _flare - delta / 0.8)
	if _heat_light != null:
		var glow := smoothstep(0.7, 1.0, heat) * 0.6 + (0.9 if exhausted else 0.0)
		glow *= 0.8 + 0.2 * sin(_time * 5.0) + 0.08 * sin(_time * 23.0)
		var e := glow * 2.6 + _flare * 6.0
		_heat_light.visible = e > 0.05 and not st.demo
		_heat_light.light_energy = e
	_update_turbo(delta, st)


func _update_turbo(delta: float, st: Dictionary) -> void:
	var tp: Vector3 = view.fx_turbine()
	var has := tp != Vector3.INF
	if has and (tp - _turb).length() > 0.5:
		on_rebuild()
	var on: bool = has and st.turbo and not st.demo
	_tb = lerpf(_tb, 1.0 if on else 0.0, 1.0 - exp(-delta * (6.0 if on else 4.0)))
	_kick = maxf(0.0, _kick - delta / 0.5)
	if not has:
		_kick = 0.0
	var tt: float = st.turbo_t
	# под конец турбо — неровное, «выдыхающееся» свечение
	var wane := 1.0
	if on and tt < 0.15:
		wane = 0.55 + 0.45 * absf(sin(_time * 17.0))
	var lvl := _tb * wane
	var show := lvl > 0.01 or _kick > 0.0
	_halo.visible = show
	if show:
		var e := lvl * (0.85 + 0.15 * sin(_time * 9.0)) + _kick * _kick * 1.6
		_halo_mat.set_shader_parameter("power", e)
		_halo_mat.set_shader_parameter("core_k", 1.0 + _kick * 1.5)
	if _ring_a != null:
		_ring_a.visible = lvl > 0.01
		_ring_b.visible = lvl > 0.01
		if lvl > 0.01:
			_ring_a_mat.set_shader_parameter("power", lvl * 1.15 + _kick * 1.5)
			_ring_b_mat.set_shader_parameter("power", lvl * 0.8 + _kick)
	# вихрь воздуха в фильтр
	if pq() > 0:
		var v_on := on
		if v_on:
			_vortex.visible = true
		if _vortex.emitting != v_on:
			_vortex.emitting = v_on
		if not v_on and _vortex.visible and _tb < 0.02:
			_vortex.visible = false
	# вспышка старта: звезда и кольцевая волна поперёк оси
	_kick_glare.visible = _kick > 0.0
	_pulse.visible = _kick > 0.0 and (q() >= 1 or pq() > 0)
	if _kick > 0.0:
		var g := _kick * _kick
		_kick_glare_mat.set_shader_parameter("power", 1.5 * g)
		var s := 8.0 * _k * (0.7 + 0.5 * (1.0 - _kick))
		_kick_glare.scale = Vector3(s, s, s)
		_kick_glare_mat.set_shader_parameter("rot", _kick * 2.0)
		var f := 1.0 - _kick
		_pulse_mat.set_shader_parameter("r", 0.08 + 0.85 * (1.0 - pow(1.0 - f, 2.5)))
		_pulse_mat.set_shader_parameter("width", 0.02 + 0.04 * f)
		_pulse_mat.set_shader_parameter("trail", 0.15 + 0.2 * f)
		_pulse_mat.set_shader_parameter("power", 1.6 * pow(_kick, 1.4))
	# свет турбины
	var le := lvl * 3.0 + _kick * _kick * 9.0
	_turbo_light.visible = has and le > 0.03
	if _turbo_light.visible:
		_turbo_light.light_energy = le
