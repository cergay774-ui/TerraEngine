class_name GarageScene
extends RefCounted
## Тёмный гараж в 3D (как на логотипе): бетонный пол, рифлёные стены, ворота с окном,
## стена с ключами, тумба с ящиками, шины, лампы-трубки. Плюс окружение для отражений.

static func environment(quality: int, glow: bool) -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.016, 0.02)
	var sky := Sky.new()
	var pano := PanoramaSkyMaterial.new()
	pano.panorama = _studio_panorama()
	pano.energy_multiplier = 1.3
	sky.sky_material = pano
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
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
	env.fog_enabled = quality >= 1
	env.fog_light_color = Color(0.09, 0.09, 0.11)
	env.fog_density = 0.0028
	return env


## Панорама «студийного» неба: тёмная, с яркими полосами ламп — даёт красивые блики на металле.
static func _studio_panorama() -> Texture2D:
	var w := 256
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBAF)
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


static func _noise_tex(freq: float, normal: bool, seed: int = 1) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = freq
	n.fractal_octaves = 5
	var t := NoiseTexture2D.new()
	t.noise = n
	t.width = 512
	t.height = 512
	t.seamless = true
	t.as_normal_map = normal
	t.bump_strength = 4.0
	return t


static func material(color: Color, metallic: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = rough
	return m


static func build(parent: Node3D, floor_y: float, quality: int) -> Dictionary:
	var root := Node3D.new()
	root.name = "Garage"
	parent.add_child(root)
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
	}
	var tube := StandardMaterial3D.new()
	tube.albedo_color = Color.WHITE
	tube.emission_enabled = true
	tube.emission = Color(1.0, 0.97, 0.9)
	tube.emission_energy_multiplier = 6.0
	mats["tube"] = tube
	var window := StandardMaterial3D.new()
	window.albedo_color = Color(0.8, 0.85, 0.9)
	window.emission_enabled = true
	window.emission = Color(0.75, 0.8, 0.9)
	window.emission_energy_multiplier = 2.5
	mats["window"] = window

	# пол: бетон с шумом, нормалями и бликами
	var floor_m := StandardMaterial3D.new()
	floor_m.albedo_color = Color(0.16, 0.16, 0.17)
	floor_m.albedo_texture = _noise_tex(0.02, false, 3)
	floor_m.normal_enabled = quality >= 1
	if quality >= 1:
		floor_m.normal_texture = _noise_tex(0.04, true, 7)
		floor_m.normal_scale = 0.6
	floor_m.roughness = 0.62
	floor_m.metallic = 0.15
	floor_m.uv1_scale = Vector3(6, 6, 6)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(90, 90)
	var fl := MeshInstance3D.new()
	fl.mesh = floor_mesh
	fl.material_override = floor_m
	fl.position = Vector3(0, floor_y, 0)
	root.add_child(fl)
	# пятна масла
	var stain := StandardMaterial3D.new()
	stain.albedo_color = Color(0, 0, 0, 0.55)
	stain.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	stain.albedo_texture = _soft_dot()
	stain.metallic = 0.6
	stain.roughness = 0.1
	for p in [Vector3(-5, 0, 6), Vector3(7, 0, 2), Vector3(-2, 0, -4)]:
		var s := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(5.0 + p.x * 0.1, 3.5)
		s.mesh = pm
		s.material_override = stain
		s.position = Vector3(p.x, floor_y + 0.01, p.z)
		s.rotation.y = p.x * 0.3
		root.add_child(s)

	var back_z := -17.0
	var side_x := 20.0
	var height := 18.0
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

	batch.commit(root, mats)

	# лампы-трубки под потолком
	var lights: Array = []
	for lx in [-8.0, 6.0]:
		var t := MeshInstance3D.new()
		t.mesh = MeshKit.rounded_box(Vector3(7.0, 0.25, 0.4), 0.1, 2)
		t.material_override = tube
		t.position = Vector3(lx, floor_y + 15.5, back_z + 9.0)
		root.add_child(t)
	# мягкий луч света под лампой (аддитивный конус)
	if quality >= 1:
		var beam_m := StandardMaterial3D.new()
		beam_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		beam_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		beam_m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		beam_m.cull_mode = BaseMaterial3D.CULL_DISABLED
		beam_m.albedo_color = Color(1.0, 0.92, 0.75, 0.035)
		beam_m.disable_receive_shadows = true
		var beam := MeshInstance3D.new()
		beam.mesh = MeshKit.cone(14.0, 2.0, 15.0, 32)
		beam.material_override = beam_m
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beam.position = Vector3(0, floor_y + 7.6, 0)
		root.add_child(beam)

	# пыль в луче
	if quality >= 2:
		var dust := CPUParticles3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.06, 0.06)
		var dm := StandardMaterial3D.new()
		dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		dm.albedo_texture = _soft_dot()
		dm.albedo_color = Color(1, 0.9, 0.7, 0.6)
		q.material = dm
		dust.mesh = q
		dust.amount = 80
		dust.lifetime = 12.0
		dust.preprocess = 12.0
		dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		dust.emission_box_extents = Vector3(9, 6, 6)
		dust.direction = Vector3(0.2, 1, 0)
		dust.spread = 180.0
		dust.initial_velocity_min = 0.05
		dust.initial_velocity_max = 0.25
		dust.gravity = Vector3(0, -0.02, 0)
		dust.position = Vector3(0, floor_y + 7.0, 0)
		root.add_child(dust)

	# свет: ключевой прожектор сверху с тенью, заполняющий, контровой
	var key := SpotLight3D.new()
	key.light_color = Color(1.0, 0.93, 0.82)
	key.light_energy = 11.0
	key.spot_range = 60.0
	key.spot_angle = 42.0
	key.spot_angle_attenuation = 0.8
	key.shadow_enabled = quality >= 1
	key.shadow_blur = 1.5 if quality >= 2 else 0.8
	key.position = Vector3(2.0, floor_y + 16.0, 6.0)
	key.look_at_from_position(key.position, Vector3(0, floor_y + 3.0, 0), Vector3.UP)
	root.add_child(key)
	lights.append(key)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.75, 0.8, 1.0)
	fill.light_energy = 0.35
	fill.rotation_degrees = Vector3(-35, 40, 0)
	root.add_child(fill)
	var rim := OmniLight3D.new()
	rim.light_color = Color(0.35, 0.55, 1.0)
	rim.light_energy = 3.0
	rim.omni_range = 26.0
	rim.position = Vector3(-6.0, floor_y + 9.0, back_z + 3.0)
	root.add_child(rim)
	var warm := OmniLight3D.new()
	warm.light_color = Color(1.0, 0.6, 0.3)
	warm.light_energy = 1.2
	warm.omni_range = 20.0
	warm.position = Vector3(12.0, floor_y + 5.0, 6.0)
	root.add_child(warm)
	return {"root": root, "key": key}


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
