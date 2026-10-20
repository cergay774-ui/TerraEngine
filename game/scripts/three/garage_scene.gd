class_name GarageScene
extends RefCounted
## Тёмный гараж в 3D (как на логотипе): полированный бетонный пол с отражениями, рифлёные
## стены, ворота с окном, стена с ключами, тумба с ящиками, шины, лампы-трубки, подвесной
## прожектор над мотором с мягким лучом и пылью в нём, светодиодная лента у пола, тёплое бра
## и неоновая вывеска. Плюс окружение для отражений.
##
## Всё строится один раз в build(); каждый кадр меняются только параметры шейдеров, материалов
## и частиц: узел Driver внутри гаража (подгоняет тень и пятно света под мотор, гасит вспышки)
## и необязательные update()/on_event(), которые EngineView может звать вместе с модулями эффектов.
##
## Пресеты: Low (0) — пол без нормалей и отражений, без луча, пыли, ленты и вывески;
## Medium (1) — луч, пыль, лента, вывеска, отражения ярких ламп в полу (аналитически);
## High/Ultra (2/3) — плюс отражение мотора в полу (марш по глубине экрана, только Vulkan),
## тёплое бра и холодный контровой свет. В OpenGL (compat) всё, кроме отражения мотора.

# ключевой прожектор: где висит и куда смотрит (мотор стоит в начале координат на полу y = 0)
const KEY_POS := Vector3(2.0, 16.0, 6.0)
const KEY_AIM := Vector3(0.0, 3.0, 0.0)
const BEAM_ANGLE := 25.0       # видимый луч уже самого света — читается как «столб»
const BEAM_LEN := 19.0
const BACK_Z := -17.0
const SIDE_X := 20.0
const HEIGHT := 18.0
# пол на своём слое: заполняющий направленный свет его не трогает
const LAYER_FLOOR := 1 << 18

const LED := Color(1.0, 0.6, 0.26)
const LED_ENERGY := 2.2
const WINDOW := Color(0.6, 0.72, 0.95)
const WINDOW_ENERGY := 2.2
const BULB := Color(1.0, 0.62, 0.28)
const BULB_ENERGY := 7.0
const TUBE_ENERGY := 6.0
const NEON_ORANGE := Color(1.0, 0.5, 0.16)
const NEON_BLUE := Color(0.4, 0.7, 1.0)
const NEON_ENERGY := 3.4
const NEON_SCALE := 0.85
const BEAM_COL := Color(1.0, 0.85, 0.62)
const BEAM_GOLD := Color(1.0, 0.76, 0.3)


static func environment(quality: int, glow: bool) -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.012, 0.013, 0.017)
	var sky := Sky.new()
	var pano := PanoramaSkyMaterial.new()
	pano.panorama = _studio_panorama()
	pano.energy_multiplier = 1.3
	sky.sky_material = pano
	sky.radiance_size = Sky.RADIANCE_SIZE_64  # отражения размытые — большая карта не нужна
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.5
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.1
	env.tonemap_white = 6.0
	env.glow_enabled = glow
	env.glow_intensity = 0.55
	env.glow_strength = 1.0
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	# лёгкая тёплая дымка: дальняя стена мягче, мотор остаётся контрастным
	env.fog_enabled = quality >= 1
	env.fog_light_color = Color(0.075, 0.068, 0.065)
	env.fog_density = 0.0032 if quality >= 2 else 0.0024
	env.fog_sky_affect = 0.0
	return env


## Панорама «студийного» неба: тёмная, с яркими полосами ламп — даёт красивые блики на металле.
static func _studio_panorama() -> Texture2D:
	var w := 256
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBAH)
	for y in h:
		for x in w:
			var v := 0.02 + 0.05 * (1.0 - float(y) / h)
			var c := Color(v, v, v * 1.15)
			# лампы-трубки под потолком
			if y > 14 and y < 22 and (x % 64) > 10 and (x % 64) < 46:
				c = Color(6.0, 5.8, 5.2)
			# тёплый софтбокс сбоку
			if y > 40 and y < 70 and x > 20 and x < 44:
				c = Color(2.2, 1.6, 1.0)
			# холодный контровой свет
			if y > 45 and y < 60 and x > 150 and x < 190:
				c = Color(0.6, 0.9, 1.6)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


static func _noise_tex(freq: float, normal: bool, seed: int = 1, size: int = 512, octaves: int = 5) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = freq
	n.fractal_octaves = octaves
	var t := NoiseTexture2D.new()
	t.noise = n
	t.width = size
	t.height = size
	t.seamless = true
	t.generate_mipmaps = true
	t.as_normal_map = normal
	t.bump_strength = 4.0
	return t


static func material(color: Color, metallic: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = rough
	return m


static func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r * 0.3, color.g * 0.3, color.b * 0.3)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.roughness = 0.4
	return m


static func build(parent: Node3D, floor_y: float, quality: int) -> Dictionary:
	var root := Node3D.new()
	root.name = "Garage"
	parent.add_child(root)
	var g := {"root": root, "q": quality}
	var batch := MeshKit.Batch.new()
	var mats := {
		"wall": material(Color(0.11, 0.115, 0.13), 0.55, 0.45),
		"rib": material(Color(0.15, 0.155, 0.17), 0.7, 0.35),
		"door": material(Color(0.13, 0.135, 0.15), 0.6, 0.4),
		"board": material(Color(0.07, 0.07, 0.08), 0.1, 0.8),
		"chrome": material(Color(0.85, 0.87, 0.9), 1.0, 0.12),
		"cabinet": material(Color(0.09, 0.09, 0.1), 0.6, 0.35),
		"rubber": material(Color(0.03, 0.03, 0.035), 0.0, 0.85),
		"bench": material(Color(0.12, 0.1, 0.09), 0.2, 0.6),
		"can_red": material(Color(0.55, 0.06, 0.05), 0.5, 0.35),
		"can_yel": material(Color(0.8, 0.6, 0.05), 0.5, 0.35),
		"fixture": material(Color(0.05, 0.05, 0.055), 0.8, 0.3),
		"alu": material(Color(0.5, 0.52, 0.55), 0.9, 0.3),
	}
	var tube := _emissive(Color(0.92, 0.96, 1.0), TUBE_ENERGY)
	mats["tube"] = tube
	g["tube_mat"] = tube
	mats["window"] = _emissive(WINDOW, WINDOW_ENERGY)
	mats["led"] = _emissive(LED, LED_ENERGY)
	mats["bulb"] = _emissive(BULB, BULB_ENERGY)

	_build_floor(root, floor_y, quality, g)

	var back_z := BACK_Z
	var side_x := SIDE_X
	var height := HEIGHT
	# стены: задняя и левая, рифлёный металл (справа открыто — там камера при виде спереди)
	batch.add("wall", MeshKit.box(Vector3(side_x * 2, height, 0.4)), Transform3D(Basis.IDENTITY, Vector3(0, floor_y + height * 0.5, back_z)))
	batch.add("wall", MeshKit.box(Vector3(0.4, height, 40)), Transform3D(Basis.IDENTITY, Vector3(-side_x, floor_y + height * 0.5, back_z + 20)))
	var rib_step := 1.2 if quality >= 1 else 2.4
	var x := -side_x + 0.6
	while x < -2.0:
		batch.add("rib", MeshKit.box(Vector3(0.35, height, 0.3)), Transform3D(Basis.IDENTITY, Vector3(x, floor_y + height * 0.5, back_z + 0.3)))
		x += rib_step
	var z := back_z + 0.6
	while z < back_z + 38.0:
		batch.add("rib", MeshKit.box(Vector3(0.3, height, 0.35)), Transform3D(Basis.IDENTITY, Vector3(-side_x + 0.3, floor_y + height * 0.5, z)))
		z += rib_step
	# гаражные ворота справа на задней стене + окно-полоса (как на логотипе)
	var door_x0 := 0.0
	var door_w := 17.0
	for k in 14:
		var y := floor_y + 0.4 + k * 0.85
		batch.add("door", MeshKit.rounded_box(Vector3(door_w, 0.7, 0.35), 0.12, 3), Transform3D(Basis.IDENTITY, Vector3(door_x0 + door_w * 0.5, y, back_z + 0.4)))
	batch.add("window", MeshKit.box(Vector3(door_w * 0.7, 0.9, 0.2)), Transform3D(Basis.IDENTITY, Vector3(door_x0 + door_w * 0.5, floor_y + 10.6, back_z + 0.62)))
	batch.add("rib", MeshKit.box(Vector3(0.6, 13.0, 0.6)), Transform3D(Basis.IDENTITY, Vector3(door_x0, floor_y + 6.5, back_z + 0.5)))

	# стена с ключами слева
	batch.add("board", MeshKit.rounded_box(Vector3(10.0, 6.0, 0.25), 0.1, 2), Transform3D(Basis.IDENTITY, Vector3(-10.0, floor_y + 8.5, back_z + 0.55)))
	if quality >= 1:
		for k in 9:
			var wl := 3.2 - k * 0.22
			var wx := -14.0 + k * 0.85
			var top := floor_y + 10.6
			_wrench(batch, Vector3(wx, top - wl * 0.5, back_z + 0.75), wl)
		for k in 4:
			batch.add("can_red", MeshKit.rounded_box(Vector3(0.35, 1.8, 0.35), 0.1, 2), Transform3D(Basis.IDENTITY, Vector3(-6.6 + k * 0.6, floor_y + 7.4, back_z + 0.8)))
	# тумба с ящиками
	var cab := Vector3(-11.0, floor_y, back_z + 2.4)
	batch.add("cabinet", MeshKit.rounded_box(Vector3(7.0, 5.0, 3.0), 0.2, 3), Transform3D(Basis.IDENTITY, cab + Vector3(0, 2.8, 0)))
	for k in 5:
		var dy := 1.1 + k * 0.85
		batch.add("rib", MeshKit.rounded_box(Vector3(6.6, 0.72, 0.15), 0.06, 2), Transform3D(Basis.IDENTITY, cab + Vector3(0, dy, 1.52)))
		batch.add("chrome", MeshKit.rounded_box(Vector3(3.5, 0.12, 0.15), 0.05, 2), Transform3D(Basis.IDENTITY, cab + Vector3(0, dy + 0.15, 1.65)))
	for sx in [-3.0, 3.0]:
		batch.add("rubber", MeshKit.cyl(0.3, 0.3, 12), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), cab + Vector3(sx, 0.3, 1.0)))
	# канистры на тумбе
	batch.add("can_red", MeshKit.rounded_box(Vector3(1.2, 1.6, 0.8), 0.15, 3), Transform3D(Basis.IDENTITY, cab + Vector3(-2.0, 6.1, 0)))
	batch.add("can_yel", MeshKit.cyl(0.45, 1.3, 16), Transform3D(Basis.IDENTITY, cab + Vector3(0.0, 5.95, 0.3)))
	batch.add("can_yel", MeshKit.cyl(0.45, 1.3, 16), Transform3D(Basis.IDENTITY, cab + Vector3(1.1, 5.95, -0.2)))

	# верстак справа и шины
	var bench := Vector3(14.0, floor_y, back_z + 6.0)
	batch.add("bench", MeshKit.rounded_box(Vector3(6.0, 0.35, 10.0), 0.08, 2), Transform3D(Basis.IDENTITY, bench + Vector3(0, 3.6, 0)))
	for c in [Vector3(-2.6, 0, -4.6), Vector3(2.6, 0, -4.6), Vector3(-2.6, 0, 4.6), Vector3(2.6, 0, 4.6)]:
		batch.add("cabinet", MeshKit.box(Vector3(0.3, 3.6, 0.3)), Transform3D(Basis.IDENTITY, bench + c + Vector3(0, 1.8, 0)))
	var tire := TorusMesh.new()
	tire.inner_radius = 0.9
	tire.outer_radius = 1.7
	tire.rings = 24
	tire.ring_segments = 12
	for k in 3:
		batch.add("rubber", tire, Transform3D(Basis.IDENTITY.scaled(Vector3(1, 0.7, 1)), Vector3(9.0, floor_y + 0.42 + k * 0.82, back_z + 3.0)))
	batch.add("rubber", tire, Transform3D(Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3(1, 1, 0.7)), Vector3(16.5, floor_y + 1.7, back_z + 13.0)))

	# светильники: трубки в тёмных отражателях на подвесах
	for lx in [-8.0, 6.0]:
		var c := Vector3(lx, floor_y + 15.5, back_z + 9.0)
		batch.add("tube", MeshKit.rounded_box(Vector3(7.0, 0.22, 0.32), 0.1, 2), Transform3D(Basis.IDENTITY, c))
		batch.add("fixture", MeshKit.rounded_box(Vector3(7.6, 0.28, 0.9), 0.08, 2), Transform3D(Basis.IDENTITY, c + Vector3(0, 0.24, 0)))
		for sx in [-2.8, 2.8]:
			batch.add("fixture", MeshKit.cyl(0.03, height - 15.6, 4), Transform3D(Basis.IDENTITY, c + Vector3(sx, (height - 15.6) * 0.5 + 0.3, 0)))
	# подвесной прожектор над мотором: абажур, светящийся диск, трос
	var dir := (KEY_AIM - KEY_POS).normalized()
	var kp := KEY_POS + Vector3(0, floor_y, 0)
	batch.add("fixture", MeshKit.cone(1.25, 0.32, 1.1, 24, false), Transform3D(MeshKit.align_y(-dir), kp - dir * 0.15))
	batch.add("bulb", MeshKit.cyl(1.05, 0.06, 20), Transform3D(MeshKit.align_y(-dir), kp + dir * 0.32))
	var cable := height + 2.0 - KEY_POS.y
	batch.add("fixture", MeshKit.cyl(0.035, cable, 4), Transform3D(Basis.IDENTITY, kp + Vector3(0, cable * 0.5 + 0.4, 0)))
	# тёплое бра на стене между доской и воротами
	var sconce := Vector3(-2.4, floor_y + 9.6, back_z + 0.75)
	batch.add("fixture", MeshKit.rounded_box(Vector3(0.9, 1.25, 0.35), 0.12, 2), Transform3D(Basis.IDENTITY, sconce))
	batch.add("bulb", MeshKit.rounded_box(Vector3(0.62, 0.95, 0.3), 0.14, 2), Transform3D(Basis.IDENTITY, sconce + Vector3(0, 0, 0.12)))
	for k in 3:
		batch.add("fixture", MeshKit.box(Vector3(0.75, 0.06, 0.08)), Transform3D(Basis.IDENTITY, sconce + Vector3(0, -0.3 + k * 0.3, 0.3)))
	# светодиодная лента вдоль низа стен (тёплый ободок; в полированном полу — отражение)
	if quality >= 1:
		batch.add("alu", MeshKit.box(Vector3(19.0, 0.16, 0.16)), Transform3D(Basis.IDENTITY, Vector3(-10.4, floor_y + 0.42, back_z + 0.6)))
		batch.add("led", MeshKit.box(Vector3(19.0, 0.07, 0.05)), Transform3D(Basis.IDENTITY, Vector3(-10.4, floor_y + 0.36, back_z + 0.7)))
		batch.add("alu", MeshKit.box(Vector3(0.16, 0.16, 36.0)), Transform3D(Basis.IDENTITY, Vector3(-side_x + 0.6, floor_y + 0.42, back_z + 19.2)))
		batch.add("led", MeshKit.box(Vector3(0.05, 0.07, 36.0)), Transform3D(Basis.IDENTITY, Vector3(-side_x + 0.7, floor_y + 0.36, back_z + 19.2)))

	# обстановка гаража тени не отбрасывает: стоит у стен, а проход теней дорогой
	for mi in batch.commit(root, mats):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	if quality >= 1:
		_build_beam(root, quality, g)
		_build_wash(root, floor_y)
		_build_dust(root, quality, g)
		_build_neon(root, floor_y, quality, g)
	_halo(root, sconce + Vector3(0, 0, -0.1), Basis.IDENTITY, 6.0, Color(1.0, 0.6, 0.3), 0.22 if quality >= 1 else 0.16)

	# свет: ключевой прожектор сверху с тенью, заполняющий, контровой
	var key: Light3D
	if quality >= 1:
		var spot := SpotLight3D.new()
		spot.light_energy = 11.0
		spot.spot_range = 60.0
		# широкий конус с плоской серединой: мотор освещён ровно, край пятна уходит за кадр,
		# а мягкое «пятно на полу» рисует сам пол (pool в шейдере)
		spot.spot_angle = 48.0
		spot.spot_angle_attenuation = 1.6
		key = spot
	else:
		# на «Низком» — направленный свет: в упрощённом рендере он идёт в основном проходе,
		# а прожектор добавляет ещё по проходу на каждую деталь (для слабых телефонов это много)
		var dl := DirectionalLight3D.new()
		dl.light_energy = 1.5
		key = dl
	key.light_color = Color(1.0, 0.93, 0.82)
	key.shadow_enabled = quality >= 1
	key.shadow_blur = 1.5 if quality >= 2 else 0.8
	key.position = kp
	key.look_at_from_position(key.position, KEY_AIM + Vector3(0, floor_y, 0), Vector3.UP)
	root.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.75, 0.8, 1.0)
	fill.light_energy = 0.35
	fill.rotation_degrees = Vector3(-35, 40, 0)
	fill.light_cull_mask = 0xFFFFF & ~LAYER_FLOOR   # пол светлеет только под прожектором
	root.add_child(fill)
	var rim := OmniLight3D.new()
	rim.light_color = Color(0.35, 0.55, 1.0)
	rim.light_energy = 3.0
	rim.omni_range = 18.0
	rim.visible = quality >= 2
	rim.position = Vector3(-6.0, floor_y + 9.0, back_z + 3.0)
	root.add_child(rim)
	if quality >= 2:
		# тёплый практический свет у бра: пятно на рифлёной стене даёт глубину
		var warm := OmniLight3D.new()
		warm.light_color = Color(1.0, 0.58, 0.26)
		warm.light_energy = 3.5
		warm.omni_range = 9.0
		warm.omni_attenuation = 1.6
		warm.position = sconce + Vector3(0, 0, 1.1)
		root.add_child(warm)
	g["key"] = key

	var drv := Driver.new()
	drv.name = "GarageDriver"
	drv.g = g
	root.add_child(drv)
	return g


# ---------------------------------------------------------------------
# Шейдеры. В OpenGL (compat) картинка считается в гамма-пространстве: свои константы
# (заданные в линейном) переводим туда, иначе всё выходит заметно темнее, чем в Vulkan.
# ---------------------------------------------------------------------

static func _compat() -> bool:
	return RenderingServer.get_current_rendering_method() == "gl_compatibility"


static func _shader(code: String, defs: String = "") -> Shader:
	var sh := Shader.new()
	sh.code = ("#define COMPAT\n" if _compat() else "") + defs + code
	return sh


static func _lin(c: Color, energy: float) -> Vector3:
	var l := c.srgb_to_linear()
	return Vector3(l.r, l.g, l.b) * energy


# ---------------------------------------------------------------------
# Пол: полированный бетон
# ---------------------------------------------------------------------

const FLOOR_SHADER := """
shader_type spatial;
render_mode cull_back;

uniform sampler2D n_big : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D n_fine : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
#ifdef NORMALS
uniform sampler2D n_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
#endif
uniform vec3 base_col = vec3(0.07, 0.066, 0.062);
uniform float joint_step = 15.0;
uniform vec2 joint_ofs = vec2(7.5, 7.5);
uniform float rough_lo = 0.1;
uniform float rough_hi = 0.34;
// пятно масла под мотором: центр xz, полуоси
uniform vec4 oil = vec4(0.0, 0.0, 3.0, 1.6);
// светлый круг под прожектором (центр xz, внутренний и внешний радиус): снаружи пол темнее
uniform vec4 pool = vec4(0.0, 0.0, 9.0, 24.0);
#ifdef REFL
// отражения ярких источников (лента, окно ворот, бра) — считаются аналитически, без зонда
uniform float back_z = -16.3;
uniform float left_x = -19.3;
uniform vec4 led_back = vec4(-19.9, -0.9, 0.325, 0.395);
uniform vec4 led_left = vec4(-15.8, 20.2, 0.325, 0.395);
uniform vec4 win = vec4(2.55, 14.45, 10.15, 11.05);
uniform vec4 sconce = vec4(-2.71, -2.09, 9.12, 10.08);
uniform vec3 led_col = vec3(2.4, 0.8, 0.15);
uniform vec3 win_col = vec3(0.7, 1.05, 1.95);
uniform vec3 sconce_col = vec3(7.0, 2.4, 0.45);
uniform float refl_gain = 1.0;
// габариты мотора: заслоняет отражения позади себя
uniform vec3 occ_min = vec3(-4.0, 0.0, -2.5);
uniform vec3 occ_max = vec3(4.0, 7.0, 2.5);
#endif

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

#ifdef REFL
// доля прямоугольника [u0,u1]x[y0,y1], попавшая в квадратик размытия ±s вокруг точки q
float box_cov(vec2 q, vec4 rc, float s) {
	float a = clamp(min(q.x + s, rc.y) - max(q.x - s, rc.x), 0.0, 2.0 * s) / (2.0 * s);
	float b = clamp(min(q.y + s, rc.w) - max(q.y - s, rc.z), 0.0, 2.0 * s) / (2.0 * s);
	return a * b;
}

float occluded(vec3 ro, vec3 rd, float tmax) {
	vec3 inv = 1.0 / rd;
	vec3 t0 = (occ_min - ro) * inv;
	vec3 t1 = (occ_max - ro) * inv;
	vec3 tn = min(t0, t1);
	vec3 tf = max(t0, t1);
	float a = max(max(tn.x, tn.y), tn.z);
	float b = min(min(tf.x, tf.y), tf.z);
	return (b > max(a, 0.0) && a < tmax) ? 1.0 : 0.0;
}
#endif

void fragment() {
	vec2 p = wp.xz;
	float big = texture(n_big, p * 0.011).r;
	float mid = texture(n_big, p * 0.047 + vec2(0.31, 0.77)).r;
	float fine = texture(n_fine, p * 0.23).r;
	// затирка: крупные пятна светлее/темнее, мелкое зерно, светлые зёрна заполнителя
	float trowel = big * 0.6 + mid * 0.4;
	vec3 c = base_col * (0.65 + 0.7 * trowel);
	c *= 0.86 + 0.28 * fine;
	float speck = smoothstep(0.74, 0.82, fine);
	c = mix(c, base_col * 1.8, speck * 0.25);
	// пропилы-швы плит (сглажены по fwidth — не мерцают на дальнем плане)
	vec2 jq = abs(fract((p + joint_ofs) / joint_step + 0.5) - 0.5) * joint_step;
	float jd = min(jq.x, jq.y);
	float fw = max(fwidth(jd), 1e-4);
	float joint = 1.0 - smoothstep(0.025, 0.025 + fw * 1.5, jd);
	float grime = 1.0 - smoothstep(0.0, 0.35, jd);
	c *= 1.0 - 0.12 * grime;
	c *= 1.0 - 0.55 * joint;
	float r = mix(rough_lo, rough_hi, smoothstep(0.3, 0.72, trowel));
	r += (fine - 0.5) * 0.12;
	r = mix(r, 0.85, joint);
	// масляное пятно — темнее и глаже
	vec2 od = (p - oil.xy) / oil.zw;
	float o = 1.0 - smoothstep(0.35, 1.0 + 0.35 * (mid - 0.5), length(od));
	c *= 1.0 - 0.55 * o;
	r = mix(r, 0.07, o * 0.85);
	// вне светлого круга пол темнее: свет собирается на моторе
	float out_pool = smoothstep(pool.z, pool.w, length(p - pool.xy));
	c *= mix(1.0, 0.4, out_pool);
#ifdef COMPAT
	c = pow(c, vec3(0.4545));
#endif
	ALBEDO = c;
	ROUGHNESS = clamp(r, 0.05, 1.0);
	SPECULAR = 0.5 * mix(1.0, 0.6, out_pool);
	METALLIC = 0.0;
#ifdef NORMALS
	vec3 nm = texture(n_nrm, p * 0.09).xyz;
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = 0.2 * (1.0 - o);
#else
	vec3 nm = vec3(0.5, 0.5, 1.0);
#endif
#ifdef REFL
	vec3 v = normalize(wp - CAMERA_POSITION_WORLD);
	// лёгкая рябь полировки: отражение чуть «плывёт»
	vec3 rd = vec3(v.x + (nm.x - 0.5) * 0.06, -v.y, v.z + (nm.y - 0.5) * 0.06);
	float fres = 0.04 + 0.96 * pow(1.0 - clamp(-v.y, 0.0, 1.0), 5.0);
	float gloss = 1.0 - smoothstep(0.08, 0.5, r);
	vec3 e = vec3(0.0);
	// размытие растёт с шероховатостью и с расстоянием до источника
	float k = 0.012 + r * 0.32;
	if (rd.z < -1e-4) {
		float t = (back_z - wp.z) / rd.z;
		vec3 h = wp + rd * t;
		float s = 0.015 + t * k;
		float vis = 1.0 - occluded(wp, rd, t);
		e += led_col * box_cov(h.xy, led_back, s);
		e += (win_col * box_cov(h.xy, win, s) + sconce_col * box_cov(h.xy, sconce, s)) * vis;
	}
	if (rd.x < -1e-4) {
		float t = (left_x - wp.x) / rd.x;
		vec3 h = wp + rd * t;
		float s = 0.015 + t * k;
		e += led_col * box_cov(h.zy, led_left, s);
	}
	e *= fres * gloss * refl_gain;
#ifdef COMPAT
	e = pow(e, vec3(0.4545));
#endif
	EMISSION = e;
#endif
}
"""

const CONTACT_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

// мягкая тень-«подложка» под мотором: чёрный с прозрачностью (работает одинаково везде)
uniform float strength = 0.7;

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	// «суперэллипс»: широкая полутень + плотное ядро под самым мотором, к краю квада — ноль
	float r = pow(pow(abs(q.x), 3.0) + pow(abs(q.y), 3.0), 1.0 / 3.0);
	float broad = 1.0 - smoothstep(0.15, 1.0, r);
	broad *= broad;
	float core = 1.0 - smoothstep(0.0, 0.55, r);
	float a = clamp((broad * 0.45 + core * 0.4) * strength, 0.0, 0.95);
#ifdef COMPAT
	a = 1.0 - pow(1.0 - a, 0.4545);
#endif
	ALBEDO = vec3(0.0);
	ALPHA = a;
}
"""

const SSR_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

// Отражение мотора в полированном полу: короткий марш луча по глубине экрана
// (одна площадка вокруг мотора, ~22 выборки глубины на пиксель, только High/Ultra в Vulkan).
uniform sampler2D scr : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D dep : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D n_big : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float strength = 0.8;
uniform float max_dist = 16.0;
uniform float thickness = 2.5;
uniform vec2 center = vec2(0.0);
uniform vec2 radius = vec2(9.0, 16.0);

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 view_at(vec2 uv, mat4 inv_proj) {
	float d = textureLod(dep, uv, 0.0).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return v.xyz / v.w;
}

vec2 to_uv(vec3 pv, mat4 proj) {
	vec4 c = proj * vec4(pv, 1.0);
	return c.xy / c.w * 0.5 + 0.5;
}

void fragment() {
	vec3 P = VERTEX;
	vec3 V = normalize(P);
	vec3 N = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	vec3 R = normalize(reflect(V, N));
	const int STEPS = 18;
	float st = max_dist / float(STEPS);
	float t = st * 0.5;
	float hit = 0.0;
	float ht = 0.0;
	vec2 huv = vec2(0.0);
	for (int i = 0; i < STEPS; i++) {
		vec3 q = P + R * t;
		vec2 uv = to_uv(q, PROJECTION_MATRIX);
		if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
			break;
		}
		vec3 sp = view_at(uv, INV_PROJECTION_MATRIX);
		float dz = sp.z - q.z;
		if (dz > 0.0 && dz < thickness) {
			// уточнение попадания делением пополам
			float a = t - st;
			float b = t;
			for (int k = 0; k < 4; k++) {
				float m = (a + b) * 0.5;
				vec3 qm = P + R * m;
				vec3 sm = view_at(to_uv(qm, PROJECTION_MATRIX), INV_PROJECTION_MATRIX);
				if (sm.z - qm.z > 0.0) {
					b = m;
				} else {
					a = m;
				}
			}
			ht = b;
			vec3 qh = P + R * b;
			huv = to_uv(qh, PROJECTION_MATRIX);
			// уверенность попадания: луч должен прийти к самой поверхности, а не пройти за ней
			hit = 1.0 - 0.7 * smoothstep(1.0, 3.0, abs(view_at(huv, INV_PROJECTION_MATRIX).z - qh.z));
			break;
		}
		t += st;
	}
	if (hit < 0.01) {
		discard;
	}
	vec2 e = smoothstep(vec2(0.0), vec2(0.06), huv) * smoothstep(vec2(1.0), vec2(0.94), huv);
	float fade = e.x * e.y * (1.0 - smoothstep(max_dist * 0.45, max_dist, ht));
	// к краям площадки отражение гаснет, дальше работает обычный пол
	float rd = length((wp.xz - center) / radius);
	fade *= 1.0 - smoothstep(0.55, 1.0, rd);
	// пятна полировки: где пол матовее, отражение слабее и мягче
	float big = texture(n_big, wp.xz * 0.011).r;
	float gloss = 1.0 - smoothstep(0.35, 0.75, big) * 0.6;
	float lod = clamp(ht * 0.12 + (1.0 - gloss) * 1.5, 0.0, 4.0);
	// мягкое размытие: мип-уровень + четыре выборки вокруг (если мипов у копии экрана нет)
	vec2 px = (1.0 + ht * 0.22 + (1.0 - gloss) * 2.0) / VIEWPORT_SIZE;
	vec3 c = textureLod(scr, huv + px * vec2(0.5, 1.0), lod).rgb;
	c += textureLod(scr, huv + px * vec2(-1.0, 0.5), lod).rgb;
	c += textureLod(scr, huv + px * vec2(-0.5, -1.0), lod).rgb;
	c += textureLod(scr, huv + px * vec2(1.0, -0.5), lod).rgb;
	c *= 0.25;
	float fres = 0.6 + 0.4 * pow(1.0 - clamp(dot(-V, N), 0.0, 1.0), 4.0);
	ALBEDO = c;
	ALPHA = clamp(strength * fade * gloss * fres * hit, 0.0, 1.0);
}
"""


static func _build_floor(root: Node3D, floor_y: float, quality: int, g: Dictionary) -> void:
	var big := _noise_tex(0.006, false, 3, 256, 4)
	var m := ShaderMaterial.new()
	m.shader = _shader(FLOOR_SHADER, "#define NORMALS\n#define REFL\n" if quality >= 1 else "")
	m.set_shader_parameter("n_big", big)
	m.set_shader_parameter("n_fine", _noise_tex(0.05, false, 11, 256, 3))
	if quality == 0:
		# на «Низком» пол освещён направленным светом целиком — делаем его темнее
		m.set_shader_parameter("base_col", Vector3(0.042, 0.04, 0.038))
	else:
		m.set_shader_parameter("n_nrm", _noise_tex(0.03, true, 7, 256, 4))
		m.set_shader_parameter("led_col", _lin(LED, LED_ENERGY))
		m.set_shader_parameter("win_col", _lin(WINDOW, WINDOW_ENERGY))
		m.set_shader_parameter("sconce_col", _lin(BULB, BULB_ENERGY))
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(90, 90)
	var fl := MeshInstance3D.new()
	fl.name = "Floor"
	fl.mesh = floor_mesh
	fl.material_override = m
	fl.position = Vector3(0, floor_y, 0)
	fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # ниже пола ничего нет
	fl.layers = LAYER_FLOOR
	root.add_child(fl)
	g["floor_mat"] = m
	g["floor_y"] = floor_y
	# мягкое затемнение под стендом (подгоняется под мотор в fit_contact)
	var cm := ShaderMaterial.new()
	cm.shader = _shader(CONTACT_SHADER)
	cm.render_priority = -2   # сначала тень, поверх неё — отражение
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.orientation = PlaneMesh.FACE_Y
	var contact := MeshInstance3D.new()
	contact.name = "Contact"
	contact.mesh = q
	contact.material_override = cm
	contact.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	contact.position = Vector3(0, floor_y + 0.02, 0)
	contact.scale = Vector3(15.0, 1.0, 9.0)
	root.add_child(contact)
	g["contact"] = contact
	# отражение мотора в полу (High/Ultra, только Vulkan: читает экран и глубину)
	if quality >= 2 and not _compat():
		var sm := ShaderMaterial.new()
		sm.shader = _shader(SSR_SHADER)
		sm.render_priority = -1
		sm.set_shader_parameter("n_big", big)
		sm.set_shader_parameter("strength", 0.9 if quality >= 3 else 0.8)
		var pm := PlaneMesh.new()
		pm.size = Vector2(36, 36)
		var ssr := MeshInstance3D.new()
		ssr.name = "FloorReflection"
		ssr.mesh = pm
		ssr.material_override = sm
		ssr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ssr.position = Vector3(0, floor_y + 0.01, 0)
		ssr.layers = LAYER_FLOOR
		root.add_child(ssr)
		g["ssr"] = ssr
		g["ssr_mat"] = sm


## Подогнать тень под стендом, масляное пятно, светлый круг и отражения под габариты мотора
## (AABB в координатах сцены). Зовёт Driver, когда мотор пересобран.
static func fit_contact(g: Dictionary, box: AABB) -> void:
	if not g.has("contact") or box.size == Vector3.ZERO:
		return
	var c := box.get_center()
	var fy := float(g.floor_y)
	var contact: MeshInstance3D = g.contact
	contact.position = Vector3(c.x, fy + 0.02, c.z)
	contact.scale = Vector3(box.size.x * 1.3 + 3.0, 1.0, box.size.z * 1.3 + 3.0)
	var fm: ShaderMaterial = g.floor_mat
	fm.set_shader_parameter("oil", Vector4(c.x + box.size.x * 0.08, c.z - box.size.z * 0.05, box.size.x * 0.28, box.size.z * 0.25))
	var reach := maxf(box.size.x, box.size.z) * 0.5
	fm.set_shader_parameter("pool", Vector4(c.x, c.z, reach + 2.0, reach + 16.0))
	var shrink := Vector3(box.size.x * 0.12, 0.0, box.size.z * 0.12)
	fm.set_shader_parameter("occ_min", Vector3(box.position.x, fy + 0.4, box.position.z) + shrink)
	fm.set_shader_parameter("occ_max", box.end - shrink - Vector3(0, box.size.y * 0.1, 0))
	if g.has("ssr"):
		var ssr: MeshInstance3D = g.ssr
		ssr.position = Vector3(c.x, fy + 0.01, c.z)
		var sm: ShaderMaterial = g.ssr_mat
		sm.set_shader_parameter("center", Vector2(c.x, c.z))
		sm.set_shader_parameter("radius", Vector2(reach + 5.0, reach + 9.0))
		sm.set_shader_parameter("max_dist", clampf(box.size.y * 1.6, 8.0, 20.0))


# ---------------------------------------------------------------------
# Луч прожектора, пыль в нём, отсветы
# ---------------------------------------------------------------------

const BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 col : source_color = vec3(1.0, 0.85, 0.62);
uniform float strength = 0.05;
uniform vec3 apex = vec3(0.0);
uniform vec3 axis = vec3(0.0, -1.0, 0.0);
uniform float beam_len = 19.0;
uniform float floor_y = 0.0;
uniform sampler2D noise : hint_default_white, filter_linear_mipmap, repeat_enable;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = clamp(dot(wp - apex, axis) / beam_len, 0.0, 1.0);
	// края конуса гаснут: объёмный столб, а не плоский треугольник
	float edge = abs(dot(normalize(NORMAL), normalize(VIEW)));
	edge = edge * edge * (3.0 - 2.0 * edge);
	// ярче у лампы, к полу растворяется
	float along = mix(1.0, 0.25, t) * smoothstep(0.0, 0.06, t);
	float near_floor = smoothstep(floor_y + 0.2, floor_y + 4.5, wp.y);
	// медленно плывущая дымка
	vec2 nq = vec2(wp.x * 0.7 + wp.z * 0.7, wp.y) * 0.045;
	float n1 = texture(noise, nq + vec2(TIME * 0.006, -TIME * 0.004)).r;
	float n2 = texture(noise, nq * 2.3 + vec2(-TIME * 0.011, TIME * 0.007)).r;
	float haze = 0.55 + 1.44 * n1 * n2;
	float a = clamp(strength * edge * along * near_floor * haze, 0.0, 1.0);
#ifdef COMPAT
	a = pow(a, 0.4545) * 0.55;
#endif
	ALBEDO = col;
	ALPHA = a;
}
"""

const DUST_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// пылинка: мягкая точка-билборд, ярко вспыхивает только внутри луча прожектора
uniform vec3 col : source_color = vec3(1.0, 0.86, 0.66);
uniform vec3 apex = vec3(0.0);
uniform vec3 axis = vec3(0.0, -1.0, 0.0);
uniform float tan_a = 0.45;
uniform float glow = 2.6;
uniform float base = 0.04;

varying float lit;

void vertex() {
	vec3 p = MODEL_MATRIX[3].xyz;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	vec3 d = p - apex;
	float t = dot(d, axis);
	float r = length(d - axis * t);
	float cone = t > 0.0 ? 1.0 - smoothstep(tan_a * t * 0.5, tan_a * t * 1.05, r) : 0.0;
	float tw = 0.65 + 0.35 * sin(TIME * (1.3 + fract(float(INSTANCE_ID) * 0.37) * 2.0) + float(INSTANCE_ID) * 2.17);
	lit = (base + glow * cone) * tw;
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float a = max(0.0, 1.0 - dot(q, q));
	a *= a;
	a = clamp(a * COLOR.a, 0.0, 1.0);
#ifdef COMPAT
	a = pow(a, 0.4545);
#endif
	ALBEDO = col * lit;
	ALPHA = a;
}
"""

const WASH_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled, fog_disabled;

// мягкий отсвет ленты на стене: ярко у низа, гаснет кверху и к краям
uniform vec3 col : source_color = vec3(1.0, 0.6, 0.26);
uniform float strength = 0.12;

void fragment() {
	float v = 1.0 - UV.y;
	float a = exp(-v * 5.0) * smoothstep(0.0, 0.08, UV.x) * smoothstep(1.0, 0.92, UV.x);
	a = clamp(a * strength, 0.0, 1.0);
#ifdef COMPAT
	a = pow(a, 0.75);
#endif
	ALBEDO = col;
	ALPHA = a;
}
"""

const HALO_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled, fog_disabled;

// мягкий ореол источника на стене (виден и без свечения, и в OpenGL)
uniform vec3 col : source_color = vec3(1.0, 0.5, 0.15);
uniform float strength = 0.3;

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float a = max(exp(-dot(q, q) * 4.0) - 0.018, 0.0);
	a = clamp(a * strength, 0.0, 1.0);
#ifdef COMPAT
	a = pow(a, 0.75);
#endif
	ALBEDO = col;
	ALPHA = a;
}
"""


static func _build_beam(root: Node3D, quality: int, g: Dictionary) -> void:
	var dir := (KEY_AIM - KEY_POS).normalized()
	var apex := KEY_POS + dir * 0.45
	var m := ShaderMaterial.new()
	m.shader = _shader(BEAM_SHADER)
	var strength := 0.07 if quality >= 2 else 0.055
	m.set_shader_parameter("apex", apex)
	m.set_shader_parameter("axis", dir)
	m.set_shader_parameter("beam_len", BEAM_LEN)
	m.set_shader_parameter("strength", strength)
	m.set_shader_parameter("col", BEAM_COL)
	m.set_shader_parameter("noise", _noise_tex(0.006, false, 5, 128, 3))
	var r0 := tan(deg_to_rad(BEAM_ANGLE)) * BEAM_LEN
	var mesh := MeshKit.cone(r0, 0.35, BEAM_LEN, 40 if quality >= 2 else 24, false)
	mesh.rings = 4
	var beam := MeshInstance3D.new()
	beam.name = "Beam"
	beam.mesh = mesh
	beam.material_override = m
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.transform = Transform3D(MeshKit.align_y(-dir), apex + dir * BEAM_LEN * 0.5)
	root.add_child(beam)
	g["beam_mat"] = m
	g["beam_strength"] = strength


static func _build_wash(root: Node3D, floor_y: float) -> void:
	var m := ShaderMaterial.new()
	m.shader = _shader(WASH_SHADER)
	m.set_shader_parameter("col", LED)
	# задняя стена (слева от ворот) и левая стена
	var spans := [
		[Vector3(-10.4, floor_y + 1.6, BACK_Z + 0.68), Vector2(19.0, 3.2), Basis.IDENTITY],
		[Vector3(-SIDE_X + 0.68, floor_y + 1.6, BACK_Z + 19.2), Vector2(36.0, 3.2), Basis(Vector3.UP, PI * 0.5)],
	]
	for s in spans:
		var q := QuadMesh.new()
		q.size = s[1]
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.transform = Transform3D(s[2], s[0])
		root.add_child(mi)


static func _halo(root: Node3D, pos: Vector3, basis: Basis, size: float, col: Color, strength: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader(HALO_SHADER)
	m.set_shader_parameter("col", col)
	m.set_shader_parameter("strength", strength)
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = Transform3D(basis, pos)
	root.add_child(mi)
	return m


static func _build_dust(root: Node3D, quality: int, g: Dictionary) -> void:
	var dir := (KEY_AIM - KEY_POS).normalized()
	var pset := 1
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root.has_node("G"):
		pset = int(tree.root.get_node("G").settings.get("particles", 1))
	var count: int = [0, 70, 140, 220][clampi(quality, 0, 3)]
	count = int(count * [0.5, 1.0, 1.4][clampi(pset, 0, 2)])
	if count <= 0:
		return
	var p := GPUParticles3D.new()
	p.name = "Dust"
	p.amount = count
	p.lifetime = 16.0
	p.preprocess = 16.0
	p.randomness = 1.0
	p.fixed_fps = 30
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-14, -2, -12), Vector3(28, 22, 24))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(8.0, 6.5, 6.0)
	pm.direction = Vector3(0.3, 0.2, 0.1)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.03
	pm.initial_velocity_max = 0.16
	pm.gravity = Vector3(0, -0.012, 0)
	pm.scale_min = 0.45
	pm.scale_max = 1.5
	# медленное завихрение: пылинки плавают, а не летят по прямой
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 6.0
	pm.turbulence_noise_speed_random = 0.3
	pm.turbulence_influence_min = 0.01
	pm.turbulence_influence_max = 0.04
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0))
	grad.set_color(1, Color(1, 1, 1, 0))
	grad.add_point(0.15, Color(1, 1, 1, 1))
	grad.add_point(0.85, Color(1, 1, 1, 1))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.075, 0.075)
	var dm := ShaderMaterial.new()
	dm.shader = _shader(DUST_SHADER)
	dm.set_shader_parameter("apex", KEY_POS + dir * 0.45)
	dm.set_shader_parameter("axis", dir)
	dm.set_shader_parameter("tan_a", tan(deg_to_rad(BEAM_ANGLE)))
	quad.material = dm
	p.draw_pass_1 = quad
	p.position = Vector3(0.0, 7.5, 0.5)
	root.add_child(p)
	g["dust"] = p


## Неоновая вывеска: шестерня (оранжевая) и молния (голубая, как турбо). Строится в своих
## координатах (плоскость XY, смотрит в +Z), место на стене выбирает place_neon().
static func _build_neon(root: Node3D, floor_y: float, quality: int, g: Dictionary) -> void:
	var node := Node3D.new()
	node.name = "Neon"
	# пока место не выбрано, вывеска крошечная (но рисуется — шейдеры соберутся сразу)
	node.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.001), Vector3(-SIDE_X + 0.8, floor_y + 4.0, -6.0))
	root.add_child(node)
	var gear := PackedVector3Array()
	var n := 180
	var teeth := 10
	for i in n + 1:
		var a := TAU * float(i) / n
		var w := smoothstep(0.25, 0.75, 0.5 + 0.5 * cos(a * teeth))
		var r := 1.55 + 0.38 * w
		gear.append(Vector3(cos(a) * r, sin(a) * r, 0.0))
	var bolt_2d := [Vector2(0.25, 1.05), Vector2(-0.45, -0.05), Vector2(0.05, -0.05), Vector2(-0.3, -1.05),
		Vector2(0.5, 0.15), Vector2(0.0, 0.15), Vector2(0.25, 1.05)]
	var bolt := PackedVector3Array()
	for p in _chaikin(bolt_2d, 2):
		bolt.append(Vector3(p.x, p.y, 0.0))
	var orange := _emissive(NEON_ORANGE, NEON_ENERGY)
	var blue := _emissive(NEON_BLUE, NEON_ENERGY)
	var sides := 6 if quality >= 2 else 4
	for part in [[gear, orange, 0.055], [bolt, blue, 0.05]]:
		var mi := MeshInstance3D.new()
		mi.mesh = MeshKit.sweep(part[0], part[2], sides, false)
		mi.material_override = part[1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mi)
	g["neon"] = node
	g["neon_gear"] = orange
	g["neon_bolt"] = blue
	_halo(node, Vector3(0, 0, -0.2), Basis.IDENTITY, 7.0, Color(1.0, 0.45, 0.12), 0.13)
	_halo(node, Vector3(0, 0, -0.15), Basis.IDENTITY, 3.6, NEON_BLUE, 0.1)
	# места на стенах по порядку предпочтения: [центр, поворот (куда смотрит)]
	var left := Basis(Vector3.UP, PI * 0.5)
	var spots: Array = []
	for z in [-6.0, -8.0, -4.0, -2.0, 2.0, -10.0, 6.0]:
		for y in [4.6, 3.8, 5.8, 7.2]:
			spots.append([Vector3(-SIDE_X + 0.75, floor_y + y, z), left])
	for y in [6.0, 7.6, 9.2]:
		spots.append([Vector3(-17.4, floor_y + y, BACK_Z + 0.75), Basis.IDENTITY])
	# задняя стена под бра, между доской и воротами
	for y in [5.0, 3.4]:
		spots.append([Vector3(-2.6, floor_y + y, BACK_Z + 0.75), Basis.IDENTITY])
	g["neon_spots"] = spots


## Поставить вывеску туда, где она видна в кадре и не задевает мотор. Камера «гуляет»
## (покачивание, облёт после загрузки), поэтому проверяем в позе покоя: точки поворачиваем
## вокруг мотора на текущий угол камеры (yaw). parts — AABB деталей мотора в мире (силуэт
## точнее общего AABB). Если места нет — вывеска прячется.
static func place_neon(g: Dictionary, cam: Camera3D, vp_size: Vector2, box: AABB, parts: Array,
		yaw: float = 0.0, top: float = 0.12) -> void:
	if not g.has("neon") or cam == null or vp_size.x < 2.0:
		return
	var node: Node3D = g.neon
	var pivot := box.get_center()
	var proj := func(p: Vector3) -> Vector2:
		return cam.unproject_position(pivot + (p - pivot).rotated(Vector3.UP, yaw))
	# силуэт мотора на экране: прямоугольники деталей (с запасом)
	var margin := vp_size.y * 0.03
	var rects: Array = []
	for a in parts:
		var ab: AABB = a
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for i in 8:
			var sp: Vector2 = proj.call(ab.position + ab.size * Vector3(i & 1, (i >> 1) & 1, (i >> 2) & 1))
			lo = lo.min(sp)
			hi = hi.max(sp)
		rects.append(Rect2(lo, hi - lo).grow(margin))
	if rects.is_empty():
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for i in 8:
			var sp: Vector2 = proj.call(box.position + box.size * Vector3(i & 1, (i >> 1) & 1, (i >> 2) & 1))
			lo = lo.min(sp)
			hi = hi.max(sp)
		rects.append(Rect2(lo, hi - lo))
	# куда можно: ниже верхней панели интерфейса, выше кнопок, не у самого края
	var allowed := Rect2(vp_size * Vector2(0.04, top), vp_size * Vector2(0.82, 0.7 - top))
	var ui_right := Rect2(vp_size * Vector2(0.74, 0.0), vp_size * Vector2(0.26, 0.25))   # подпись и кнопка «Рентген»
	var rad := 2.0 * NEON_SCALE
	for spot in g.neon_spots:
		var c: Vector3 = spot[0]
		var bas: Basis = spot[1]
		if cam.is_position_behind(pivot + (c - pivot).rotated(Vector3.UP, yaw)):
			continue
		var sp: Vector2 = proj.call(c)
		var r := 0.0
		for off in [Vector3(rad, 0, 0), Vector3(-rad, 0, 0), Vector3(0, rad, 0), Vector3(0, -rad, 0)]:
			r = maxf(r, sp.distance_to(proj.call(c + bas * off)))
		var sq := Rect2(sp - Vector2(r, r), Vector2(r, r) * 2.0)
		if not allowed.encloses(sq) or sq.intersects(ui_right):
			continue
		var free := true
		for rc in rects:
			if (rc as Rect2).intersects(sq):
				free = false
				break
		if free:
			node.transform = Transform3D(bas.scaled(Vector3.ONE * NEON_SCALE), c)
			node.visible = true
			return
	node.visible = false


## AABB видимых деталей мотора (всё под корнем вида, кроме модулей эффектов и света).
static func engine_parts(root: Node) -> Array:
	var out: Array = []
	if root == null:
		return out
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is FxModule:
			continue
		if n is MeshInstance3D and (n as MeshInstance3D).is_visible_in_tree():
			var mi := n as MeshInstance3D
			var ab := mi.global_transform * mi.get_aabb()
			if ab.size.length() < 40.0:   # пол/фон сюда не попадают, но на всякий случай
				out.append(ab)
		for ch in n.get_children():
			stack.append(ch)
	return out


## Скругление ломаной (как гнутая неоновая трубка).
static func _chaikin(pts: Array, iters: int) -> Array:
	var cur := pts.duplicate()
	for it in iters:
		var nxt: Array = [cur[0]]
		for i in cur.size() - 1:
			var a: Vector2 = cur[i]
			var b: Vector2 = cur[i + 1]
			nxt.append(a.lerp(b, 0.25))
			nxt.append(a.lerp(b, 0.75))
		nxt.append(cur[cur.size() - 1])
		cur = nxt
	return cur


# ---------------------------------------------------------------------
# Реакция на игру. Driver зовёт tick() сам; update()/on_event() — необязательные хуки,
# EngineView может звать их рядом с модулями эффектов (тот же словарь st и те же события).
# ---------------------------------------------------------------------

## Каждый кадр: st — тот же словарь, что получают модули эффектов (FxModule.update).
static func update(g: Dictionary, delta: float, st: Dictionary) -> void:
	if g.is_empty():
		return
	var ratio := clampf(float(st.get("ratio", 0.0)), 0.0, 1.2)
	g["turbo"] = bool(st.get("turbo", false))
	g["exhausted"] = bool(st.get("exhausted", false))
	if g.has("dust"):
		# вибрация от оборотов поднимает пыль — пылинки плывут быстрее
		var dust: GPUParticles3D = g.dust
		dust.speed_scale = lerpf(dust.speed_scale, 1.0 + ratio * 2.2, clampf(delta * 2.0, 0.0, 1.0))


## События игры (как FxModule.on_event): мигание ламп от крита, золотая вспышка луча…
static func on_event(g: Dictionary, event_name: String, _data: Dictionary) -> void:
	if g.is_empty():
		return
	match event_name:
		"crit":
			g["flicker"] = 0.35
		"level_up":
			g["gold"] = 1.0
		"upgrade":
			g["gold"] = maxf(float(g.get("gold", 0.0)), 0.5)
		"turbo_start":
			g["kick"] = 1.0


## Внутренние часы гаража (зовёт Driver): мигание трубок и неона, вспышка луча, турбо-молния.
static func tick(g: Dictionary, delta: float) -> void:
	var t: float = float(g.get("t", 0.0)) + delta
	g["t"] = t
	var flick: float = maxf(0.0, float(g.get("flicker", 0.0)) - delta)
	g["flicker"] = flick
	var gold: float = maxf(0.0, float(g.get("gold", 0.0)) - delta * 0.8)
	g["gold"] = gold
	var kick: float = maxf(0.0, float(g.get("kick", 0.0)) - delta * 1.5)
	g["kick"] = kick
	var turbo: float = move_toward(float(g.get("turbo_v", 0.0)), 1.0 if g.get("turbo", false) else 0.0, delta * 3.0)
	g["turbo_v"] = turbo
	# лампы коротко «моргают», когда мотор бьёт по гаражу (крит)
	var f := 1.0
	if flick > 0.0:
		f = 0.3 + 0.7 * _blink(t * 38.0)
	_set_energy(g, "tube_mat", TUBE_ENERGY * f)
	# неон: от перегрева «подсаживается» и мерцает, турбо зажигает молнию ярче
	if g.has("neon_gear"):
		var sag := 1.0
		if g.get("exhausted", false):
			sag = 0.7 + 0.3 * _blink(t * 5.0)
		_set_energy(g, "neon_gear", NEON_ENERGY * f * sag)
		_set_energy(g, "neon_bolt", NEON_ENERGY * f * sag * (1.0 + turbo * 0.9 + kick * 1.5))
	if g.has("beam_mat"):
		var s: float = float(g.beam_strength) * (1.0 + gold * 1.2) * lerpf(0.8, 1.0, f)
		if absf(s - float(g.get("beam_s", -1.0))) > 0.0005:
			g["beam_s"] = s
			var bm: ShaderMaterial = g.beam_mat
			bm.set_shader_parameter("strength", s)
			bm.set_shader_parameter("col", BEAM_COL.lerp(BEAM_GOLD, gold))


static func _set_energy(g: Dictionary, key: String, e: float) -> void:
	var m: StandardMaterial3D = g[key]
	if absf(m.emission_energy_multiplier - e) > 0.01:
		m.emission_energy_multiplier = e


static func _blink(x: float) -> float:
	return 1.0 if fposmod(sin(floor(x) * 12.9898) * 43758.5453, 1.0) > 0.4 else 0.0


static func _wrench(batch: MeshKit.Batch, center: Vector3, length: float) -> void:
	var w := 0.16 + length * 0.03
	batch.add("chrome", MeshKit.rounded_box(Vector3(w, length, 0.08), 0.04, 2), Transform3D(Basis.IDENTITY, center))
	var ring := TorusMesh.new()
	ring.inner_radius = w * 0.9
	ring.outer_radius = w * 1.7
	ring.rings = 12
	ring.ring_segments = 6
	batch.add("chrome", ring, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), center + Vector3(0, length * 0.5, 0)))
	batch.add("chrome", MeshKit.rounded_box(Vector3(w * 2.6, w * 2.2, 0.08), 0.05, 2), Transform3D(Basis.IDENTITY, center - Vector3(0, length * 0.5, 0)))


static var _dot: Texture2D = null

static func _soft_dot() -> Texture2D:
	if _dot != null:
		return _dot
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, y - 15.5).length() / 15.5
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	_dot = ImageTexture.create_from_image(img)
	return _dot


## Узел-«часовой» гаража: подгоняет тень и пятно света под мотор (по fx_bounds() вида)
## и крутит tick() — вспышки и мигания гаснут сами.
class Driver extends Node3D:
	var g: Dictionary = {}
	var _view: Node = null
	var _box := AABB()
	var _place_t := -1.0
	var _place_n := 0
	var _locked := false

	func _ready() -> void:
		var n: Node = get_parent()
		while n != null and not n.has_method("fx_bounds"):
			n = n.get_parent()
		_view = n

	func _process(delta: float) -> void:
		if _view != null and is_instance_valid(_view):
			var b: AABB = _view.call("fx_bounds")
			if b != _box:
				_box = b
				GarageScene.fit_contact(g, b)
				# вывеску переставляем, когда камера уже встала под новый мотор (и ещё пару раз)
				_place_t = 0.15
				_place_n = 3
			# режим гаража: по бокам панели деталей с выносками — вывеску там не показываем
			var lk: bool = _view.get("locked") == true
			if lk != _locked:
				_locked = lk
				_place_t = 0.15
				_place_n = 3
				if lk and g.has("neon"):
					(g.neon as Node3D).visible = false
			if _place_t >= 0.0:
				_place_t -= delta
				# пока камера облетает мотор после загрузки — ждём
				if _place_t < 0.0 and float(_view.get("_intro_t") if _view.get("_intro_t") != null else 0.0) > 0.0:
					_place_t = 0.2
				if _place_t < 0.0 and _locked:
					if g.has("neon"):
						(g.neon as Node3D).visible = false
					_place_n = 0
				elif _place_t < 0.0:
					var vp: SubViewport = _view.call("fx_viewport")
					var yaw := 0.0
					if _view.get("_yaw") != null:
						yaw = float(_view.get("_yaw")) + float(_view.get("_intro_yaw") if _view.get("_intro_yaw") != null else 0.0)
					# на экране новой эпохи сверху крупный заголовок — вывеску держим ниже
					var top := 0.3 if _view.get("demo") == true else 0.12
					var parts := GarageScene.engine_parts(_view.call("fx_root"))
					GarageScene.place_neon(g, _view.call("fx_camera"), Vector2(vp.size), _box, parts, yaw, top)
					_place_n -= 1
					if _place_n > 0:
						_place_t = 0.8
		GarageScene.tick(g, delta)
