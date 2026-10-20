extends FxModule
## Постобработка всего 3D-кадра: один шейдер canvas_item на TextureRect, который показывает
## картинку SubViewport (view.fx_display()). Всё в один проход и с малым числом выборок:
##   • грейдинг: мягкий S-контраст, тёплые света / холодные тени, насыщенность, виньетка
##     и лёгкая «подсветка» вокруг мотора, повышение резкости (3D растягивается на экран);
##   • марево: дрожание воздуха над выхлопом и турбиной (сильнее от газа, нагрева и турбо),
##     лёгкое марево по всему кадру и красный пульс по краям при перегреве;
##   • удары: турбо — радиальный рывок с размытием, хроматикой и синими штрихами скорости,
##     крит — толчок, ударная волна и тёплая вспышка, отсечка — крошечный пульс,
##     уровень — золотая волна.
## Плюс один раз настраивается Environment: тонмаппер, экспозиция, свечение (bloom).
## Low (q=0): только грейдинг и виньетка — без искажений и дополнительных выборок.
## Каждый кадр меняются только параметры шейдера, и только когда заметно изменились.

const SHADER_BODY := """
uniform vec4 grade = vec4(0.5, 1.12, 0.55, 0.75);  // контраст, насыщенность, виньетка, сплит-тон
uniform vec4 vig = vec4(0.5, 0.45, 0.0, 0.0);      // центр мотора на экране (uv), шарп, подсветка
uniform vec4 tail_seg = vec4(-1.0);                // струя выхлопа: начало xy, конец zw (uv)
uniform vec4 turb_pos = vec4(-1.0, -1.0, 0.05, 0.0);  // турбина: xy (uv), z — радиус; w — марево над мотором
uniform vec4 eng_pos = vec4(0.5, 0.4, 0.2, 0.1);  // верх мотора: xy (uv), полуоси zw (доли высоты)
uniform vec4 heat = vec4(0.0);    // марево: выхлоп, турбина, весь кадр; w — перегрев
uniform vec4 punch = vec4(0.0);   // турбо-рывок, хроматика, крит-вспышка, отсечка
uniform vec4 tint = vec4(0.0);    // турбо (холодный тон), золото, штрихи скорости
uniform vec4 wave = vec4(0.0, 0.0, 0.08, 0.0);     // ударная волна: радиус, сила, ширина
uniform vec4 wave_col = vec4(1.0, 0.6, 0.25, 0.0); // цвет кромки волны
uniform vec2 punch_center = vec2(0.5);
uniform sampler2D noise_tex : filter_linear, repeat_enable;

varying vec4 v_mod;

const vec3 LUM = vec3(0.2126, 0.7152, 0.0722);

void vertex() {
	v_mod = COLOR;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	vec2 asp = vec2(px.y / px.x, 1.0);
	vec2 uv = UV;
	// толчок камеры: картинка чуть приближается к мотору
	float zoom = punch.x * 0.026 + punch.z * 0.02 + punch.w * 0.005;
	uv = punch_center + (uv - punch_center) * (1.0 - zoom);
	vec2 suv = uv;
	vec2 cd = (uv - punch_center) * asp;   // от мотора, в квадратных единицах
	float cr = length(cd);
	float ring = 0.0;
#if Q >= 1
	// ударная волна: кольцо-линза, бегущее от мотора
	if (wave.y > 0.001) {
		float x = (cr - wave.x) / wave.z;
		float r1 = 1.0 - smoothstep(0.0, 1.0, abs(x));
		ring = r1 * wave.y;
		suv -= (cd / max(cr, 1e-4)) / asp * (x * r1) * wave.y * 0.03;
	}
	// марево: маска (струя выхлопа + столб над турбиной + общий фон) * шум, бегущий вверх
	vec2 p = uv * asp;
	float m = heat.z;
	if (heat.x > 0.002) {
		vec2 a = tail_seg.xy * asp;
		vec2 ab = tail_seg.zw * asp - a;
		float l2 = max(dot(ab, ab), 1e-6);
		float h = clamp(dot(p - a, ab) / l2, 0.0, 1.0);
		float d = length(p - a - ab * h);
		float w = sqrt(l2) * (0.1 + 0.3 * h);
		m += heat.x * (1.0 - smoothstep(w * 0.2, w, d)) * smoothstep(0.0, 0.1, h) * (1.0 - h * h);
	}
	if (heat.y > 0.002) {
		vec2 tq = (p - turb_pos.xy * asp) / turb_pos.z;
		tq.y = (tq.y + 0.9) * 0.55;   // столб тёплого воздуха поднимается над турбиной
		m += heat.y * (1.0 - smoothstep(0.3, 1.0, length(tq)));
	}
	if (turb_pos.w > 0.002) {
		// горячий мотор: воздух дрожит над ним (столб от верха блока)
		vec2 eq = (p - eng_pos.xy * asp) / eng_pos.zw;
		eq.y = eq.y * (eq.y < 0.0 ? 0.6 : 1.6);
		m += turb_pos.w * (1.0 - smoothstep(0.2, 1.0, length(eq)));
	}
	if (m > 0.002) {
		vec2 n = texture(noise_tex, p * 2.2 + vec2(0.0, TIME * 0.32)).rg * 2.0 - 1.0;
#if Q >= 2
		n = n * 0.65 + (texture(noise_tex, p * 4.7 + vec2(TIME * 0.05, TIME * 0.75)).rg * 2.0 - 1.0) * 0.35;
#endif
		suv += n * min(m, 1.6) * 0.0042;
	}
#endif
	vec3 c = texture(TEXTURE, suv).rgb;
#if Q >= 1
	vec3 base = c;
	// резкость: 3D рисуется в меньшем разрешении и растягивается — возвращаем чёткость граням
	vec2 hp = px * 0.5;
	vec3 bl = texture(TEXTURE, suv + hp).rgb + texture(TEXTURE, suv - hp).rgb;
#if Q >= 2
	bl += texture(TEXTURE, suv + vec2(hp.x, -hp.y)).rgb + texture(TEXTURE, suv + vec2(-hp.x, hp.y)).rgb;
	bl *= 0.25;
#else
	bl *= 0.5;
#endif
	c = max(c + (c - bl) * vig.z, vec3(0.0));
	// турбо-рывок: радиальное размытие к мотору
	if (punch.x > 0.01) {
		// выборки сдвинуты на случайную долю шага — вместо «двоения» мягкий след
		vec2 dir = (uv - punch_center) * punch.x * 0.055;
		float j = hash12(FRAGCOORD.xy);
		vec3 acc = c;
		for (int i = 0; i < TAPS; i++) {
			acc += texture(TEXTURE, suv - dir * ((float(i) + j) / float(TAPS))).rgb;
		}
		c = acc / float(TAPS + 1);
	}
	// хроматика по краям (рывок, крит, турбо): сдвиг каналов добавляем разностью,
	// чтобы не потерять размытие и шарп
	if (punch.y > 0.001) {
		vec2 o = (uv - punch_center) * punch.y * 0.008;
		c.r += texture(TEXTURE, suv + o).r - base.r;
		c.b += texture(TEXTURE, suv - o).b - base.b;
	}
#endif
	// --- грейдинг ---
	c = clamp(c, 0.0, 1.0);
	vec3 s = c * c * (3.0 - 2.0 * c);
	c = mix(c, s, grade.x);
	float l = dot(c, LUM);
	c = max(mix(vec3(l), c, grade.y), 0.0);
	float hi = smoothstep(0.25, 0.85, l);
	vec3 split = mix(vec3(0.93, 0.98, 1.07), vec3(1.07, 1.0, 0.9), hi);
	c *= mix(vec3(1.0), split, grade.w);
	// турбо: холодный тон
	c = mix(c, c * vec3(0.86, 0.98, 1.16) + vec3(0.0, 0.01, 0.03), tint.x * 0.55);
	// виньетка и мягкая подсветка вокруг мотора
	vec2 vd = (UV - vig.xy) * vec2(1.15, 0.82);
	float vr = dot(vd, vd);
	float v = smoothstep(0.05, 0.42, vr);
	c *= (1.0 - v * grade.z) * (1.0 + vig.w * (1.0 - v));
	// края: перегрев — красный пульс, турбо — синее свечение
	float edge = smoothstep(0.08, 0.45, vr);
	float beat = 0.5 + 0.5 * sin(TIME * 4.6);
	float pulse = heat.w * (0.3 + 0.7 * beat * beat);
	c = mix(c, c * vec3(1.15, 0.84, 0.78), heat.w * 0.25);
	c += vec3(0.55, 0.05, 0.01) * edge * pulse * 0.42;
	c += vec3(0.05, 0.2, 0.55) * edge * tint.x * (0.1 + punch.x * 0.45);
	// штрихи скорости при включении турбо
	if (tint.z > 0.01) {
		float ang = atan(cd.y, cd.x);
		float st = sin(ang * 41.0 + 1.3) * sin(ang * 23.0 + 0.4) * sin(ang * 13.0);
		float lines = smoothstep(0.25, 0.8, st) * smoothstep(0.22, 0.5, cr);
		c += vec3(0.45, 0.7, 1.0) * lines * tint.z * 0.32;
	}
	// крит: тёплая вспышка (сильнее по светлому); кромка волны; отсечка — короткий пульс
	c += vec3(1.0, 0.7, 0.36) * punch.z * (0.1 + 0.6 * l * l);
	c += wave_col.rgb * ring * 0.3;
	c *= 1.0 + punch.w * 0.035;   // отсечка бьёт ~8 раз в секунду — перепад яркости держим малым
	// золото уровня: мотор «вспыхивает» золотом — множим (чёрное остаётся чёрным) и чуть добавляем
	float gf = tint.y * (1.0 - smoothstep(0.05, 0.6, cr));
	c *= 1.0 + gf * vec3(0.55, 0.38, 0.05);
	c += vec3(1.0, 0.75, 0.3) * gf * 0.05;
#if Q >= 2
	// зерно — едва заметное, только в тенях
	float g = hash12(FRAGCOORD.xy + fract(TIME * 7.13) * 413.0) - 0.5;
	c += g * 0.03 * (1.0 - l) * (1.0 - l);
#else
	c += (hash12(FRAGCOORD.xy) - 0.5) * (1.5 / 255.0);
#endif
	COLOR = vec4(c, 1.0) * v_mod;
}
"""

const SHARPEN := [0.0, 0.4, 0.5, 0.5]    # по пресету
const SPOT := 0.07                         # подсветка вокруг мотора

static var _noise: Texture2D
static var _shaders: Dictionary = {}

var _mat: ShaderMaterial
var _sent: Dictionary = {}
var _warm: bool = false
var _q: int = 1
var _sharp: float = 0.0
var _gl: bool = false          # запасной OpenGL: картинка темнее, красный пульс там заметнее
# плавные уровни эффектов
var _h_tail: float = 0.0
var _h_turb: float = 0.0
var _h_all: float = 0.0
var _h_eng: float = 0.0
var _over: float = 0.0
var _turbo: float = 0.0
# импульсы событий (затухают)
var _kick: float = 0.0
var _crit: float = 0.0
var _limit: float = 0.0
var _gold: float = 0.0
var _pop: float = 0.0
var _wave_t: float = -1.0      # время с начала ударной волны (< 0 — нет)
var _wave_len: float = 0.45
var _wave_amp: float = 1.0


func setup() -> void:
	_q = clampi(q(), 0, 3)
	_sharp = SHARPEN[_q]
	_gl = compat()
	_tune_environment()
	_mat = ShaderMaterial.new()
	_mat.shader = _shader_for(_q)
	if _q >= 1:
		_mat.set_shader_parameter("noise_tex", _noise_texture())
	_sent.clear()
	# контраст, насыщенность, виньетка, сплит-тон; в OpenGL картинка темнее — грейдинг мягче
	_set4("grade", Vector4(0.3, 1.1, 0.42, 0.7) if compat() else Vector4(0.5, 1.12, 0.55, 0.75))
	view.fx_display().material = _mat
	# FXAA в 3D-вьюпорте (в проходе тонмаппинга, при меньшем разрешении 3D — дёшево): лесенки
	# на гранях мотора и линии пола сглаживаются, а шарп в нашем шейдере возвращает чёткость.
	# Только High/Ultra на Vulkan: там свечение и так даёт отдельный проход тонмаппинга.
	var vp: SubViewport = view.fx_viewport()
	if vp != null:
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if _q >= 2 and not compat() else Viewport.SCREEN_SPACE_AA_DISABLED


static func _shader_for(quality: int) -> Shader:
	if _shaders.has(quality):
		return _shaders[quality]
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\n#define Q %d\n#define TAPS %d\n" % [quality, [1, 2, 4, 6][quality]] + SHADER_BODY
	_shaders[quality] = sh
	return sh


## Карта искажений: градиент бесшовного шума, записанный как карта нормалей (RG — смещение).
static func _noise_texture() -> Texture2D:
	if _noise != null:
		return _noise
	var n := FastNoiseLite.new()
	n.seed = 11
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.035
	n.fractal_octaves = 3
	var img := n.get_seamless_image(128, 128)
	img.convert(Image.FORMAT_RGBA8)
	img.bump_map_to_normal_map(6.0)
	img.generate_mipmaps()
	_noise = ImageTexture.create_from_image(img)
	return _noise


## Тонмаппинг и свечение 3D-картинки (один раз при создании мира). Включает ли свечение —
## решает настройка «glow» (EngineView), здесь только его вид: тёплый ореол у раскалённого
## коллектора, пламени и ламп без общей дымки.
func _tune_environment() -> void:
	var env: Environment = view.fx_environment()
	if env == null:
		return
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.1
	env.tonemap_white = 6.0
	env.glow_intensity = 0.8
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 0.9
	env.glow_hdr_scale = 2.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	var levels := [0.15, 0.85, 0.8, 0.55, 0.35, 0.15, 0.0]
	for i in levels.size():
		env.set("glow_levels/%d" % (i + 1), levels[i])


func warmup(on: bool) -> void:
	_warm = on


func on_event(event_name: String, _data: Dictionary) -> void:
	match event_name:
		"turbo_start":
			_kick = 1.0
		"crit":
			_crit = 1.0
			_start_wave(0.7, 1.0, Color(1.0, 0.62, 0.25))
		"limiter":
			_limit = 1.0
		"level_up":
			_gold = 1.0
			_start_wave(0.8, 0.7, Color(1.0, 0.8, 0.3))
		"upgrade":
			_gold = maxf(_gold, 0.45)
		"gold":
			_gold = maxf(_gold, 0.3)
		"pop":
			_pop = 1.0
		"exhausted":
			_crit = maxf(_crit, 0.3)


func _start_wave(length: float, amp: float, col: Color) -> void:
	if _q == 0:
		return
	_wave_t = 0.0
	_wave_len = length
	_wave_amp = amp
	_set4("wave_col", Vector4(col.r, col.g, col.b, 0.0))


func update(delta: float, st: Dictionary) -> void:
	if _mat == null:
		return
	var demo: bool = st.demo
	var ratio: float = st.ratio
	var hot: float = st.heat
	var throttle: bool = st.throttle
	var turbo_on: bool = st.turbo and not demo
	var exhausted: bool = st.exhausted and not demo
	var live: bool = _q >= 1 and not demo and not view.render_paused
	# цели марева
	var t_tail := 0.0
	var t_turb := 0.0
	var t_all := 0.0
	var t_eng := 0.0
	if live:
		t_tail = clampf(0.25 + ratio * 0.75 + hot * 0.3, 0.0, 1.3) * (1.0 if throttle else 0.6)
		if turbo_on:
			t_tail *= 1.35
		t_turb = 1.0 if turbo_on else clampf(ratio * 0.45 + hot * 0.25, 0.0, 0.6)
		t_all = 0.3 if exhausted else 0.0
		t_eng = clampf((hot - 0.35) * 1.6, 0.0, 1.0) * (0.6 + 0.4 * ratio)
		if exhausted:
			t_eng = 1.0
	var k := 1.0 - exp(-delta * 4.0)
	_h_tail = lerpf(_h_tail, t_tail, k)
	_h_turb = lerpf(_h_turb, t_turb, k)
	_h_all = lerpf(_h_all, t_all, 1.0 - exp(-delta * 2.0))
	_h_eng = lerpf(_h_eng, t_eng, 1.0 - exp(-delta * 2.0))
	_over = lerpf(_over, 1.0 if exhausted else 0.0, 1.0 - exp(-delta * 3.0))
	var turbo_tint := clampf(float(st.turbo_t) * 5.0, 0.0, 1.0) if turbo_on else 0.0
	_turbo = lerpf(_turbo, turbo_tint, 1.0 - exp(-delta * 5.0))
	_kick = maxf(0.0, _kick - delta / 0.6)
	_crit = maxf(0.0, _crit - delta / 0.5)
	_limit = maxf(0.0, _limit - delta / 0.09)
	_gold = maxf(0.0, _gold - delta / 0.9)
	_pop = maxf(0.0, _pop - delta / 0.35)
	if _q == 0:
		_kick = 0.0
	var e_kick := _kick * _kick
	var e_crit := _crit * _crit * (1.6 - 0.6 * _crit)
	var e_gold := _gold * _gold * (3.0 - 2.0 * _gold)
	# ударная волна
	var wave := Vector4(0.0, 0.0, 0.07, 0.0)
	if _wave_t >= 0.0:
		_wave_t += delta
		var f := _wave_t / _wave_len
		if f >= 1.0:
			_wave_t = -1.0
		else:
			var r := 1.0 - (1.0 - f) * (1.0 - f)
			wave = Vector4(0.03 + r * 0.7, (1.0 - f) * _wave_amp, 0.05 + 0.07 * f, 0.0)
	# точки на экране
	var has_turb := false
	var warm := 0.004 if _warm else 0.0
	var tw := Vector4(-1.0, -1.0, 0.05, 0.0)
	if _h_tail > 0.002 or _h_turb > 0.002 or _h_eng > 0.002 or _warm:
		var tail: Vector3 = view.fx_tail()
		var dir: Vector3 = view.fx_tail_dir()
		var a: Vector2 = view.fx_screen_uv(tail + dir * 0.25)
		var b: Vector2 = view.fx_screen_uv(tail + dir * 2.2 + Vector3(0, 2.6, 0))
		if a.x > -0.5 and b.x > -0.5:
			_set4("tail_seg", Vector4(a.x, a.y, b.x, b.y), 0.0008)
		var tp: Vector3 = view.fx_turbine()
		if tp != Vector3.INF:
			var tu: Vector2 = view.fx_screen_uv(tp)
			var tr: Vector2 = view.fx_screen_uv(tp + Vector3(0, 1.4, 0))
			if tu.x > -0.5 and tr.x > -0.5:
				has_turb = true
				tw = Vector4(tu.x, tu.y, maxf(0.01, absf(tu.y - tr.y)), 0.0)
		# верх мотора и его размер на экране
		var box: AABB = view.fx_bounds()
		var bc := box.get_center()
		var top: Vector2 = view.fx_screen_uv(Vector3(bc.x, box.end.y - box.size.y * 0.15, bc.z))
		var up: Vector2 = view.fx_screen_uv(Vector3(bc.x, box.end.y + box.size.y * 0.3, bc.z))
		var side: Vector2 = view.fx_screen_uv(Vector3(box.position.x, box.end.y, bc.z))
		var side2: Vector2 = view.fx_screen_uv(Vector3(box.end.x, box.end.y, bc.z))
		if top.x > -0.5 and up.x > -0.5:
			var asp := float(view.fx_viewport().size.x) / maxf(1.0, float(view.fx_viewport().size.y))
			var rx := maxf(0.02, absf(side2.x - side.x) * asp * 0.45)
			_set4("eng_pos", Vector4(top.x, top.y - (top.y - up.y) * 0.4, rx, maxf(0.02, absf(top.y - up.y))), 0.001)
		tw.w = maxf(_z(_h_eng), warm)
	_set4("turb_pos", tw, 0.0008)
	var center: Vector2 = view.fx_screen_uv(view.fx_center())
	if center.x > -0.5:
		_set2("punch_center", center, 0.002)
	var band: Rect2 = view.band
	_set4("vig", Vector4(band.position.x + band.size.x * 0.5, band.position.y + band.size.y * 0.5,
		_sharp, SPOT), 0.002)
	# прогрев: крошечные значения, чтобы все ветки шейдера сработали в первые кадры
	_set4("heat", Vector4(maxf(_z(_h_tail + _pop * 0.7), warm), maxf(_z(_h_turb) if has_turb else 0.0, warm),
		_z(_h_all), _z(_over) * (0.7 if _gl else 1.0)), 0.004)
	var chroma := e_kick * 0.5 + e_crit * 0.5 + (_turbo * 0.2 if _q >= 2 else 0.0)
	_set4("punch", Vector4(maxf(_z(e_kick), warm * 3.0), maxf(_z(chroma), warm), _z(e_crit), _z(_limit * _limit)), 0.004)
	_set4("tint", Vector4(_z(_turbo), _z(e_gold), maxf(_z(e_kick), warm * 3.0), 0.0), 0.004)
	if _warm and wave.y == 0.0:
		wave.y = 0.002
	_set4("wave", wave, 0.002)


## Мелочь — в ноль: тогда ветки шейдера выключаются целиком.
static func _z(x: float) -> float:
	return x if x > 0.003 else 0.0


func _set4(param: String, v: Vector4, eps: float = 0.0) -> void:
	var old = _sent.get(param)
	if old != null and eps > 0.0:
		var o: Vector4 = old
		if absf(o.x - v.x) < eps and absf(o.y - v.y) < eps and absf(o.z - v.z) < eps and absf(o.w - v.w) < eps:
			# к нулю досылаем точно, чтобы ветки шейдера выключились
			if not ((v.x == 0.0 and o.x != 0.0) or (v.y == 0.0 and o.y != 0.0) or (v.z == 0.0 and o.z != 0.0) or (v.w == 0.0 and o.w != 0.0)):
				return
	_sent[param] = v
	_mat.set_shader_parameter(param, v)


func _set2(param: String, v: Vector2, eps: float) -> void:
	var old = _sent.get(param)
	if old != null and (old as Vector2).distance_to(v) < eps:
		return
	_sent[param] = v
	_mat.set_shader_parameter(param, v)
