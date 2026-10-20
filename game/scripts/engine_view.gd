extends Control
## Мотор в 3D внутри тёмного гаража. Модель собирается кодом из деталей: блок в разрезе,
## поршни с кольцами, шатуны, коленвал с противовесами, ГБЦ с крышкой и катушками, ремень ГРМ
## со звёздочками, выпускной коллектор (краснеет от нагрева), впускные дудки, турбина с конусным
## фильтром, стенд на колёсиках. Поршни и шатуны считаются по геометрии кривошипа, у каждого
## цилиндра своя фаза по порядку зажигания. Мотор можно покрутить пальцем, зажатие даёт газ.

signal hold_changed(pressed: bool)

const ROD := 3.0
const BORE := 1.12
const HEAD := 1.15
const SPACING := 2.9
const ENGINE_SIZE := 7.0      # мотор любого типа приводится к одному размеру
const FX_MODULES := [
	preload("res://scripts/vfx/post_fx.gd"),
	preload("res://scripts/vfx/exhaust_fx.gd"),
	preload("res://scripts/vfx/sparks_fx.gd"),
	preload("res://scripts/vfx/heat_fx.gd"),
]

var engine_type: String = "inline4"
var material_index: int = 0
var demo: bool = false
var demo_rpm: float = 900.0
var interactive: bool = true
var crank_deg: float = 0.0
var rpm: float = 800.0
var heat: float = 0.0
var shake_offset: Vector2 = Vector2.ZERO
var flash_white: float = 0.0
var show_hud: bool = true
var drives_audio: bool = true
var band: Rect2 = Rect2(0, 0, 1, 1)   # где на экране стоит мотор (доли экрана)
var render_paused: bool = false       # мотор закрыт меню — 3D не перерисовываем (меньше нагрев)
var locked: bool = false              # режим гаража: мотор не крутится пальцем

var _vp: SubViewport
var _tex: TextureRect
var _world: Node3D
var _cam: Camera3D
var _env: Environment
var _root: Node3D
var _engine: Node3D
var _garage: Dictionary = {}
var _hud: Control
var _hud_flash_drawn: float = 0.0
var _ring: ColorRect
var _ring_mat: ShaderMaterial
var _ring_sent := Vector3(-1, -1, -1)   # прогресс, режим, видимость — что уже отправлено шейдеру
var _flash_light: OmniLight3D
var _turbo_pos: Vector3 = Vector3.ZERO
var _has_turbo: bool = false
var _fx: Array = []             # модули эффектов (scripts/vfx), см. FxModule
var _limiter_t: float = 0.0
var _was_turbo: bool = false
var _was_exhausted: bool = false
var _cyls: Array = []
var _spinners: Array = []      # [{node, ratio}] — вращаются вместе с коленвалом
var _rotors: Array = []
var _turbine_wheel: Node3D = null
var _mats: Dictionary = {}
var _built_key: String = ""
var _gfx_key: String = ""
var _center: Vector3 = Vector3.ZERO
var _bounds: AABB = AABB()
var _cam_attr: CameraAttributesPractical = null
const INTRO_TIME := 2.2
var _intro_t: float = 0.0
var _intro_lift: float = 0.0
var _intro_yaw: float = 0.0


## Кинематографичный облёт мотора (после экрана загрузки).
func play_intro() -> void:
	_intro_t = INTRO_TIME
var _yaw: float = 0.0
var _yaw_target: float = 0.0
var _pressed: bool = false
var _time: float = 0.0
var _prev_throttle: bool = false
var _turbine_deg: float = 0.0
var _tint_acc: float = 1.0
var _fov_kick: float = 0.0
var _tail_pos: Vector3 = Vector3.ZERO
var _lift: float = 0.0
var _frame_i: int = 0
var _xray_warmers: Array = []
var _warm_frames: int = 0   # первые кадры после сборки: все эффекты включены — шейдеры компилируются сразу, а не посреди игры
var _anchors: Dictionary = {}     # слот запчасти -> точка на моторе (локально в _engine)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_tex = TextureRect.new()
	_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tex.stretch_mode = TextureRect.STRETCH_SCALE
	_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tex.texture = _vp.get_texture()
	add_child(_tex)
	_world = Node3D.new()
	_vp.add_child(_world)
	_hud = Control.new()
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.draw.connect(_draw_hud)
	add_child(_hud)
	_make_turbo_ring()
	resized.connect(_apply_graphics)
	G.settings_changed.connect(_on_settings)
	_setup_world()
	_rebuild()


func set_engine(type: String, material: int) -> void:
	# пересобираем модель только если она реально изменилась (тип, материал, турбина, гоночный облик):
	# сборка тяжёлая, а уровни/покупки меняют только цвета, их обновляет _update_tints
	var same := type == engine_type and material == material_index and _engine != null and is_instance_valid(_engine)
	engine_type = type
	material_index = material
	if not is_inside_tree():
		return
	if same and _build_key() == _built_key:
		_tint_acc = 1.0
		return
	_rebuild()


func _q() -> int:
	return clampi(int(G.settings.get("quality", 1)), 0, 3)


func _on_settings() -> void:
	if _graphics_key() != _gfx_key:
		Diag.event("смена графики: " + _graphics_key())
		_setup_world()
		_rebuild()
	else:
		_apply_graphics()


func _graphics_key() -> String:
	return "%d|%d|%s|%d" % [_q(), int(G.settings.get("shadows", 1)), str(G.settings.get("garage", true)), int(G.settings.get("particles", 1))]


func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_pressed = event.pressed
		hold_changed.emit(event.pressed)
		accept_event()
	elif event is InputEventMouseMotion and _pressed and not locked:
		_yaw_target = clampf(_yaw_target - event.relative.x * 0.006, -1.0, 1.0)
		accept_event()


# ---------------------------------------------------------------------
# Мир: гараж, свет, частицы
# ---------------------------------------------------------------------

func _setup_world() -> void:
	_gfx_key = _graphics_key()
	for c in _world.get_children():
		_world.remove_child(c)
		c.queue_free()
	_engine = null
	var q := _q()
	var shadows := int(G.settings.get("shadows", 1))
	_env = GarageScene.environment(q, G.settings.get("glow", true))
	var we := WorldEnvironment.new()
	we.environment = _env
	_world.add_child(we)
	_garage = {}
	if G.settings.get("garage", true):
		_garage = GarageScene.build(_world, 0.0, q)
		var key: Light3D = _garage.key
		key.shadow_enabled = shadows > 0
		key.shadow_blur = 2.0 if shadows >= 2 else 0.8
	else:
		var sun := DirectionalLight3D.new()
		sun.light_energy = 1.2
		sun.rotation_degrees = Vector3(-55, 30, 0)
		sun.shadow_enabled = shadows > 0
		_world.add_child(sun)

	_cam = Camera3D.new()
	_cam.fov = 30.0
	_cam.far = 300.0
	_cam_attr = null
	if q >= 2 and RenderingServer.get_current_rendering_method() != "gl_compatibility":
		_cam_attr = CameraAttributesPractical.new()
		_cam_attr.dof_blur_far_enabled = true
		_cam_attr.dof_blur_far_distance = 40.0
		_cam_attr.dof_blur_far_transition = 14.0
		_cam_attr.dof_blur_amount = 0.05 if q == 2 else 0.07
		_cam.attributes = _cam_attr
	_world.add_child(_cam)
	_root = Node3D.new()
	_world.add_child(_root)

	_flash_light = _omni(Color(1.0, 0.55, 0.15), 6.0)
	_fx.clear()
	for scr in FX_MODULES:
		var m: FxModule = scr.new()
		m.view = self
		_root.add_child(m)
		m.setup()
		_fx.append(m)
	_apply_graphics()


func _omni(color: Color, rng: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.omni_range = rng
	l.light_energy = 0.0
	l.shadow_enabled = false
	_root.add_child(l)
	return l


func _apply_graphics() -> void:
	if _vp == null or size.x < 2.0:
		return
	# res_scale считается от логического размера экрана (720 по ширине); больше 1 — значит
	# рисовать чётче, вплоть до настоящего разрешения экрана (на флагманах оно в 2 раза выше)
	var sc := clampf(float(G.settings.get("res_scale", 1.0)), 0.4, 2.0)
	if sc > 1.0:
		var phys := float(get_window().size.y) / maxf(get_viewport_rect().size.y, 1.0)
		sc = minf(sc, maxf(1.0, phys))
	_vp.size = Vector2i(maxi(16, int(size.x * sc)), maxi(16, int(size.y * sc)))
	_vp.positional_shadow_atlas_size = 2048 if _q() >= 2 else 1024
	# сглаживание: в Vulkan на телефонах MSAA почти бесплатно (тайловые видеокарты); в
	# запасном OpenGL на Android у MSAA отдельный путь с утечкой памяти — там выключено
	var compat := RenderingServer.get_current_rendering_method() == "gl_compatibility"
	var q := _q()
	if compat:
		_vp.msaa_3d = Viewport.MSAA_DISABLED
		_vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	else:
		_vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_4X][q]
		_vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	if _env != null:
		_env.glow_enabled = G.settings.get("glow", true)
	_tex.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


# ---------------------------------------------------------------------
# Материалы
# ---------------------------------------------------------------------

func _mat(color: Color, metallic: float = 0.6, rough: float = 0.4, alpha: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.metallic = metallic
	m.roughness = rough
	m.metallic_specular = 0.6
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# все детали построены лицом наружу — задние грани можно отсекать (меньше нагрузка)
	m.cull_mode = BaseMaterial3D.CULL_BACK
	return m


func _make_mats() -> void:
	var md: Dictionary = D.MATERIALS[material_index % D.MATERIALS.size()]
	var mc: Color = md.color
	var shine: float = md.shine
	var racing := _built_key.split("|")[3] == "1"
	var exp_look := engine_type == "experimental"
	_mats = {
		"block": _mat(mc.lightened(0.05), 0.45 + shine * 0.45, 0.5 - shine * 0.3),
		"case": _mat(mc.darkened(0.1), 0.4 + shine * 0.4, 0.5, 0.5),
		"head": _mat(mc.lightened(0.15), 0.5 + shine * 0.45, 0.4 - shine * 0.2),
		"cover": _mat(Color("b81d1d") if racing else (Color("1b1c20") if not exp_look else Color("d8dde3")), 0.55 if racing else 0.3, 0.3 if racing else 0.55),
		"bore": _mat(Color("1a1b1f"), 0.3, 0.6),
		"piston": _mat(Color("d4d9df"), 0.95, 0.18),
		"rod": _mat(Color("9aa1a9"), 0.95, 0.25),
		"crank": _mat(Color("6f767e"), 0.95, 0.28),
		"steel": _mat(Color("c8ced6"), 1.0, 0.12),
		"plug": _mat(Color("efe9da"), 0.1, 0.35),
		"header": _mat(Color("8a8a8f"), 0.95, 0.3),
		"coil": _mat(Color("c01818") if racing else Color("161618"), 0.3, 0.4),
		"stand": _mat(Color("c4471b"), 0.5, 0.35),
		"rubber": _mat(Color("0d0d0f"), 0.0, 0.8),
		"belt": _mat(Color("101012"), 0.1, 0.7),
		"filter": _mat(Color("1d4fa8"), 0.7, 0.3),
		"airfilter": _mat(Color("16171a"), 0.2, 0.75),
		"accent": _mat(Color(0.3, 1.0, 0.9), 0.2, 0.3),
		"brass": _mat(Color("c9a050"), 1.0, 0.25),
		"flash": _mat(Color(1.0, 0.55, 0.15), 0.0, 1.0, 0.0),
	}
	var fm: StandardMaterial3D = _mats.flash
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var ac: StandardMaterial3D = _mats.accent
	ac.emission_enabled = true
	ac.emission = Color(0.3, 1.0, 0.9)
	ac.emission_energy_multiplier = 3.0
	var hd: StandardMaterial3D = _mats.header
	hd.emission_enabled = true
	hd.emission = Color.BLACK
	# свечение у этих материалов включено всегда (просто чёрное, когда не нужно):
	# переключение emission_enabled на лету заставляет движок заново компилировать шейдеры,
	# на телефоне это секундные зависания
	for k in ["block", "head", "piston", "crank"]:
		var em: StandardMaterial3D = _mats[k]
		em.emission_enabled = true
		em.emission = Color.BLACK
	if md.get("weave", false):
		var w := _weave_tex()
		# у процедурных сеток нет UV — карбоновое плетение кладём трипланарно
		for k in ["block", "head", "cover"]:
			var wm: StandardMaterial3D = _mats[k]
			wm.albedo_texture = w
			wm.uv1_triplanar = true
			wm.uv1_scale = Vector3(0.6, 0.6, 0.6)
	# вспышка и полупрозрачный картер видны с обеих сторон
	for k in ["flash", "case"]:
		var m: StandardMaterial3D = _mats[k]
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_dress_mats(md)


## Фактура поверх базовых цветов: литьё (мелкая шероховатая рябь на блоке и головке),
## разброс шероховатости, лак на крышке и стенде, контровой блик по краям металла.
## Включается с «Среднего»; на «Низком» материалы остаются простыми.
func _dress_mats(md: Dictionary) -> void:
	var q := _q()
	if q < 1:
		return
	var cast_n := _cast_normal()
	var rough_n := _rough_noise()
	var weave: bool = md.get("weave", false)
	for k in ["block", "head", "case"]:
		var m: StandardMaterial3D = _mats[k]
		if not weave:
			m.normal_enabled = true
			m.normal_texture = cast_n
			m.normal_scale = 0.55
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(0.9, 0.9, 0.9)
		if q >= 2:
			m.roughness_texture = rough_n
			m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	# окрашенное и лакированное: крышка клапанов, катушки, стенд, фильтр
	for k in ["cover", "coil", "stand", "filter"]:
		var m: StandardMaterial3D = _mats[k]
		m.clearcoat_enabled = true
		m.clearcoat = 0.75
		m.clearcoat_roughness = 0.12
	# полированный и точёный металл: контровой блик по краям
	for k in ["piston", "rod", "crank", "steel", "brass", "header"]:
		var m: StandardMaterial3D = _mats[k]
		m.rim_enabled = true
		m.rim = 0.25
		m.rim_tint = 0.7
		if q >= 2:
			m.roughness_texture = rough_n
			m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN


static var _cast_n_tex: NoiseTexture2D
static var _rough_tex: NoiseTexture2D


static func _cast_normal() -> NoiseTexture2D:
	if _cast_n_tex == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 0.09
		n.fractal_octaves = 4
		n.seed = 7
		_cast_n_tex = NoiseTexture2D.new()
		_cast_n_tex.noise = n
		_cast_n_tex.width = 256
		_cast_n_tex.height = 256
		_cast_n_tex.seamless = true
		_cast_n_tex.as_normal_map = true
		_cast_n_tex.bump_strength = 6.0
		_cast_n_tex.generate_mipmaps = true
	return _cast_n_tex


static func _rough_noise() -> NoiseTexture2D:
	if _rough_tex == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_PERLIN
		n.frequency = 0.02
		n.fractal_octaves = 3
		n.seed = 3
		_rough_tex = NoiseTexture2D.new()
		_rough_tex.noise = n
		_rough_tex.width = 256
		_rough_tex.height = 256
		_rough_tex.seamless = true
		_rough_tex.generate_mipmaps = true
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.55, 0.65, 0.6))
		ramp.set_color(1, Color(1.0, 1.0, 1.0))
		_rough_tex.color_ramp = ramp
	return _rough_tex


func _weave_tex() -> Texture2D:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var on := ((x / 4) + (y / 4)) % 2 == 0
			var stripe := (x + (y if on else -y)) % 4 == 0
			var v := 0.45 + (0.25 if on else 0.0) + (0.12 if stripe else 0.0)
			img.set_pixel(x, y, Color(v, v, v))
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------------
# Раскладка цилиндров
# ---------------------------------------------------------------------

func _spec() -> Dictionary:
	return D.ENGINES.get(engine_type, D.ENGINES.inline4)


func _layout() -> Array:
	var c: Array = []
	match engine_type:
		"single":
			c.append({"row": 0, "bank": 0.0, "tdc": 0.0})
		"inline4", "diesel":
			var tdc := [0.0, 540.0, 180.0, 360.0]  # порядок 1-3-4-2
			for i in 4:
				c.append({"row": i, "bank": 0.0, "tdc": tdc[i]})
		"boxer":
			for row in 2:
				c.append({"row": row, "bank": -90.0, "tdc": row * 180.0})
				c.append({"row": row, "bank": 90.0, "tdc": row * 180.0 + 360.0})
		"v6":
			for row in 3:
				c.append({"row": row, "bank": -30.0, "tdc": row * 240.0})
				c.append({"row": row, "bank": 30.0, "tdc": row * 240.0 + 120.0})
		"v8":
			for row in 4:
				c.append({"row": row, "bank": -45.0, "tdc": row * 180.0})
				c.append({"row": row, "bank": 45.0, "tdc": row * 180.0 + 90.0})
		"v12":
			for row in 6:
				c.append({"row": row, "bank": -30.0, "tdc": row * 120.0})
				c.append({"row": row, "bank": 30.0, "tdc": row * 120.0 + 60.0})
		"experimental":
			for row in 4:
				for b in 3:
					c.append({"row": row, "bank": [-55.0, 0.0, 55.0][b], "tdc": fmod((row * 3 + b) * 60.0, 720.0)})
		"radial":
			var order := [0, 2, 4, 6, 1, 3, 5]
			for k in 7:
				c.append({"row": 0, "bank": k * 360.0 / 7.0, "tdc": order.find(k) * 720.0 / 7.0})
	return c


func _view_dir() -> Vector3:
	match _spec().view:
		"side":
			return Vector3(0.45, 0.36, 0.82).normalized()
		"rotary":
			return Vector3(0.85, 0.32, 0.45).normalized()
		"radial":
			return Vector3(0.9, 0.3, 0.35).normalized()
	return Vector3(0.8, 0.42, 0.45).normalized()


func _build_key() -> String:
	var tur := "0" if demo else ("1" if not G.equipped("turbine").is_empty() else "0")
	var race := "0" if demo else ("1" if D.epoch_info(G.level).racing else "0")
	return "%s|%d|%s|%s" % [engine_type, material_index, tur, race]


# ---------------------------------------------------------------------
# Сборка модели
# ---------------------------------------------------------------------

func _rebuild() -> void:
	var t0 := Time.get_ticks_msec()
	_rebuild_inner()
	Diag.event("сборка мотора %s (%s) за %d мс" % [engine_type, "витрина" if demo else "игра", Time.get_ticks_msec() - t0])


func _rebuild_inner() -> void:
	_built_key = _build_key()
	if _engine != null and is_instance_valid(_engine):
		_engine.queue_free()
	_engine = Node3D.new()
	_engine.name = "Engine"
	_root.add_child(_engine)
	_cyls.clear()
	_spinners.clear()
	_rotors.clear()
	_anchors.clear()
	_turbine_wheel = null
	_has_turbo = false
	_make_mats()
	var batch := MeshKit.Batch.new()
	var exhaust_end: Vector3
	if _spec().view == "rotary":
		exhaust_end = _build_rotary(batch)
	else:
		exhaust_end = _build_piston_engine(batch)
	_build_exhaust_tail(batch, exhaust_end)
	batch.commit(_engine, _mats)
	# приводим к одному размеру, ставим на стенд и на пол (y = 0)
	var box := _engine_aabb()
	var k := ENGINE_SIZE / maxf(box.size.length() * 0.5, 0.1)
	_engine.scale = Vector3.ONE * k
	box = _engine_aabb()
	var stand_batch := MeshKit.Batch.new()
	_lift = _build_stand(stand_batch, box, k)
	stand_batch.commit(_engine, _mats)
	_engine.position = Vector3(0, _lift, 0)
	box = _engine_aabb()
	_center = box.get_center()
	_bounds = box
	_apply_xray()
	_update_tints()
	_warm_frames = 3
	_add_xray_warmers()
	for m in _fx:
		m.on_rebuild()
		m.warmup(true)


## Рентген меняет прозрачность материалов, а это другие шейдеры. Чтобы первое нажатие
## «Рентген» не подвешивало картинку на компиляцию, пока идёт прогрев, внутри мотора
## рисуются крошечные кубики с материалами во втором состоянии.
func _add_xray_warmers() -> void:
	for w in _xray_warmers:
		if is_instance_valid(w):
			w.queue_free()
	_xray_warmers.clear()
	if demo:
		return
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE * 0.05
	for key in ["block", "head", "cover", "coil"]:
		var src: StandardMaterial3D = _mats[key]
		var m: StandardMaterial3D = src.duplicate()
		var xr := src.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA
		m.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED if xr else BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color.a = 1.0 if xr else 0.22
		var mi := MeshInstance3D.new()
		mi.mesh = cube
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.position = _center
		_root.add_child(mi)
		_xray_warmers.append(mi)


func _engine_aabb() -> AABB:
	var aabb := AABB()
	var first := true
	var inv := _root.global_transform.affine_inverse()
	for n in _engine.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		if mi.mesh == null:
			continue
		var b: AABB = inv * mi.global_transform * mi.get_aabb()
		if first:
			aabb = b
			first = false
		else:
			aabb = aabb.merge(b)
	return aabb


func _rows() -> int:
	var rows := 0
	for c in _layout():
		rows = maxi(rows, int(c.row) + 1)
	return rows


func _row_x(row: int, rows: int) -> float:
	return (row - (rows - 1) * 0.5) * SPACING


func _part(parent: Node3D, mesh: Mesh, mat_key: String, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = _mats.get(mat_key)
	m.position = pos
	m.rotation_degrees = rot_deg
	parent.add_child(m)
	return m


func _xf(pos: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> Transform3D:
	return Transform3D(Basis.from_euler(rot_deg * (PI / 180.0)), pos)


func _build_piston_engine(batch: MeshKit.Batch) -> Vector3:
	var rows := _rows()
	var layout := _layout()
	var short := engine_type == "radial"
	var rod_len := ROD * (0.85 if short else 1.0)
	var deck := rod_len + 1.7
	var length := rows * SPACING + 1.4
	var diesel: bool = _spec().diesel
	var turbo := _built_key.split("|")[2] == "1"

	# прототипы движущихся деталей (одна сетка на деталь, несколько материалов)
	var pb := MeshKit.Batch.new()
	pb.add("piston", MeshKit.cyl(BORE, 1.3, 32), Transform3D.IDENTITY)
	for k in 3:
		pb.add("crank", MeshKit.cyl(BORE + 0.012, 0.06, 32), _xf(Vector3(0, 0.5 - k * 0.15, 0)))
	pb.add("steel", MeshKit.cyl(0.19, BORE * 1.7, 12), _xf(Vector3(0, 0.15, 0), Vector3(0, 0, 90)))
	if diesel:
		pb.add("crank", MeshKit.cyl(BORE * 0.55, 0.05, 24), _xf(Vector3(0, 0.64, 0)))
	var piston_mesh := pb.commit_mesh(_mats)
	pb.add("rod", MeshKit.rounded_box(Vector3(0.26, rod_len, 0.42), 0.08, 3), _xf(Vector3(0, rod_len * 0.5, 0)))
	pb.add("rod", MeshKit.cyl(0.46, 0.36, 20), _xf(Vector3.ZERO, Vector3(0, 0, 90)))
	pb.add("steel", MeshKit.cyl(0.24, 0.4, 12), _xf(Vector3.ZERO, Vector3(0, 0, 90)))
	pb.add("rod", MeshKit.cyl(0.26, 0.32, 16), _xf(Vector3(0, rod_len, 0), Vector3(0, 0, 90)))
	var rod_mesh := pb.commit_mesh(_mats)
	for sx in [-0.26, 0.26]:
		pb.add("crank", MeshKit.extrude(_web_poly(), 0.2), _xf(Vector3(sx, 0, 0)))
	pb.add("steel", MeshKit.cyl(0.3, 0.6, 16), _xf(Vector3(0, 1.0, 0), Vector3(0, 0, 90)))
	var throw_mesh := pb.commit_mesh(_mats)
	pb.add("steel", MeshKit.cyl(0.07, HEAD * 0.95, 8), _xf(Vector3(0, HEAD * 0.47, 0)))
	pb.add("steel", MeshKit.cone(0.34, 0.1, 0.12, 20), _xf(Vector3(0, 0.06, 0)))
	pb.add("brass", MeshKit.cyl(0.2, 0.25, 12), _xf(Vector3(0, HEAD * 0.8, 0)))
	var valve_mesh := pb.commit_mesh(_mats)

	# коленвал, маховик с венцом
	var shaft := Node3D.new()
	_engine.add_child(shaft)
	_part(shaft, MeshKit.cyl(0.42, length, 20), "crank", Vector3.ZERO, Vector3(0, 0, 90))
	_spinners.append({"node": shaft, "ratio": 1.0})
	var fly := Node3D.new()
	fly.position = Vector3(-length * 0.5 - 0.25, 0, 0)
	_engine.add_child(fly)
	_part(fly, MeshKit.cyl(2.0, 0.3, 40), "steel", Vector3.ZERO, Vector3(0, 0, 90))
	_part(fly, MeshKit.gear(2.05, 0.22, 48, 0.1), "crank", Vector3(-0.08, 0, 0))
	for k in 6:
		_part(fly, MeshKit.cyl(0.1, 0.36, 6), "crank", Vector3(0, cos(k * TAU / 6) * 0.7, sin(k * TAU / 6) * 0.7), Vector3(0, 0, 90))
	_spinners.append({"node": fly, "ratio": 1.0})
	var front_x := length * 0.5 + 0.2
	_anchors["flywheel"] = fly.position
	_anchors["crank"] = Vector3(length * 0.3, 0, 0.4)
	_anchors["reactor"] = Vector3(0, -0.4, 1.75)
	_anchors["stabilizer"] = Vector3(-length * 0.3, -2.05, 1.5)
	_anchors["cooling"] = Vector3(front_x, deck * 0.5, 1.5)

	# картер, поддон с рёбрами, масляный фильтр, щуп
	var case_w := rows * SPACING + 0.5
	if engine_type == "radial":
		_part(_engine, MeshKit.cyl(2.0, 2.6, 32), "case", Vector3.ZERO, Vector3(0, 0, 90))
	else:
		_part(_engine, MeshKit.rounded_box(Vector3(case_w, 2.6, 3.4), 0.35, 4), "case", Vector3(0, -0.4, 0))
		batch.add("block", MeshKit.rounded_box(Vector3(case_w - 0.3, 0.8, 2.9), 0.25, 3), _xf(Vector3(0, -2.05, 0)))
		for k in int(case_w / 0.6):
			batch.add("block", MeshKit.box(Vector3(0.08, 0.5, 3.0)), _xf(Vector3(-case_w * 0.5 + 0.4 + k * 0.6, -2.1, 0)))
		batch.add("filter", MeshKit.cyl(0.42, 0.9, 20), _xf(Vector3(case_w * 0.25, -0.6, 1.95), Vector3(90, 0, 0)))
		batch.add("rubber", MeshKit.cyl(0.44, 0.08, 20), _xf(Vector3(case_w * 0.25, -0.6, 1.5), Vector3(90, 0, 0)))
		batch.add("brass", MeshKit.rounded_box(Vector3(0.3, 0.12, 0.3), 0.05, 2), _xf(Vector3(-case_w * 0.3, 1.6, 1.85)))
		batch.add("steel", MeshKit.cyl(0.04, 1.8, 6), _xf(Vector3(-case_w * 0.3, 0.7, 1.8)))

	var banks: Array = []
	for c in layout:
		if not banks.has(c.bank):
			banks.append(c.bank)
	banks.sort()
	var header_ends: Array = []
	for c in layout:
		var frame := Node3D.new()
		var bi := banks.find(c.bank)
		var bx := 0.0
		if banks.size() > 1 and engine_type != "radial":
			bx = (bi - (banks.size() - 1) * 0.5) * 0.44
		frame.position = Vector3(_row_x(int(c.row), rows) + bx, 0, 0)
		frame.rotation_degrees = Vector3(c.bank, 0, 0)
		_engine.add_child(frame)
		var fx := frame.transform
		var head_w := SPACING * 0.96 if banks.size() == 1 else 2.75
		var bank_sign := signf(c.bank) if c.bank != 0.0 else -1.0
		var out_z := 1.45 * bank_sign  # выпуск наружу (у рядного — назад, от камеры)
		var cy := {"frame": frame, "tdc": float(c.tdc), "deck": deck, "fins": [], "rod_len": rod_len}
		# гильза в разрезе (поворачивается к камере)
		var liner_h := deck - 1.2
		cy.liner = _part(frame, MeshKit.half_tube(BORE + 0.06, BORE + 0.42, liner_h, 24), "block", Vector3(0, 1.2 + liner_h * 0.5, 0))
		cy.bore = _part(frame, MeshKit.half_tube(BORE + 0.015, BORE + 0.06, liner_h, 24), "bore", Vector3(0, 1.2 + liner_h * 0.5, 0))
		if engine_type in ["single", "radial", "experimental"]:
			for k in 6:
				cy.fins.append(_part(frame, MeshKit.half_tube(BORE + 0.42, BORE + 0.85, 0.1, 24), "block", Vector3(0, 1.9 + k * 0.48 * (rod_len / ROD), 0)))
		# ГБЦ: литая головка, рёбристая крышка, болты
		batch.add("head", MeshKit.rounded_box(Vector3(head_w, HEAD, 3.1), 0.18, 4), fx * _xf(Vector3(0, deck + HEAD * 0.5, 0)))
		batch.add("cover", MeshKit.rounded_box(Vector3(head_w * 0.9, 0.55, 2.5), 0.22, 4), fx * _xf(Vector3(0, deck + HEAD + 0.25, 0)))
		for k in 3:
			batch.add("cover", MeshKit.rounded_box(Vector3(head_w * 0.8, 0.12, 0.18), 0.05, 2), fx * _xf(Vector3(0, deck + HEAD + 0.55, -0.7 + k * 0.7)))
		for bxp in [-1, 1]:
			for bzp in [-1, 1]:
				batch.add("steel", MeshKit.cyl(0.11, 0.14, 6), fx * _xf(Vector3(bxp * head_w * 0.4, deck + HEAD + 0.5, bzp * 1.05)))
		if engine_type == "experimental":
			for zz in [-1.58, 1.58]:
				batch.add("accent", MeshKit.rounded_box(Vector3(head_w * 0.92, 0.07, 0.08), 0.02, 1), fx * _xf(Vector3(0, deck + HEAD * 0.5, zz)))
		# катушка зажигания или форсунка
		if not diesel:
			batch.add("coil", MeshKit.rounded_box(Vector3(0.55, 0.75, 0.55), 0.14, 3), fx * _xf(Vector3(0, deck + HEAD + 0.85, 0)))
			batch.add("plug", MeshKit.cyl(0.13, 0.5, 10), fx * _xf(Vector3(0, deck + HEAD + 0.25, 0)))
		else:
			batch.add("steel", MeshKit.cyl(0.17, 0.9, 10), fx * _xf(Vector3(0, deck + HEAD + 0.75, 0)))
			batch.add("brass", MeshKit.cyl(0.1, 0.3, 8), fx * _xf(Vector3(0, deck + HEAD + 1.3, 0)))
		# впускные «дудки» (не у звезды)
		if engine_type != "radial":
			var in_z := -out_z * 0.9
			batch.add("head", MeshKit.rounded_box(Vector3(0.9, 0.7, 0.6), 0.15, 2), fx * _xf(Vector3(0, deck + HEAD * 0.5, in_z * 1.1)))
			var tr := _xf(Vector3(0, deck + HEAD * 0.9, in_z * 1.25), Vector3(-signf(in_z) * 35.0, 0, 0))
			batch.add("steel", MeshKit.cyl(0.36, 1.1, 20), fx * tr * _xf(Vector3(0, 0.5, 0)))
			batch.add("steel", MeshKit.cone(0.36, 0.62, 0.35, 20), fx * tr * _xf(Vector3(0, 1.2, 0)))
		# выпускной патрубок → точки коллектора
		var port: Vector3
		var out_dir: Vector3
		if engine_type == "radial":
			port = fx * Vector3(-0.9, deck + HEAD * 0.3, 0)
			out_dir = Vector3(-1, 0, 0)
		else:
			port = fx * Vector3(0, deck + HEAD * 0.45, out_z * 1.08)
			out_dir = (fx.basis * Vector3(0, -0.25, signf(out_z))).normalized()
		header_ends.append({"port": port, "dir": out_dir, "bank": c.bank})
		if not _anchors.has("block") or frame.position.x >= float(_anchors.get("_x", -INF)):
			_anchors["_x"] = frame.position.x
			_anchors["block"] = fx * Vector3(0, 1.6, BORE + 0.3)
			_anchors["pistons"] = fx * Vector3(0, 3.0, 0)
			_anchors["head"] = fx * Vector3(0, deck + HEAD * 0.5, 1.3)
			_anchors["ignition"] = fx * Vector3(0, deck + HEAD + 0.9, 0)
			_anchors["fuel"] = fx * (Vector3(0, deck + HEAD * 1.4, -out_z * 1.1) if engine_type != "radial" else Vector3(0, deck + HEAD, 0))
		# клапаны
		var valves: Array = []
		for side in [-1, 1]:
			var v := MeshInstance3D.new()
			v.mesh = valve_mesh
			v.position = Vector3(side * 0.42, deck, 0)
			frame.add_child(v)
			valves.append(v)
		cy.valves = valves
		# вспышка в камере
		var fl := _part(frame, SphereMesh.new(), "flash", Vector3(0, deck - 0.35, 0))
		fl.scale = Vector3(BORE * 1.9, 0.6, BORE * 1.9)
		fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cy.flash = fl
		var piston := MeshInstance3D.new()
		piston.mesh = piston_mesh
		frame.add_child(piston)
		cy.piston = piston
		var rod := MeshInstance3D.new()
		rod.mesh = rod_mesh
		frame.add_child(rod)
		cy.rod = rod
		var throw := MeshInstance3D.new()
		throw.mesh = throw_mesh
		frame.add_child(throw)
		cy.throw = throw
		_cyls.append(cy)

	if engine_type != "radial":
		_build_timing(batch, front_x, deck, banks)
	else:
		# пропеллер у звездообразного
		var prop := Node3D.new()
		prop.position = Vector3(front_x + 1.6, 0, 0)
		_engine.add_child(prop)
		_part(prop, MeshKit.cone(0.9, 0.0, 1.6, 24), "steel", Vector3(0.7, 0, 0), Vector3(0, 0, -90))
		for k in 3:
			var a := TAU * k / 3.0
			var blade := _part(prop, MeshKit.rounded_box(Vector3(0.18, 6.5, 0.7), 0.08, 3), "rubber")
			blade.basis = Basis(Vector3.RIGHT, a) * Basis(Vector3.UP, 0.35)
			blade.position = Vector3(0, cos(a), sin(a)) * 3.3
		_spinners.append({"node": prop, "ratio": 1.0})
		_part(_engine, MeshKit.cyl(0.5, 1.2, 16), "crank", Vector3(front_x + 0.6, 0, 0), Vector3(0, 0, 90))
	return _build_headers(batch, header_ends, length, turbo)


func _web_poly() -> PackedVector2Array:
	# щека коленвала в плоскости (y, z): от шатунной шейки сверху к противовесу-полукругу снизу
	var p := PackedVector2Array()
	p.append(Vector2(1.25, -0.4))
	p.append(Vector2(1.25, 0.4))
	for i in 17:
		var a := PI * i / 16.0
		p.append(Vector2(-0.15 - sin(a) * 1.0, cos(a) * 1.0))
	return p


func _build_timing(batch: MeshKit.Batch, front_x: float, deck: float, banks: Array) -> void:
	var crank_sp := Node3D.new()
	crank_sp.position = Vector3(front_x + 0.15, 0, 0)
	_engine.add_child(crank_sp)
	_part(crank_sp, MeshKit.gear(0.75, 0.32, 20, 0.08), "steel")
	_part(crank_sp, MeshKit.cyl(1.0, 0.25, 32), "crank", Vector3(0.3, 0, 0), Vector3(0, 0, 90))
	_spinners.append({"node": crank_sp, "ratio": 1.0})
	var belt_pts: Array = [Vector2(0, 0)]
	var radii: Array = [0.9]
	for b in banks:
		var cam_y := deck + HEAD * 0.75
		var p3 := Basis(Vector3.RIGHT, deg_to_rad(b)) * Vector3(0, cam_y, 0)
		var sp := Node3D.new()
		sp.position = Vector3(front_x + 0.15, p3.y, p3.z)
		_engine.add_child(sp)
		_part(sp, MeshKit.gear(1.15, 0.3, 30, 0.09), "steel")
		_part(sp, MeshKit.cyl(0.35, 0.36, 16), "crank", Vector3.ZERO, Vector3(0, 0, 90))
		for k in 4:
			_part(sp, MeshKit.cyl(0.18, 0.34, 12), "crank", Vector3(0, cos(k * TAU / 4) * 0.7, sin(k * TAU / 4) * 0.7), Vector3(0, 0, 90))
		_spinners.append({"node": sp, "ratio": 0.5})
		belt_pts.append(Vector2(p3.y, p3.z))
		radii.append(1.25)
	# натяжной ролик
	var idler := Vector2(deck * 0.45, 1.7)
	belt_pts.append(idler)
	radii.append(0.45)
	_part(_engine, MeshKit.cyl(0.42, 0.34, 16), "steel", Vector3(front_x + 0.15, idler.x, idler.y), Vector3(0, 0, 90))
	# ремень — выпуклая оболочка вокруг шкивов
	var cloud := PackedVector2Array()
	for i in belt_pts.size():
		var c: Vector2 = belt_pts[i]
		var r: float = radii[i]
		for k in 24:
			var a := TAU * k / 24.0
			cloud.append(c + Vector2(cos(a), sin(a)) * r)
	var hull := Geometry2D.convex_hull(cloud)
	var path := PackedVector3Array()
	for v in hull:
		path.append(Vector3(front_x + 0.15, v.x, v.y))
	batch.add("belt", MeshKit.sweep(path, 0.1, 4, false), Transform3D.IDENTITY)
	# генератор с крыльчаткой
	_anchors["cooling"] = Vector3(front_x - 0.4, 1.4, 2.3)
	batch.add("steel", MeshKit.cyl(0.75, 1.1, 24), _xf(Vector3(front_x - 0.4, 1.4, 2.3), Vector3(0, 0, 90)))
	for k in 8:
		batch.add("crank", MeshKit.box(Vector3(1.12, 0.08, 0.3)), _xf(Vector3(front_x - 0.4, 1.4, 2.3), Vector3(k * 22.5, 0, 0)))


func _build_headers(batch: MeshKit.Batch, ends: Array, length: float, turbo: bool) -> Vector3:
	# коллектор: трубы от каждого цилиндра плавно уходят вниз к общей трубе
	var collector_y := -0.6
	var groups := {}
	for e in ends:
		if engine_type == "experimental" and e.bank == 0.0:
			# средний ряд W-образного: короткие прямоточные трубы вверх-назад —
			# общий коллектор с боковым рядом пронзал бы его головки
			var s0: Vector3 = e.port
			var tip := s0 + Vector3(0, 1.9, -1.0)
			batch.add("header", MeshKit.sweep(MeshKit.bezier(s0, s0 + Vector3(0, 0.2, -0.7), tip + Vector3(0, -0.8, 0), tip, 10), 0.24, 12), Transform3D.IDENTITY)
			batch.add("header", MeshKit.cone(0.24, 0.34, 0.3, 14), _xf(tip + Vector3(0, 0.12, 0)))
			continue
		var key: String = "r" if engine_type == "radial" else str(signf(e.bank) if e.bank != 0.0 else -1.0)
		if not groups.has(key):
			groups[key] = []
		groups[key].append(e)
	var merge_points: Array = []
	for key in groups:
		var list: Array = groups[key]
		if engine_type == "radial":
			# звездообразный: патрубки назад и внутрь, в кольцевой коллектор между картером и маховиком
			var ring_x := -2.3
			var ring_r := 2.56
			for e in list:
				var p0: Vector3 = e.port
				var rd := Vector3(0, p0.y, p0.z).normalized()
				var q := Vector3(ring_x, 0, 0) + rd * ring_r
				batch.add("header", MeshKit.sweep(MeshKit.bezier(p0, p0 + Vector3(-1.0, 0, 0), q + rd * 1.4, q), 0.26, 10), Transform3D.IDENTITY)
			var ring := TorusMesh.new()
			ring.inner_radius = ring_r - 0.25
			ring.outer_radius = ring_r + 0.25
			ring.rings = 36
			batch.add("header", ring, _xf(Vector3(ring_x, 0, 0), Vector3(0, 0, 90)))
			merge_points.append(Vector3(ring_x, -ring_r, 0))
			continue
		var side_z: float = list[0].port.z
		var out := signf(side_z) if absf(side_z) > 0.01 else -1.0
		var col_z := side_z + out * 1.6
		var col_x := length * 0.5 + 0.4
		var xs: Array = []
		for e in list:
			var p0: Vector3 = e.port
			var dir: Vector3 = e.dir
			var p1 := p0 + dir * 1.4
			var p3 := Vector3(lerpf(p0.x, col_x, 0.35), collector_y, col_z)
			var p2 := p3 + Vector3(0, 1.4, 0)
			batch.add("header", MeshKit.sweep(MeshKit.bezier(p0, p1, p2, p3, 14), 0.27, 12), Transform3D.IDENTITY)
			batch.add("steel", MeshKit.rounded_box(Vector3(0.8, 0.12, 0.8), 0.06, 2), Transform3D(MeshKit.align_y(dir), p0))
			xs.append(p3.x)
		xs.sort()
		var a := Vector3(float(xs[0]) - 0.2, collector_y, col_z)
		var b := Vector3(col_x, collector_y, col_z)
		batch.add("header", MeshKit.sweep(PackedVector3Array([a, b]), 0.42, 14), Transform3D.IDENTITY)
		merge_points.append(b)
	var m := Vector3.ZERO
	for p in merge_points:
		m += p
	m /= maxf(1.0, merge_points.size())
	if merge_points.size() > 1:
		var target := m + Vector3(1.2, -1.2, 0)
		for p in merge_points:
			var pp: Vector3 = p
			batch.add("header", MeshKit.sweep(MeshKit.bezier(pp, pp + Vector3(0.8, 0, 0), target + Vector3(-0.6, 0.4, 0), target, 10), 0.38, 12), Transform3D.IDENTITY)
		m = target
	_anchors["turbine"] = m
	if turbo:
		m = _build_turbo(batch, m)
	return m


func _build_turbo(batch: MeshKit.Batch, inlet: Vector3) -> Vector3:
	# улитка, крыльчатка, компрессор с конусным фильтром (как на логотипе)
	var tp := inlet + Vector3(1.2, 1.6, 0)
	batch.add("header", MeshKit.sweep(MeshKit.bezier(inlet, inlet + Vector3(0.6, 0, 0), tp + Vector3(-0.4, -1.2, 0), tp + Vector3(0, -0.9, 0), 8), 0.38, 12), Transform3D.IDENTITY)
	var housing := TorusMesh.new()
	housing.inner_radius = 0.55
	housing.outer_radius = 1.25
	housing.rings = 24
	batch.add("header", housing, _xf(tp, Vector3(0, 0, 90)))
	batch.add("steel", MeshKit.cyl(0.65, 0.9, 24), _xf(tp + Vector3(0.6, 0, 0), Vector3(0, 0, 90)))
	var comp := TorusMesh.new()
	comp.inner_radius = 0.6
	comp.outer_radius = 1.35
	comp.rings = 24
	batch.add("steel", comp, _xf(tp + Vector3(1.2, 0, 0), Vector3(0, 0, 90)))
	batch.add("steel", MeshKit.cone(0.7, 0.55, 0.9, 24), _xf(tp + Vector3(1.9, 0, 0), Vector3(0, 0, -90)))
	batch.add("airfilter", MeshKit.cone(0.62, 0.95, 1.6, 28), _xf(tp + Vector3(3.1, 0, 0), Vector3(0, 0, -90)))
	for k in 6:
		batch.add("steel", MeshKit.cyl(0.66 + k * 0.055, 0.04, 28), _xf(tp + Vector3(2.4 + k * 0.27, 0, 0), Vector3(0, 0, 90)))
	batch.add("steel", MeshKit.cyl(0.98, 0.08, 28), _xf(tp + Vector3(3.92, 0, 0), Vector3(0, 0, 90)))
	_turbine_wheel = Node3D.new()
	_turbine_wheel.position = tp + Vector3(1.2, 0, 0)
	_engine.add_child(_turbine_wheel)
	for k in 10:
		var a := TAU * k / 10.0
		var blade := _part(_turbine_wheel, MeshKit.box(Vector3(0.08, 0.5, 0.18)), "piston")
		blade.basis = Basis(Vector3.RIGHT, a) * Basis(Vector3.UP, 0.5)
		blade.position = Vector3(0, cos(a), sin(a)) * 0.3
	_turbo_pos = tp
	_has_turbo = true
	_anchors["turbine"] = tp + Vector3(1.2, 0, 0)
	var down := tp + Vector3(-0.2, -2.2, 0.8)
	batch.add("header", MeshKit.sweep(MeshKit.bezier(tp + Vector3(0, -0.6, 0.6), tp + Vector3(0, -1.2, 1.0), down + Vector3(0, 0.6, 0), down, 8), 0.36, 12), Transform3D.IDENTITY)
	return down


func _build_exhaust_tail(batch: MeshKit.Batch, from: Vector3) -> void:
	# глушитель и хвост — назад и вниз, чтобы не закрывать мотор
	var muff_c := from + Vector3(0.6, -0.6, -2.4)
	batch.add("header", MeshKit.sweep(MeshKit.bezier(from, from + Vector3(0.3, -0.4, -0.5), muff_c + Vector3(0, 0.3, 1.8), muff_c + Vector3(0, 0, 1.3), 8), 0.34, 12), Transform3D.IDENTITY)
	batch.add("steel", MeshKit.rounded_box(Vector3(1.5, 1.2, 2.8), 0.5, 4), _xf(muff_c))
	_anchors["exhaust"] = muff_c
	var tail0 := muff_c + Vector3(0, 0, -1.3)
	var tail1 := tail0 + Vector3(0, 0.2, -1.0)
	batch.add("steel", MeshKit.sweep(PackedVector3Array([tail0, tail1]), 0.3, 16), Transform3D.IDENTITY)
	batch.add("bore", MeshKit.cyl(0.25, 0.05, 16), _xf(tail1, Vector3(90, 0, 0)))
	_tail_pos = tail1


func _build_rotary(batch: MeshKit.Batch) -> Vector3:
	var e := 0.7
	var R := 3.6
	var inner := PackedVector2Array()
	var outer := PackedVector2Array()
	for i in 96:
		var a := TAU * i / 96.0
		var p := Vector2(e * cos(3.0 * a) + R * cos(a) * 1.04, e * sin(3.0 * a) + R * sin(a) * 1.04)
		inner.append(p)
		outer.append(p * 1.25)
	var shaft := Node3D.new()
	_engine.add_child(shaft)
	_part(shaft, MeshKit.cyl(0.5, 5.2, 16), "crank", Vector3.ZERO, Vector3(0, 0, 90))
	_spinners.append({"node": shaft, "ratio": 1.0})
	var fly := Node3D.new()
	fly.position = Vector3(-2.9, 0, 0)
	_engine.add_child(fly)
	_part(fly, MeshKit.cyl(2.3, 0.35, 40), "steel", Vector3.ZERO, Vector3(0, 0, 90))
	_part(fly, MeshKit.gear(2.35, 0.25, 54, 0.1), "crank", Vector3(-0.08, 0, 0))
	_spinners.append({"node": fly, "ratio": 1.0})
	var tri := PackedVector2Array()
	for k in 3:
		var a0 := TAU * k / 3.0
		var a1 := TAU * (k + 1) / 3.0
		var v0 := Vector2(cos(a0), sin(a0)) * R
		var v1 := Vector2(cos(a1), sin(a1)) * R
		for s in 10:
			var t := s / 10.0
			var mid := v0.lerp(v1, t)
			tri.append(mid + (-mid).normalized() * -sin(PI * t) * 0.35)
	for i in 2:
		var x := -0.9 + i * 1.8
		batch.add("block", MeshKit.extrude_ring(inner, outer, 1.2), _xf(Vector3(x, 0, 0)))
		batch.add("bore", MeshKit.extrude(outer, 0.15), _xf(Vector3(x - 0.62, 0, 0)))
		for k in 10:
			var a := TAU * k / 10.0
			batch.add("steel", MeshKit.cyl(0.12, 1.3, 6), _xf(Vector3(x, cos(a) * R * 1.32, sin(a) * R * 1.32), Vector3(0, 0, 90)))
		var rotor := Node3D.new()
		rotor.position = Vector3(x, 0, 0)
		_engine.add_child(rotor)
		var body := _part(rotor, MeshKit.extrude(tri, 1.0), "piston")
		_part(body, MeshKit.gear(1.1, 1.05, 24, 0.08), "crank")
		var fl := _part(_engine, SphereMesh.new(), "flash", Vector3(x, 0, -R * 0.8))
		fl.scale = Vector3(1.0, 2.2, 1.2)
		_rotors.append({"node": rotor, "phase": PI * i, "flash": fl})
		for k in 2:
			batch.add("plug", MeshKit.cyl(0.13, 0.9, 10), _xf(Vector3(x, -0.6 + 1.2 * k, -R * 1.33), Vector3(90, 0, 0)))
			batch.add("coil", MeshKit.rounded_box(Vector3(0.5, 0.5, 0.7), 0.12, 2), _xf(Vector3(x, -0.6 + 1.2 * k, -R * 1.33 - 0.7)))
		batch.add("steel", MeshKit.sweep(MeshKit.bezier(Vector3(x, R * 1.1, 1.2), Vector3(x, R * 1.6, 1.6), Vector3(x, R * 1.8, 2.4), Vector3(x, R * 1.8, 3.2), 8), 0.35, 14), Transform3D.IDENTITY)
		batch.add("steel", MeshKit.cone(0.35, 0.6, 0.4, 16), _xf(Vector3(x, R * 1.8, 3.4), Vector3(90, 0, 0)))
	batch.add("case", MeshKit.rounded_box(Vector3(4.2, 1.0, 3.0), 0.3, 3), _xf(Vector3(0, -R * 1.25 - 0.4, 0)))
	_anchors["block"] = Vector3(0.9, R * 0.95, 0)
	_anchors["pistons"] = Vector3(0.9, 0, 0)
	_anchors["crank"] = Vector3(2.6, 0, 0)
	_anchors["flywheel"] = Vector3(-2.9, 0, 0)
	_anchors["head"] = Vector3(0.9, R * 1.5, 1.6)
	_anchors["ignition"] = Vector3(0.9, 0, -R * 1.4)
	_anchors["fuel"] = Vector3(0.9, R * 1.8, 3.2)
	_anchors["cooling"] = Vector3(0.9, -R * 1.1, 0)
	_anchors["reactor"] = Vector3(0, -R * 1.25 - 0.4, 1.5)
	_anchors["stabilizer"] = Vector3(-0.9, -R * 1.1, 0)
	var col := Vector3(2.4, -2.6, R * 1.6)
	for i in 2:
		var p := Vector3(-0.9 + i * 1.8, -1.0, R * 1.2)
		batch.add("header", MeshKit.sweep(MeshKit.bezier(p, p + Vector3(0, 0, 1.0), col + Vector3(-1.0, 0.8, 0), col, 10), 0.3, 12), Transform3D.IDENTITY)
	_anchors["turbine"] = col
	if _built_key.split("|")[2] == "1":
		return _build_turbo(batch, col)
	return col


func _build_stand(batch: MeshKit.Batch, box: AABB, k: float) -> float:
	# стенд из труб на колёсиках, стойки держат мотор за торцы коленвала.
	# Координаты считаются в пространстве корня (мотор уже отмасштабирован) и переводятся в локальные.
	var inv := 1.0 / k
	var floor_y := box.position.y - 0.7
	var cx := box.get_center().x
	var half_x := box.size.x * 0.5 + 0.5
	var half_z := maxf(1.8, box.size.z * 0.28)
	var corners := []
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			corners.append(Vector3(cx + sx * half_x, floor_y + 0.55, sz * half_z))
	var tube := 0.16
	for pair in [[0, 1], [2, 3], [0, 2], [1, 3]]:
		batch.add("stand", MeshKit.sweep(PackedVector3Array([corners[pair[0]], corners[pair[1]]]), tube, 10), _sc(inv))
	for sx in [-1, 1]:
		var base := Vector3(cx + sx * half_x, floor_y + 0.55, 0)
		var top := Vector3(cx + sx * half_x, 0.0, 0)
		batch.add("stand", MeshKit.sweep(PackedVector3Array([base + Vector3(0, 0, -half_z), top]), tube, 10), _sc(inv))
		batch.add("stand", MeshKit.sweep(PackedVector3Array([base + Vector3(0, 0, half_z), top]), tube, 10), _sc(inv))
		batch.add("stand", MeshKit.rounded_box(Vector3(0.55, 0.55, 0.55), 0.12, 2), _sc(inv, top))
		batch.add("steel", MeshKit.sweep(PackedVector3Array([top, top - Vector3(sx * 0.9, 0, 0)]), 0.12, 10), _sc(inv))
	for p in corners:
		batch.add("steel", MeshKit.cyl(0.08, 0.3, 8), _sc(inv, p + Vector3(0, -0.2, 0)))
		batch.add("rubber", MeshKit.cyl(0.24, 0.16, 16), Transform3D(Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3.ONE * inv), (p + Vector3(0, -0.36, 0)) * inv))
	# низ колёс должен стоять на полу (y = 0)
	return -(floor_y - 0.05)


## Где на экране (в координатах этого Control) находится деталь слота. (-1, -1) — нет такой точки.
func part_screen_pos(slot_id: String) -> Vector2:
	if _engine == null or _cam == null or not _anchors.has(slot_id):
		return Vector2(-1, -1)
	var gp := _engine.to_global(_anchors[slot_id])
	if _cam.is_position_behind(gp):
		return Vector2(-1, -1)
	var p := _cam.unproject_position(gp)
	return p * (size / Vector2(maxi(1, _vp.size.x), maxi(1, _vp.size.y)))


func _sc(inv: float, at: Vector3 = Vector3.ZERO) -> Transform3D:
	return Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * inv), at * inv)


func _apply_xray() -> void:
	var xr := _xray()
	var a := 0.22 if xr else 1.0
	for key in ["block", "head", "cover", "coil"]:
		var m: StandardMaterial3D = _mats[key]
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if xr else BaseMaterial3D.TRANSPARENCY_DISABLED
		m.albedo_color.a = a
	var cm: StandardMaterial3D = _mats.case
	cm.albedo_color.a = 0.12 if xr else 0.5


func _xray() -> bool:
	return (not demo) and (G.settings.xray or G.ultra > 0)


# ---------------------------------------------------------------------
# Кадр
# ---------------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	if _engine == null or not is_instance_valid(_engine):
		return
	if not demo and _build_key() != _built_key:
		_rebuild()
	var spec := _spec()
	var max_rpm: float = spec.rpm
	var idle: float = spec.idle
	var throttle := false
	if demo:
		rpm = lerpf(rpm, demo_rpm, 1.0 - exp(-delta * 3.0))
	else:
		throttle = G.throttle
		var target := idle
		if throttle:
			target = max_rpm * G.d_max_rpm_mult * (1.08 if G.turbo_time > 0.0 else 1.0)
			# отсечка: на максимуме обороты «бьются» об ограничитель
			if rpm > target * 0.97:
				target *= 0.94 + (0.06 if fmod(_time, 0.12) < 0.06 else 0.0)
				_limiter_t -= delta
				if _limiter_t <= 0.0:
					_limiter_t = 0.12
					fx_event("limiter")
			else:
				_limiter_t = 0.0
		elif G.is_exhausted:
			target = idle * (0.75 + 0.2 * sin(_time * 9.0))
		if not throttle:
			_limiter_t = 0.0
		var kk := 3.2 if target > rpm else 1.6
		rpm = lerpf(rpm, target, 1.0 - exp(-delta * kk))
		if _prev_throttle and not throttle and rpm > max_rpm * 0.55:
			_pop_flame()
		_prev_throttle = throttle
		var want_heat := 0.0
		if G.d_stamina_max > 0.0:
			want_heat = 1.0 - G.stamina / G.d_stamina_max
		if G.is_exhausted:
			want_heat = maxf(want_heat, 0.85)
		heat = lerpf(heat, want_heat, 1.0 - exp(-delta * 2.0))

	var rev_per_s := 0.35 + rpm / 1300.0
	crank_deg = fmod(crank_deg + 360.0 * rev_per_s * delta, 1440.0)
	var ratio := clampf(rpm / max_rpm, 0.0, 1.2)
	_animate(delta)

	# тряска мотора и камеры
	var amp := 0.0
	if demo or G.settings.shake:
		amp = (0.012 + 0.09 * ratio * ratio) * float(spec.balance)
		if not demo:
			amp *= G.d_shake_mult
			if G.is_exhausted:
				amp *= 1.6
	var n := Vector3(sin(_time * 53.0) + 0.5 * sin(_time * 97.0), cos(_time * 61.0) + 0.5 * sin(_time * 83.0), sin(_time * 71.0))
	_engine.rotation = Vector3(n.y, 0, n.x) * amp * 0.04
	_engine.position = Vector3(n.x * amp * 0.5, _lift, n.z * amp * 0.5)
	shake_offset = Vector2(n.x, n.y) * amp * 25.0

	if locked:
		_yaw_target = 0.0
	elif not _pressed:
		var sway := 0.18 * sin(_time * 0.25) if G.settings.get("cam_sway", true) else 0.0
		_yaw_target = lerpf(_yaw_target, sway, 1.0 - exp(-delta * 0.6))
	_yaw = lerpf(_yaw, _yaw_target, 1.0 - exp(-delta * 8.0))
	if _intro_t > 0.0:
		# облёт после загрузки: камера заходит сбоку и сверху и плавно встаёт на место
		_intro_t = maxf(0.0, _intro_t - delta)
		var k := _intro_t / INTRO_TIME
		var e := k * k * (3.0 - 2.0 * k)
		_intro_yaw = 1.1 * e
		_intro_lift = 4.0 * e
	else:
		_intro_yaw = 0.0
		_intro_lift = 0.0
	_fov_kick = maxf(0.0, _fov_kick - delta * 4.0)
	_place_camera(n * amp * 0.15)

	_update_effects(delta, ratio, throttle)
	flash_white = maxf(0.0, flash_white - delta * 2.5)
	_tint_acc += delta
	if _tint_acc >= 0.2:
		_tint_acc = 0.0
		_update_tints()

	if drives_audio:
		Sfx.rpm = rpm
		Sfx.idle_rpm = idle
		Sfx.max_rpm = max_rpm * (1.0 if demo else G.d_max_rpm_mult)
		Sfx.cylinders = spec.cyl
		Sfx.pitch = spec.pitch
		Sfx.diesel = spec.diesel
		Sfx.engine_type = engine_type
		if demo:
			Sfx.engine_load = clampf((rpm - idle) / maxf(1.0, max_rpm - idle), 0.0, 1.0)
		else:
			Sfx.engine_load = (1.0 if throttle else 0.0) * (1.0 if not G.is_exhausted else 0.0)
		Sfx.turbo_level = 0.0 if demo else (1.0 if G.turbo_time > 0.0 else (0.35 * ratio if _turbine_wheel != null else 0.0))
	# белая вспышка — перерисовка только пока она есть; кольцо турбо — параметрами шейдера
	if flash_white > 0.0 or _hud_flash_drawn > 0.0:
		_hud_flash_drawn = flash_white
		_hud.queue_redraw()
	_update_turbo_ring()
	_update_render_mode()


## Экономия: 3D рисуется через кадр на слабых пресетах и не рисуется вовсе, когда мотор закрыт меню.
func _update_render_mode() -> void:
	_frame_i += 1
	if _warm_frames > 0:
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	elif render_paused:
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	elif int(G.settings.get("fps3d", 1)) == 0:
		if _frame_i % 2 == 0:
			_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	else:
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func _place_camera(jitter: Vector3) -> void:
	var dir := _view_dir().rotated(Vector3.UP, _yaw + _intro_yaw)
	var aspect := maxf(0.3, size.x / maxf(size.y, 1.0))
	_cam.fov = 30.0 + _fov_kick * 4.0
	var half_v := deg_to_rad(_cam.fov * 0.5)
	var half_h := atan(tan(half_v) * aspect)
	var zoom := clampf(float(G.settings.get("cam_zoom", 1.0)), 0.7, 1.4)
	var r := ENGINE_SIZE * 0.97
	var fit_v := atan(tan(half_v) * band.size.y)
	var fit_h := atan(tan(half_h) * band.size.x)
	var dist := r / sin(minf(fit_v, fit_h)) / zoom
	_cam.position = _center + dir * dist + jitter + Vector3(0, _intro_lift, 0)
	_cam.look_at(_center, Vector3.UP)
	# дальний план гаража мягко размыт (как у камеры с открытой диафрагмой) — мотор выделяется
	if _cam_attr != null and absf(_cam_attr.dof_blur_far_distance - (dist + ENGINE_SIZE * 0.9)) > 0.5:
		_cam_attr.dof_blur_far_distance = dist + ENGINE_SIZE * 0.9
	# сдвиг кадра, чтобы мотор стоял в своей полосе экрана
	var ndc_y := 1.0 - 2.0 * (band.position.y + band.size.y * 0.5)
	var ndc_x := 2.0 * (band.position.x + band.size.x * 0.5) - 1.0
	_cam.v_offset = -ndc_y * dist * tan(half_v)
	_cam.h_offset = -ndc_x * dist * tan(half_h)


func _animate(delta: float) -> void:
	var cam_pos := _cam.global_position
	var max_flash := 0.0
	var flash_pos := Vector3.ZERO
	var ultra := not demo and G.ultra > 0
	for s in _spinners:
		s.node.rotation.x = deg_to_rad(crank_deg * s.ratio)
	for cy in _cyls:
		var psi := deg_to_rad(crank_deg - cy.tdc)
		var L: float = cy.rod_len
		var pin := Vector3(0, cos(psi), sin(psi))
		var d := cos(psi) + sqrt(maxf(0.0, L * L - pow(sin(psi), 2.0)))
		cy.piston.position = Vector3(0, d - 0.15, 0)
		cy.throw.rotation.x = psi
		var v := Vector3(0, d, 0) - pin
		cy.rod.position = pin
		cy.rod.rotation.x = atan2(v.z, v.y)
		var c := fposmod(crank_deg - cy.tdc, 720.0)
		cy.valves[0].position.y = cy.deck - 0.3 * _valve_lift(c, 340.0, 560.0)
		cy.valves[1].position.y = cy.deck - 0.3 * _valve_lift(c, 160.0, 380.0)
		var f := 1.0 - c / 60.0 if c < 60.0 else 0.0
		cy.flash.visible = f > 0.01
		if f > max_flash:
			max_flash = f
			flash_pos = cy.frame.to_global(Vector3(0, cy.deck - 0.4, 0))
		cy.flash.scale = Vector3(BORE * 1.9, 0.4 + 0.5 * f, BORE * 1.9)
		var local_cam: Vector3 = cy.frame.to_local(cam_pos)
		var yaw := atan2(local_cam.x, local_cam.z)
		cy.liner.rotation.y = yaw
		cy.bore.rotation.y = yaw
		for fin in cy.fins:
			fin.rotation.y = yaw
	for r in _rotors:
		var ph: float = deg_to_rad(crank_deg) + r.phase
		var e := 0.7
		r.node.position.y = cos(ph) * e
		r.node.position.z = sin(ph) * e
		r.node.rotation.x = ph / 3.0
		var cyc := fposmod(rad_to_deg(ph), 360.0)
		var f2 := 1.0 - cyc / 50.0 if cyc < 50.0 else 0.0
		r.flash.visible = f2 > 0.01
		if f2 > max_flash:
			max_flash = f2
			flash_pos = r.flash.global_position
	var flm: StandardMaterial3D = _mats.flash
	var fc := Color(1.0, 0.55, 0.15)
	if _spec().diesel:
		fc = Color(1.0, 0.75, 0.4)
	if ultra:
		fc = _ultra_color()
	flm.albedo_color = Color(fc.r, fc.g, fc.b, 0.85)
	_flash_light.light_color = fc
	if max_flash > 0.0:
		_flash_light.position = _root.to_local(flash_pos)
	_flash_light.light_energy = 4.0 * max_flash
	# свет вспышки — лишний проход отрисовки для всех деталей рядом: только на «Высоком» и «Ультра»
	_flash_light.visible = (max_flash > 0.02 and _q() >= 2) or (_warm_frames > 0 and _q() >= 2)
	if _turbine_wheel != null:
		_turbine_deg = fmod(_turbine_deg + (200.0 + rpm * rpm / 25000.0) * delta * (2.0 if (not demo and G.turbo_time > 0.0) else 1.0), 360.0)
		_turbine_wheel.rotation.x = deg_to_rad(_turbine_deg)


func _valve_lift(c: float, a: float, b: float) -> float:
	var cc := c
	if cc < a and cc + 720.0 <= b:
		cc += 720.0
	if cc < a or cc > b:
		return 0.0
	return sin(PI * (cc - a) / (b - a))


func _tail_world() -> Vector3:
	return _root.to_local(_engine.to_global(_tail_pos))


func _pop_flame() -> void:
	Sfx.pop()
	fx_event("pop")


## Сноп искр из мотора (для крита).
func burst_sparks() -> void:
	fx_event("crit")
	_fov_kick = 0.6


## Рывок камеры и выстрел пламени при включении турбо.
func turbo_kick() -> void:
	_fov_kick = 1.0
	fx_event("turbo_start")
	_pop_flame()


## Сообщить модулям эффектов о событии.
func fx_event(event_name: String, data: Dictionary = {}) -> void:
	for m in _fx:
		m.on_event(event_name, data)
	GarageScene.on_event(_garage, event_name, data)


# ---------------------------------------------------------------------
# Что видят модули эффектов (координаты — в пространстве _root, пол на y = 0)
# ---------------------------------------------------------------------

func fx_quality() -> int:
	return _q()


func fx_particles() -> int:
	return clampi(int(G.settings.get("particles", 1)), 0, 2)


func fx_root() -> Node3D:
	return _root


func fx_camera() -> Camera3D:
	return _cam


func fx_viewport() -> SubViewport:
	return _vp


## TextureRect, на котором показан 3D-кадр (для постобработки).
func fx_display() -> TextureRect:
	return _tex


func fx_environment() -> Environment:
	return _env


func fx_point(engine_local: Vector3) -> Vector3:
	return _root.to_local(_engine.to_global(engine_local))


func fx_dir(engine_local_dir: Vector3) -> Vector3:
	var b := _root.global_transform.basis.inverse() * _engine.global_transform.basis
	return (b * engine_local_dir).normalized()


func fx_tail() -> Vector3:
	return _tail_world()


## Направление струи из выхлопной трубы.
func fx_tail_dir() -> Vector3:
	return fx_dir(Vector3(0, 0.2, -1.0))


## Центр улитки турбины или Vector3.INF, если турбины нет.
func fx_turbine() -> Vector3:
	return fx_point(_turbo_pos) if _has_turbo else Vector3.INF


func fx_center() -> Vector3:
	return _center


func fx_bounds() -> AABB:
	return _bounds


func fx_floor_y() -> float:
	return 0.0


## Точка детали ("block", "head", "pistons", "exhaust", "turbine", "fuel"…) или Vector3.INF.
func fx_anchor(slot_id: String) -> Vector3:
	if _engine == null or not _anchors.has(slot_id):
		return Vector3.INF
	return fx_point(_anchors[slot_id])


## Где точка 3D-мира на картинке: (0..1, 0..1), или (-1, -1), если за камерой.
func fx_screen_uv(root_pos: Vector3) -> Vector2:
	if _cam == null:
		return Vector2(-1, -1)
	var gp := _root.to_global(root_pos)
	if _cam.is_position_behind(gp):
		return Vector2(-1, -1)
	return _cam.unproject_position(gp) / Vector2(maxi(1, _vp.size.x), maxi(1, _vp.size.y))


func _update_effects(delta: float, ratio: float, throttle: bool) -> void:
	var exhausted: bool = (not demo) and G.is_exhausted
	var black: bool = exhausted or (_spec().diesel and throttle)
	var turbo_on := not demo and G.turbo_time > 0.0
	if throttle and ratio > 0.8 and randf() < (0.5 + (2.5 if turbo_on else 0.0)) * delta:
		_pop_flame()
	var flame_col := Color(1.0, 0.55, 0.15)
	if turbo_on:
		flame_col = Color(0.35, 0.65, 1.0)
	if not demo and G.ultra > 0:
		flame_col = _ultra_color()
	# события по смене состояния
	if turbo_on != _was_turbo:
		_was_turbo = turbo_on
		if not turbo_on:
			fx_event("turbo_end")
	if exhausted != _was_exhausted:
		_was_exhausted = exhausted
		fx_event("exhausted" if exhausted else "recovered")
	var st := {
		"ratio": ratio, "rpm": rpm, "throttle": throttle, "turbo": turbo_on,
		"turbo_t": clampf(G.turbo_time / G.TURBO_TIME, 0.0, 1.0) if turbo_on else 0.0,
		"heat": heat, "exhausted": exhausted, "black": black, "flame_col": flame_col,
		"ultra": (not demo) and G.ultra > 0, "diesel": bool(_spec().diesel), "demo": demo,
		"time": _time, "xray": _xray(), "garage": locked, "limiter": _limiter_t > 0.0,
	}
	for m in _fx:
		m.update(delta, st)
	GarageScene.update(_garage, delta, st)
	if _warm_frames > 0:
		_warm_frames -= 1
		if _warm_frames == 0:
			for w in _xray_warmers:
				if is_instance_valid(w):
					w.queue_free()
			_xray_warmers.clear()
			for m in _fx:
				m.warmup(false)
		for cy in _cyls:
			cy.flash.visible = true


func _update_tints() -> void:
	if _mats.is_empty():
		return
	var h := clampf((heat - 0.45) / 0.55, 0.0, 1.0)
	var mc: Color = D.MATERIALS[material_index % D.MATERIALS.size()].color
	var hot := Color(0.85, 0.18, 0.08)
	var base := {"block": _part_color("block", mc.lightened(0.05)), "head": _part_color("head", mc.lightened(0.15)),
		"piston": _part_color("pistons", Color("d4d9df")), "crank": _part_color("crank", Color("6f767e"))}
	for key in base:
		var m: StandardMaterial3D = _mats[key]
		var col: Color = base[key].lerp(hot, h * (0.5 if key != "crank" else 0.2))
		m.albedo_color = Color(col.r, col.g, col.b, m.albedo_color.a)
		var glow := _part_glow(key)
		m.emission = hot * h * 0.5 + _glow_color(key) * glow
	# коллектор: побежалость и красное свечение от нагрева и оборотов
	var hm: StandardMaterial3D = _mats.header
	var ratio := clampf(rpm / float(_spec().rpm), 0.0, 1.0)
	var glow_amt := clampf(heat * 0.9 + ratio * 0.5 - 0.2, 0.0, 1.0)
	if demo:
		glow_amt = clampf(ratio - 0.4, 0.0, 0.6)
	var hc := _part_color("exhaust", Color("8a8a8f"))
	hm.albedo_color = hc.lerp(Color("6a5a7a"), clampf(heat + ratio * 0.3, 0.0, 1.0) * 0.5)
	hm.emission = Color(1.0, 0.2, 0.03) * glow_amt * glow_amt * 0.85
	if _xray() != (_mats.block.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA):
		_apply_xray()


func _slot_for(key: String) -> String:
	return {"block": "block", "head": "head", "piston": "pistons", "crank": "crank", "exhaust": "exhaust"}.get(key, "")


func _part_color(slot_id: String, fallback: Color) -> Color:
	if demo:
		return fallback
	var it: Dictionary = G.equipped(slot_id)
	if it.is_empty():
		return fallback
	return fallback.lerp(D.mark_color(int(it.mk)), 0.45)


func _part_glow(key: String) -> float:
	if demo:
		return 0.0
	var it: Dictionary = G.equipped(_slot_for(key))
	if it.is_empty():
		return 0.0
	return D.mark_glow(int(it.mk)) * 0.5


func _glow_color(key: String) -> Color:
	var it: Dictionary = G.equipped(_slot_for(key)) if not demo else {}
	if it.is_empty():
		return Color.BLACK
	return D.RARITIES[int(it.rar)].color


func _ultra_color() -> Color:
	var hue := fmod(0.75 + 0.13 * maxi(G.ultra, 1), 1.0)
	return Color.from_hsv(hue, 0.7, 1.0)


# ---------------------------------------------------------------------
# 2D поверх: кружок турбо, белая вспышка
# ---------------------------------------------------------------------

const RING_SHADER := """
shader_type canvas_item;
render_mode blend_premul_alpha;
uniform float progress = 1.0;
uniform vec4 arc_col : source_color = vec4(0.5, 1.0, 0.5, 0.8);
void fragment() {
	vec2 p = (UV - 0.5) * 60.0;
	float ring = clamp(3.5 - abs(length(p) - 22.0), 0.0, 1.0);
	float a01 = fract(atan(p.x, -p.y) / 6.2831853 + 1.0);
	float on = step(a01, progress) * ring;
	vec4 col = vec4(vec3(0.15), 0.15) * ring;
	float a = arc_col.a * on;
	COLOR = vec4(arc_col.rgb * a + col.rgb * (1.0 - a), a + col.a * (1.0 - a));
}
"""

static var _ring_shader: Shader


## Кольцо турбо над мотором: шейдер на квадрате 60×60, каждый кадр меняются только параметры.
func _make_turbo_ring() -> void:
	if _ring_shader == null:
		_ring_shader = Shader.new()
		_ring_shader.code = RING_SHADER
	_ring_mat = ShaderMaterial.new()
	_ring_mat.shader = _ring_shader
	_ring = ColorRect.new()
	_ring.material = _ring_mat
	_ring.size = Vector2(60, 60)
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.visible = false
	add_child(_ring)


func _update_turbo_ring() -> void:
	var on := show_hud and not demo and not locked and G.d_turbo_on
	if on != _ring.visible:
		_ring.visible = on
	if not on:
		return
	_ring.position = Vector2(size.x * (band.position.x + band.size.x * 0.5), size.y * band.position.y + 34.0) - Vector2(30, 30)
	var prog := 1.0
	var mode := 0.0
	if G.turbo_time > 0.0:
		prog = G.turbo_time / G.TURBO_TIME
		mode = 1.0
	elif G.turbo_cd > 0.0:
		prog = 1.0 - G.turbo_cd / G.d_turbo_cd
		mode = 2.0
	prog = snappedf(clampf(prog, 0.0, 1.0), 0.004)
	if mode != _ring_sent.y:
		_ring_mat.set_shader_parameter("arc_col", [Color(0.5, 1.0, 0.5, 0.8), Color(0.35, 0.65, 1.0), Color(1.0, 0.55, 0.15)][int(mode)])
	if prog != _ring_sent.x:
		_ring_mat.set_shader_parameter("progress", prog)
	_ring_sent = Vector3(prog, mode, 1.0)


func _draw_hud() -> void:
	if flash_white > 0.0:
		_hud.draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, flash_white))
