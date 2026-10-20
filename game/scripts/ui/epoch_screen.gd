extends Control
## Экран «Новая эпоха!»: новый мотор выкатывается, за ним вращаются лучи света, хлопушки
## конфетти, заголовок влетает со вспышкой и бликом, описание проявляется по строчке.
## Лучи — квадрат с шейдером в 3D-мире витрины позади мотора (мотор их честно заслоняет,
## у пола они гаснут); остальное — 2D-узлы с шейдерами и частицы. В кадре меняются
## только трансформы и параметры.

const UiFx := preload("res://scripts/ui/ui_fx.gd")
const GOLD := Color(1.0, 0.74, 0.28)

var epoch_index: int = 0
var level: int = 1
var _engine: Control
var _t: float = 0.0
var _q: int = 1
var _rays: MeshInstance3D = null
var _rays_mat: ShaderMaterial = null
var _rays_root: Node3D = null
var _title: Label
var _title_mat: ShaderMaterial
var _title_glow: TextureRect
var _fx: Control
var _hit_t: float = -1.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_q = UiFx.quality()
	var scr := size if size.x > 10.0 else get_viewport_rect().size
	var bgc := ColorRect.new()
	bgc.color = Color(0.03, 0.03, 0.04, 0.0)
	bgc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bgc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bgc)
	var info := D.epoch_info(level)
	var engines: Array = info.engines

	_engine = preload("res://scripts/engine_view.gd").new()
	_engine.demo = true
	_engine.interactive = false
	_engine.show_hud = false
	_engine.drives_audio = false
	_engine.engine_type = engines[engines.size() - 1]
	_engine.material_index = info.material
	_engine.demo_rpm = 1500.0
	_engine.anchor_right = 1.0
	_engine.anchor_bottom = 1.0
	_engine.band = Rect2(0.05, 0.22, 0.9, 0.42)
	# выезжает из-за левого края экрана любой ширины
	var w := scr.x
	_engine.offset_left = -w
	_engine.offset_right = -w
	add_child(_engine)

	# низ экрана затемнён плавным градиентом (а не ступенькой)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.22, 1.0])
	grad.colors = PackedColorArray([Color(0.02, 0.02, 0.03, 0.0), Color(0.02, 0.02, 0.03, 0.72), Color(0.02, 0.02, 0.03, 0.9)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 128
	var shade := TextureRect.new()
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.anchor_right = 1.0
	shade.anchor_bottom = 1.0
	shade.anchor_top = 0.6
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	# верх тоже чуть темнее — заголовок читается на любом гараже
	var grad2 := Gradient.new()
	grad2.offsets = PackedFloat32Array([0.0, 1.0])
	grad2.colors = PackedColorArray([Color(0.02, 0.02, 0.03, 0.75), Color(0.02, 0.02, 0.03, 0.0)])
	var gt2 := GradientTexture2D.new()
	gt2.gradient = grad2
	gt2.fill_from = Vector2(0, 0)
	gt2.fill_to = Vector2(0, 1)
	gt2.width = 4
	gt2.height = 64
	var top := TextureRect.new()
	top.texture = gt2
	top.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	top.stretch_mode = TextureRect.STRETCH_SCALE
	top.anchor_right = 1.0
	top.offset_bottom = 330
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)

	_fx = Control.new()
	_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx)

	# заголовок: золотой градиент, вспышка при ударе, блик пробегает раз в пару секунд
	var tc := Vector2(scr.x * 0.5, 186.0)
	_title_glow = UiFx.glow(Vector2(760, 230), Color(GOLD.r, GOLD.g, GOLD.b, 0.0), tc)
	add_child(_title_glow)
	_title = UI.label("НОВАЯ ЭПОХА!", 66, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.add_theme_constant_override("outline_size", 14)
	_title.add_theme_color_override("font_outline_color", Color(0.22, 0.09, 0.0, 1.0))
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_title.add_theme_constant_override("shadow_offset_x", 0)
	_title.add_theme_constant_override("shadow_offset_y", 6)
	_title.add_theme_constant_override("shadow_outline_size", 14)
	_title.size = Vector2(scr.x, 110)
	_title.position = tc - _title.size * 0.5
	_title.pivot_offset = _title.size * 0.5
	_title_mat = UiFx.text_mat(Color(1.0, 0.97, 0.78), Color(1.0, 0.58, 0.08), scr.x, _title.size.y, 66.0)
	_title.material = _title_mat
	add_child(_title)
	var sub := UI.label("Уровень %d · эпоха %d" % [level, epoch_index + 1], 27, Color("fff0d2"), HORIZONTAL_ALIGNMENT_CENTER)
	sub.add_theme_constant_override("outline_size", 9)
	sub.add_theme_color_override("font_outline_color", Color(0.12, 0.05, 0.0, 0.9))
	sub.anchor_right = 1.0
	sub.offset_top = 236
	add_child(sub)

	var v := VBoxContainer.new()
	v.anchor_right = 1.0
	v.offset_left = 50
	v.offset_right = -50
	v.anchor_top = 0.655
	v.offset_top = 0
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	var names: Array = []
	for e in engines:
		names.append(D.ENGINES[e].name)
	var rows: Array = []
	var nm := UI.label(" и ".join(names) + (" (гоночный)" if info.racing else ""), 32, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	nm.add_theme_constant_override("outline_size", 6)
	nm.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	rows.append(nm)
	rows.append(UI.label("Материал: " + D.MATERIALS[info.material].name, 22, Color("c9b48a"), HORIZONTAL_ALIGNMENT_CENTER))
	var m := UI.wrap_label("Новое: " + info.mechanic, 20, UI.MUTED)
	m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.append(m)
	var mult := UI.label("Множитель эпохи: x%s" % G.fmt(info.mult), 24, UI.GOOD, HORIZONTAL_ALIGNMENT_CENTER)
	mult.add_theme_constant_override("outline_size", 6)
	mult.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	rows.append(mult)
	rows.append(UI.label("Нажмите, чтобы продолжить", 16, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	for r in rows:
		v.add_child(r)

	Sfx.play("fanfare")
	G.vibrate(150)
	# фон затемняется до непрозрачного (под ним замерший кадр игры), мотор въезжает без
	# перелёта — иначе на миг открывается правый край
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(bgc, "color:a", 1.0, 0.35)
	tw.tween_property(_engine, "offset_left", 0.0, 1.1)
	tw.tween_property(_engine, "offset_right", 0.0, 1.1)

	# заголовок: влетает из большого, бьёт вспышкой
	_title.scale = Vector2(2.8, 2.8)
	_title.modulate.a = 0.0
	_title.self_modulate = Color(2.5, 2.5, 2.5)
	var tt := create_tween()
	tt.tween_interval(0.08)
	tt.tween_property(_title, "modulate:a", 1.0, 0.1)
	tt.parallel().tween_property(_title, "scale", Vector2(0.94, 0.94), 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tt.tween_callback(_title_hit.bind(tc))
	tt.tween_property(_title, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tt.parallel().tween_property(_title, "self_modulate", Color.WHITE, 0.45)
	# подзаголовок и строки описания проявляются по очереди
	sub.modulate.a = 0.0
	var ts := create_tween()
	ts.tween_interval(0.45)
	ts.tween_property(sub, "modulate:a", 1.0, 0.3)
	var i := 0
	for r in rows:
		r.modulate.a = 0.0
		var tr := create_tween()
		tr.tween_interval(0.75 + 0.12 * i)
		tr.tween_property(r, "modulate:a", 1.0, 0.35)
		i += 1

	# хлопушки конфетти из-за краёв экрана
	var n := UiFx.amount(90)
	var cy := scr.y * 0.6
	var left := UiFx.emitter("confetti", n, Color.WHITE, {"dir": Vector2(0.55, -1.0), "spread": 22.0, "box": Vector2(4, 30), "vmin": 1100.0, "vmax": 1900.0, "damp": 650.0, "gravity": 600.0})
	left.position = Vector2(-10, cy)
	var right := UiFx.emitter("confetti", n, Color.WHITE, {"dir": Vector2(-0.55, -1.0), "spread": 22.0, "box": Vector2(4, 30), "vmin": 1100.0, "vmax": 1900.0, "damp": 650.0, "gravity": 600.0})
	right.position = Vector2(scr.x + 10, cy)
	for p in [left, right]:
		p.emitting = false
		_fx.add_child(p)
	var tc2 := create_tween()
	tc2.tween_interval(0.3)
	tc2.tween_callback(func():
		left.emitting = true
		right.emitting = true)
	# тёплые пылинки поднимаются по всему экрану
	var motes := UiFx.emitter("motes", UiFx.amount(30), Color(1.0, 0.7, 0.35), {"one_shot": false, "box": Vector2(scr.x * 0.5, 40.0), "dir": Vector2(0, -1), "spread": 25.0, "vmin": 40.0, "vmax": 110.0, "gravity": -10.0, "life": 5.0, "scale": 1.3})
	motes.position = Vector2(scr.x * 0.5, scr.y * 0.62)
	motes.preprocess = 2.0
	_fx.add_child(motes)
	# блёстки вокруг заголовка
	var tw2 := UiFx.emitter("twinkle", UiFx.amount(16), GOLD, {"one_shot": false, "box": Vector2(280, 46), "life": 1.1, "scale": 1.15})
	tw2.position = tc
	tw2.emitting = false
	add_child(tw2)
	var tl := create_tween()
	tl.tween_interval(0.35)
	tl.tween_callback(func(): tw2.emitting = true)

	_setup_rays()


## Удар заголовка: вспышка-кольцо, искры, свечение позади, блик по буквам — по кругу.
func _title_hit(tc: Vector2) -> void:
	UiFx.ring(_fx, tc, Color(1.0, 0.72, 0.28), 820.0, 0.75, {"rays": 14.0, "gain": 0.75, "core": 0.45})
	UiFx.burst(_fx, "sparks", tc, UiFx.amount(50), Color(1.0, 0.65, 0.2), {"box": Vector2(240, 30), "vmin": 350.0, "vmax": 900.0, "gravity": 700.0, "scale": 1.1})
	UiFx.burst(_fx, "stars", tc, UiFx.amount(24), Color(1.0, 0.85, 0.4), {"box": Vector2(260, 34), "vmax": 380.0, "life": 1.3})
	G.vibrate(40)
	_hit_t = _t
	var ts := create_tween().set_loops()
	ts.tween_property(_title_mat, "shader_parameter/sweep", 1.3, 0.85).from(-0.3).set_delay(0.1)
	ts.tween_interval(1.4)


## Лучи — квадрат в 3D-мире витрины позади мотора, всегда повёрнут к камере.
func _setup_rays() -> void:
	if _engine == null or not _engine.has_method("fx_root"):
		return
	var root: Node3D = _engine.fx_root()
	if root == null:
		return
	_rays_root = root
	_rays = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1, 1)
	_rays.mesh = qm
	_rays.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rays.extra_cull_margin = 16384.0
	if _rays_mat == null:
		_rays_mat = UiFx.shader_mat("rays3d")
		_rays_mat.set_shader_parameter("col", Color(1.0, 0.66, 0.26))
		_rays_mat.set_shader_parameter("layers", 1.0 if _q >= 1 else 0.0)
	_rays.material_override = _rays_mat
	root.add_child(_rays)
	_place_rays()


func _place_rays() -> void:
	var cam: Camera3D = _engine.fx_camera()
	if cam == null or not cam.is_inside_tree() or _rays == null:
		return
	var root := _rays_root
	var cg := root.to_global(_engine.fx_center())
	var eye := cam.get_camera_transform().origin
	var to := cg - eye
	if to.length() < 0.01:
		return
	var dir := to.normalized()
	var b: AABB = _engine.fx_bounds()
	var back := clampf(b.size.length() * 0.45, 2.5, 7.0)
	var pos := cg + dir * back
	var dist := eye.distance_to(pos)
	var basis := Basis.looking_at(dir, Vector3.UP).scaled(Vector3.ONE * dist * 1.25)
	_rays.global_transform = Transform3D(basis, pos)
	_rays_mat.set_shader_parameter("floor_y", root.to_global(Vector3(0, _engine.fx_floor_y(), 0)).y)


func _process(delta: float) -> void:
	_t += delta
	_engine.demo_rpm = 1200.0 + 2500.0 * (0.5 + 0.5 * sin(_t * 1.5))
	# мир витрины могли пересобрать (сменили графику) — лучи создаём заново
	if _rays == null or not is_instance_valid(_rays) or not is_instance_valid(_rays_root) or _rays_root != _engine.fx_root():
		_rays = null
		_setup_rays()
	if _hit_t >= 0.0:
		var since := _t - _hit_t
		_title_glow.modulate.a = 0.36 + 0.1 * sin(since * 2.6) + 0.45 * exp(-since * 4.0)
	if _rays != null:
		_place_rays()
		var k := smoothstep(0.15, 1.1, _t)
		var breathe := 1.0 + 0.08 * sin(_t * 2.3)
		_rays_mat.set_shader_parameter("intensity", (0.8 if _q >= 1 else 0.65) * k * breathe)
		_rays_mat.set_shader_parameter("spin", _t * 0.32)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and _t > 1.0:
		queue_free()
