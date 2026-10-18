class_name GameIcon
extends Control
## Иконка валюты или кнопки. Если в res://assets/icons/<kind>.png есть картинка — рисуется она,
## иначе простая векторная заглушка.

var kind: String = "cash"
var tint: Color = Color.WHITE
var _tex: Texture2D = null


static func make(icon_kind: String, px: int = 28, color: Color = Color.WHITE) -> GameIcon:
	var i := GameIcon.new()
	i.kind = icon_kind
	i.tint = color
	i.custom_minimum_size = Vector2(px, px)
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return i


func _ready() -> void:
	var path := "res://assets/icons/%s.png" % kind
	if ResourceLoader.exists(path):
		_tex = load(path)


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size * 0.5
	if _tex != null:
		draw_texture_rect(_tex, Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)), false)
		return
	var col: Color = tint
	if D.CURRENCIES.has(kind):
		col = D.CURRENCIES[kind].color
	var r := s * 0.42
	if kind.begins_with("part_"):
		# заглушка детали: шестерёнка с поршнем, пока нет своей иконки
		draw_circle(c, r, Color("1b1d22"))
		draw_arc(c, r, 0, TAU, 32, Color("ffc21a"), 2.5)
		for k in 8:
			var a := TAU * k / 8.0
			draw_line(c + Vector2(cos(a), sin(a)) * r * 0.55, c + Vector2(cos(a), sin(a)) * r * 0.82, Color("8d939b"), r * 0.18)
		draw_circle(c, r * 0.55, Color("8d939b"))
		draw_rect(Rect2(c + Vector2(-r * 0.28, -r * 0.42), Vector2(r * 0.56, r * 0.5)), Color("d4d9df"))
		draw_line(c + Vector2(0, 0.05 * r), c + Vector2(r * 0.15, r * 0.42), Color("d4d9df"), r * 0.14)
		return
	match kind:
		"cash":
			draw_circle(c, r, col.darkened(0.3))
			draw_circle(c, r * 0.8, col)
			draw_rect(Rect2(c + Vector2(-r * 0.12, -r * 0.6), Vector2(r * 0.24, r * 1.2)), col.darkened(0.45))
		"gold":
			var pts := PackedVector2Array([c + Vector2(-r, r * 0.5), c + Vector2(r, r * 0.5),
				c + Vector2(r * 0.6, -r * 0.4), c + Vector2(-r * 0.6, -r * 0.4)])
			draw_colored_polygon(pts, col)
			draw_polyline(pts + PackedVector2Array([pts[0]]), col.darkened(0.4), 1.5)
		"diamond":
			var d := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.8, -r * 0.2),
				c + Vector2(0, r), c + Vector2(-r * 0.8, -r * 0.2)])
			draw_colored_polygon(d, col)
			draw_line(c + Vector2(-r * 0.8, -r * 0.2), c + Vector2(r * 0.8, -r * 0.2), col.lightened(0.5), 1.5)
		"emerald":
			var h := PackedVector2Array()
			for k in 6:
				var a := TAU * k / 6.0 + PI / 6.0
				h.append(c + Vector2(cos(a), sin(a)) * r)
			draw_colored_polygon(h, col)
			draw_circle(c, r * 0.4, col.lightened(0.3))
		"sapphire":
			draw_circle(c, r, col)
			draw_arc(c, r * 0.6, 0, TAU, 16, col.lightened(0.5), 1.5)
		"quantum":
			for k in 3:
				draw_arc(c, r, 0, TAU, 24, col, 1.5)
				var pts2 := PackedVector2Array()
				for i in 25:
					var a := TAU * i / 24.0
					pts2.append(c + Vector2(cos(a) * r, sin(a) * r * 0.35).rotated(PI * k / 3.0))
				draw_polyline(pts2, col, 1.5)
			draw_circle(c, r * 0.22, col)
		"core":
			var st := PackedVector2Array()
			for k in 10:
				var a := TAU * k / 10.0 - PI * 0.5
				st.append(c + Vector2(cos(a), sin(a)) * (r if k % 2 == 0 else r * 0.45))
			draw_colored_polygon(st, col)
		"settings":
			draw_arc(c, r * 0.75, 0, TAU, 24, col, r * 0.3)
			for k in 8:
				var a := TAU * k / 8.0
				draw_line(c + Vector2(cos(a), sin(a)) * r * 0.75, c + Vector2(cos(a), sin(a)) * r * 1.1, col, r * 0.25)
		"upgrades":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.8, 0),
				c + Vector2(r * 0.3, 0), c + Vector2(r * 0.3, r), c + Vector2(-r * 0.3, r),
				c + Vector2(-r * 0.3, 0), c + Vector2(-r * 0.8, 0)]), col)
		"parts":
			draw_rect(Rect2(c + Vector2(-r * 0.55, -r), Vector2(r * 1.1, r * 0.9)), col)
			draw_line(c + Vector2(0, -r * 0.1), c + Vector2(r * 0.3, r * 0.6), col, r * 0.3)
			draw_circle(c + Vector2(0, r * 0.6), r * 0.4, col.darkened(0.3))
		"shop":
			draw_rect(Rect2(c + Vector2(-r, -r * 0.4), Vector2(r * 2.0, r * 1.3)), col.darkened(0.2))
			draw_rect(Rect2(c + Vector2(-r * 1.1, -r * 0.75), Vector2(r * 2.2, r * 0.4)), col)
			draw_rect(Rect2(c + Vector2(-r * 0.15, -r * 0.75), Vector2(r * 0.3, r * 1.65)), UI.ACCENT)
		"rebirth":
			draw_arc(c, r * 0.8, 0.3, PI - 0.2, 16, col, r * 0.28)
			draw_arc(c, r * 0.8, PI + 0.3, TAU - 0.2, 16, col, r * 0.28)
			draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.8, -r * 0.55), c + Vector2(r * 1.15, 0.1 * r), c + Vector2(r * 0.45, 0.1 * r)]), col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.8, r * 0.55), c + Vector2(-r * 1.15, -0.1 * r), c + Vector2(-r * 0.45, -0.1 * r)]), col)
		"xray":
			draw_arc(c, r * 0.9, 0, TAU, 24, col, 2.0)
			draw_circle(c, r * 0.4, col)
		_:
			draw_circle(c, r, col)
