class_name Big
extends RefCounted
## Большое число: мантисса [1, 10) и целая степень десяти.
## Держит значения далеко за 1e308 (до 1e1000000 и дальше).

const SUFFIXES := ["", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"]

var m: float = 0.0
var e: int = 0


func _init(mant: float = 0.0, ex: int = 0) -> void:
	m = mant
	e = ex
	_norm()


func _norm() -> void:
	if m == 0.0 or is_nan(m):
		m = 0.0
		e = 0
		return
	if is_inf(m):
		m = 9.99 if m > 0 else -9.99
		e += 308
		return
	var a := absf(m)
	if a >= 10.0 or a < 1.0:
		var k := int(floor(log(a) / log(10.0)))
		m = m / pow(10.0, k)
		e += k
		if absf(m) >= 10.0:
			m /= 10.0
			e += 1
		elif absf(m) < 1.0:
			m *= 10.0
			e -= 1


static func of(v) -> Big:
	if v is Big:
		return Big.new(v.m, v.e)
	if v is Array:
		return Big.new(float(v[0]), int(v[1]))
	return Big.new(float(v), 0)


static func zero() -> Big:
	return Big.new(0.0, 0)


## base^exp без переполнения.
static func power(base: float, ex: float) -> Big:
	if base <= 0.0:
		return Big.zero()
	var l := ex * log(base) / log(10.0)
	var ie := int(floor(l))
	return Big.new(pow(10.0, l - ie), ie)


static func from_log10(l: float) -> Big:
	var ie := int(floor(l))
	return Big.new(pow(10.0, l - ie), ie)


func copy() -> Big:
	return Big.new(m, e)


func is_zero() -> bool:
	return m == 0.0


func add(b) -> Big:
	var o := Big.of(b)
	if o.m == 0.0:
		return copy()
	if m == 0.0:
		return o
	var d := e - o.e
	if d > 16:
		return copy()
	if d < -16:
		return o
	if d >= 0:
		return Big.new(m + o.m * pow(10.0, -d), e)
	return Big.new(o.m + m * pow(10.0, d), o.e)


func sub(b) -> Big:
	var o := Big.of(b)
	return add(Big.new(-o.m, o.e))


func mul(b) -> Big:
	if b is Big:
		return Big.new(m * b.m, e + b.e)
	return Big.new(m * float(b), e)


func div(b) -> Big:
	if b is Big:
		if b.m == 0.0:
			return Big.zero()
		return Big.new(m / b.m, e - b.e)
	var f := float(b)
	if f == 0.0:
		return Big.zero()
	return Big.new(m / f, e)


func cmp(b) -> int:
	var d := sub(b)
	if d.m > 0.0:
		return 1
	if d.m < 0.0:
		return -1
	return 0


func gte(b) -> bool:
	return cmp(b) >= 0


func lt(b) -> bool:
	return cmp(b) < 0


func max_with(b) -> Big:
	return copy() if gte(b) else Big.of(b)


func log10() -> float:
	if m <= 0.0:
		return -INF
	return log(m) / log(10.0) + e


func to_float() -> float:
	if e > 308:
		return INF
	if e < -308:
		return 0.0
	return m * pow(10.0, e)


func floored() -> Big:
	if e >= 15:
		return copy()
	return Big.new(floor(to_float()), 0)


func to_arr() -> Array:
	return [m, e]


static func _letters(i: int) -> String:
	# 0 -> aa, 1 -> ab, ... 675 -> zz, 676 -> aaa ...
	var length := 2
	var span := 676
	while i >= span:
		i -= span
		length += 1
		span *= 26
	var s := ""
	for _k in length:
		s = char(97 + i % 26) + s
		i = i / 26
	return s


static func suffix_for(group: int) -> String:
	if group < SUFFIXES.size():
		return SUFFIXES[group]
	return _letters(group - SUFFIXES.size())


func fmt(sci: bool = false) -> String:
	if m == 0.0:
		return "0"
	var sign := "-" if m < 0.0 else ""
	var am := absf(m)
	if e < 3:
		var v := am * pow(10.0, e)
		if v < 10.0 and v != floor(v):
			return sign + ("%.1f" % v)
		return sign + str(int(floor(v)))
	if sci:
		return sign + ("%.2fe%d" % [am, e])
	var group := e / 3
	var v2 := am * pow(10.0, e - group * 3)
	var num: String
	if v2 < 10.0:
		num = "%.2f" % v2
	elif v2 < 100.0:
		num = "%.1f" % v2
	else:
		num = "%d" % int(floor(v2))
	return sign + num + suffix_for(group)


func _to_string() -> String:
	return fmt()
