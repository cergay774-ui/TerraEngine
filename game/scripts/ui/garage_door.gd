extends Control
## Переход «гаражные ворота»: ворота опускаются, в середине — смена экрана, ворота поднимаются.

signal closed

var _h: float = 1280.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_h = get_viewport_rect().size.y
	position.y = -_h


func play() -> void:
	Sfx.play("garage_door")
	G.vibrate(25)
	var tw := create_tween()
	tw.tween_property(self, "position:y", 0.0, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		G.vibrate(40)
		closed.emit())
	tw.tween_interval(0.18)
	tw.tween_property(self, "position:y", -_h, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(queue_free)


func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(Vector2.ZERO, size), Color("2a2d33"))
	var n := 16
	var sh := h / n
	for i in n:
		var y := i * sh
		draw_rect(Rect2(0, y, w, sh - 6.0), Color("3c4048"))
		draw_rect(Rect2(0, y, w, 3.0), Color("4a4f58"))
		draw_line(Vector2(0, y + sh - 6.0), Vector2(w, y + sh - 6.0), Color("17181c"), 6.0)
	# ручка и жёлто-чёрная полоса внизу
	draw_rect(Rect2(w * 0.42, h - 90, w * 0.16, 24), Color("17181c"))
	var stripe_h := 26.0
	for k in int(w / 40.0) + 2:
		var x := k * 40.0
		draw_colored_polygon(PackedVector2Array([Vector2(x, h - stripe_h), Vector2(x + 20, h - stripe_h), Vector2(x, h), Vector2(x - 20, h)]), Color("ffc21a"))
	draw_rect(Rect2(0, h - stripe_h, w, 2), Color(0, 0, 0, 0.5))
