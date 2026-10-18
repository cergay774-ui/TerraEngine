extends PanelContainer
## Настройки: графика, FPS, тряска, вибрация, громкость, формат чисел, язык,
## экспорт и импорт сохранения.

var main: Control
var _content: VBoxContainer
var _save_text: TextEdit
var _reset_armed: bool = false


func _ready() -> void:
	add_theme_stylebox_override("panel", UI.box(Color(0.09, 0.095, 0.115, 0.98), 22, Color(1, 1, 1, 0.1), 2, 16))
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
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 12)
	scroll.add_child(_content)


func refresh() -> void:
	UI.clear(_content)
	_reset_armed = false
	_choice("Качество графики", ["Низкое", "Среднее", "Высокое"], int(G.settings.quality), func(i): G.settings.quality = i)
	_choice("Частота кадров", ["30 FPS", "60 FPS"], 1 if int(G.settings.fps) >= 60 else 0, func(i):
		G.settings.fps = 60 if i == 1 else 30
		G.apply_settings())
	_toggle("Тряска экрана", G.settings.shake, func(on): G.settings.shake = on)
	_toggle("Вибрация", G.settings.vibration, func(on): G.settings.vibration = on)
	_slider("Громкость звуков", G.settings.sfx, func(val):
		G.settings.sfx = val
		G.apply_settings())
	_slider("Громкость музыки", G.settings.music, func(val):
		G.settings.music = val
		G.apply_settings())
	_choice("Формат чисел", ["1.5T", "1.5e12"], 1 if G.settings.sci else 0, func(i):
		G.settings.sci = i == 1
		G.changed.emit())
	_choice("Язык", ["Русский"], 0, func(_i): pass)

	_content.add_child(UI.hsep())
	_content.add_child(UI.label("Сохранение", 22, UI.TEXT))
	_content.add_child(UI.wrap_label("Игра сохраняется сама каждые 30 секунд и при сворачивании. Экспорт копирует сохранение в буфер обмена — его можно вставить на другом телефоне.", 15, UI.MUTED))
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
	_content.add_child(UI.label("Версия %s" % ProjectSettings.get_setting("application/config/version", "0.1"), 14, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER))


func _row(title: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := UI.label(title, 19, UI.TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	_content.add_child(h)
	return h


func _choice(title: String, options: Array, selected: int, on_pick: Callable) -> void:
	var h := _row(title)
	var btns: Array = []
	for i in options.size():
		var b := UI.button(options[i], 16, UI.PANEL_2, 46)
		b.toggle_mode = true
		b.button_pressed = i == selected
		b.custom_minimum_size.x = 92
		var idx := i
		b.pressed.connect(func():
			for o in btns:
				o.button_pressed = o == b
			on_pick.call(idx))
		btns.append(b)
		h.add_child(b)


func _toggle(title: String, value: bool, on_set: Callable) -> void:
	var h := _row(title)
	var b := UI.button("Вкл" if value else "Выкл", 16, UI.PANEL_2, 46)
	b.toggle_mode = true
	b.button_pressed = value
	b.custom_minimum_size.x = 110
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
