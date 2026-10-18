extends Control
## Вертикальная стамина справа: стеклянная капсула, заливка снизу вверх с градиентом,
## деления, значок-молния сверху и подпись снизу. Плавно догоняет значение,
## мигает красным при перегреве, синеет при бесконечной стамине, светится при зажатии.

const W := 44.0

var _shown: float = 1.0
var _time: float = 0.0
var _glow: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_time += delta
	var target := clampf(G.stamina / maxf(G.d_stamina_max, 0.01), 0.0, 1.0)
	if G.has_boost("stamina"):
		target = 1.0
	_shown = lerpf(_shown, target, 1.0 - exp(-delta * 10.0))
	_glow = lerpf(_glow, 1.0 if G.throttle else 0.0, 1.0 - exp(-delta * 6.0))
	queue_redraw()


func _capsule(rect: Rect2, r: float, segs: int = 10) -> PackedVector2Array:
	var pts := PackedVector2Array()
	r = minf(r, minf(rect.size.x, rect.size.y) * 0.5)
	var corners := [
		[rect.position + Vector2(rect.size.x - r, r), -PI * 0.5],
		[rect.position + Vector2(rect.size.x - r, rect.size.y - r), 0.0],
		[rect.position + Vector2(r, rect.size.y - r), PI * 0.5],
		[rect.position + Vector2(r, r), PI],
	]
	for c in corners:
		for i in segs + 1:
			var a: float = c[1] + PI * 0.5 * i / segs
			pts.append(c[0] + Vector2(cos(a), sin(a)) * r)
	return pts


func _draw() -> void:
	var boost := G.has_boost("stamina")
	var hot := G.is_exhausted
	var bar_top := 58.0
	var bar_bottom := size.y - 40.0
	var x0 := (size.x - W) * 0.5
	var bar := Rect2(x0, bar_top, W, bar_bottom - bar_top)

	# свечение при зажатии
	if _glow > 0.02:
		var gc := Color(1.0, 0.7, 0.2) if not boost else Color(0.35, 0.65, 1.0)
		for k in 4:
			var g := bar.grow(4.0 + k * 4.0)
			draw_colored_polygon(_capsule(g, g.size.x * 0.5), Color(gc.r, gc.g, gc.b, 0.05 * _glow * (0.7 + 0.3 * sin(_time * 8.0))))

	# стеклянная капсула
	draw_colored_polygon(_capsule(bar.grow(3.0), (W + 6.0) * 0.5), Color(0, 0, 0, 0.55))
	draw_colored_polygon(_capsule(bar, W * 0.5), Color(0.07, 0.075, 0.09, 0.92))

	# заливка снизу вверх
	var inner := bar.grow(-5.0)
	var fill_h := inner.size.y * _shown
	if fill_h > 2.0:
		var fr := Rect2(inner.position.x, inner.end.y - fill_h, inner.size.x, fill_h)
		var top_c: Color
		var bot_c: Color
		if boost:
			top_c = Color("9fd2ff")
			bot_c = Color("2f6fe0")
		elif hot:
			var blink := 0.6 + 0.4 * sin(_time * 10.0)
			top_c = Color(1.0, 0.45, 0.3) * blink
			bot_c = Color(0.75, 0.08, 0.05)
		elif _shown < 0.25:
			top_c = Color("ff9a4a")
			bot_c = Color("e0301e")
		else:
			top_c = Color("ffe27a")
			bot_c = Color("ff8a1a")
		var pts := _capsule(fr, inner.size.x * 0.5)
		var cols := PackedColorArray()
		for p in pts:
			var t := clampf((p.y - fr.position.y) / maxf(fr.size.y, 1.0), 0.0, 1.0)
			cols.append(top_c.lerp(bot_c, t))
		draw_polygon(pts, cols)
		# блик слева и бегущая полоска
		draw_line(Vector2(fr.position.x + 6, fr.position.y + 8), Vector2(fr.position.x + 6, fr.end.y - 8), Color(1, 1, 1, 0.25), 3.0)
		var band_y := fr.end.y - fmod(_time * (120.0 if not hot else 50.0), maxf(fr.size.y, 1.0))
		if band_y > fr.position.y + 6 and band_y < fr.end.y - 6:
			draw_line(Vector2(fr.position.x + 4, band_y), Vector2(fr.end.x - 4, band_y), Color(1, 1, 1, 0.18), 6.0)

	# деления
	for k in range(1, 4):
		var y := inner.end.y - inner.size.y * k / 4.0
		draw_line(Vector2(bar.position.x + 4, y), Vector2(bar.position.x + 13, y), Color(1, 1, 1, 0.3), 2.0)
		draw_line(Vector2(bar.end.x - 13, y), Vector2(bar.end.x - 4, y), Color(1, 1, 1, 0.3), 2.0)

	# рамка
	draw_polyline(_capsule(bar, W * 0.5) + PackedVector2Array([_capsule(bar, W * 0.5)[0]]), Color("ffc21a").darkened(0.25), 2.5, true)

	# значок сверху: молния в круге
	var ic := Vector2(size.x * 0.5, 26.0)
	var pulse := 1.0 + (0.12 * sin(_time * 12.0) if hot else 0.0)
	draw_circle(ic, 24.0 * pulse, Color(0, 0, 0, 0.6))
	draw_circle(ic, 21.0 * pulse, Color("ffc21a") if not hot else Color("ff4a3a"))
	draw_circle(ic, 17.0 * pulse, Color(0.1, 0.1, 0.12))
	var bolt := PackedVector2Array([ic + Vector2(3, -12), ic + Vector2(-7, 2), ic + Vector2(-1, 2), ic + Vector2(-4, 12), ic + Vector2(7, -3), ic + Vector2(1, -3)])
	draw_colored_polygon(bolt, Color("ffc21a") if not boost else Color("6fb6ff"))

	# подпись снизу
	var font := ThemeDB.fallback_font
	var txt: String
	if boost:
		txt = "∞"
	elif hot:
		txt = "ОСТЫВ"
	else:
		txt = "%.1fс" % G.stamina
	var fs := 18
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var tp := Vector2((size.x - tw) * 0.5, size.y - 12.0)
	draw_string_outline(font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.85))
	draw_string(font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("ff6a5a") if hot else Color.WHITE)
