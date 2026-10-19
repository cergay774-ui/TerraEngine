extends FxModule
## Выхлоп: дым из трубы, язык пламени, хлопки с вспышкой и искрами, свет от пламени.

var _smoke: CPUParticles3D
var _flames: CPUParticles3D
var _sparks: CPUParticles3D
var _tail_flame: MeshInstance3D
var _tail_light: OmniLight3D
var _pop_glow: float = 0.0
var _warm: bool = false


func setup() -> void:
	var n := pq()
	_tail_light = make_omni(Color(1.0, 0.5, 0.15), 10.0)
	_smoke = make_cpu_particles(Color(0.8, 0.8, 0.85, 0.3), 0.7, 2.2, [16, 40, 70][n])
	_smoke.direction = Vector3(0, 1, -0.3)
	_smoke.gravity = Vector3(0, 0.5, 0)
	_flames = make_cpu_particles(Color(1.0, 0.6, 0.15, 1.0), 0.55, 0.28, [10, 24, 40][n], true)
	_flames.direction = Vector3(0, 0.3, -1)
	_flames.spread = 12.0
	_flames.initial_velocity_min = 5.0
	_flames.initial_velocity_max = 9.0
	_flames.gravity = Vector3.ZERO
	_flames.emitting = false
	_flames.one_shot = true
	_flames.explosiveness = 0.9
	_sparks = make_cpu_particles(Color(1.0, 0.8, 0.35, 1.0), 0.14, 0.8, [1, 30, 60][n], true)
	_sparks.direction = Vector3(0, 0.6, -1)
	_sparks.spread = 70.0
	_sparks.initial_velocity_min = 5.0
	_sparks.initial_velocity_max = 11.0
	_sparks.gravity = Vector3(0, -22, 0)
	_sparks.emitting = false
	_sparks.one_shot = true
	_sparks.explosiveness = 1.0
	_sparks.scale_amount_curve = null

	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.albedo_color = Color(1.0, 0.55, 0.15, 0.0)
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_tail_flame = MeshInstance3D.new()
	_tail_flame.mesh = MeshKit.cone(0.35, 0.0, 2.2, 12)
	_tail_flame.material_override = fm
	_tail_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_tail_flame)


func on_event(event_name: String, _data: Dictionary) -> void:
	if event_name != "pop":
		return
	_pop_glow = 1.0
	var tail: Vector3 = view.fx_tail()
	_flames.position = tail
	_flames.restart()
	_flames.emitting = true
	if pq() > 0:
		_sparks.position = tail
		_sparks.restart()
		_sparks.emitting = true


func warmup(on: bool) -> void:
	_warm = on
	if on:
		_flames.restart()
		_flames.emitting = true
		_sparks.restart()
		_sparks.emitting = pq() > 0


func update(delta: float, st: Dictionary) -> void:
	var tail: Vector3 = view.fx_tail()
	var ratio: float = st.ratio
	var black: bool = st.black
	_smoke.position = tail
	_smoke.emitting = pq() > 0 or ratio > 0.2
	_smoke.initial_velocity_min = 0.6 + 2.0 * ratio
	_smoke.initial_velocity_max = 1.4 + 3.5 * ratio
	_smoke.color_ramp.set_color(0, Color(0.06, 0.06, 0.07, 0.6) if black else Color(0.8, 0.8, 0.85, 0.22))
	var flame_col: Color = st.flame_col
	_flames.color_ramp.set_color(0, flame_col)
	_pop_glow = maxf(0.0, _pop_glow - delta * 5.0)
	var flame := maxf(_pop_glow, 0.55 if st.turbo and st.throttle else 0.0)
	var tfm: StandardMaterial3D = _tail_flame.material_override
	tfm.albedo_color = Color(flame_col.r, flame_col.g, flame_col.b, flame * (0.7 + 0.3 * randf()))
	_tail_flame.visible = flame > 0.02 or _warm
	_tail_flame.position = tail + Vector3(0, 0.1, -1.0)
	_tail_flame.rotation_degrees = Vector3(-90, 0, 0)
	_tail_flame.scale = Vector3(1, 0.6 + flame * (0.8 + 0.4 * randf()), 1)
	_tail_light.position = tail + Vector3(0, 0.5, -0.8)
	_tail_light.light_color = flame_col
	_tail_light.light_energy = flame * 6.0
	_tail_light.visible = (flame > 0.02 or _warm) and q() >= 1
