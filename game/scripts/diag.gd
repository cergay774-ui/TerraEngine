extends Node
## Диагностика зависаний. Раз в секунду пишет в user://diag.log FPS, самый долгий кадр,
## память, число отрисовок и состояние игры, плюс события (уровень, сборка мотора, меню…).
## Сторожевой поток замечает, если главный цикл встал больше чем на 3 с, и записывает,
## на каком этапе кадра это случилось: в логике игры (process) или в отрисовке (draw).
## При следующем запуске прошлый журнал лежит в user://diag_prev.log — его можно скопировать
## в настройках («Данные» → «Отчёт о прошлой сессии»).

const LOG_PATH := "user://diag.log"
const PREV_PATH := "user://diag_prev.log"
const MAX_LINES := 1500

var _file: FileAccess
var _header: String = ""
var _lines: int = 0
var _t0: int = 0
var _sec_acc: float = 0.0
var _frame_max_ms: float = 0.0
var _last_frame_us: int = 0
var _frames: int = 0

# общее с потоком-сторожем
var _mutex := Mutex.new()
var _beat_us: int = 0
var _phase: String = "start"
var _last_event: String = ""
var _stall_logged: bool = false
var _thread: Thread
var _running: bool = true
var _suspended: bool = false      # приложение свёрнуто — цикл стоит законно
var _armed: bool = false          # до входа в игру не следим: первая компиляция шейдеров на загрузке — не зависание

## Прошлый запуск зависал (в его журнале есть STALL) — игра сама снизит графику.
var prev_stalled: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -1000  # раньше всех: отмечаем начало кадра
	_t0 = Time.get_ticks_msec()
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists("diag.log"):
		var pf := FileAccess.open(LOG_PATH, FileAccess.READ)
		if pf != null:
			prev_stalled = pf.get_as_text().contains(" STALL ")
			pf.close()
		dir.remove("diag_prev.log")
		dir.rename("diag.log", "diag_prev.log")
	_file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	var dt := Time.get_datetime_dict_from_system()
	_header = "=== сессия %04d-%02d-%02d %02d:%02d:%02d | %s | %s | %s | %s | Godot %s" % [
		dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second, OS.get_model_name(), OS.get_name(),
		RenderingServer.get_video_adapter_name() + " / " + RenderingServer.get_video_adapter_vendor(),
		RenderingServer.get_current_rendering_method(), Engine.get_version_info().string]
	_write(_header)
	RenderingServer.frame_pre_draw.connect(func(): _set_phase("draw"))
	RenderingServer.frame_post_draw.connect(func(): _set_phase("idle"))
	_beat_us = Time.get_ticks_usec()
	_thread = Thread.new()
	_thread.start(_watchdog)


func _exit_tree() -> void:
	_running = false
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			if not _suspended:
				_mutex.lock()
				_suspended = true
				_mutex.unlock()
				event("свёрнуто")
		NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN:
			if _suspended:
				_mutex.lock()
				_suspended = false
				_beat_us = Time.get_ticks_usec()
				_mutex.unlock()
				event("развёрнуто")


func _set_phase(p: String) -> void:
	_mutex.lock()
	_phase = p
	_beat_us = Time.get_ticks_usec()
	_mutex.unlock()


## Начать следить за зависаниями (вызывается, когда игра загрузилась).
func arm() -> void:
	_mutex.lock()
	_armed = true
	_beat_us = Time.get_ticks_usec()
	_mutex.unlock()
	event("сторож включён")


## Отметить событие (уровень, сборка мотора, открытие меню…).
func event(text: String) -> void:
	_mutex.lock()
	_last_event = text
	_mutex.unlock()
	_write("%7.1f EVENT %s" % [_now(), text])


func _now() -> float:
	return (Time.get_ticks_msec() - _t0) / 1000.0


func _write(line: String) -> void:
	if _file == null:
		return
	_mutex.lock()
	_file.store_line(line)
	_file.flush()
	_lines += 1
	if _lines > MAX_LINES:
		# журнал не разрастается: начинаем заново, сохранив хвост
		_file.close()
		var f := FileAccess.open(LOG_PATH, FileAccess.READ)
		var tail := PackedStringArray()
		if f != null:
			var all := f.get_as_text().split("\n")
			tail = all.slice(maxi(0, all.size() - 300))
			f.close()
		_file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
		if _file == null:
			_mutex.unlock()
			return
		_file.store_line(_header)
		for l in tail:
			_file.store_line(l)
		_lines = tail.size() + 1
	_mutex.unlock()


func _process(delta: float) -> void:
	_set_phase("process")
	var now := Time.get_ticks_usec()
	if _last_frame_us > 0:
		_frame_max_ms = maxf(_frame_max_ms, (now - _last_frame_us) / 1000.0)
	_last_frame_us = now
	_frames += 1
	_sec_acc += delta
	if _sec_acc < 1.0:
		return
	_sec_acc = 0.0
	var P := Performance
	var g := get_node_or_null("/root/G")
	var state := ""
	if g != null:
		state = "lvl=%d hold=%s thr=%s exh=%s q=%d" % [g.level, str(g.holding), str(g.throttle), str(g.is_exhausted), int(g.settings.get("quality", -1))]
	_write("%7.1f fps=%d frames=%d max_ms=%d proc_ms=%.1f draws=%d objs=%d nodes=%d mem=%.0fMB vmem=%.0fMB %s" % [
		_now(), Engine.get_frames_per_second(), _frames, int(_frame_max_ms),
		P.get_monitor(P.TIME_PROCESS) * 1000.0, P.get_monitor(P.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		P.get_monitor(P.RENDER_TOTAL_OBJECTS_IN_FRAME), P.get_monitor(P.OBJECT_NODE_COUNT),
		P.get_monitor(P.MEMORY_STATIC) / 1e6, P.get_monitor(P.RENDER_VIDEO_MEM_USED) / 1e6, state])
	_frame_max_ms = 0.0
	_frames = 0
	_stall_logged = false


func _watchdog() -> void:
	while _running:
		OS.delay_msec(500)
		_mutex.lock()
		var since := (Time.get_ticks_usec() - _beat_us) / 1000000.0
		var phase := _phase
		var ev := _last_event
		var logged := _stall_logged
		var suspended := _suspended
		var armed := _armed
		_mutex.unlock()
		if since > 3.0 and not logged and not suspended and armed:
			_mutex.lock()
			_stall_logged = true
			_mutex.unlock()
			_write("%7.1f STALL главный цикл стоит %.1f с, этап=%s, последнее событие=%s" % [_now(), since, phase, ev])


## Текст журнала прошлой сессии (для отправки разработчику).
func previous_report() -> String:
	if not FileAccess.file_exists(PREV_PATH):
		return ""
	var f := FileAccess.open(PREV_PATH, FileAccess.READ)
	if f == null:
		return ""
	var lines := f.get_as_text().split("\n")
	f.close()
	var tail := lines.slice(maxi(0, lines.size() - 220))
	# строка с моделью телефона и видеокартой нужна всегда
	if lines.size() > 220 and lines[0].begins_with("==="):
		tail.insert(0, lines[0])
	return "\n".join(tail)
