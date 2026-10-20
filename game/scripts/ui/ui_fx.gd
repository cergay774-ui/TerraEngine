extends RefCounted
## Эффекты интерфейса (2D поверх игры): вспышки-кольца, искры, звёздочки, конфетти,
## «пробивные» надписи, блики. Подключается через preload (без class_name).
##
## Правило: всё создаётся один раз на эффект (по событию) и само удаляется; в кадре
## меняются только параметры шейдеров и трансформы (твинами). Никаких draw_* в кадре —
## на Android каждый такой вызов создаёт буферы видеопамяти.
## Текстуры процедурные и кешируются; шейдеры собираются один раз (см. warmup).


## Кеш текстур/шейдеров/материалов. Живёт в метаданных корня дерева (а не в static var):
## так при выходе из игры ресурсы освобождаются вместе с деревом, пока видеосервер ещё жив.
static func cache(group: String) -> Dictionary:
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	if not root.has_meta("ui_fx_cache"):
		root.set_meta("ui_fx_cache", {})
	var c: Dictionary = root.get_meta("ui_fx_cache")
	if not c.has(group):
		c[group] = {}
	return c[group]


# ---------------------------------------------------------------------
# Настройки качества
# ---------------------------------------------------------------------

## Пресет графики 0..3 (Низкое..Ультра).
static func quality() -> int:
	return clampi(int(G.settings.get("quality", 1)), 0, 3)


## Частицы 0..2.
static func particles() -> int:
	return clampi(int(G.settings.get("particles", 1)), 0, 2)


static func compat() -> bool:
	return RenderingServer.get_current_rendering_method() == "gl_compatibility"


## Сколько частиц при данных настройках (n — для «Высокого»).
static func amount(n: int) -> int:
	var k: float = [0.35, 0.65, 1.0][particles()]
	if quality() >= 3:
		k *= 1.3
	return maxi(2, int(round(n * k)))


# ---------------------------------------------------------------------
# Текстуры (процедурные, кешируются)
# ---------------------------------------------------------------------

## Мягкое круглое пятно (свечение).
static func soft_tex() -> Texture2D:
	var _tex := cache("tex")
	if not _tex.has("soft"):
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.18, 0.45, 0.75, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0.25), Color(1, 1, 1, 0.06), Color(1, 1, 1, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 128
		t.height = 128
		_tex.soft = t
	return _tex.soft


## Четырёхлучевая звёздочка-блёстка.
static func spark_tex() -> Texture2D:
	var _tex := cache("tex")
	if not _tex.has("spark"):
		var n := 64
		var img := Image.create_empty(n, n, true, Image.FORMAT_LA8)
		for y in n:
			for x in n:
				var p := Vector2((x + 0.5) / n * 2.0 - 1.0, (y + 0.5) / n * 2.0 - 1.0)
				var d := p.length()
				var core := exp(-d * d * 40.0)
				var halo := exp(-d * d * 7.0) * 0.35
				var rays := exp(-absf(p.x) * 22.0) * exp(-absf(p.y) * 2.6) + exp(-absf(p.y) * 22.0) * exp(-absf(p.x) * 2.6)
				var diag := Vector2(p.x + p.y, p.x - p.y) * 0.7071
				var rays2 := (exp(-absf(diag.x) * 30.0) * exp(-absf(diag.y) * 6.0) + exp(-absf(diag.y) * 30.0) * exp(-absf(diag.x) * 6.0)) * 0.35
				var a := clampf(core + halo + rays * 0.9 + rays2, 0.0, 1.0) * clampf((1.0 - d) * 3.0, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, a))
		img.generate_mipmaps()
		_tex.spark = ImageTexture.create_from_image(img)
	return _tex.spark


## Вытянутая искра (по оси Y — вдоль скорости при align_y).
static func streak_tex() -> Texture2D:
	var _tex := cache("tex")
	if not _tex.has("streak"):
		var w := 16
		var h := 64
		var img := Image.create_empty(w, h, true, Image.FORMAT_LA8)
		for y in h:
			var v := (y + 0.5) / h
			var along := pow(sin(PI * v), 1.2) * (0.55 + 0.45 * (1.0 - v))
			for x in w:
				var u := (x + 0.5) / w * 2.0 - 1.0
				var a := clampf(exp(-u * u * 9.0) * along * 1.15, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, a))
		img.generate_mipmaps()
		_tex.streak = ImageTexture.create_from_image(img)
	return _tex.streak


## Конфетти: прямоугольник с лёгким сгибом посередине.
static func confetti_tex() -> Texture2D:
	var _tex := cache("tex")
	if not _tex.has("confetti"):
		var w := 12
		var h := 20
		var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
		for y in h:
			for x in w:
				var u := (x + 0.5) / w
				var shade := 0.82 + 0.18 * absf(u - 0.5) * 2.0
				var edge := 1.0 if (x > 0 and x < w - 1 and y > 0 and y < h - 1) else 0.75
				img.set_pixel(x, y, Color(shade, shade, shade, edge))
		_tex.confetti = ImageTexture.create_from_image(img)
	return _tex.confetti


## Аддитивное смешивание (для свечений и искр) — один материал на всех.
static func add_mat() -> CanvasItemMaterial:
	var c := cache("mat")
	if not c.has("add"):
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		c.add = m
	return c.add


static func _curve(name: String) -> CurveTexture:
	var _curves := cache("curve")
	if not _curves.has(name):
		var c := Curve.new()
		match name:
			"shrink":       # искры: сразу полный размер, к концу тают
				c.add_point(Vector2(0.0, 1.0))
				c.add_point(Vector2(0.55, 0.75))
				c.add_point(Vector2(1.0, 0.0))
			"twinkle":      # блёстка: вспыхнула — погасла
				c.add_point(Vector2(0.0, 0.0))
				c.add_point(Vector2(0.18, 1.0))
				c.add_point(Vector2(0.5, 0.65))
				c.add_point(Vector2(1.0, 0.0))
			_:              # "pop": выросла и плавно сжалась
				c.add_point(Vector2(0.0, 0.3))
				c.add_point(Vector2(0.12, 1.0))
				c.add_point(Vector2(0.7, 0.8))
				c.add_point(Vector2(1.0, 0.0))
		var t := CurveTexture.new()
		t.curve = c
		t.width = 64
		_curves[name] = t
	return _curves[name]


static func _ramp(colors: Array, offsets: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 64
	return t


# ---------------------------------------------------------------------
# Шейдеры (один экземпляр на имя)
# ---------------------------------------------------------------------

const SH_RING := """
shader_type canvas_item;
render_mode blend_add;
// вспышка: расходящееся кольцо + звёздные лучи + яркое ядро; t — прогресс 0..1
uniform vec4 col : source_color = vec4(1.0, 0.78, 0.25, 1.0);
uniform float t = 0.0;
uniform float rays = 8.0;
uniform float ray_amt = 1.0;
uniform float ring_amt = 1.0;
uniform float seed = 0.0;
uniform float gain = 1.0;
uniform float core = 1.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float tt = clamp(t, 0.0, 1.0);
	float e = 1.0 - pow(1.0 - tt, 3.0);
	float k = 1.0 - tt;
	float rr = mix(0.10, 0.90, e);
	float w = mix(0.08, 0.018, e);
	float ring = exp(-pow((r - rr) / w, 2.0)) * k * ring_amt;
	float ring2 = exp(-pow((r - rr * 0.78) / (w * 3.0), 2.0)) * k * k * 0.35 * ring_amt;
	float flash = (exp(-r * r * 30.0) * 1.4 + exp(-r * r * 6.0) * 0.35) * k * k * core;
	float a = atan(p.y, p.x) + seed + tt * 0.5;
	float sp = pow(abs(cos(a * rays * 0.5)), 80.0);
	float sp2 = pow(abs(cos(a * rays * 0.5 + 1.5708)), 40.0) * 0.45;
	float len = mix(0.3, 1.0, e);
	float spikes = (sp + sp2) * (1.0 - smoothstep(0.0, len, r)) * k * ray_amt;
	float v = (ring + ring2 + flash + spikes) * gain;
	vec3 c = mix(col.rgb, vec3(1.0), clamp(v - 0.7, 0.0, 1.0) * 0.75);
	float edge = 1.0 - smoothstep(0.9, 1.0, r);
	COLOR = vec4(c * v * edge * COLOR.a, 1.0);
}
"""

const SH_RAYS := """
shader_type canvas_item;
render_mode blend_add;
// вращающиеся лучи света из центра (center — в долях прямоугольника)
uniform vec4 col : source_color = vec4(1.0, 0.75, 0.3, 1.0);
uniform float intensity = 1.0;
uniform float speed = 0.25;
uniform float layers = 1.0;
uniform float falloff = 2.0;
uniform float core = 1.0;
uniform vec2 center = vec2(0.5, 0.5);
void fragment() {
	vec2 p = UV - center;
	float r = length(p) * 2.0;
	float a = atan(p.y, p.x);
	float tm = TIME * speed;
	float s1 = smoothstep(0.4, 1.0, 0.5 + 0.5 * cos(a * 9.0 + tm));
	float s2 = smoothstep(0.55, 1.0, 0.5 + 0.5 * cos(a * 14.0 - tm * 1.7 + 1.3));
	float s3 = 0.6 + 0.4 * cos(a * 4.0 + tm * 0.6);
	float rays = (s1 * 0.8 + s2 * 0.5 * layers) * s3;
	rays *= smoothstep(0.0, 0.15, r);
	float fall = exp(-r * falloff) * (1.0 - smoothstep(0.75, 1.0, r));
	float glow = (exp(-r * r * 30.0) + exp(-r * r * 5.0) * 0.3) * core;
	float v = (rays * fall + glow) * intensity;
	vec3 c = mix(col.rgb, vec3(1.0), clamp(glow * intensity - 0.5, 0.0, 1.0) * 0.6);
	COLOR = vec4(c * v * COLOR.a, 1.0);
}
"""

const SH_SHINE := """
shader_type canvas_item;
render_mode blend_add;
// свечение вокруг скруглённой карточки + косой блик по ней. Прямоугольник шире карточки
// на margin со всех сторон; sweep — положение блика 0..1 (вне диапазона — не виден)
uniform vec2 rect = vec2(600.0, 300.0);
uniform float margin = 40.0;
uniform float radius = 14.0;
uniform vec4 col : source_color = vec4(1.0, 0.75, 0.3, 1.0);
uniform float glow = 0.6;
uniform float sweep = -1.0;
uniform float shine = 0.5;
float sd_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}
void fragment() {
	vec2 c = UV * rect - rect * 0.5;
	vec2 hb = max(rect * 0.5 - margin, vec2(1.0));
	float d = sd_box(c, hb, radius);
	float outer = d > 0.0 ? exp(-d / (margin * 0.33)) * (1.0 - smoothstep(margin * 0.7, margin, d)) : 0.0;
	float border = exp(-abs(d) / 2.0);
	float inside = clamp(0.5 - d, 0.0, 1.0);
	float x = (c.x / hb.x) * 0.5 + 0.5 + (c.y / hb.y) * 0.18;
	float band = exp(-pow((x - sweep) * 7.0, 2.0)) * 0.5 + exp(-pow((x - sweep - 0.05) * 26.0, 2.0)) * 0.6;
	vec3 cc = col.rgb * (outer * 0.9 + border * 0.7) * glow + mix(col.rgb, vec3(1.0), 0.7) * band * inside * shine;
	COLOR = vec4(cc * COLOR.a, 1.0);
}
"""

const SH_TEXT := """
shader_type canvas_item;
// надпись: вертикальный градиент заливки (обводка тёмная — остаётся тёмной) и косой блик.
// Цвет шрифта у надписи — белый; y0..y1 — где стоят буквы (в пикселях надписи), w — ширина
uniform vec4 top_col : source_color = vec4(1.0, 0.95, 0.7, 1.0);
uniform vec4 bot_col : source_color = vec4(1.0, 0.6, 0.1, 1.0);
uniform float y0 = 0.0;
uniform float y1 = 60.0;
uniform float w = 400.0;
uniform float sweep = -1.0;
uniform float shine = 0.9;
varying vec2 lp;
void vertex() {
	lp = VERTEX;
}
void fragment() {
	float lum = max(COLOR.r, max(COLOR.g, COLOR.b));
	float gy = clamp((lp.y - y0) / max(y1 - y0, 1.0), 0.0, 1.0);
	vec3 g = mix(top_col.rgb, bot_col.rgb, smoothstep(0.2, 0.85, gy));
	vec3 c = COLOR.rgb * g;
	float x = (lp.x + (lp.y - y0) * 0.45) / max(w, 1.0);
	float band = exp(-pow((x - sweep) * 12.0, 2.0)) * shine;
	c += vec3(band) * smoothstep(0.35, 0.9, lum);
	COLOR.rgb = c;
}
"""

const SH_CONFETTI := """
shader_type canvas_item;
// конфетти кувыркаются: листок поворачивается ребром (сжимается по X) и темнеет
void vertex() {
	float s = float(INSTANCE_ID) * 1.618;
	float ph = INSTANCE_CUSTOM.y * (16.0 + 12.0 * fract(s));
	float f = cos(ph + fract(s * 3.7) * 6.283);
	VERTEX.x *= max(abs(f), 0.12) * sign(f + 0.0001);
	COLOR.rgb *= 0.62 + 0.38 * abs(f);
}
"""

const SH_RAYS3D := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// лучи света за мотором (квадрат, повёрнутый к камере); у пола гаснут
uniform vec4 col : source_color = vec4(1.0, 0.72, 0.32, 1.0);
uniform float intensity = 0.0;
uniform float floor_y = 0.0;
uniform float layers = 1.0;
uniform float spin = 0.0;
varying float wy;
void vertex() {
	wy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}
void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p) * 2.0;
	float a = atan(p.y, p.x);
	float s1 = smoothstep(0.45, 1.0, 0.5 + 0.5 * cos(a * 10.0 + spin));
	float s2 = smoothstep(0.6, 1.0, 0.5 + 0.5 * cos(a * 16.0 - spin * 1.6 + 1.3));
	float s3 = 0.5 + 0.5 * cos(a * 5.0 + spin * 0.5 + 0.7);
	float rays = (s1 * 0.85 + s2 * 0.5 * layers) * (0.45 + 0.55 * s3);
	rays *= smoothstep(0.0, 0.08, r);
	float fall = exp(-r * 3.2) * (1.0 - smoothstep(0.6, 1.0, r));
	float core = exp(-r * r * 90.0) * 1.1 + exp(-r * r * 14.0) * 0.35;
	float fl = smoothstep(floor_y + 0.3, floor_y + 3.0, wy);
	ALBEDO = col.rgb * (rays * fall + core) * intensity * fl;
}
"""


static func shader(name: String) -> Shader:
	var _shaders := cache("shader")
	if not _shaders.has(name):
		var s := Shader.new()
		match name:
			"ring": s.code = SH_RING
			"rays": s.code = SH_RAYS
			"shine": s.code = SH_SHINE
			"text": s.code = SH_TEXT
			"confetti": s.code = SH_CONFETTI
			"rays3d": s.code = SH_RAYS3D
			_: push_error("ui_fx: нет шейдера " + name)
		_shaders[name] = s
	return _shaders[name]


static func shader_mat(name: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader(name)
	return m


## Прямоугольник с шейдером (по умолчанию — не ловит нажатия).
static func shader_rect(name: String, sz: Vector2) -> ColorRect:
	var r := ColorRect.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.size = sz
	r.material = shader_mat(name)
	return r


## Мягкое цветное свечение (аддитивно), центр — в at.
static func glow(sz: Vector2, color: Color, at: Vector2 = Vector2.ZERO) -> TextureRect:
	var g := TextureRect.new()
	g.texture = soft_tex()
	g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	g.stretch_mode = TextureRect.STRETCH_SCALE
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.material = add_mat()
	g.size = sz
	g.position = at - sz * 0.5
	g.pivot_offset = sz * 0.5
	g.modulate = color
	return g


# ---------------------------------------------------------------------
# Частицы
# ---------------------------------------------------------------------

## Излучатель частиц 2D. kind: "sparks" (искры по скорости), "stars" (блёстки),
## "twinkle" (мерцание на месте), "motes" (тёплые пылинки вверх), "confetti", "streaks"
## (скоростные штрихи). o — переопределения: dir (Vector2), spread, vmin, vmax, gravity,
## damp, box (Vector2 — полуразмеры зоны), radius, scale, life, one_shot, explosive.
static func emitter(kind: String, n: int, color: Color = Color.WHITE, o: Dictionary = {}) -> GPUParticles2D:
	var p := GPUParticles2D.new()
	var m := ParticleProcessMaterial.new()
	m.particle_flag_disable_z = true
	var dir: Vector2 = o.get("dir", Vector2(0, -1))
	m.direction = Vector3(dir.x, dir.y, 0.0)
	m.spread = float(o.get("spread", 180.0))
	if o.has("box"):
		var b: Vector2 = o.box
		m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		m.emission_box_extents = Vector3(b.x, b.y, 1.0)
	else:
		m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		m.emission_sphere_radius = float(o.get("radius", 6.0))
	var white := Color(1, 1, 1, 1)
	var hot := color.lerp(white, 0.75)
	var cl := Color(color.r, color.g, color.b, 0.0)
	var sc: float = float(o.get("scale", 1.0))
	var life := 1.0
	p.texture = spark_tex()
	p.material = add_mat()
	match kind:
		"sparks":
			p.texture = streak_tex()
			m.particle_flag_align_y = true
			m.initial_velocity_min = float(o.get("vmin", 320.0))
			m.initial_velocity_max = float(o.get("vmax", 820.0))
			m.damping_min = float(o.get("damp", 700.0)) * 0.7
			m.damping_max = float(o.get("damp", 700.0))
			m.gravity = Vector3(0, float(o.get("gravity", 520.0)), 0)
			m.scale_min = 0.35 * sc
			m.scale_max = 0.8 * sc
			m.scale_curve = _curve("shrink")
			m.color_ramp = _ramp([white, hot, color, cl], [0.0, 0.12, 0.55, 1.0])
			life = 0.75
		"streaks":
			p.texture = streak_tex()
			m.particle_flag_align_y = true
			m.initial_velocity_min = float(o.get("vmin", 700.0))
			m.initial_velocity_max = float(o.get("vmax", 1300.0))
			m.damping_min = float(o.get("damp", 1800.0)) * 0.7
			m.damping_max = float(o.get("damp", 1800.0))
			m.gravity = Vector3(0, float(o.get("gravity", 0.0)), 0)
			m.scale_min = 0.5 * sc
			m.scale_max = 1.1 * sc
			m.scale_curve = _curve("shrink")
			m.color_ramp = _ramp([white, hot, Color(color.r, color.g, color.b, 0.7), cl], [0.0, 0.15, 0.5, 1.0])
			life = 0.5
		"stars":
			m.initial_velocity_min = float(o.get("vmin", 120.0))
			m.initial_velocity_max = float(o.get("vmax", 460.0))
			m.damping_min = float(o.get("damp", 420.0)) * 0.6
			m.damping_max = float(o.get("damp", 420.0))
			m.gravity = Vector3(0, float(o.get("gravity", 60.0)), 0)
			m.angle_min = -45.0
			m.angle_max = 45.0
			m.angular_velocity_min = -160.0
			m.angular_velocity_max = 160.0
			m.scale_min = 0.22 * sc
			m.scale_max = 0.62 * sc
			m.scale_curve = _curve("pop")
			m.color_ramp = _ramp([white, hot, color, cl], [0.0, 0.2, 0.7, 1.0])
			life = 1.1
		"twinkle":
			m.initial_velocity_min = float(o.get("vmin", 0.0))
			m.initial_velocity_max = float(o.get("vmax", 24.0))
			m.gravity = Vector3(0, float(o.get("gravity", -20.0)), 0)
			m.angle_min = -30.0
			m.angle_max = 30.0
			m.scale_min = 0.2 * sc
			m.scale_max = 0.55 * sc
			m.scale_curve = _curve("twinkle")
			m.color_ramp = _ramp([white, hot, color], [0.0, 0.3, 1.0])
			life = 1.0
		"motes":
			p.texture = soft_tex()
			m.initial_velocity_min = float(o.get("vmin", 10.0))
			m.initial_velocity_max = float(o.get("vmax", 50.0))
			m.gravity = Vector3(0, float(o.get("gravity", -30.0)), 0)
			m.scale_min = 0.05 * sc
			m.scale_max = 0.14 * sc
			m.color_ramp = _ramp([cl, Color(color.r, color.g, color.b, 0.9), Color(color.r, color.g, color.b, 0.6), cl], [0.0, 0.2, 0.7, 1.0])
			life = 2.4
		"confetti":
			p.texture = confetti_tex()
			p.material = shader_mat("confetti") if not compat() else null
			m.initial_velocity_min = float(o.get("vmin", 900.0))
			m.initial_velocity_max = float(o.get("vmax", 1500.0))
			m.damping_min = float(o.get("damp", 600.0)) * 0.6
			m.damping_max = float(o.get("damp", 600.0))
			m.gravity = Vector3(0, float(o.get("gravity", 560.0)), 0)
			m.angle_min = 0.0
			m.angle_max = 360.0
			m.angular_velocity_min = -540.0
			m.angular_velocity_max = 540.0
			m.scale_min = 0.8 * sc
			m.scale_max = 1.35 * sc
			var palette: Array = o.get("palette", [Color("ffc21a"), Color("ff8a1f"), Color("fff1b0"), Color("ff5a3c"), Color("6fb6ff"), Color("ffd966")])
			var offs: Array = []
			for i in palette.size():
				offs.append(float(i) / palette.size())
			var pg := Gradient.new()
			pg.offsets = PackedFloat32Array(offs)
			pg.colors = PackedColorArray(palette)
			pg.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
			var pt := GradientTexture1D.new()
			pt.gradient = pg
			pt.width = 64
			m.color_initial_ramp = pt
			m.color_ramp = _ramp([white, white, Color(1, 1, 1, 0)], [0.0, 0.85, 1.0])
			life = 3.4
	p.lifetime = float(o.get("life", life))
	p.amount = maxi(1, n)
	p.one_shot = bool(o.get("one_shot", true))
	p.explosiveness = float(o.get("explosive", 0.92 if p.one_shot else 0.0))
	p.randomness = 0.35
	p.process_material = m
	p.visibility_rect = Rect2(-3000, -3000, 6000, 6000)
	p.emitting = true
	return p


## Разовый выброс частиц в точке at; сам удалится.
static func burst(parent: Node, kind: String, at: Vector2, n: int, color: Color, o: Dictionary = {}) -> GPUParticles2D:
	var p := emitter(kind, n, color, o)
	p.position = at
	parent.add_child(p)
	_free_after(p, p.lifetime * (1.0 + p.randomness) + 0.2)
	return p


static func _free_after(n: Node, sec: float) -> void:
	var tw := n.create_tween()
	tw.tween_interval(sec)
	tw.tween_callback(n.queue_free)


# ---------------------------------------------------------------------
# Готовые эффекты
# ---------------------------------------------------------------------

## Вспышка: кольцо + звёздные лучи + ядро. Сама удаляется.
static func ring(parent: Control, at: Vector2, color: Color, diameter: float, dur: float = 0.7, o: Dictionary = {}) -> ColorRect:
	var r := shader_rect("ring", Vector2(diameter, diameter))
	r.position = at - r.size * 0.5
	var m: ShaderMaterial = r.material
	m.set_shader_parameter("col", color)
	m.set_shader_parameter("rays", float(o.get("rays", 8.0)))
	m.set_shader_parameter("ray_amt", float(o.get("ray_amt", 1.0)))
	m.set_shader_parameter("ring_amt", float(o.get("ring_amt", 1.0)))
	m.set_shader_parameter("seed", randf() * TAU)
	m.set_shader_parameter("gain", float(o.get("gain", 1.0)))
	m.set_shader_parameter("core", float(o.get("core", 1.0)))
	m.set_shader_parameter("t", 0.0)
	parent.add_child(r)
	var tw := r.create_tween()
	if o.has("delay"):
		r.modulate.a = 0.0
		tw.tween_interval(float(o.delay))
		tw.tween_property(r, "modulate:a", 1.0, 0.0)
	tw.tween_property(m, "shader_parameter/t", 1.0, dur)
	tw.tween_callback(r.queue_free)
	return r


## Свечение + блик поверх карточки/полосы. Возвращает прямоугольник (шире rect на margin).
static func shine_rect(card_size: Vector2, color: Color, margin: float = 36.0, radius: float = 14.0, glow_amt: float = 0.6) -> ColorRect:
	var sz := card_size + Vector2(margin, margin) * 2.0
	var r := shader_rect("shine", sz)
	r.position = -Vector2(margin, margin)
	var m: ShaderMaterial = r.material
	m.set_shader_parameter("rect", sz)
	m.set_shader_parameter("margin", margin)
	m.set_shader_parameter("radius", radius)
	m.set_shader_parameter("col", color)
	m.set_shader_parameter("glow", glow_amt)
	m.set_shader_parameter("sweep", -1.0)
	return r


## Материал надписи: градиент заливки + блик. lbl_h — высота надписи, font — размер шрифта.
static func text_mat(top: Color, bottom: Color, lbl_w: float, lbl_h: float, font: float) -> ShaderMaterial:
	var m := shader_mat("text")
	m.set_shader_parameter("top_col", top)
	m.set_shader_parameter("bot_col", bottom)
	m.set_shader_parameter("y0", lbl_h * 0.5 - font * 0.42)
	m.set_shader_parameter("y1", lbl_h * 0.5 + font * 0.42)
	m.set_shader_parameter("w", lbl_w)
	m.set_shader_parameter("sweep", -1.0)
	return m


## «Пробивная» всплывающая надпись: влетает с перелётом, вспыхивает, по ней бежит блик,
## позади мягкое свечение; style "crit" / "turbo" добавляют вспышку и частицы.
static func pop_text(parent: Control, text: String, color: Color, fsize: int, at: Vector2, style: String = "") -> Control:
	var strong := style != "" or fsize >= 34
	var box := Vector2(640, fsize * 2.0)
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size = box
	holder.position = at - box * 0.5
	holder.pivot_offset = box * 0.5
	var tw_px := ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	if strong:
		# цветной ореол вокруг и тёмная подложка прямо под буквами — надпись читается
		# даже поверх искр и яркого мотора
		var gl := glow(Vector2(tw_px * 1.5 + fsize * 2.0, fsize * 3.6), Color(color.r, color.g, color.b, 0.42), box * 0.5)
		holder.add_child(gl)
		var dark := TextureRect.new()
		dark.texture = soft_tex()
		dark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		dark.stretch_mode = TextureRect.STRETCH_SCALE
		dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dark.size = Vector2(tw_px * 1.15 + fsize, fsize * 2.0)
		dark.position = box * 0.5 - dark.size * 0.5
		dark.modulate = Color(0, 0, 0, 0.5)
		holder.add_child(dark)
	var l := Label.new()
	l.text = text
	l.size = box
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_constant_override("outline_size", maxi(6, fsize / 4))
	l.add_theme_color_override("font_outline_color", Color(color.r * 0.18, color.g * 0.12, color.b * 0.1, 0.92))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", maxi(2, fsize / 12))
	l.add_theme_constant_override("shadow_outline_size", maxi(6, fsize / 4))
	var tm := text_mat(color.lerp(Color.WHITE, 0.55), color, box.x, box.y, fsize)
	l.material = tm
	holder.add_child(l)

	# вспышка и частицы — позади надписи, чтобы она читалась
	var center := at
	match style:
		"crit":
			ring(parent, center, Color(1.0, 0.7, 0.2), fsize * 7.5, 0.5, {"rays": 10.0, "gain": 0.8, "core": 0.4})
			burst(parent, "sparks", center, amount(22), Color(1.0, 0.6, 0.14), {"box": Vector2(tw_px * 0.4, fsize * 0.25), "vmin": 220.0, "vmax": 520.0, "damp": 900.0, "gravity": 380.0, "scale": 0.55, "life": 0.6})
			burst(parent, "stars", center, amount(12), Color(1.0, 0.85, 0.35), {"box": Vector2(tw_px * 0.5, fsize * 0.45), "vmin": 40.0, "vmax": 200.0, "life": 1.0, "scale": 0.9})
		"turbo":
			ring(parent, center, Color(0.4, 0.7, 1.0), fsize * 7.0, 0.5, {"rays": 6.0, "ray_amt": 0.6, "gain": 0.8, "core": 0.5})
			burst(parent, "streaks", center + Vector2(-tw_px * 0.5 - 12.0, 0), amount(12), Color(0.45, 0.75, 1.0), {"dir": Vector2(-1, 0), "spread": 8.0, "box": Vector2(4, fsize * 0.45), "vmin": 450.0, "vmax": 950.0, "scale": 0.8})
			burst(parent, "streaks", center + Vector2(tw_px * 0.5 + 12.0, 0), amount(12), Color(0.45, 0.75, 1.0), {"dir": Vector2(1, 0), "spread": 8.0, "box": Vector2(4, fsize * 0.45), "vmin": 450.0, "vmax": 950.0, "scale": 0.8})
			burst(parent, "stars", center, amount(12), Color(0.55, 0.8, 1.0), {"box": Vector2(tw_px * 0.45, fsize * 0.4), "vmin": 40.0, "vmax": 220.0})
		_:
			if strong:
				burst(parent, "stars", center, amount(8), color, {"box": Vector2(tw_px * 0.4, fsize * 0.3), "vmax": 200.0, "scale": 0.8})
	parent.add_child(holder)

	# влёт с перелётом и вспышкой, потом блик, всплытие и таяние
	holder.scale = Vector2(0.25, 0.25)
	holder.modulate.a = 0.0
	l.self_modulate = Color(2.4, 2.4, 2.4) if strong else Color(1.6, 1.6, 1.6)
	var punch := 1.22 if strong else 1.12
	var tw := holder.create_tween()
	tw.set_parallel(true)
	tw.tween_property(holder, "scale", Vector2(punch, punch), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(holder, "modulate:a", 1.0, 0.08)
	tw.tween_property(l, "self_modulate", Color.WHITE, 0.32).set_delay(0.06)
	tw.tween_property(tm, "shader_parameter/sweep", 1.25, 0.5).from(-0.25).set_delay(0.14)
	tw.tween_property(holder, "position:y", holder.position.y - (90.0 if strong else 70.0), 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT).set_delay(0.12)
	tw.tween_property(holder, "modulate:a", 0.0, 0.45).set_delay(1.05)
	tw.chain().tween_callback(holder.queue_free)
	var tw2 := holder.create_tween()
	tw2.tween_interval(0.12)
	tw2.tween_property(holder, "scale", Vector2.ONE, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if strong:
		tw2.tween_interval(0.35)
		tw2.tween_property(holder, "scale", Vector2(1.04, 1.04), 0.5).set_trans(Tween.TRANS_SINE)
	return holder


## Повышение уровня: золотое кольцо и искры вокруг значка уровня, блик по полосе опыта.
static func level_up(parent: Control, badge: Vector2, bar: Rect2) -> void:
	var gold := Color(1.0, 0.78, 0.22)
	var fl := glow(Vector2(150, 150), Color(1.0, 0.82, 0.4, 0.8), badge)
	parent.add_child(fl)
	fl.scale = Vector2(0.4, 0.4)
	var tw := fl.create_tween().set_parallel(true)
	tw.tween_property(fl, "scale", Vector2(1.5, 1.5), 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(fl, "modulate:a", 0.0, 0.6).set_delay(0.1)
	tw.chain().tween_callback(fl.queue_free)
	ring(parent, badge, gold, 300.0, 0.75, {"rays": 12.0, "core": 0.6})
	ring(parent, badge, Color(1.0, 0.92, 0.6), 190.0, 0.6, {"rays": 0.0, "ray_amt": 0.0, "delay": 0.14})
	burst(parent, "stars", badge, amount(26), gold, {"radius": 22.0, "vmin": 160.0, "vmax": 420.0})
	burst(parent, "sparks", badge, amount(22), Color(1.0, 0.66, 0.18), {"radius": 18.0, "vmin": 260.0, "vmax": 620.0, "gravity": 260.0, "scale": 0.8})
	burst(parent, "twinkle", badge, amount(10), gold, {"box": Vector2(70, 50), "life": 1.2, "explosive": 0.4})
	if bar.size.x > 4.0:
		var holder := Control.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.position = bar.position
		holder.size = bar.size
		parent.add_child(holder)
		var sh := shine_rect(bar.size, gold, 14.0, bar.size.y * 0.5, 0.9)
		holder.add_child(sh)
		var sm: ShaderMaterial = sh.material
		sm.set_shader_parameter("shine", 1.0)
		var t2 := holder.create_tween()
		t2.tween_property(sm, "shader_parameter/sweep", 1.3, 0.65).from(-0.3).set_delay(0.08)
		t2.parallel().tween_property(sh, "modulate:a", 0.0, 0.4).set_delay(0.45)
		t2.tween_callback(holder.queue_free)


## Прогрев: один раз показать каждый эффект почти прозрачным, чтобы шейдеры и частицы
## собрались заранее, а не в момент первого крита/уровня/кейса.
static func warmup(parent: Control) -> void:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.modulate = Color(1, 1, 1, 0.01)
	parent.add_child(holder)
	var at := Vector2(60, 60)
	ring(holder, at, Color.WHITE, 40.0, 0.3)
	for k in ["sparks", "streaks", "stars", "twinkle", "motes", "confetti"]:
		burst(holder, k, at, 2, Color.WHITE, {"life": 0.3})
	var r := shader_rect("rays", Vector2(40, 40))
	holder.add_child(r)
	var s := shine_rect(Vector2(40, 20), Color.WHITE)
	holder.add_child(s)
	var l := Label.new()
	l.text = "1"
	l.material = text_mat(Color.WHITE, Color.WHITE, 40, 40, 20)
	holder.add_child(l)
	_free_after(holder, 0.6)
