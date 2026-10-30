extends RefCounted
## Immutable PCM is published only after completion. No SceneTree or global RNG.
const SE_RATE := 32000
const MUSIC_RATE := 22050
const MUSIC_IDS := ["title", "region0", "region1", "region2", "boss"]
# duration, frequency, end-frequency ratio, voice, peak target
# voices: 0 bright blip, 1 air, 2 impact, 3 metal, 4 major phrase,
# 5 pulse zap, 6 buzzer, 7 rising charge, 8 fanfare, 9 descending phrase,
# 10 diminished escalation (enemy loop, distinct from major rewards).
const MUSIC_BPM := {"title": 128, "region0": 140, "region1": 132, "region2": 150, "boss": 172}
const MUSIC_BEATS := {"title": 64, "region0": 64, "region1": 64, "region2": 64, "boss": 80}
# 8A measured peak/RMS; normalization stays below these values (+1dB tolerance in tests).
const QUIET_LIMITS := {
	"enemy_shot": [-22.61, -32.11], "enemy_warn": [-24.01, -33.83],
	"enemy_warn_special": [-18.04, -26.08], "enemy_homing": [-16.96, -32.29],
	"enemy_absorb": [-15.37, -23.41], "enemy_switch": [-18.86, -26.88],
	"boss_shot": [-12.40, -25.56],
	"bomb_warn": [-17.99, -27.94], "laser_charge": [-15.11, -25.03],
	"amb0_drop": [-18.66, -28.65], "amb0_ripple": [-20.38, -36.68],
	"amb1_chime": [-18.51, -26.57], "amb1_ring": [-20.11, -30.10],
	"amb2_ember": [-22.03, -36.38], "amb2_metal": [-19.28, -27.34]
}
# Fixed whole-wave makeup after compression; calibrated by K max50ms tests.
# Hits/defeats are player feedback; boss_appear uses the important-sound K floor.
const SOUND_LEVEL_DB := {
	"enemy_hit": 5.47077,
	"enemy_defeat": 3.28646,
	"boss_hit": 4.22060,
	"boss_defeat": 2.52893,
	"enhancer_defeat": 7.38021,
	"block_break": 3.47052,
	"bomb_explode": 5.65410,
	"ability_get": 2.11427,
	"arrow_unlock": 1.56809,
	"charge": 4.63227,
	"key": 4.07738,
	"heal": 2.44528,
	"item_get": 1.64267,
	"chest_open": 4.69539,
	"buy": 2.53545,
	"tutorial_step": 1.60660,
	"absorb_a": 3.33800,
	"absorb_b": 4.76589,
	"switch_a": 2.47891,
	"switch_b": 3.20330,
	"hurt": 3.18464,
	"death": 2.50939,
	"boss_appear": 6.20865,
	"win": 1.72608,
	"shot_a": -1.22726,
	"shot_b": 0.18240,
	"laser_fire": -2.48288,
}
const SOUNDS := {
	"ui_move": [0.04, 880, 1.0, 0, 0.13], "ui_confirm": [0.12, 880, 1.5, 0, 0.24],
	"ui_back": [0.08, 660, 0.7, 0, 0.18], "pause": [0.12, 588, 0.75, 0, 0.20],
	"map_open": [0.15, 660, 1.5, 0, 0.20], "map_close": [0.12, 784, 0.67, 0, 0.17],
	"jump": [0.10, 320, 2.0, 5, 0.26], "air_jump": [0.12, 640, 1.8, 5, 0.28],
	"land": [0.09, 130, 0.32, 2, 0.30], "shot_a": [0.06, 1500, 0.22, 5, 0.23],
	"shot_b": [0.07, 750, 0.22, 5, 0.25], "homing": [0.20, 360, 2.5, 5, 0.30],
	"empty": [0.07, 220, 0.7, 6, 0.15], "switch_a": [0.14, 740, 1.8, 4, 0.29],
	"switch_b": [0.14, 370, 1.8, 4, 0.30], "aim": [0.035, 840, 1.0, 0, 0.14],
	"dash": [0.16, 500, 2.2, 1, 0.28], "glide": [0.24, 440, 1.4, 1, 0.15],
	"absorb_a": [0.16, 880, 1.5, 4, 0.30], "absorb_b": [0.16, 440, 1.5, 4, 0.31],
	"charge": [0.36, 660, 2.0, 4, 0.33], "hurt": [0.18, 190, 0.3, 2, 0.49],
	"death": [1.0, 280, 0.12, 2, 0.48], "heal": [0.36, 660, 1.5, 4, 0.31],
	"potion": [0.20, 520, 2.0, 4, 0.24], "enemy_hit": [0.06, 220, 0.25, 2, 0.20],
	"enemy_absorb": [0.12, 330, 1.5, 3, 0.19], "enemy_defeat": [0.24, 220, 0.2, 2, 0.31],
	"enhancer_defeat": [0.48, 440, 2.0, 4, 0.36], "arrow_unlock": [0.65, 740, 2.0, 4, 0.34],
	"enemy_warn": [0.10, 360, 1.2, 3, 0.07], "enemy_warn_special": [0.24, 430, 1.7, 3, 0.14],
	"enemy_shot": [0.05, 330, 0.4, 3, 0.09], "enemy_homing": [0.18, 280, 2.0, 3, 0.16],
	"enemy_switch": [0.12, 330, 1.5, 3, 0.13], "laser_charge": [0.60, 200, 6.0, 7, 0.19],
	"laser_fire": [0.20, 1300, 0.18, 5, 0.32], "bomb_warn": [0.30, 250, 2.0, 7, 0.14],
	"bomb_explode": [0.45, 160, 0.15, 2, 0.45], "block_break": [0.14, 260, 0.2, 2, 0.26],
	"wall_place": [0.14, 200, 0.4, 2, 0.22], "wall_vanish": [0.10, 600, 0.4, 1, 0.12],
	"boss_appear": [1.8, 165, 4.0, 7, 0.43], "boss_shot": [0.12, 220, 0.3, 3, 0.24],
	"boss_hit": [0.10, 150, 0.2, 2, 0.31], "boss_defeat": [2.0, 160, 0.15, 2, 0.58],
	"loop_up": [0.95, 440, 2.0, 10, 0.37], "crystal": [0.10, 1320, 1.5, 4, 0.21],
	"key": [0.32, 988, 2.0, 4, 0.29], "chest_open": [0.30, 660, 2.0, 4, 0.31],
	"chest_locked": [0.12, 220, 0.7, 6, 0.20], "item_get": [0.45, 740, 2.0, 4, 0.30],
	"ability_get": [0.95, 660, 2.0, 4, 0.38], "shop_open": [0.24, 660, 1.5, 4, 0.25],
	"buy": [0.24, 880, 1.5, 4, 0.29], "deny": [0.12, 260, 0.7, 6, 0.20],
	"equip": [0.16, 660, 1.5, 4, 0.25], "tutorial_step": [0.40, 830, 2.0, 4, 0.31],
	"win": [3.5, 588, 2.0, 8, 0.43], "lose": [2.5, 440, 0.5, 9, 0.34],
	"amb0_drop": [0.16, 1320, 0.65, 0, 0.12], "amb0_ripple": [0.30, 680, 1.3, 1, 0.09],
	"amb1_chime": [0.42, 1568, 1.0, 3, 0.12], "amb1_ring": [0.36, 1175, 1.0, 0, 0.10],
	"amb2_ember": [0.10, 360, 0.3, 1, 0.10], "amb2_metal": [0.36, 293, 0.97, 3, 0.11]
}
var thread: Thread
var mutex := Mutex.new()
var _cancel := false
var _mailbox: Dictionary = {}
var metrics: Dictionary = {}
var started_usec := 0
var completed := false
var _sines := PackedFloat32Array()
var _pulse := PackedFloat32Array()
var _metal := PackedFloat32Array()
var _grit := PackedFloat32Array()

func start() -> void:
	if thread != null: return
	started_usec = Time.get_ticks_usec()
	thread = Thread.new()
	thread.start(_work, Thread.PRIORITY_LOW)

func stopped() -> bool:
	mutex.lock()
	var value := _cancel
	mutex.unlock()
	return value

func shutdown() -> void:
	mutex.lock()
	_cancel = true
	mutex.unlock()
	if thread != null:
		thread.wait_to_finish()
		thread = null

func collect() -> Dictionary:
	mutex.lock()
	var result := _mailbox
	_mailbox = {}
	mutex.unlock()
	return result

func _work() -> void:
	_sines.resize(4096)
	_pulse.resize(4096)
	_metal.resize(4096)
	_grit.resize(4096)
	for i in range(4096):
		var p := TAU * i / 4096.0
		_sines[i] = sin(p)
		# Finite harmonics: no discontinuous square/saw or unbounded FM sidebands.
		_pulse[i] = (sin(p) + 0.42 * sin(2*p) + 0.25 * sin(3*p) + 0.12 * sin(5*p)) / 1.4
		_metal[i] = (sin(p) + 0.45 * sin(3*p) + 0.26 * sin(7*p)) / 1.4
		_grit[i] = (sin(p) + 0.6 * sin(3*p) + 0.35 * sin(5*p) + 0.18 * sin(7*p)) / 1.5
	for id: String in SOUNDS.keys() + MUSIC_IDS:
		if stopped(): break
		var began := Time.get_ticks_usec()
		var music := MUSIC_IDS.has(id)
		var samples := _music(id) if music else _sound(id)
		if stopped(): break
		var rate := MUSIC_RATE if music else SE_RATE
		var result := _encode(samples, rate, music, id)
		if stopped(): break
		result.ms = (Time.get_ticks_usec() - began) / 1000.0
		result.ready_ms = (Time.get_ticks_usec() - started_usec) / 1000.0
		mutex.lock()
		_mailbox[id] = result.stream
		result.erase("stream")
		metrics[id] = result
		mutex.unlock()
	mutex.lock()
	completed = true
	mutex.unlock()

func snapshot() -> Dictionary:
	mutex.lock()
	var result := {"ids": metrics.duplicate(true), "complete": completed}
	mutex.unlock()
	return result

# Table selection bounds the highest partial below Nyquist, including sweeps.
func _tone(freq: float, ratio: float, seconds: float, rate: int, kind: int, decay: float = 6.0) -> PackedFloat32Array:
	var n := maxi(1, int(seconds * rate))
	var data := PackedFloat32Array()
	data.resize(n)
	var wave := _metal if kind == 3 else _pulse
	if kind == 2: wave = _grit
	var harmonic := 7 if kind in [2, 3] else 5
	if kind == 0 or maxf(freq, freq * ratio) * harmonic > rate * 0.46: wave = _sines
	var phase := 0.0
	var increment := freq * 4096.0 / rate
	var bend := pow(maxf(0.05, ratio), 1.0 / n)
	var envelope := 1.0
	var fall := exp(-decay / n)
	var attack_scale := 1.0 / (rate * 0.001)
	var release_scale := 1.0 / (rate * 0.004)
	for i in range(n):
		if i % 4096 == 0 and stopped(): return data
		phase += increment
		increment *= bend
		data[i] = wave[int(phase) & 4095] * envelope * minf(1, i * attack_scale) * minf(1, (n-1-i) * release_scale)
		envelope *= fall
	return data

func _noise(seconds: float, rate: int, seed_value: int, decay: float, high: bool = false) -> PackedFloat32Array:
	var data := PackedFloat32Array()
	var n := int(seconds * rate)
	data.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var previous := 0.0
	var envelope := 1.0
	var fall := exp(-decay / n)
	for i in range(n):
		if i % 4096 == 0 and stopped(): return data
		var white := rng.randf_range(-1, 1)
		# Two-tap filters: bright noise for air/hats, rounded but un-muffled impacts.
		var value := (white - previous) * 0.5 if high else (white + previous) * 0.5
		previous = white
		data[i] = value * envelope * minf(1, i / (rate * 0.001)) * minf(1, (n-1-i) / (rate * 0.004))
		envelope *= fall
	return data

func _add(into: PackedFloat32Array, note: PackedFloat32Array, offset: int, gain: float) -> void:
	var end := mini(note.size(), into.size() - offset)
	for i in range(end):
		if i % 4096 == 0 and stopped(): return
		into[offset+i] += note[i] * gain

func _phrase(into: PackedFloat32Array, freq: float, seconds: float, kind: int, offset: int = 0) -> void:
	var steps := [0, 4, 7, 12]
	if kind == 9: steps = [7, 4, 2, 0, -3, -5]
	elif kind == 8: steps = [0, 4, 7, 12, 7, 12, 16, 19]
	elif seconds <= 0.12: steps = [0, 7]
	var spacing := minf(0.095, seconds / (steps.size() + 1))
	if kind == 9: spacing = 0.24
	if kind == 8: spacing = 0.16
	for j in range(steps.size()):
		if stopped(): return
		var duration := minf(seconds - j * spacing, spacing * 1.6)
		_add(into, _tone(freq * pow(2, steps[j] / 12.0), 1, duration, SE_RATE, 1, 4), offset + int(j * spacing * SE_RATE), 0.7)
	# Fanfare ends with a sustained major triad; loss resolves to a short minor chord.
	if kind in [8, 9] or seconds > 0.6:
		var at := int((steps.size() * spacing) * SE_RATE) + offset
		var remaining := seconds - steps.size() * spacing
		for interval in [0, 3 if kind == 9 else 4, 7]:
			_add(into, _tone(freq * pow(2, interval / 12.0), 1, remaining, SE_RATE, 1, 3.5), at, 0.32)

func _sound(id: String) -> PackedFloat32Array:
	var spec: Array = SOUNDS[id]
	var seconds: float = spec[0]
	var freq: float = spec[1]
	var ratio: float = spec[2]
	var kind: int = spec[3]
	var data := PackedFloat32Array()
	data.resize(int(seconds * SE_RATE))
	var noise_seed := 80421 + id.hash()
	match kind:
		4, 8, 9:
			_phrase(data, freq, seconds, kind)
			if id.begins_with("switch"):
				_add(data, _noise(0.035, SE_RATE, noise_seed, 5, true), 0, 0.35)
				for interval in [0, 4, 7]:
					_add(data, _tone(freq * pow(2, interval / 12.0), 1, 0.09, SE_RATE, 1, 5), int(0.025 * SE_RATE), 0.18)
			elif id == "enhancer_defeat":
				_add(data, _tone(180, 0.2, 0.14, SE_RATE, 1, 7), 0, 0.7)
				_add(data, _noise(0.12, SE_RATE, noise_seed, 7), 0, 0.8)
		2:
			# Rapid pitch drop supplies the impact's core; noise supplies its edge.
			_add(data, _tone(freq, ratio, minf(seconds, 0.22), SE_RATE, 1, 7), 0, 0.9)
			_add(data, _noise(minf(seconds, 0.20), SE_RATE, noise_seed, 7), 0, 0.85)
			if id in ["enemy_defeat", "boss_defeat", "block_break"]:
				_phrase(data, 660 if id != "boss_defeat" else 440, minf(seconds * 0.8, 1.6), 4, int(seconds * 0.12 * SE_RATE))
			elif id == "death":
				_add(data, _tone(440, 0.2, seconds, SE_RATE, 3, 5), 0, 0.55)
		1:
			_add(data, _noise(seconds, SE_RATE, noise_seed, 7, true), 0, 0.9)
			_add(data, _tone(freq, ratio, seconds, SE_RATE, 1, 7), 0, 0.4)
		5:
			_add(data, _tone(freq, ratio, seconds, SE_RATE, 1, 6), 0, 1)
			_add(data, _noise(0.012, SE_RATE, noise_seed, 5, true), 0, 0.65)
		6:
			_add(data, _tone(freq, ratio, seconds, SE_RATE, 1, 5), 0, 0.8)
			_add(data, _tone(freq * 1.05946, ratio, seconds, SE_RATE, 1, 5), 0, 0.5)
		7:
			# Accelerating articulated pulses, including a final high rising layer.
			var at := 0.0
			while at < seconds:
				if stopped(): return data
				var progress := at / seconds
				var gap := lerpf(0.09, 0.026, progress)
				_add(data, _tone(freq * pow(ratio, progress), 1.15, gap * 1.4, SE_RATE, 3, 4), int(at * SE_RATE), lerpf(0.5, 0.9, progress))
				at += gap
		10:
			for step in range(8):
				var interval: int = LOOP_UP_INTERVALS[step]
				_add(data, _tone(freq * pow(2, interval / 12.0), 1, 0.15, SE_RATE, 3, 4), int(step * 0.075 * SE_RATE), 0.65)
			_add(data, _tone(110, 0.35, 0.3, SE_RATE, 2, 5), 0, 1.1)
			_add(data, _noise(0.12, SE_RATE, noise_seed, 6), 0, 0.5)
		_:
			_add(data, _tone(freq, ratio, seconds, SE_RATE, kind, 7), 0, 1)
	if kind == 2 or id in ["enhancer_defeat", "boss_appear"]:
		_compress(data, SE_RATE, false, 0.16)
	return data

func _drum(kind: int, seed_value: int) -> PackedFloat32Array:
	if kind == 0:
		var kick := _tone(155, 0.28, 0.22, MUSIC_RATE, 0, 7)
		_add(kick, _noise(0.010, MUSIC_RATE, seed_value, 6, true), 0, 0.90)
		_add(kick, _tone(1400, 0.6, 0.012, MUSIC_RATE, 0, 5), 0, 0.30)
		return kick
	if kind == 1:
		var snare := _noise(0.14, MUSIC_RATE, seed_value, 7)
		_add(snare, _tone(190, 0.65, 0.10, MUSIC_RATE, 1, 6), 0, 0.45)
		return snare
	return _noise(0.065 if kind == 2 else 0.24, MUSIC_RATE, seed_value, 7, true)

# Distinct one-bar drum and bass grids (sixteenth-note positions).
const MUSIC_KICKS := [[0,4,8,12], [0,3,6,8,10,14], [0,8], [0,1,7,8,9,14], [0,2,4,6,8,10,12,14]]
const MUSIC_SNARES := [[4,12], [4,12], [4,12], [8], [4,12]]
# [sixteenth position, chord-relative semitone]; rests and lengths differ.
const MUSIC_BASS := [
 [[0,0],[2,0],[6,7],[8,0],[10,12],[14,7]],
 [[0,0],[3,0],[6,10],[7,12],[10,7],[14,2]],
 [[0,0],[4,12],[7,7],[10,12],[12,2]],
 [[0,0],[1,0],[6,1],[8,0],[9,0],[12,10],[14,1]],
 [[0,0],[1,0],[2,12],[3,0],[4,1],[5,0],[6,7],[7,0],[8,0],[9,12],[10,0],[11,10],[12,7],[13,0],[14,1],[15,7]]
]
# Two-bar melodic hooks: position, semitone relative to tonic, length in 16ths.
# Repeated notes, steps, held notes and rests; these are not chord arpeggios.
const MUSIC_HOOKS := [
 [[0,7,2],[3,9,1],[4,11,3],[8,9,2],[11,7,1],[12,6,3],[16,7,2],[19,9,1],[20,14,3],[24,11,2],[27,9,1],[28,7,3]],
 [[0,7,1],[3,9,2],[6,10,1],[8,9,2],[11,7,1],[14,5,2],[17,7,2],[20,9,1],[22,12,2],[26,10,1],[29,9,2]],
 [[0,12,2],[4,11,2],[7,14,1],[10,16,2],[14,14,2],[16,12,3],[21,11,2],[24,9,2],[28,7,3]],
 [[0,0,3],[4,1,2],[8,0,4],[14,7,2],[16,0,3],[20,1,2],[24,3,3],[28,1,3]],
 [[0,12,1],[2,11,1],[4,12,2],[7,13,1],[8,12,2],[12,7,3],[16,12,1],[18,11,1],[20,8,2],[23,7,1],[24,5,2],[28,4,3]]
]
const LOOP_UP_INTERVALS := [0,3,6,9,12,15,18,21]

func _cached(cache: Dictionary, semitone: int, root: float, seconds: float, kind: int, decay: float = 3.0) -> PackedFloat32Array:
	var key := Vector3i(semitone, kind, int(round(seconds * MUSIC_RATE)))
	if not cache.has(key):
		var note := _tone(root * pow(2, semitone / 12.0), 1, seconds, MUSIC_RATE, kind, decay)
		cache[key] = note
	return cache[key]

# Smooth envelope follower / gain, never sample clipping or wave folding.
# One full read-only warm-up settles the periodic state; only pass two writes.
# The 70ms release loses <1e-100 of its initial error over the shortest loop.
func _compress(data: PackedFloat32Array, rate: int, circular: bool, threshold: float) -> void:
	var attack := exp(-1.0 / (rate * 0.002))
	var release := exp(-1.0 / (rate * 0.070))
	var envelope := 0.0
	var gain := 1.0
	var lookahead := int(rate * 0.008)
	var original := data.duplicate()
	if not circular:
		for i in range(mini(lookahead, data.size())): envelope = maxf(envelope, absf(data[i]))
		if envelope > threshold: gain = pow(threshold / envelope, 5.0/6.0)
	for pass_index in range(2 if circular else 1):
		for i in range(data.size()):
			if i % 4096 == 0 and stopped(): return
			var ahead := i + lookahead
			var level := absf(original[ahead % original.size()]) if circular or ahead < original.size() else 0.0
			# Peak hold anticipates short drum crests; gain still moves over 2ms.
			envelope = maxf(level, release * envelope)
			# Ratio 6:1, continuous at threshold; power only above threshold.
			var target := pow(threshold / envelope, 5.0/6.0) if envelope > threshold else 1.0
			var smoothing := attack if target < gain else release
			gain = smoothing * gain + (1-smoothing) * target
			if not circular or pass_index == 1: data[i] *= gain

func _music(id: String) -> PackedFloat32Array:
	var index := MUSIC_IDS.find(id)
	var beat := 60.0 / float(MUSIC_BPM[id])
	var beats: int = MUSIC_BEATS[id]
	var data := PackedFloat32Array()
	data.resize(int(round(beats * beat * MUSIC_RATE)))
	var drums := PackedFloat32Array()
	drums.resize(data.size())
	var sustained := PackedFloat32Array()
	sustained.resize(data.size())
	var duck := PackedFloat32Array()
	duck.resize(data.size())
	duck.fill(1.0)
	var root: float = [146.832384, 164.813778, 174.614116, 110.0, 110.0][index]
	var progression: Array = [
		[[0,4],[-5,4],[-3,3],[-7,4]], [[0,3],[-4,4],[3,4],[-2,4]],
		[[0,4],[2,4],[7,4],[0,4]], [[0,3],[1,4],[-2,4],[0,3]],
		[[0,3],[-4,4],[-7,3],[-5,3]]
	][index]
	var kick := _drum(0, 68152+index)
	var snare := _drum(1, 68252+index)
	var hat := _drum(2, 68352+index)
	var open_hat := _drum(3, 68452+index)
	var bass_cache: Dictionary = {}
	var lead_cache: Dictionary = {}
	var pad_cache: Dictionary = {}
	for bar in range(beats / 4):
		if stopped(): return data
		var section_b := (bar / 8) % 2 == 1
		var degree: int = progression[bar % 4][0]
		var third: int = progression[bar % 4][1]
		for step in range(16):
			var offset := int(round((bar*4 + step*0.25) * beat * MUSIC_RATE))
			if step in MUSIC_KICKS[index]:
				var accent := (3.00 if index == 2 else 1.60) if step in [0,8] else 0.50
				_mix(drums, kick, offset, accent * (0.65 if index != 3 else 0.75))
				_duck_music(duck, offset)
			if step in MUSIC_SNARES[index]: _mix(drums, snare, offset, 0.65 if index != 3 else 0.80)
			var hat_step := 1 if index in [2,4] or section_b else 2
			if step % hat_step == 0:
				var hat_gain := (0.65 if step % 2 == 0 else 0.40) if index != 2 else (1.7 if step in [0,8] else 1.15)
				_mix(drums, hat, offset, hat_gain)
			if index == 0 and step % 4 == 2: _mix(drums, open_hat, offset, 0.07)
			elif index == 1 and step in [3,10,14]: _mix(drums, open_hat, offset, 0.045)
			elif index == 3 and step == 14: _mix(drums, open_hat, offset, 0.06)
		for note: Array in MUSIC_BASS[index]:
			var step: int = note[0]
			var duration := beat * (0.22 if index == 4 else 0.43)
			var bass_gain := (0.20 if step != 0 else 0.36) if index == 2 else (0.40 if index >= 3 else 0.36)
			_mix(data, _cached(bass_cache, degree+(0 if index == 4 else -12)+int(note[1]), root, duration, 2 if index >= 3 else 1, 2.6), int(round((bar*4+step*0.25)*beat*MUSIC_RATE)), bass_gain)
		# Region1's arpeggio is a separate backing voice beneath its melodic hook.
		if index == 2:
			for step in range(16):
				var arp: int = [0,third,7,12,7,third,14,7][step%8]
				var arp_gain := 1.9 if step in [0,8] else 1.3
				_mix(data, _cached(lead_cache, degree+arp+12, root, beat*0.12, 3, 8.0), int(round((bar*4+step*0.25)*beat*MUSIC_RATE)), arp_gain)
			# Anticipated tonic carries a pitched release through the bar/loop seam.
			_mix(sustained, _cached(lead_cache, degree+12, root, beat*0.45, 1), int(round((bar*4+3.875)*beat*MUSIC_RATE)), 0.50)
		for note: Array in MUSIC_HOOKS[index]:
			if int(note[0]) / 16 != bar % 2: continue
			var pitch := int(note[1]) + 12 + (12 if section_b and index in [0,2] else 0)
			var duration := beat * int(note[2]) * 0.23
			var offset := int(round((bar*4+int(note[0])%16*0.25)*beat*MUSIC_RATE))
			_mix(data, _cached(lead_cache, pitch, root, duration, 3 if index in [2,3] else 1), offset, 0.18 if index == 2 else (0.25 if index != 4 else 0.30))
			if section_b and index in [1,3,4]:
				_mix(data, _cached(lead_cache, pitch+7, root, duration, 1), offset+int(beat*0.25*MUSIC_RATE), 0.11)
		for interval in [0,third,7]:
			_mix(sustained, _cached(pad_cache, degree+int(interval), root, beat*4.4, 0, 1.6), int(round(bar*4*beat*MUSIC_RATE)), 0.20 if index == 2 else 0.40)
		# Region-specific fourth-bar pickups; each includes a soft, wrapped release.
		if bar % 4 == 3:
			var fill_steps: Array = [[13,14,15],[11,14,15],[12,13,14,15],[12,13,15],[8,10,12,13,14,15]][index]
			for step: int in fill_steps:
				_mix(drums, snare if index in [0,4] else hat, int(round((bar*4+step*0.25)*beat*MUSIC_RATE)), 0.075)
			var pickup := int(round((bar*4+3.875)*beat*MUSIC_RATE))
			_mix(drums, kick, pickup, 0.65 if index == 3 else (0.45 if index == 0 else 0.35))
			_duck_music(duck, pickup)
	# Only held backing voices follow the kick; drums and hook attacks stay intact.
	for i in range(data.size()):
		if i % 4096 == 0 and stopped(): return data
		sustained[i] *= duck[i]
	_compress(sustained, MUSIC_RATE, true, 0.16)
	for i in range(data.size()):
		if i % 4096 == 0 and stopped(): return data
		data[i] += sustained[i] * (2.5 if index == 4 else (3.1 if index == 2 else (2.0 if index == 1 else 1.8))) + drums[i]
	# Peak-dependent lookahead only; no metrical gain on the complete mix.
	_music_peak_control(data, 0.95 if index == 2 else 0.65)
	return data

# Circular lookahead limiter: smooth gain, 1ms attack / 25ms release.
# A full read-only loop settles both states before the writing pass.
func _music_peak_control(data: PackedFloat32Array, threshold: float) -> void:
	var original := data.duplicate()
	var attack := exp(-1.0 / (MUSIC_RATE * 0.001))
	var release := exp(-1.0 / (MUSIC_RATE * 0.025))
	var ahead := int(MUSIC_RATE * 0.005)
	var envelope := 0.0
	var gain := 1.0
	for pass_index in range(2):
		for i in range(data.size()):
			if i % 4096 == 0 and stopped(): return
			envelope = maxf(absf(original[(i+ahead) % data.size()]), envelope * release)
			var target := minf(1.0, threshold / maxf(0.00001, envelope))
			var smoothing := attack if target < gain else release
			gain = smoothing * gain + (1-smoothing) * target
			if pass_index == 1: data[i] *= gain

# -8dB on pads and the crystal pickup release, reached in 3ms, back in 120ms.
# Every scheduled kick (including pickups) wraps through the loop seam.
func _duck_music(gains: PackedFloat32Array, offset: int) -> void:
	var attack := int(MUSIC_RATE * 0.003)
	var release := int(MUSIC_RATE * 0.120)
	for i in range(attack + release):
		if i % 4096 == 0 and stopped(): return
		var phase := float(i) / attack if i < attack else 1.0 - float(i-attack) / release
		var dip := phase * phase * (3 - 2 * phase)
		var at := (offset + i) % gains.size()
		gains[at] = minf(gains[at], 1.0 - 0.602 * dip)

func _mix(into: PackedFloat32Array, note: PackedFloat32Array, offset: int, gain: float) -> void:
	# Both the release and the short, quiet echo wrap into the next loop.
	var n := into.size()
	var delay := int(MUSIC_RATE * 0.065)
	for i in range(note.size()):
		if i % 4096 == 0 and stopped(): return
		var value := note[i] * gain
		into[(offset+i) % n] += value
		into[(offset+i+delay) % n] += value * 0.07

func _encode(samples: PackedFloat32Array, rate: int, loop: bool, id: String) -> Dictionary:
	var n := samples.size()
	var total := 0.0
	var weight := 0.0
	var raw_peak := 0.0
	var raw_sq := 0.0
	var window_scale := 1.0 / (rate * 0.004)
	for i in range(n):
		if i % 4096 == 0 and stopped(): return {}
		var window := 1.0 if loop else minf(1, minf(i, n-1-i) * window_scale)
		var value := samples[i] * window
		total += value
		raw_peak = maxf(raw_peak, absf(value))
		raw_sq += value * value
		weight += window
	var mean := total / weight
	var peak_target := 0.69 if loop else float(SOUNDS[id][4])
	var rms_target := (0.20 if id == "boss" else (0.155 if id == "region1" else 0.17)) if loop else 1.0
	if not loop: peak_target = minf(0.85, peak_target * db_to_linear(SOUND_LEVEL_DB.get(id, 0.0)))
	if QUIET_LIMITS.has(id):
		peak_target = minf(peak_target, db_to_linear(QUIET_LIMITS[id][0]))
		rms_target = db_to_linear(QUIET_LIMITS[id][1])
	# Whole-wave gain only; never clip individual samples. DC is removed under the window.
	var scale := minf(peak_target / maxf(0.0001, raw_peak + absf(mean)), rms_target / maxf(0.0001, sqrt(raw_sq/n)))
	var peak := 0.0
	var sum_sq := 0.0
	var pcm := PackedByteArray()
	pcm.resize(n * 2)
	for i in range(n):
		if i % 4096 == 0 and stopped(): return {}
		var value := (samples[i] - mean) * scale
		if not loop: value *= minf(1, minf(i, n-1-i) * window_scale)
		pcm.encode_s16(i*2, roundi(value * 32767))
		peak = maxf(peak, absf(value))
		sum_sq += value * value
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = pcm
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = n
	return {"stream": stream, "bytes": pcm.size(), "seconds": float(n)/rate, "peak": peak, "rms": sqrt(sum_sq/n)}
