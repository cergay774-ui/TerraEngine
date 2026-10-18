extends Control
## Справа вверху: кэш и стрелочка. Нажатие на стрелочку раскрывает список всех ресурсов игрока.

var _cash_label: Label
var _arrow: Button
var _list_panel: PanelContainer
var _list: VBoxContainer
var _rows: Dictionary = {}
var _open: bool = false
var _shown_cash: Big = null
var _chip: PanelContainer


func _ready() -> void:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", UI.box(Color(0.08, 0.09, 0.12, 0.92), 26, Color("ffc21a").darkened(0.35), 3, 8))
	chip.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	chip.offset_left = -300
	chip.offset_right = 0
	chip.offset_top = 0
	chip.offset_bottom = 64
	add_child(chip)
	_chip = chip
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	chip.add_child(h)
	h.add_child(GameIcon.make("cash", 48))
	_cash_label = UI.label("0", 30, D.CURRENCIES.cash.color)
	_cash_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cash_label.add_theme_constant_override("outline_size", 6)
	_cash_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	h.add_child(_cash_label)
	_arrow = Button.new()
	_arrow.focus_mode = Control.FOCUS_NONE
	_arrow.custom_minimum_size = Vector2(48, 48)
	var st := UI.box(Color("ffc21a"), 24, Color("8a5a00"), 2, 0)
	_arrow.add_theme_stylebox_override("normal", st)
	_arrow.add_theme_stylebox_override("hover", st)
	_arrow.add_theme_stylebox_override("pressed", UI.box(Color("e0a800"), 24, Color("8a5a00"), 2, 0))
	_arrow.draw.connect(_draw_arrow)
	_arrow.pressed.connect(toggle)
	h.add_child(_arrow)

	_list_panel = PanelContainer.new()
	_list_panel.add_theme_stylebox_override("panel", UI.box(Color(0.08, 0.09, 0.12, 0.97), 20, Color("ffc21a").darkened(0.35), 3, 14))
	_list_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_list_panel.offset_left = -360
	_list_panel.offset_right = 0
	_list_panel.offset_top = 74
	_list_panel.visible = false
	add_child(_list_panel)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list_panel.add_child(_list)
	_list.add_child(UI.label("Ресурсы", 24, Color("ffc21a")))
	for id in D.CURRENCY_ORDER:
		var row := HBoxContainer.new()
		row.add_child(GameIcon.make(id, 52))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(v)
		var name_l := UI.label(D.CURRENCIES[id].name, 17, UI.MUTED)
		v.add_child(name_l)
		var amount := UI.label("0", 24, D.CURRENCIES[id].color)
		v.add_child(amount)
		_list.add_child(row)
		_rows[id] = {"row": row, "amount": amount}


func _draw_arrow() -> void:
	var c := _arrow.size * 0.5
	var s := 11.0
	var pts: PackedVector2Array
	if _open:
		pts = PackedVector2Array([c + Vector2(-s, s * 0.5), c + Vector2(s, s * 0.5), c + Vector2(0, -s * 0.6)])
	else:
		pts = PackedVector2Array([c + Vector2(-s, -s * 0.5), c + Vector2(s, -s * 0.5), c + Vector2(0, s * 0.6)])
	_arrow.draw_colored_polygon(pts, Color("2a1c00"))


func toggle() -> void:
	set_open(not _open)


func set_open(v: bool) -> void:
	_open = v
	_arrow.queue_redraw()
	refresh()
	if v:
		_list_panel.visible = true
		_list_panel.modulate.a = 0.0
		_list_panel.scale = Vector2(1, 0.8)
		_list_panel.pivot_offset = Vector2(_list_panel.size.x, 0)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(_list_panel, "modulate:a", 1.0, 0.15)
		tw.tween_property(_list_panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_list_panel.visible = false


## Кэш «докручивается» до нового значения, а крупная прибавка подпрыгивает.
func _process(delta: float) -> void:
	var target: Big = G.cur.cash
	if _shown_cash == null or target.lt(_shown_cash):
		_shown_cash = target.copy()
	else:
		var diff := target.sub(_shown_cash)
		if not target.is_zero() and diff.div(target).to_float() > 0.15:
			_bump()
		_shown_cash = _shown_cash.add(diff.mul(1.0 - exp(-delta * 9.0)))
		if target.is_zero() or target.sub(_shown_cash).div(target).to_float() < 0.0005:
			_shown_cash = target.copy()
	_cash_label.text = G.fmt(_shown_cash)


var _bumping: bool = false

func _bump() -> void:
	if _bumping:
		return
	_bumping = true
	_chip.pivot_offset = _chip.size * 0.5
	var tw := _chip.create_tween()
	tw.tween_property(_chip, "scale", Vector2(1.08, 1.08), 0.08)
	tw.tween_property(_chip, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func(): _bumping = false)


func refresh() -> void:
	if not _open:
		return
	for id in _rows:
		var r: Dictionary = _rows[id]
		var unlocked: bool = G.unlocked_cur.get(id, false)
		r.row.modulate = Color(1, 1, 1, 1) if unlocked else Color(1, 1, 1, 0.4)
		if unlocked:
			r.amount.text = G.fmt(G.cur[id])
		elif id == "core":
			r.amount.text = "Ультра-перерождение"
		else:
			r.amount.text = "Перерождение %d" % D.CURRENCIES[id].rebirth
