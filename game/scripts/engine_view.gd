extends Control
## Мотор в 3D. Модель собирается кодом из простых деталей (блок в разрезе, поршни, шатуны,
## коленвал, ГБЦ, выхлоп, турбина). Поршни и шатуны считаются по геометрии кривошипа,
## у каждого цилиндра своя фаза по порядку зажигания, поэтому любой мотор анимируется сам.
## Пальцем можно покрутить мотор (провести влево-вправо), зажатие даёт газ.

signal hold_changed(pressed: bool)

const ROD := 3.0          # длина шатуна в радиусах кривошипа
const BORE := 1.12        # радиус поршня
const DECK := 4.7
const HEAD := 1.1
const SPACING := 2.9

var engine_type: String = "inline4"
var material_index: int = 0
var demo: bool = false            # загрузка/витрина: обороты задаются снаружи
var demo_rpm: float = 900.0
var interactive: bool = true
var crank_deg: float = 0.0
var rpm: float = 800.0
var heat: float = 0.0
var shake_offset: Vector2 = Vector2.ZERO
var flash_white: float = 0.0
var show_hud: bool = true
var drives_audio: bool = true

var _container: SubViewportContainer
var _vp: SubViewport
var _world: Node3D
var _cam: Camera3D
var _root: Node3D            # всё, что трясётся
var _engine: Node3D          # собранный мотор
var _hud: Control
var _flash_light: OmniLight3D
var _turbo_light: OmniLight3D
var _smoke: CPUParticles3D
var _flames: CPUParticles3D
var _steam: CPUParticles3D
var _cyls: Array = []
var _shafts: Array = []
var _rotors: Array = []
var _turbine_wheel: Node3D = null
var _flywheel: Node3D = null
var _mats: Dictionary = {}
var _built_key: String = ""
var _center: Vector3 = Vector3.ZERO
var _radius: float = 6.0
var _yaw: float = 0.0
var _yaw_target: float = 0.0
var _pressed: bool = false
var _drag_px: float = 0.0
var _time: float = 0.0
var _prev_throttle: bool = false
var _turbine_deg: float = 0.0
var _tint_acc: float = 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_container = SubViewportContainer.new()
	_container.stretch = true
	_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_container)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_container.add_child(_vp)
	_world = Node3D.new()
	_vp.add_child(_world)
	_setup_world()
	_hud = Control.new()
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.draw.connect(_draw_hud)
	add_child(_hud)
	_rebuild()


func set_engine(type: String, material: int) -> void:
	engine_type = type
	material_index = material
	if is_inside_tree():
		_rebuild()


func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_pressed = event.pressed
		_drag_px = 0.0
		hold_changed.emit(event.pressed)
		accept_event()
	elif event is InputEventMouseMotion and _pressed:
		_drag_px += absf(event.relative.x)
		_yaw_target = clampf(_yaw_target - event.relative.x * 0.006, -1.4, 1.4)
		accept_event()


# ---------------------------------------------------------------------
# Сцена: свет, окружение, частицы
# ---------------------------------------------------------------------

func _setup_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.52, 0.5)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)

	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.9, 0.75)
	key.light_energy = 1.25
	key.shadow_enabled = true
	key.rotation_degrees = Vector3(-58, 35, 0)
	_world.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(0.45, 0.6, 1.0)
	rim.light_energy = 0.55
	rim.rotation_degrees = Vector3(-20, -150, 0)
	_world.add_child(rim)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.82, 0.55)
	lamp.light_energy = 1.2
	lamp.omni_range = 30.0
	lamp.position = Vector3(0, 12, 4)
	_world.add_child(lamp)

	_cam = Camera3D.new()
	_cam.fov = 32.0
	_world.add_child(_cam)

	_root = Node3D.new()
	_world.add_child(_root)

	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.55, 0.15)
	_flash_light.omni_range = 4.0
	_flash_light.light_energy = 0.0
	_root.add_child(_flash_light)
	_turbo_light = OmniLight3D.new()
	_turbo_light.light_color = Color(0.3, 0.55, 1.0)
	_turbo_light.omni_range = 14.0
	_turbo_light.light_energy = 0.0
	_root.add_child(_turbo_light)

	_smoke = _make_particles(Color(0.8, 0.8, 0.85, 0.35), 0.5, 1.6, 40)
	_smoke.direction = Vector3(0.3, 1, 0.2)
	_smoke.initial_velocity_min = 0.8
	_smoke.initial_velocity_max = 1.8
	_smoke.gravity = Vector3(0, 0.6, 0)
	_flames = _make_particles(Color(1.0, 0.6, 0.15, 1.0), 0.35, 0.25, 24, true)
	_flames.direction = Vector3(0.6, -0.2, 0.3)
	_flames.initial_velocity_min = 3.0
	_flames.initial_velocity_max = 6.0
	_flames.gravity = Vector3.ZERO
	_flames.emitting = false
	_flames.one_shot = true
	_flames.explosiveness = 1.0
	_steam = _make_particles(Color(0.95, 0.95, 1.0, 0.3), 0.6, 1.4, 30)
	_steam.direction = Vector3(0, 1, 0)
	_steam.initial_velocity_min = 1.0
	_steam.initial_velocity_max = 2.0
	_steam.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_steam.emission_box_extents = Vector3(3, 0.2, 1)
	_steam.emitting = false


func _make_particles(color: Color, size: float, life: float, amount: int, glow: bool = false) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_dot()
	if glow:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	quad.material = m
	p.mesh = quad
	p.amount = amount
	p.lifetime = life
	p.spread = 15.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.5))
	curve.add_point(Vector2(1, 1.8 if not glow else 0.2))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, color)
	grad.set_color(1, Color(color.r, color.g, color.b, 0.0))
	p.color_ramp = grad
	p.local_coords = false
	_root.add_child(p)
	return p


var _dot_tex: Texture2D = null

func _soft_dot() -> Texture2D:
	if _dot_tex != null:
		return _dot_tex
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, y - 15.5).length() / 15.5
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	_dot_tex = ImageTexture.create_from_image(img)
	return _dot_tex


# ---------------------------------------------------------------------
# Материалы и примитивы
# ---------------------------------------------------------------------

func _mat(color: Color, metallic: float = 0.6, rough: float = 0.4, alpha: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.metallic = metallic
	m.roughness = rough
	m.metallic_specular = 0.6
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _mi(mesh: Mesh, mat: Material, parent: Node3D, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.rotation_degrees = rot_deg
	parent.add_child(m)
	return m


func _cyl(r: float, h: float, segs: int = 24) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c


func _box(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b


## Половина трубы (гильза цилиндра в разрезе), открыта в сторону +Z.
func _half_tube(r_in: float, r_out: float, h: float, segs: int = 18) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a0 := PI * 0.5
	var a1 := PI * 1.5
	var y0 := -h * 0.5
	var y1 := h * 0.5
	for i in segs:
		var t0 := lerpf(a0, a1, float(i) / segs)
		var t1 := lerpf(a0, a1, float(i + 1) / segs)
		var c0 := Vector3(sin(t0), 0, cos(t0))
		var c1 := Vector3(sin(t1), 0, cos(t1))
		for r in [r_out, r_in]:
			_quad(st, c0 * r + Vector3(0, y0, 0), c1 * r + Vector3(0, y0, 0), c1 * r + Vector3(0, y1, 0), c0 * r + Vector3(0, y1, 0))
		for y in [y0, y1]:
			_quad(st, c0 * r_in + Vector3(0, y, 0), c1 * r_in + Vector3(0, y, 0), c1 * r_out + Vector3(0, y, 0), c0 * r_out + Vector3(0, y, 0))
	for t in [a0, a1]:
		var c := Vector3(sin(t), 0, cos(t))
		_quad(st, c * r_in + Vector3(0, y0, 0), c * r_out + Vector3(0, y0, 0), c * r_out + Vector3(0, y1, 0), c * r_in + Vector3(0, y1, 0))
	st.generate_normals()
	return st.commit()


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)


## Выдавливание плоского многоугольника (в плоскости YZ) вдоль X.
func _extrude(poly: PackedVector2Array, depth: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var idx := Geometry2D.triangulate_polygon(poly)
	for side in [-0.5, 0.5]:
		for i in range(0, idx.size(), 3):
			for k in 3:
				var p := poly[idx[i + k]]
				st.add_vertex(Vector3(side * depth, p.x, p.y))
	var n := poly.size()
	for i in n:
		var p0 := poly[i]
		var p1 := poly[(i + 1) % n]
		_quad(st, Vector3(-depth * 0.5, p0.x, p0.y), Vector3(-depth * 0.5, p1.x, p1.y),
			Vector3(depth * 0.5, p1.x, p1.y), Vector3(depth * 0.5, p0.x, p0.y))
	st.generate_normals()
	return st.commit()


## Кольцо между двумя контурами с одинаковым числом точек, выдавленное вдоль X.
func _extrude_ring(inner: PackedVector2Array, outer: PackedVector2Array, depth: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := inner.size()
	var x0 := -depth * 0.5
	var x1 := depth * 0.5
	for i in n:
		var j := (i + 1) % n
		var a := inner[i]
		var b := inner[j]
		var c := outer[j]
		var d := outer[i]
		for x in [x0, x1]:
			_quad(st, Vector3(x, a.x, a.y), Vector3(x, b.x, b.y), Vector3(x, c.x, c.y), Vector3(x, d.x, d.y))
		_quad(st, Vector3(x0, a.x, a.y), Vector3(x0, b.x, b.y), Vector3(x1, b.x, b.y), Vector3(x1, a.x, a.y))
		_quad(st, Vector3(x0, d.x, d.y), Vector3(x0, c.x, c.y), Vector3(x1, c.x, c.y), Vector3(x1, d.x, d.y))
	st.generate_normals()
	return st.commit()


func _pipe(parent: Node3D, a: Vector3, b: Vector3, r: float, mat: Material) -> MeshInstance3D:
	var dir := b - a
	var m := _mi(_cyl(r, dir.length(), 12), mat, parent, (a + b) * 0.5)
	m.basis = Basis(Quaternion(Vector3.UP, dir.normalized()))
	return m


# ---------------------------------------------------------------------
# Раскладка цилиндров (ряд — позиция вдоль коленвала, bank — угол наклона)
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
			return Vector3(0.42, 0.38, 0.82).normalized()
		"rotary":
			return Vector3(0.85, 0.3, 0.45).normalized()
	return Vector3(0.82, 0.4, 0.42).normalized()


# ---------------------------------------------------------------------
# Сборка модели
# ---------------------------------------------------------------------

func _build_key() -> String:
	var tur := "0" if demo else ("1" if not G.equipped("turbine").is_empty() else "0")
	var race := "0" if demo else ("1" if D.epoch_info(G.level).racing else "0")
	return "%s|%d|%s|%s" % [engine_type, material_index, tur, race]


func _rebuild() -> void:
	_built_key = _build_key()
	if _engine != null:
		_engine.queue_free()
	_engine = Node3D.new()
	_root.add_child(_engine)
	_cyls.clear()
	_shafts.clear()
	_rotors.clear()
	_turbine_wheel = null
	_flywheel = null

	var mc: Color = D.MATERIALS[material_index % D.MATERIALS.size()].color
	var shine: float = D.MATERIALS[material_index % D.MATERIALS.size()].shine
	_mats = {
		"block": _mat(mc.lightened(0.05), 0.35 + shine * 0.5, 0.55 - shine * 0.3),
		"case": _mat(mc.darkened(0.1), 0.3 + shine * 0.4, 0.6, 0.55),
		"head": _mat(mc.lightened(0.15), 0.4 + shine * 0.5, 0.45 - shine * 0.2),
		"cover": _mat(Color("b81d1d") if _build_key().split("|")[3] == "1" else mc.darkened(0.35), 0.5, 0.35),
		"bore": _mat(Color("1a1b1f"), 0.2, 0.8),
		"piston": _mat(Color("cfd4da"), 0.85, 0.25),
		"rod": _mat(Color("9aa1a9"), 0.9, 0.3),
		"crank": _mat(Color("7f868e"), 0.9, 0.3),
		"steel": _mat(Color("b5bcc4"), 0.95, 0.2),
		"plug": _mat(Color("efe9da"), 0.1, 0.4),
		"exhaust": _mat(Color("6b5e55"), 0.7, 0.45),
		"stand": _mat(Color("3a3f47"), 0.7, 0.45),
		"flash": _mat(Color(1.0, 0.55, 0.15), 0.0, 1.0, 0.0),
	}
	var fm: StandardMaterial3D = _mats.flash
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	if D.MATERIALS[material_index % D.MATERIALS.size()].get("weave", false):
		_mats.block.albedo_texture = _weave_tex()
		_mats.head.albedo_texture = _weave_tex()

	if _spec().view == "rotary":
		_build_rotary()
	else:
		_build_piston_engine()
	_build_exhaust()
	_build_stand()
	_fit_camera()
	_apply_xray()


func _weave_tex() -> Texture2D:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var on := ((x / 4) + (y / 4)) % 2 == 0
			var v := 0.55 + (0.25 if on else 0.0) + 0.1 * float((x + y) % 4 == 0)
			img.set_pixel(x, y, Color(v, v, v))
	var t := ImageTexture.create_from_image(img)
	return t


func _rows_info() -> Dictionary:
	var layout := _layout()
	var rows := 0
	for c in layout:
		rows = maxi(rows, int(c.row) + 1)
	return {"layout": layout, "rows": rows}


func _row_x(row: int, rows: int) -> float:
	return (row - (rows - 1) * 0.5) * SPACING


func _build_piston_engine() -> void:
	var info := _rows_info()
	var rows: int = info.rows
	var layout: Array = info.layout
	var short := engine_type == "radial"
	var rod_len := ROD * (0.85 if short else 1.0)
	var deck := rod_len + 1.7
	# коленвал целиком
	var length := rows * SPACING + 1.6
	var shaft := Node3D.new()
	_engine.add_child(shaft)
	_mi(_cyl(0.42, length, 16), _mats.crank, shaft, Vector3.ZERO, Vector3(0, 0, 90))
	_shafts.append(shaft)
	# маховик и шкив
	_flywheel = Node3D.new()
	_flywheel.position = Vector3(-length * 0.5 - 0.25, 0, 0)
	_engine.add_child(_flywheel)
	_mi(_cyl(2.0, 0.35, 32), _mats.steel, _flywheel, Vector3.ZERO, Vector3(0, 0, 90))
	for k in 6:
		_mi(_box(Vector3(0.4, 0.25, 0.6)), _mats.crank, _flywheel, Vector3(0, cos(k * TAU / 6) * 1.6, sin(k * TAU / 6) * 1.6))
	var pulley := Node3D.new()
	pulley.position = Vector3(length * 0.5 + 0.2, 0, 0)
	_engine.add_child(pulley)
	_mi(_cyl(0.9, 0.3, 24), _mats.crank, pulley, Vector3.ZERO, Vector3(0, 0, 90))
	_shafts.append(pulley)
	# картер
	var case_w := rows * SPACING + 0.4
	_mi(_box(Vector3(case_w, 2.6, 3.4)), _mats.case, _engine, Vector3(0, -0.4, 0))
	_mi(_box(Vector3(case_w - 0.4, 0.7, 2.8)), _mats.block, _engine, Vector3(0, -2.0, 0))

	var bank_count := {}
	for c in layout:
		bank_count[c.bank] = true
	var banks: Array = bank_count.keys()
	banks.sort()
	for c in layout:
		var frame := Node3D.new()
		var bi := banks.find(c.bank)
		var bx := 0.0
		if banks.size() > 1 and engine_type != "radial":
			bx = (bi - (banks.size() - 1) * 0.5) * 0.42
		frame.position = Vector3(_row_x(int(c.row), rows) + bx, 0, 0)
		frame.rotation_degrees = Vector3(c.bank, 0, 0)
		_engine.add_child(frame)
		var cy := {"frame": frame, "tdc": float(c.tdc), "deck": deck, "fins": []}
		# гильза в разрезе + стенки
		var liner_h := deck - 1.2
		var liner := _mi(_half_tube(BORE + 0.06, BORE + 0.38, liner_h), _mats.block, frame, Vector3(0, 1.2 + liner_h * 0.5, 0))
		cy.liner = liner
		var bore := _mi(_half_tube(BORE + 0.02, BORE + 0.06, liner_h), _mats.bore, frame, Vector3(0, 1.2 + liner_h * 0.5, 0))
		cy.bore = bore
		# ГБЦ, крышка, свеча
		var head := _mi(_box(Vector3(SPACING * 0.92 if banks.size() == 1 else 2.7, HEAD, 3.0)), _mats.head, frame, Vector3(0, deck + HEAD * 0.5, 0))
		cy.head = head
		_mi(_box(Vector3(SPACING * 0.8 if banks.size() == 1 else 2.4, 0.45, 2.4)), _mats.cover, frame, Vector3(0, deck + HEAD + 0.22, 0))
		if not _spec().diesel:
			_mi(_cyl(0.12, 0.7, 10), _mats.plug, frame, Vector3(0, deck + HEAD + 0.6, 0.6))
			_mi(_cyl(0.18, 0.25, 10), _mats.steel, frame, Vector3(0, deck + HEAD + 0.95, 0.6))
		else:
			_mi(_cyl(0.16, 0.8, 10), _mats.steel, frame, Vector3(0, deck + HEAD + 0.6, 0.6))
		# рёбра охлаждения (для одноцилиндрового и звезды)
		if engine_type in ["single", "radial"]:
			for k in 5:
				cy.fins.append(_mi(_half_tube(BORE + 0.38, BORE + 0.75, 0.12), _mats.block, frame, Vector3(0, 2.0 + k * 0.55, 0)))
		# клапаны
		var valves: Array = []
		for side in [-1, 1]:
			var v := Node3D.new()
			v.position = Vector3(side * 0.45, deck, 0)
			frame.add_child(v)
			_mi(_cyl(0.07, HEAD * 0.9, 8), _mats.steel, v, Vector3(0, HEAD * 0.45, 0))
			_mi(_cyl(0.33, 0.08, 16), _mats.steel, v, Vector3(0, 0.04, 0))
			valves.append(v)
		cy.valves = valves
		# вспышка в камере
		var fl := _mi(SphereMesh.new(), _mats.flash, frame, Vector3(0, deck - 0.35, 0))
		fl.scale = Vector3(BORE * 1.9, 0.6, BORE * 1.9)
		cy.flash = fl
		# поршень
		var piston := Node3D.new()
		frame.add_child(piston)
		_mi(_cyl(BORE, 1.3, 24), _mats.piston, piston, Vector3(0, 0.0, 0))
		for k in 2:
			_mi(_cyl(BORE + 0.01, 0.07, 24), _mats.crank, piston, Vector3(0, 0.45 - k * 0.18, 0))
		_mi(_cyl(0.18, BORE * 1.6, 10), _mats.steel, piston, Vector3(0, 0.15, 0), Vector3(0, 0, 90))
		cy.piston = piston
		# шатун
		var rod := Node3D.new()
		frame.add_child(rod)
		cy.rod_len = rod_len
		_mi(_box(Vector3(0.28, rod_len, 0.38)), _mats.rod, rod, Vector3(0, rod_len * 0.5, 0))
		_mi(_cyl(0.42, 0.34, 16), _mats.rod, rod, Vector3.ZERO, Vector3(0, 0, 90))
		cy.rod = rod
		# кривошип
		var throw := Node3D.new()
		frame.add_child(throw)
		_mi(_box(Vector3(0.22, 1.5, 0.75)), _mats.crank, throw, Vector3(0.24, 0.35, 0))
		_mi(_box(Vector3(0.22, 1.5, 0.75)), _mats.crank, throw, Vector3(-0.24, 0.35, 0))
		_mi(_cyl(0.75, 0.22, 16), _mats.crank, throw, Vector3(0.24, -0.45, 0), Vector3(0, 0, 90))
		_mi(_cyl(0.75, 0.22, 16), _mats.crank, throw, Vector3(-0.24, -0.45, 0), Vector3(0, 0, 90))
		_mi(_cyl(0.3, 0.5, 12), _mats.steel, throw, Vector3(0, 1.0, 0), Vector3(0, 0, 90))
		cy.throw = throw
		# выпускной патрубок
		_pipe(frame, Vector3(0, deck + HEAD * 0.4, -1.2), Vector3(0, deck + HEAD * 0.3, -2.1), 0.28, _mats.exhaust)
		_cyls.append(cy)


func _build_rotary() -> void:
	var e := 0.7
	var R := 3.6
	var inner := PackedVector2Array()
	var outer := PackedVector2Array()
	for i in 72:
		var a := TAU * i / 72.0
		var p := Vector2(e * cos(3.0 * a) + R * cos(a) * 1.04, e * sin(3.0 * a) + R * sin(a) * 1.04)
		inner.append(p)
		outer.append(p * 1.25)
	var shaft := Node3D.new()
	_engine.add_child(shaft)
	_mi(_cyl(0.5, 5.0, 16), _mats.crank, shaft, Vector3.ZERO, Vector3(0, 0, 90))
	_shafts.append(shaft)
	_flywheel = Node3D.new()
	_flywheel.position = Vector3(-2.8, 0, 0)
	_engine.add_child(_flywheel)
	_mi(_cyl(2.2, 0.35, 32), _mats.steel, _flywheel, Vector3.ZERO, Vector3(0, 0, 90))
	var tri := PackedVector2Array()
	for k in 3:
		var a0 := TAU * k / 3.0
		var a1 := TAU * (k + 1) / 3.0
		var v0 := Vector2(cos(a0), sin(a0)) * R
		var v1 := Vector2(cos(a1), sin(a1)) * R
		for s in 8:
			var t := s / 8.0
			var mid := v0.lerp(v1, t)
			tri.append(mid + (-mid).normalized() * -sin(PI * t) * 0.35)
	for i in 2:
		var x := -0.9 + i * 1.8
		_mi(_extrude_ring(inner, outer, 1.2), _mats.block, _engine, Vector3(x, 0, 0))
		# задняя стенка корпуса
		_mi(_extrude(outer, 0.15), _mats.bore, _engine, Vector3(x - 0.62, 0, 0))
		var rotor := Node3D.new()
		rotor.position = Vector3(x, 0, 0)
		_engine.add_child(rotor)
		var body := _mi(_extrude(tri, 1.0), _mats.piston, rotor)
		_mi(_cyl(1.1, 1.05, 24), _mats.crank, body, Vector3.ZERO, Vector3(0, 0, 90))
		var fl := _mi(SphereMesh.new(), _mats.flash, _engine, Vector3(x, 0, -R * 0.8))
		fl.scale = Vector3(1.0, 2.2, 1.2)
		_rotors.append({"node": rotor, "phase": PI * i, "flash": fl})
		# свечи
		for k in 2:
			_mi(_cyl(0.13, 0.9, 10), _mats.plug, _engine, Vector3(x, -0.6 + 1.2 * k, -R * 1.33), Vector3(90, 0, 0))
	_mi(_box(Vector3(4.2, 1.0, 3.0)), _mats.case, _engine, Vector3(0, -R * 1.25 - 0.4, 0))


func _build_exhaust() -> void:
	var info := _rows_info()
	var rows: int = maxi(1, info.rows)
	var end_x := (rows * SPACING) * 0.5 + 1.2
	if _spec().view == "rotary":
		end_x = 2.0
	# коллектор → глушитель
	var start := Vector3(0, DECK * 0.6, -2.4)
	if _spec().view == "rotary":
		start = Vector3(0, 0, -4.8)
	# глушитель сзади мотора, чтобы не закрывал вид
	var muff_pos := Vector3(end_x * 0.5, -1.2, -3.6)
	if _spec().view == "rotary":
		muff_pos = Vector3(0.5, -2.0, -5.6)
	_pipe(_engine, Vector3(-end_x + 1.2, start.y, start.z), Vector3(end_x, start.y, start.z), 0.35, _mats.exhaust)
	_pipe(_engine, Vector3(end_x, start.y, start.z), muff_pos + Vector3(-0.2, 0.9, 0), 0.32, _mats.exhaust)
	var muff := _mi(_cyl(0.75, 2.2, 20), _mats.exhaust, _engine, muff_pos)
	muff.name = "muffler"
	var tail := muff_pos + Vector3(0.0, 1.6, -0.6)
	_pipe(_engine, muff_pos + Vector3(0, 0.9, 0), tail, 0.22, _mats.steel)
	_smoke.position = tail
	_flames.position = tail
	_steam.position = Vector3(0, DECK + HEAD + 1.2, 0)
	# турбина
	var has_turbine := not demo and not G.equipped("turbine").is_empty()
	if has_turbine:
		var tp := Vector3(end_x + 0.2, start.y + 1.2, start.z)
		var housing := _mi(TorusMesh.new(), _mats.steel, _engine, tp, Vector3(90, 0, 0))
		housing.scale = Vector3(1.4, 1.4, 1.4)
		_turbine_wheel = Node3D.new()
		_turbine_wheel.position = tp
		_engine.add_child(_turbine_wheel)
		for k in 8:
			var blade := _mi(_box(Vector3(0.12, 0.9, 0.3)), _mats.piston, _turbine_wheel, Vector3.ZERO)
			blade.rotation = Vector3(0, 0, TAU * k / 8.0)
			blade.position = Vector3(cos(TAU * k / 8.0 + PI * 0.5), sin(TAU * k / 8.0 + PI * 0.5), 0) * -0.45
		_turbo_light.position = tp
	else:
		_turbo_light.position = Vector3(0, 3, 2)


func _build_stand() -> void:
	# стенд: основание под мотором и стойки, держащие коленвал с торцов
	var box := _engine_aabb()
	var y := box.position.y - 0.5
	var half := box.size.x * 0.5 + 0.3
	var cx := box.get_center().x
	_mi(_box(Vector3(box.size.x + 1.4, 0.35, maxf(3.6, box.size.z * 0.7))), _mats.stand, _engine, Vector3(cx, y, 0))
	for sx in [-1, 1]:
		var px: float = cx + sx * half
		_mi(_box(Vector3(0.4, -y, 0.5)), _mats.stand, _engine, Vector3(px, y * 0.5, 0))
		_mi(_cyl(0.35, 0.5, 12), _mats.steel, _engine, Vector3(px, 0, 0), Vector3(0, 0, 90))
		_mi(_box(Vector3(0.6, 0.12, 2.4)), _mats.stand, _engine, Vector3(px, y + 0.2, 0))
	var floor_m := StandardMaterial3D.new()
	floor_m.albedo_color = Color(0, 0, 0, 0.55)
	floor_m.shadow_to_opacity = true
	floor_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	_mi(plane, floor_m, _engine, Vector3(0, y - 0.18, 0))


func _engine_aabb() -> AABB:
	var aabb := AABB()
	var first := true
	for n in _engine.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		if mi.mesh is PlaneMesh:
			continue
		var b: AABB = _engine.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
		if first:
			aabb = b
			first = false
		else:
			aabb = aabb.merge(b)
	return aabb


func _fit_camera() -> void:
	var aabb := _engine_aabb()
	_center = aabb.get_center()
	_radius = aabb.size.length() * 0.5
	_place_camera()


func _place_camera() -> void:
	var dir := _view_dir().rotated(Vector3.UP, _yaw)
	var aspect := maxf(0.3, size.x / maxf(size.y, 1.0))
	var half_v := deg_to_rad(_cam.fov * 0.5)
	var half_h := atan(tan(half_v) * aspect)
	var dist := _radius / sin(minf(half_v, half_h)) * 0.92
	_cam.position = _center + dir * dist
	_cam.look_at(_center + Vector3(0, -_radius * 0.05, 0), Vector3.UP)


func _apply_xray() -> void:
	var xr := _xray()
	var a := 0.25 if xr else 1.0
	for key in ["block", "head", "cover"]:
		var m: StandardMaterial3D = _mats[key]
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if xr else BaseMaterial3D.TRANSPARENCY_DISABLED
		m.albedo_color.a = a
	var cm: StandardMaterial3D = _mats.case
	cm.albedo_color.a = 0.15 if xr else 0.55


func _xray() -> bool:
	return (not demo) and (G.settings.xray or G.ultra > 0)


# ---------------------------------------------------------------------
# Обновление
# ---------------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	if _engine == null:
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
		elif G.is_exhausted:
			target = idle * (0.75 + 0.2 * sin(_time * 9.0))
		var k := 3.2 if target > rpm else 1.6
		rpm = lerpf(rpm, target, 1.0 - exp(-delta * k))
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
	crank_deg = fmod(crank_deg + 360.0 * rev_per_s * delta, 720.0)
	var ratio := clampf(rpm / max_rpm, 0.0, 1.2)
	_animate(ratio)

	# тряска мотора и камеры
	var amp := 0.0
	if demo or G.settings.shake:
		amp = (0.012 + 0.09 * ratio * ratio) * float(spec.balance)
		if not demo:
			amp *= G.d_shake_mult
			if G.is_exhausted:
				amp *= 1.6
	var n := Vector3(sin(_time * 53.0) + 0.5 * sin(_time * 97.0), cos(_time * 61.0) + 0.5 * sin(_time * 83.0), sin(_time * 71.0))
	_root.position = n * amp * 0.6
	_root.rotation = Vector3(n.y, 0, n.x) * amp * 0.05
	shake_offset = Vector2(n.x, n.y) * amp * 25.0

	# камера: лёгкое покачивание и поворот пальцем
	if not _pressed:
		_yaw_target = lerpf(_yaw_target, 0.18 * sin(_time * 0.25), 1.0 - exp(-delta * 0.6))
	_yaw = lerpf(_yaw, _yaw_target, 1.0 - exp(-delta * 8.0))
	_place_camera()

	_update_effects(delta, ratio, throttle)
	flash_white = maxf(0.0, flash_white - delta * 2.5)
	_tint_acc += delta
	if _tint_acc >= 0.25:
		_tint_acc = 0.0
		_update_tints()

	if drives_audio:
		Sfx.rpm = rpm
		Sfx.max_rpm = max_rpm
		Sfx.cylinders = spec.cyl
		Sfx.pitch = spec.pitch
		Sfx.diesel = spec.diesel
		Sfx.engine_type = engine_type
		Sfx.turbo_level = 0.0 if demo else (1.0 if G.turbo_time > 0.0 else (0.35 * ratio if _turbine_wheel != null else 0.0))
	_hud.queue_redraw()


func _animate(_ratio: float) -> void:
	var cam_pos := _cam.global_position
	var max_flash := 0.0
	var flash_pos := Vector3.ZERO
	var ultra := not demo and G.ultra > 0
	for s in _shafts:
		s.rotation.x = deg_to_rad(crank_deg)
	if _flywheel != null:
		_flywheel.rotation.x = deg_to_rad(crank_deg)
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
		# клапаны: выпуск 160–380°, впуск 340–560° цикла
		var c := fposmod(crank_deg - cy.tdc, 720.0)
		cy.valves[0].position.y = cy.deck - 0.3 * _valve_lift(c, 340.0, 560.0)
		cy.valves[1].position.y = cy.deck - 0.3 * _valve_lift(c, 160.0, 380.0)
		var f := 1.0 - c / 60.0 if c < 60.0 else 0.0
		cy.flash.visible = f > 0.01
		if f > max_flash:
			max_flash = f
			flash_pos = cy.frame.to_global(Vector3(0, cy.deck - 0.4, 0))
		cy.flash.scale = Vector3(BORE * 1.9, 0.4 + 0.5 * f, BORE * 1.9)
		# разрез гильзы всегда смотрит на камеру
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
	# общий материал вспышки
	var flm: StandardMaterial3D = _mats.flash
	var fc := Color(1.0, 0.55, 0.15)
	if _spec().diesel:
		fc = Color(1.0, 0.75, 0.4)
	if ultra:
		fc = _ultra_color()
	flm.albedo_color = Color(fc.r, fc.g, fc.b, 0.85)
	_flash_light.light_color = fc
	_flash_light.position = _root.to_local(flash_pos) if max_flash > 0.0 else _flash_light.position
	_flash_light.light_energy = 3.0 * max_flash
	if _turbine_wheel != null:
		_turbine_deg = fmod(_turbine_deg + (200.0 + rpm * rpm / 25000.0) * get_process_delta_time() * (2.0 if G.turbo_time > 0.0 else 1.0), 360.0)
		_turbine_wheel.rotation.x = deg_to_rad(_turbine_deg)


func _valve_lift(c: float, a: float, b: float) -> float:
	var cc := c
	if cc < a and cc + 720.0 <= b:
		cc += 720.0
	if cc < a or cc > b:
		return 0.0
	return sin(PI * (cc - a) / (b - a))


func _pop_flame() -> void:
	Sfx.pop()
	_flames.restart()
	_flames.emitting = true


func _update_effects(_delta: float, ratio: float, throttle: bool) -> void:
	var q := clampi(int(G.settings.quality), 0, 2)
	var black: bool = (not demo and G.is_exhausted) or (_spec().diesel and throttle)
	_smoke.emitting = q > 0 or ratio > 0.2
	_smoke.initial_velocity_min = 0.6 + 2.0 * ratio
	_smoke.initial_velocity_max = 1.4 + 3.0 * ratio
	_smoke.color_ramp.set_color(0, Color(0.08, 0.08, 0.09, 0.6) if black else Color(0.8, 0.8, 0.85, 0.3))
	if throttle and ratio > 0.75 and randf() < (0.6 + (2.5 if G.turbo_time > 0.0 else 0.0)) * get_process_delta_time():
		_pop_flame()
	var flame_col := Color(1.0, 0.6, 0.15)
	if not demo and G.turbo_time > 0.0:
		flame_col = Color(0.35, 0.65, 1.0)
	if not demo and G.ultra > 0:
		flame_col = _ultra_color()
	_flames.color_ramp.set_color(0, flame_col)
	_steam.emitting = heat > 0.75 and q > 0
	_turbo_light.light_energy = 2.5 if (not demo and G.turbo_time > 0.0) else 0.0


func _update_tints() -> void:
	if _mats.is_empty():
		return
	var h := clampf((heat - 0.45) / 0.55, 0.0, 1.0)
	var mc: Color = D.MATERIALS[material_index % D.MATERIALS.size()].color
	var hot := Color(0.85, 0.18, 0.08)
	var base := {"block": _part_color("block", mc.lightened(0.05)), "head": _part_color("head", mc.lightened(0.15)),
		"piston": _part_color("pistons", Color("cfd4da")), "crank": _part_color("crank", Color("7f868e")),
		"exhaust": _part_color("exhaust", Color("6b5e55"))}
	for key in base:
		var m: StandardMaterial3D = _mats[key]
		var col: Color = base[key].lerp(hot, h * (0.55 if key != "crank" else 0.2))
		m.albedo_color = Color(col.r, col.g, col.b, m.albedo_color.a)
		m.emission_enabled = h > 0.05 or _part_glow(key) > 0.0
		var glow := _part_glow(key)
		m.emission = hot * h * 0.6 + _glow_color(key) * glow
		m.emission_energy_multiplier = 1.0
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
	return fallback.lerp(D.mark_color(int(it.mk)), 0.5)


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
# 2D-поверх: кружок турбо и белая вспышка
# ---------------------------------------------------------------------

func _draw_hud() -> void:
	if show_hud and not demo and G.d_turbo_on:
		var c := Vector2(size.x * 0.5, 34.0)
		var rad := 22.0
		_hud.draw_arc(c, rad, 0, TAU, 40, Color(1, 1, 1, 0.15), 6.0)
		if G.turbo_time > 0.0:
			var f := G.turbo_time / G.TURBO_TIME
			_hud.draw_arc(c, rad, -PI * 0.5, -PI * 0.5 + TAU * f, 40, Color(0.35, 0.65, 1.0), 6.0)
		elif G.turbo_cd > 0.0:
			var f2 := 1.0 - G.turbo_cd / G.d_turbo_cd
			_hud.draw_arc(c, rad, -PI * 0.5, -PI * 0.5 + TAU * f2, 40, Color(1.0, 0.55, 0.15), 6.0)
		else:
			_hud.draw_arc(c, rad, 0, TAU, 40, Color(0.5, 1.0, 0.5, 0.8), 6.0)
	if flash_white > 0.0:
		_hud.draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, flash_white))
