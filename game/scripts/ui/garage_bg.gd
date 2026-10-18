extends Control
## Фон: тёмный гараж, лампа сверху, лёгкая пыль в луче.

var lamp_y: float = 0.0
var dust_count: int = 40
var offset: Vector2 = Vector2.ZERO
var _dust: Array = []
var _time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in dust_count:
		_dust.append({"p": Vector2(randf(), randf()), "v": Vector2(randf_range(-0.01, 0.01), randf_range(-0.012, 0.004)),
			"s": randf_range(1.0, 2.6), "ph": randf() * TAU})


func _process(delta: float) -> void:
	_time += delta
	for d in _dust:
		d.p += d.v * delta
		d.p.x += sin(_time * 0.7 + d.ph) * 0.0006
		if d.p.y < 0.0:
			d.p.y = 1.0
		if d.p.x < 0.0 or d.p.x > 1.0:
			d.p.x = fposmod(d.p.x, 1.0)
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var o := offset * 0.3
	draw_rect(Rect2(Vector2.ZERO, size), Color("0c0d10"))
	# стена из панелей
	var panel_w := w / 5.0
	for i in 6:
		var x := i * panel_w + o.x
		draw_rect(Rect2(x, 0, panel_w - 3.0, h * 0.72), Color("14161a"))
		draw_line(Vector2(x + panel_w - 3.0, 0), Vector2(x + panel_w - 3.0, h * 0.72), Color("0a0b0d"), 3.0)
	# полка с инструментом
	draw_rect(Rect2(w * 0.06 + o.x, h * 0.2, w * 0.25, 8), Color("2a2116"))
	for k in 5:
		draw_rect(Rect2(w * 0.08 + o.x + k * w * 0.045, h * 0.2 - 30 - (k % 2) * 12, w * 0.018, 30 + (k % 2) * 12), Color("23262c"))
	draw_rect(Rect2(w * 0.7 + o.x, h * 0.16, w * 0.22, h * 0.12), Color("191b20"))
	for k in 4:
		draw_circle(Vector2(w * 0.73 + o.x + k * w * 0.05, h * 0.19), 6, Color("2c3038"))
	# пол
	draw_rect(Rect2(0, h * 0.72, w, h * 0.28), Color("101114"))
	draw_line(Vector2(0, h * 0.72), Vector2(w, h * 0.72), Color("1d1f24"), 4.0)
	for k in 8:
		var y := h * 0.72 + pow(k / 8.0, 1.6) * h * 0.28
		draw_line(Vector2(0, y), Vector2(w, y), Color(1, 1, 1, 0.015), 2.0)
	# пятно масла
	draw_circle(Vector2(w * 0.32, h * 0.86), 40, Color(0, 0, 0, 0.25))
	# луч лампы
	var lx := w * 0.5 + o.x * 0.5
	var ly := lamp_y + 8.0
	var flick := 0.95 + 0.05 * sin(_time * 23.0) * sin(_time * 7.0)
	for k in 7:
		var spread := w * (0.18 + k * 0.07)
		var poly := PackedVector2Array([Vector2(lx - 30, ly), Vector2(lx + 30, ly),
			Vector2(lx + spread, h * 0.95), Vector2(lx - spread, h * 0.95)])
		draw_colored_polygon(poly, Color(1.0, 0.85, 0.55, 0.018 * flick))
	draw_circle(Vector2(lx, h * 0.93), w * 0.38, Color(1.0, 0.85, 0.55, 0.025 * flick))
	# пыль
	for d in _dust:
		var p := Vector2(d.p.x * w, d.p.y * h) + o
		var in_beam := absf(p.x - lx) < (p.y - ly) * 0.55 + 30.0
		var a := (0.35 if in_beam else 0.06) * (0.6 + 0.4 * sin(_time * 2.0 + d.ph))
		draw_circle(p, d.s, Color(1.0, 0.9, 0.7, a))
	# лампа
	draw_line(Vector2(lx, 0), Vector2(lx, ly - 18), Color("2a2c31"), 3.0)
	draw_colored_polygon(PackedVector2Array([Vector2(lx - 34, ly), Vector2(lx + 34, ly), Vector2(lx + 14, ly - 20), Vector2(lx - 14, ly - 20)]), Color("3b3f47"))
	draw_circle(Vector2(lx, ly + 2), 9, Color(1.0, 0.92, 0.7, flick))
	draw_circle(Vector2(lx, ly + 2), 20, Color(1.0, 0.85, 0.5, 0.15 * flick))
	# виньетка
	for k in 6:
		var m := k * 14.0
		draw_rect(Rect2(m, m, w - 2 * m, h - 2 * m), Color(0, 0, 0, 0.08), false, 14.0)
