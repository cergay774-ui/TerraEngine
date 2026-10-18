extends Control
## Плашка профиля: аватар, номер уровня и полоса опыта (картинки из assets/ui).

const BG := preload("res://assets/ui/level_bg.png")
const FILL := preload("res://assets/ui/level_fill.png")
const FILL_RECT := Rect2(414, 144, 392, 75)   # где полоса лежит на фоне (в пикселях фона)

var progress: float = 0.0
var level: int = 1
var _shown: float = 0.0


func _process(delta: float) -> void:
	_shown = lerpf(_shown, progress, 1.0 - exp(-delta * 6.0))
	if progress < _shown - 0.5:
		_shown = progress
	queue_redraw()


func _draw() -> void:
	var tex_size := BG.get_size()
	var k := minf(size.x / tex_size.x, size.y / tex_size.y)
	var origin := Vector2.ZERO
	draw_texture_rect(BG, Rect2(origin, tex_size * k), false)
	var p := clampf(_shown, 0.0, 1.0)
	if p > 0.0:
		var fr := Rect2(origin + FILL_RECT.position * k, FILL_RECT.size * k)
		var fs := FILL.get_size()
		draw_texture_rect_region(FILL, Rect2(fr.position, Vector2(fr.size.x * p, fr.size.y)), Rect2(0, 0, fs.x * p, fs.y))
	# номер уровня на аватаре
	var font := ThemeDB.fallback_font
	var c := origin + Vector2(152, 286) * k
	var r := 44.0 * k
	draw_circle(c, r + 3.0, Color("1b1d22"))
	draw_circle(c, r, Color("ffc21a"))
	draw_circle(c, r - 4.0, Color("23262e"))
	var txt := str(level)
	var fsz := int(40.0 * k) if txt.length() < 3 else int(30.0 * k)
	var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, fsz).x
	draw_string_outline(font, c + Vector2(-w * 0.5, fsz * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, 4, Color.BLACK)
	draw_string(font, c + Vector2(-w * 0.5, fsz * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, Color.WHITE)
	# процент внутри полосы
	var pct := "%d%%" % int(progress * 100.0)
	var ps := int(30.0 * k)
	var fr2 := Rect2(origin + FILL_RECT.position * k, FILL_RECT.size * k)
	var pw := font.get_string_size(pct, HORIZONTAL_ALIGNMENT_CENTER, -1, ps).x
	var pp := fr2.get_center() + Vector2(-pw * 0.5, ps * 0.36)
	draw_string_outline(font, pp, pct, HORIZONTAL_ALIGNMENT_LEFT, -1, ps, 4, Color(0, 0, 0, 0.8))
	draw_string(font, pp, pct, HORIZONTAL_ALIGNMENT_LEFT, -1, ps, Color.WHITE)
