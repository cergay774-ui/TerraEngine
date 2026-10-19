class_name UI
extends RefCounted
## Общие стили и конструкторы элементов интерфейса.

const ACCENT := Color("ffb81c")
const BG := Color("121317")
const PANEL := Color("1b1f29")
const PANEL_2 := Color("272c39")
const TEXT := Color("ecebe6")
const MUTED := Color("8d9099")
const GOOD := Color("8fe36b")
const BAD := Color("ff5a5a")


static func box(color: Color, radius: int = 14, border: Color = Color(0, 0, 0, 0), border_w: int = 0, pad: int = 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	if border_w > 0:
		s.border_color = border
		s.set_border_width_all(border_w)
	# объём: тень снизу, как у иконок в стиле игры
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 2
	s.shadow_offset = Vector2(0, 5)
	s.anti_aliasing = true
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.7
	s.content_margin_bottom = pad * 0.7
	return s


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 24
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_pressed_color", "Button", TEXT)
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", Color(0.6, 0.6, 0.62))
	t.set_stylebox("normal", "Button", box(PANEL_2, 12, Color(1, 1, 1, 0.08), 2))
	t.set_stylebox("hover", "Button", box(PANEL_2.lightened(0.06), 12, Color(1, 1, 1, 0.12), 2))
	var pressed := box(PANEL_2.darkened(0.2), 12, ACCENT, 2)
	pressed.shadow_offset = Vector2(0, 1)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", box(PANEL_2.darkened(0.25), 12, Color(1, 1, 1, 0.04), 2))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("panel", "PanelContainer", box(PANEL, 18, Color(1, 1, 1, 0.07), 2, 16))
	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 10)
	var grab := StyleBoxFlat.new()
	grab.bg_color = ACCENT
	grab.set_corner_radius_all(6)
	t.set_stylebox("slider", "HSlider", box(PANEL_2, 6, Color(0, 0, 0, 0), 0, 4))
	t.set_stylebox("grabber_area", "HSlider", grab)
	t.set_stylebox("grabber_area_highlight", "HSlider", grab)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.12)
	sb.set_corner_radius_all(4)
	t.set_stylebox("scroll", "VScrollBar", sb)
	t.set_stylebox("scroll", "HScrollBar", sb)
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(1, 1, 1, 0.35)
	grabber.set_corner_radius_all(4)
	t.set_stylebox("grabber", "VScrollBar", grabber)
	t.set_stylebox("grabber", "HScrollBar", grabber)
	t.set_stylebox("normal", "LineEdit", box(Color("0e0f12"), 10, Color(1, 1, 1, 0.1), 2))
	t.set_stylebox("normal", "TextEdit", box(Color("0e0f12"), 10, Color(1, 1, 1, 0.1), 2))
	t.set_font_size("font_size", "TextEdit", 16)
	return t


static func label(text: String, size: int = 24, color: Color = TEXT, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l


static func wrap_label(text: String, size: int = 20, color: Color = MUTED) -> Label:
	var l := label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 10
	return l


static func button(text: String, size: int = 24, color: Color = PANEL_2, min_h: int = 64) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size.y = min_h
	if color != PANEL_2:
		b.add_theme_stylebox_override("normal", box(color, 12, color.lightened(0.3), 3))
		b.add_theme_stylebox_override("hover", box(color.lightened(0.08), 12, color.lightened(0.35), 3))
		var pr := box(color.darkened(0.2), 12, Color.WHITE, 3)
		pr.shadow_offset = Vector2(0, 1)
		b.add_theme_stylebox_override("pressed", pr)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): Sfx.play("click"))
	return b


static func accent_button(text: String, size: int = 24, min_h: int = 64) -> Button:
	var b := button(text, size, ACCENT.darkened(0.1), min_h)
	b.add_theme_color_override("font_color", Color("2a1c00"))
	b.add_theme_color_override("font_hover_color", Color("2a1c00"))
	b.add_theme_color_override("font_pressed_color", Color("2a1c00"))
	return b


static func card(color: Color = PANEL_2, border: Color = Color(1, 1, 1, 0.06), pad: int = 12) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(color, 14, border, 2, pad))
	return p


static func hsep() -> Control:
	var c := ColorRect.new()
	c.color = Color(1, 1, 1, 0.07)
	c.custom_minimum_size.y = 2
	return c


static func bar(fill: Color, height: int = 14) -> ProgressBar:
	var p := ProgressBar.new()
	p.show_percentage = false
	p.custom_minimum_size.y = height
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	bg.set_corner_radius_all(height / 2)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.set_corner_radius_all(height / 2)
	p.add_theme_stylebox_override("background", bg)
	p.add_theme_stylebox_override("fill", fg)
	p.max_value = 1.0
	p.step = 0.0
	return p


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


static func time_text(sec: float) -> String:
	var s := int(sec)
	if s >= 3600:
		return "%d ч %02d мин" % [s / 3600, (s % 3600) / 60]
	if s >= 60:
		return "%d:%02d" % [s / 60, s % 60]
	return "%d с" % s


static func price_text(cur_id: String, amount: Big) -> String:
	var name: String = D.CURRENCIES[cur_id].name
	if cur_id == "cash":
		return "$" + G.fmt(amount)
	return "%s %s" % [G.fmt(amount), name.to_lower()]


# ---------------------------------------------------------------------
# Круги без многоугольников. draw_circle/draw_arc/draw_polygon на каждой перерисовке
# создают и удаляют буферы видеопамяти; если элемент обновляется каждый кадр, на
# телефоне это десятки буферов в кадр. Кружок из готовой текстуры рисуется как
# обычный прямоугольник и не создаёт ничего.
# ---------------------------------------------------------------------

static var _disc: ImageTexture


static func disc_tex() -> ImageTexture:
	if _disc == null:
		var n := 128
		var img := Image.create(n, n, false, Image.FORMAT_LA8)
		var c := (n - 1) * 0.5
		var r := n * 0.5 - 1.0
		for y in n:
			for x in n:
				var d := Vector2(x - c, y - c).length()
				img.set_pixel(x, y, Color(1, 1, 1, clampf(r - d + 0.5, 0.0, 1.0)))
		img.generate_mipmaps()
		_disc = ImageTexture.create_from_image(img)
	return _disc


static func draw_disc(ci: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	ci.draw_texture_rect(disc_tex(), Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false, color)
