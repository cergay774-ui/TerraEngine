extends Control
## Главный экран: верхняя панель с валютами, мотор по центру, стамина, 5 кнопок внизу.

var W: float = 720.0           # ширина экрана в единицах интерфейса (на широких экранах больше)
var H: float = 1280.0          # высота экрана в единицах интерфейса (на вытянутых телефонах больше)
const ENGINE_TOP := 205.0
var ENGINE_BOTTOM: float = 930.0  # низ полосы мотора — считается от низа экрана

var engine_view: Control
var _fps_label: Label
var _garage_mode: bool = false
var _garage_ui: Control = null
var _door_busy: bool = false
var _panel_tween: Tween = null
var _epoch_screen: Control = null
var _pending_level: int = 0
var _fps_low_time: float = 0.0
var _fps_check_acc: float = 0.0
var _auto_cooldown: float = 20.0
var top_margin: float = 0.0

var _level_tab: Control
var _resources: Control
var _rebirth_label: Label
var _level_label: Label
var _stamina_gauge: Control
var _float_gain: Big = Big.zero()
var _float_next: float = 0.5
var _last_float_angle: float = 0.0
var _badges: Dictionary = {}      # кнопка нижней панели -> точка «есть что купить»
var _badge_acc: float = 0.0
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
	W = maxf(720.0, get_viewport_rect().size.x)
	ENGINE_BOTTOM = H - 350.0
	_compute_safe_area()

	# 3D-гараж с мотором — на весь экран, интерфейс поверх
	engine_view = preload("res://scripts/engine_view.gd").new()
	# сразу нужный мотор — иначе при старте собирается сначала мотор «по умолчанию», потом нужный
	engine_view.engine_type = G.current_engine()
	engine_view.material_index = D.epoch_info(G.level).material
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
	G.settings_changed.connect(func(): _xray_btn.set_pressed_no_signal(G.settings.xray))
	G.offline_ready.connect(func(): call_deferred("_show_offline"))

	_refresh_all()
	if G.offline_report != null:
		call_deferred("_show_offline")
	# сторож зависаний — после того как игра загрузилась и шейдеры первого кадра собраны
	get_tree().create_timer(4.0).timeout.connect(Diag.arm)
	if G.stall_renderer_switched:
		G.stall_renderer_switched = false
		get_tree().create_timer(1.5).timeout.connect(func():
			show_toast("Прошлый запуск подвисал — со следующего запуска игра включит режим OpenGL. Вернуть можно в настройках.", Color("ffc21a")))
	if G.stall_downgraded:
		G.stall_downgraded = false
		get_tree().create_timer(1.5).timeout.connect(func():
			show_toast("Прошлый запуск подвисал — графика снижена до «Низкой». Вернуть можно в настройках.", Color("ffc21a")))


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
	# стамина — вертикальная капсула справа посередине полосы мотора
	_stamina_gauge = preload("res://scripts/ui/stamina_gauge.gd").new()
	var band_top := ENGINE_TOP + top_margin + 70.0
	var band_mid := (band_top + ENGINE_BOTTOM) * 0.5
	var gh := minf(430.0, ENGINE_BOTTOM - band_top)
	_stamina_gauge.position = Vector2(W - 70.0, band_mid - gh * 0.5)
	_stamina_gauge.size = Vector2(60.0, gh)
	add_child(_stamina_gauge)
	_status_label = UI.label("", 20, Color("8fc4ff"), HORIZONTAL_ALIGNMENT_CENTER)
	_status_label.anchor_right = 1.0
	_status_label.offset_left = 20
	_status_label.offset_right = -20
	_status_label.offset_top = ENGINE_BOTTOM + 20
	_status_label.add_theme_constant_override("outline_size", 6)
	_status_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
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
	_xray_btn.toggled.connect(func(on: bool):
		G.settings.xray = on
		G.apply_settings())
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
		# точка «есть что купить/забрать»
		var dot := Control.new()
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.size = Vector2(26, 26)
		dot.position = Vector2(b.custom_minimum_size.x - 30, 4)
		dot.visible = false
		dot.pivot_offset = Vector2(13, 13)
		dot.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		# рисуется один раз; «дыхание» — масштабом в _process, без перерисовки
		dot.draw.connect(func():
			UI.draw_disc(dot, Vector2(13, 13), 12.0, Color(0, 0, 0, 0.6))
			UI.draw_disc(dot, Vector2(13, 13), 9.0, Color("8fe36b"))
			UI.draw_disc(dot, Vector2(11, 11), 3.2, Color(1, 1, 1, 0.7)))
		b.add_child(dot)
		_badges[id] = {"button": b, "dot": dot}


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
	Diag.event("меню открыто: " + str(p.get_script().resource_path.get_file()))
	_open_panel = p
	_open_side = side
	if side != "left":
		get_tree().create_timer(0.35).timeout.connect(func():
			if _open_panel == p:
				engine_view.render_paused = true)
	p.visible = true
	if p.has_method("refresh"):
		p.refresh()
	_kill_panel_tween()
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_panel_tween = tw
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
			if not _garage_mode:
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
			tw.tween_property(p, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK)
			tw.tween_property(p, "modulate:a", 1.0, 0.18)
			_dim.visible = true
			_dim.modulate.a = 0.0
			tw.tween_property(_dim, "modulate:a", 1.0, 0.2)
	_overlay.move_child(_dim, 0)


func _kill_panel_tween() -> void:
	if _panel_tween != null and _panel_tween.is_valid():
		_panel_tween.custom_step(10.0)  # довести прежнюю анимацию до конца (полоса мотора, скрытие панели)
		_panel_tween.kill()
	_panel_tween = null


## Обычное положение мотора: в гараже — своя рамка между карточками.
func _base_band() -> Rect2:
	if _garage_mode:
		var top := (ENGINE_TOP + top_margin + 90.0) / H
		var bottom := (ENGINE_BOTTOM + 60.0) / H
		return Rect2(0.16, top, 0.68, bottom - top)
	return _engine_band(false)


func close_panel(instant: bool = false) -> void:
	var p := _open_panel
	if p == null:
		return
	var side := _open_side
	_open_panel = null
	_open_side = ""
	engine_view.render_paused = _epoch_screen != null
	_kill_panel_tween()
	if instant:
		p.visible = false
		engine_view.band = _base_band()
		_dim.visible = false
		return
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_panel_tween = tw
	match side:
		"left":
			tw.tween_property(p, "offset_left", -W * 0.56, 0.22)
			tw.tween_property(p, "offset_right", 0.0, 0.22)
			tw.tween_property(engine_view, "band", _base_band(), 0.22)
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
	Diag.event("гараж " + ("вход" if on else "выход"))
	_garage_mode = on
	close_panel(true)
	engine_view.locked = on
	engine_view.mouse_filter = Control.MOUSE_FILTER_IGNORE if on else Control.MOUSE_FILTER_STOP
	G.set_holding(false)
	engine_view.band = _base_band()
	for n in [_stamina_gauge, _status_label, _xray_btn, get_node_or_null("Hint")]:
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
	if _open_panel != null and _open_panel.has_method("refresh") and _open_panel != _panels.get("settings"):
		_open_panel.refresh()


func _refresh_numbers() -> void:
	_resources.refresh()
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
	var hint := get_node_or_null("Hint")
	if hint:
		hint.visible = G.stats.presses < 5 and _toast_box.get_child_count() == 0 and not _garage_mode

	_ui_acc += delta
	if _ui_acc >= 0.1:
		_ui_acc = 0.0
		_refresh_numbers()
		_status_label.text = _status_text()
		if _open_panel != null and _open_panel.has_method("tick"):
			_open_panel.tick()

	# доход всплывает «+X» вокруг мотора: при зажатии часто и ярко, на холостых реже и бледнее
	if _garage_mode:
		_float_gain = Big.zero()
		_float_acc = 0.0
	else:
		_float_gain = _float_gain.add(G.income_now.mul(delta * G.d_time_mult))
		_float_acc += delta
	if _float_acc >= _float_next and not _garage_mode:
		_float_acc = 0.0
		_float_next = randf_range(0.35, 0.55) if G.throttle else randf_range(1.4, 1.9)
		if not _float_gain.is_zero():
			_income_popup(_float_gain)
		_float_gain = Big.zero()

	_auto_quality(delta)

	_badge_acc += delta
	if _badge_acc >= 0.5:
		_badge_acc = 0.0
		_update_badges()
	var breathe := 1.0 + 0.15 * sin(Time.get_ticks_msec() / 1000.0 * 6.0)
	for id in _badges:
		var dot: Control = _badges[id].dot
		if dot.visible and not _badge_tweening(dot):
			dot.scale = Vector2(breathe, breathe)


func _badge_tweening(dot: Control) -> bool:
	return Time.get_ticks_msec() < int(dot.get_meta("pop_until", 0))


## Если телефон не тянет (FPS долго ниже 22), графика сама снижается на ступень.
func _auto_quality(delta: float) -> void:
	_auto_cooldown = maxf(0.0, _auto_cooldown - delta)
	_fps_check_acc += delta
	if _fps_check_acc < 1.0:
		return
	_fps_check_acc = 0.0
	if _open_panel != null or _garage_mode or _epoch_screen != null:
		_fps_low_time = 0.0
		return
	var fps := Engine.get_frames_per_second()
	if fps > 0 and fps < 22:
		_fps_low_time += 1.0
	else:
		_fps_low_time = 0.0
	var q := int(G.settings.quality)
	if _fps_low_time >= 5.0 and _auto_cooldown <= 0.0 and q > 0:
		_fps_low_time = 0.0
		_auto_cooldown = 20.0
		Diag.event("автоснижение графики, fps=%d" % Engine.get_frames_per_second())
		G.apply_preset(q - 1)
		show_toast("Графика снижена до «%s» для плавности" % ["Низкое", "Среднее", "Высокое", "Ультра"][q - 1], Color("ffc21a"))


## Зелёные точки на кнопках: есть доступное улучшение, запчасть, награда или перерождение.
func _update_badges() -> void:
	if _badges.is_empty():
		return
	var any_upg := false
	for u in D.UPGRADES:
		if G.upgrade_unlocked(u.id) and G.upgrade_affordable(u.id) > 0:
			any_upg = true
			break
	var any_part := false
	for sl in D.SLOTS:
		if not G.slot_visible(sl.id):
			continue
		var o := G.mark_offer(sl.id, G.best_mark(sl.id) + 1)
		if o.ok and (o.free or G.can_pay(o.cur, o.price)):
			any_part = true
			break
	var any_shop := false
	for t in G.daily_tasks():
		if not t.claimed and t.progress >= t.goal:
			any_shop = true
			break
	var flags := {"settings": false, "upgrades": any_upg, "parts": any_part, "shop": any_shop, "rebirth": G.can_rebirth()}
	for id in _badges:
		var dot: Control = _badges[id].dot
		var on: bool = flags.get(id, false)
		if on and not dot.visible:
			dot.scale = Vector2(0.2, 0.2)
			dot.pivot_offset = dot.size * 0.5
			dot.set_meta("pop_until", Time.get_ticks_msec() + 360)
			dot.create_tween().tween_property(dot, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		dot.visible = on


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


## «+X» в случайной точке вокруг мотора: появляется с пружинкой, уплывает наружу и вверх, тает.
func _income_popup(amount: Big) -> void:
	var turbo := G.turbo_time > 0.0
	var holding := G.throttle
	var col := Color("8fc4ff") if turbo else (UI.GOOD if holding else Color(0.75, 0.9, 0.7, 0.85))
	var fsize := 30 if holding else 22
	var center := _engine_point(0.5, 0.5)
	var b: Rect2 = engine_view.band
	var rx := W * b.size.x * 0.36
	var ry := H * b.size.y * 0.38
	var ang := randf() * TAU
	for _i in 6:
		if absf(angle_difference(ang, _last_float_angle)) > 0.9:
			break
		ang = randf() * TAU
	_last_float_angle = ang
	var dir := Vector2(cos(ang), sin(ang))
	var at := center + dir * Vector2(rx, ry) * randf_range(0.75, 1.0)
	var l := UI.label("+" + G.fmt(amount), fsize, col, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	l.size = Vector2(260, 44)
	l.position = at - l.size * 0.5
	l.pivot_offset = l.size * 0.5
	l.scale = Vector2(0.35, 0.35)
	l.modulate.a = 0.0
	l.rotation = randf_range(-0.08, 0.08)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_float_layer.add_child(l)
	var drift := dir * 26.0 + Vector2(0, -46.0)
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 1.0, 0.16)
	tw.tween_property(l, "position", l.position + drift, 1.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "rotation", 0.0, 0.5)
	tw.tween_property(l, "modulate:a", 0.0, 0.5).set_delay(0.8)
	tw.chain().tween_callback(l.queue_free)


func float_text(text: String, color: Color, size: int = 26, at: Vector2 = Vector2(-1, -1)) -> void:
	# надпись влетает с перелётом и вспышкой, по ней бежит блик; крупные — со свечением
	# и горстью блёсток (всё — узлы с шейдерами и частицы, см. ui_fx.gd)
	if at.x < 0.0:
		at = _engine_point(0.5, 0.3) + Vector2(randf_range(-150, 150), randf_range(-60, 60))
	preload("res://scripts/ui/ui_fx.gd").pop_text(_float_layer, text, color, size, at)


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
	p.scale = Vector2(0.92, 0.92)
	p.resized.connect(func(): p.pivot_offset = p.size * 0.5)
	var tw := p.create_tween()
	tw.set_parallel(true)
	tw.tween_property(p, "modulate:a", 1.0, 0.22)
	tw.tween_property(p, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(2.6)
	tw.chain().tween_property(p, "modulate:a", 0.0, 0.4)
	tw.chain().tween_callback(p.queue_free)


func _on_level_up(lvl: int) -> void:
	if _pending_level == 0:
		call_deferred("_flush_level_up")
	_pending_level = maxi(_pending_level, lvl)


func _flush_level_up() -> void:
	var lvl := _pending_level
	Diag.event("уровень %d" % lvl)
	_pending_level = 0
	_apply_engine()
	engine_view.fx_event("level_up")
	if (lvl - 1) % 10 != 0:
		show_toast("Уровень %d! Доход x1.05" % lvl, Color("8fc4ff"))
		Sfx.play("buy", 1.2)
		# золотое кольцо и искры вокруг значка уровня, блик по полосе опыта
		# (координаты — как у плашки level_tab: фон 838x326, значок (152, 286), полоса (414, 144, 392, 75))
		var bg_size := Vector2(838, 326)
		var k := minf(_level_tab.size.x / bg_size.x, _level_tab.size.y / bg_size.y)
		var badge: Vector2 = _level_tab.position + Vector2(152, 286) * k
		var bar := Rect2(_level_tab.position + Vector2(414, 144) * k, Vector2(392, 75) * k)
		preload("res://scripts/ui/ui_fx.gd").level_up(_float_layer, badge, bar)


func _on_new_epoch(ei: int) -> void:
	Diag.event("новая эпоха %d" % ei)
	_apply_engine()
	# одна заставка за раз; под ней основной 3D не рисуем (две 3D-сцены сразу — тяжело)
	if _epoch_screen != null and is_instance_valid(_epoch_screen):
		_epoch_screen.queue_free()
	var scr := preload("res://scripts/ui/epoch_screen.gd").new()
	scr.epoch_index = ei
	scr.level = G.level
	add_child(scr)
	_epoch_screen = scr
	engine_view.render_paused = true
	scr.tree_exited.connect(func():
		if _epoch_screen == scr:
			_epoch_screen = null
			engine_view.render_paused = _open_panel != null and _open_side != "left")


func _on_turbo() -> void:
	Sfx.play("turbo")
	engine_view.turbo_kick()
	preload("res://scripts/ui/ui_fx.gd").pop_text(_float_layer, "ТУРБО x%s!" % _fmt_mult(G.d_turbo_mult),
		Color("6fb6ff"), 44, _engine_point(0.5, 0.15), "turbo")


func _on_crit(amount: Big) -> void:
	Sfx.play("crit")
	engine_view.burst_sparks()
	G.vibrate(40)
	preload("res://scripts/ui/ui_fx.gd").pop_text(_float_layer, "КРИТ! +%s" % G.fmt(amount),
		Color("ffb02e"), 46, _engine_point(0.5, 0.25), "crit")


func _on_gold(n: int) -> void:
	Sfx.play("coin")
	engine_view.fx_event("gold")
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
	if G.offline_report == null:
		return
	var old := get_node_or_null("OfflinePopup")
	if old:
		old.queue_free()
	var p := UI.card(UI.PANEL, UI.ACCENT, 20)
	p.name = "OfflinePopup"
	p.custom_minimum_size = Vector2(560, 0)
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
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 0.5
	p.anchor_bottom = 0.5
	p.offset_left = -280
	p.offset_right = 280
	p.offset_top = -150
	p.offset_bottom = 150
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	p.pivot_offset = Vector2(280, 150)
	p.scale = Vector2(0.8, 0.8)
	p.create_tween().tween_property(p, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	G.offline_report = null


## Анимация открытия кейса (вызывается из магазина).
func play_case_opening(result: Dictionary) -> void:
	if result.is_empty():
		return
	var scr := preload("res://scripts/ui/case_opening.gd").new()
	scr.result = result
	add_child(scr)


# ---------------------------------------------------------------------
# Кнопка «Назад» Android: закрывает окно/меню/гараж, а не игру
# ---------------------------------------------------------------------

func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST:
		return
	var off := get_node_or_null("OfflinePopup")
	if off:
		off.queue_free()
		return
	if _epoch_screen != null and is_instance_valid(_epoch_screen):
		_epoch_screen.queue_free()
		return
	for c in get_children():
		if c.get_script() == preload("res://scripts/ui/case_opening.gd"):
			c.queue_free()
			return
	if _resources.get("_open"):
		_resources.set_open(false)
		return
	if _open_panel != null:
		close_panel()
		return
	if _garage_mode:
		_toggle_garage()
		return
	G.save_game()
	get_tree().quit()
