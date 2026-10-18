extends Node
## Звук. Если в res://assets/sounds/ лежит файл с таким же именем (.ogg) — берётся он,
## иначе звук синтезируется кодом. Звук мотора — бесшовная петля, высота тона от оборотов.

const MIX_RATE := 22050.0
const SOUND_NAMES := ["starter", "knock", "crit", "coin", "turbo", "case_shake", "case_open",
	"fanfare", "click", "buy", "garage_door", "rebirth"]

# параметры мотора, их выставляет EngineView каждый кадр
var rpm: float = 0.0
var max_rpm: float = 7000.0
var cylinders: int = 4
var pitch: float = 1.0
var diesel: bool = false
var engine_on: bool = false
var turbo_level: float = 0.0
var engine_type: String = ""

var _gen_player: AudioStreamPlayer
var _pb: AudioStreamGeneratorPlayback
var _file_player: AudioStreamPlayer
var _file_type: String = ""
var _music: AudioStreamPlayer
var _pool: Array[AudioStreamPlayer] = []
var _sounds: Dictionary = {}

var _phase: float = 0.0
var _t_since: float = 1.0
var _amp: float = 1.0
var _body: float = 0.0
var _whistle: float = 0.0
var _lp: float = 0.0
var _pop_left: int = 0
var _vol: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_make_bus("SFX")
	_make_bus("Music")
	_gen_player = AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.12
	_gen_player.stream = gen
	_gen_player.bus = "SFX"
	add_child(_gen_player)
	_gen_player.play()
	_pb = _gen_player.get_stream_playback()

	_file_player = AudioStreamPlayer.new()
	_file_player.bus = "SFX"
	add_child(_file_player)

	for i in 8:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)

	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	var mpath := "res://assets/sounds/music.ogg"
	if ResourceLoader.exists(mpath):
		var ms = load(mpath)
		if ms is AudioStreamOggVorbis:
			ms.loop = true
		_music.stream = ms
		_music.play()

	for n in SOUND_NAMES:
		_sounds[n] = _load_or_synth(n)
	apply_volumes()


func _make_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")


func apply_volumes() -> void:
	if AudioServer.get_bus_index("SFX") == -1 or AudioServer.get_bus_index("Music") == -1:
		return
	var s: float = G.settings.sfx
	var m: float = G.settings.music
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(maxf(s, 0.0001)))
	AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), s <= 0.001)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(maxf(m, 0.0001)))
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), m <= 0.001)


func play(sound_name: String, pitch_scale: float = 1.0, volume_db: float = 0.0) -> void:
	var st = _sounds.get(sound_name)
	if st == null:
		return
	for p in _pool:
		if not p.playing:
			p.stream = st
			p.pitch_scale = pitch_scale
			p.volume_db = volume_db
			p.play()
			return
	_pool[0].stream = st
	_pool[0].play()


## Хлопок в выхлопе.
func pop() -> void:
	_pop_left = int(MIX_RATE * 0.05)


func _process(_delta: float) -> void:
	var type_file := "res://assets/sounds/engine_%s.ogg" % engine_type
	var generic := "res://assets/sounds/engine.ogg"
	var want_file := ""
	if ResourceLoader.exists(type_file):
		want_file = type_file
	elif ResourceLoader.exists(generic):
		want_file = generic
	if want_file != "":
		if _file_type != want_file:
			_file_type = want_file
			var st = load(want_file)
			if st is AudioStreamOggVorbis:
				st.loop = true
			_file_player.stream = st
		if engine_on and not _file_player.playing:
			_file_player.play()
		elif not engine_on and _file_player.playing:
			_file_player.stop()
		_file_player.pitch_scale = clampf(0.5 + 1.5 * rpm / maxf(max_rpm, 1.0), 0.3, 3.0)
		_fill(true)
	else:
		_fill(false)


func _fill(silent_engine: bool) -> void:
	if _pb == null:
		return
	var frames := _pb.get_frames_available()
	if frames <= 0:
		return
	var fire_freq := rpm / 60.0 * maxf(1.0, cylinders) / 2.0
	if engine_type == "rotary":
		fire_freq = rpm / 60.0 * 2.0
	var body_freq := (70.0 + rpm / 45.0) * pitch
	var decay := 30.0 + rpm / 60.0
	var target_vol := 0.0 if (silent_engine or not engine_on) else 0.55
	var whistle_freq := 1800.0 + rpm * 0.35
	var dt := 1.0 / MIX_RATE
	var noise_amt := 0.9 if diesel else 0.55
	for i in frames:
		_vol += (target_vol - _vol) * 0.0005
		_phase += fire_freq * dt
		if _phase >= 1.0:
			_phase -= 1.0
			_t_since = 0.0
			_amp = randf_range(0.75, 1.0)
		_t_since += dt
		_body = fmod(_body + body_freq * dt, 1.0)
		var env := exp(-_t_since * decay) * _amp
		var n := randf() * 2.0 - 1.0
		var s := env * (noise_amt * n + 0.8 * sin(TAU * _body))
		s += 0.18 * sin(TAU * _phase) # низкий гул
		s *= _vol
		if turbo_level > 0.01:
			_whistle = fmod(_whistle + whistle_freq * dt, 1.0)
			s += turbo_level * 0.06 * sin(TAU * _whistle)
		if _pop_left > 0:
			_pop_left -= 1
			s += (randf() * 2.0 - 1.0) * 0.6 * (_pop_left / (MIX_RATE * 0.05))
		_lp += (s - _lp) * 0.35
		var v := clampf(_lp, -1.0, 1.0)
		_pb.push_frame(Vector2(v, v))


# ---------------------------------------------------------------------
# Синтез коротких звуков
# ---------------------------------------------------------------------

func _load_or_synth(sound_name: String) -> AudioStream:
	var path := "res://assets/sounds/%s.ogg" % sound_name
	if ResourceLoader.exists(path):
		return load(path)
	var buf := PackedFloat32Array()
	match sound_name:
		"starter":
			buf = _synth_starter()
		"knock":
			buf = _synth_knock()
		"crit":
			buf = _tones([[1320.0, 0.0, 0.35], [1760.0, 0.07, 0.4], [2640.0, 0.14, 0.3]], 0.6)
		"coin":
			buf = _tones([[1500.0, 0.0, 0.15], [2250.0, 0.05, 0.15]], 0.25)
		"turbo":
			buf = _synth_sweep(400.0, 3200.0, 0.7, 0.5)
		"case_shake":
			buf = _synth_rattle(0.9)
		"case_open":
			buf = _tones([[523.0, 0.0, 0.2], [659.0, 0.08, 0.2], [784.0, 0.16, 0.25], [1046.0, 0.24, 0.5]], 0.8)
		"fanfare":
			buf = _tones([[392.0, 0.0, 0.2], [523.0, 0.18, 0.2], [659.0, 0.36, 0.2], [784.0, 0.54, 0.6],
				[659.0, 0.9, 0.15], [784.0, 1.05, 0.9]], 2.0, true)
		"click":
			buf = _tones([[2000.0, 0.0, 0.03]], 0.05)
		"buy":
			buf = _tones([[880.0, 0.0, 0.08], [1320.0, 0.06, 0.12]], 0.2)
		"garage_door":
			buf = _synth_rumble(1.1)
		"rebirth":
			buf = _synth_sweep(200.0, 1600.0, 1.2, 0.4)
	return _to_wav(buf)


func _to_wav(buf: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = int(MIX_RATE)
	w.stereo = false
	w.data = data
	return w


func _tones(notes: Array, length: float, square: bool = false) -> PackedFloat32Array:
	var n := int(length * MIX_RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for note in notes:
		var f: float = note[0]
		var start := int(note[1] * MIX_RATE)
		var dur := int(note[2] * MIX_RATE)
		for i in dur:
			var k := start + i
			if k >= n:
				break
			var t := float(i) / MIX_RATE
			var env := minf(1.0, t * 200.0) * exp(-t * 6.0 / maxf(note[2], 0.05))
			var w := sin(TAU * f * t)
			if square:
				w = 0.6 * signf(w) * 0.5 + 0.5 * w
			buf[k] += 0.35 * env * w
	return buf


func _synth_starter() -> PackedFloat32Array:
	var n := int(1.4 * MIX_RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var crank := 0.5 + 0.5 * sin(TAU * 5.0 * t) # «чих-чих»
		var whine := sin(TAU * (110.0 + 20.0 * sin(TAU * 5.0 * t)) * t)
		var noise := randf() * 2.0 - 1.0
		lp += (noise - lp) * 0.2
		var env := minf(1.0, t * 10.0) * (1.0 if t < 1.1 else maxf(0.0, 1.0 - (t - 1.1) * 4.0))
		buf[i] = env * (0.45 * pow(crank, 4.0) * lp * 2.0 + 0.2 * whine * crank)
	return buf


func _synth_knock() -> PackedFloat32Array:
	var n := int(0.7 * MIX_RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for hit in 3:
		var start := int(hit * 0.18 * MIX_RATE)
		for i in int(0.15 * MIX_RATE):
			var k := start + i
			if k >= n:
				break
			var t := float(i) / MIX_RATE
			var env := exp(-t * 35.0)
			buf[k] += env * (0.35 * sin(TAU * 900.0 * t) + 0.25 * sin(TAU * 1370.0 * t) + 0.4 * sin(TAU * 80.0 * t))
	return buf


func _synth_sweep(f0: float, f1: float, length: float, vol: float) -> PackedFloat32Array:
	var n := int(length * MIX_RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / n
		var f := lerpf(f0, f1, t * t)
		ph = fmod(ph + f / MIX_RATE, 1.0)
		var env := sin(PI * t)
		buf[i] = vol * env * (0.6 * sin(TAU * ph) + 0.25 * (randf() * 2.0 - 1.0) * t)
	return buf


func _synth_rattle(length: float) -> PackedFloat32Array:
	var n := int(length * MIX_RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var hits := pow(0.5 + 0.5 * sin(TAU * 14.0 * t), 8.0)
		buf[i] = 0.5 * hits * (randf() * 2.0 - 1.0) * minf(1.0, (length - t) * 5.0)
	return buf


func _synth_rumble(length: float) -> PackedFloat32Array:
	var n := int(length * MIX_RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		lp += ((randf() * 2.0 - 1.0) - lp) * 0.03
		var env := minf(1.0, t * 8.0) * minf(1.0, (length - t) * 3.0)
		buf[i] = env * (lp * 2.5 + 0.15 * sin(TAU * 55.0 * t))
	return buf
