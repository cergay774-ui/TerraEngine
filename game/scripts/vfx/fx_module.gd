class_name FxModule
extends Node3D
## Модуль визуальных эффектов мотора. EngineView создаёт модули в своём 3D-мире (узел
## _root, координаты «корня» сцены), каждый кадр передаёт состояние мотора и сообщает
## о событиях. Модуль ничего не знает об игре — только то, что ему передали.
##
## Состояние (update, словарь st):
##   ratio      — обороты 0..1.2 от максимума          rpm      — обороты
##   throttle   — газ зажат                            turbo    — турбо работает
##   turbo_t    — сколько турбо осталось 0..1          heat     — нагрев 0..1
##   exhausted  — перегрев (стамина кончилась)        black    — чёрный дым (перегрев/дизель)
##   flame_col  — цвет пламени (оранжевый, синий в турбо, особый в ультра)
##   ultra      — ультра-облик                          diesel   — дизель
##   demo       — витрина (загрузка, эпоха)            time     — время, с
##   xray       — рентген                               garage   — режим гаража (мотор зафиксирован)
##   limiter    — обороты бьются об отсечку
##
## События (on_event): "pop" — хлопок в выхлопе; "crit" — критический газ; "turbo_start";
##   "turbo_end"; "limiter" — удар об отсечку (часто, пока газ в пол); "exhausted";
##   "recovered"; "gold" — выпало золото; "level_up"; "upgrade" — куплено улучшение.
##
## Точки (через view): fx_tail() — срез выхлопной трубы, fx_tail_dir() — куда бьёт выхлоп,
##   fx_turbine() — турбина (Vector3.INF, если её нет), fx_center(), fx_bounds() — AABB мотора,
##   fx_floor_y() — пол, fx_camera(), fx_screen_uv(p) — точка на экране (0..1),
##   fx_anchor(slot) — точка детали ("block", "head", "exhaust", "turbine"…).
## Настройки: q() — пресет 0..3, pq() — частицы 0..2.

var view: Control   # EngineView


## Создать узлы. Вызывается, когда модуль уже в дереве и view задан.
func setup() -> void:
	pass


## Каждый кадр.
func update(_delta: float, _st: Dictionary) -> void:
	pass


func on_event(_name: String, _data: Dictionary) -> void:
	pass


## Мотор пересобран: точки крепления поменялись.
func on_rebuild() -> void:
	pass


## Прогрев после сборки: on=true — показать всё на пару кадров, чтобы шейдеры собрались
## сразу, а не посреди игры; on=false — вернуть как было.
func warmup(_on: bool) -> void:
	pass


func q() -> int:
	return view.fx_quality()


func pq() -> int:
	return view.fx_particles()


## Мягкая круглая точка для частиц.
static func soft_dot() -> Texture2D:
	return GarageScene._soft_dot()


## Простые CPU-частицы с билбордом (как были в игре до модулей).
func make_cpu_particles(color: Color, psize: float, life: float, amount: int, glow: bool = false) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(psize, psize)
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = soft_dot()
	m.disable_receive_shadows = true
	if glow:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	quad.material = m
	p.mesh = quad
	p.amount = maxi(1, amount)
	p.lifetime = life
	p.spread = 18.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 2.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.5))
	curve.add_point(Vector2(1, 2.2 if not glow else 0.2))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, color)
	grad.set_color(1, Color(color.r, color.g, color.b, 0.0))
	p.color_ramp = grad
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


func make_omni(color: Color, rng: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.omni_range = rng
	l.light_energy = 0.0
	l.shadow_enabled = false
	add_child(l)
	return l
