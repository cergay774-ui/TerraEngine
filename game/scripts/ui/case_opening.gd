extends Control
## Открытие кейса: ящик трясётся, крышка слетает, запчасть вылетает со вспышкой
## цвета её редкости.

var result: Dictionary = {}
var _t: float = 0.0
var _opened: bool = false
var _card: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	Sfx.play("case_shake")
	G.vibrate(30)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and _t > 1.4:
		queue_free()


func _process(delta: float) -> void:
	_t += delta
	if _t >= 1.0 and not _opened:
		_opened = true
		Sfx.play("case_open", 0.9 + 0.1 * int(result.rar))
		G.vibrate(60 + 30 * int(result.rar))
		_show_card()
	queue_redraw()


func _rar_color() -> Color:
	return D.RARITIES[int(result.rar)].color


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.78))
	var c := size * Vector2(0.5, 0.42)
	var col := _rar_color()
	if _opened:
		var k := clampf((_t - 1.0) / 0.5, 0.0, 1.0)
		for i in 8:
			var a := TAU * i / 8.0 + _t * 0.6
			var poly := PackedVector2Array([c, c + Vector2(cos(a - 0.12), sin(a - 0.12)) * 900.0, c + Vector2(cos(a + 0.12), sin(a + 0.12)) * 900.0])
			draw_colored_polygon(poly, Color(col.r, col.g, col.b, 0.08 * k))
		draw_circle(c, 40.0 + 300.0 * k, Color(col.r, col.g, col.b, 0.35 * (1.0 - k)))
		draw_circle(c, 120.0, Color(col.r, col.g, col.b, 0.18))
	# ящик
	var shake := 0.0
	if not _opened:
		shake = sin(_t * 60.0) * 0.08 * _t
	draw_set_transform(c + Vector2(0, 120), shake, Vector2.ONE)
	var bw := 260.0
	var bh := 170.0
	var wood := Color("6b4a2b")
	draw_rect(Rect2(-bw * 0.5, -bh, bw, bh), wood)
	for k in 4:
		draw_line(Vector2(-bw * 0.5, -bh + k * bh / 4.0), Vector2(bw * 0.5, -bh + k * bh / 4.0), wood.darkened(0.35), 4.0)
	draw_rect(Rect2(-bw * 0.5, -bh, bw, bh), wood.darkened(0.5), false, 6.0)
	draw_rect(Rect2(-18, -bh, 36, bh), col.darkened(0.2))
	# крышка
	var lid_off := Vector2.ZERO
	var lid_rot := 0.0
	if _opened:
		var k2 := clampf((_t - 1.0) / 0.6, 0.0, 1.0)
		lid_off = Vector2(160.0 * k2, -520.0 * k2 + 600.0 * k2 * k2)
		lid_rot = 1.4 * k2
	draw_set_transform(c + Vector2(0, 120 - bh) + lid_off, shake + lid_rot, Vector2.ONE)
	draw_rect(Rect2(-bw * 0.55, -36, bw * 1.1, 36), wood.lightened(0.1))
	draw_rect(Rect2(-bw * 0.55, -36, bw * 1.1, 36), wood.darkened(0.5), false, 5.0)
	draw_rect(Rect2(-18, -36, 36, 36), col.darkened(0.2))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _show_card() -> void:
	_card = UI.card(UI.PANEL, _rar_color(), 18)
	_card.anchor_left = 0.5
	_card.anchor_right = 0.5
	_card.offset_left = -270
	_card.offset_right = 270
	_card.offset_top = size.y * 0.42 + 150.0
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(v)
	var r: Dictionary = D.RARITIES[int(result.rar)]
	v.add_child(UI.label(r.name.to_upper(), 22, r.color, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UI.label("%s Mk %s" % [D.slot(result.slot).name, D.roman(int(result.mk))], 32, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UI.label(D.slot(result.slot).bonus, 18, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	if result.has("cash") and not result.cash.is_zero():
		v.add_child(UI.label("+%s кэша" % G.fmt(result.cash), 22, UI.GOOD, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UI.label("Нажмите, чтобы продолжить", 16, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	add_child(_card)
	_card.pivot_offset = Vector2(270, 80)
	_card.scale = Vector2(0.3, 0.3)
	_card.modulate.a = 0.0
	var tw := _card.create_tween().set_parallel(true)
	tw.tween_property(_card, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_card, "modulate:a", 1.0, 0.2)
