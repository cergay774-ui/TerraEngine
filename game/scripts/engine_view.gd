extends Control
## Мотор целиком рисуется кодом: коленвал, шатуны и поршни считаются по геометрии
## кривошипа, у каждого цилиндра своя фаза по порядку зажигания. Поэтому любой собранный
## мотор анимируется сам.

signal hold_changed(pressed: bool)

const ROD := 3.0          # длина шатуна в радиусах кривошипа
const BORE := 1.15        # половина диаметра цилиндра
const WALL := 0.32
const DECK := 4.7
const HEAD := 1.1
const SPACING := 2.9

var engine_type: String = "inline4"
var material_index: int = 0
var demo: bool = false            # загрузочный экран/витрина: обороты задаются снаружи
var demo_rpm: float = 900.0
var interactive: bool = true
var crank_deg: float = 0.0
var rpm: float = 800.0
var heat: float = 0.0
var shake_offset: Vector2 = Vector2.ZERO
var flash_white: float = 0.0
var show_hud: bool = true
var drives_audio: bool = true

var _cyl: Array = []
var _r: float = 20.0
var _origin: Vector2 = Vector2.ZERO
var _exhaust_local: Vector2 = Vector2.ZERO
var _exhaust_dir: Vector2 = Vector2.RIGHT
var _turbine_local: Vector2 = Vector2.ZERO
var _head_top_local: Vector2 = Vector2.ZERO
var _particles: Array = []
var _time: float = 0.0
var _prev_throttle: bool = false
var _turbine_deg: float = 0.0
var _laid_for: String = ""
var _laid_size: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	resized.connect(_relayout)


func set_engine(type: String, material: int) -> void:
	engine_type = type
	material_index = material
	_relayout()


func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		hold_changed.emit(event.pressed)
		accept_event()


# ---------------------------------------------------------------------
# Раскладка цилиндров
# ---------------------------------------------------------------------

func _spec() -> Dictionary:
	return D.ENGINES.get(engine_type, D.ENGINES.inline4)


func _build_cylinders() -> Array:
	var c: Array = []
	match engine_type:
		"single":
			c.append({"base": Vector2.ZERO, "axis": -90.0, "tdc": 0.0, "row": 0})
		"inline4", "diesel":
			var tdc := [0.0, 540.0, 180.0, 360.0]  # порядок 1-3-4-2
			for i in 4:
				c.append({"base": Vector2((i - 1.5) * SPACING, 0), "axis": -90.0, "tdc": tdc[i], "row": 0})
		"boxer":
			for row in 2:
				c.append({"base": Vector2.ZERO, "axis": 180.0, "tdc": row * 180.0, "row": row})
				c.append({"base": Vector2.ZERO, "axis": 0.0, "tdc": row * 180.0 + 360.0, "row": row})
		"v6":
			for row in 3:
				c.append({"base": Vector2.ZERO, "axis": -120.0, "tdc": row * 240.0, "row": row})
				c.append({"base": Vector2.ZERO, "axis": -60.0, "tdc": row * 240.0 + 120.0, "row": row})
		"v8":
			for row in 4:
				c.append({"base": Vector2.ZERO, "axis": -135.0, "tdc": row * 180.0, "row": row})
				c.append({"base": Vector2.ZERO, "axis": -45.0, "tdc": row * 180.0 + 90.0, "row": row})
		"v12":
			for row in 6:
				c.append({"base": Vector2.ZERO, "axis": -120.0, "tdc": row * 120.0, "row": row})
				c.append({"base": Vector2.ZERO, "axis": -60.0, "tdc": row * 120.0 + 60.0, "row": row})
		"experimental":
			for row in 4:
				for b in 3:
					c.append({"base": Vector2.ZERO, "axis": [-145.0, -90.0, -35.0][b],
						"tdc": fmod((row * 3 + b) * 60.0 * 1.0, 720.0), "row": row})
		"radial":
			var order := [0, 2, 4, 6, 1, 3, 5]
			for k in 7:
				var pos_in_order := order.find(k)
				c.append({"base": Vector2.ZERO, "axis": -90.0 + k * 360.0 / 7.0,
					"tdc": pos_in_order * 720.0 / 7.0, "row": 0})
	return c


func _row_offset(row: int) -> Vector2:
	return Vector2(0.55, -0.42) * row


func _relayout() -> void:
	_laid_for = engine_type
	_laid_size = size
	_cyl = _build_cylinders()
	var spec := _spec()
	var view: String = spec.view
	# рамка в единицах радиуса кривошипа
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	if view == "rotary":
		mn = Vector2(-6.6, -6.4)
		mx = Vector2(8.4, 6.0)
	else:
		for cy in _cyl:
			var rot := deg_to_rad(cy.axis + 90.0)
			var off: Vector2 = cy.base + _row_offset(cy.row)
			for p in [Vector2(-BORE - WALL - 0.3, 1.8), Vector2(BORE + WALL + 0.3, 1.8),
					Vector2(-BORE - WALL - 0.3, -DECK - HEAD - 0.6), Vector2(BORE + WALL + 0.3, -DECK - HEAD - 0.6)]:
				var q: Vector2 = off + p.rotated(rot)
				mn = mn.min(q)
				mx = mx.max(q)
		mn -= Vector2(0.4, 0.4)
		mx += Vector2(2.2, 0.4)  # место под выхлоп
	var box := mx - mn
	var avail := size * Vector2(0.94, 0.82)
	_r = maxf(4.0, minf(avail.x / box.x, avail.y / box.y))
	if view == "radial":
		_r *= 1.0
	var center_units := (mn + mx) * 0.5
	_origin = size * Vector2(0.5, 0.54) - center_units * _r
	# выхлоп и турбина
	if view == "side":
		var right := 0.0
		for cy in _cyl:
			right = maxf(right, cy.base.x)
		_exhaust_local = Vector2(right + BORE + WALL + 1.8, 0.6)
		_head_top_local = Vector2(0, -DECK - HEAD)
	elif view == "rotary":
		_exhaust_local = Vector2(7.2, 3.6)
		_head_top_local = Vector2(0, -4.2)
	else:
		_exhaust_local = Vector2(mx.x - 0.6, 1.0)
		_head_top_local = Vector2(0, mn.y + 0.5)
	_turbine_local = _exhaust_local + Vector2(-0.9, -1.6)
	_exhaust_dir = Vector2(0.6, 1.0).normalized()


# ---------------------------------------------------------------------
# Обновление
# ---------------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	if _laid_for != engine_type or _laid_size != size:
		_relayout()
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
	_turbine_deg = fmod(_turbine_deg + delta * (200.0 + rpm * rpm / 25000.0) * (2.0 if (not demo and G.turbo_time > 0.0) else 1.0), 360.0)

	# тряска
	var ratio := clampf(rpm / max_rpm, 0.0, 1.2)
	var amp := 0.0
	if demo or G.settings.shake:
		amp = (1.2 + 9.0 * ratio * ratio) * float(spec.balance)
		if not demo:
			amp *= G.d_shake_mult
			if G.is_exhausted:
				amp *= 1.6
		amp *= _r / 26.0
	shake_offset = Vector2(sin(_time * 53.0) + 0.5 * sin(_time * 97.0), cos(_time * 61.0) + 0.5 * sin(_time * 83.0)) * amp * 0.6

	_update_particles(delta, ratio, throttle)
	flash_white = maxf(0.0, flash_white - delta * 2.5)

	# звук
	if drives_audio:
		Sfx.rpm = rpm
		Sfx.max_rpm = max_rpm
		Sfx.cylinders = spec.cyl
		Sfx.pitch = spec.pitch
		Sfx.diesel = spec.diesel
		Sfx.engine_type = engine_type
		Sfx.turbo_level = 0.0 if demo else (1.0 if G.turbo_time > 0.0 else (0.35 * ratio if not G.equipped("turbine").is_empty() else 0.0))
	queue_redraw()


func _quality_cap() -> int:
	return [12, 45, 110][clampi(int(G.settings.quality), 0, 2)]


func _emit(p: Dictionary) -> void:
	if _particles.size() < _quality_cap():
		_particles.append(p)


func _pop_flame() -> void:
	Sfx.pop()
	for i in 4:
		_emit({"pos": _exhaust_local, "vel": _exhaust_dir.rotated(randf_range(-0.4, 0.4)) * randf_range(3.0, 6.0),
			"life": 0.25, "max": 0.25, "size": randf_range(0.4, 0.8), "kind": "flame"})


func _update_particles(delta: float, ratio: float, throttle: bool) -> void:
	var diesel: bool = _spec().diesel
	var black := (not demo and G.is_exhausted) or diesel and throttle
	var rate := 2.0 + 14.0 * ratio
	if randf() < rate * delta:
		_emit({"pos": _exhaust_local, "vel": _exhaust_dir * randf_range(1.0, 2.5) + Vector2(0, -0.8),
			"life": 1.4, "max": 1.4, "size": randf_range(0.14, 0.26), "kind": "black" if black else "smoke"})
	# хлопки и вспышки на высоких оборотах
	var pop_chance := 0.0
	if throttle and ratio > 0.75:
		pop_chance = 0.6 + (2.5 if G.turbo_time > 0.0 else 0.0)
	if randf() < pop_chance * delta:
		_pop_flame()
	# пар при перегреве
	if heat > 0.75 and randf() < 10.0 * delta:
		_emit({"pos": _head_top_local + Vector2(randf_range(-3.0, 3.0), 0.0), "vel": Vector2(randf_range(-0.3, 0.3), -1.8),
			"life": 1.2, "max": 1.2, "size": randf_range(0.3, 0.6), "kind": "steam"})
	for i in range(_particles.size() - 1, -1, -1):
		var p: Dictionary = _particles[i]
		p.life -= delta
		if p.life <= 0.0:
			_particles.remove_at(i)
			continue
		p.pos += p.vel * delta
		p.vel *= 0.98
		if p.kind != "flame":
			p.vel.y -= 0.9 * delta
			p.size += delta * 0.45


# ---------------------------------------------------------------------
# Рисование
# ---------------------------------------------------------------------

func _mat_color() -> Color:
	return D.MATERIALS[material_index % D.MATERIALS.size()].color


func _heat_tint(c: Color, amount: float = 1.0) -> Color:
	var h := clampf((heat - 0.45) / 0.55, 0.0, 1.0) * amount
	return c.lerp(Color(0.85, 0.18, 0.08), h * 0.55)


func _part_color(slot_id: String, fallback: Color) -> Color:
	if demo:
		return fallback
	var it: Dictionary = G.equipped(slot_id)
	if it.is_empty():
		return fallback
	return fallback.lerp(D.mark_color(int(it.mk)), 0.55)


func _part_glow(slot_id: String) -> Color:
	if demo:
		return Color(0, 0, 0, 0)
	var it: Dictionary = G.equipped(slot_id)
	if it.is_empty():
		return Color(0, 0, 0, 0)
	var g := D.mark_glow(int(it.mk))
	var rc: Color = D.RARITIES[int(it.rar)].color
	return Color(rc.r, rc.g, rc.b, g * 0.6)


func _xray() -> bool:
	return (not demo) and (G.settings.xray or G.ultra > 0)


func _ultra_color() -> Color:
	var hue := fmod(0.75 + 0.13 * maxi(G.ultra, 1), 1.0)
	return Color.from_hsv(hue, 0.7, 1.0)


func _draw() -> void:
	if _cyl.is_empty() and _spec().view != "rotary":
		_relayout()
	var base := Transform2D(0.0, _origin + shake_offset)
	var spec := _spec()
	var view: String = spec.view
	# свечение турбо
	if not demo and G.turbo_time > 0.0:
		var center := _origin + shake_offset + Vector2(0, -2.0 * _r)
		for i in 6:
			draw_circle(center, _r * (7.5 - i), Color(0.25, 0.55, 1.0, 0.035 + i * 0.008))
	if spec.get("glow", false) or (not demo and G.ultra > 0):
		var gc := _ultra_color() if (not demo and G.ultra > 0) else Color(0.4, 1.0, 0.9)
		var center2 := _origin + shake_offset + Vector2(0, -2.0 * _r)
		for i in 5:
			draw_circle(center2, _r * (6.5 - i), Color(gc.r, gc.g, gc.b, 0.025 * (0.6 + 0.4 * sin(_time * 3.0))))

	_draw_particles(base, true)
	if view == "rotary":
		_draw_rotary(base)
	elif view == "side":
		_draw_side(base)
	else:
		_draw_front(base)
	_draw_exhaust(base)
	_draw_particles(base, false)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	if show_hud and not demo:
		_draw_turbo_ring()
	if flash_white > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, flash_white))


func _cyl_xform(base: Transform2D, cy: Dictionary) -> Transform2D:
	var pos: Vector2 = (cy.base + _row_offset(cy.row)) * _r
	return base * Transform2D(deg_to_rad(cy.axis + 90.0), pos)


func _cycle(cy: Dictionary) -> float:
	return fposmod(crank_deg - cy.tdc, 720.0)


func _draw_side(base: Transform2D) -> void:
	var r := _r
	var xr := _xray()
	var mc := _mat_color()
	# коленвал и шатуны позади картера
	for cy in _cyl:
		_draw_crank_and_rod(_cyl_xform(base, cy), cy, true)
	# картер
	draw_set_transform_matrix(base)
	var left := INF
	var right := -INF
	for cy in _cyl:
		left = minf(left, cy.base.x)
		right = maxf(right, cy.base.x)
	var case_rect := Rect2(Vector2((left - BORE - WALL) * r, -1.25 * r), Vector2((right - left + 2.0 * (BORE + WALL)) * r, 3.0 * r))
	var case_col := _heat_tint(_part_color("block", mc.darkened(0.15)), 0.5)
	case_col.a = 0.3 if xr else 0.72
	draw_rect(case_rect, case_col)
	draw_rect(case_rect, Color(0, 0, 0, 0.5), false, 2.0)
	# масляный поддон
	var pan := Rect2(case_rect.position + Vector2(r * 0.4, case_rect.size.y), Vector2(case_rect.size.x - r * 0.8, r * 0.5))
	draw_rect(pan, Color(mc.darkened(0.35), 0.9 if not xr else 0.3))
	# цилиндры
	for cy in _cyl:
		_draw_cylinder(_cyl_xform(base, cy), cy, false)
	# общая ГБЦ
	draw_set_transform_matrix(base)
	var head_rect := Rect2(Vector2((left - BORE - WALL - 0.1) * r, -(DECK + HEAD) * r),
		Vector2((right - left + 2.0 * (BORE + WALL + 0.1)) * r, HEAD * r))
	_draw_head_block(head_rect, xr, mc)
	for cy in _cyl:
		_draw_head_parts(_cyl_xform(base, cy), cy, xr)


func _draw_front(base: Transform2D) -> void:
	var rows := 0
	for cy in _cyl:
		rows = maxi(rows, int(cy.row) + 1)
	var xr := _xray()
	var mc := _mat_color()
	for row in range(rows - 1, -1, -1):
		var shade := 1.0 - 0.13 * row
		var row_base := base
		var group: Array = []
		for cy in _cyl:
			if int(cy.row) == row:
				group.append(cy)
		for cy in group:
			_draw_crank_and_rod(_cyl_xform(row_base, cy), cy, true, shade)
		# картер ряда
		draw_set_transform_matrix(row_base)
		var cpos := _row_offset(row) * _r
		var cc := _heat_tint(_part_color("block", mc.darkened(0.15)), 0.5) * Color(shade, shade, shade)
		cc.a = 0.28 if xr else 0.7
		draw_circle(cpos, _r * 1.75, cc)
		draw_arc(cpos, _r * 1.75, 0, TAU, 40, Color(0, 0, 0, 0.45), 2.0)
		for cy in group:
			_draw_cylinder(_cyl_xform(row_base, cy), cy, true, shade)
			var hx := _cyl_xform(row_base, cy)
			draw_set_transform_matrix(hx)
			var hr := Rect2(Vector2(-(BORE + WALL + 0.1) * _r, -(DECK + HEAD) * _r), Vector2(2.0 * (BORE + WALL + 0.1) * _r, HEAD * _r))
			_draw_head_block(hr, xr, mc, shade)
			_draw_head_parts(hx, cy, xr, shade)


func _draw_crank_and_rod(x: Transform2D, cy: Dictionary, with_rod: bool, shade: float = 1.0) -> void:
	draw_set_transform_matrix(x)
	var r := _r
	var psi := deg_to_rad(crank_deg - cy.tdc)
	var pin := Vector2(sin(psi), -cos(psi)) * r
	var crank_col := _part_color("crank", Color("8d939b")) * Color(shade, shade, shade)
	# противовес
	var cw := -pin.normalized() * r * 0.55
	draw_circle(cw, r * 0.75, crank_col.darkened(0.25))
	draw_line(Vector2.ZERO, pin, crank_col, r * 0.55)
	draw_circle(Vector2.ZERO, r * 0.42, crank_col.lightened(0.1))
	draw_circle(pin, r * 0.3, crank_col.lightened(0.2))
	if with_rod:
		var d := r * cos(psi) + sqrt(maxf(0.0, (ROD * r) * (ROD * r) - pow(r * sin(psi), 2.0)))
		var ppin := Vector2(0, -d)
		var rod_col := Color("a7adb5") * Color(shade, shade, shade)
		draw_line(pin, ppin, rod_col, r * 0.42)
		draw_circle(pin, r * 0.24, rod_col.darkened(0.2))
		draw_circle(ppin, r * 0.16, rod_col.darkened(0.3))


func _draw_cylinder(x: Transform2D, cy: Dictionary, front: bool, shade: float = 1.0) -> void:
	draw_set_transform_matrix(x)
	var r := _r
	var xr := _xray()
	var mc := _mat_color()
	var psi := deg_to_rad(crank_deg - cy.tdc)
	var d := r * cos(psi) + sqrt(maxf(0.0, (ROD * r) * (ROD * r) - pow(r * sin(psi), 2.0)))
	var top := d + 0.5 * r
	var skirt := d - 0.8 * r
	var bw := BORE * r
	var deck := DECK * r
	var sh := Color(shade, shade, shade)
	# гильза (тёмная внутренность)
	draw_rect(Rect2(-bw, -deck, 2.0 * bw, deck - 1.3 * r), Color("15161a") * sh)
	# вспышка в камере сгорания
	var c := _cycle(cy)
	var flash := 0.0
	if c < 60.0:
		flash = 1.0 - c / 60.0
	if flash > 0.0:
		var fc := Color(1.0, 0.55, 0.12, 0.85 * flash)
		if _spec().diesel:
			fc = Color(1.0, 0.75, 0.35, 0.7 * flash)
		if not demo and G.ultra > 0:
			var uc := _ultra_color()
			fc = Color(uc.r, uc.g, uc.b, 0.9 * flash)
		draw_rect(Rect2(-bw, -deck, 2.0 * bw, deck - top), fc)
	# поршень
	var pc := _heat_tint(_part_color("pistons", Color("c9ced6")), 0.8) * sh
	var pr := Rect2(-bw + 0.05 * r, -top, 2.0 * bw - 0.1 * r, top - skirt)
	draw_rect(pr, pc)
	for k in 3:
		var y := -top + (0.14 + 0.13 * k) * r
		draw_line(Vector2(-bw + 0.05 * r, y), Vector2(bw - 0.05 * r, y), pc.darkened(0.35), maxf(1.0, r * 0.05))
	var glow := _part_glow("pistons")
	if glow.a > 0.0:
		draw_rect(pr.grow(r * 0.06), glow, false, maxf(1.0, r * 0.08))
	# стенки блока
	var wc := _heat_tint(_part_color("block", mc), 1.0) * sh
	wc.a = 0.38 if xr else 1.0
	draw_rect(Rect2(-bw - WALL * r, -deck, WALL * r, deck - 1.2 * r), wc)
	draw_rect(Rect2(bw, -deck, WALL * r, deck - 1.2 * r), wc)
	if D.MATERIALS[material_index % D.MATERIALS.size()].get("weave", false):
		for k in int(deck / (r * 0.4)):
			var yy := -deck + k * r * 0.4
			draw_line(Vector2(-bw - WALL * r, yy), Vector2(-bw, yy + r * 0.2), Color(1, 1, 1, 0.08), 1.0)
			draw_line(Vector2(bw, yy + r * 0.2), Vector2(bw + WALL * r, yy), Color(1, 1, 1, 0.08), 1.0)
	# клапаны (тарелки видны в камере)
	var lift_ex := _valve_lift(c, 160.0, 380.0)
	var lift_in := _valve_lift(c, 340.0, 560.0)
	var vc := Color("b0b6be") * sh
	for side in [-1, 1]:
		var lift := lift_in if side < 0 else lift_ex
		var vx: float = side * bw * 0.5
		var vy := -deck + lift * 0.35 * r
		draw_line(Vector2(vx, -deck - HEAD * r * 0.7), Vector2(vx, vy), vc, maxf(1.0, r * 0.1))
		draw_rect(Rect2(vx - bw * 0.32, vy - r * 0.06, bw * 0.64, r * 0.12), vc)


func _valve_lift(c: float, a: float, b: float) -> float:
	var cc := c
	if cc < a and cc + 720.0 <= b:
		cc += 720.0
	if cc < a or cc > b:
		return 0.0
	return sin(PI * (cc - a) / (b - a))


func _draw_head_block(rect: Rect2, xr: bool, mc: Color, shade: float = 1.0) -> void:
	var hc := _heat_tint(_part_color("head", mc.lightened(0.12)), 1.0) * Color(shade, shade, shade)
	hc.a = 0.35 if xr else 1.0
	draw_rect(rect, hc)
	draw_rect(rect, Color(0, 0, 0, 0.45), false, 2.0)
	# клапанная крышка
	var cover := Rect2(rect.position + Vector2(rect.size.x * 0.06, -rect.size.y * 0.35), Vector2(rect.size.x * 0.88, rect.size.y * 0.38))
	var cc := hc.darkened(0.2)
	if not demo and D.epoch_info(G.level).racing:
		cc = Color(0.8, 0.1, 0.1, hc.a)
	draw_rect(cover, cc)
	if not demo and D.epoch_info(G.level).racing:
		draw_rect(Rect2(cover.position + Vector2(0, cover.size.y * 0.4), Vector2(cover.size.x, cover.size.y * 0.2)), Color(1, 1, 1, 0.8 * hc.a))
	var glow := _part_glow("head")
	if glow.a > 0.0:
		draw_rect(rect.grow(2.0), glow, false, 3.0)


func _draw_head_parts(x: Transform2D, cy: Dictionary, xr: bool, shade: float = 1.0) -> void:
	draw_set_transform_matrix(x)
	var r := _r
	var deck := DECK * r
	var c := _cycle(cy)
	# распредвал (виден в рентгене)
	if xr:
		var cam_a := deg_to_rad(crank_deg * 0.5 - cy.tdc * 0.5)
		for side in [-1, 1]:
			var cp := Vector2(side * BORE * r * 0.5, -deck - HEAD * r * 0.75)
			draw_circle(cp, r * 0.18, Color("d0d4da") * Color(shade, shade, shade))
			var lobe := Vector2(0, -r * 0.28).rotated(cam_a + (0.0 if side < 0 else PI * 0.5))
			draw_line(cp, cp + lobe, Color("e0e4ea"), r * 0.16)
	# свеча / форсунка
	var plug_col := Color("e8e1d0") if not _spec().diesel else Color("6c7480")
	draw_rect(Rect2(-r * 0.09, -deck - HEAD * r * 1.15, r * 0.18, HEAD * r * 0.6), plug_col * Color(shade, shade, shade))
	if c < 25.0 and not _spec().diesel:
		var sc := Color(1.0, 0.95, 0.6)
		if not demo and G.ultra > 0:
			sc = _ultra_color().lightened(0.4)
		for k in 4:
			var a := k * PI * 0.5 + _time * 7.0
			draw_line(Vector2(0, -deck + r * 0.05), Vector2(0, -deck + r * 0.05) + Vector2(cos(a), sin(a)) * r * 0.35, sc, maxf(1.0, r * 0.07))


func _draw_rotary(base: Transform2D) -> void:
	var r := _r
	var xr := _xray()
	var mc := _mat_color()
	var e := 0.7
	var R := 3.6
	var shaft := deg_to_rad(crank_deg)
	for row: int in [1, 0]:
		var shade := 1.0 - 0.15 * row
		var off := _row_offset(row) * r * 2.0
		draw_set_transform_matrix(base * Transform2D(0.0, off))
		var phase := shaft + (PI if row == 1 else 0.0)
		# корпус (эпитрохоида)
		var pts := PackedVector2Array()
		for i in 72:
			var a := TAU * i / 72.0
			pts.append(Vector2(e * cos(3.0 * a) + R * cos(a) * 1.04, e * sin(3.0 * a) + R * sin(a) * 1.04) * r)
		var outer := PackedVector2Array()
		for p in pts:
			outer.append(p * 1.22)
		var hc := _heat_tint(_part_color("block", mc), 1.0) * Color(shade, shade, shade)
		hc.a = 0.4 if xr else 1.0
		draw_colored_polygon(outer, hc)
		draw_colored_polygon(pts, Color("15161a") * Color(shade, shade, shade))
		# вспышка у свечей
		var cyc := fposmod(rad_to_deg(phase), 360.0)
		if cyc < 50.0:
			var fl := 1.0 - cyc / 50.0
			var fc := Color(1.0, 0.55, 0.12, 0.8 * fl)
			if not demo and G.ultra > 0:
				fc = _ultra_color()
				fc.a = 0.8 * fl
			draw_circle(Vector2(-R * 0.75 * r, 0), r * 1.3 * fl + r * 0.3, fc)
		# ротор
		var rc := Vector2(cos(phase), sin(phase)) * e * r
		var rot := phase / 3.0
		var tri := PackedVector2Array()
		for k in 3:
			var a0 := rot + TAU * k / 3.0
			var a1 := rot + TAU * (k + 1) / 3.0
			var v0 := rc + Vector2(cos(a0), sin(a0)) * R * r
			var v1 := rc + Vector2(cos(a1), sin(a1)) * R * r
			for s in 8:
				var t := s / 8.0
				var mid := v0.lerp(v1, t)
				var bulge := (rc - mid).normalized() * -sin(PI * t) * r * 0.35
				tri.append(mid + bulge)
		var pc := _heat_tint(_part_color("pistons", Color("c9ced6")), 0.8) * Color(shade, shade, shade)
		draw_colored_polygon(tri, pc)
		draw_polyline(tri + PackedVector2Array([tri[0]]), pc.darkened(0.4), 2.0)
		# зубчатый венец и вал
		draw_arc(rc, r * 1.1, 0, TAU, 24, pc.darkened(0.3), r * 0.15)
		draw_circle(Vector2.ZERO, r * 0.55, _part_color("crank", Color("8d939b")))
		draw_circle(rc * 0.9, r * 0.2, Color("d0d4da"))
		# свечи
		for k in 2:
			draw_rect(Rect2(Vector2(-R * 1.28 * r, (-0.6 + 1.2 * k) * r - r * 0.12), Vector2(r * 0.5, r * 0.24)), Color("e8e1d0"))


func _draw_exhaust(base: Transform2D) -> void:
	draw_set_transform_matrix(base)
	var r := _r
	var view: String = _spec().view
	var start: Vector2
	if view == "side":
		var right := -INF
		for cy in _cyl:
			right = maxf(right, cy.base.x)
		start = Vector2(right + BORE + WALL, -DECK + 0.4) * r
	elif view == "rotary":
		start = Vector2(4.2, 1.2) * r
	else:
		start = Vector2(_exhaust_local.x - 2.4, -2.2) * r
	var end := _exhaust_local * r
	var col := _heat_tint(_part_color("exhaust", Color("5f5853")), 1.0)
	var mid := Vector2(end.x - r * 0.9, start.y)
	var low := Vector2(end.x - r * 0.9, end.y - r * 1.3)
	draw_polyline(PackedVector2Array([start, mid, low]), col.darkened(0.2), r * 0.34)
	# глушитель
	var muff := Rect2(low + Vector2(-r * 0.45, 0), Vector2(r * 0.9, r * 1.1))
	draw_rect(muff, col)
	draw_rect(muff, col.darkened(0.45), false, 2.0)
	draw_line(muff.position + Vector2(r * 0.45, muff.size.y), end - _exhaust_dir * r * 0.2, col.darkened(0.1), r * 0.24)
	draw_circle(end - _exhaust_dir * r * 0.2, r * 0.16, Color("15161a"))
	var eg := _part_glow("exhaust")
	if eg.a > 0.0:
		draw_rect(muff.grow(2.0), eg, false, 3.0)
	# турбина
	if demo or G.equipped("turbine").is_empty():
		return
	var tp := _turbine_local * r
	var housing := _part_color("turbine", Color("9aa3ad"))
	draw_circle(tp, r * 0.95, housing.darkened(0.2))
	draw_arc(tp, r * 0.95, 0, TAU, 32, housing.lightened(0.2), 2.0)
	draw_circle(tp, r * 0.7, Color("1b1c20"))
	var a0 := deg_to_rad(_turbine_deg)
	for k in 7:
		var a := a0 + TAU * k / 7.0
		draw_line(tp, tp + Vector2(cos(a), sin(a)) * r * 0.65, Color("d8dde3"), maxf(1.0, r * 0.1))
	draw_circle(tp, r * 0.15, housing)
	if G.turbo_time > 0.0:
		draw_arc(tp, r * 1.1, 0, TAU, 32, Color(0.3, 0.6, 1.0, 0.8), 3.0)


func _draw_particles(base: Transform2D, behind: bool) -> void:
	draw_set_transform_matrix(base)
	for p in _particles:
		var t: float = p.life / p.max
		match p.kind:
			"smoke":
				if behind:
					continue
				draw_circle(p.pos * _r, p.size * _r, Color(0.75, 0.75, 0.78, 0.16 * t))
			"black":
				if behind:
					continue
				draw_circle(p.pos * _r, p.size * _r * 1.3, Color(0.06, 0.06, 0.07, 0.5 * t))
			"steam":
				if not behind:
					continue
				draw_circle(p.pos * _r, p.size * _r, Color(0.95, 0.95, 1.0, 0.25 * t))
			"flame":
				if behind:
					continue
				var fc := Color(1.0, 0.6, 0.15, t)
				if not demo and G.turbo_time > 0.0:
					fc = Color(0.35, 0.65, 1.0, t)
				if not demo and G.ultra > 0:
					fc = _ultra_color()
					fc.a = t
				draw_circle(p.pos * _r, p.size * _r * (0.5 + t), fc)


func _draw_turbo_ring() -> void:
	if not G.d_turbo_on:
		return
	var c := Vector2(size.x * 0.5, 34.0)
	var rad := 22.0
	draw_arc(c, rad, 0, TAU, 40, Color(1, 1, 1, 0.15), 6.0)
	if G.turbo_time > 0.0:
		var f := G.turbo_time / G.TURBO_TIME
		draw_arc(c, rad, -PI * 0.5, -PI * 0.5 + TAU * f, 40, Color(0.35, 0.65, 1.0), 6.0)
	elif G.turbo_cd > 0.0:
		var f2 := 1.0 - G.turbo_cd / G.d_turbo_cd
		draw_arc(c, rad, -PI * 0.5, -PI * 0.5 + TAU * f2, 40, Color(1.0, 0.55, 0.15), 6.0)
	else:
		draw_arc(c, rad, 0, TAU, 40, Color(0.5, 1.0, 0.5, 0.8), 6.0)
