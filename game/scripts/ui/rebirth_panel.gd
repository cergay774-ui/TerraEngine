extends PanelContainer
## Перерождение: что нужно для следующего, какой станет множитель, какая валюта
## откроется. Там же статистика, постоянные улучшения (сапфиры/квант) и ультра.

var main: Control
var _tab: int = 0
var _tab_btns: Array = []
var _content: VBoxContainer
var _live: Array = []   # [{"btn", "check": Callable}]


func _ready() -> void:
	add_theme_stylebox_override("panel", UI.box(Color(0.09, 0.095, 0.115, 0.98), 22, UI.ACCENT.darkened(0.3), 2, 16))
	var v := VBoxContainer.new()
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := UI.label("Перерождение", 30, UI.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var x := UI.button("×", 28, UI.PANEL_2, 48)
	x.custom_minimum_size.x = 56
	x.pressed.connect(func(): main.close_panel())
	head.add_child(x)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	v.add_child(tabs)
	for i in 4:
		var b := UI.button(["Сброс", "Статистика", "Навсегда", "Ультра"][i], 17, UI.PANEL_2, 48)
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
	_live.clear()
	match _tab:
		0:
			_build_rebirth()
		1:
			_build_stats()
		2:
			_build_perm()
		3:
			_build_ultra()
	tick()


func _line(title: String, value: String, color: Color = UI.TEXT) -> void:
	var h := HBoxContainer.new()
	var l := UI.label(title, 18, UI.MUTED)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(l)
	h.add_child(UI.label(value, 18, color, HORIZONTAL_ALIGNMENT_RIGHT))
	_content.add_child(h)


func _build_rebirth() -> void:
	var req := G.rebirth_req()
	_content.add_child(UI.label("Следующее: перерождение %d" % (G.rebirths + 1), 24, UI.TEXT))
	_content.add_child(UI.wrap_label("Заработано в этом перерождении: %s / %s" % [G.fmt(G.run_earned), G.fmt(req)], 18, UI.TEXT))
	var bar := UI.bar(UI.ACCENT, 18)
	bar.value = clampf(G.run_earned.div(req).to_float(), 0.0, 1.0)
	_content.add_child(bar)
	_line("Множитель сейчас", "x" + Big.power(1.25, G.rebirths).fmt(G.settings.sci))
	_line("Станет", "x" + Big.power(1.25, G.rebirths + 1).fmt(G.settings.sci), UI.GOOD)
	var rw := G.rebirth_rewards(G.rebirths + 1)
	if not rw.is_empty():
		var txt: Array = []
		for id in rw:
			txt.append("+%d %s" % [rw[id], D.CURRENCIES[id].name.to_lower()])
		_line("Награда", ", ".join(txt), Color("ffcc33"))
	var nc := G.next_currency_info()
	if not nc.is_empty():
		_line("Новая валюта", "%s через %d" % [D.CURRENCIES[nc.id].name, nc["in"]], D.CURRENCIES[nc.id].color)
	_content.add_child(UI.hsep())
	_content.add_child(UI.wrap_label("Сбрасывается: кэш, уровни всех улучшений, запчасти, открытые за кэш.\nОстаётся: счётчик перерождений, валюты и их запас, запчасти из кейсов и за редкие валюты, уровень, статистика, достижения.", 16, UI.MUTED))
	_content.add_child(UI.wrap_label("Каждое перерождение требует в 10 раз больше, а даёт только x1.25 — поэтому каждое следующее даётся тяжелее.", 15, Color("8a7f6a")))
	var btn := UI.accent_button("Переродиться", 26, 72)
	btn.pressed.connect(func():
		if G.do_rebirth():
			main.close_panel())
	_content.add_child(btn)
	_live.append({"btn": btn, "check": func(): return G.can_rebirth()})


func _build_stats() -> void:
	var s: Dictionary = G.stats
	_line("Всего заработано", G.fmt(G.total_earned))
	_line("В этом перерождении", G.fmt(G.run_earned))
	_line("Нажатий на двигатель", G.fmt(Big.of(s.presses)))
	_line("Общее время зажатия", UI.time_text(s.hold_time))
	_line("Лучший доход в секунду", G.fmt(Big.of(s.best_ips)))
	_line("Срабатываний турбо", str(s.turbos))
	_line("Критов", str(s.crits))
	_line("Открыто запчастей", str(s.parts))
	_line("Открыто кейсов", str(s.cases))
	_line("Перерождений (всего)", str(s.rebirths_total))
	_line("Ультра-перерождений", str(s.ultras))
	_line("Время в игре", UI.time_text(s.playtime))
	_content.add_child(UI.hsep())
	_content.add_child(UI.label("Достижения: %d (+%d%% к доходу)" % [G.achievements_count(), G.achievements_count()], 22, Color("ffd27f")))
	for cat in G.ACH_CATS:
		var n: int = G.ach.get(cat, 0)
		_line("Следующее: " + G.ach_title(cat, n), "%d получено" % n, UI.MUTED)


func _perm_section(title: String, table: Array, store: Dictionary, currency: String) -> void:
	_content.add_child(UI.label(title, 22, D.CURRENCIES[currency].color))
	if not G.unlocked_cur.get(currency, false):
		_content.add_child(UI.wrap_label("Откроется на перерождении %d." % D.CURRENCIES[currency].rebirth, 16, UI.MUTED))
		return
	for t in table:
		var card := UI.card(UI.PANEL_2, Color(1, 1, 1, 0.05), 10)
		var h := HBoxContainer.new()
		card.add_child(h)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 2)
		h.add_child(v)
		var lvl: int = store.get(t.id, 0)
		v.add_child(UI.label("%s (ур. %d)" % [t.name, lvl], 19, UI.TEXT))
		v.add_child(UI.wrap_label(t.desc, 15, UI.MUTED))
		var maxed: bool = t.has("max") and lvl >= t.max
		var cost := G.perm_cost(table, t.id, store)
		var btn := UI.button("Максимум" if maxed else UI.price_text(currency, cost), 16, Color("2c3a2a"), 56)
		btn.custom_minimum_size.x = 160
		btn.disabled = maxed
		var tid: String = t.id
		btn.pressed.connect(func():
			if G.buy_perm(table, tid, store, currency):
				Sfx.play("buy")
				refresh())
		h.add_child(btn)
		if not maxed:
			_live.append({"btn": btn, "check": func(): return G.can_pay(currency, cost)})
		_content.add_child(card)


func _build_perm() -> void:
	_content.add_child(UI.wrap_label("Эти улучшения не сбрасываются при перерождении.", 16, UI.MUTED))
	_perm_section("Сапфировые улучшения", D.SAPPHIRE_UPGRADES, G.sapph, "sapphire")
	_perm_section("Квантовые модули", D.QUANTUM_UPGRADES, G.quant, "quantum")


func _build_ultra() -> void:
	_content.add_child(UI.label("Ультра-перерождение %d" % (G.ultra + 1), 24, D.CURRENCIES.core.color))
	_content.add_child(UI.wrap_label("Стоит %d перерождений и сбрасывает уже и их, но даёт то, чего обычное перерождение не может:" % G.ultra_req(), 17, UI.TEXT))
	for s in ["Ультра-ядра — высшая валюта для дерева ультра-навыков", "x100 ко всему доходу навсегда",
			"Потолок улучшений +1000 уровней", "Ультра-облик двигателя: прозрачный корпус и плазма",
			"Новые слоты запчастей: реактор и стабилизатор", "Открытые валюты остаются открытыми"]:
		_content.add_child(UI.wrap_label("• " + s, 16, UI.MUTED))
	_content.add_child(UI.wrap_label("Перерождений: %d / %d" % [G.rebirths, G.ultra_req()], 18, UI.TEXT))
	var bar := UI.bar(D.CURRENCIES.core.color, 16)
	bar.value = clampf(float(G.rebirths) / G.ultra_req(), 0.0, 1.0)
	_content.add_child(bar)
	var btn := UI.button("Ультра-перерождение", 24, D.CURRENCIES.core.color.darkened(0.5), 68)
	btn.pressed.connect(func():
		if G.do_ultra():
			main.close_panel())
	_content.add_child(btn)
	_live.append({"btn": btn, "check": func(): return G.can_ultra()})
	_content.add_child(UI.hsep())
	_perm_section("Дерево ультра-навыков", D.ULTRA_SKILLS, G.uskill, "core")


func tick() -> void:
	for l in _live:
		l.btn.disabled = not l.check.call()
