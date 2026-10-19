extends Node
## Все таблицы игры: улучшения, запчасти, валюты, моторы, материалы, эпохи, кейсы.
## Новые детали/моторы добавляются здесь без правки остального кода.

const CURRENCIES := {
	"cash": {"name": "Кэш", "short": "$", "color": Color("8fe36b"), "rebirth": 0},
	"gold": {"name": "Золото", "short": "Au", "color": Color("ffcc33"), "rebirth": 1},
	"diamond": {"name": "Алмазы", "short": "◆", "color": Color("7fe7ff"), "rebirth": 5},
	"emerald": {"name": "Изумруды", "short": "✦", "color": Color("38e08c"), "rebirth": 15},
	"sapphire": {"name": "Сапфиры", "short": "S", "color": Color("4f7bff"), "rebirth": 50},
	"quantum": {"name": "Квант", "short": "Q", "color": Color("d07bff"), "rebirth": 250},
	"core": {"name": "Ультра-ядра", "short": "U", "color": Color("ff5ad1"), "rebirth": -1},
}
const CURRENCY_ORDER := ["cash", "gold", "diamond", "emerald", "sapphire", "quantum", "core"]

# unlock: {"upg": id, "lvl": n} | {"rebirth": n} | {}
const UPGRADES := [
	{"id": "press", "name": "Сила нажатия", "desc": "Доход при зажатии",
		"cur": "cash", "base": 10.0, "growth": 1.15, "max": 1000, "ultra_cap": true, "unlock": {}},
	{"id": "stamina", "name": "Стамина двигателя", "desc": "Сколько можно держать зажатым",
		"cur": "cash", "base": 25.0, "growth": 1.15, "max": 1000, "ultra_cap": true, "unlock": {}},
	{"id": "passive", "name": "Пассивный доход", "desc": "Доход без зажатия",
		"cur": "cash", "base": 300.0, "growth": 1.15, "max": 180, "unlock": {"upg": "press", "lvl": 25}},
	{"id": "turbo", "name": "Турботюнинг", "desc": "Шанс включить x2 на 4 с при зажатии",
		"cur": "cash", "base": 5000.0, "growth": 1.15, "max": 501, "unlock": {"upg": "press", "lvl": 50}},
	{"id": "cooling", "name": "Охлаждение", "desc": "Скорость восстановления стамины",
		"cur": "cash", "base": 1.0e6, "growth": 1.15, "max": -1, "unlock": {"upg": "press", "lvl": 100}},
	{"id": "crit", "name": "Критический газ", "desc": "Шанс мгновенно получить доход x10",
		"cur": "gold", "base": 2.0, "growth": 1.08, "max": -1, "unlock": {"rebirth": 1}},
	{"id": "autogas", "name": "Автогаз", "desc": "Мотор сам газует на 1 с, тратя стамину",
		"cur": "diamond", "base": 2.0, "growth": 1.08, "max": 281, "unlock": {"rebirth": 5}},
	{"id": "offline", "name": "Офлайн-гараж", "desc": "Доход, пока игра закрыта",
		"cur": "emerald", "base": 1.0, "growth": 1.08, "max": 1381, "unlock": {"rebirth": 15}},
]

const RARITIES := [
	{"name": "Обычная", "mult": 1.0, "color": Color("c8c8c8")},
	{"name": "Редкая", "mult": 1.5, "color": Color("4da3ff")},
	{"name": "Эпическая", "mult": 2.5, "color": Color("b05cff")},
	{"name": "Легендарная", "mult": 4.0, "color": Color("ffa31a")},
	{"name": "Мифическая", "mult": 7.0, "color": Color("ff3d5a")},
]

# unlock для Mk I: {"cash": x} | {"upg": id, "lvl": n} | {"gold": x} | {"level": n, "cash": x} | {"ultra": 1}
const SLOTS := [
	{"id": "block", "name": "Блок цилиндров", "bonus": "Общий множитель дохода", "base": 0.5,
		"unlock": {"cash": 50.0}},
	{"id": "pistons", "name": "Поршни", "bonus": "Доход при зажатии", "base": 0.5,
		"unlock": {"upg": "press", "lvl": 10}},
	{"id": "crank", "name": "Коленвал", "bonus": "Доход, меньше тряски", "base": 0.3,
		"unlock": {"cash": 1000.0}},
	{"id": "head", "name": "ГБЦ и клапаны", "bonus": "Максимальные обороты", "base": 0.3,
		"unlock": {"upg": "press", "lvl": 40}},
	{"id": "ignition", "name": "Зажигание", "bonus": "Шанс турботюнинга", "base": 1.0,
		"unlock": {"cash": 2.0e4}},
	{"id": "fuel", "name": "Топливная система", "bonus": "Длительность стамины", "base": 0.25,
		"unlock": {"level": 11, "cash": 5.0e4}},
	{"id": "cooling", "name": "Охлаждение", "bonus": "Скорость восстановления стамины", "base": 0.25,
		"unlock": {"upg": "press", "lvl": 75}},
	{"id": "exhaust", "name": "Выхлоп", "bonus": "Пассивный доход", "base": 0.4,
		"unlock": {"cash": 2.0e5}},
	{"id": "turbine", "name": "Турбина", "bonus": "Сила турбо-бонуса", "base": 0.5,
		"unlock": {"level": 21, "cash": 1.0e6}},
	{"id": "flywheel", "name": "Маховик", "bonus": "Шанс и сила критического газа", "base": 0.5,
		"unlock": {"gold": 5.0}},
	{"id": "reactor", "name": "Реактор", "bonus": "Огромный множитель дохода", "base": 2.0,
		"unlock": {"ultra": 1}},
	{"id": "stabilizer", "name": "Стабилизатор", "bonus": "Стамина и меньше тряски", "base": 0.5,
		"unlock": {"ultra": 1}},
]

const MARK_ROMAN := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X",
	"XI", "XII", "XIII", "XIV", "XV", "XVI", "XVII", "XVIII", "XIX", "XX"]

# Мотор: layout описывает цилиндры, balance — сила тряски (1 = сильно), rpm — максимальные обороты.
const ENGINES := {
	"single": {"name": "Одноцилиндровый (мопед)", "view": "side", "cyl": 1, "balance": 1.0,
		"rpm": 6500, "idle": 1100, "pitch": 1.3, "diesel": false,
		"character": "Слабый, сильно трясётся, дешёвый"},
	"inline4": {"name": "Рядная четвёрка", "view": "side", "cyl": 4, "balance": 0.45,
		"rpm": 7000, "idle": 850, "pitch": 1.0, "diesel": false,
		"character": "Сбалансированный стартовый мотор"},
	"boxer": {"name": "Оппозитный (боксер)", "view": "front", "cyl": 4, "balance": 0.25,
		"rpm": 7200, "idle": 850, "pitch": 0.9, "diesel": false,
		"character": "Ровный, низкий центр тяжести"},
	"v6": {"name": "V6", "view": "front", "cyl": 6, "balance": 0.3,
		"rpm": 7000, "idle": 800, "pitch": 0.85, "diesel": false,
		"character": "Мощнее, компактный"},
	"v8": {"name": "V8", "view": "front", "cyl": 8, "balance": 0.25,
		"rpm": 6800, "idle": 700, "pitch": 0.7, "diesel": false,
		"character": "Много момента, басовитый звук"},
	"rotary": {"name": "Роторный (Ванкель)", "view": "rotary", "cyl": 2, "balance": 0.15,
		"rpm": 9000, "idle": 1000, "pitch": 1.4, "diesel": false,
		"character": "Высокие обороты, капризный нагрев"},
	"diesel": {"name": "Дизель", "view": "side", "cyl": 4, "balance": 0.6,
		"rpm": 4200, "idle": 650, "pitch": 0.6, "diesel": true,
		"character": "Огромный момент, низкие обороты"},
	"v12": {"name": "V12", "view": "front", "cyl": 12, "balance": 0.05,
		"rpm": 8500, "idle": 900, "pitch": 1.25, "diesel": false,
		"character": "Почти без тряски, очень дорогой"},
	"radial": {"name": "Звездообразный (авиационный)", "view": "radial", "cyl": 7, "balance": 0.35,
		"rpm": 3000, "idle": 600, "pitch": 0.75, "diesel": false,
		"character": "Эффектный, для поздней игры"},
	"experimental": {"name": "Экспериментальный", "view": "front", "cyl": 12, "balance": 0.1,
		"rpm": 12000, "idle": 1200, "pitch": 1.5, "diesel": false, "glow": true,
		"character": "Финальный контент"},
}

const MATERIALS := [
	{"name": "Чугун", "color": Color("4a4d52"), "shine": 0.05, "desc": "Дешёвый, тяжёлый, держит нагрев"},
	{"name": "Сталь", "color": Color("6f767e"), "shine": 0.2, "desc": "Прочнее, всё ещё тяжёлая"},
	{"name": "Алюминий", "color": Color("b4bcc4"), "shine": 0.35, "desc": "Лёгкий, хуже держит нагрев"},
	{"name": "Кованая сталь", "color": Color("5d6874"), "shine": 0.45, "desc": "Выдерживает турбину и высокие обороты"},
	{"name": "Титан", "color": Color("7d8aa8"), "shine": 0.55, "desc": "Лёгкий и прочный, дорогой"},
	{"name": "Титан+", "color": Color("8c9bd0"), "shine": 0.65, "desc": "Улучшенный титановый сплав"},
	{"name": "Карбон и керамика", "color": Color("2b2d33"), "shine": 0.4, "weave": true,
		"desc": "Минимальный вес, максимальные обороты"},
	{"name": "Карбон+", "color": Color("1f2a3a"), "shine": 0.6, "weave": true, "desc": "Гоночный карбон"},
	{"name": "Сверхсплавы", "color": Color("c9a96e"), "shine": 0.8, "desc": "Почти не греются"},
	{"name": "Сверхсплавы+", "color": Color("e6d3a0"), "shine": 1.0, "desc": "Для экспериментальных моторов"},
]

const EPOCHS := [
	{"engines": ["single"], "mult": 1.0, "mechanic": "Сборка, стенд, первые заказы"},
	{"engines": ["inline4"], "mult": 3.0, "mechanic": "Улучшения деталей, топливная система"},
	{"engines": ["boxer", "v6"], "mult": 8.0, "mechanic": "Турбина, нагрев становится важен"},
	{"engines": ["v8"], "mult": 20.0, "mechanic": "Тюнинг: зажигание и смесь ползунками"},
	{"engines": ["rotary"], "mult": 50.0, "mechanic": "Стресс-тест на поломку с наградами"},
	{"engines": ["diesel"], "mult": 120.0, "mechanic": "Крупные заказы (грузовики, лодки)"},
	{"engines": ["v12"], "mult": 300.0, "mechanic": "Второй стенд: два мотора приносят доход одновременно"},
	{"engines": ["v8"], "mult": 800.0, "racing": true, "mechanic": "Нитро и заезды на время"},
	{"engines": ["radial"], "mult": 2000.0, "mechanic": "Сборка на скорость (мини-игра)"},
	{"engines": ["experimental"], "mult": 6000.0, "mechanic": "Ультра-цели и квантовые модули"},
]

const CASES := [
	{"id": "garage", "name": "Гаражный", "cur": "cash", "price": 2000.0, "price_growth": 3.0,
		"odds": [75.0, 25.0, 0.0, 0.0, 0.0], "mark_bonus": [0, 0], "desc": "Обычные и редкие запчасти, немного кэша"},
	{"id": "gold", "name": "Золотой", "cur": "gold", "price": 3.0, "price_growth": 1.25,
		"odds": [0.0, 70.0, 30.0, 0.0, 0.0], "mark_bonus": [0, 1], "desc": "Редкие и эпические запчасти, бусты"},
	{"id": "diamond", "name": "Алмазный", "cur": "diamond", "price": 3.0, "price_growth": 1.2,
		"odds": [0.0, 0.0, 75.0, 25.0, 0.0], "mark_bonus": [1, 2], "desc": "Эпические и легендарные запчасти"},
	{"id": "emerald", "name": "Изумрудный", "cur": "emerald", "price": 2.0, "price_growth": 1.15,
		"odds": [0.0, 0.0, 0.0, 80.0, 20.0], "mark_bonus": [2, 4], "desc": "Легендарные и мифические запчасти, высокие марки"},
]

const SAPPHIRE_UPGRADES := [
	{"id": "s_income", "name": "Сапфировый множитель", "desc": "x1.5 к доходу за уровень", "base": 1.0, "growth": 1.6},
	{"id": "s_stamina", "name": "Сапфировая стамина", "desc": "+20% стамины за уровень", "base": 1.0, "growth": 1.5},
	{"id": "s_xp", "name": "Сапфировый опыт", "desc": "x2 к опыту за уровень", "base": 2.0, "growth": 1.7},
]

const QUANTUM_UPGRADES := [
	{"id": "q_auto", "name": "Автоперерождение", "desc": "Перерождается само, когда цель достигнута", "base": 1.0, "growth": 1.0, "max": 1},
	{"id": "q_time", "name": "Ускорение времени", "desc": "+25% к скорости дохода за уровень", "base": 1.0, "growth": 2.0},
	{"id": "q_mult", "name": "Квантовый множитель", "desc": "x10 к доходу за уровень", "base": 2.0, "growth": 3.0},
]

const ULTRA_SKILLS := [
	{"id": "u_income", "name": "Ультра-доход", "desc": "x3 к доходу за уровень", "base": 1.0, "growth": 2.0},
	{"id": "u_start", "name": "Быстрый старт", "desc": "+10 стартовых перерождений за уровень", "base": 1.0, "growth": 2.0},
	{"id": "u_stamina", "name": "Вечный двигатель", "desc": "+50% стамины и охлаждения за уровень", "base": 1.0, "growth": 2.0},
	{"id": "u_luck", "name": "Удача механика", "desc": "+5% к шансам турбо и крита за уровень", "base": 2.0, "growth": 2.5, "max": 5},
]

const TIPS := [
	"Алюминиевый блок легче чугунного, но хуже держит нагрев.",
	"Зажми двигатель — полный доход. Отпусти — капает пассивный.",
	"Стамина кончилась? Мотор сам сбросит газ, пока не остынет.",
	"Каждые 25 уровней силы нажатия доход удваивается.",
	"Турботюнинг бросает кубик раз в секунду, пока палец на моторе.",
	"V12 почти не трясётся, а одноцилиндровый — ещё как.",
	"Перерождение сбрасывает кэш, но множитель остаётся навсегда.",
	"Марки запчастей бесконечны: каждая следующая даёт x3 к бонусу.",
	"Порядок зажигания рядной четвёрки: 1-3-4-2.",
	"Дизелю не нужна искра — смесь вспыхивает от сжатия.",
	"Ежечасовой магазин обновляется каждый час — загляни за «горячим» предложением.",
	"Титан даёт синеватый отлив, а карбон — узор плетения.",
]


func upgrade(id: String) -> Dictionary:
	for u in UPGRADES:
		if u.id == id:
			return u
	return {}


func slot(id: String) -> Dictionary:
	for s in SLOTS:
		if s.id == id:
			return s
	return {}


func roman(mk: int) -> String:
	if mk >= 1 and mk <= MARK_ROMAN.size():
		return MARK_ROMAN[mk - 1]
	return str(mk)


func epoch_index(level: int) -> int:
	return max(0, (level - 1) / 10)


func epoch_info(level: int) -> Dictionary:
	var ei := epoch_index(level)
	var cycle := ei / EPOCHS.size()
	var ep: Dictionary = EPOCHS[ei % EPOCHS.size()]
	return {
		"index": ei,
		"cycle": cycle,
		"engines": ep.engines,
		"material": ei % MATERIALS.size(),
		"mult": ep.mult * pow(10.0, cycle * 4),
		"mechanic": ep.mechanic,
		"racing": ep.get("racing", false),
	}


func unlocked_engines(level: int) -> Array:
	var res: Array = []
	var ei := epoch_index(level)
	for i in mini(ei + 1, EPOCHS.size()):
		for en in EPOCHS[i].engines:
			if not res.has(en):
				res.append(en)
	return res


## Цвет металла марки: первые 20 — заданы вручную, дальше циклически с ростом свечения.
func mark_color(mk: int) -> Color:
	var palette := [Color("8a8f96"), Color("9aa3ad"), Color("b8c0c8"), Color("c9b48a"), Color("d8c27a"),
		Color("8fb3d9"), Color("7fd1c7"), Color("a7e08a"), Color("e0a36b"), Color("e07b6b"),
		Color("d46bb0"), Color("a07be0"), Color("6b8be0"), Color("6bd0e0"), Color("e0e06b"),
		Color("ffd27f"), Color("ff9f7f"), Color("ff7fbf"), Color("bf7fff"), Color("ffffff")]
	return palette[(maxi(mk, 1) - 1) % palette.size()]


func mark_glow(mk: int) -> float:
	return clampf((mk - 4) / 16.0, 0.0, 1.0)
