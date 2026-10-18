extends PanelContainer
## Улучшения: выезжает слева до середины экрана, мотор виден справа.

var main: Control
var _mode: int = 1   # 1, 10, 100, -1 = максимум
var _rows: Dictionary = {}
var _mode_btns: Array = []


func _ready() -> void:
	add_theme_stylebox_override("panel", UI.box(Color(0.09, 0.095, 0.115, 0.97), 0, Color(1, 1, 1, 0.08), 2, 12))
	var v := VBoxContainer.new()
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := UI.label("Улучшения", 30, UI.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var x := UI.button("✕", 24, UI.PANEL_2, 48)
	x.custom_minimum_size.x = 52
	x.pressed.connect(func(): main.close_panel())
	head.add_child(x)

	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 6)
	v.add_child(modes)
	for m in [[1, "x1"], [10, "x10"], [100, "x100"], [-1, "МАКС"]]:
		var b := UI.button(m[1], 18, UI.PANEL_2, 44)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.button_pressed = m[0] == _mode
		var val: int = m[0]
		b.pressed.connect(func():
			_mode = val
			for mb in _mode_btns:
				mb.button_pressed = mb == b
			refresh())
		modes.add_child(b)
		_mode_btns.append(b)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)

	for i in D.UPGRADES.size():
		var u: Dictionary = D.UPGRADES[i]
		var card := UI.card(UI.PANEL_2, Color(1, 1, 1, 0.05), 10)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 4)
		card.add_child(cv)
		var top := HBoxContainer.new()
		cv.add_child(top)
		var name_l := UI.label("%d. %s" % [i + 1, u.name], 20, UI.TEXT)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.clip_text = true
		top.add_child(name_l)
		var lvl_l := UI.label("", 16, UI.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
		top.add_child(lvl_l)
		var desc := UI.wrap_label(u.desc, 15, UI.MUTED)
		cv.add_child(desc)
		var eff := UI.wrap_label("", 16, Color("b9d7a8"))
		cv.add_child(eff)
		var btn := UI.button("", 18, Color("2c3a2a"), 52)
		var id: String = u.id
		btn.pressed.connect(func(): _buy(id))
		cv.add_child(btn)
		list.add_child(card)
		_rows[u.id] = {"card": card, "lvl": lvl_l, "eff": eff, "btn": btn, "desc": desc}


func _count(id: String) -> int:
	if _mode == -1:
		return maxi(1, G.upgrade_affordable(id))
	return _mode


func _buy(id: String) -> void:
	var n := G.buy_upgrade(id, _count(id))
	if n > 0:
		Sfx.play("buy", 1.0 + randf() * 0.1)
		G.vibrate(10)
	refresh()


func refresh() -> void:
	for u in D.UPGRADES:
		var row: Dictionary = _rows[u.id]
		var l: int = G.upg[u.id]
		var cap := G.upgrade_cap(u.id)
		row.lvl.text = "ур. %d%s" % [l, ("/%d" % cap) if cap >= 0 else ""]
		var unlocked := G.upgrade_unlocked(u.id)
		row.card.modulate = Color(1, 1, 1, 1) if unlocked else Color(1, 1, 1, 0.55)
		if not unlocked:
			row.eff.text = G.upgrade_unlock_text(u.id)
			row.btn.text = "Закрыто"
			row.btn.disabled = true
			continue
		if cap >= 0 and l >= cap:
			row.eff.text = G.upgrade_effect_text(u.id, l) + " (предел)"
			row.btn.text = "Максимум"
			row.btn.disabled = true
			continue
		var n := _count(u.id)
		if cap >= 0:
			n = mini(n, cap - l)
		var cost := G.upgrade_cost(u.id, n)
		row.eff.text = "%s → %s" % [G.upgrade_effect_text(u.id, l), G.upgrade_effect_text(u.id, l + n)]
		row.btn.text = "+%d  %s" % [n, UI.price_text(u.cur, cost)]
		row.btn.disabled = not G.can_pay(u.cur, cost)


func tick() -> void:
	refresh()
