extends PanelContainer
## Магазин: постоянные кейсы, ежечасовой магазин (6 предложений, одно «горячее»)
## и ежедневные задания.

var main: Control
var _tab: int = 0
var _tab_btns: Array = []
var _content: VBoxContainer
var _timer_label: Label
var _price_btns: Array = []
var _daily_rows: Array = []


func _ready() -> void:
	add_theme_stylebox_override("panel", UI.box(Color(0.09, 0.095, 0.115, 0.98), 22, Color(1, 1, 1, 0.08), 2, 14))
	var v := VBoxContainer.new()
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := UI.label("Магазин", 30, UI.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var x := UI.button("×", 28, UI.PANEL_2, 48)
	x.custom_minimum_size.x = 56
	x.pressed.connect(func(): main.close_panel())
	head.add_child(x)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	v.add_child(tabs)
	for i in 3:
		var b := UI.button(["Кейсы", "Ежечасовой", "Задания"][i], 20, UI.PANEL_2, 50)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var idx := i
		b.pressed.connect(func():
			_tab = idx
			refresh())
		tabs.add_child(b)
		_tab_btns.append(b)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 10)
	scroll.add_child(_content)


func refresh() -> void:
	for i in _tab_btns.size():
		_tab_btns[i].button_pressed = i == _tab
	UI.clear(_content)
	_price_btns.clear()
	_daily_rows.clear()
	_timer_label = null
	match _tab:
		0:
			_build_cases()
		1:
			_build_hourly()
		2:
			_build_daily()
	tick()


func _build_cases() -> void:
	for c in D.CASES:
		var col: Color = D.CURRENCIES[c.cur].color
		var card := UI.card(UI.PANEL_2, Color(col.r, col.g, col.b, 0.35), 12)
		var h := HBoxContainer.new()
		card.add_child(h)
		h.add_child(GameIcon.make(c.cur, 56))
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 2)
		h.add_child(v)
		v.add_child(UI.label("%s кейс" % c.name, 22, col))
		v.add_child(UI.wrap_label(c.desc, 15, UI.MUTED))
		v.add_child(UI.wrap_label("Шансы: " + G.case_odds_text(c), 14, Color("a9a3c9")))
		var btn: Button
		if G.case_available(c):
			var price := G.case_price(c)
			btn = UI.button("Открыть\n" + UI.price_text(c.cur, price), 16, col.darkened(0.55), 70)
			var cc: Dictionary = c
			btn.pressed.connect(func(): _open(cc))
			_price_btns.append({"btn": btn, "cur": c.cur, "price": price})
		else:
			btn = UI.button("Перерожд.\n%d" % D.CURRENCIES[c.cur].rebirth, 16, UI.PANEL_2, 70)
			btn.disabled = true
		btn.custom_minimum_size.x = 150
		h.add_child(btn)
		_content.add_child(card)
	_content.add_child(UI.wrap_label("Цена кейса растёт с каждым перерождением, чтобы не обесцениваться. Из кейсов запчасти не сбрасываются при перерождении.", 15, UI.MUTED))


func _open(c: Dictionary) -> void:
	var res := G.open_case(c)
	if res.is_empty():
		return
	main.play_case_opening(res)
	refresh()


func _build_hourly() -> void:
	_timer_label = UI.label("", 20, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_content.add_child(_timer_label)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_content.add_child(grid)
	for o in G.hourly_offers():
		var hot: bool = o.hot
		var border := Color("ff5a1f") if hot else Color(1, 1, 1, 0.06)
		var card := UI.card(Color("2a1a14") if hot else UI.PANEL_2, border, 10)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		card.add_child(v)
		if hot:
			v.add_child(UI.label("ГОРЯЧЕЕ", 16, Color("ff7a2a")))
		var tl := UI.wrap_label(o.title, 18, UI.TEXT)
		tl.custom_minimum_size.y = 50
		v.add_child(tl)
		v.add_child(UI.label("-%d%%" % int(round(o.disc * 100.0)), 22, Color("ff9f4a") if hot else UI.GOOD))
		var btn: Button
		if o.bought:
			btn = UI.button("Куплено", 16, UI.PANEL_2, 56)
			btn.disabled = true
		elif o.get("blocked", false):
			btn = UI.button("Недоступно", 16, UI.PANEL_2, 56)
			btn.disabled = true
		else:
			btn = UI.button(UI.price_text(o.cur, o.final), 16, Color("2c3a2a"), 56)
			var oo: Dictionary = o
			btn.pressed.connect(func(): _buy_offer(oo))
			_price_btns.append({"btn": btn, "cur": o.cur, "price": o.final})
		v.add_child(btn)
		grid.add_child(card)
	_content.add_child(UI.wrap_label("6 случайных предложений, обновляются каждый час. Одно в час может быть «горячим» — скидка до 50%.", 15, UI.MUTED))


func _buy_offer(o: Dictionary) -> void:
	var res := G.buy_offer(o)
	if res.is_empty():
		return
	Sfx.play("buy")
	if res.has("slot"):
		main.play_case_opening(res)
	else:
		main.show_toast("Куплено: %s" % o.title, UI.GOOD)
	refresh()


func _build_daily() -> void:
	_content.add_child(UI.label("Ежедневные задания", 22, UI.TEXT))
	var tasks := G.daily_tasks()
	for i in tasks.size():
		var t: Dictionary = tasks[i]
		var card := UI.card(UI.PANEL_2, Color(1, 1, 1, 0.05), 12)
		var v := VBoxContainer.new()
		card.add_child(v)
		var h := HBoxContainer.new()
		v.add_child(h)
		var l := UI.wrap_label(t.text, 19, UI.TEXT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		h.add_child(GameIcon.make(t.reward, 30))
		var bar := UI.bar(UI.ACCENT, 14)
		bar.value = t.progress / maxf(t.goal, 0.001)
		v.add_child(bar)
		var btn: Button
		if t.claimed:
			btn = UI.button("Получено", 18, UI.PANEL_2, 50)
			btn.disabled = true
		else:
			btn = UI.accent_button("Забрать награду", 18, 50)
			btn.disabled = t.progress < t.goal
			var idx := i
			btn.pressed.connect(func():
				var txt := G.claim_daily(idx)
				if txt != "":
					Sfx.play("coin")
					main.show_toast("Задание выполнено: %s" % txt, UI.GOOD)
				refresh())
		v.add_child(btn)
		_daily_rows.append({"bar": bar, "btn": btn, "i": i})
		_content.add_child(card)
	_content.add_child(UI.wrap_label("Задания обновляются каждый день. Награда — в редких валютах (пока они не открыты — в кэше или золоте).", 15, UI.MUTED))


func tick() -> void:
	if _timer_label != null:
		_timer_label.text = "Обновление через %s" % UI.time_text(G.hour_left())
		if G.shop_state.hour != G.hour_index():
			refresh()
			return
	for p in _price_btns:
		p.btn.disabled = not G.can_pay(p.cur, p.price)
	# задания: прогресс и кнопка «забрать» живые
	var tasks := G.daily_tasks()
	for r in _daily_rows:
		if r.i >= tasks.size():
			continue
		var t: Dictionary = tasks[r.i]
		r.bar.value = t.progress / maxf(t.goal, 0.001)
		if not t.claimed:
			r.btn.disabled = t.progress < t.goal
