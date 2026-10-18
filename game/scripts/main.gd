extends Control
## Главный экран: верхняя панель с валютами, мотор по центру, стамина, 5 кнопок внизу.

const W := 720.0
var H: float = 1280.0          # высота экрана в единицах интерфейса (на вытянутых телефонах больше)
const ENGINE_TOP := 205.0
var ENGINE_BOTTOM: float = 930.0  # низ полосы мотора — считается от низа экрана

var engine_view: Control
var _fps_label: Label
var _garage_mode: bool = false
var _garage_ui: Control = null
var _door_busy: bool = false
var top_margin: float = 0.0

var _level_tab: Control
var _resources: Control
var _ips_label: Label
var _rebirth_label: Label
var _level_label: Label
var _stamina_bar: ProgressBar
var _stamina_label: Label
var _status_label: Label
var _xray_btn: Button
var _float_layer: Control
var _toast_box: VBoxContainer
var _overlay: Control
var _dim: ColorRect
var _open_panel: Control = null
var _open_side: String = ""
var _panels: Dictionary = {}
var _float_acc: float = 0.0
var _ui_acc: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UI.make_theme()
	H = maxf(1280.0, get_viewport_rect().size.y)
	ENGINE_BOTTOM = H - 350.0
	_compute_safe_area()

	# 3D-гараж с мотором — на весь экран, интерфейс поверх
	engine_view = preload("res://scripts/engine_view.gd").new()
	engine_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	engine_view.band = _engine_band(false)
	engine_view.hold_changed.connect(_on_hold)
	add_child(engine_view)
	_apply_engine()

	_build_top_bar()
	_build_engine_hud()
	_build_bottom_bar()

	_float_layer = Control.new()
	_float_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_float_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_float_layer)

	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.55)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.visible = false
	_dim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			close_panel())
	_overlay.add_child(_dim)

	add_child(_resources)

	_toast_box = VBoxContainer.new()
	_toast_box.anchor_right = 1.0
	_toast_box.offset_left = 30
	_toast_box.offset_right = -30
	_toast_box.offset_top = ENGINE_BOTTOM + 92
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(_toast_box)

	G.changed.connect(_refresh_all)
	G.level_up.connect(_on_level_up)
	G.new_epoch.connect(_on_new_epoch)
	G.turbo_started.connect(_on_turbo)
	G.crit.connect(_on_crit)
	G.gold_dropped.connect(_on_gold)
	G.exhausted.connect(_on_exhausted)
	G.toast.connect(show_toast)
	G.rebirth_done.connect(_on_rebirth)
	G.part_gained.connect(func(_s, _m, _r): _apply_engine())

	_refresh_all()
	if G.offline_report != null:
		call_deferred("_show_offline")


## Полоса экрана, где стоит мотор (между верхней плашкой и стаминой).
func _engine_band(shifted: bool) -> Rect2:
	var top := (ENGINE_TOP + top_margin) / H
	var bottom := ENGINE_BOTTOM / H
	if shifted:
		return Rect2(0.5, top, 0.5, bottom - top)
	return Rect2(0.0, top, 1.0, bottom - top)


func _engine_point(fx: float, fy: float) -> Vector2:
	var b: Rect2 = engine_view.band
	return Vector2(W * (b.position.x + b.size.x * fx), H * (b.position.y + b.size.y * fy))


func _compute_safe_area() -> void:
	var safe := DisplayServer.get_display_safe_area()
	var win := DisplayServer.window_get_size()
	if win.y > 0 and safe.size.y > 0:
		top_margin = clampf(safe.position.y * get_viewport_rect().size.y / float(win.y), 0.0, 90.0)


# ---------------------------------------------------------------------
# Построение интерфейса
# ---------------------------------------------------------------------

func _build_top_bar() -> void:
	# лёгкая тень сверху, чтобы плашки читались на фоне гаража
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0.6))
	grad.set_color(1, Color(0, 0, 0, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	var shade := TextureRect.new()
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.anchor_right = 1.0
	shade.offset_bottom = top_margin + 240
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	_level_tab = preload("res://scripts/ui/level_tab.gd").new()
	_level_tab.position = Vector2(4, top_margin + 4)
	_level_tab.size = Vector2(400, 156)
	_level_tab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_level_tab)

	_resources = preload("res://scripts/ui/resources_box.gd").new()
	_resources.anchor_left = 1.0
	_resources.anchor_right = 1.0
	_resources.offset_left = -310
	_resources.offset_right = -10
	_resources.offset_top = top_margin + 18
	_resources.offset_bottom = top_margin + 90
	_resources.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_rebirth_label = UI.label("", 19, Color("ffb35c"), HORIZONTAL_ALIGNMENT_RIGHT)
	_rebirth_label.anchor_left = 1.0
	_rebirth_label.anchor_right = 1.0
	_rebirth_label.offset_left = -310
	_rebirth_label.offset_right = -14
	_rebirth_label.offset_top = top_margin + 92
	_rebirth_label.add_theme_constant_override("outline_size", 5)
	_rebirth_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	add_child(_rebirth_label)

	_ips_label = UI.label("+0/с", 38, UI.GOOD)
	_ips_label.position = Vector2(20, top_margin + 150)
	_ips_label.size = Vector2(420, 50)
	_ips_label.add_theme_constant_override("outline_size", 8)
	_ips_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	add_child(_ips_label)

	_level_label = UI.label("", 19, Color("d8d2c4"), HORIZONTAL_ALIGNMENT_RIGHT)
	_level_label.anchor_left = 1.0
	_level_label.anchor_right = 1.0
	_level_label.offset_left = -420
	_level_label.offset_right = -14
	_level_label.offset_top = top_margin + 162
	_level_label.clip_text = true
	_level_label.add_theme_constant_override("outline_size", 5)
	_level_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	add_child(_level_label)


func _build_engine_hud() -> void:
	_stamina_bar = UI.bar(Color("ffb02e"), 18)
	_stamina_bar.anchor_left = 0.15
	_stamina_bar.anchor_right = 0.85
	_stamina_bar.offset_top = ENGINE_BOTTOM + 8
	_stamina_bar.offset_bottom = ENGINE_BOTTOM + 26
	_stamina_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stamina_bar)
	_stamina_label = UI.label("", 18, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_stamina_label.anchor_right = 1.0
	_stamina_label.offset_top = ENGINE_BOTTOM + 30
	_stamina_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stamina_label)
	_status_label = UI.label("", 20, Color("8fc4ff"), HORIZONTAL_ALIGNMENT_CENTER)
	_status_label.anchor_right = 1.0
	_status_label.offset_left = 20
	_status_label.offset_right = -20
	_status_label.offset_top = ENGINE_BOTTOM + 60
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_status_label)

	var hint := UI.label("Зажми мотор пальцем · проведи, чтобы повернуть", 18, Color(1, 1, 1, 0.35), HORIZONTAL_ALIGNMENT_CENTER)
	hint.name = "Hint"
	hint.anchor_right = 1.0
	hint.offset_top = ENGINE_BOTTOM + 120
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)

	_fps_label = UI.label("", 16, Color(0.6, 1.0, 0.6), HORIZONTAL_ALIGNMENT_LEFT)
	_fps_label.position = Vector2(14, ENGINE_TOP + top_margin + 14)
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fps_label)

	_xray_btn = UI.button("Рентген", 18, UI.PANEL_2, 48)
	_xray_btn.toggle_mode = true
	_xray_btn.anchor_left = 1.0
	_xray_btn.anchor_right = 1.0
	_xray_btn.offset_left = -150
	_xray_btn.offset_right = -14
	_xray_btn.offset_top = ENGINE_TOP + top_margin + 10
	_xray_btn.offset_bottom = ENGINE_TOP + top_margin + 58
	_xray_btn.button_pressed = G.settings.xray
	_xray_btn.toggled.connect(func(on: bool): G.settings.xray = on)
	add_child(_xray_btn)


func _build_bottom_bar() -> void:
	var bar := HBoxContainer.new()
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.anchor_right = 1.0
	bar.offset_left = 8
	bar.offset_right = -8
	bar.offset_top = -158
	bar.offset_bottom = -10
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 4)
	add_child(bar)
	for id in ["settings", "upgrades", "parts", "shop", "rebirth"]:
		var big: bool = id == "parts"
		var b := TextureButton.new()
		b.texture_normal = load("res://assets/icons/%s.png" % id)
		b.ignore_texture_size = true
		b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		b.custom_minimum_size = Vector2(148, 148) if big else Vector2(130, 130)
		b.size_flags_vertical = Control.SIZE_SHRINK_END
		b.focus_mode = Control.FOCUS_NONE
		var bid: String = id
		b.button_down.connect(func():
			b.pivot_offset = b.size * 0.5
			b.scale = Vector2(0.9, 0.9))
		b.button_up.connect(func():
			var tw := b.create_tween()
			tw.tween_property(b, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
		b.pressed.connect(func():
			Sfx.play("click")
			_resources.set_open(false)
			_toggle_panel(bid))
		bar.add_child(b)


# ---------------------------------------------------------------------
# Панели
# ---------------------------------------------------------------------

func _panel_for(id: String) -> Control:
	if _panels.has(id):
		return _panels[id]
	var p: Control
	match id:
		"settings":
			p = preload("res://scripts/ui/settings_panel.gd").new()
		"upgrades":
			p = preload("res://scripts/ui/upgrades_panel.gd").new()
		"parts":
			p = preload("res://scripts/ui/parts_panel.gd").new()
		"shop":
			p = preload("res://scripts/ui/shop_panel.gd").new()
		"rebirth":
			p = preload("res://scripts/ui/rebirth_panel.gd").new()
	p.set("main", self)
	p.visible = false
	_overlay.add_child(p)
	_panels[id] = p
	return p


func _side_of(id: String) -> String:
	match id:
		"upgrades":
			return "left"
		"parts", "shop":
			return "bottom"
	return "center"


func _toggle_panel(id: String) -> void:
	if id == "parts":
		_toggle_garage()
		return
	var p := _panel_for(id)
	if _open_panel == p:
		close_panel()
		return
	if _open_panel != null:
		close_panel(true)
	open_panel(p, _side_of(id))


func open_panel(p: Control, side: String) -> void:
	_open_panel = p
	_open_side = side
	if side != "left":
		get_tree().create_timer(0.35).timeout.connect(func():
			if _open_panel == p:
				engine_view.render_paused = true)
	p.visible = true
	if p.has_method("refresh"):
		p.refresh()
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	match side:
		"left":
			# до середины экрана, мотор остаётся виден справа
			p.anchor_left = 0.0
			p.anchor_right = 0.0
			p.anchor_top = 0.0
			p.anchor_bottom = 1.0
			p.offset_top = top_margin + 222
			p.offset_bottom = -168
			p.size.x = W * 0.56
			p.offset_left = -W * 0.56
			p.offset_right = 0
			tw.tween_property(p, "offset_left", 0.0, 0.28)
			tw.tween_property(p, "offset_right", W * 0.56, 0.28)
			tw.tween_property(engine_view, "band", _engine_band(true), 0.28)
			_dim.visible = false
		"bottom":
			p.anchor_left = 0.0
			p.anchor_right = 1.0
			p.anchor_top = 1.0
			p.anchor_bottom = 1.0
			p.offset_left = 0
			p.offset_right = 0
			var h := H * 0.66
			p.offset_top = 10
			p.offset_bottom = h + 10
			tw.tween_property(p, "offset_top", -h, 0.3)
			tw.tween_property(p, "offset_bottom", 0.0, 0.3)
			_dim.visible = true
			_dim.modulate.a = 0.0
			tw.tween_property(_dim, "modulate:a", 1.0, 0.25)
		"center":
			p.anchor_left = 0.5
			p.anchor_right = 0.5
			p.anchor_top = 0.5
			p.anchor_bottom = 0.5
			p.offset_left = -W * 0.46
			p.offset_right = W * 0.46
			p.offset_top = -H * 0.38
			p.offset_bottom = H * 0.38
			p.pivot_offset = Vector2(W * 0.46, H * 0.38)
			p.scale = Vector2(0.85, 0.85)
			p.modulate.a = 0.0
			tw.tween_property(p, "scale", Vector2.ONE, 0.22)
			tw.tween_property(p, "modulate:a", 1.0, 0.18)
			_dim.visible = true
			_dim.modulate.a = 0.0
			tw.tween_property(_dim, "modulate:a", 1.0, 0.2)
	_overlay.move_child(_dim, 0)


func close_panel(instant: bool = false) -> void:
	var p := _open_panel
	if p == null:
		return
	var side := _open_side
	_open_panel = null
	_open_side = ""
	engine_view.render_paused = false
	if instant:
		p.visible = false
		engine_view.band = _engine_band(false)
		_dim.visible = false
		return
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	match side:
		"left":
			tw.tween_property(p, "offset_left", -W * 0.56, 0.22)
			tw.tween_property(p, "offset_right", 0.0, 0.22)
			tw.tween_property(engine_view, "band", _engine_band(false), 0.22)
		"bottom":
			tw.tween_property(p, "offset_top", 10.0, 0.22)
			tw.tween_property(p, "offset_bottom", H * 0.66 + 10.0, 0.22)
		"center":
			tw.tween_property(p, "modulate:a", 0.0, 0.15)
			tw.tween_property(p, "scale", Vector2(0.9, 0.9), 0.15)
	tw.tween_property(_dim, "modulate:a", 0.0, 0.2)
	tw.chain().tween_callback(func():
		if _open_panel != p:
			p.visible = false
		if _open_panel == null:
			_dim.visible = false)


# ---------------------------------------------------------------------
# Режим гаража
# ---------------------------------------------------------------------

func _toggle_garage() -> void:
	if _door_busy:
		return
	_door_busy = true
	var door := preload("res://scripts/ui/garage_door.gd").new()
	add_child(door)
	door.closed.connect(func(): _set_garage(not _garage_mode))
	door.tree_exited.connect(func(): _door_busy = false)
	door.play()


func _set_garage(on: bool) -> void:
	_garage_mode = on
	close_panel(true)
	engine_view.locked = on
	engine_view.mouse_filter = Control.MOUSE_FILTER_IGNORE if on else Control.MOUSE_FILTER_STOP
	G.set_holding(false)
	var top := (ENGINE_TOP + top_margin + 90.0) / H
	var bottom := (ENGINE_BOTTOM + 60.0) / H
	engine_view.band = Rect2(0.16, top, 0.68, bottom - top) if on else _engine_band(false)
	for n in [_stamina_bar, _stamina_label, _status_label, _xray_btn, get_node_or_null("Hint")]:
		if n:
			n.visible = not on
	if on:
		if _garage_ui == null:
			_garage_ui = preload("res://scripts/ui/garage_mode.gd").new()
			_garage_ui.main = self
			_garage_ui.engine_view = engine_view
			add_child(_garage_ui)
			move_child(_garage_ui, engine_view.get_index() + 1)
		_garage_ui.visible = true
		_garage_ui.set("_layout_key", "")
	elif _garage_ui != null:
		_garage_ui.visible = false
		_garage_ui.process_mode = Node.PROCESS_MODE_INHERIT
	if _garage_ui != null:
		_garage_ui.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


## Открыть выбор вариантов для одной детали (из режима гаража).
func open_slot(slot_id: String) -> void:
	var p := _panel_for("parts")
	p.set("only_slot", slot_id)
	if _open_panel != null:
		close_panel(true)
	open_panel(p, "bottom")


# ---------------------------------------------------------------------
# Обновление
# ---------------------------------------------------------------------

func _apply_engine() -> void:
	var ep := D.epoch_info(G.level)
	engine_view.set_engine(G.current_engine(), ep.material)


func _refresh_all() -> void:
	_refresh_numbers()
	if _open_panel != null and _open_panel.has_method("refresh"):
		_open_panel.refresh()


func _refresh_numbers() -> void:
	_resources.refresh()
	_ips_label.text = "+%s/с" % G.fmt(G.income_now.mul(G.d_time_mult))
	_ips_label.add_theme_color_override("font_color", Color("6fb6ff") if G.turbo_time > 0.0 else (UI.GOOD if G.throttle else Color("b9d7a8")))
	var mult := Big.power(1.25, G.rebirths).mul(Big.power(100.0, G.ultra))
	var rtxt := "Перерождение %d (x%s)" % [G.rebirths, G.fmt(mult)]
	if G.ultra > 0:
		rtxt = "Ультра %d · " % G.ultra + rtxt
	_rebirth_label.text = rtxt
	var ep := D.epoch_info(G.level)
	_level_label.text = "%s · %s" % [D.ENGINES[G.current_engine()].name, D.MATERIALS[ep.material].name]
	_level_tab.level = G.level
	_level_tab.progress = clampf(G.xp.div(G.xp_need(G.level)).to_float(), 0.0, 1.0)


func _process(delta: float) -> void:
	# камера слегка дрожит вместе с мотором
	if _fps_label != null:
		_fps_label.visible = G.settings.get("show_fps", false)
		if _fps_label.visible:
			_fps_label.text = "%d FPS" % Engine.get_frames_per_second()
	_stamina_bar.value = G.stamina / maxf(G.d_stamina_max, 0.01)
	var sb: StyleBoxFlat = _stamina_bar.get_theme_stylebox("fill")
	sb.bg_color = Color("ff4a3a") if G.is_exhausted else (Color("6fb6ff") if G.has_boost("stamina") else Color("ffb02e"))
	if G.has_boost("stamina"):
		_stamina_label.text = "Стамина: бесконечная"
	elif G.is_exhausted:
		_stamina_label.text = "Перегрев! Мотор остывает…"
	else:
		_stamina_label.text = "Стамина %.1f / %.1f с" % [G.stamina, G.d_stamina_max]
	var hint := get_node_or_null("Hint")
	if hint:
		hint.visible = G.stats.presses < 5 and _toast_box.get_child_count() == 0

	_ui_acc += delta
	if _ui_acc >= 0.1:
		_ui_acc = 0.0
		_refresh_numbers()
		_status_label.text = _status_text()
		if _open_panel != null and _open_panel.has_method("tick"):
			_open_panel.tick()

	if G.throttle:
		_float_acc += delta
		if _float_acc >= 0.5:
			_float_acc = 0.0
			var amt := G.income_now.mul(0.5 * G.d_time_mult)
			var col := Color("8fc4ff") if G.turbo_time > 0.0 else UI.GOOD
			float_text("+" + G.fmt(amt), col, 26)
	else:
		_float_acc = 0.0


func _status_text() -> String:
	var parts: Array = []
	if G.turbo_time > 0.0:
		parts.append("ТУРБО x%s" % _fmt_mult(G.d_turbo_mult))
	if G.has_boost("income"):
		parts.append("x2 доход %s" % UI.time_text(G.boost_left("income")))
	if G.has_boost("stamina"):
		parts.append("стамина ∞ %s" % UI.time_text(G.boost_left("stamina")))
	if G.guaranteed_turbo:
		parts.append("турбо гарантирован")
	if G.d_autogas_on and not G.holding:
		parts.append("автогаз через %.0f с" % maxf(0.0, G.d_autogas_int - G.autogas_timer))
	return "  ·  ".join(parts)


func _fmt_mult(v: float) -> String:
	if v < 100.0:
		return ("%.1f" % v).trim_suffix(".0")
	return G.fmt(v)


# ---------------------------------------------------------------------
# События
# ---------------------------------------------------------------------

func _on_hold(pressed: bool) -> void:
	G.set_holding(pressed)
	if pressed:
		G.vibrate(15)


func float_text(text: String, color: Color, size: int = 26, at: Vector2 = Vector2(-1, -1)) -> void:
	var l := UI.label(text, size, color, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	var center := _engine_point(0.5, 0.3)
	if at.x < 0.0:
		at = center + Vector2(randf_range(-150, 150), randf_range(-60, 60))
	l.size = Vector2(400, 40)
	l.position = at - Vector2(200, 20)
	_float_layer.add_child(l)
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 90.0, 1.1).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 1.1).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)


func show_toast(text: String, color: Color = UI.TEXT) -> void:
	var p := UI.card(Color(0.08, 0.085, 0.1, 0.95), Color(color.r, color.g, color.b, 0.6), 10)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UI.wrap_label(text, 18, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	_toast_box.add_child(p)
	var hint := get_node_or_null("Hint")
	if hint:
		hint.visible = false
	while _toast_box.get_child_count() > 2:
		_toast_box.get_child(0).queue_free()
		_toast_box.remove_child(_toast_box.get_child(0))
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.2)
	tw.tween_interval(2.6)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(p.queue_free)


func _on_level_up(lvl: int) -> void:
	_apply_engine()
	if (lvl - 1) % 10 != 0:
		show_toast("Уровень %d! Доход x1.05" % lvl, Color("8fc4ff"))
		Sfx.play("buy", 1.2)


func _on_new_epoch(ei: int) -> void:
	_apply_engine()
	var scr := preload("res://scripts/ui/epoch_screen.gd").new()
	scr.epoch_index = ei
	scr.level = G.level
	add_child(scr)


func _on_turbo() -> void:
	Sfx.play("turbo")
	engine_view.turbo_kick()
	float_text("ТУРБО x%s!" % _fmt_mult(G.d_turbo_mult), Color("6fb6ff"), 40,
		_engine_point(0.5, 0.15))


func _on_crit(amount: Big) -> void:
	Sfx.play("crit")
	engine_view.burst_sparks()
	G.vibrate(40)
	float_text("КРИТ! +%s" % G.fmt(amount), Color("ffb02e"), 42,
		_engine_point(0.5, 0.25))


func _on_gold(n: int) -> void:
	Sfx.play("coin")
	float_text("+%d золото" % n, D.CURRENCIES.gold.color, 30)


func _on_exhausted() -> void:
	Sfx.play("knock")
	G.vibrate(120)
	float_text("ПЕРЕГРЕВ!", UI.BAD, 38, _engine_point(0.5, 0.2))


func _on_rebirth() -> void:
	Sfx.play("rebirth")
	engine_view.flash_white = 0.9
	_apply_engine()
	_refresh_all()


func _show_offline() -> void:
	var p := UI.card(UI.PANEL, UI.ACCENT, 20)
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.custom_minimum_size = Vector2(560, 0)
	p.position = Vector2(80, 470)
	var v := VBoxContainer.new()
	p.add_child(v)
	v.add_child(UI.label("Офлайн-гараж", 32, UI.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UI.wrap_label("Пока вас не было (%s), гараж заработал:" % UI.time_text(G.offline_seconds), 22, UI.TEXT))
	v.add_child(UI.label("+%s" % G.fmt(G.offline_report), 40, UI.GOOD, HORIZONTAL_ALIGNMENT_CENTER))
	var ok := UI.accent_button("Забрать", 26)
	v.add_child(ok)
	ok.pressed.connect(func():
		Sfx.play("coin")
		p.queue_free())
	add_child(p)
	G.offline_report = null


## Анимация открытия кейса (вызывается из магазина).
func play_case_opening(result: Dictionary) -> void:
	if result.is_empty():
		return
	var scr := preload("res://scripts/ui/case_opening.gd").new()
	scr.result = result
	add_child(scr)
