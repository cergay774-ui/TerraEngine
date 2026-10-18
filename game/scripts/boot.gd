extends Control
## Экран загрузки: гараж, логотип, поршень в разрезе (скорость растёт с прогрессом),
## тахометр вместо прогресс-бара, подсказки каждые 3 секунды. На 100% — рёв, вспышка
## и экран уезжает вверх, как гаражная дверь.

const MAIN_SCENE := "res://scenes/main.tscn"
const MIN_TIME := 3.4

var _loading: Control
var _engine: Control
var _tacho: Control
var _tip: Label
var _percent: Label
var _slats: Control
var _t: float = 0.0
var _tip_t: float = 0.0
var _tip_i: int = 0
var _done: bool = false
var _main_packed: PackedScene = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UI.make_theme()
	ResourceLoader.load_threaded_request(MAIN_SCENE)

	_loading = Control.new()
	_loading.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_loading)

	var bg := preload("res://scripts/ui/garage_bg.gd").new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.lamp_y = 40.0
	_loading.add_child(bg)

	var title := UI.label("МОТОР ГАРАЖ", 64, UI.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.position.y = 150
	_loading.add_child(title)
	var sub := UI.label("кликер-тайкун про сборку моторов", 22, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	sub.set_anchors_preset(Control.PRESET_TOP_WIDE)
	sub.position.y = 232
	_loading.add_child(sub)

	_engine = preload("res://scripts/engine_view.gd").new()
	_engine.demo = true
	_engine.interactive = false
	_engine.show_hud = false
	_engine.engine_type = "single"
	_engine.demo_rpm = 300.0
	_engine.rpm = 0.0
	_engine.anchor_left = 0.0
	_engine.anchor_right = 1.0
	_engine.offset_top = 270
	_engine.offset_bottom = 780
	_loading.add_child(_engine)

	_tacho = preload("res://scripts/ui/tacho.gd").new()
	_tacho.anchor_left = 0.5
	_tacho.anchor_right = 0.5
	_tacho.offset_left = -170
	_tacho.offset_right = 170
	_tacho.offset_top = 800
	_tacho.offset_bottom = 1040
	_loading.add_child(_tacho)

	_percent = UI.label("0%", 26, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_percent.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_percent.position.y = 1040
	_loading.add_child(_percent)

	_tip = UI.wrap_label("", 22, Color("b9b5aa"))
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.anchor_left = 0.0
	_tip.anchor_right = 1.0
	_tip.offset_left = 50
	_tip.offset_right = -50
	_tip.offset_top = 1110
	_tip.offset_bottom = 1220
	_loading.add_child(_tip)
	_tip_i = randi() % D.TIPS.size()
	_tip.text = D.TIPS[_tip_i]

	_slats = Control.new()
	_slats.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_slats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slats.modulate.a = 0.0
	_slats.draw.connect(_draw_slats)
	_loading.add_child(_slats)

	Sfx.engine_on = false
	Sfx.play("starter")
	get_tree().create_timer(1.15).timeout.connect(func(): Sfx.engine_on = true)


func _draw_slats() -> void:
	var h := _slats.size.y
	var w := _slats.size.x
	_slats.draw_rect(Rect2(Vector2.ZERO, _slats.size), Color("2a2d33"))
	var n := 14
	for i in n:
		var y := i * h / n
		_slats.draw_rect(Rect2(0, y, w, h / n - 6.0), Color("3a3e46"))
		_slats.draw_line(Vector2(0, y + h / n - 6.0), Vector2(w, y + h / n - 6.0), Color("1b1d21"), 6.0)
	_slats.draw_rect(Rect2(w * 0.42, h - 70, w * 0.16, 22), Color("1b1d21"))


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	var fake := clampf(_t / MIN_TIME, 0.0, 1.0)
	var arr := []
	var status := ResourceLoader.load_threaded_get_status(MAIN_SCENE, arr)
	var real := 1.0 if status == ResourceLoader.THREAD_LOAD_LOADED else (float(arr[0]) if arr.size() > 0 else 0.0)
	var p := minf(fake, real)
	if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		p = fake
	_tacho.value = p
	_percent.text = "%d%%" % int(p * 100.0)
	_engine.demo_rpm = 300.0 + p * p * 5200.0
	_tip_t += delta
	if _tip_t >= 3.0:
		_tip_t = 0.0
		_tip_i = (_tip_i + 1) % D.TIPS.size()
		var tw := create_tween()
		tw.tween_property(_tip, "modulate:a", 0.0, 0.2)
		tw.tween_callback(func(): _tip.text = D.TIPS[_tip_i])
		tw.tween_property(_tip, "modulate:a", 1.0, 0.2)
	if p >= 1.0:
		_finish()


func _finish() -> void:
	_done = true
	if ResourceLoader.load_threaded_get_status(MAIN_SCENE) == ResourceLoader.THREAD_LOAD_LOADED:
		_main_packed = ResourceLoader.load_threaded_get(MAIN_SCENE)
	else:
		_main_packed = load(MAIN_SCENE)
	# короткий рёв мотора и вспышка
	_engine.demo_rpm = 7200.0
	Sfx.pop()
	var tw := create_tween()
	tw.tween_interval(0.45)
	tw.tween_callback(func():
		_engine.flash_white = 1.0
		Sfx.pop()
		G.vibrate(80))
	tw.tween_interval(0.25)
	tw.tween_callback(_show_main)
	tw.tween_property(_slats, "modulate:a", 1.0, 0.18)
	tw.tween_callback(func(): Sfx.play("garage_door"))
	tw.tween_property(_loading, "position:y", -size.y - 40.0, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func(): _loading.queue_free())


func _show_main() -> void:
	_engine.drives_audio = false
	var main := _main_packed.instantiate()
	add_child(main)
	move_child(main, 0)
