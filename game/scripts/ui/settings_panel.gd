extends PanelContainer
## Настройки: вкладки «Графика», «Звук», «Игра», «Данные».

var main: Control
var _tab: int = 0
var _tab_btns: Array = []
var _content: VBoxContainer
var _save_text: TextEdit
var _reset_armed: bool = false


func _ready() -> void:
	add_theme_stylebox_override("panel", UI.box(Color(0.09, 0.095, 0.115, 0.98), 22, Color("ffc21a").darkened(0.4), 2, 16))
	var v := VBoxContainer.new()
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := UI.label("Настройки", 30, UI.ACCENT)
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
		var b := UI.button(["Графика", "Звук", "Игра", "Данные"][i], 18, UI.PANEL_2, 48)
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
	_content.add_theme_constant_override("separation", 12)
	scroll.add_child(_content)


func refresh() -> void:
	for i in _tab_btns.size():
		_tab_btns[i].button_pressed = i == _tab
	UI.clear(_content)
	_reset_armed = false
	match _tab:
		0:
			_build_graphics()
		1:
			_build_sound()
		2:
			_build_game()
		3:
			_build_data()


func _put(key: String, value) -> void:
	G.settings[key] = value
	G.apply_settings()


func _build_graphics() -> void:
	_section("Пресет")
	_choice("Качество", ["Низкое", "Среднее", "Высокое", "Ультра"], int(G.settings.quality), func(i):
		G.apply_preset(i)
		refresh())
	_hint("Пресет выставляет все пункты ниже. Их можно поменять по одному.")
	_section("Детали")
	_choice("Тени", ["Выкл", "Чёткие", "Мягкие"], int(G.settings.shadows), func(i): _put("shadows", i))
	_choice("Сглаживание", ["Выкл", "2x", "4x"], [0, 2, 4].find(int(G.settings.msaa)), func(i): _put("msaa", [0, 2, 4][i]))
	_choice("Частицы", ["Мало", "Средне", "Много"], int(G.settings.particles), func(i): _put("particles", i))
	_choice("Разрешение 3D", ["60%", "85%", "100%"], _res_index(), func(i): _put("res_scale", [0.6, 0.85, 1.0][i]))
	_toggle("Свечение (bloom)", G.settings.glow, func(on): _put("glow", on))
	_toggle("Гараж вокруг мотора", G.settings.garage, func(on): _put("garage", on))
	_section("Экран")
	_choice("Частота кадров", ["30", "60", "90", "120"], [30, 60, 90, 120].find(int(G.settings.fps)), func(i): _put("fps", [30, 60, 90, 120][i]))
	_toggle("Показывать FPS", G.settings.show_fps, func(on): _put("show_fps", on))
	_hint("Если телефон греется или тормозит — выберите «Низкое» или «Среднее» и 30 FPS.")


func _res_index() -> int:
	var r := float(G.settings.res_scale)
	if r < 0.7:
		return 0
	if r < 0.95:
		return 1
	return 2


func _build_sound() -> void:
	_slider("Громкость звуков", G.settings.sfx, func(val): _put("sfx", val))
	_slider("Громкость музыки", G.settings.music, func(val): _put("music", val))
	_toggle("Вибрация", G.settings.vibration, func(on): _put("vibration", on))
	_hint("Звук мотора синтезируется кодом. Свои звуки (.ogg) можно положить в assets/sounds.")


func _build_game() -> void:
	_section("Камера")
	_toggle("Тряска мотора и камеры", G.settings.shake, func(on): _put("shake", on))
	_toggle("Плавное покачивание камеры", G.settings.cam_sway, func(on): _put("cam_sway", on))
	_slider("Приближение", (float(G.settings.cam_zoom) - 0.7) / 0.7, func(val): _put("cam_zoom", 0.7 + val * 0.7))
	_toggle("Рентген (прозрачный корпус)", G.settings.xray, func(on): _put("xray", on))
	_section("Интерфейс")
	_choice("Формат чисел", ["1.5T", "1.5e12"], 1 if G.settings.sci else 0, func(i):
		_put("sci", i == 1)
		G.changed.emit())
	_choice("Язык", ["Русский"], 0, func(_i): pass)


func _build_data() -> void:
	_content.add_child(UI.label("Сохранение", 22, UI.TEXT))
	_hint("Игра сохраняется сама каждые 30 секунд и при сворачивании. Экспорт копирует сохранение в буфер обмена — его можно вставить на другом телефоне.")
	_save_text = TextEdit.new()
	_save_text.custom_minimum_size.y = 110
	_save_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_save_text.placeholder_text = "Вставьте сюда код сохранения для импорта"
	_content.add_child(_save_text)
	var h := HBoxContainer.new()
	_content.add_child(h)
	var ex := UI.button("Экспорт", 20, UI.PANEL_2, 56)
	ex.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ex.pressed.connect(func():
		var code := G.export_save()
		_save_text.text = code
		DisplayServer.clipboard_set(code)
		main.show_toast("Сохранение скопировано в буфер обмена", UI.GOOD))
	h.add_child(ex)
	var im := UI.button("Импорт", 20, UI.PANEL_2, 56)
	im.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	im.pressed.connect(func():
		var code := _save_text.text.strip_edges()
		if code == "":
			code = DisplayServer.clipboard_get()
		if G.import_save(code):
			main.show_toast("Сохранение загружено", UI.GOOD)
			main._apply_engine()
			main.close_panel()
		else:
			main.show_toast("Не удалось прочитать код сохранения", UI.BAD))
	h.add_child(im)
	var reset := UI.button("Сбросить весь прогресс", 18, Color("3a1c1c"), 52)
	reset.pressed.connect(func():
		if not _reset_armed:
			_reset_armed = true
			reset.text = "Точно? Нажмите ещё раз"
			return
		G.reset_progress()
		main._apply_engine()
		main.close_panel()
		main.show_toast("Прогресс сброшен", UI.BAD))
	_content.add_child(reset)
	_content.add_child(UI.label("My Engine Garage · версия %s" % ProjectSettings.get_setting("application/config/version", "0.1"), 14, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER))


func _section(title: String) -> void:
	var l := UI.label(title, 20, Color("ffc21a"))
	_content.add_child(l)


func _hint(text: String) -> void:
	_content.add_child(UI.wrap_label(text, 15, UI.MUTED))


func _row(title: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := UI.label(title, 19, UI.TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(l)
	_content.add_child(h)
	return h


func _choice(title: String, options: Array, selected: int, on_pick: Callable) -> void:
	var h := _row(title)
	var btns: Array = []
	for i in options.size():
		var b := UI.button(options[i], 15, UI.PANEL_2, 44)
		b.toggle_mode = true
		b.button_pressed = i == selected
		b.custom_minimum_size.x = 64 if options.size() > 3 else 84
		var idx := i
		b.pressed.connect(func():
			for o in btns:
				o.button_pressed = o == b
			on_pick.call(idx))
		btns.append(b)
		h.add_child(b)


func _toggle(title: String, value: bool, on_set: Callable) -> void:
	var h := _row(title)
	var b := UI.button("Вкл" if value else "Выкл", 16, UI.PANEL_2, 44)
	b.toggle_mode = true
	b.button_pressed = value
	b.custom_minimum_size.x = 100
	b.toggled.connect(func(on: bool):
		b.text = "Вкл" if on else "Выкл"
		on_set.call(on))
	h.add_child(b)


func _slider(title: String, value: float, on_set: Callable) -> void:
	var h := _row(title)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.custom_minimum_size = Vector2(220, 40)
	s.value_changed.connect(func(v: float): on_set.call(v))
	h.add_child(s)
