extends Control
## Плашка профиля: аватар, номер уровня и полоса опыта (картинки из assets/ui).

const BG := preload("res://assets/ui/level_bg.png")
const FILL := preload("res://assets/ui/level_fill.png")
const AVATAR := preload("res://assets/ui/avatar.png")
const FILL_RECT := Rect2(414, 144, 392, 75)   # где полоса лежит на фоне (в пикселях фона)

var progress: float = 0.0
var level: int = 1
var _shown: float = 0.0
var _last_level: int = -1
var _pulse: float = 0.0
var _time: float = 0.0
var _drawn_key: String = ""

static var _shine: ImageTexture


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _process(delta: float) -> void:
	_time += delta
	if _last_level != -1 and level != _last_level:
		_pulse = 1.0
		_shown = 0.0
	_last_level = level
	_pulse = maxf(0.0, _pulse - delta * 1.6)
	_shown = lerpf(_shown, progress, 1.0 - exp(-delta * 6.0))
	if progress < _shown - 0.5:
		_shown = progress
	# перерисовка только когда картинка правда меняется (полоса едет, пульс, блик, цифры)
	var sweep := _sweep()
	var key := "%d|%d|%.3f|%.3f|%.3f" % [level, int(progress * 100.0), _shown, _pulse, sweep if sweep > 0.0 and sweep < _shown else -1.0]
	if key != _drawn_key:
		_drawn_key = key
		queue_redraw()


func _sweep() -> float:
	return fmod(_time * 0.35, 1.4) - 0.2


## Косой блик (параллелограмм) — текстурой, чтобы не строить многоугольник каждый кадр.
static func _shine_tex() -> ImageTexture:
	if _shine == null:
		var w := 40
		var h := 64
		var img := Image.create(w, h, false, Image.FORMAT_LA8)
		for y in h:
			var v := float(y) / (h - 1)
			var left := 0.5 * (1.0 - v) * w
			for x in w:
				var a := clampf(minf(x + 0.5 - left, left + w * 0.5 - (x + 0.5)) + 0.5, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, a))
		_shine = ImageTexture.create_from_image(img)
	return _shine


func _draw() -> void:
	var tex_size := BG.get_size()
	var k := minf(size.x / tex_size.x, size.y / tex_size.y)
	var origin := Vector2.ZERO
	draw_texture_rect(BG, Rect2(origin, tex_size * k), false)
	# аватар игрока внутри кольца
	var ac := origin + Vector2(152, 160) * k
	var ar := 106.0 * k
	draw_texture_rect(AVATAR, Rect2(ac - Vector2(ar, ar), Vector2(ar, ar) * 2.0), false)
	var p := clampf(_shown, 0.0, 1.0)
	if p > 0.0:
		var fr := Rect2(origin + FILL_RECT.position * k, FILL_RECT.size * k)
		var fs := FILL.get_size()
		draw_texture_rect_region(FILL, Rect2(fr.position, Vector2(fr.size.x * p, fr.size.y)), Rect2(0, 0, fs.x * p, fs.y))
		# блик пробегает по заполненной части раз в несколько секунд
		var sweep := _sweep()
		if sweep > 0.0 and sweep < p:
			var sx := fr.position.x + fr.size.x * sweep
			draw_texture_rect(_shine_tex(), Rect2(sx - 6, fr.position.y + 4, 20, fr.size.y - 8), false, Color(1, 1, 1, 0.35))
	# номер уровня на аватаре
	var font := ThemeDB.fallback_font
	var c := origin + Vector2(152, 286) * k
	var r := 44.0 * k * (1.0 + 0.35 * sin(_pulse * PI) * _pulse)
	if _pulse > 0.0:
		UI.draw_disc(self, c, r * (1.0 + (1.0 - _pulse) * 1.2), Color(1.0, 0.8, 0.2, 0.5 * _pulse))
	UI.draw_disc(self, c, r + 3.0, Color("1b1d22"))
	UI.draw_disc(self, c, r, Color("ffc21a"))
	UI.draw_disc(self, c, r - 4.0, Color("23262e"))
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
