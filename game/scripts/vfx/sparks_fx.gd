extends FxModule
## Искры: сноп из мотора на критическом газе.

var _sparks: CPUParticles3D


func setup() -> void:
	_sparks = make_cpu_particles(Color(1.0, 0.8, 0.35, 1.0), 0.14, 0.8, [1, 30, 60][pq()], true)
	_sparks.direction = Vector3(0, 1, 0)
	_sparks.spread = 70.0
	_sparks.initial_velocity_min = 5.0
	_sparks.initial_velocity_max = 11.0
	_sparks.gravity = Vector3(0, -22, 0)
	_sparks.emitting = false
	_sparks.one_shot = true
	_sparks.explosiveness = 1.0
	_sparks.scale_amount_curve = null


func on_event(event_name: String, _data: Dictionary) -> void:
	if event_name != "crit" or pq() == 0:
		return
	_sparks.position = view.fx_center() + Vector3(0, 2.0, 0)
	_sparks.restart()
	_sparks.emitting = true
