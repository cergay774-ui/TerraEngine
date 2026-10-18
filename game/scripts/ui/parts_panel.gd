extends PanelContainer
## Запчасти: выезжает снизу и показывает все запчасти сразу. Закрытые — тёмным
## силуэтом с замком и условием открытия. Новая запчасть сразу меняется на моторе.

var main: Control
var only_slot: String = ""     # режим гаража: показываем одну деталь
var _title: Label
var _engine_row: HBoxContainer
var _list: VBoxContainer
var _engines: HFlowContainer
var _buy_tiles: Array = []


func _ready() -> void:
	add_theme_stylebox_override("panel", UI.box(Color(0.09, 0.095, 0.115, 0.98), 22, Color(1, 1, 1, 0.08), 2, 14))
	var v := VBoxContainer.new()
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	_title = UI.label("Запчасти", 30, UI.ACCENT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var x := UI.button("×", 28, UI.PANEL_2, 48)
	x.custom_minimum_size.x = 56
	x.pressed.connect(func(): main.close_panel())
	head.add_child(x)

	var eh := HBoxContainer.new()
	_engine_row = eh
	v.add_child(eh)
	eh.add_child(UI.label("Мотор:", 18, UI.MUTED))
	_engines = HFlowContainer.new()
	_engines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_engines.add_theme_constant_override("h_separation", 6)
	_engines.add_theme_constant_override("v_separation", 6)
	eh.add_child(_engines)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_list)


func refresh() -> void:
	_engine_row.visible = only_slot == ""
	_title.text = "Запчасти" if only_slot == "" else D.slot(only_slot).name
	if only_slot == "":
		_build_engines()
	UI.clear(_list)
	_buy_tiles.clear()
	for s in D.SLOTS:
		if not G.slot_visible(s.id):
			continue
		if only_slot != "" and s.id != only_slot:
			continue
		_list.add_child(_slot_card(s))
	_list.add_child(UI.wrap_label("Марки бесконечны: каждая следующая даёт x3 к бонусу и стоит примерно в 10 раз дороже. Марки VI–X — за золото, XI–XV — за алмазы, дальше — за изумруды. Редкость (только из кейсов) множит бонус марки.", 15, UI.MUTED))
	tick()


func _build_engines() -> void:
	UI.clear(_engines)
	var cur := G.current_engine()
	for id in D.unlocked_engines(G.level):
		var b := UI.button(D.ENGINES[id].name, 15, UI.ACCENT.darkened(0.3) if id == cur else UI.PANEL_2, 40)
		var eid: String = id
		b.pressed.connect(func():
			G.engine_choice = eid
			main._apply_engine()
			main._refresh_numbers()
			refresh())
		_engines.add_child(b)


func _slot_card(s: Dictionary) -> Control:
	var card := UI.card(UI.PANEL_2, Color(1, 1, 1, 0.05), 10)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var nl := UI.label(s.name, 22, UI.TEXT)
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nl)
	var eq := G.equipped(s.id)
	if eq.is_empty():
		top.add_child(UI.label("пусто", 18, UI.MUTED))
	else:
		var r: Dictionary = D.RARITIES[int(eq.rar)]
		top.add_child(UI.label("Mk %s · %s" % [D.roman(int(eq.mk)), r.name], 18, r.color))
	v.add_child(UI.wrap_label("%s: %s" % [s.bonus, _effect(s.id, G.part_bonus(s.id))], 16, Color("b9d7a8")))

	var hs := ScrollContainer.new()
	hs.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hs.custom_minimum_size.y = 118
	v.add_child(hs)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	hs.add_child(row)

	# купленные/выпавшие
	var owned: Array = G.parts[s.id].owned
	var order: Array = []
	for i in owned.size():
		order.append(i)
	order.sort_custom(func(a, b): return G.part_power(s.id, int(owned[a].mk), int(owned[a].rar)) > G.part_power(s.id, int(owned[b].mk), int(owned[b].rar)))
	for i in order:
		var it: Dictionary = owned[i]
		var is_eq: bool = G.parts[s.id].eq == i
		var rc: Color = D.RARITIES[int(it.rar)].color
		var tile := _tile("Mk %s\n%s" % [D.roman(int(it.mk)), D.RARITIES[int(it.rar)].name], rc, is_eq)
		var idx: int = i
		var sid: String = s.id
		tile.pressed.connect(func():
			G.equip(sid, idx)
			Sfx.play("click", 1.3)
			main._apply_engine())
		row.add_child(tile)

	# следующая марка для покупки
	var next_mk := G.best_mark(s.id) + 1
	if G.owns(s.id, next_mk, 0):
		next_mk += 1
	var offer := G.mark_offer(s.id, next_mk)
	var label := "Mk %s\n" % D.roman(next_mk)
	if not offer.ok:
		label += "ЗАКРЫТО\n" + offer.text
		var lt := _tile(label, Color(0.3, 0.3, 0.32), false, true)
		lt.disabled = true
		row.add_child(lt)
	else:
		if offer.free:
			label += "Открыть\nбесплатно"
		else:
			label += UI.price_text(offer.cur, offer.price)
		var bt := _tile(label, UI.ACCENT, false)
		var sid2: String = s.id
		var mk2: int = next_mk
		bt.pressed.connect(func():
			if G.buy_mark(sid2, mk2):
				Sfx.play("buy")
				G.vibrate(20)
				main._apply_engine()
				main.show_toast("%s Mk %s установлена" % [D.slot(sid2).name, D.roman(mk2)], UI.GOOD)
				refresh())
		row.add_child(bt)
		_buy_tiles.append({"btn": bt, "offer": offer})
	# силуэт следующей
	var ghost := _tile("Mk %s\n???" % D.roman(next_mk + 1), Color(0.18, 0.18, 0.2), false, true)
	ghost.disabled = true
	row.add_child(ghost)
	return card


func _tile(text: String, color: Color, selected: bool, locked: bool = false) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.text = text
	b.custom_minimum_size = Vector2(150, 108)
	b.add_theme_font_size_override("font_size", 15)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var bg := Color(0.07, 0.075, 0.09) if locked else color.darkened(0.7)
	var st := UI.box(bg, 12, color if not locked else Color(1, 1, 1, 0.08), 4 if selected else 2, 6)
	b.add_theme_stylebox_override("normal", st)
	b.add_theme_stylebox_override("hover", st)
	b.add_theme_stylebox_override("disabled", st)
	var st2 := st.duplicate()
	st2.border_color = Color.WHITE
	b.add_theme_stylebox_override("pressed", st2)
	b.add_theme_color_override("font_color", Color(0.45, 0.45, 0.48) if locked else Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(0.45, 0.45, 0.48))
	return b


func _effect(id: String, b: float) -> String:
	if b <= 0.0:
		return "нет бонуса"
	match id:
		"block", "reactor":
			return "x%s к доходу" % G.fmt(1.0 + b)
		"pistons":
			return "x%s при зажатии" % G.fmt(1.0 + b)
		"crank":
			return "x%s к доходу, тряска меньше" % G.fmt(1.0 + 0.5 * b)
		"head":
			return "x%s к доходу, обороты +%d%%" % [G.fmt(1.0 + 0.5 * b), int(minf(0.6, 0.05 * b) * 100.0)]
		"ignition":
			return "+%.1f%% к шансу турбо" % minf(25.0, b)
		"fuel":
			return "x%s стамины" % G.fmt(1.0 + b)
		"cooling":
			return "x%s к восстановлению" % G.fmt(1.0 + b)
		"exhaust":
			return "x%s пассивного дохода" % G.fmt(1.0 + b)
		"turbine":
			return "турбо x%s" % G.fmt(2.0 + b)
		"flywheel":
			return "+%.1f%% шанс крита, x%s сила" % [minf(25.0, b * 0.5), G.fmt(1.0 + b)]
		"stabilizer":
			return "x%s стамины, меньше тряски" % G.fmt(1.0 + 0.5 * b)
	return ""


func tick() -> void:
	for t in _buy_tiles:
		var o: Dictionary = t.offer
		t.btn.disabled = not o.free and not G.can_pay(o.cur, o.price)
