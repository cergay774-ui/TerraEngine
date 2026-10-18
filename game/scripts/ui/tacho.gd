extends Control
## Прогресс-бар в виде тахометра: стрелка ползёт от 0 до красной зоны.

var value: float = 0.0


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var c := Vector2(size.x * 0.5, size.y * 0.78)
	var r := minf(size.x * 0.5, size.y * 0.75) - 8.0
	var a0 := PI * 0.85
	var a1 := PI * 2.15
	draw_circle(c, r + 6.0, Color("101114"))
	draw_arc(c, r, a0, a1, 64, Color("2a2c31"), 10.0)
	var red0 := lerpf(a0, a1, 0.8)
	draw_arc(c, r, red0, a1, 24, Color("d03030"), 10.0)
	for i in 9:
		var t := i / 8.0
		var a := lerpf(a0, a1, t)
		var dir := Vector2(cos(a), sin(a))
		draw_line(c + dir * (r - 22.0), c + dir * (r - 6.0), Color("d8d8d8") if t < 0.8 else Color("ff5050"), 3.0)
		draw_string(ThemeDB.fallback_font, c + dir * (r - 42.0) + Vector2(-7, 8), str(i), HORIZONTAL_ALIGNMENT_CENTER, -1, 20, Color("b8b8b8"))
		if i < 8:
			for k in 4:
				var a2 := lerpf(a0, a1, (i + (k + 1) / 5.0) / 8.0)
				var d2 := Vector2(cos(a2), sin(a2))
				draw_line(c + d2 * (r - 12.0), c + d2 * (r - 6.0), Color("6a6a6a"), 2.0)
	var na := lerpf(a0, a1, clampf(value, 0.0, 1.0)) + sin(Time.get_ticks_msec() * 0.03) * 0.01 * value
	var nd := Vector2(cos(na), sin(na))
	draw_line(c - nd * 14.0, c + nd * (r - 14.0), Color("ff7a1a"), 5.0)
	draw_circle(c, 12.0, Color("3a3d44"))
	draw_circle(c, 5.0, Color("ff7a1a"))
	draw_string(ThemeDB.fallback_font, c + Vector2(-60, 46), "x1000 об/мин", HORIZONTAL_ALIGNMENT_CENTER, 120, 16, Color("777"))
