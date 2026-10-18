extends Control
## Экран «Новая эпоха!»: новый мотор выкатывается, фанфары.

var epoch_index: int = 0
var level: int = 1
var _engine: Control
var _t: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bgc := ColorRect.new()
	bgc.color = Color(0.03, 0.03, 0.04, 0.0)
	bgc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bgc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bgc)
	var info := D.epoch_info(level)
	var engines: Array = info.engines
	var title := UI.label("НОВАЯ ЭПОХА!", 60, UI.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	title.anchor_right = 1.0
	title.offset_top = 140
	add_child(title)
	var sub := UI.label("Уровень %d · эпоха %d" % [level, epoch_index + 1], 24, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	sub.anchor_right = 1.0
	sub.offset_top = 220
	add_child(sub)

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
	_engine.offset_left = -720
	_engine.offset_right = -720
	add_child(_engine)
	move_child(_engine, 0)

	var v := VBoxContainer.new()
	v.anchor_right = 1.0
	v.offset_left = 50
	v.offset_right = -50
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.anchor_right = 1.0
	shade.anchor_bottom = 1.0
	shade.anchor_top = 0.645
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	v.anchor_top = 0.655
	v.offset_top = 0
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	var names: Array = []
	for e in engines:
		names.append(D.ENGINES[e].name)
	v.add_child(UI.label(" и ".join(names) + (" (гоночный)" if info.racing else ""), 30, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UI.label("Материал: " + D.MATERIALS[info.material].name, 22, Color("c9b48a"), HORIZONTAL_ALIGNMENT_CENTER))
	var m := UI.wrap_label("Новое: " + info.mechanic, 20, UI.MUTED)
	m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(m)
	v.add_child(UI.label("Множитель эпохи: x%s" % G.fmt(info.mult), 22, UI.GOOD, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UI.label("Нажмите, чтобы продолжить", 16, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER))

	Sfx.play("fanfare")
	G.vibrate(150)
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_engine, "offset_left", 0.0, 1.1)
	tw.tween_property(_engine, "offset_right", 0.0, 1.1)


func _process(delta: float) -> void:
	_t += delta
	_engine.demo_rpm = 1200.0 + 2500.0 * (0.5 + 0.5 * sin(_t * 1.5))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and _t > 1.0:
		queue_free()
