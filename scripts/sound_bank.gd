extends RefCounted
## Immutable PCM is published only after completion. No SceneTree or global RNG.
const SE_RATE := 32000
const MUSIC_RATE := 22050
const MUSIC_IDS := ["title", "region0", "region1", "region2", "boss"]
# duration, frequency, end-frequency ratio, timbre (0 glass / 1 wind / 2 impact / 3 FM), gain
const SOUNDS := {
	"ui_move": [0.045, 440, 1.0, 0, 0.10], "ui_confirm": [0.15, 660, 1.5, 0, 0.19],
	"ui_back": [0.12, 520, 0.7, 0, 0.16], "pause": [0.19, 392, 0.75, 0, 0.18],
	"map_open": [0.22, 330, 1.5, 0, 0.16], "map_close": [0.18, 495, 0.67, 0, 0.14],
	"jump": [0.12, 240, 1.8, 1, 0.20], "air_jump": [0.15, 480, 1.6, 0, 0.23],
	"land": [0.13, 100, 0.55, 2, 0.26], "shot_a": [0.065, 740, 0.68, 0, 0.15],
	"shot_b": [0.075, 370, 0.7, 0, 0.16], "homing": [0.28, 280, 2.0, 1, 0.25],
	"empty": [0.08, 140, 0.65, 1, 0.13], "switch_a": [0.18, 500, 1.7, 0, 0.24],
	"switch_b": [0.20, 550, 0.5, 0, 0.24], "aim": [0.045, 420, 1.0, 0, 0.11],
	"dash": [0.22, 210, 0.6, 1, 0.22], "glide": [0.40, 170, 0.8, 1, 0.13],
	"absorb_a": [0.21, 660, 1.03, 3, 0.25], "absorb_b": [0.24, 330, 1.03, 3, 0.25],
	"charge": [0.55, 660, 1.5, 3, 0.27], "hurt": [0.24, 110, 0.4, 2, 0.43],
	"death": [1.0, 330, 0.12, 2, 0.42], "heal": [0.55, 523, 1.5, 0, 0.26],
	"potion": [0.30, 260, 1.8, 1, 0.21], "enemy_hit": [0.075, 160, 0.6, 2, 0.17],
	"enemy_absorb": [0.16, 290, 0.95, 3, 0.18], "enemy_defeat": [0.32, 140, 0.3, 2, 0.25],
	"enhancer_defeat": [0.70, 350, 0.4, 3, 0.30], "arrow_unlock": [0.85, 587, 1.5, 0, 0.29],
	"enemy_warn": [0.10, 240, 1.1, 0, 0.07], "enemy_warn_special": [0.24, 290, 1.4, 3, 0.13],
	"enemy_shot": [0.06, 220, 0.8, 0, 0.09], "enemy_homing": [0.25, 190, 1.6, 1, 0.16],
	"enemy_switch": [0.18, 280, 1.3, 3, 0.12], "laser_charge": [0.60, 100, 4.0, 0, 0.18],
	"laser_fire": [0.30, 320, 0.55, 1, 0.26], "bomb_warn": [0.30, 170, 1.8, 0, 0.13],
	"bomb_explode": [0.65, 85, 0.2, 2, 0.37], "block_break": [0.20, 170, 0.4, 2, 0.20],
	"wall_place": [0.22, 160, 0.7, 2, 0.18], "wall_vanish": [0.17, 200, 0.5, 1, 0.10],
	"boss_appear": [1.8, 110, 2.0, 3, 0.40], "boss_shot": [0.17, 130, 0.7, 2, 0.21],
	"boss_hit": [0.13, 90, 0.55, 2, 0.25], "boss_defeat": [2.0, 95, 0.12, 2, 0.45],
	"loop_up": [1.2, 146, 0.8, 3, 0.30], "crystal": [0.19, 880, 1.03, 0, 0.14],
	"key": [0.52, 784, 1.5, 3, 0.23], "chest_open": [0.40, 392, 2.0, 3, 0.25],
	"chest_locked": [0.16, 150, 0.75, 2, 0.17], "item_get": [0.65, 587, 1.5, 0, 0.25],
	"ability_get": [1.3, 523, 2.0, 3, 0.31], "shop_open": [0.35, 440, 1.5, 0, 0.20],
	"buy": [0.35, 698, 1.5, 0, 0.23], "deny": [0.16, 180, 0.8, 0, 0.17],
	"equip": [0.22, 440, 1.5, 3, 0.19], "tutorial_step": [0.65, 659, 1.5, 0, 0.25],
	"win": [3.5, 523, 2.0, 3, 0.35], "lose": [2.5, 293, 0.35, 0, 0.30],
	"amb0_drop": [0.30, 1047, 0.65, 0, 0.12], "amb0_ripple": [0.55, 340, 0.7, 1, 0.09],
	"amb1_chime": [0.80, 1175, 1.01, 3, 0.12], "amb1_ring": [0.70, 784, 1.0, 0, 0.10],
	"amb2_ember": [0.15, 180, 0.4, 1, 0.10], "amb2_metal": [0.75, 146, 0.97, 3, 0.11]
}
var thread: Thread
var mutex := Mutex.new()
var _cancel := false
var _mailbox: Dictionary = {}
var metrics: Dictionary = {}
var started_usec := 0
var completed := false
var _sines := PackedFloat32Array()

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
	for i in range(4096): _sines[i] = sin(TAU * i / 4096.0)
	for id: String in SOUNDS.keys() + MUSIC_IDS:
		if stopped(): break
		var began := Time.get_ticks_usec()
		var music := MUSIC_IDS.has(id)
		var samples := _music(id) if music else _sound(id)
		if stopped(): break
		var rate := MUSIC_RATE if music else SE_RATE
		var result := _encode(samples, rate, music)
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

func _sound(id: String) -> PackedFloat32Array:
	var spec: Array = SOUNDS[id]
	var n := int(float(spec[0]) * SE_RATE)
	var data := PackedFloat32Array()
	data.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 80421 + id.hash()
	var phase := 0.0
	var noise := 0.0
	var kind: int = spec[3]
	var frequency: float = spec[1]
	var sweep: float = spec[2] - 1.0
	for i in range(n):
		if i % 4096 == 0 and stopped(): return data
		var t := float(i) / n
		phase += frequency * (1.0 + sweep * t) / SE_RATE
		var p := int(phase * 4096) & 4095
		var value: float = _sines[p]
		if kind == 1 or kind == 2:
			noise += 0.14 * (rng.randf_range(-1.0, 1.0) - noise)
			value = value * (0.35 if kind == 1 else 0.75) + noise * 1.7
		elif kind == 3:
			value = _sines[int(phase * 4096 + 650 * _sines[(p * 2) & 4095] * (1.0-t)) & 4095]
		var attack := minf(1.0, float(i) / (SE_RATE * 0.004))
		var release := 1.0 - t
		var envelope := attack * release * release
		if id in ["win", "lose", "ability_get", "arrow_unlock"]:
			# Discrete triad steps make these short phrases rather than a single sweep.
			var step := int(t * 6)
			var local_t := fmod(t * 6, 1.0)
			value = _sines[int(phase * [1.0, 1.25, 1.5, 1.0, 1.5, 2.0][step] * 4096) & 4095]
			envelope *= minf(1.0, local_t * 40.0) * (1.0-local_t)
		data[i] = value * envelope * float(spec[4])
	return data

func _note(freq: float, seconds: float, kind: int) -> PackedFloat32Array:
	var data := PackedFloat32Array()
	data.resize(int(seconds * MUSIC_RATE))
	var phase := 0.0
	for i in range(data.size()):
		var t := float(i) / data.size()
		phase += freq / MUSIC_RATE
		var p := int(phase * 4096) & 4095
		var value: float = _sines[p]
		if kind == 1: value += 0.15 * _sines[(p * 2) & 4095]
		if kind == 2: value = _sines[int(phase * 4096 + 440 * _sines[(p * 3) & 4095] * (1.0-t)) & 4095]
		var attack := minf(1.0, float(i) / (MUSIC_RATE * (0.18 if kind == 3 else 0.008)))
		var release := minf(1.0,(1.0-t)/0.25) if kind == 3 else (1.0-t)*(1.0-t)
		data[i] = value * attack * release
	return data

func _music(id: String) -> PackedFloat32Array:
	var index := MUSIC_IDS.find(id)
	var bpm: float = [76, 84, 70, 64, 136][index]
	var beats := 64 if id == "boss" else 32
	var beat := 60.0 / bpm
	# Region 0 uses 40 beats (28.57s), keeping every exploration loop >=24s.
	if index == 1: beats = 40
	var n := int(round(beats * beat * MUSIC_RATE))
	var data := PackedFloat32Array()
	data.resize(n)
	var root: float = [146.832, 164.814, 174.614, 110.0, 110.0][index]
	var scale: Array = [[0,4,7,11,12,7,4,2], [0,3,5,7,10,12,7,5], [0,4,6,11,12,6,4,2], [0,1,7,8,12,7,1,0], [0,0,7,0,3,0,8,7]][index]
	var notes: Array[PackedFloat32Array] = []
	for semitone in range(13):
		if stopped(): return data
		notes.append(_note(root * 2 * pow(2.0, semitone/12.0), beat * 1.8, 2 if index == 2 else 1))
	var bass := _note(root / 2, beat * 1.5, 0)
	var pad := _note(root, beat * 6, 3)
	var fifth := _note(root * 1.5, beat * 6, 3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 68152 + index
	var noise := 0.0
	for b in range(beats * (2 if index == 4 else 1)):
		if stopped(): return data
		var offset := int(round(b * beat * MUSIC_RATE / (2 if index == 4 else 1)))
		_mix(data, notes[scale[b % 8]], offset, 0.13 if index != 3 else 0.065)
		_mix(data, bass, offset, 0.13)
		if b % 4 == 0:
			_mix(data, pad, offset, 0.14)
			_mix(data, fifth, offset, 0.07)
		if index == 4:
			for j in range(2205):
				noise += 0.25 * (rng.randf_range(-1,1)-noise)
				var t := float(j)/2205
				data[(offset+j)%n] += noise * minf(1,j/64.0) * (1.0-t)*(1.0-t) * 0.17
	if index == 1 or index == 3:
		# Periodic filtered noise: circular smoothing gives the same boundary as the interior.
		var layer := PackedFloat32Array()
		layer.resize(n)
		for i in range(n):
			noise += 0.035 * (rng.randf_range(-1,1)-noise)
			layer[i] = noise * 0.035
		var seam := (layer[0]+layer[-1])/2
		for i in range(1102):
			var blend := 1.0-float(i)/1102
			layer[i] = lerpf(layer[i],seam,blend)
			layer[n-1-i] = lerpf(layer[n-1-i],seam,blend)
		for i in range(n): data[i] += layer[i]
	return data

func _mix(into: PackedFloat32Array, note: PackedFloat32Array, offset: int, gain: float) -> void:
	# Godot packed arrays are reference-counted; indexed writes modify this array in-place.
	var n := into.size()
	for i in range(note.size()): into[(offset+i)%n] += note[i]*gain
	# A quiet delayed copy wraps across the boundary, including its entire release tail.
	var delay := int(MUSIC_RATE*0.19)
	for i in range(note.size()): into[(offset+i+delay)%n] += note[i]*gain*0.16

func _encode(samples: PackedFloat32Array, rate: int, loop: bool) -> Dictionary:
	var total := 0.0
	var weight := 0.0
	var raw_peak := 0.0
	for i in range(samples.size()):
		if i % 4096 == 0 and stopped(): return {}
		var window := 1.0 if loop else minf(1.0,minf(i,samples.size()-1-i)/float(rate*0.004))
		total += samples[i]*window
		raw_peak = maxf(raw_peak,absf(samples[i]))
		weight += window
	var mean := total / weight
	# Scale the whole waveform; never flatten individual peaks.
	var scale := minf(1.0,(0.69 if loop else 0.88)/maxf(0.0001,raw_peak+absf(mean)))
	var peak := 0.0
	var sum_sq := 0.0
	var pcm := PackedByteArray()
	pcm.resize(samples.size()*2)
	for i in range(samples.size()):
		if i % 4096 == 0 and stopped(): return {}
		var value := (samples[i] - mean)*scale
		# DC removal followed by a 4ms boundary window for non-looping sounds.
		if not loop: value *= minf(1.0,minf(i,samples.size()-1-i)/float(rate*0.004))
		pcm.encode_s16(i*2,roundi(value*32767))
		peak = maxf(peak,absf(value))
		sum_sq += value*value
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = pcm
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	return {"stream": stream, "bytes": pcm.size(), "seconds": float(samples.size())/rate, "peak": peak, "rms": sqrt(sum_sq/samples.size())}
