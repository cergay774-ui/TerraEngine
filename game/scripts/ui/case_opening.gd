extends Control
## Открытие кейса: ящик падает и трясётся, сквозь щели пробивается свет; крышка слетает,
## вспышка и лучи цвета редкости, из ящика поднимается деталь, карточка награды с бликом.
## Всё собрано из узлов с шейдерами и частиц: в кадре меняются только трансформы и
## параметры шейдеров (никаких draw_* в кадре).

const UiFx := preload("res://scripts/ui/ui_fx.gd")
const OPEN_T := 1.0
const BW := 300.0     # ящик
const BH := 190.0
const LW := 336.0     # крышка
const LH := 58.0
const GOLD := Color(1.0, 0.74, 0.3)

const SH_CRATE := """
shader_type canvas_item;
// деревянный ящик (lid = 0) или крышка (lid = 1). glow — свет изнутри сквозь щели,
// open — ящик открыт (верхний край пылает). rect — размер прямоугольника в пикселях
uniform vec2 rect = vec2(300.0, 190.0);
uniform float lid = 0.0;
uniform vec4 leak : source_color = vec4(1.0, 0.8, 0.4, 1.0);
uniform float glow = 0.0;
uniform float open = 0.0;

float hash(float n) { return fract(sin(n * 12.9898) * 43758.5453); }
float sd_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}
vec3 wood(vec2 p, float id) {
	float h = hash(id + 1.0);
	vec3 base = mix(vec3(0.36, 0.21, 0.11), vec3(0.56, 0.35, 0.18), h);
	float g = sin(p.x * 0.07 + sin(p.y * 0.17 + id * 3.1) * 2.6 + sin(p.x * 0.012 + id * 5.0) * 3.0);
	float g2 = sin(p.x * 0.29 + p.y * 0.09 + id * 11.0);
	return base * (0.84 + 0.12 * g + 0.05 * g2);
}
vec3 brass(float xn, float yn) {
	vec3 b = mix(vec3(1.0, 0.82, 0.45), vec3(0.55, 0.36, 0.12), clamp(yn, 0.0, 1.0));
	return b * (0.75 + 0.35 * exp(-pow((xn + 0.35) / 0.25, 2.0)));
}
vec3 steel(float yn) {
	return mix(vec3(0.66, 0.68, 0.72), vec3(0.24, 0.25, 0.28), clamp(yn, 0.0, 1.0));
}
// заклёпка: x — маска, y — освещённость
vec2 rivet(vec2 p, vec2 c, float r) {
	vec2 d = p - c;
	float m = 1.0 - smoothstep(r - 0.8, r + 0.4, length(d));
	float l = 0.55 + 0.45 * clamp(dot(normalize(d + vec2(0.001)), vec2(-0.6, -0.8)), -1.0, 1.0) * smoothstep(0.0, r, length(d));
	return vec2(m, l);
}

void fragment() {
	vec2 px = UV * rect;
	vec2 c = px - rect * 0.5;
	vec2 hb = rect * 0.5;
	float d = sd_box(c, hb - 1.0, 6.0);
	float alpha = clamp(0.5 - d, 0.0, 1.0);
	vec3 col = vec3(0.0);
	vec3 em = vec3(0.0);
	float fl = 0.85 + 0.15 * sin(TIME * 23.0) * sin(TIME * 13.7);
	if (lid < 0.5) {
		float fw = 17.0;
		vec2 ib = hb - fw;
		float din = max(abs(c.x) - ib.x, abs(c.y) - ib.y);
		float seam = 0.0;
		if (din > 0.0) {
			// рамка: горизонтальные балки во всю ширину, стойки между ними
			bool rail = abs(c.y) > ib.y;
			col = rail ? wood(px + vec2(0.0, 7.0), 5.0 + step(0.0, c.y)) : wood(px.yx + vec2(31.0, 0.0), 3.0 + step(0.0, c.x));
			col *= 0.92;
			if (!rail) {
				col *= 0.55 + 0.45 * smoothstep(0.0, 1.6, abs(abs(c.y) - ib.y));
			}
			col *= 0.7 + 0.3 * smoothstep(0.0, 4.0, din);
			col += vec3(0.1, 0.07, 0.04) * (1.0 - smoothstep(0.0, 3.0, -d));
		} else {
			// три доски
			float iy = (c.y + ib.y) / (2.0 * ib.y);
			float id = floor(iy * 3.0);
			float fy = fract(iy * 3.0);
			float ph = 2.0 * ib.y / 3.0;
			col = wood(px + vec2(id * 53.0, id * 17.0), id + 10.0);
			float gap = min(fy, 1.0 - fy) * ph;
			seam = 1.0 - smoothstep(0.0, 2.2, gap);
			col *= mix(0.25, 1.0, smoothstep(0.0, 3.5, gap));
			float inner = min(ib.x - abs(c.x), ib.y - abs(c.y));
			col *= 0.55 + 0.45 * smoothstep(0.0, 10.0, inner);
			seam = max(seam, 1.0 - smoothstep(0.0, 2.0, inner));
			// диагональная распорка
			vec2 dv = normalize(vec2(2.0 * ib.x, -2.0 * ib.y));
			float dd = abs(c.x * dv.y - c.y * dv.x);
			if (dd < 12.0) {
				col = wood(vec2(dot(c, dv), dd * 0.3) + 300.0, 20.0) * 1.04;
				col *= 1.0 - 0.4 * smoothstep(8.0, 12.0, dd);
				seam = 0.0;
			} else {
				col *= 0.7 + 0.3 * smoothstep(12.0, 20.0, dd);
			}
		}
		// латунная полоса по центру
		float sx = abs(c.x);
		if (sx < 19.0) {
			col = brass(c.x / 19.0, UV.y * 0.8 + 0.1) * (0.6 + 0.4 * smoothstep(0.0, 2.0, 19.0 - sx));
			seam = 0.0;
			for (int i = 0; i < 4; i++) {
				float ry = -hb.y + 14.0 + float(i) * (rect.y - 28.0) / 3.0;
				vec2 rv = rivet(c, vec2(-10.0, ry), 3.0);
				vec2 rv2 = rivet(c, vec2(10.0, ry), 3.0);
				col = mix(col, vec3(0.9, 0.75, 0.45) * rv.y, rv.x);
				col = mix(col, vec3(0.9, 0.75, 0.45) * rv2.y, rv2.x);
			}
		} else {
			col *= 0.7 + 0.3 * smoothstep(19.0, 25.0, sx);
		}
		// замок
		vec2 lc = c - vec2(0.0, -hb.y + 30.0);
		float ld = sd_box(lc, vec2(20.0, 17.0), 5.0);
		if (ld < 1.0) {
			vec3 lk = brass(lc.x / 20.0, (lc.y + 17.0) / 34.0) * 1.1;
			lk *= 0.75 + 0.25 * smoothstep(0.0, 2.5, -ld);
			float kh = min(length(lc - vec2(0.0, -3.0)) - 4.5, sd_box(lc - vec2(0.0, 4.0), vec2(1.8, 6.0), 0.5));
			lk = mix(lk, vec3(0.05, 0.03, 0.02) + leak.rgb * glow * 1.4 * fl, 1.0 - smoothstep(-0.5, 0.5, kh));
			col = mix(col, lk, clamp(0.5 - ld, 0.0, 1.0));
		} else {
			col *= 0.6 + 0.4 * smoothstep(1.0, 6.0, ld);
		}
		// стальные уголки с заклёпками
		vec2 q = hb - abs(c);
		float bd = min(sd_box(q - vec2(21.0, 7.5), vec2(21.0, 7.5), 2.0), sd_box(q - vec2(7.5, 21.0), vec2(7.5, 21.0), 2.0));
		if (bd < 1.0) {
			vec3 st = steel(UV.y) * (0.7 + 0.3 * smoothstep(0.0, 2.0, -bd));
			vec2 r1 = rivet(q, vec2(30.0, 7.5), 3.2);
			vec2 r2 = rivet(q, vec2(7.5, 30.0), 3.2);
			st = mix(st, vec3(0.85) * r1.y, r1.x);
			st = mix(st, vec3(0.85) * r2.y, r2.x);
			col = mix(col, st, clamp(0.5 - bd, 0.0, 1.0));
			seam = 0.0;
		} else {
			col *= 0.65 + 0.35 * smoothstep(1.0, 5.0, bd);
		}
		// объём: сверху светлее, снизу темнее
		col *= mix(1.12, 0.72, UV.y);
		// свет изнутри
		float top = exp(-(c.y + hb.y) / 5.0);
		em += leak.rgb * glow * fl * (seam * 1.3 + top * 0.9);
		em += leak.rgb * glow * 0.12 * (1.0 - UV.y);
		em += mix(leak.rgb, vec3(1.0), 0.5) * open * (exp(-(c.y + hb.y) / 9.0) * 1.6 + exp(-(c.y + hb.y) / 40.0) * 0.3);
	} else {
		// крышка: две доски, стальные торцы, латунная полоса, снизу щель со светом
		float id = step(0.0, c.y);
		col = wood(px + vec2(id * 77.0, 0.0), 40.0 + id) * 1.06;
		col *= mix(0.3, 1.0, smoothstep(0.0, 2.0, abs(c.y)));
		col *= 0.62 + 0.38 * smoothstep(0.0, 6.0, -d);
		col += vec3(0.14, 0.1, 0.06) * exp(-(c.y + hb.y) / 2.5);
		float sx = abs(c.x);
		if (sx < 19.0) {
			col = brass(c.x / 19.0, UV.y) * (0.6 + 0.4 * smoothstep(0.0, 2.0, 19.0 - sx));
		} else {
			col *= 0.7 + 0.3 * smoothstep(19.0, 25.0, sx);
		}
		float ex = hb.x - sx;
		if (ex < 26.0) {
			vec3 st = steel(UV.y) * (0.75 + 0.25 * smoothstep(0.0, 2.0, 26.0 - ex));
			vec2 r1 = rivet(vec2(ex, c.y), vec2(13.0, -12.0), 3.2);
			vec2 r2 = rivet(vec2(ex, c.y), vec2(13.0, 12.0), 3.2);
			st = mix(st, vec3(0.85) * r1.y, r1.x);
			st = mix(st, vec3(0.85) * r2.y, r2.x);
			col = mix(col, st, 1.0 - smoothstep(25.0, 26.0, ex));
		} else {
			col *= 0.7 + 0.3 * smoothstep(26.0, 31.0, ex);
		}
		col *= mix(1.15, 0.8, UV.y);
		em += leak.rgb * glow * fl * exp(-(hb.y - c.y) / 4.0) * 1.2;
	}
	COLOR = vec4((col + em) * COLOR.rgb, alpha * COLOR.a);
}
"""

const SH_GEAR := """
shader_type canvas_item;
// металлическая шестерня-эмблема детали (оттенок редкости); spin — поворот, свет неподвижен
uniform vec4 tint : source_color = vec4(0.3, 0.6, 1.0, 1.0);
uniform float spin = 0.0;
uniform float teeth = 10.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float ra = a + spin;
	float aa = 0.012;
	float tooth = smoothstep(-0.25, 0.25, cos(ra * teeth));
	float R = mix(0.75, 0.93, tooth);
	float m = (1.0 - smoothstep(R - aa, R + aa, r)) * smoothstep(0.16 - aa, 0.16 + aa, r);
	float sector = mod(ra, 6.28318 / 6.0) - 3.14159 / 6.0;
	vec2 hp = vec2(cos(sector), sin(sector)) * r - vec2(0.635, 0.0);
	float lh = length(hp) - 0.075;
	m *= smoothstep(-aa, aa, lh);
	vec2 n = p / max(r, 0.001);
	float lit = dot(n, normalize(vec2(-0.55, -0.83)));
	vec3 base = mix(vec3(0.9, 0.92, 0.96), tint.rgb, 0.45);
	vec3 col = base * (0.78 + 0.3 * lit * smoothstep(0.1, 0.9, r));
	col += vec3(0.3) * pow(max(0.0, cos(2.0 * a + 0.9)), 6.0) * smoothstep(0.2, 0.7, r);
	float rim = smoothstep(R - 0.08, R - aa, r);
	col = mix(col, col * (0.8 + 0.6 * max(lit, 0.0)) + 0.08, rim);
	col += mix(tint.rgb, vec3(1.0), 0.3) * rim * 0.3;
	col *= 1.0 - exp(-pow((r - 0.53) / 0.02, 2.0)) * 0.5;
	col *= 1.0 - (1.0 - smoothstep(0.0, 0.03, lh)) * 0.45;
	col *= 1.0 - exp(-pow((r - 0.175) / 0.025, 2.0)) * 0.45;
	float hub = 1.0 - smoothstep(0.51, 0.53, r);
	col = mix(col, col * 0.82 + tint.rgb * 0.18, hub);
	COLOR = vec4(col * COLOR.rgb, m * COLOR.a);
}
"""

const SH_BEAM := """
shader_type canvas_item;
render_mode blend_add;
// столб света из открытого ящика (низ прямоугольника — у ящика)
uniform vec4 col : source_color = vec4(1.0, 0.8, 0.4, 1.0);
uniform float intensity = 1.0;
void fragment() {
	float y = 1.0 - UV.y;
	float x = UV.x * 2.0 - 1.0;
	float w = mix(0.42, 1.0, y);
	float xn = x / w;
	float core = exp(-xn * xn * 5.0);
	float hot = exp(-xn * xn * 40.0) * 0.6;
	float st = 0.65 + 0.35 * sin(xn * 11.0 + TIME * 1.7) * sin(xn * 5.0 - TIME * 1.1 + y * 3.0);
	float v = (core * st + hot) * pow(1.0 - y, 1.4) * smoothstep(0.0, 0.05, y) * intensity;
	vec3 c = mix(col.rgb, vec3(1.0), clamp(v - 0.6, 0.0, 1.0) * 0.6);
	COLOR = vec4(c * v * COLOR.a, 1.0);
}
"""

var result: Dictionary = {}
var _t: float = 0.0
var _opened: bool = false
var _card: Control
var _rar: int = 0
var _col: Color = Color.WHITE
var _scr: Vector2 = Vector2(720, 1280)
var _base: Vector2           # середина низа ящика
var _mouth: Vector2          # верх ящика (откуда бьёт свет)
var _gear_at: Vector2        # где зависает деталь
var _dim: ColorRect
var _halo: TextureRect
var _crate: Control          # падение и сплющивание (твины)
var _shake: Control          # тряска (каждый кадр)
var _lid: ColorRect
var _body_mat: ShaderMaterial
var _lid_mat: ShaderMaterial
var _rays: ColorRect
var _rays_mat: ShaderMaterial
var _beam: ColorRect
var _beam_mat: ShaderMaterial
var _gear: Control
var _gear_rect: ColorRect
var _gear_mat: ShaderMaterial
var _gear_glow: TextureRect
var _flash: ColorRect
var _motes: GPUParticles2D
var _gear_spin: float = 0.0
var _spin_v: float = 0.0
var _lid_from: Vector2


static func _shader(name: String, code: String) -> Shader:
	var _sh := UiFx.cache("case_shader")
	if not _sh.has(name):
		var s := Shader.new()
		s.code = code
		_sh[name] = s
	return _sh[name]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_scr = size if size.x > 10.0 else get_viewport_rect().size
	_rar = clampi(int(result.get("rar", 0)), 0, D.RARITIES.size() - 1)
	_col = D.RARITIES[_rar].color
	_base = Vector2(_scr.x * 0.5, _scr.y * 0.42 + 120.0)
	_mouth = _base - Vector2(0, BH)
	_gear_at = _mouth - Vector2(0, 150)
	_build()
	Sfx.play("case_shake")
	G.vibrate(30)


func _build() -> void:
	var q := UiFx.quality()
	_dim = ColorRect.new()
	_dim.color = Color(0.01, 0.012, 0.02, 0.0)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)
	create_tween().tween_property(_dim, "color:a", 0.84, 0.25)

	# лучи редкости (видны после открытия)
	var rs := maxf(_scr.x * 1.7, 1150.0)
	_rays = UiFx.shader_rect("rays", Vector2(rs, rs))
	_rays.position = _gear_at - _rays.size * 0.5
	_rays_mat = _rays.material
	_rays_mat.set_shader_parameter("col", _col.lerp(Color.WHITE, 0.15))
	_rays_mat.set_shader_parameter("intensity", 0.5 + 0.14 * _rar)
	_rays_mat.set_shader_parameter("layers", 1.0 if q >= 1 else 0.0)
	_rays_mat.set_shader_parameter("speed", 0.22)
	_rays_mat.set_shader_parameter("falloff", 2.4)
	_rays_mat.set_shader_parameter("core", 0.8)
	_rays.visible = false
	add_child(_rays)

	_halo = UiFx.glow(Vector2(720, 560), Color(GOLD.r, GOLD.g, GOLD.b, 0.0), _base - Vector2(0, BH * 0.55))
	add_child(_halo)

	# тень под ящиком
	var sh := TextureRect.new()
	sh.texture = UiFx.soft_tex()
	sh.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sh.stretch_mode = TextureRect.STRETCH_SCALE
	sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sh.size = Vector2(440, 70)
	sh.position = _base - Vector2(220, 30)
	sh.modulate = Color(0, 0, 0, 0.75)
	add_child(sh)

	_crate = Control.new()
	_crate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crate.position = _base - Vector2(0, 760)
	add_child(_crate)
	_shake = Control.new()
	_shake.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crate.add_child(_shake)
	var body := ColorRect.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.position = Vector2(-BW * 0.5, -BH)
	body.size = Vector2(BW, BH)
	_body_mat = ShaderMaterial.new()
	_body_mat.shader = _shader("crate", SH_CRATE)
	_body_mat.set_shader_parameter("rect", body.size)
	_body_mat.set_shader_parameter("lid", 0.0)
	_body_mat.set_shader_parameter("leak", GOLD)
	_body_mat.set_shader_parameter("glow", 0.0)
	_body_mat.set_shader_parameter("open", 0.0)
	body.material = _body_mat
	_shake.add_child(body)
	_lid = ColorRect.new()
	_lid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lid.size = Vector2(LW, LH)
	_lid_from = Vector2(-LW * 0.5, -BH - LH + 8.0)
	_lid.position = _lid_from
	_lid.pivot_offset = _lid.size * 0.5
	_lid_mat = ShaderMaterial.new()
	_lid_mat.shader = _body_mat.shader
	_lid_mat.set_shader_parameter("rect", _lid.size)
	_lid_mat.set_shader_parameter("lid", 1.0)
	_lid_mat.set_shader_parameter("leak", GOLD)
	_lid.material = _lid_mat
	_shake.add_child(_lid)

	# падение с приземлением
	var tw := create_tween()
	tw.tween_property(_crate, "position", _base, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_land)
	tw.tween_property(_crate, "scale", Vector2(1.1, 0.88), 0.06)
	tw.tween_property(_crate, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_beam = ColorRect.new()
	_beam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_beam_mat = ShaderMaterial.new()
	_beam_mat.shader = _shader("beam", SH_BEAM)
	_beam_mat.set_shader_parameter("col", _col.lerp(Color.WHITE, 0.25))
	_beam.material = _beam_mat
	_beam.size = Vector2(380, _mouth.y - (_gear_at.y - 300.0))
	_beam.position = Vector2(_mouth.x - 190.0, _mouth.y - _beam.size.y + 6.0)
	_beam.visible = false
	add_child(_beam)

	# деталь-эмблема
	_gear = Control.new()
	_gear.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gear.position = _mouth
	_gear.visible = false
	add_child(_gear)
	_gear_glow = UiFx.glow(Vector2(420, 420), Color(_col.r, _col.g, _col.b, 0.75))
	_gear.add_child(_gear_glow)
	_gear_rect = ColorRect.new()
	_gear_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gear_rect.size = Vector2(176, 176)
	_gear_rect.position = -_gear_rect.size * 0.5
	_gear_mat = ShaderMaterial.new()
	_gear_mat.shader = _shader("gear", SH_GEAR)
	_gear_mat.set_shader_parameter("tint", _col)
	_gear_rect.material = _gear_mat
	_gear.add_child(_gear_rect)
	var mk := UI.label(D.roman(int(result.get("mk", 1))), 40, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	mk.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mk.size = Vector2(120, 60)
	mk.add_theme_constant_override("outline_size", 8)
	mk.add_theme_color_override("font_outline_color", Color(0.06, 0.05, 0.08, 0.95))
	_gear_rect.add_child(mk)
	mk.position = _gear_rect.size * 0.5 - mk.size * 0.5

	# пылинки света из щелей, пока ящик трясётся
	_motes = UiFx.emitter("motes", UiFx.amount(18), GOLD, {"one_shot": false, "box": Vector2(BW * 0.45, 8.0), "vmin": 20.0, "vmax": 70.0, "gravity": -60.0, "scale": 1.2, "life": 1.6})
	_motes.position = _mouth + Vector2(0, 6)
	_motes.emitting = false
	add_child(_motes)

	_flash = ColorRect.new()
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.material = UiFx.add_mat()
	_flash.color = Color(_col.lerp(Color.WHITE, 0.55), 0.0)
	add_child(_flash)


func _land() -> void:
	G.vibrate(20)
	UiFx.burst(self, "motes", _base + Vector2(0, -6), UiFx.amount(16), Color(0.75, 0.68, 0.6), {"box": Vector2(BW * 0.5, 4.0), "dir": Vector2(0, -1), "spread": 80.0, "vmin": 40.0, "vmax": 140.0, "gravity": 30.0, "life": 0.9, "scale": 1.6})
	_motes.emitting = true


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and _t > 1.4:
		queue_free()


func _process(delta: float) -> void:
	_t += delta
	if not _opened:
		_build_up()
		if _t >= OPEN_T:
			_opened = true
			Sfx.play("case_open", 0.9 + 0.1 * _rar)
			G.vibrate(60 + 30 * _rar)
			_open()
	else:
		_after_open(delta)


## Тряска нарастает, свет в щелях разгорается (под конец — цветом редкости).
func _build_up() -> void:
	var k := smoothstep(0.3, OPEN_T, _t)
	var k2 := k * k
	_shake.rotation = (sin(_t * 58.0) * 0.045 + sin(_t * 37.0) * 0.02) * k
	_shake.position = Vector2(sin(_t * 71.0) * 5.0 * k, -absf(sin(_t * 29.0)) * 3.0 * k2)
	var pulse := 1.0 + 0.035 * k2 * sin(_t * 42.0)
	_shake.scale = Vector2(pulse, 2.0 - pulse)
	_lid.position = _lid_from + Vector2(0, -absf(sin(_t * 31.0)) * 9.0 * k2)
	_lid.rotation = sin(_t * 23.0) * 0.06 * k
	var leak := GOLD.lerp(_col.lerp(Color.WHITE, 0.2), smoothstep(0.55, 1.0, _t / OPEN_T))
	var g := 0.15 + 1.05 * k2
	_body_mat.set_shader_parameter("glow", g)
	_body_mat.set_shader_parameter("leak", leak)
	_lid_mat.set_shader_parameter("glow", g)
	_lid_mat.set_shader_parameter("leak", leak)
	_halo.modulate = Color(leak.r, leak.g, leak.b, 0.08 + 0.42 * k2)


func _open() -> void:
	var q := UiFx.quality()
	var c := _col
	var hot := c.lerp(Color.WHITE, 0.4)
	_shake.rotation = 0.0
	_shake.position = Vector2.ZERO
	_motes.emitting = false
	# вспышка на весь экран
	_flash.color.a = 0.42 if q >= 1 else 0.3
	var tf := create_tween()
	tf.tween_property(_flash, "color:a", 0.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# ящик отдаёт отдачей, верх пылает
	var tr := create_tween()
	tr.tween_property(_shake, "scale", Vector2(1.1, 0.9), 0.06)
	tr.tween_property(_shake, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_body_mat.set_shader_parameter("leak", c)
	var tg := create_tween().set_parallel(true)
	tg.tween_property(_body_mat, "shader_parameter/open", 1.0, 0.12).from(0.0)
	tg.tween_property(_body_mat, "shader_parameter/glow", 0.35, 0.8).from(1.2)
	_halo.modulate = Color(c.r, c.g, c.b, 0.0)
	tg.tween_property(_halo, "modulate:a", 0.55, 0.3)
	# лучи и столб света
	_rays.visible = true
	_rays.modulate.a = 0.0
	tg.tween_property(_rays, "modulate:a", 1.0, 0.4)
	_beam.visible = true
	_beam.modulate.a = 0.0
	_beam_mat.set_shader_parameter("intensity", 0.75 + 0.1 * _rar)
	tg.tween_property(_beam, "modulate:a", 1.0, 0.15)
	# вспышка-кольцо и искры
	UiFx.ring(self, _mouth, hot, 900.0, 0.8, {"rays": 12.0, "gain": 0.8, "core": 0.25})
	UiFx.ring(self, _mouth, hot.lerp(Color.WHITE, 0.5), 420.0, 0.5, {"rays": 0.0, "ray_amt": 0.0, "delay": 0.08, "gain": 0.6, "core": 0.0})
	UiFx.burst(self, "sparks", _mouth, UiFx.amount(60 + 22 * _rar), c, {"box": Vector2(BW * 0.38, 6.0), "dir": Vector2(0, -1), "spread": 62.0, "vmin": 520.0, "vmax": 1350.0, "gravity": 1100.0, "damp": 420.0, "scale": 1.15, "life": 1.1})
	UiFx.burst(self, "stars", _mouth - Vector2(0, 40), UiFx.amount(26 + 8 * _rar), hot, {"radius": 60.0, "dir": Vector2(0, -1), "spread": 100.0, "vmin": 160.0, "vmax": 560.0, "life": 1.4})
	if _rar >= 2:
		var pal := [c, c.lerp(Color.WHITE, 0.5), Color("ffc21a"), c.darkened(0.25), Color("fff1b0")]
		UiFx.burst(self, "confetti", _mouth, UiFx.amount(40 + 20 * (_rar - 2)), Color.WHITE, {"dir": Vector2(0, -1), "spread": 38.0, "vmin": 900.0, "vmax": 1600.0, "palette": pal, "life": 2.6})
	# блёстки вокруг детали — пока экран открыт
	var tw := UiFx.emitter("twinkle", UiFx.amount(12 + 4 * _rar), c.lerp(Color.WHITE, 0.3), {"one_shot": false, "box": Vector2(150, 120), "life": 1.1, "scale": 1.1})
	tw.position = _gear_at
	add_child(tw)
	# деталь поднимается из ящика
	_gear.visible = true
	_gear.scale = Vector2(0.25, 0.25)
	_spin_v = 9.0
	var tgr := create_tween().set_parallel(true)
	tgr.tween_property(_gear, "position", _gear_at, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tgr.tween_property(_gear, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# карточка — чуть позже, когда деталь уже вылетела
	get_tree().create_timer(0.18).timeout.connect(_show_card)


func _after_open(delta: float) -> void:
	# крышка улетает, кувыркаясь
	var k := clampf((_t - OPEN_T) / 0.75, 0.0, 1.0)
	if _lid.visible:
		_lid.position = _lid_from + Vector2(330.0 * k, -760.0 * k + 980.0 * k * k)
		_lid.rotation = 2.6 * k
		_lid.modulate.a = 1.0 - smoothstep(0.7, 1.0, k)
		_lid_mat.set_shader_parameter("glow", maxf(0.0, 1.0 - k * 3.0))
		if k >= 1.0:
			_lid.visible = false
	# деталь вращается, замедляясь, и покачивается
	_spin_v = lerpf(_spin_v, 0.5, 1.0 - exp(-delta * 2.5))
	_gear_spin = fmod(_gear_spin + _spin_v * delta, TAU)
	_gear_mat.set_shader_parameter("spin", _gear_spin)
	var bob := sin((_t - OPEN_T) * 2.2) * 6.0
	_gear_rect.position = -_gear_rect.size * 0.5 + Vector2(0, bob)
	var pulse := 0.6 + 0.12 * sin(_t * 3.1)
	_gear_glow.modulate.a = pulse
	_gear_glow.position = -_gear_glow.size * 0.5 + Vector2(0, bob)


func _show_card() -> void:
	if not is_inside_tree():
		return
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.position = Vector2(_scr.x * 0.5 - 270.0, _base.y + 34.0)
	add_child(holder)
	_card = UI.card(UI.PANEL, _col, 18)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(v)
	var r: Dictionary = D.RARITIES[_rar]
	var rl := UI.label(r.name.to_upper(), 24, r.color, HORIZONTAL_ALIGNMENT_CENTER)
	rl.add_theme_constant_override("outline_size", 6)
	rl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	v.add_child(rl)
	v.add_child(UI.label("%s Mk %s" % [D.slot(result.slot).name, D.roman(int(result.mk))], 32, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UI.label(D.slot(result.slot).bonus, 18, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	if result.has("cash") and not result.cash.is_zero():
		v.add_child(UI.label("+%s кэша" % G.fmt(result.cash), 22, UI.GOOD, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UI.label("Нажмите, чтобы продолжить", 16, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	holder.add_child(_card)
	_card.size = Vector2(540, 0)
	# свечение по краю и блик — поверх карточки
	var sh := UiFx.shine_rect(Vector2(540, 200), _col, 34.0, 14.0, 0.55)
	holder.add_child(sh)
	var sm: ShaderMaterial = sh.material
	var fit := func():
		sh.size = _card.size + Vector2(68, 68)
		sm.set_shader_parameter("rect", sh.size)
		holder.pivot_offset = _card.size * 0.5
	_card.resized.connect(fit)
	fit.call()
	holder.scale = Vector2(0.3, 0.3)
	holder.modulate.a = 0.0
	var tw := holder.create_tween().set_parallel(true)
	tw.tween_property(holder, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(holder, "modulate:a", 1.0, 0.2)
	var ts := holder.create_tween().set_loops()
	ts.tween_property(sm, "shader_parameter/sweep", 1.3, 0.75).from(-0.3).set_delay(0.25)
	ts.tween_interval(1.5)
