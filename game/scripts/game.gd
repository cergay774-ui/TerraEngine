extends Node
## Состояние игры и экономика: доход, стамина, турбо, криты, улучшения, запчасти,
## перерождения, магазин, задания, достижения, сохранение.

signal changed                       # что-то купили/поменялось — UI перерисовывается
signal level_up(level: int)
signal new_epoch(epoch_index: int)
signal turbo_started
signal crit(amount: Big)
signal gold_dropped(amount: int)
signal exhausted
signal toast(text: String, color: Color)
signal rebirth_done
signal part_gained(slot_id: String, mk: int, rarity: int)
signal settings_changed

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1
const AUTOSAVE_EVERY := 30.0
const TURBO_TIME := 4.0
const BASE_INCOME := 3.0

# --- сохраняемое состояние ---
var cur: Dictionary = {}            # id валюты -> Big
var unlocked_cur: Dictionary = {"cash": true}
var upg: Dictionary = {}            # id улучшения -> уровень
var parts: Dictionary = {}          # id слота -> {"owned": [{mk, rar, src}], "eq": индекс}
var rebirths: int = 0
var ultra: int = 0
var sapph: Dictionary = {}
var quant: Dictionary = {}
var uskill: Dictionary = {}
var level: int = 1
var xp: Big = Big.zero()
var run_earned: Big = Big.zero()
var total_earned: Big = Big.zero()
var stats: Dictionary = {}
var ach: Dictionary = {}            # категория -> сколько ступеней пройдено
var boosts: Array = []              # [{"type", "until"}]
var shop_state: Dictionary = {"hour": -1, "bought": []}
var daily: Dictionary = {"day": "", "tasks": []}
var engine_choice: String = ""
var settings: Dictionary = {
	"quality": 1, "fps": 60, "shake": true, "vibration": true,
	"sfx": 0.8, "music": 0.6, "sci": false, "lang": "ru", "xray": false,
	"shadows": 1, "msaa": 2, "glow": true, "particles": 1, "res_scale": 0.85,
	"garage": true, "cam_sway": true, "cam_zoom": 1.0, "show_fps": false,
}

## Пресеты графики: Низкое, Среднее, Высокое, Ультра.
const PRESETS := [
	{"shadows": 0, "msaa": 0, "glow": false, "particles": 0, "res_scale": 0.6, "garage": true},
	{"shadows": 1, "msaa": 2, "glow": true, "particles": 1, "res_scale": 0.85, "garage": true},
	{"shadows": 1, "msaa": 4, "glow": true, "particles": 2, "res_scale": 1.0, "garage": true},
	{"shadows": 2, "msaa": 4, "glow": true, "particles": 2, "res_scale": 1.0, "garage": true},
]
var last_time: float = 0.0

# --- рантайм ---
var holding: bool = false
var throttle: bool = false
var stamina: float = 4.0
var is_exhausted: bool = false
var turbo_time: float = 0.0
var turbo_cd: float = 0.0
var autogas_timer: float = 0.0
var autogas_left: float = 0.0
var guaranteed_turbo: bool = false
var income_now: Big = Big.zero()
var offline_report: Big = null
var offline_seconds: float = 0.0

var _roll_acc: float = 0.0
var _save_acc: float = 0.0
var _sec_acc: float = 0.0
var _dirty: bool = true
var _rng := RandomNumberGenerator.new()

# --- производные (пересчитываются в recalc) ---
var d_hold: Big = Big.zero()
var d_passive: Big = Big.zero()
var d_passive_frac: float = 0.1
var d_stamina_max: float = 4.0
var d_regen: float = 0.5
var d_turbo_on: bool = false
var d_turbo_chance: float = 0.0
var d_turbo_cd: float = 60.0
var d_turbo_mult: float = 2.0
var d_crit_on: bool = false
var d_crit_chance: float = 0.0
var d_crit_power: float = 10.0
var d_autogas_on: bool = false
var d_autogas_int: float = 30.0
var d_offline_hours: float = 0.0
var d_offline_pct: float = 0.0
var d_max_rpm_mult: float = 1.0
var d_shake_mult: float = 1.0
var d_time_mult: float = 1.0


func _ready() -> void:
	_rng.randomize()
	_reset_all()
	load_game()
	recalc()
	_refresh_daily()
	apply_settings()


func _reset_all() -> void:
	cur = {}
	for id in D.CURRENCY_ORDER:
		cur[id] = Big.zero()
	unlocked_cur = {"cash": true}
	upg = {}
	for u in D.UPGRADES:
		upg[u.id] = 0
	parts = {}
	for s in D.SLOTS:
		parts[s.id] = {"owned": [], "eq": -1}
	rebirths = 0
	ultra = 0
	sapph = {}
	quant = {}
	uskill = {}
	level = 1
	xp = Big.zero()
	run_earned = Big.zero()
	total_earned = Big.zero()
	stats = {"presses": 0, "hold_time": 0.0, "best_ips": [0.0, 0], "turbos": 0, "crits": 0,
		"parts": 0, "cases": 0, "playtime": 0.0, "ultras": 0, "rebirths_total": 0}
	ach = {}
	boosts = []
	shop_state = {"hour": -1, "bought": []}
	daily = {"day": "", "tasks": []}
	engine_choice = ""
	stamina = 4.0
	is_exhausted = false


# =====================================================================
# Производные характеристики
# =====================================================================

func part_bonus(slot_id: String) -> float:
	var p: Dictionary = parts.get(slot_id, {})
	if p.is_empty() or p.eq < 0 or p.eq >= p.owned.size():
		return 0.0
	var it: Dictionary = p.owned[p.eq]
	return part_power(slot_id, int(it.mk), int(it.rar))


func part_power(slot_id: String, mk: int, rar: int) -> float:
	var s := D.slot(slot_id)
	return minf(1e300, float(s.base) * pow(3.0, mk - 1) * float(D.RARITIES[rar].mult))


func equipped(slot_id: String) -> Dictionary:
	var p: Dictionary = parts.get(slot_id, {})
	if p.is_empty() or p.eq < 0 or p.eq >= p.owned.size():
		return {}
	return p.owned[p.eq]


func press_mult() -> Big:
	var l: int = upg.press
	return Big.power(2.0, l / 25).mul(1.0 + 0.1 * l)


func global_mult() -> Big:
	var g := Big.of(1.0)
	g = g.mul(1.0 + part_bonus("block"))
	g = g.mul(1.0 + 0.5 * part_bonus("crank"))
	g = g.mul(1.0 + 0.5 * part_bonus("head"))
	g = g.mul(1.0 + part_bonus("reactor"))
	g = g.mul(Big.power(1.25, rebirths))
	g = g.mul(Big.power(100.0, ultra))
	g = g.mul(Big.power(1.05, level - 1))
	g = g.mul(D.epoch_info(level).mult)
	g = g.mul(Big.power(1.5, sapph.get("s_income", 0)))
	g = g.mul(Big.power(10.0, quant.get("q_mult", 0)))
	g = g.mul(Big.power(3.0, uskill.get("u_income", 0)))
	g = g.mul(1.0 + 0.01 * achievements_count())
	if has_boost("income"):
		g = g.mul(2.0)
	return g


func recalc() -> void:
	_dirty = false
	var gm := global_mult()
	d_hold = press_mult().mul(1.0 + part_bonus("pistons")).mul(gm).mul(BASE_INCOME)
	d_passive_frac = minf(1.0, 0.10 + 0.005 * upg.passive)
	d_passive = d_hold.mul(d_passive_frac).mul(1.0 + part_bonus("exhaust"))
	var us: int = uskill.get("u_stamina", 0)
	d_stamina_max = (4.0 + 0.1 * upg.stamina) * (1.0 + part_bonus("fuel")) \
		* (1.0 + 0.2 * sapph.get("s_stamina", 0)) * (1.0 + 0.5 * us) * (1.0 + 0.5 * part_bonus("stabilizer"))
	# полное восстановление всегда ~8 с (1 с стамины за 2 с отдыха на старте), охлаждение ускоряет
	d_regen = d_stamina_max / 8.0 * (1.0 + 0.01 * upg.cooling) * (1.0 + part_bonus("cooling")) * (1.0 + 0.5 * us)
	var luck: float = 0.05 * uskill.get("u_luck", 0)
	var tl: int = upg.turbo
	d_turbo_on = tl >= 1
	d_turbo_chance = minf(0.5, 0.02 + 0.001 * maxi(tl - 1, 0)) + minf(0.25, part_bonus("ignition") * 0.01) + luck
	d_turbo_cd = maxf(10.0, 60.0 - 0.1 * maxi(tl - 1, 0))
	d_turbo_mult = 2.0 + part_bonus("turbine")
	var cl: int = upg.crit
	d_crit_on = cl >= 1
	d_crit_chance = minf(0.25, 0.01 + 0.0005 * maxi(cl - 1, 0)) + minf(0.25, part_bonus("flywheel") * 0.005) + luck
	d_crit_power = (10.0 + maxi(cl - 1, 0)) * (1.0 + part_bonus("flywheel"))
	var al: int = upg.autogas
	d_autogas_on = al >= 1
	d_autogas_int = maxf(2.0, 30.0 - 0.1 * maxi(al - 1, 0))
	var ol: int = upg.offline
	d_offline_hours = 0.0 if ol < 1 else minf(24.0, 1.0 + maxi(ol - 1, 0) / 60.0)
	d_offline_pct = 0.0 if ol < 1 else minf(1.0, 0.5 + 0.001 * maxi(ol - 1, 0))
	d_max_rpm_mult = 1.0 + minf(0.6, 0.05 * part_bonus("head"))
	d_shake_mult = 1.0 / (1.0 + 0.5 * part_bonus("crank") + part_bonus("stabilizer"))
	d_time_mult = 1.0 + 0.25 * quant.get("q_time", 0)
	stamina = minf(stamina, d_stamina_max)


func mark_dirty() -> void:
	_dirty = true


func current_income() -> Big:
	if throttle:
		var r := d_hold
		if turbo_time > 0.0:
			r = r.mul(d_turbo_mult)
		return r
	return d_passive


# =====================================================================
# Игровой цикл
# =====================================================================

func set_holding(v: bool) -> void:
	if v and not holding:
		stats.presses += 1
	holding = v


func _process(delta: float) -> void:
	if _dirty:
		recalc()
	var now := Time.get_unix_time_from_system()
	stats.playtime += delta
	_update_boosts(now)

	# автогаз
	if d_autogas_on and not holding:
		autogas_timer += delta
		if autogas_timer >= d_autogas_int:
			autogas_timer = 0.0
			autogas_left = 1.0
	else:
		autogas_timer = 0.0
	if autogas_left > 0.0:
		autogas_left -= delta
	var want := holding or autogas_left > 0.0

	# стамина
	var infinite := has_boost("stamina")
	if is_exhausted:
		stamina = minf(d_stamina_max, stamina + d_regen * delta)
		if stamina >= d_stamina_max:
			is_exhausted = false
	elif want:
		if not infinite:
			stamina -= delta
		if stamina <= 0.0:
			stamina = 0.0
			is_exhausted = true
			exhausted.emit()
	else:
		stamina = minf(d_stamina_max, stamina + d_regen * delta)
	throttle = want and not is_exhausted

	# турбо
	if has_boost("turbo"):
		turbo_time = maxf(turbo_time, 0.2)
	if turbo_time > 0.0:
		turbo_time -= delta
		if turbo_time <= 0.0:
			turbo_cd = d_turbo_cd
	elif turbo_cd > 0.0:
		turbo_cd -= delta

	# броски раз в секунду, пока газ зажат
	if throttle:
		if holding:
			stats.hold_time += delta
			_daily_progress("hold", delta)
		_roll_acc += delta
		while _roll_acc >= 1.0:
			_roll_acc -= 1.0
			_roll_second()
	else:
		_roll_acc = 0.0

	# доход
	income_now = current_income()
	var gain := income_now.mul(delta * d_time_mult)
	add_income(gain)
	if income_now.gte(Big.of(stats.best_ips)):
		stats.best_ips = income_now.to_arr()

	_sec_acc += delta
	if _sec_acc >= 1.0:
		_sec_acc = 0.0
		_check_achievements()
		if quant.get("q_auto", 0) > 0 and can_rebirth():
			do_rebirth()

	_save_acc += delta
	if _save_acc >= AUTOSAVE_EVERY:
		_save_acc = 0.0
		save_game()


func _roll_second() -> void:
	if d_turbo_on and turbo_time <= 0.0 and turbo_cd <= 0.0:
		if guaranteed_turbo or _rng.randf() < d_turbo_chance:
			guaranteed_turbo = false
			start_turbo(TURBO_TIME)
	if d_crit_on and _rng.randf() < d_crit_chance:
		var amount := d_hold.mul(d_crit_power)
		add_income(amount)
		stats.crits += 1
		crit.emit(amount)
	if unlocked_cur.get("gold", false) and _rng.randf() < 0.004:
		var g := maxi(1, rebirths / 2)
		add_cur("gold", Big.of(g))
		gold_dropped.emit(g)


func start_turbo(t: float) -> void:
	turbo_time = t
	stats.turbos += 1
	_daily_progress("turbo", 1)
	turbo_started.emit()
	vibrate(60)


func add_income(amount: Big) -> void:
	if amount.is_zero():
		return
	cur.cash = cur.cash.add(amount)
	run_earned = run_earned.add(amount)
	total_earned = total_earned.add(amount)
	xp = xp.add(amount.mul(pow(2.0, sapph.get("s_xp", 0))))
	_daily_progress("earn", 0)
	var need := xp_need(level)
	var guard := 0
	while xp.gte(need) and guard < 50:
		guard += 1
		xp = xp.sub(need)
		level += 1
		mark_dirty()
		level_up.emit(level)
		if (level - 1) % 10 == 0:
			var ei := D.epoch_index(level)
			var ep := D.epoch_info(level)
			engine_choice = ep.engines[ep.engines.size() - 1]
			new_epoch.emit(ei)
		need = xp_need(level)


func xp_need(l: int) -> Big:
	return Big.power(4.0, l - 1).mul(50.0)


func add_cur(id: String, amount: Big) -> void:
	cur[id] = cur[id].add(amount)
	changed.emit()


func can_pay(id: String, amount: Big) -> bool:
	return cur[id].gte(amount)


func pay(id: String, amount: Big) -> bool:
	if not cur[id].gte(amount):
		return false
	cur[id] = cur[id].sub(amount)
	if cur[id].m < 0.0:
		cur[id] = Big.zero()
	return true


func fmt(b) -> String:
	return Big.of(b).fmt(settings.sci)


func vibrate(ms: int) -> void:
	if settings.vibration and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)


# =====================================================================
# Бусты
# =====================================================================

func has_boost(type: String) -> bool:
	for b in boosts:
		if b.type == type:
			return true
	return false


func boost_left(type: String) -> float:
	var now := Time.get_unix_time_from_system()
	for b in boosts:
		if b.type == type:
			return maxf(0.0, b.until - now)
	return 0.0


func add_boost(type: String, seconds: float) -> void:
	var now := Time.get_unix_time_from_system()
	for b in boosts:
		if b.type == type:
			b.until = maxf(b.until, now) + seconds
			mark_dirty()
			return
	boosts.append({"type": type, "until": now + seconds})
	mark_dirty()


func _update_boosts(now: float) -> void:
	for i in range(boosts.size() - 1, -1, -1):
		if boosts[i].until <= now:
			boosts.remove_at(i)
			mark_dirty()


# =====================================================================
# Улучшения
# =====================================================================

func upgrade_unlocked(id: String) -> bool:
	var u := D.upgrade(id)
	var un: Dictionary = u.unlock
	if un.has("upg"):
		return upg[un.upg] >= un.lvl
	if un.has("rebirth"):
		return unlocked_cur.get(u.cur, false)
	return true


func upgrade_cap(id: String) -> int:
	var u := D.upgrade(id)
	if u.max < 0:
		return -1
	return u.max + (1000 * ultra if u.get("ultra_cap", false) else 0)


func upgrade_cost(id: String, n: int = 1) -> Big:
	var u := D.upgrade(id)
	var g: float = u.growth
	var start := Big.power(g, upg[id]).mul(u.base)
	if n == 1:
		return start
	return start.mul(Big.power(g, n).sub(1.0)).div(g - 1.0)


## Сколько уровней можно купить сейчас (не больше лимита).
func upgrade_affordable(id: String) -> int:
	var u := D.upgrade(id)
	var g: float = u.growth
	var money: Big = cur[u.cur]
	var start := Big.power(g, upg[id]).mul(u.base)
	if money.lt(start):
		return 0
	var ratio := money.mul(g - 1.0).div(start).add(1.0)
	var n := int(floor(ratio.log10() / (log(g) / log(10.0))))
	n = maxi(n, 1)
	while n > 1 and upgrade_cost(id, n).cmp(money) > 0:
		n -= 1
	var cap := upgrade_cap(id)
	if cap >= 0:
		n = mini(n, cap - upg[id])
	return maxi(n, 0)


func buy_upgrade(id: String, n: int) -> int:
	if not upgrade_unlocked(id):
		return 0
	var cap := upgrade_cap(id)
	if cap >= 0:
		n = mini(n, cap - upg[id])
	if n <= 0:
		return 0
	var u := D.upgrade(id)
	var cost := upgrade_cost(id, n)
	if not pay(u.cur, cost):
		return 0
	upg[id] += n
	_daily_progress("upgrades", n)
	mark_dirty()
	changed.emit()
	return n


func upgrade_effect_text(id: String, l: int) -> String:
	match id:
		"press":
			return "x%s дохода" % Big.power(2.0, l / 25).mul(1.0 + 0.1 * l).fmt(settings.sci)
		"stamina":
			return "%.1f с" % (4.0 + 0.1 * l)
		"passive":
			return "%.1f%% от полного" % (minf(1.0, 0.10 + 0.005 * l) * 100.0)
		"turbo":
			if l < 1:
				return "выкл."
			return "%.1f%%/с, перезарядка %.0f с" % [minf(0.5, 0.02 + 0.001 * (l - 1)) * 100.0, maxf(10.0, 60.0 - 0.1 * (l - 1))]
		"cooling":
			return "+%d%% скорости" % l
		"crit":
			if l < 1:
				return "выкл."
			return "%.2f%%, x%d" % [minf(0.25, 0.01 + 0.0005 * (l - 1)) * 100.0, 10 + (l - 1)]
		"autogas":
			if l < 1:
				return "выкл."
			return "раз в %.1f с" % maxf(2.0, 30.0 - 0.1 * (l - 1))
		"offline":
			if l < 1:
				return "выкл."
			return "%.1f ч, %.1f%%" % [minf(24.0, 1.0 + (l - 1) / 60.0), minf(1.0, 0.5 + 0.001 * (l - 1)) * 100.0]
	return ""


func upgrade_unlock_text(id: String) -> String:
	var u := D.upgrade(id)
	var un: Dictionary = u.unlock
	if un.has("upg"):
		return "Откроется: %s %d ур." % [D.upgrade(un.upg).name, un.lvl]
	if un.has("rebirth"):
		return "Откроется: перерождение %d" % un.rebirth
	return ""


# =====================================================================
# Запчасти
# =====================================================================

func slot_visible(slot_id: String) -> bool:
	var s := D.slot(slot_id)
	if s.unlock.has("ultra"):
		return ultra >= 1 or stats.ultras >= 1
	return true


func best_mark(slot_id: String) -> int:
	var best := 0
	for it in parts[slot_id].owned:
		best = maxi(best, int(it.mk))
	return best


func owns(slot_id: String, mk: int, rar: int) -> bool:
	for it in parts[slot_id].owned:
		if int(it.mk) == mk and int(it.rar) == rar:
			return true
	return false


## Покупаемая марка (обычная редкость): условие и цена.
## Возвращает {"ok": bool, "cur": id, "price": Big, "text": String, "free": bool}
func mark_offer(slot_id: String, mk: int) -> Dictionary:
	var s := D.slot(slot_id)
	var un: Dictionary = s.unlock
	if mk == 1:
		if un.has("upg"):
			var ok: bool = upg[un.upg] >= un.lvl
			return {"ok": ok, "cur": "cash", "price": Big.zero(), "free": true,
				"text": "%s %d ур." % [D.upgrade(un.upg).name, un.lvl]}
		if un.has("level"):
			var ok2: bool = level >= un.level
			return {"ok": ok2, "cur": "cash", "price": Big.of(un.cash), "free": false,
				"text": "Уровень %d" % un.level if not ok2 else ""}
		if un.has("gold"):
			var ok3: bool = unlocked_cur.get("gold", false)
			return {"ok": ok3, "cur": "gold", "price": Big.of(un.gold), "free": false,
				"text": "" if ok3 else "Перерождение 1"}
		if un.has("ultra"):
			return {"ok": ultra >= 1, "cur": "core", "price": Big.of(1.0), "free": false,
				"text": "" if ultra >= 1 else "Ультра-перерождение"}
		return {"ok": true, "cur": "cash", "price": Big.of(un.get("cash", 100.0)), "free": false, "text": ""}
	# Mk II+ — нужна предыдущая марка
	var need_prev := best_mark(slot_id) >= mk - 1
	var base_cash: float = un.get("cash", 0.0)
	if base_cash <= 0.0:
		base_cash = {"pistons": 2.0e3, "head": 2.0e5, "cooling": 2.0e6}.get(slot_id, 1.0e4)
	var curr := "cash"
	var price: Big
	if un.has("ultra"):
		curr = "core"
		price = Big.power(2.0, mk - 1)
	elif un.has("gold") or mk >= 16:
		curr = "emerald" if mk >= 16 else "gold"
		price = Big.power(2.0, mk - (16 if mk >= 16 else 1)).mul(5.0)
	elif mk <= 5:
		price = Big.power(10.0, mk - 1).mul(base_cash)
	elif mk <= 10:
		curr = "gold"
		price = Big.power(2.0, mk - 6).mul(5.0)
	else:
		curr = "diamond"
		price = Big.power(2.0, mk - 11).mul(5.0)
	var cur_ok: bool = unlocked_cur.get(curr, false)
	var txt := ""
	if not need_prev:
		txt = "Нужна Mk %s" % D.roman(mk - 1)
	elif not cur_ok:
		txt = "Нужна валюта: %s" % D.CURRENCIES[curr].name
	return {"ok": need_prev and cur_ok, "cur": curr, "price": price, "free": false, "text": txt}


func buy_mark(slot_id: String, mk: int, discount: float = 0.0) -> bool:
	if owns(slot_id, mk, 0):
		return false
	var o := mark_offer(slot_id, mk)
	if not o.ok:
		return false
	var price: Big = o.price.mul(1.0 - discount)
	if not o.free and not pay(o.cur, price):
		return false
	var src: String = "cash" if (o.cur == "cash") else "rare"
	give_part(slot_id, mk, 0, src)
	return true


func give_part(slot_id: String, mk: int, rar: int, src: String) -> void:
	var p: Dictionary = parts[slot_id]
	if owns(slot_id, mk, rar):
		var comp := d_hold.mul(30.0)
		add_income(comp)
		toast.emit("Дубликат: +%s кэша" % fmt(comp), Color("c8c8c8"))
		return
	p.owned.append({"mk": mk, "rar": rar, "src": src})
	stats.parts += 1
	# ставим лучшую
	var best_i := 0
	var best_v := -1.0
	for i in p.owned.size():
		var v := part_power(slot_id, int(p.owned[i].mk), int(p.owned[i].rar))
		if v > best_v:
			best_v = v
			best_i = i
	p.eq = best_i
	mark_dirty()
	part_gained.emit(slot_id, mk, rar)
	changed.emit()


func equip(slot_id: String, index: int) -> void:
	parts[slot_id].eq = index
	mark_dirty()
	changed.emit()


# =====================================================================
# Магазин: кейсы
# =====================================================================

func case_price(c: Dictionary) -> Big:
	return Big.power(c.price_growth, rebirths).mul(c.price)


func case_available(c: Dictionary) -> bool:
	return unlocked_cur.get(c.cur, false)


## Открывает кейс, возвращает {"slot", "mk", "rar", "cash": Big}
func open_case(c: Dictionary, discount: float = 0.0) -> Dictionary:
	if not case_available(c):
		return {}
	if not pay(c.cur, case_price(c).mul(1.0 - discount)):
		return {}
	stats.cases += 1
	_daily_progress("cases", 1)
	var roll := _rng.randf() * 100.0
	var rar := 0
	var acc := 0.0
	for i in c.odds.size():
		acc += c.odds[i]
		if roll < acc:
			rar = i
			break
	var pool: Array = []
	for s in D.SLOTS:
		if slot_visible(s.id):
			pool.append(s.id)
	var sid: String = pool[_rng.randi() % pool.size()]
	var mk := maxi(1, best_mark(sid)) + _rng.randi_range(c.mark_bonus[0], c.mark_bonus[1])
	if c.id == "garage":
		mk = _rng.randi_range(1, maxi(1, best_mark(sid)))
	var bonus_cash := Big.zero()
	if c.id == "garage":
		bonus_cash = d_hold.mul(_rng.randf_range(10.0, 40.0))
		add_income(bonus_cash)
	if c.id == "gold" and _rng.randf() < 0.3:
		add_boost("income", 120.0)
		toast.emit("Буст: x2 дохода на 2 минуты", Color("ffcc33"))
	if c.id == "gold" and unlocked_cur.get("diamond", false) and _rng.randf() < 0.05:
		add_cur("diamond", Big.of(1.0))
		toast.emit("Из кейса выпал алмаз!", Color("7fe7ff"))
	give_part(sid, mk, rar, "case")
	return {"slot": sid, "mk": mk, "rar": rar, "cash": bonus_cash}


func case_odds_text(c: Dictionary) -> String:
	var parts_txt: Array = []
	for i in c.odds.size():
		if c.odds[i] > 0.0:
			parts_txt.append("%s %d%%" % [D.RARITIES[i].name, int(c.odds[i])])
	return ", ".join(parts_txt)


# =====================================================================
# Магазин: ежечасовые предложения
# =====================================================================

func hour_index() -> int:
	return int(Time.get_unix_time_from_system() / 3600.0)


func hour_left() -> float:
	var now := Time.get_unix_time_from_system()
	return 3600.0 - fmod(now, 3600.0)


func hourly_offers() -> Array:
	var h := hour_index()
	if shop_state.hour != h:
		shop_state = {"hour": h, "bought": []}
	var rng := RandomNumberGenerator.new()
	rng.seed = h * 7919 + 1337
	var hot := rng.randi_range(0, 5)
	var kinds := ["boost_income", "boost_stamina", "boost_turbo", "upgrade", "part", "case"]
	var res: Array = []
	for i in 6:
		var kind: String = kinds[rng.randi_range(0, kinds.size() - 1)]
		var disc := rng.randf_range(0.05, 0.15)
		if kind in ["upgrade", "case", "boost_income", "boost_stamina", "boost_turbo"]:
			disc = rng.randf_range(0.1, 0.3)
		if i == hot:
			disc = rng.randf_range(0.35, 0.5)
		var o := {"i": i, "kind": kind, "disc": disc, "hot": i == hot, "pick": rng.randi()}
		res.append(_resolve_offer(o))
	return res


func _resolve_offer(o: Dictionary) -> Dictionary:
	var pick: int = o.pick
	match o.kind:
		"boost_income":
			o.title = "x2 дохода на 10 мин"
			o.cur = "cash"
			o.price = d_hold.mul(240.0)
		"boost_stamina":
			o.title = "Бесконечная стамина 2 мин"
			o.cur = "cash"
			o.price = d_hold.mul(90.0)
		"boost_turbo":
			o.title = "Гарантированный турбо"
			o.cur = "cash"
			o.price = d_hold.mul(60.0)
		"upgrade":
			var ids: Array = []
			for u in D.UPGRADES:
				if u.cur == "cash" and upgrade_unlocked(u.id):
					ids.append(u.id)
			var id: String = ids[pick % ids.size()]
			o.target = id
			o.title = "%s +10 ур." % D.upgrade(id).name
			o.cur = "cash"
			o.price = upgrade_cost(id, 10)
		"part":
			var sids: Array = []
			for s in D.SLOTS:
				if slot_visible(s.id):
					sids.append(s.id)
			var sid: String = sids[pick % sids.size()]
			var mk := best_mark(sid) + 1
			var off := mark_offer(sid, mk)
			o.target = sid
			o.mk = mk
			o.title = "%s Mk %s" % [D.slot(sid).name, D.roman(mk)]
			o.cur = off.cur
			o.price = off.price
			o.blocked = not off.ok or off.free
		"case":
			var avail: Array = []
			for c in D.CASES:
				if case_available(c):
					avail.append(c)
			var c2: Dictionary = avail[pick % avail.size()]
			o.target = c2.id
			o.title = "%s кейс" % c2.name
			o.cur = c2.cur
			o.price = case_price(c2)
	o.final = Big.of(o.price).mul(1.0 - o.disc)
	o.bought = shop_state.bought.has(o.i)
	return o


func buy_offer(o: Dictionary) -> Dictionary:
	if o.bought or o.get("blocked", false):
		return {}
	var res := {"ok": true}
	match o.kind:
		"boost_income":
			if not pay(o.cur, o.final):
				return {}
			add_boost("income", 600.0)
		"boost_stamina":
			if not pay(o.cur, o.final):
				return {}
			add_boost("stamina", 120.0)
		"boost_turbo":
			if not pay(o.cur, o.final):
				return {}
			if d_turbo_on:
				guaranteed_turbo = true
				turbo_cd = 0.0
			else:
				start_turbo(TURBO_TIME)
		"upgrade":
			var cap := upgrade_cap(o.target)
			if cap >= 0 and upg[o.target] + 10 > cap:
				return {}
			if not pay(o.cur, o.final):
				return {}
			upg[o.target] += 10
			mark_dirty()
		"part":
			if not buy_mark(o.target, o.mk, o.disc):
				return {}
		"case":
			for c in D.CASES:
				if c.id == o.target:
					res = open_case(c, o.disc)
					if res.is_empty():
						return {}
	shop_state.bought.append(o.i)
	changed.emit()
	return res


# =====================================================================
# Перерождение
# =====================================================================

func rebirth_req() -> Big:
	return Big.power(10.0, rebirths).mul(2.0e5)


func can_rebirth() -> bool:
	return run_earned.gte(rebirth_req())


func rebirth_rewards(r: int) -> Dictionary:
	# награды за переход на перерождение r
	var res := {}
	if r >= 1:
		res["gold"] = 1 + r / 2
	if r >= 5:
		res["diamond"] = 1 + r / 10
	if r >= 15 and r % 5 == 0:
		res["emerald"] = 1 + r / 50
	if r >= 50 and r % 10 == 0:
		res["sapphire"] = 1 + r / 200
	if r >= 250 and r % 50 == 0:
		res["quantum"] = 1
	return res


func next_currency_info() -> Dictionary:
	for id in D.CURRENCY_ORDER:
		var need: int = D.CURRENCIES[id].rebirth
		if need > 0 and not unlocked_cur.get(id, false):
			return {"id": id, "at": need, "in": maxi(0, need - rebirths)}
	return {}


func do_rebirth() -> bool:
	if not can_rebirth():
		return false
	rebirths += 1
	stats.rebirths_total += 1
	for id in D.CURRENCY_ORDER:
		var need: int = D.CURRENCIES[id].rebirth
		if need > 0 and rebirths >= need:
			unlocked_cur[id] = true
	var rw := rebirth_rewards(rebirths)
	for id in rw:
		cur[id] = cur[id].add(Big.of(rw[id]))
	_soft_reset()
	toast.emit("Перерождение %d! Множитель x%s" % [rebirths, Big.power(1.25, rebirths).fmt(settings.sci)], Color("ffa31a"))
	rebirth_done.emit()
	save_game()
	return true


func _soft_reset() -> void:
	cur.cash = Big.zero()
	for u in D.UPGRADES:
		upg[u.id] = 0
	for sid in parts:
		var p: Dictionary = parts[sid]
		var keep: Array = []
		for it in p.owned:
			if it.src != "cash":
				keep.append(it)
		p.owned = keep
		p.eq = -1
		var best_v := -1.0
		for i in keep.size():
			var v := part_power(sid, int(keep[i].mk), int(keep[i].rar))
			if v > best_v:
				best_v = v
				p.eq = i
	run_earned = Big.zero()
	is_exhausted = false
	turbo_time = 0.0
	turbo_cd = 0.0
	mark_dirty()
	recalc()
	stamina = d_stamina_max
	changed.emit()


func ultra_req() -> int:
	return 1000 + 500 * ultra


func can_ultra() -> bool:
	return rebirths >= ultra_req()


func do_ultra() -> bool:
	if not can_ultra():
		return false
	ultra += 1
	stats.ultras += 1
	unlocked_cur["core"] = true
	cur.core = cur.core.add(Big.of(1 + ultra))
	rebirths = 10 * uskill.get("u_start", 0)
	_soft_reset()
	toast.emit("УЛЬТРА-ПЕРЕРОЖДЕНИЕ %d! x100 ко всему доходу" % ultra, Color("ff5ad1"))
	rebirth_done.emit()
	save_game()
	return true


func perm_cost(table: Array, id: String, store: Dictionary) -> Big:
	for t in table:
		if t.id == id:
			return Big.power(t.growth, store.get(id, 0)).mul(t.base)
	return Big.zero()


func buy_perm(table: Array, id: String, store: Dictionary, currency: String) -> bool:
	for t in table:
		if t.id == id:
			if t.has("max") and store.get(id, 0) >= t.max:
				return false
			if not pay(currency, perm_cost(table, id, store)):
				return false
			store[id] = store.get(id, 0) + 1
			mark_dirty()
			changed.emit()
			return true
	return false


# =====================================================================
# Достижения (генерируются бесконечно)
# =====================================================================

const ACH_CATS := ["earn", "presses", "rebirths", "level", "cases", "turbos", "crits"]


func ach_threshold(cat: String, n: int) -> float:
	match cat:
		"earn":
			var exps := [3, 6, 9, 12, 15, 20, 25, 30, 40, 50, 60]
			if n < exps.size():
				return float(exps[n])
			return floor(60.0 * pow(1.5, n - exps.size() + 1))
		"presses":
			return 10.0 * pow(10.0, n)
		"rebirths":
			var r := [1, 5, 10, 25, 50, 100, 250, 500, 1000]
			return float(r[n]) if n < r.size() else 1000.0 * pow(2.0, n - r.size() + 1)
		"level":
			return 10.0 * (n + 1)
		"cases":
			var c := [1, 10, 50, 100, 500]
			return float(c[n]) if n < c.size() else 500.0 * pow(5.0, n - c.size() + 1)
		"turbos", "crits":
			return pow(10.0, n)
	return INF


func ach_value(cat: String) -> float:
	match cat:
		"earn":
			return total_earned.log10()
		"presses":
			return float(stats.presses)
		"rebirths":
			return float(stats.rebirths_total)
		"level":
			return float(level)
		"cases":
			return float(stats.cases)
		"turbos":
			return float(stats.turbos)
		"crits":
			return float(stats.crits)
	return 0.0


func ach_title(cat: String, n: int) -> String:
	var t := ach_threshold(cat, n)
	match cat:
		"earn":
			return "Заработай 1e%d" % int(t)
		"presses":
			return "Нажми двигатель: %s" % Big.of(t).fmt(settings.sci)
		"rebirths":
			return "Переродись: %d" % int(t)
		"level":
			return "Достигни %d уровня" % int(t)
		"cases":
			return "Открой кейсы: %d" % int(t)
		"turbos":
			return "Включи турбо: %s" % Big.of(t).fmt(settings.sci)
		"crits":
			return "Поймай криты: %s" % Big.of(t).fmt(settings.sci)
	return ""


func achievements_count() -> int:
	var n := 0
	for k in ach:
		n += int(ach[k])
	return n


func _check_achievements() -> void:
	for cat in ACH_CATS:
		var n: int = ach.get(cat, 0)
		var guard := 0
		while ach_value(cat) >= ach_threshold(cat, n) and guard < 20:
			guard += 1
			ach[cat] = n + 1
			var title := ach_title(cat, n)
			n += 1
			var reward := ""
			if unlocked_cur.get("emerald", false):
				cur.emerald = cur.emerald.add(Big.of(1.0))
				reward = "+1 изумруд"
			elif unlocked_cur.get("gold", false):
				cur.gold = cur.gold.add(Big.of(1.0))
				reward = "+1 золото"
			else:
				var c := d_hold.mul(120.0)
				add_income(c)
				reward = "+%s кэша" % fmt(c)
			toast.emit("Достижение: %s (%s)" % [title, reward], Color("ffd27f"))
			mark_dirty()


# =====================================================================
# Ежедневные задания
# =====================================================================

func _today() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]


func _refresh_daily() -> void:
	var t := _today()
	if daily.day == t:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(t)
	var pool := [
		{"type": "hold", "goal": float(rng.randi_range(4, 10) * 30), "text": "Держи двигатель %d с"},
		{"type": "upgrades", "goal": float(rng.randi_range(5, 20) * 5), "text": "Купи %d уровней улучшений"},
		{"type": "cases", "goal": float(rng.randi_range(1, 3)), "text": "Открой %d кейса"},
		{"type": "turbo", "goal": float(rng.randi_range(3, 10)), "text": "Включи турбо %d раз"},
	]
	var tasks: Array = []
	var idx := [0, 1, 2, 3]
	for i in range(idx.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = idx[i]
		idx[i] = idx[j]
		idx[j] = tmp
	for k in 3:
		var p: Dictionary = pool[idx[k]]
		tasks.append({"type": p.type, "goal": p.goal, "text": p.text % int(p.goal),
			"progress": 0.0, "claimed": false, "reward": ["gold", "diamond", "emerald"][k]})
	daily = {"day": t, "tasks": tasks}


func _daily_progress(type: String, amount: float) -> void:
	if type == "earn":
		return
	for t in daily.tasks:
		if t.type == type and not t.claimed:
			t.progress = minf(t.goal, t.progress + amount)


func daily_tasks() -> Array:
	_refresh_daily()
	return daily.tasks


func claim_daily(i: int) -> String:
	var t: Dictionary = daily.tasks[i]
	if t.claimed or t.progress < t.goal:
		return ""
	t.claimed = true
	var id: String = t.reward
	# если редкая валюта ещё не открыта — даём следующую доступную
	while not unlocked_cur.get(id, false) and id != "cash":
		id = {"emerald": "diamond", "diamond": "gold", "gold": "cash"}[id]
	var txt := ""
	if id == "cash":
		var c := d_hold.mul(300.0)
		add_income(c)
		txt = "+%s кэша" % fmt(c)
	else:
		var n: int = {"gold": 5, "diamond": 3, "emerald": 1}[id]
		add_cur(id, Big.of(n))
		txt = "+%d %s" % [n, D.CURRENCIES[id].name]
	changed.emit()
	return txt


# =====================================================================
# Настройки
# =====================================================================

func apply_preset(q: int) -> void:
	settings.quality = clampi(q, 0, 3)
	for k in PRESETS[settings.quality]:
		settings[k] = PRESETS[settings.quality][k]
	apply_settings()


func apply_settings() -> void:
	Engine.max_fps = int(settings.fps)
	if has_node("/root/Sfx"):
		get_node("/root/Sfx").apply_volumes()
	settings_changed.emit()


# =====================================================================
# Сохранение
# =====================================================================

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT \
			or what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		save_game()


func to_dict() -> Dictionary:
	var c := {}
	for id in cur:
		c[id] = cur[id].to_arr()
	return {
		"version": SAVE_VERSION, "cur": c, "unlocked_cur": unlocked_cur, "upg": upg, "parts": parts,
		"rebirths": rebirths, "ultra": ultra, "sapph": sapph, "quant": quant, "uskill": uskill,
		"level": level, "xp": xp.to_arr(), "run_earned": run_earned.to_arr(),
		"total_earned": total_earned.to_arr(), "stats": stats, "ach": ach, "boosts": boosts,
		"shop": shop_state, "daily": daily, "engine": engine_choice, "settings": settings,
		"last_time": Time.get_unix_time_from_system(),
	}


func from_dict(d: Dictionary) -> void:
	_reset_all()
	var c: Dictionary = d.get("cur", {})
	for id in c:
		if cur.has(id):
			cur[id] = Big.of(c[id])
	unlocked_cur = d.get("unlocked_cur", unlocked_cur)
	var u: Dictionary = d.get("upg", {})
	for id in u:
		if upg.has(id):
			upg[id] = int(u[id])
	var p: Dictionary = d.get("parts", {})
	for sid in p:
		if parts.has(sid):
			var owned: Array = []
			for it in p[sid].get("owned", []):
				owned.append({"mk": int(it.mk), "rar": int(it.rar), "src": str(it.src)})
			parts[sid] = {"owned": owned, "eq": int(p[sid].get("eq", -1))}
	rebirths = int(d.get("rebirths", 0))
	ultra = int(d.get("ultra", 0))
	for pair in [["sapph", sapph], ["quant", quant], ["uskill", uskill], ["ach", ach]]:
		var src: Dictionary = d.get(pair[0], {})
		for k in src:
			pair[1][k] = int(src[k])
	level = maxi(1, int(d.get("level", 1)))
	xp = Big.of(d.get("xp", [0, 0]))
	run_earned = Big.of(d.get("run_earned", [0, 0]))
	total_earned = Big.of(d.get("total_earned", [0, 0]))
	var st: Dictionary = d.get("stats", {})
	for k in st:
		stats[k] = st[k]
	for k in ["presses", "turbos", "crits", "parts", "cases", "ultras", "rebirths_total"]:
		stats[k] = int(stats[k])
	boosts = d.get("boosts", [])
	shop_state = d.get("shop", shop_state)
	shop_state.hour = int(shop_state.get("hour", -1))
	var bought: Array = []
	for b in shop_state.get("bought", []):
		bought.append(int(b))
	shop_state.bought = bought
	daily = d.get("daily", daily)
	engine_choice = str(d.get("engine", ""))
	var s: Dictionary = d.get("settings", {})
	for k in s:
		settings[k] = s[k]
	for k in ["quality", "fps", "shadows", "msaa", "particles"]:
		settings[k] = int(settings[k])
	last_time = float(d.get("last_time", 0.0))
	mark_dirty()
	recalc()
	stamina = d_stamina_max
	_compute_offline()


func _compute_offline() -> void:
	offline_report = null
	if last_time <= 0.0 or d_offline_hours <= 0.0:
		return
	var elapsed := Time.get_unix_time_from_system() - last_time
	if elapsed < 60.0:
		return
	offline_seconds = minf(elapsed, d_offline_hours * 3600.0)
	var gain := d_passive.mul(d_offline_pct * offline_seconds)
	add_income(gain)
	offline_report = gain


func save_game() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(to_dict()))
	f.close()


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if data is Dictionary:
		from_dict(data)


func export_save() -> String:
	return Marshalls.utf8_to_base64(JSON.stringify(to_dict()))


func import_save(text: String) -> bool:
	var raw := Marshalls.base64_to_utf8(text.strip_edges())
	var data = JSON.parse_string(raw)
	if not (data is Dictionary) or not data.has("version"):
		return false
	from_dict(data)
	save_game()
	changed.emit()
	return true


func reset_progress() -> void:
	var keep := settings.duplicate()
	_reset_all()
	settings = keep
	mark_dirty()
	recalc()
	save_game()
	changed.emit()


func current_engine() -> String:
	var avail := D.unlocked_engines(level)
	if engine_choice != "" and avail.has(engine_choice):
		return engine_choice
	return avail[avail.size() - 1]
