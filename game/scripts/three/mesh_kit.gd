class_name MeshKit
extends RefCounted
## Генераторы 3D-деталей: скруглённые коробки, трубы по кривой, шестерни, рёбра.
## Всё строится кодом, без внешних моделей.


static func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)


## Треугольник, гарантированно повёрнутый лицом в сторону out.
## В Godot 4 лицевая сторона — обход по часовой стрелке, т.е. (b - a) × (c - a) смотрит ОТ зрителя.
## Нормали: если na/nb/nc не заданы — плоская нормаль грани.
static func tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, out: Vector3,
		na: Vector3 = Vector3.ZERO, nb: Vector3 = Vector3.ZERO, nc: Vector3 = Vector3.ZERO) -> void:
	var cr := (b - a).cross(c - a)
	if cr.length_squared() < 1e-14:
		return
	if cr.dot(out) > 0.0:
		var t := b
		b = c
		c = t
		var tn := nb
		nb = nc
		nc = tn
	var fn := -cr.normalized() if cr.dot(out) <= 0.0 else cr.normalized()
	if fn.dot(out) < 0.0:
		fn = -fn
	st.set_normal(na if na != Vector3.ZERO else fn)
	st.add_vertex(a)
	st.set_normal(nb if nb != Vector3.ZERO else fn)
	st.add_vertex(b)
	st.set_normal(nc if nc != Vector3.ZERO else fn)
	st.add_vertex(c)


## Четырёхугольник a-b-c-d лицом в сторону out (нормали — плоские или по вершинам).
static func oquad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, out: Vector3,
		na: Vector3 = Vector3.ZERO, nb: Vector3 = Vector3.ZERO, nc: Vector3 = Vector3.ZERO, nd: Vector3 = Vector3.ZERO) -> void:
	tri(st, a, b, c, out, na, nb, nc)
	tri(st, a, c, d, out, na, nc, nd)


## Коробка со скруглёнными рёбрами (как литая деталь).
static func rounded_box(size: Vector3, radius: float, res: int = 6) -> ArrayMesh:
	var half := size * 0.5
	radius = minf(radius, minf(half.x, minf(half.y, half.z)) * 0.95)
	var inner := half - Vector3.ONE * radius
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# шесть граней куба, каждая — сетка res×res, точки «надуваются» вокруг внутренней коробки
	var faces := [
		[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)],
		[Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
		[Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)],
		[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
		[Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0)],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var hu: float = absf(u.dot(half))
		var hv: float = absf(v.dot(half))
		var hn: float = absf(n.dot(half))
		var su := _round_samples(hu, hu - radius, res)
		var sv := _round_samples(hv, hv - radius, res)
		var grid := []
		for i in su.size():
			var row := []
			for j in sv.size():
				var q: Vector3 = n * hn + u * su[i] + v * sv[j]
				var cl := q.clamp(-inner, inner)
				var dir := (q - cl)
				if dir.length() < 0.00001:
					dir = n
				dir = dir.normalized()
				row.append([cl + dir * radius, dir])
			grid.append(row)
		for i in su.size() - 1:
			for j in sv.size() - 1:
				var a: Array = grid[i][j]
				var b: Array = grid[i + 1][j]
				var c: Array = grid[i + 1][j + 1]
				var d: Array = grid[i][j + 1]
				oquad(st, a[0], b[0], c[0], d[0], n, a[1], b[1], c[1], d[1])
	st.index()
	return st.commit()


## Координаты вдоль оси грани: res шагов на каждом скруглении и один пролёт по плоской части.
static func _round_samples(h: float, w: float, res: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for k in res + 1:
		out.append(-h + (h - w) * k / float(res))
	for k in res + 1:
		out.append(w + (h - w) * k / float(res))
	return out


## Труба по ломаной с плавными рамками (выпускные коллекторы, патрубки).
static func sweep(points: PackedVector3Array, radius: float, sides: int = 12, caps: bool = true) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := points.size()
	if n < 2:
		return st.commit()
	var rings: Array = []
	var prev_normal := Vector3.ZERO
	for i in n:
		var t: Vector3
		if i == 0:
			t = (points[1] - points[0]).normalized()
		elif i == n - 1:
			t = (points[n - 1] - points[n - 2]).normalized()
		else:
			t = (points[i + 1] - points[i - 1]).normalized()
		var nrm: Vector3
		if i == 0:
			nrm = t.cross(Vector3.UP)
			if nrm.length() < 0.01:
				nrm = t.cross(Vector3.RIGHT)
			nrm = nrm.normalized()
		else:
			nrm = (prev_normal - t * prev_normal.dot(t))
			if nrm.length() < 0.0001:
				nrm = prev_normal
			nrm = nrm.normalized()
		prev_normal = nrm
		var bin := t.cross(nrm).normalized()
		var ring := []
		for k in sides:
			var a := TAU * k / sides
			var dir := nrm * cos(a) + bin * sin(a)
			ring.append([points[i] + dir * radius, dir])
		rings.append(ring)
	for i in n - 1:
		for k in sides:
			var k2 := (k + 1) % sides
			var a: Array = rings[i][k]
			var b: Array = rings[i + 1][k]
			var c: Array = rings[i + 1][k2]
			var d: Array = rings[i][k2]
			var out: Vector3 = a[1] + b[1] + c[1] + d[1]
			oquad(st, a[0], b[0], c[0], d[0], out, a[1], b[1], c[1], d[1])
	if caps:
		for end in [0, n - 1]:
			var ring: Array = rings[end]
			var center := points[end]
			var dirn := -(points[1] - points[0]).normalized() if end == 0 else (points[n - 1] - points[n - 2]).normalized()
			for k in sides:
				tri(st, center, ring[k][0], ring[(k + 1) % sides][0], dirn, dirn, dirn, dirn)
	st.index()
	return st.commit()


## Точки кривой Безье (для плавно изогнутых труб).
static func bezier(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, steps: int = 12) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for i in steps + 1:
		var t := float(i) / steps
		var u := 1.0 - t
		pts.append(p0 * u * u * u + p1 * 3.0 * u * u * t + p2 * 3.0 * u * t * t + p3 * t * t * t)
	return pts


## Шестерня/звёздочка с зубьями, ось вдоль X.
static func gear(radius: float, width: float, teeth: int, tooth_h: float = 0.12) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := PackedVector2Array()
	for i in teeth * 4:
		var a := TAU * i / (teeth * 4)
		var r := radius + (tooth_h if (i % 4) in [1, 2] else 0.0)
		pts.append(Vector2(cos(a), sin(a)) * r)
	var x0 := -width * 0.5
	var x1 := width * 0.5
	var n := pts.size()
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var mid := (a + b) * 0.5
		oquad(st, Vector3(x0, a.x, a.y), Vector3(x1, a.x, a.y), Vector3(x1, b.x, b.y), Vector3(x0, b.x, b.y), Vector3(0, mid.x, mid.y))
		tri(st, Vector3(x0, 0, 0), Vector3(x0, a.x, a.y), Vector3(x0, b.x, b.y), Vector3(-1, 0, 0))
		tri(st, Vector3(x1, 0, 0), Vector3(x1, a.x, a.y), Vector3(x1, b.x, b.y), Vector3(1, 0, 0))
	st.index()
	return st.commit()


## Половина трубы (гильза в разрезе), открыта в сторону +Z.
static func half_tube(r_in: float, r_out: float, h: float, segs: int = 20) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a0 := PI * 0.5
	var a1 := PI * 1.5
	var y0 := -h * 0.5
	var y1 := h * 0.5
	var up := Vector3(0, 1, 0)
	for i in segs:
		var t0 := lerpf(a0, a1, float(i) / segs)
		var t1 := lerpf(a0, a1, float(i + 1) / segs)
		var c0 := Vector3(sin(t0), 0, cos(t0))
		var c1 := Vector3(sin(t1), 0, cos(t1))
		var mid := (c0 + c1) * 0.5
		# внешняя стенка — наружу, внутренняя — к оси (гладкие нормали)
		oquad(st, c0 * r_out + up * y0, c1 * r_out + up * y0, c1 * r_out + up * y1, c0 * r_out + up * y1, mid, c0, c1, c1, c0)
		oquad(st, c0 * r_in + up * y0, c1 * r_in + up * y0, c1 * r_in + up * y1, c0 * r_in + up * y1, -mid, -c0, -c1, -c1, -c0)
		oquad(st, c0 * r_in + up * y0, c1 * r_in + up * y0, c1 * r_out + up * y0, c0 * r_out + up * y0, -up)
		oquad(st, c0 * r_in + up * y1, c1 * r_in + up * y1, c1 * r_out + up * y1, c0 * r_out + up * y1, up)
	# торцы разреза смотрят в открытую сторону (+Z)
	for t in [a0, a1]:
		var c := Vector3(sin(t), 0, cos(t))
		oquad(st, c * r_in + up * y0, c * r_out + up * y0, c * r_out + up * y1, c * r_in + up * y1, Vector3(0, 0, 1))
	st.index()
	return st.commit()


static func _poly_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


## Выдавливание многоугольника (в плоскости YZ) вдоль X.
static func extrude(poly: PackedVector2Array, depth: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var idx := Geometry2D.triangulate_polygon(poly)
	for side in [-0.5, 0.5]:
		var out := Vector3(signf(side), 0, 0)
		for i in range(0, idx.size(), 3):
			var p0 := poly[idx[i]]
			var p1 := poly[idx[i + 1]]
			var p2 := poly[idx[i + 2]]
			tri(st, Vector3(side * depth, p0.x, p0.y), Vector3(side * depth, p1.x, p1.y), Vector3(side * depth, p2.x, p2.y), out)
	var n := poly.size()
	var ccw := _poly_area(poly) > 0.0
	for i in n:
		var p0 := poly[i]
		var p1 := poly[(i + 1) % n]
		var e := p1 - p0
		var o2 := Vector2(e.y, -e.x) if ccw else Vector2(-e.y, e.x)
		oquad(st, Vector3(-depth * 0.5, p0.x, p0.y), Vector3(-depth * 0.5, p1.x, p1.y),
			Vector3(depth * 0.5, p1.x, p1.y), Vector3(depth * 0.5, p0.x, p0.y), Vector3(0, o2.x, o2.y))
	st.index()
	return st.commit()


## Кольцо между двумя контурами с одинаковым числом точек, выдавленное вдоль X.
static func extrude_ring(inner: PackedVector2Array, outer: PackedVector2Array, depth: float) -> ArrayMesh:
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
			oquad(st, Vector3(x, a.x, a.y), Vector3(x, b.x, b.y), Vector3(x, c.x, c.y), Vector3(x, d.x, d.y), Vector3(signf(x), 0, 0))
		var mi := (a + b) * 0.5
		var mo := (c + d) * 0.5
		oquad(st, Vector3(x0, a.x, a.y), Vector3(x0, b.x, b.y), Vector3(x1, b.x, b.y), Vector3(x1, a.x, a.y), -Vector3(0, mi.x, mi.y))
		oquad(st, Vector3(x0, d.x, d.y), Vector3(x0, c.x, c.y), Vector3(x1, c.x, c.y), Vector3(x1, d.x, d.y), Vector3(0, mo.x, mo.y))
	st.index()
	return st.commit()


static func cyl(r: float, h: float, segs: int = 24) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c


static func cone(r0: float, r1: float, h: float, segs: int = 24, caps: bool = true) -> CylinderMesh:
	var c := cyl(r0, h, segs)
	c.top_radius = r1
	c.cap_top = caps
	c.cap_bottom = caps
	return c


static func box(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b


## Поворот, переводящий ось Y в направление dir.
static func align_y(dir: Vector3) -> Basis:
	var d := dir.normalized()
	if d.is_equal_approx(Vector3.UP):
		return Basis.IDENTITY
	if d.is_equal_approx(Vector3.DOWN):
		return Basis(Vector3.RIGHT, PI)
	return Basis(Quaternion(Vector3.UP, d))


# ---------------------------------------------------------------------
# Склейка статичных деталей по материалам: одна сетка на материал
# ---------------------------------------------------------------------

class Batch:
	var tools: Dictionary = {}

	func add(key: String, mesh: Mesh, xf: Transform3D) -> void:
		if not tools.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[key] = st
		var s: SurfaceTool = tools[key]
		for i in mesh.get_surface_count():
			s.append_from(mesh, i, xf)

	## Одна сетка с несколькими поверхностями (по поверхности на материал).
	func commit_mesh(mats: Dictionary) -> ArrayMesh:
		var mesh := ArrayMesh.new()
		for key in tools:
			var st: SurfaceTool = tools[key]
			st.commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, mats.get(key))
		tools.clear()
		return mesh

	func commit(parent: Node3D, mats: Dictionary) -> Array:
		var out: Array = []
		for key in tools:
			var st: SurfaceTool = tools[key]
			var mi := MeshInstance3D.new()
			mi.mesh = st.commit()
			mi.material_override = mats.get(key)
			mi.name = "batch_" + key
			parent.add_child(mi)
			out.append(mi)
		tools.clear()
		return out
