extends FxModule
## Постобработка всего 3D-кадра: один шейдер canvas_item на TextureRect, который показывает
## картинку SubViewport (view.fx_display()). Всё в один проход и с малым числом выборок:
##   • грейдинг: мягкий S-контраст, тёплые света / холодные тени, насыщенность, виньетка
##     вокруг мотора, лёгкое повышение резкости (картинка 3D растягивается на экран телефона);
##   • марево: дрожание воздуха над выхлопом и турбиной (сильнее от газа, нагрева и турбо),
##     лёгкое марево по всему кадру и красный пульс по краям при перегреве;
##   • удары: турбо — радиальный «рывок» с размытием и хроматикой, крит — толчок и тёплая
##     вспышка, отсечка — крошечный пульс, уровень — золотая волна.
## Плюс один раз настраивается Environment: тонмаппер, экспозиция, свечение (bloom).
## Low (q=0): только грейдинг и виньетка, без искажений и дополнительных выборок.

const SHADER_BODY := """
uniform vec4 grade = vec4(0.3, 1.1, 0.4, 0.5);   // контраст, насыщенность, виньетка, сплит-тон
uniform vec4 vig = vec4(0.5, 0.45, 0.0, 0.0);    // центр виньетки (uv), сила шарпа
uniform vec4 tail_seg = vec4(-1.0);              // струя выхлопа: начало xy, конец zw (uv)
uniform vec4 turb_pos = vec4(-1.0, -1.0, 0.05, 0.0);  // турбина: xy (uv), z — радиус
uniform vec4 heat = vec4(0.0);    // марево: выхлоп, турбина, весь кадр, перегрев (красный пульс)
uniform vec4 punch = vec4(0.0);   // турбо-рывок, хроматика, крит-вспышка, отсечка
uniform vec4 tint = vec4(0.0);    // турбо (холодный тон), золото уровня
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
	float zoom = punch.x * 0.028 + punch.z * 0.022 + punch.w * 0.006;
	uv = punch_center + (uv - punch_center) * (1.0 - zoom);
	vec2 suv = uv;
#if Q >= 1
	// марево: маска (струя выхлопа + столб над турбиной + общий фон) * шум, бегущий вверх
	vec2 p = uv * asp;
	float m = heat.z;
	if (heat.x > 0.002) {
		vec2 a = tail_seg.xy * asp;
		vec2 ab = tail_seg.zw * asp - a;
		float l2 = max(dot(ab, ab), 1e-6);
		float h = clamp(dot(p - a, ab) / l2, 0.0, 1.0);
		float d = length(p - a - ab * h);
		float w = sqrt(l2) * (0.09 + 0.3 * h);
		m += heat.x * (1.0 - smoothstep(w * 0.25, w, d)) * smoothstep(0.0, 0.12, h) * (1.0 - h * h);
	}
	if (heat.y > 0.002) {
		vec2 tq = (p - turb_pos.xy * asp) / turb_pos.z;
		tq.y += 0.9;   // столб тёплого воздуха поднимается над турбиной
		tq.y *= 0.55;
		m += heat.y * (1.0 - smoothstep(0.35, 1.0, length(tq)));
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
	// резкость: 3D рисуется в меньшем разрешении и растягивается — возвращаем чёткость граням
	if (vig.z > 0.001) {
		vec2 hp = px * 0.5;
		vec3 bl = texture(TEXTURE, suv + hp).rgb + texture(TEXTURE, suv - hp).rgb;
#if Q >= 2
		bl += texture(TEXTURE, suv + vec2(hp.x, -hp.y)).rgb + texture(TEXTURE, suv + vec2(-hp.x, hp.y)).rgb;
		bl *= 0.25;
#else
		bl *= 0.5;
#endif
		c = max(c + (c - bl) * vig.z, vec3(0.0));
	}
	// турбо-рывок: радиальное размытие к мотору
	if (punch.x > 0.01) {
		vec2 dir = (uv - punch_center) * punch.x * 0.07;
		vec3 acc = c;
		for (int i = 1; i <= TAPS; i++) {
			acc += texture(TEXTURE, suv - dir * (float(i) / float(TAPS))).rgb;
		}
		c = acc / float(TAPS + 1);
	}
	// хроматика по краям (рывок, крит, турбо)
	if (punch.y > 0.001) {
		vec2 o = (uv - punch_center) * punch.y * 0.018;
		c.r = texture(TEXTURE, suv + o).r;
		c.b = texture(TEXTURE, suv - o).b;
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
	// виньетка вокруг мотора
	vec2 vd = (UV - vig.xy) * vec2(1.15, 0.82);
	float vr = dot(vd, vd);
	float v = smoothstep(0.06, 0.42, vr);
	c *= 1.0 - v * grade.z;
	// края: перегрев — красный пульс, турбо — синее свечение
	float edge = smoothstep(0.12, 0.5, vr);
	float pulse = heat.w * (0.55 + 0.45 * sin(TIME * 5.2));
	c += vec3(0.75, 0.08, 0.02) * edge * pulse * 0.5;
	c = mix(c, c * vec3(1.12, 0.86, 0.8), heat.w * 0.35);
	c += vec3(0.06, 0.22, 0.6) * edge * tint.x * (0.12 + punch.x * 0.5);
	// крит: тёплая вспышка, сильнее по светлому; отсечка — короткий пульс яркости
	c += vec3(1.0, 0.72, 0.38) * punch.z * (0.08 + 0.5 * l * l);
	c *= 1.0 + punch.w * 0.07;
	// золото уровня — тёплая волна от мотора
	float gd = length((UV - punch_center) * asp);
	c += vec3(1.0, 0.72, 0.22) * tint.y * (1.0 - smoothstep(0.0, 0.55, gd)) * 0.32;
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

static var _noise: Texture2D
static var _shaders: Dictionary = {}

var _mat: ShaderMaterial
var _sent: Dictionary = {}
var _warm: bool = false
var _q: int = 1
# плавные уровни эффектов
var _h_tail: float = 0.0
var _h_turb: float = 0.0
var _h_all: float = 0.0
var _over: float = 0.0
var _turbo: float = 0.0
# импульсы событий (затухают)
var _kick: float = 0.0
var _crit: float = 0.0
var _limit: float = 0.0
var _gold: float = 0.0
var _pop: float = 0.0


func setup() -> void:
	_q = clampi(q(), 0, 3)
	_tune_environment()
	_mat = ShaderMaterial.new()
	_mat.shader = _shader_for(_q)
	if _q >= 1:
		_mat.set_shader_parameter("noise_tex", _noise_texture())
	_sent.clear()
	_set4("grade", _grade())
	_set4("vig", Vector4(0.5, 0.45, [0.0, 0.35, 0.45, 0.5][_q], 0.0))
	view.fx_display().material = _mat


func _grade() -> Vector4:
	# контраст, насыщенность, виньетка, сплит-тон
	return Vector4(0.5, 1.12, 0.55, 0.75)


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


## Тонмаппинг и свечение 3D-картинки (один раз при создании мира).
func _tune_environment() -> void:
	var env: Environment = view.fx_environment()
	if env == null:
		return
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.1
	env.tonemap_white = 6.0


func warmup(on: bool) -> void:
	_warm = on


func on_event(event_name: String, _data: Dictionary) -> void:
	match event_name:
		"turbo_start":
			_kick = 1.0
		"crit":
			_crit = 1.0
		"limiter":
			_limit = 1.0
		"level_up":
			_gold = 1.0
		"upgrade":
			_gold = maxf(_gold, 0.45)
		"gold":
			_gold = maxf(_gold, 0.3)
		"pop":
			_pop = 1.0
		"exhausted":
			_crit = maxf(_crit, 0.35)


func update(delta: float, st: Dictionary) -> void:
	if _mat == null:
		return
	var demo: bool = st.demo
	var ratio: float = st.ratio
	var hot: float = st.heat
	var throttle: bool = st.throttle
	var turbo_on: bool = st.turbo
	var exhausted: bool = st.exhausted
	# цели
	var t_tail := 0.0
	var t_turb := 0.0
	var t_all := 0.0
	if _q >= 1 and not demo and not view.render_paused:
		t_tail = clampf(0.25 + ratio * 0.75 + hot * 0.3, 0.0, 1.3) * (1.0 if throttle else 0.6)
		if turbo_on:
			t_tail *= 1.35
		t_turb = (1.0 if turbo_on else clampf(ratio * 0.45 + hot * 0.25, 0.0, 0.6))
		t_all = 0.35 if exhausted else clampf((hot - 0.75) * 0.8, 0.0, 0.2)
	var k := 1.0 - exp(-delta * 4.0)
	_h_tail = lerpf(_h_tail, t_tail, k)
	_h_turb = lerpf(_h_turb, t_turb, k)
	_h_all = lerpf(_h_all, t_all, 1.0 - exp(-delta * 2.0))
	_over = lerpf(_over, 1.0 if exhausted and not demo else 0.0, 1.0 - exp(-delta * 3.0))
	var turbo_tint := 0.0
	if turbo_on and not demo:
		turbo_tint = clampf(float(st.turbo_t) * 5.0, 0.0, 1.0)
	_turbo = lerpf(_turbo, turbo_tint, 1.0 - exp(-delta * 5.0))
	_kick = maxf(0.0, _kick - delta / 0.55)
	_crit = maxf(0.0, _crit - delta / 0.4)
	_limit = maxf(0.0, _limit - delta / 0.09)
	_gold = maxf(0.0, _gold - delta / 0.9)
	_pop = maxf(0.0, _pop - delta / 0.35)
	if _q == 0:
		_kick = 0.0
	var e_kick := _kick * _kick
	var e_crit := _crit * _crit
	var e_gold := _gold * _gold * (3.0 - 2.0 * _gold)
	# точки на экране
	var has_turb := false
	if _h_tail > 0.002 or _h_turb > 0.002 or _warm:
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
				_set4("turb_pos", Vector4(tu.x, tu.y, maxf(0.01, absf(tu.y - tr.y)), 0.0), 0.0008)
	var center: Vector2 = view.fx_screen_uv(view.fx_center())
	if center.x > -0.5:
		_set2("punch_center", center, 0.002)
	var band: Rect2 = view.band
	_set4("vig", Vector4(band.position.x + band.size.x * 0.5, band.position.y + band.size.y * 0.5,
		[0.0, 0.35, 0.45, 0.5][_q], 0.0), 0.002)
	var warm := 0.004 if _warm else 0.0
	_set4("heat", Vector4(maxf(_h_tail + _pop * 0.7, warm), (_h_turb if has_turb else 0.0) + warm,
		_h_all, _over), 0.004)
	var chroma := e_kick * 1.0 + e_crit * 0.6 + (_turbo * 0.18 if _q >= 2 else 0.0)
	_set4("punch", Vector4(e_kick + warm * 3.0, chroma + warm, e_crit, _limit * _limit), 0.004)
	_set4("tint", Vector4(_turbo, e_gold, 0.0, 0.0), 0.004)


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
