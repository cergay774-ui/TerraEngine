extends Control
## Вертикальная стамина справа: стеклянная капсула, заливка снизу вверх с градиентом,
## деления, значок-молния сверху и подпись снизу. Плавно догоняет значение,
## мигает красным при перегреве, синеет при бесконечной стамине, светится при зажатии.
##
## Капсулу рисует шейдер на одном прямоугольнике: каждый кадр меняются только его
## параметры. Раньше она перерисовывалась многоугольниками каждый кадр — на телефоне
## это десятки созданных и удалённых буферов видеопамяти за кадр.

const W := 44.0
const PAD := 20.0          # запас вокруг капсулы под свечение
const BAR_TOP := 58.0
const BAR_BOTTOM := 40.0   # от низа

const SHADER := """
shader_type canvas_item;
render_mode blend_premul_alpha;

uniform vec2 rect_size = vec2(84.0, 400.0);
uniform float pad = 20.0;
uniform float fill = 1.0;
uniform vec4 top_col : source_color = vec4(1.0, 0.886, 0.478, 1.0);
uniform vec4 bot_col : source_color = vec4(1.0, 0.541, 0.102, 1.0);
uniform vec4 glow_col : source_color = vec4(1.0, 0.7, 0.2, 1.0);
uniform vec4 border_col : source_color = vec4(0.75, 0.57, 0.02, 1.0);
uniform float glow = 0.0;
uniform float blink = 0.0;
uniform float band_speed = 120.0;

float sd_rbox(vec2 p, vec2 hs, float r) {
	vec2 q = abs(p) - hs + vec2(r);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

vec4 over(vec4 dst, vec3 rgb, float a) {
	return vec4(rgb * a + dst.rgb * (1.0 - a), a + dst.a * (1.0 - a));
}

void fragment() {
	vec2 px = UV * rect_size;
	vec2 bmin = vec2(pad);
	vec2 bmax = rect_size - vec2(pad);
	vec2 hs = (bmax - bmin) * 0.5;
	float w = bmax.x - bmin.x;
	float d = sd_rbox(px - (bmin + bmax) * 0.5, hs, w * 0.5);
	vec4 col = vec4(0.0);

	// свечение при зажатии
	if (glow > 0.01 && d > 0.0) {
		float g = 1.0 - smoothstep(0.0, pad, d);
		col = over(col, glow_col.rgb, g * g * 0.35 * glow * (0.7 + 0.3 * sin(TIME * 8.0)));
	}
	// тень и стеклянный корпус
	col = over(col, vec3(0.0), clamp(0.5 - (d - 3.0), 0.0, 1.0) * 0.55);
	col = over(col, vec3(0.07, 0.075, 0.09), clamp(0.5 - d, 0.0, 1.0) * 0.92);

	// заливка снизу вверх
	vec2 imin = bmin + vec2(5.0);
	vec2 imax = bmax - vec2(5.0);
	float ih = imax.y - imin.y;
	float fh = ih * clamp(fill, 0.0, 1.0);
	if (fh > 2.0) {
		vec2 fmin = vec2(imin.x, imax.y - fh);
		vec2 fhs = (imax - fmin) * 0.5;
		float df = sd_rbox(px - (fmin + imax) * 0.5, fhs, min((imax.x - imin.x) * 0.5, fhs.y));
		float t = clamp((px.y - fmin.y) / max(fh, 1.0), 0.0, 1.0);
		float bl = mix(1.0, 0.6 + 0.4 * sin(TIME * 10.0), blink);
		vec3 fc = mix(top_col.rgb * bl, bot_col.rgb, t);
		// блик слева
		float hl = (1.0 - smoothstep(1.0, 2.0, abs(px.x - (fmin.x + 6.0))))
			* step(fmin.y + 8.0, px.y) * step(px.y, imax.y - 8.0);
		fc = mix(fc, vec3(1.0), 0.25 * hl);
		// бегущая полоска
		float band_y = imax.y - mod(TIME * band_speed, max(fh, 1.0));
		float band = (1.0 - smoothstep(2.0, 3.5, abs(px.y - band_y)))
			* step(fmin.y + 6.0, band_y) * step(band_y, imax.y - 6.0)
			* step(fmin.x + 4.0, px.x) * step(px.x, imax.x - 4.0);
		fc = mix(fc, vec3(1.0), 0.18 * band);
		col = over(col, fc, clamp(0.5 - df, 0.0, 1.0));
	}

	// деления на 1/4, 1/2, 3/4
	for (int k = 1; k <= 3; k++) {
		float y = imax.y - ih * float(k) / 4.0;
		float on_y = 1.0 - smoothstep(0.5, 1.5, abs(px.y - y));
		float on_x = step(bmin.x + 4.0, px.x) * step(px.x, bmin.x + 13.0) + step(bmax.x - 13.0, px.x) * step(px.x, bmax.x - 4.0);
		col = over(col, vec3(1.0), 0.3 * on_y * on_x);
	}

	// рамка
	col = over(col, border_col.rgb, clamp(1.75 - abs(d), 0.0, 1.0));
	COLOR = col;
}
"""

static var _shader: Shader

var _shown: float = 1.0
var _glow: float = 0.0
var _bar: ColorRect
var _mat: ShaderMaterial
var _icon: Control
var _caption: Label
var _state: int = -1        # 0 обычная, 1 мало, 2 перегрев, 3 бесконечная
var _sent_fill: float = -1.0
var _sent_glow: float = -1.0
var _time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	_bar = ColorRect.new()
	_bar.material = _mat
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar)

	_icon = Control.new()
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.size = Vector2(52, 52)
	_icon.pivot_offset = Vector2(26, 26)
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_icon.draw.connect(_draw_icon)
	add_child(_icon)

	_caption = Label.new()
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_font_size_override("font_size", 18)
	_caption.add_theme_constant_override("outline_size", 5)
	_caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_caption)

	resized.connect(_layout)
	_layout()


func _layout() -> void:
	var bar_h := maxf(40.0, size.y - BAR_TOP - BAR_BOTTOM)
	_bar.position = Vector2((size.x - W) * 0.5 - PAD, BAR_TOP - PAD)
	_bar.size = Vector2(W + PAD * 2.0, bar_h + PAD * 2.0)
	_mat.set_shader_parameter("rect_size", _bar.size)
	_mat.set_shader_parameter("pad", PAD)
	_icon.position = Vector2(size.x * 0.5 - 26.0, 0.0)
	_caption.position = Vector2(-20.0, size.y - 34.0)
	_caption.size = Vector2(size.x + 40.0, 30.0)


func _process(delta: float) -> void:
	_time += delta
	var boost := G.has_boost("stamina")
	var hot := G.is_exhausted
	var target := clampf(G.stamina / maxf(G.d_stamina_max, 0.01), 0.0, 1.0)
	if boost:
		target = 1.0
	_shown = lerpf(_shown, target, 1.0 - exp(-delta * 10.0))
	_glow = lerpf(_glow, 1.0 if G.throttle else 0.0, 1.0 - exp(-delta * 6.0))

	# параметры шейдера отправляются, только когда что-то заметно изменилось
	var st := 3 if boost else (2 if hot else (1 if _shown < 0.25 else 0))
	if st != _state:
		_state = st
		_apply_state(st)
	if absf(_shown - _sent_fill) > 0.002:
		_sent_fill = _shown
		_mat.set_shader_parameter("fill", _shown)
	var g := _glow if _glow > 0.02 else 0.0
	if absf(g - _sent_glow) > 0.02 or (g == 0.0 and _sent_glow != 0.0):
		_sent_glow = g
		_mat.set_shader_parameter("glow", g)

	# значок пульсирует при перегреве (масштабом — без перерисовки)
	var pulse := 1.0 + (0.12 * sin(_time * 12.0) if hot else 0.0)
	_icon.scale = Vector2(pulse, pulse)

	var txt: String
	if boost:
		txt = "∞"
	elif hot:
		txt = "%d%%" % int(G.stamina / maxf(G.d_stamina_max, 0.01) * 100.0)
	else:
		txt = "%.1fс" % G.stamina
	_caption.text = txt


func _apply_state(st: int) -> void:
	var top: Color
	var bot: Color
	match st:
		3:
			top = Color("9fd2ff")
			bot = Color("2f6fe0")
		2:
			top = Color(1.0, 0.45, 0.3)
			bot = Color(0.75, 0.08, 0.05)
		1:
			top = Color("ff9a4a")
			bot = Color("e0301e")
		_:
			top = Color("ffe27a")
			bot = Color("ff8a1a")
	_mat.set_shader_parameter("top_col", top)
	_mat.set_shader_parameter("bot_col", bot)
	_mat.set_shader_parameter("blink", 1.0 if st == 2 else 0.0)
	_mat.set_shader_parameter("band_speed", 50.0 if st == 2 else 120.0)
	_mat.set_shader_parameter("glow_col", Color(0.35, 0.65, 1.0) if st == 3 else Color(1.0, 0.7, 0.2))
	_mat.set_shader_parameter("border_col", Color("ffc21a").darkened(0.25))
	_caption.add_theme_color_override("font_color", Color("ff6a5a") if st == 2 else Color.WHITE)
	_icon.queue_redraw()


func _draw_icon() -> void:
	# молния в круге; перерисовывается только при смене состояния
	var hot := _state == 2
	var boost := _state == 3
	var ic := Vector2(26, 26)
	UI.draw_disc(_icon, ic, 24.0, Color(0, 0, 0, 0.6))
	UI.draw_disc(_icon, ic, 21.0, Color("ffc21a") if not hot else Color("ff4a3a"))
	UI.draw_disc(_icon, ic, 17.0, Color(0.1, 0.1, 0.12))
	var bolt := PackedVector2Array([ic + Vector2(3, -12), ic + Vector2(-7, 2), ic + Vector2(-1, 2), ic + Vector2(-4, 12), ic + Vector2(7, -3), ic + Vector2(1, -3)])
	_icon.draw_colored_polygon(bolt, Color("ffc21a") if not boost else Color("6fb6ff"))
