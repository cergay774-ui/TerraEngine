extends Control
## Режим гаража: мотор зафиксирован, от каждой детали идёт линия к карточке.
## Нажатие на карточку открывает выбор: поставить другой вариант или купить новую марку.

var main: Control
var engine_view: Control
var _cards: Dictionary = {}       # слот -> Button
var _sides: Dictionary = {}       # слот -> -1 (слева) / 1 (справа)
var _lines: Control
var _time: float = 0.0
var _layout_key: String = ""
var _appear: float = 0.0      # 0..1 — линии «прорастают» от карточек к деталям

const CARD_W := 196.0
const CARD_H := 86.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines = Control.new()
	_lines.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines.draw.connect(_draw_lines)
	add_child(_lines)
	G.changed.connect(_refresh_cards)
	G.part_gained.connect(func(_a, _b, _c): _refresh_cards())


func _build_header() -> void:
	var box := VBoxContainer.new()
	box.name = "Header"
	box.position = Vector2(0, main.ENGINE_TOP + main.top_margin - 8.0)
	box.size = Vector2(size.x, 60)
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	var t := UI.label("ГАРАЖ", 30, Color("ffc21a"), HORIZONTAL_ALIGNMENT_CENTER)
	t.add_theme_constant_override("outline_size", 8)
	t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	box.add_child(t)
	var flow := HFlowContainer.new()
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.add_theme_constant_override("h_separation", 6)
	box.add_child(flow)
	var cur := G.current_engine()
	var avail := D.unlocked_engines(G.level)
	if avail.size() > 1:
		for id in avail:
			var b := UI.button(D.ENGINES[id].name, 14, UI.ACCENT.darkened(0.35) if id == cur else UI.PANEL_2, 36)
			var eid: String = id
			b.pressed.connect(func():
				G.engine_choice = eid
				main._apply_engine()
				main._refresh_numbers())
			flow.add_child(b)


func rebuild() -> void:
	var old := get_node_or_null("Header")
	if old:
		old.free()
	_build_header()
	for c in _cards.values():
		c.queue_free()
	_cards.clear()
	_sides.clear()
	var slots: Array = []
	for s in D.SLOTS:
		if G.slot_visible(s.id) and engine_view.part_screen_pos(s.id).x >= 0.0:
			slots.append(s.id)
	# слева — детали, что левее середины мотора, справа — остальные; внутри колонки — сверху вниз
	var pts := {}
	var cx := 0.0
	for sid in slots:
		pts[sid] = engine_view.part_screen_pos(sid)
		cx += pts[sid].x
	cx /= maxf(1.0, slots.size())
	slots.sort_custom(func(a, b): return pts[a].x < pts[b].x)
	var half := int(ceil(slots.size() / 2.0))
	var left := slots.slice(0, half)
	var right := slots.slice(half)
	left.sort_custom(func(a, b): return pts[a].y < pts[b].y)
	right.sort_custom(func(a, b): return pts[a].y < pts[b].y)
	var top: float = main.ENGINE_TOP + main.top_margin + 70.0
	var bottom: float = main.ENGINE_BOTTOM + 90.0
	for col in [[left, -1], [right, 1]]:
		var list: Array = col[0]
		var step := (bottom - top) / maxf(1.0, list.size())
		for i in list.size():
			var sid: String = list[i]
			var card := _make_card(sid)
			var x := 10.0 if col[1] < 0 else size.x - CARD_W - 10.0
			var target := Vector2(x, top + step * i + (step - CARD_H) * 0.5)
			card.position = target + Vector2(-70.0 if col[1] < 0 else 70.0, 0)
			card.modulate.a = 0.0
			add_child(card)
			var tw := card.create_tween().set_parallel(true)
			tw.tween_property(card, "position", target, 0.38).set_delay(0.05 * i).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(card, "modulate:a", 1.0, 0.25).set_delay(0.05 * i)
			_cards[sid] = card
			_sides[sid] = col[1]
	_appear = 0.0
	_refresh_cards()


func _make_card(sid: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.size = Vector2(CARD_W, CARD_H)
	b.custom_minimum_size = b.size
	b.clip_text = true
	b.add_theme_font_size_override("font_size", 15)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(func():
		Sfx.play("click")
		main.open_slot(sid))
	var icon := GameIcon.make("part_" + sid, 54)
	icon.position = Vector2(8, (CARD_H - 54) * 0.5)
	b.add_child(icon)
	var name_l := UI.label(D.slot(sid).name, 15, Color.WHITE)
	name_l.position = Vector2(68, 14)
	name_l.size = Vector2(CARD_W - 74, 22)
	name_l.clip_text = true
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(name_l)
	var info := UI.label("", 14, UI.MUTED)
	info.name = "Info"
	info.position = Vector2(68, 44)
	info.size = Vector2(CARD_W - 74, 22)
	info.clip_text = true
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(info)
	return b


func _refresh_cards() -> void:
	for sid in _cards:
		var b: Button = _cards[sid]
		var eq := G.equipped(sid)
		var col := Color(0.35, 0.35, 0.4)
		var line2 := "пусто"
		if not eq.is_empty():
			var r: Dictionary = D.RARITIES[int(eq.rar)]
			col = r.color
			line2 = "Mk %s · %s" % [D.roman(int(eq.mk)), r.name]
		var next := G.mark_offer(sid, G.best_mark(sid) + 1)
		var can_buy: bool = next.ok and (next.free or G.can_pay(next.cur, next.price))
		var info: Label = b.get_node("Info")
		info.text = line2
		info.add_theme_color_override("font_color", col if not eq.is_empty() else UI.MUTED)
		var st := UI.box(Color(0.07, 0.075, 0.09, 0.9), 14, col, 3, 6)
		b.add_theme_stylebox_override("normal", st)
		b.add_theme_stylebox_override("hover", st)
		var st2 := st.duplicate()
		st2.border_color = Color.WHITE
		b.add_theme_stylebox_override("pressed", st2)
		b.add_theme_color_override("font_color", Color.WHITE)
		b.set_meta("color", col)
		b.set_meta("upgrade", can_buy)


func _process(delta: float) -> void:
	_time += delta
	_appear = minf(1.0, _appear + delta * 1.6)
	var key := G.current_engine() + "|" + str(G.level) + "|" + str(G.equipped("turbine").is_empty())
	if key != _layout_key and engine_view.part_screen_pos("block").x >= 0.0:
		_layout_key = key
		rebuild()
	_lines.queue_redraw()


func _draw_lines() -> void:
	for sid in _cards:
		var b: Button = _cards[sid]
		var p: Vector2 = engine_view.part_screen_pos(sid)
		if p.x < 0.0:
			continue
		var side: int = _sides[sid]
		var col: Color = b.get_meta("color", Color.WHITE)
		col = col.lerp(Color("ffc21a"), 0.35)
		var start := b.position + Vector2(CARD_W if side < 0 else 0.0, CARD_H * 0.5)
		var elbow := Vector2(start.x + side * -1.0 * 26.0, start.y)
		# линия растёт от карточки к детали
		var k := clampf(_appear * 1.4 - 0.2, 0.0, 1.0)
		k = k * k * (3.0 - 2.0 * k)
		var l1 := start.distance_to(elbow)
		var l2 := elbow.distance_to(p)
		var want := (l1 + l2) * k
		var end_p := p
		var pts: PackedVector2Array
		if want <= l1:
			end_p = start.lerp(elbow, want / maxf(l1, 0.001))
			pts = PackedVector2Array([start, end_p])
		else:
			end_p = elbow.lerp(p, (want - l1) / maxf(l2, 0.001))
			pts = PackedVector2Array([start, elbow, end_p])
		if k < 0.999:
			_lines.draw_polyline(pts, Color(0, 0, 0, 0.6), 5.0, true)
			_lines.draw_polyline(pts, col, 2.5, true)
			_lines.draw_circle(end_p, 4.0, Color.WHITE)
			continue
		_lines.draw_polyline(pts, Color(0, 0, 0, 0.6), 5.0, true)
		_lines.draw_polyline(pts, col, 2.5, true)
		var pulse := 0.5 + 0.5 * sin(_time * 4.0 + p.x * 0.05)
		_lines.draw_circle(p, 9.0 + pulse * 4.0, Color(col.r, col.g, col.b, 0.25))
		_lines.draw_circle(p, 6.0, col)
		_lines.draw_circle(p, 2.5, Color.WHITE)
		if b.get_meta("upgrade", false):
			_lines.draw_circle(b.position + Vector2(CARD_W - 12, 12), 7.0 + pulse * 2.0, Color("8fe36b"))
