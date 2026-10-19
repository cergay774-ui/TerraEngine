extends FxModule
## Нагрев и турбо: пар над перегретым мотором, синий свет от работающей турбины.

var _steam: CPUParticles3D
var _turbo_light: OmniLight3D
var _warm: bool = false


func setup() -> void:
	_turbo_light = make_omni(Color(0.3, 0.55, 1.0), 16.0)
	_steam = make_cpu_particles(Color(0.95, 0.95, 1.0, 0.25), 1.0, 1.6, [1, 24, 40][pq()])
	_steam.direction = Vector3(0, 1, 0)
	_steam.initial_velocity_min = 1.0
	_steam.initial_velocity_max = 2.5
	_steam.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_steam.emission_box_extents = Vector3(3, 0.2, 1)
	_steam.emitting = false


func on_rebuild() -> void:
	var box: AABB = view.fx_bounds()
	var c := box.get_center()
	_steam.position = Vector3(c.x, box.end.y - 1.0, c.z)


func warmup(on: bool) -> void:
	_warm = on


func update(_delta: float, st: Dictionary) -> void:
	_steam.emitting = st.heat > 0.75 and pq() > 0
	var tp: Vector3 = view.fx_turbine()
	var has_turbo := tp != Vector3.INF
	_turbo_light.light_energy = 3.0 if st.turbo else 0.0
	_turbo_light.visible = has_turbo and (st.turbo or _warm)
	if _turbo_light.visible:
		_turbo_light.position = tp
