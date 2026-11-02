extends "res://tests/test_tree.gd"
const Bank := preload("res://scripts/sound_bank.gd")
const Main := preload("res://scripts/main.gd")
const Settings := preload("res://scripts/audio_settings.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Loot := preload("res://scripts/loot.gd")
const Terrain := preload("res://scripts/world_terrain.gd")
const T := preload("res://scripts/tuning.gd")
const Assets := preload("res://scripts/sound_assets.gd")
var OUT := "res://builds/qa/sound/assets/audio-%s-%d/" % [Time.get_datetime_string_from_system().replace(":", ""), OS.get_process_id()]
var checks := 0
var failures: Array[String] = []
var groups: Dictionary = {}
var group := "synthesis"
var bank: RefCounted
var streams: Dictionary
var wave_metrics: Dictionary = {}
var game: Node2D
var event_ids: Dictionary = {}
var benchmark: Dictionary = {}
var music_trace: Array[Dictionary] = []

# Scale-independent brightness and rhythmic onset measurements, also used by
# builds/qa/sound/energy/measure*.gd for archived/current banks.
const ENERGY_ATTACK_IDS := ["shot_a", "shot_b", "enemy_hit", "boss_hit", "enemy_defeat", "hurt", "jump", "land", "dash", "crystal", "ui_move", "ui_confirm"]
const ENERGY_BRIGHTNESS_MIN := 0.35
const ENERGY_RHYTHM_MIN := 0.16
# BS.1770 K weighting, DeMan parameterization used by pyloudnorm.
# Return normalized [b0,b1,b2,a1,a2] for shelf then RLB, at the actual rate.
static func k_coefficients(rate: int) -> Array[PackedFloat64Array]:
	var k := tan(PI * 1681.9744509555319 / rate)
	var q := 0.7071752369554193
	var vh := pow(10, 3.99984385397 / 20.0)
	var vb := pow(vh, 0.499666774155)
	var a := 1 + k / q + k * k
	var shelf := PackedFloat64Array([(vh+vb*k/q+k*k)/a, 2*(k*k-vh)/a, (vh-vb*k/q+k*k)/a, 2*(k*k-1)/a, (1-k/q+k*k)/a])
	k = tan(PI * 38.13547087613982 / rate)
	q = 0.5003270373253953
	a = 1 + k / q + k * k
	return [shelf, PackedFloat64Array([1, -2, 1, 2*(k*k-1)/a, (1-k/q+k*k)/a])]

static func k_weighted(stream: AudioStreamWAV, circular: bool, channel: int = 0, pitch: float = 1.0, gain_db: float = 0.0) -> PackedFloat64Array:
	var pcm := stream.data
	var channels := 2 if stream.stereo else 1
	var source_n := pcm.size() / (2 * channels)
	var n := int(ceil(source_n / pitch))
	var warm := mini(n, int(stream.mix_rate * 0.5)) if circular else 0
	# A zero-input tail includes energy after the last source sample for effects.
	var tail := 0 if circular else int(stream.mix_rate * 0.05)
	var data := PackedFloat64Array()
	data.resize(warm + n + tail)
	var gain := db_to_linear(gain_db)
	for i in range(warm + n):
		var position := ((i - warm + n) % n) * pitch
		var first := mini(source_n - 1, int(position))
		var second := (first + 1) % source_n if circular else mini(source_n - 1, first + 1)
		var a := pcm.decode_s16((first * channels + channel) * 2) / 32768.0
		var b := pcm.decode_s16((second * channels + channel) * 2) / 32768.0
		data[i] = lerpf(a, b, position - first) * gain
	for c in k_coefficients(stream.mix_rate):
		var x1 := 0.0
		var x2 := 0.0
		var y1 := 0.0
		var y2 := 0.0
		for i in range(data.size()):
			var x := data[i]
			var y := c[0]*x + c[1]*x1 + c[2]*x2 - c[3]*y1 - c[4]*y2
			x2 = x1
			x1 = x
			y2 = y1
			y1 = y
			data[i] = y
	return data.slice(warm)

static func k_music_rms_db(stream: AudioStreamWAV, gain_db: float = 0.0) -> float:
	var sq := 0.0
	var n := 0
	for channel in range(2 if stream.stereo else 1):
		var data := k_weighted(stream, true, channel, 1.0, gain_db)
		n = data.size()
		for value in data: sq += value * value
	# BS.1770: sum L/R channel mean squares (no divide by channel count).
	return linear_to_db(sqrt(maxf(1e-20, sq / n)))

static func k_effect_max50_db(stream: AudioStreamWAV, pitch: float = 1.0, gain_db: float = 0.0) -> float:
	var data := k_weighted(stream, false, 0, pitch, gain_db)
	var window := int(round(stream.mix_rate * 0.05))
	var sq := 0.0
	var largest := 0.0
	# Every sample offset, fixed 50ms denominator (including short effects).
	for i in range(data.size()):
		sq += data[i] * data[i]
		if i >= window: sq -= data[i-window] * data[i-window]
		if i >= window-1: largest = maxf(largest, sq)
	return linear_to_db(sqrt(maxf(1e-20, largest / window)))

# Fresh 8A synthesis, measured with the static functions above; dB RMS, not LUFS.
const ENERGY_K_8A_MUSIC := {
	"boss": -13.17576535,
	"region0": -16.81710942,
	"region1": -17.15169604,
	"region2": -19.84009125,
	"title": -17.47908159,
}
const ENERGY_K_8A_EFFECTS := {
	"enemy_hit": -26.15659051,
	"enemy_defeat": -18.46875849,
	"boss_hit": -21.34107985,
	"boss_defeat": -12.55164622,
	"enhancer_defeat": -12.13800063,
	"block_break": -21.34518404,
	"bomb_explode": -14.79618260,
	"ability_get": -14.70242037,
	"arrow_unlock": -16.02508024,
	"charge": -12.79152491,
	"key": -14.05376886,
	"heal": -15.52154251,
	"item_get": -15.69807171,
	"chest_open": -14.16177765,
	"buy": -16.95065912,
	"tutorial_step": -15.61714248,
	"absorb_a": -14.98143018,
	"absorb_b": -15.11818930,
	"switch_a": -18.07146102,
	"switch_b": -17.82059691,
	"hurt": -14.60137240,
	"death": -11.96046576,
	"boss_appear": -9.97694475,
	"win": -12.82354234,
	"shot_a": -26.22270529,
	"shot_b": -25.16089042,
	"enemy_shot": -31.54963154,
	"enemy_warn": -31.09176416,
	"enemy_warn_special": -20.82469209,
	"enemy_homing": -26.35581773,
	"enemy_absorb": -19.06193244,
	"enemy_switch": -22.23774930,
	"boss_shot": -21.34888750,
	"bomb_warn": -22.67699988,
	"laser_charge": -19.57027678,
	"laser_fire": -21.70650014,
	"amb0_drop": -22.34500939,
	"amb0_ripple": -29.81123872,
	"amb1_chime": -18.62533145,
	"amb1_ring": -23.39277977,
	"amb2_ember": -31.46079407,
	"amb2_metal": -21.25941199,
}
const ENERGY_K_COMBAT := ["enemy_hit","enemy_defeat","boss_hit","boss_defeat","enhancer_defeat","block_break","bomb_explode"]
const ENERGY_K_IMPORTANT := ["ability_get","arrow_unlock","charge","key","heal","item_get","chest_open","buy","tutorial_step","absorb_a","absorb_b","switch_a","switch_b","hurt","death","boss_appear","win"]
const ENERGY_K_QUIET := ["enemy_shot","enemy_warn","enemy_warn_special","enemy_homing","enemy_absorb","enemy_switch","boss_shot","bomb_warn","laser_charge","laser_fire","amb0_drop","amb0_ripple","amb1_chime","amb1_ring","amb2_ember","amb2_metal"]
const ENERGY_K_TOLERANCE_DB := 0.5
const ENERGY_QUIET_LIMITS := {
	"enemy_shot": [-22.61, -32.11], "enemy_warn": [-24.01, -33.83],
	"enemy_warn_special": [-18.04, -26.08], "enemy_homing": [-16.96, -32.29],
	"enemy_absorb": [-15.37, -23.41], "enemy_switch": [-18.86, -26.88],
	"boss_shot": [-12.40, -25.56],
	"bomb_warn": [-17.99, -27.94], "laser_charge": [-15.11, -25.03],
	"amb0_drop": [-18.66, -28.65], "amb0_ripple": [-20.38, -36.68],
	"amb1_chime": [-18.51, -26.57], "amb1_ring": [-20.11, -30.10],
	"amb2_ember": [-22.03, -36.38], "amb2_metal": [-19.28, -27.34]
}

static func energy_features(stream: AudioStreamWAV) -> Dictionary:
	var pcm := stream.data
	var n := pcm.size() / 2
	var block := int(stream.mix_rate * 0.01)
	var sq := 0.0
	var diff_sq := 0.0
	var peak := 0.0
	var previous := 0.0
	var envelope: Array[float] = []
	var block_sq := 0.0
	for i in range(n):
		var value := pcm.decode_s16(i*2) / 32768.0
		sq += value * value
		diff_sq += (value-previous) * (value-previous)
		peak = maxf(peak, absf(value))
		previous = value
		block_sq += value * value
		if (i+1) % block == 0:
			envelope.append(sqrt(block_sq / block))
			block_sq = 0
	var onset := -1.0
	for i in range(n):
		if absf(pcm.decode_s16(i*2) / 32768.0) >= peak * 0.5:
			onset = i * 1000.0 / stream.mix_rate
			break
	var rises := 0.0
	var level := 0.0
	for i in range(envelope.size()):
		level += envelope[i]
		rises += maxf(0, envelope[i] - envelope[(i+envelope.size()-1) % envelope.size()])
	return {"brightness": sqrt(diff_sq / maxf(0.00000001, sq)), "rhythm": rises / maxf(0.00000001, level), "attack_ms": onset}

# Average 2ms RMS windows at the same musical phase, aligned independently to
# every cycle (no accumulated sample/block rounding). PCM normalized by 32768.
# The last bin can be shorter than 2ms; every sample belongs to one phase bin.
static func phase_envelope(stream: AudioStreamWAV, period: float) -> Array[float]:
	var pcm := stream.data
	var n := pcm.size() / 2
	var bins := int(ceil(period / 0.002))
	var envelope: Array[float] = []
	envelope.resize(bins)
	envelope.fill(0.0)
	var cycles := int(round(float(n) / stream.mix_rate / period))
	for cycle in range(cycles):
		for bin_index in range(bins):
			var first := int(round((cycle * period + bin_index * 0.002) * stream.mix_rate))
			var end := mini(n, int(round((cycle * period + minf((bin_index+1)*0.002, period)) * stream.mix_rate)))
			var sq := 0.0
			for i in range(first, end):
				var value := pcm.decode_s16(i*2) / 32768.0
				sq += value * value
			envelope[bin_index] += sqrt(sq / maxi(1, end-first)) / cycles
	return envelope

static func beat_attack_features(stream: AudioStreamWAV, bpm: float) -> Dictionary:
	var half_bar := phase_envelope(stream, 120.0 / bpm)
	var eighth := phase_envelope(stream, 30.0 / bpm)
	var maximum: float = half_bar.max()
	return {"peak_ms": half_bar.find(maximum) * 2.0,
		"head_db": linear_to_db(maxf(1e-10, (half_bar[0]+half_bar[1]+half_bar[2]) / 3.0 / maximum)),
		"eighth_min_db": linear_to_db(maxf(1e-10, float(eighth.min()) / float(eighth.max())))}

func energy_test() -> void:
	group = "energy"
	k_measurement_test()
	var report: Dictionary = {"effects": {}, "music": {}, "thresholds": {"brightness": ENERGY_BRIGHTNESS_MIN, "rhythm": ENERGY_RHYTHM_MIN, "attack_ms": 10}}
	var brightness := 0.0
	for id: String in ENERGY_ATTACK_IDS:
		var features := energy_features(streams[id])
		report.effects[id] = features
		brightness += features.brightness
		check(features.attack_ms >= 0 and features.attack_ms <= 10, id + ": reaches half peak within 10ms")
	brightness /= ENERGY_ATTACK_IDS.size()
	report.brightness_mean = brightness
	check(brightness >= ENERGY_BRIGHTNESS_MIN, "mean first-difference RMS / RMS >= brightness threshold")
	var loudness: Array[float] = []
	for id: String in Bank.MUSIC_IDS:
		var stream: AudioStreamWAV = streams[id]
		var features := energy_features(stream)
		report.music[id] = features
		check(Bank.MUSIC_BPM[id] >= 120, id + ": BPM >=120")
		check(Bank.MUSIC_BEATS[id] % 4 == 0, id + ": whole four-beat bars")
		check(absf(stream.get_length() - Bank.MUSIC_BEATS[id] * 60.0 / Bank.MUSIC_BPM[id]) <= 1.0 / stream.mix_rate, id + ": duration matches beats/BPM within one sample")
		check(features.rhythm >= ENERGY_RHYTHM_MIN, id + ": positive 10ms RMS flux / mean RMS >= rhythm threshold")
		var attack := beat_attack_features(stream, Bank.MUSIC_BPM[id])
		report.music[id].beat_attack = attack
		check(attack.peak_ms <= 25 and attack.head_db >= -6, id + ": half-bar peak within 25ms and first 6ms within -6dB")
		check(attack.eighth_min_db >= -12, id + ": eighth-phase envelope floor within -12dB")
		check(0 in Bank.MUSIC_KICKS[Bank.MUSIC_IDS.find(id)] and 8 in Bank.MUSIC_KICKS[Bank.MUSIC_IDS.find(id)], id + ": half-bar attack grid has kicks at sixteenths 0 and 8")
		if id != "boss": check(Bank.MUSIC_BPM.boss > Bank.MUSIC_BPM[id], "boss faster than " + id)
		loudness.append(wave_metrics[id].rms_dbfs)
	check(Bank.MUSIC_BPM.boss >= 160, "boss BPM >=160")
	check(loudness.max() - loudness.min() <= 6, "music RMS within +/-3dB")
	for id: String in ENERGY_QUIET_LIMITS:
		check(wave_metrics[id].peak_dbfs <= ENERGY_QUIET_LIMITS[id][0] + 1, id + ": peak no more than 8A +1dB")
		check(wave_metrics[id].rms_dbfs <= ENERGY_QUIET_LIMITS[id][1] + 1, id + ": RMS no more than 8A +1dB")
	report.k_music = {}
	report.k_effects = {}
	var k_levels: Array[float] = []
	for id: String in Bank.MUSIC_IDS:
		var level := k_music_rms_db(streams[id])
		report.k_music[id] = level
		k_levels.append(level)
		check(level >= ENERGY_K_8A_MUSIC.title - 1, id + ": K RMS >= 8A title -1dB")
	check(k_levels.max() - k_levels.min() <= 3, "music K RMS spread <=3dB")
	check(report.k_music.boss >= k_levels.max() - 0.5, "boss K RMS within 0.5dB of loudest")
	for id: String in ENERGY_K_8A_EFFECTS:
		var level := k_effect_max50_db(streams[id])
		var delta: float = level - ENERGY_K_8A_EFFECTS[id]
		report.k_effects[id] = {"db": level, "delta_8a_db": delta}
		var tolerance := ENERGY_K_TOLERANCE_DB
		if id in ENERGY_K_COMBAT:
			check(delta >= 1-tolerance and delta <= 6+tolerance, id + ": K max50ms 8A +1..+6dB (+/-0.5)")
		elif id in ENERGY_K_IMPORTANT:
			check(delta >= -1-tolerance, id + ": K max50ms >= 8A -1dB (+/-0.5)")
		elif id in ["shot_a", "shot_b"]:
			check(delta >= -tolerance and delta <= 3+tolerance, id + ": K max50ms 8A 0..+3dB (+/-0.5)")
		else:
			check(id in ENERGY_K_QUIET, id + ": assigned K quiet category")
			check(delta <= (3 if id == "laser_fire" else 1) + tolerance, id + ": K max50ms quiet ceiling (+/-0.5)")
	var drum_patterns := {}
	var bass_patterns := {}
	var hooks := {}
	for index in range(Bank.MUSIC_IDS.size()):
		var id: String = Bank.MUSIC_IDS[index]
		drum_patterns[str(Bank.MUSIC_KICKS[index])] = true
		bass_patterns[str(Bank.MUSIC_BASS[index])] = true
		hooks[str(Bank.MUSIC_HOOKS[index])] = true
		var has_step := false
		var melody: Array = Bank.MUSIC_HOOKS[index]
		for i in range(1, melody.size()):
			if absi(melody[i][1]-melody[i-1][1]) in [1,2]: has_step = true
		check(has_step and melody[-1][0] >= 16, id + ": two-bar melody contains stepwise motion")
		var pcm: PackedByteArray = streams[id].data
		var bar_bytes := int(round(4*60.0/Bank.MUSIC_BPM[id]*streams[id].mix_rate))*2
		var section := int(round(32*60.0/Bank.MUSIC_BPM[id]*streams[id].mix_rate))*2
		check(pcm.slice(0,bar_bytes) != pcm.slice(section,section+bar_bytes), id + ": bar 9 varies the A section")
	check(drum_patterns.size() == 5 and bass_patterns.size() == 5 and hooks.size() == 5, "five distinct drum/bass/hook patterns")
	check(Bank.MUSIC_SNARES[3] == [8] and Bank.MUSIC_KICKS[4].size() == 8, "region2 halftime / boss eighth-note kicks")
	check(Bank.SOUNDS.loop_up[3] == 10 and Bank.SOUNDS.loop_up[0] == 0.95, "loop_up escalation voice / fixed duration")
	check(Bank.LOOP_UP_INTERVALS == [0,3,6,9,12,15,18,21], "loop_up rising diminished motif, distinct from major rewards")
	benchmark.energy = report

# Checks the filter against BS.1770's 48kHz reference and analytical sine gain,
# then checks circular warm-up, amplitude scaling and sample-wise max-window RMS.
func k_measurement_test() -> void:
	var reference := [PackedFloat64Array([1.53512485958697,-2.69169618940638,1.19839281085285,-1.69065929318241,0.73248077421585]), PackedFloat64Array([1,-2,1,-1.99004745483398,0.99007225036621])]
	var coefficients := k_coefficients(48000)
	for stage in range(2):
		for j in range(5): check(absf(coefficients[stage][j]-reference[stage][j]) < 1e-8, "K biquad matches 48kHz ITU reference")
	for rate: int in [22050,32000]:
		var stream := AudioStreamWAV.new()
		stream.mix_rate = rate
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		var pcm := PackedByteArray()
		pcm.resize(rate*2)
		for i in range(rate): pcm.encode_s16(i*2, roundi(8192*sin(TAU*1000*i/rate)))
		stream.data = pcm
		var gain := 1.0
		var w := TAU*1000/rate
		for c in k_coefficients(rate):
			var nr: float = c[0]+c[1]*cos(w)+c[2]*cos(2*w)
			var ni: float = -c[1]*sin(w)-c[2]*sin(2*w)
			var dr: float = 1+c[3]*cos(w)+c[4]*cos(2*w)
			var di: float = -c[3]*sin(w)-c[4]*sin(2*w)
			gain *= sqrt((nr*nr+ni*ni)/(dr*dr+di*di))
		var measured := k_music_rms_db(stream)
		check(absf(measured-linear_to_db(0.25/sqrt(2)*gain)) < 0.002, "K sine response at " + str(rate))
		var shifted := pcm.slice(137*2)
		shifted.append_array(pcm.slice(0,137*2))
		stream.data = shifted
		check(absf(k_music_rms_db(stream)-measured) < 0.0001, "K circular rotation invariance at " + str(rate))
		for i in range(rate): pcm.encode_s16(i*2, roundi(pcm.decode_s16(i*2)*0.5))
		stream.data = pcm
		check(absf(k_music_rms_db(stream)-measured+6.0206) < 0.002, "K amplitude scaling at " + str(rate))
		stream.data = pcm.slice(0,int(rate*0.065)*2)
		var filtered := k_weighted(stream,false)
		var width := int(round(rate*0.05))
		var maximum := 0.0
		for start in range(filtered.size()-width+1):
			var sq := 0.0
			for i in range(start,start+width): sq += filtered[i]*filtered[i]
			maximum = maxf(maximum,sq/width)
		check(absf(k_effect_max50_db(stream)-linear_to_db(sqrt(maximum))) < 1e-8, "K sliding max equals brute force at " + str(rate))

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	groups[group] = groups.get(group,0)+1
	if not ok:
		failures.append(message)
		printerr("FAIL: ",message)
func frames(count: int = 1) -> void:
	for i in range(count):
		test_progress()
		await physics_frame
		await process_frame
func raw_key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func tap(code: int) -> void:
	raw_key(code,true)
	raw_key(code,false)
func action(id: String) -> void:
	var event := InputEventAction.new()
	event.action = id
	event.pressed = true
	game.player._unhandled_input(event)

func synthesize() -> void:
	bank = Bank.new()
	bank.start()
	while not bank.snapshot().complete:
		test_progress()
		OS.delay_msec(2)
		await process_frame
	streams = bank.collect()
	benchmark.synthesis = bank.snapshot()
	bank.shutdown()
	check(streams.size()==Bank.SOUNDS.size()+5,"all sound IDs synthesized")
	var reference := Bank.new()
	reference.start()
	while not reference.snapshot().complete:
		test_progress()
		OS.delay_msec(2)
		await process_frame
	var twice: Dictionary = reference.collect()
	reference.shutdown()
	var bytes := 0
	for id: String in streams:
		test_progress()
		var stream: AudioStreamWAV = streams[id]
		var pcm := stream.data
		check(pcm == twice[id].data,id+": byte-identical fixed-seed synthesis")
		check(stream.format==AudioStreamWAV.FORMAT_16_BITS and not stream.stereo,id+": mono 16bit PCM")
		var music := Bank.MUSIC_IDS.has(id)
		check(stream.mix_rate >= (22050 if music else 32000),id+": sample rate")
		var seconds := stream.get_length()
		check(seconds >= 24 and seconds <= 48 if music else absf(seconds-float(Bank.SOUNDS[id][0]))<0.001,id+": duration")
		bytes += pcm.size()
		var n := pcm.size()/2
		var peak := 0.0
		var total := 0.0
		var sq := 0.0
		for i in range(n):
			var value := pcm.decode_s16(i*2)/32768.0
			peak = maxf(peak,absf(value))
			total += value
			sq += value*value
		var rms := sqrt(sq/n)
		wave_metrics[id] = {"peak_dbfs":linear_to_db(peak),"rms_dbfs":linear_to_db(rms),"dc":total/n,"bytes":pcm.size(),"seconds":seconds}
		check(peak <= db_to_linear(-3 if music else -1) and peak>0.01,id+": peak and non-silence")
		check(rms > 0.002 and absf(total/n)<0.0002,id+": RMS and DC")
		if music:
			check(stream.loop_begin==0 and stream.loop_end==n and stream.loop_mode==AudioStreamWAV.LOOP_FORWARD,id+": exact loop sample count")
			var jump := absf(pcm.decode_s16(0)-pcm.decode_s16((n-1)*2))/32768.0
			var window := int(stream.mix_rate*0.05)
			var before := 0.0
			var after := 0.0
			for i in range(window):
				before += pow(pcm.decode_s16((n-1-i)*2)/32768.0,2)
				after += pow(pcm.decode_s16(i*2)/32768.0,2)
			var difference := absf(linear_to_db(sqrt(before/window))-linear_to_db(sqrt(after/window)))
			wave_metrics[id].seam_jump = jump
			wave_metrics[id].seam_rms_db = difference
			check(jump<0.025,id+": loop boundary step <0.025")
			check(difference<6,id+": adjacent 50ms RMS difference <6dB")
		else:
			check(pcm.decode_s16(0)==0 and pcm.decode_s16(pcm.size()-2)==0,id+": zero endpoints")
	benchmark.pcm_bytes = bytes
	check(bytes<=32*1024*1024,"PCM <=32 MiB")
	var metrics: Dictionary = benchmark.synthesis.ids
	check(metrics.title.ready_ms<4000,"title ready before 4s")
	check(metrics.amb2_metal.ready_ms<2000,"all effects ready before 2s")
	check(metrics.boss.ready_ms<20000,"total synthesis before 20s")
	for id: String in Bank.MUSIC_IDS: check(metrics[id].ms<4000,id+": synthesis <4s")
	var cancel := Bank.new()
	cancel.start()
	cancel.shutdown()
	check(cancel.thread==null,"cancel joins dedicated synthesis thread")

func startup_test() -> void:
	group="startup"
	var began:=Time.get_ticks_usec()
	var initial:=Main.new()
	initial.controls_path=OUT+"startup-controls.cfg"
	initial.audio_settings_path=OUT+"startup-audio.cfg"
	initial.audio_synthesis_override=1
	initial.set_meta("sound_set_override", "synth")
	root.add_child(initial)
	initial.set_physics_process(false)
	var effects_ready:=0.0
	var title_ready:=0.0
	while not initial.audio.bank.snapshot().complete or initial.audio.streams.size()<Bank.SOUNDS.size()+5:
		test_progress()
		OS.delay_msec(2)
		await process_frame
		if effects_ready==0 and initial.audio.streams.has("amb2_metal"): effects_ready=(Time.get_ticks_usec()-began)/1000.0
		if title_ready==0 and initial.audio.streams.has("title"): title_ready=(Time.get_ticks_usec()-began)/1000.0
	benchmark.startup={"effects_from_scene_ms":effects_ready,"title_from_scene_ms":title_ready,"engine_before_scene_ms":began/1000.0,"effects_from_engine_ms":began/1000.0+effects_ready,"title_from_engine_ms":began/1000.0+title_ready,"setup_ms":initial.audio.setup_ms,"synthesis":initial.audio.bank.snapshot()}
	check(effects_ready>0 and effects_ready<2000,"real main receives all effects within 2s of scene creation")
	check(title_ready>0 and title_ready<4000,"real main receives title within 4s of scene creation")
	check(initial.audio.setup_ms<10,"setup including thread start <10ms")
	check(initial.audio.sound_set == "synth" and initial.audio.asset_loaded.is_empty() and initial.audio.asset_queue.is_empty(), "synth override never queues material imports")
	initial.free()

func settings_test() -> void:
	group = "settings"
	var settings := Settings.new()
	var path := OUT+"audio-test.cfg"
	settings.load_settings(OUT+"missing.cfg")
	check(settings.values==Settings.DEFAULTS,"missing config defaults")
	settings.values={"master":0,"bgm":100,"se":30}
	check(settings.save_settings(path)==OK,"save test-only config")
	settings.load_settings(path)
	check(settings.values=={"master":0,"bgm":100,"se":30},"roundtrip")
	FileAccess.open(path,FileAccess.WRITE).store_string("[audio]\nversion=1\nmaster=150\nbgm=-12\nse=\"broken\"\n")
	settings.load_settings(path)
	check(settings.values=={"master":100,"bgm":0,"se":80},"clamp and per-field fallback")
	FileAccess.open(path,FileAccess.WRITE).store_string("[audio]\nversion=99\nmaster=20\n")
	settings.load_settings(path)
	check(settings.values==Settings.DEFAULTS,"unknown version resets everything")
	FileAccess.open(path,FileAccess.WRITE).store_string("invalid configuration [")
	settings.load_settings(path)
	check(settings.values==Settings.DEFAULTS,"corrupt file defaults")
	for value in [0,10,50,80,100]:
		for key in ["master","bgm","se"]: settings.values[key]=value
		settings.apply()
		for name in ["Master","BGM","SE"]:
			var bus := AudioServer.get_bus_index(name)
			check(AudioServer.is_bus_mute(bus)==(value==0),name+": mute at zero")
			check(absf(AudioServer.get_bus_volume_db(bus)-Settings.db_for(value))<0.001,name+": perceived volume curve")
	game.audio.settings.values = Settings.DEFAULTS.duplicate()
	game.audio.settings.apply()
	game.show_menu("title")
	var count: int = game.audio.request_cursor
	game.ui.show_menu("title")
	check(game.audio.request_cursor==count,"programmatic focus is silent")
	tap(KEY_TAB)
	await frames()
	check(game.audio.history().any(func(e):return e.id=="ui_move"),"menu navigation requests ui_move")
	event_ids.ui_move=true
	game.open_audio_settings()
	var saved_before:=FileAccess.get_file_as_bytes(game.audio_settings_path) if FileAccess.file_exists(game.audio_settings_path) else PackedByteArray()
	await frames()
	check(game.state=="audio_settings" and game.ui.audio_panel.is_visible_in_tree(),"audio panel opens")
	var panel: Control = game.ui.audio_panel
	tap(KEY_LEFT)
	check(game.audio.settings.values.master==70,"left decreases by 10")
	tap(KEY_DOWN)
	tap(KEY_RIGHT)
	check(game.audio.settings.values.bgm==70,"down selects BGM; right increases")
	var old_polarity: int = game.player.polarity
	tap(KEY_K)
	tap(KEY_ENTER)
	check(game.state=="audio_settings" and game.player.polarity==old_polarity,"Enter/gameplay keys cannot leak")
	# Use the real GUI mouse path, not a direct value assignment.
	var slider: HSlider = panel.sliders[2]
	for pressed in [true,false]:
		var mouse := InputEventMouseButton.new()
		mouse.position=slider.get_global_rect().position+Vector2(slider.size.x*0.2,slider.size.y/2)
		mouse.button_index=MOUSE_BUTTON_LEFT
		mouse.pressed=pressed
		root.push_input(mouse,true)
		await frames()
	check(game.audio.settings.values.se<=30,"mouse slider click updates SE")
	var drag_start:=slider.get_global_rect().position+Vector2(slider.size.x*0.2,slider.size.y/2)
	var mouse_down:=InputEventMouseButton.new()
	mouse_down.position=drag_start
	mouse_down.button_index=MOUSE_BUTTON_LEFT
	mouse_down.pressed=true
	root.push_input(mouse_down,true)
	var motion:=InputEventMouseMotion.new()
	motion.position=slider.get_global_rect().position+Vector2(slider.size.x*0.8,slider.size.y/2)
	motion.relative=motion.position-drag_start
	motion.button_mask=MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion,true)
	var mouse_up:=InputEventMouseButton.new()
	mouse_up.position=motion.position
	mouse_up.button_index=MOUSE_BUTTON_LEFT
	mouse_up.pressed=false
	root.push_input(mouse_up,true)
	await frames()
	check(game.audio.settings.values.se>=70,"mouse drag updates SE")
	var saved_during:=FileAccess.get_file_as_bytes(game.audio_settings_path) if FileAccess.file_exists(game.audio_settings_path) else PackedByteArray()
	check(saved_before==saved_during,"volume changes do not write config while panel remains open")
	tap(KEY_ESCAPE)
	check(game.state=="title" and not panel.is_visible_in_tree(),"Esc closes panel without starting game")
	check(root.gui_get_focus_owner()==game.ui.audio_button,"focus returns to audio button")
	var saved := Settings.new()
	saved.load_settings(game.audio_settings_path)
	check(saved.values==game.audio.settings.values,"panel saves only the test settings path")
	game.start_tutorial()
	await frames()
	var practice: Node = game.tutorial_session
	practice.show_menu("paused")
	practice.open_audio_settings()
	check(practice.audio==game.audio and practice.ui.audio_panel.is_visible_in_tree(),"tutorial pause shares host director")
	practice.ui.audio_panel._reset()
	practice.ui.audio_panel._close()
	check(practice.state=="paused" and practice.get_viewport().gui_get_focus_owner()==practice.ui.audio_button,"tutorial closes to pause and restores focus")
	game.finish_tutorial()
	await frames()

func expect(id: String, callback: Callable, point: Variant = null) -> void:
	var cursor: int = game.audio.request_cursor
	var frame := Engine.get_physics_frames()
	callback.call()
	var history: Array = game.audio.history()
	var count: int = game.audio.request_cursor-cursor
	var matching: Array = history.slice(maxi(0,history.size()-count)).filter(func(e):return e.id==id)
	check(not matching.is_empty(),id+": actual event calls audio")
	if matching.is_empty(): return
	event_ids[id] = true
	check(matching.all(func(e):return e.frame==frame),id+": same physics frame")
	if point is Vector2: check(matching[0].position==point,id+": event position")

func make_enemy(kind: String, point: Vector2) -> Node:
	var actor := Enemy.new()
	actor.game=game
	actor.kind=kind
	actor.spawn_id="audio:%d" % game.world.get_child_count()
	actor.position=point
	if kind=="boss": actor.boss_id=9999
	game.world.add_child(actor)
	actor.set_physics_process(false)
	return actor

func event_test() -> void:
	group="events"
	game.start_run(37)
	game.set_physics_process(false)
	game.world.process_mode=Node.PROCESS_MODE_DISABLED
	var player: Node = game.player
	var point: Vector2 = player.position
	game.audio.streams=streams.duplicate()
	expect("shot",func(): player.fire_normal(),point)
	player.equipment.weapon="triple"
	var cursor: int=game.audio.request_cursor
	var bullets: int=game.projectiles.get_child_count()
	player.fire_normal()
	check(game.projectiles.get_child_count()-bullets==3 and game.audio.request_cursor-cursor==1,"triple shot is one sound request")
	expect("switch",func():action("switch_color"),point)
	expect("aim",func():action("aim_cycle"),point)
	expect("empty",func():player.launch_homing(),point)
	expect("charge",func():player.add_homing_charges(2),point)
	cursor=game.audio.request_cursor
	bullets=game.projectiles.get_child_count()
	expect("homing",func():player.launch_homing(),point)
	check(game.projectiles.get_child_count()-bullets==4 and game.audio.request_cursor-cursor==1,"homing volley is one sound request")
	expect("absorb",func():player.receive_hit(player.polarity,12),point)
	expect("hurt",func():player.receive_hit(1-player.polarity,12),point)
	expect("heal",func():player.heal(5),point)
	game.potions=1
	expect("potion",func():game.use_potion(),point)
	var enemy:=make_enemy("turret",point+Vector2(180,0))
	expect("enemy_hit",func():enemy.receive_hit(1-enemy.polarity,1),enemy.position)
	expect("enemy_absorb",func():enemy.receive_hit(enemy.polarity,1),enemy.position)
	expect("enemy_warn",func():enemy._begin("windup_shot",0.3),enemy.position)
	expect("enemy_warn_special",func():enemy._begin("windup_special",0.4),enemy.position)
	expect("enemy_shot",func():game.spawn_bullet(enemy,Vector2.LEFT),enemy.position)
	expect("enemy_homing",func():game.fire_special(enemy,4),enemy.position)
	enemy.next_polarity=1
	enemy.action="windup_switch"
	expect("enemy_switch",func():enemy._complete_action(),enemy.position)
	expect("enemy_defeat",func():enemy.receive_hit(1-enemy.polarity,999),enemy.position)
	var enhancer:=make_enemy("enhancer",point+Vector2(200,0))
	expect("enhancer_defeat",func():enhancer.receive_hit(1-enhancer.polarity,999),enhancer.position)
	check(game.audio.history().any(func(e):return e.id=="arrow_unlock"),"enhancer defeat unlock announcement sound")
	event_ids.arrow_unlock=true
	var boss:=make_enemy("boss",point+Vector2(240,0))
	boss.boss_role="secret"
	boss.action="windup_shot"
	bullets=game.projectiles.get_child_count()
	cursor=game.audio.request_cursor
	expect("boss_shot",func():boss._complete_action(),boss.position)
	check(game.projectiles.get_child_count()-bullets==8 and game.audio.request_cursor-cursor==1,"seven-way boss shot plus homing is one sound")
	expect("boss_hit",func():boss.receive_hit(1-boss.polarity,1),boss.position)
	# Avoid starting a boss placement job: valid defeat hook, complete phase stays inert.
	game.boss_cycle.phase="complete"
	expect("boss_defeat",func():boss.receive_hit(1-boss.polarity,9999),boss.position)
	expect("loop_up",func():game.update_loop_scaling())
	var laser:=make_enemy("laser",point+Vector2(210,0))
	var beam: Node
	cursor=game.audio.request_cursor
	beam=game.spawn_laser(laser)
	check(game.audio.history().back().id=="laser_charge" and game.audio.history().back().frame==Engine.get_physics_frames(),"laser warning start in same frame")
	event_ids.laser_charge=true
	expect("laser_fire",func():beam.fire(),laser.position)
	beam.cancel()
	var bomb: Node=game.spawn_bomb_warning(laser)
	check(game.audio.history().back().id=="bomb_warn","bomb warning sound")
	event_ids.bomb_warn=true
	bomb.position=point+Vector2(350,0)
	expect("bomb_explode",func():bomb.detonate(),bomb.position)
	expect("block_break",func():game._block_removed(Rect2(point-Vector2.ONE*16,Vector2.ONE*32),false),point)
	expect("crystal",func():game.add_crystals(30),point)
	var key:=Loot.new()
	key.game=game
	key.position=point
	key.spawn={"id":"audio-key","kind":"key"}
	game.world.add_child(key)
	expect("key",func():key.try_collect(),point)
	var chest:=Loot.new()
	chest.game=game
	chest.position=point
	chest.spawn={"id":"audio-chest","kind":"chest","contents":[{"kind":"potion"}]}
	game.world.add_child(chest)
	game.keys=0
	expect("chest_locked",func():chest.try_open(),point)
	game.keys=1
	expect("chest_open",func():chest.try_open(),point)
	check(game.audio.history().any(func(e):return e.id=="item_get"),"chest item acquisition")
	event_ids.item_get=true
	expect("ability_get",func():game.grant_loot({"kind":"ability","ability":T.ABILITY_DOUBLE}),point)
	var merchant: Node=game.nearest_merchant()
	if merchant==null:
		for candidate in get_nodes_in_group("merchants"):
			if candidate.get_parent()==game.world: merchant=candidate; break
	player.position=merchant.position
	expect("shop_open",func():game.open_shop(merchant))
	game.crystals=9999
	expect("buy",func():game.buy_item("rapid"))
	game.last_shop_action_ms=-1000
	expect("deny",func():game.buy_item("rapid"))
	expect("equip",func():game.equip("weapon","rapid"))
	expect("ui_back",func():game.close_shop())
	game.ending=false
	expect("map_open",func():game.open_map())
	expect("map_close",func():game.close_map())
	expect("pause",func():game.show_menu("paused"))
	expect("ui_confirm",func():game.open_key_settings())
	game.close_key_settings()
	game.resume_run()
	player.invulnerability=0
	expect("death",func():player.receive_hit(1-player.polarity,9999))
	await frames()
	check(game.state=="lost","actual death reaches lost screen")
	# Physics-triggered movement uses the existing movement driver fixture below.
	await movement_events()

func movement_events() -> void:
	game.start_run(37)
	game.set_physics_process(false)
	game.streaming_enabled=false
	game.world.process_mode=Node.PROCESS_MODE_INHERIT
	for child in game.world.get_children(): child.set_physics_process(false)
	var floor_body:=StaticBody2D.new()
	var shape:=CollisionShape2D.new()
	var rect:=RectangleShape2D.new()
	rect.size=Vector2(1000,100)
	shape.shape=rect
	floor_body.position=Vector2(1000,-1000)
	floor_body.add_child(shape)
	game.world.add_child(floor_body)
	var p: Node=game.player
	p.position=Vector2(1000,-1072)
	p.velocity=Vector2.ZERO
	await frames(2)
	p._physics_process(1.0/60)
	await frames()
	p.jump_buffer=0.1
	expect("jump",func():p._physics_process(1.0/60),p.position)
	p.abilities=T.ABILITY_DOUBLE|T.ABILITY_DASH|T.ABILITY_GLIDE
	p.jump_buffer=0.1
	expect("air_jump",func():p._physics_process(1.0/60),p.position)
	p.pending_dash=true
	expect("dash",func():p._physics_process(1.0/60),p.position)
	p.dash_remaining=0
	p.velocity=Vector2(0,80)
	Input.action_press("jump")
	expect("glide",func():p._physics_process(1.0/60))
	Input.action_release("jump")
	var cursor: int=game.audio.request_cursor
	for i in range(150):
		p._physics_process(1.0/60)
		await frames()
	check(game.audio.history().any(func(e):return e.id=="land"),"real falling collision requests land")
	if game.audio.request_cursor>cursor: event_ids.land=true
	var fixture:=Terrain.new()
	fixture.stage={"bounds":Rect2(0,-1400,4096,1500),"solids":[Rect2(0,-1024,4096,128)],"breakables":[],"protected_rects":[]}
	game.world.add_child(fixture)
	fixture.sound_requested.connect(game.play_sound)
	var plan:=Rect2(1504,-1120,32,96)
	var wall_id: int=fixture.next_wall_id
	expect("wall_place",func():fixture.place_wall(plan,987654),plan.get_center())
	expect("wall_vanish",func():fixture.remove_wall(wall_id),plan.get_center())
	fixture.free()
	game.boss_cycle.phase="final"
	var roles: Array[String]=["final"]
	game.boss_cycle.request(roles)
	check(await wait_until(func():return WorkerThreadPool.is_task_completed(game.boss_cycle.selection.task_id),30),"boss placement job finishes")
	expect("boss_appear",func():game.boss_cycle.service())

func overlap_test() -> void:
	group="overlap"
	game.audio.enabled=true
	game.audio.streams=streams.duplicate()
	game.state="playing"
	var audio: Node=game.audio
	audio.stop_world()
	audio.clock_ms+=1000
	var at: Vector2=game.view_rect().get_center()
	var handle: int=game.play_sound("shot",at,0,1,0)
	check(handle>=0,"synthesized sound plays")
	game.play_sound("shot",at,0,1,0)
	check(audio.history().back().reason=="same_frame","same frame merges same ID")
	await frames()
	game.play_sound("shot",at,0,1,0)
	check(audio.history().back().reason=="interval","minimum interval")
	audio.clock_ms+=1000
	game.play_sound("enemy_hit",at+Vector2(2000,0))
	check(audio.history().back().reason=="offscreen","half-screen beyond view is silent")
	var count :=0
	for id: String in Bank.SOUNDS:
		if id.begins_with("amb") or id.ends_with("_a") or id.ends_with("_b") or audio.PRIORITY.has(id) or id.begins_with("ui_"): continue
		audio.last_frame.clear()
		audio.last_id.clear()
		game.play_sound(id,at)
		count+=1
	for id in ["hurt","absorb","ui_confirm"]:
		audio.last_frame.erase(id)
		audio.last_id.erase(id)
		game.play_sound(id,null,0,1,0)
		check(audio.history().back().played,id+": priority survives enemy saturation")
	var active :=0
	for voice: Dictionary in audio.voices:
		if voice.until>audio.clock_ms: active+=1
	check(active<=32,"global polyphony <=32")
	# Fill every reserved/general slot with long priority voices, then verify
	# that a new ordinary sound is actually refused by the global capacity.
	for id: String in audio.PRIORITY+["ui_move","ui_confirm","ui_back"]:
		for repeat in range(2):
			audio.last_frame.erase(id)
			audio.last_id.erase(id)
			game.play_sound(id,null,0,0.25,0)
	active=0
	for voice: Dictionary in audio.voices:
		if voice.until>audio.clock_ms: active+=1
	check(active==32,"test really saturates all32 voices")
	audio.last_frame.erase("enemy_shot")
	audio.last_id.erase("enemy_shot")
	game.play_sound("enemy_shot",at)
	check(audio.history().back().reason=="voice_limit","global capacity rejects an extra ordinary sound")
	for voice: Dictionary in audio.voices: audio.stop_handle(voice.handle)
	audio.stop_world()
	audio.last_id.clear()
	for i in range(5):
		audio.clock_ms+=41
		audio.last_frame.erase("shot")
		game.play_sound("shot",at,0,0.25,0)
	check(audio.history().back().reason=="id_limit","shot polyphony <=4")
	audio.clock_ms+=1000
	audio.last_frame.clear()
	handle=game.play_sound("laser_charge",at)
	game.show_menu("paused")
	await frames(2)
	check(audio.voices[handle%32].player.stream_paused,"pause suspends world SE")
	game.resume_run()
	game.streaming_wait=true
	await frames(2)
	check(not audio.voices[handle%32].player.stream_paused,"streaming wait does not chop audio")
	game.streaming_wait=false
	var before: Vector2=audio.voices[handle%32].point
	audio.shift_origin(game,Vector2(-4096,0))
	check(audio.voices[handle%32].point==before+Vector2(-4096,0),"active source shifts with origin")
	audio.stop_handle(handle)
	check(audio.voices[handle%32].until==0,"cancel laser stops its voice")
	game.return_to_title()
	check(audio.voices.all(func(v):return not v.world or v.until==0),"return title clears world voices")
	game.play_sound("jump",at)
	check(audio.history().back().reason=="state","background title run stays silent")
	for i in range(600): game.play_sound("ui_move")
	check(audio.history().size()==512,"request ring bounded at512")

func music_test() -> void:
	group="music"
	var audio: Node=game.audio
	game.show_menu("title")
	audio._process(0.1)
	check(audio.requested_music=="title","title music")
	game.start_run(37)
	game.set_physics_process(false)
	game.world.process_mode=Node.PROCESS_MODE_DISABLED
	audio._process(0.1)
	check(audio.requested_music=="region%d"%game.biome_at(game.camera.position),"start selects starting region")
	audio._process(3.1)
	var original_slot: int=audio.music_slot
	var original_id: String=audio.current_music
	audio.music[original_slot].seek(4.0)
	OS.delay_msec(50)
	audio.set_music("region%d"%((game.biome_at(game.camera.position)+1)%3),3.0)
	audio.music_gain[original_slot]=0.8
	audio.music_gain[1-original_slot]=0.2
	audio.set_music(original_id,3.0)
	OS.delay_msec(50)
	check(audio.music_slot==original_slot and audio.music[original_slot].get_playback_position()>3.9,"reversing region fade preserves actual playback position")
	audio._process(3.1)
	var old_region: int=audio.region
	# Find a real adjacent-sector boundary with different region classification.
	var s: GDScript=preload("res://scripts/sector_generator.gd")
	var found :=false
	var boundary_seed:=0
	var left:=Vector2i.ZERO
	for value in range(100):
		if found: break
		for x in range(-8,9):
			if s.region_at(value,Vector2i(x,0))!=s.region_at(value,Vector2i(x+1,0)):
				boundary_seed=value
				left=Vector2i(x,0)
				found=true
				break
	check(found,"find deterministic adjacent biomes")
	game.current_seed=boundary_seed
	game.camera.position=(Vector2(left)+Vector2(0.5,0.5))*T.SECTOR_SIZE
	audio.region=game.biome_at(game.camera.position)
	old_region=audio.region
	audio.candidate_region=old_region
	var right_point: Vector2=(Vector2(left+Vector2i.RIGHT)+Vector2(0.5,0.5))*T.SECTOR_SIZE
	for i in range(8):
		game.camera.position=right_point if i%2==0 else right_point-T.SECTOR_SIZE*Vector2.RIGHT
		audio._process(0.3)
	check(audio.region==old_region,"boundary oscillation does not switch music")
	game.camera.position=right_point
	for i in range(18): audio._process(0.1)
	check(audio.region==game.biome_at(right_point) and audio.fade_seconds==3,"1.5s stable biome starts 3s crossfade")
	var boss:=make_enemy("boss",right_point)
	audio._process(0.1)
	check(not audio.boss_music,"boss must remain visible 0.3s")
	audio._process(0.21)
	check(audio.boss_music and audio.requested_music=="boss" and audio.fade_seconds==1,"boss entry music")
	boss.position+=Vector2(3000,0)
	audio._process(3.9)
	check(audio.boss_music,"boss exit hysteresis")
	audio._process(0.2)
	check(not audio.boss_music and audio.fade_seconds==2.5,"4s outside returns to biome")
	boss.position=right_point
	audio._process(0.31)
	boss.dead=true
	audio.boss_defeated()
	audio._process(0.01)
	check(not audio.boss_music and audio.requested_music.begins_with("region"),"boss defeat returns immediately")
	for state in ["paused", "map", "shop", "equipment", "settings", "audio_settings"]:
		game.state=state
		audio._process(0.25)
		check(is_equal_approx(audio.duck_db, 0 if state == "audio_settings" else -10), state + ": panel uses normal BGM, other modals duck -10dB")
		game.state="playing"
		audio._process(0.25)
		check(is_zero_approx(audio.duck_db),state+": restore BGM")
	for state in ["lost","won"]:
		game.show_menu(state)
		audio._process(0.01)
		check(audio.music_target==[0.0,0.0] and audio.fade_seconds==0.5,state+": BGM fade")
		game.open_audio_settings()
		audio._process(0.1)
		check(audio.music_target==[0.0,0.0],state+": modal settings do not resurrect ended BGM")
		game.ui.audio_panel._close()
		audio._process(0.01)
		check(audio.ending_id==("lose" if state=="lost" else "win") and audio.ending_timer<1.5,state+": settings preserve jingle phase")
		audio._process(1.6)
		check(audio.history().back().id==("lose" if state=="lost" else "win"),state+": delayed jingle")
		event_ids["lose" if state=="lost" else "win"]=true
		audio._process(4)
		check(audio.requested_music=="title" and audio.ending_started,state+": quieter title after jingle")
	game.show_menu("lost")
	audio._process(0.01)
	game.open_audio_settings()
	audio._process(1.0)
	audio._process(3.0)
	check(audio.requested_music=="title" and audio.ending_started,"result sequence continues to title inside audio settings")
	game.ui.audio_panel._close()
	game.state="playing"
	for region_id in range(3):
		var selected:=false
		for x in range(-20,21):
			var p:=Vector2(x,0)*T.SECTOR_SIZE+T.SECTOR_SIZE/2
			if game.biome_at(p)==region_id: game.camera.position=p; selected=true; break
		check(selected,"find ambient region %d"%region_id)
		audio.ambient_in=0
		audio._process(0.1)
		check(audio.history().back().id.begins_with("amb%d_"%region_id),"ambient only in current biome")
		check(audio.ambient_in>=3 and audio.ambient_in<=9,"irregular ambient interval 3..9s")
	game.start_tutorial()
	await frames()
	audio._process(0.1)
	check(audio.requested_music=="title","tutorial uses title music")
	var p: Node=game.tutorial_session
	await frames(12)
	var jump_cursor: int=audio.request_cursor
	tap(KEY_SPACE)
	await frames(2)
	var jump_events: Array=audio.history().slice(-int(audio.request_cursor-jump_cursor))
	check(jump_events.any(func(e):return e.id=="jump" and e.position is Vector2),"tutorial physical jump routes to host")
	var cursor: int=audio.request_cursor
	p.player.fire_normal()
	p.player.receive_hit(p.player.polarity,12)
	p.complete_lesson()
	var recent: Array=audio.history().slice(-int(audio.request_cursor-cursor))
	check(recent.any(func(e):return e.id=="shot") and recent.any(func(e):return e.id=="absorb"),"tutorial shot and absorb route to host")
	check(recent.any(func(e):return e.id=="tutorial_step"),"tutorial task achievement")
	check(recent.any(func(e):return e.id=="shot" and e.pan<0),"tutorial uses its own view for left panning")
	event_ids.tutorial_step=true
	game.finish_tutorial()
	await frames()

func music_levels() -> Array[float]:
	return [db_to_linear(game.audio.music[0].volume_db), db_to_linear(game.audio.music[1].volume_db)]

func trace_music(label: String, count: int, previous: Array[float] = []) -> void:
	var audio: Node = game.audio
	if previous.is_empty(): previous = music_levels()
	for frame in range(count):
		test_progress()
		var old_ids: Array = audio.music_ids.duplicate()
		audio._process(1.0 / 60)
		var levels := music_levels()
		for slot in range(2):
			check(levels[slot] - previous[slot] <= 0.100001, label + ": amplitude rise <=0.1 frame %d slot %d" % [frame, slot])
			if audio.music_target[slot] == 0 and audio.music_ids[slot] == old_ids[slot]:
				check(levels[slot] <= previous[slot] + 0.000001, label + ": outgoing never rises frame %d slot %d" % [frame, slot])
		music_trace.append({"case": label, "frame": frame, "state": game.state, "ids": audio.music_ids.duplicate(), "target": audio.music_target.duplicate(), "db": [audio.music[0].volume_db, audio.music[1].volume_db]})
		previous = levels

func freeze_run() -> void:
	game.set_physics_process(false)
	game.world.process_mode = Node.PROCESS_MODE_DISABLED

func warning_ids(cursor: int) -> Array:
	var recent: Array = game.audio.history().slice(-int(game.audio.request_cursor - cursor))
	return recent.filter(func(e): return e.id in ["enemy_warn", "enemy_warn_special", "laser_charge", "bomb_warn"]).map(func(e): return e.id)

func terrain_signal_test(source: Node) -> void:
	var terrain: Node = source.terrain
	check(terrain.sound_requested.is_connected(source.play_sound), "terrain sound signal connected to source play_sound")
	var bounds := Rect2()
	for cell: Vector2i in terrain.occupied:
		var candidate := Rect2(terrain.pixel_of_cell(cell) - Vector2(0, 96), Vector2(32, 96))
		if terrain.can_place_wall(candidate, -888):
			bounds = candidate
			break
	check(bounds.has_area(), "real terrain has supported unoccupied wall site")
	var emitted: Array = []
	var listener := func(id, point): emitted.append([id, point])
	terrain.sound_requested.connect(listener)
	var cursor: int = game.audio.request_cursor
	var wall: int = terrain.place_wall(bounds, -888)
	check(wall >= 0, "terrain fixture places real wall")
	terrain.remove_wall(wall)
	var recent: Array = game.audio.history().slice(-int(game.audio.request_cursor - cursor))
	check(emitted == [["wall_place", bounds.get_center()], ["wall_vanish", bounds.get_center()]], "wall signal timing and positions preserved")
	check(recent.map(func(e): return e.id) == ["wall_place", "wall_vanish"], "both wall signals reach host request history")
	check(recent.all(func(e): return e.position == bounds.get_center() and e.frame == Engine.get_physics_frames()), "wall history preserves position and physics frame")
	terrain.sound_requested.disconnect(listener)

func sound_regression_test() -> void:
	var audio: Node = game.audio
	audio.set_process(false)
	group = "sound_warnings"
	game.start_run(37)
	freeze_run()
	for kind in ["laser", "breaker", "turret", "shifter", "builder", "special"]:
		var actor := make_enemy("turret" if kind == "special" else kind, game.player.position + Vector2(180, 0))
		actor.shot_clock = 0
		actor.switch_clock = 100
		var cursor: int = audio.request_cursor
		if kind == "special": actor.gauge = T.GAUGE_CAPACITY
		if kind == "shifter": actor.switch_clock = 0
		if kind == "builder":
			# _choose_build depends on nearby occupancy; test its committed warning.
			actor._begin("windup_build", T.BUILD_WARNING)
		else:
			actor._choose_attack(1.0 / 60)
		var expected: String = {"laser": "laser_charge", "breaker": "bomb_warn", "special": "enemy_warn_special"}.get(kind, "enemy_warn")
		check(warning_ids(cursor) == [expected], kind + ": exactly one warning request")
		var recent: Array = audio.history().slice(-int(audio.request_cursor - cursor))
		check(recent.all(func(e): return e.frame == Engine.get_physics_frames()), kind + ": warning on attack frame")
		actor.cancel_attack()
	group = "terrain_signals"
	terrain_signal_test(game)
	game.start_tutorial()
	await frames()
	game.tutorial_session.set_physics_process(false)
	terrain_signal_test(game.tutorial_session)
	game.finish_tutorial()
	await frames()
	var terrain_text := FileAccess.get_file_as_string("res://scripts/world_terrain.gd")
	check(not terrain_text.contains("func _sound(") and not terrain_text.contains('has_method("play_sound")'), "terrain never searches parents for sound API")
	group = "volume_panel"
	for state in ["title", "paused", "lost", "won"]:
		audio.enabled = false
		audio.enabled = true
		audio.reset_run()
		game.start_run(37)
		freeze_run()
		trace_music(state + " initial gameplay", 200)
		game.show_menu(state)
		trace_music(state + " setup", 600)
		var slot: int = audio.music_slot
		var expected := -10.0 if state == "paused" else (-9.0 if state in ["lost", "won"] else 0.0)
		check(is_equal_approx(audio.music[slot].volume_db, expected), state + ": initial attenuation")
		game.state = "playing"
		audio.last_frame.clear()
		audio.last_id.clear()
		var handle: int = game.play_sound("laser_charge", game.camera.position, 0, 0.25)
		game.state = state
		game.open_audio_settings()
		trace_music(state + " panel opening", 1)
		check(audio.music[slot].volume_db < -0.01 if expected < 0 else is_zero_approx(audio.music[slot].volume_db), state + ": opening has no instant unduck")
		check(handle >= 0 and audio.voices[handle % 32].player.stream_paused, state + ": panel keeps world voice paused")
		trace_music(state + " panel", 30)
		check(is_zero_approx(audio.music[slot].volume_db), state + ": panel reaches unattenuated BGM")
		check(audio.voices[handle % 32].player.stream_paused, state + ": world voice stays paused throughout panel")
		game.ui.audio_panel._close()
		trace_music(state + " closing first frame", 1)
		check(audio.music[slot].volume_db > expected + 0.01 if expected < 0 else is_zero_approx(audio.music[slot].volume_db), state + ": closing has no instant duck")
		trace_music(state + " closed", 30)
		check(is_equal_approx(audio.music[slot].volume_db, expected), state + ": original attenuation restored")
	group = "result_transitions"
	for state in ["lost", "won"]:
		for destination in ["retry", "new", "title"]:
			audio.reset_run()
			game.start_run(37)
			freeze_run()
			trace_music(state + " " + destination + " gameplay", 200)
			game.show_menu(state)
			trace_music(state + " " + destination + " result", 600)
			var slot: int = audio.music_slot
			check(audio.music_ids[slot] == "title" and is_equal_approx(audio.music[slot].volume_db, -9), state + ": result title at -9dB")
			var previous := music_levels()
			var seed_before: int = game.current_seed
			if destination == "retry": game.primary_action()
			elif destination == "new": game.new_action()
			else: game.return_to_title()
			freeze_run()
			trace_music(state + " -> " + destination, 59, previous)
			if destination == "title":
				check(audio.music[slot].volume_db < -0.01, state + ": title recovery takes at least 1s")
				check(audio.music_ids[slot] == "title" and audio.music_target[slot] == 1, state + ": same title continues")
			else:
				check(audio.music_target[slot] == 0 and audio.music[slot].volume_db < -9, state + ": retry title only fades down")
				check(game.current_seed == seed_before if destination == "retry" else game.current_seed != seed_before, destination + ": actual menu action executed")
			trace_music(state + " -> " + destination + " settle", 181)
			check(is_zero_approx(audio.music[audio.music_slot].volume_db), destination + ": incoming or continuing music reaches normal volume")
			if destination != "title": check(not audio.music[slot].playing, destination + ": outgoing title stops")
	group = "music_rise"
	# A retry before the regional PCM is ready must retain the quiet title.
	audio.reset_run()
	game.show_menu("lost")
	trace_music("pending retry result", 600)
	var pending_slot: int = audio.music_slot
	var saved_streams: Dictionary = audio.streams.duplicate()
	for id: String in Bank.MUSIC_IDS:
		if id != "title": audio.streams.erase(id)
	game.primary_action()
	freeze_run()
	trace_music("retry awaiting synthesis", 90)
	check(is_equal_approx(audio.music[pending_slot].volume_db, -9), "retry keeps old title quiet while awaiting synthesis")
	audio.streams = saved_streams
	trace_music("retry after synthesis", 240)
	check(not audio.music[pending_slot].playing, "pending retry eventually stops outgoing title")
	game.state = "title"
	for id in ["region0", "boss", "title"]:
		audio.set_music(id, 1.0)
		# Pause selection on a modal while manually selecting each fade.
		game.state = "audio_settings"
		trace_music("ordinary fade " + id, 90)
		game.state = "paused"
		trace_music("pause " + id, 30)
		game.state = "audio_settings"
		trace_music("unduck " + id, 30)
	audio.enabled = false
	check(audio.music.all(func(p): return not p.playing), "disabled stops every BGM player")
	audio.enabled = true
	audio.set_process(true)

func state_bytes() -> PackedByteArray:
	var p: Node=game.player
	var enemies: Array=[]
	for child in game.world.get_children():
		if child is Enemy and not child.is_queued_for_deletion(): enemies.append([child.spawn_id,child.position,child.velocity,child.hp,child.gauge,child.polarity,child.dead,child.action,child.action_remaining,child.shot_clock])
	enemies.sort_custom(func(a,b):return a[0]<b[0])
	var bullets: Array=[]
	for shot in game.projectiles.get_children():
		if not shot.is_queued_for_deletion(): bullets.append([shot.position,shot.get("direction"),shot.get("polarity"),shot.get("faction")])
	return var_to_bytes([p.position,p.velocity,p.hp,p.gauge,p.homing_charges,p.polarity,p.aim_index,p.abilities,p.equipment,enemies,bullets,game.score,game.crystals,game.keys,game.loot_taken,game.kills,game.elapsed])

func replay(with_audio: bool) -> Array[PackedByteArray]:
	seed(821731)
	game.start_run(37)
	game.set_physics_process(false)
	game.streaming_enabled=false
	game.world.process_mode=Node.PROCESS_MODE_INHERIT
	for child in game.world.get_children(): child.set_physics_process(false)
	game.audio.enabled=with_audio
	game.audio.streams=streams.duplicate() if with_audio else {}
	# Confine the script to already loaded sectors; no asynchronous completion enters state.
	var output: Array[PackedByteArray]=[]
	var p: Node=game.player
	for frame in range(1800):
		test_progress()
		p.invulnerability=10000 # Only scripted damage participates in this repeatable route.
		if frame%120==0:
			Input.action_release("move_left")
			Input.action_release("move_right")
			Input.action_press("move_right" if frame%240==0 else "move_left")
		if frame%60==0: p.jump_buffer=0.1
		if frame%90==0: action("switch_color")
		if frame%130==0: p.receive_hit(p.polarity,12)
		if frame%180==1:
			p.invulnerability=0
			p.receive_hit(1-p.polarity,1)
		if frame%100==0: p.heal(2)
		if frame==20:
			var enemy:=make_enemy("turret",p.position+Vector2(180,0))
			enemy.receive_hit(1-enemy.polarity,999)
		if frame==30:
			game.keys=1
			var chest:=Loot.new()
			chest.game=game
			chest.position=p.position
			chest.spawn={"id":"replay-chest","kind":"chest","contents":[{"kind":"crystal","amount":40}]}
			game.world.add_child(chest)
			chest.try_open()
		Input.action_press("shoot") if frame%40<20 else Input.action_release("shoot")
		# Drive real handlers at fixed physics delta; tree callbacks remain disabled.
		game._physics_process(1.0/60)
		p._physics_process(1.0/60)
		for enemy in game.world.get_children():
			if enemy is Enemy and not enemy.dead and not enemy.is_queued_for_deletion(): enemy._physics_process(1.0/60)
		for shot in game.projectiles.get_children():
			shot.set_physics_process(false)
			if not shot.is_queued_for_deletion(): shot._physics_process(1.0/60)
		output.append(state_bytes())
		await frames()
	Input.action_release("shoot")
	Input.action_release("move_left")
	Input.action_release("move_right")
	return output

func replay_test() -> void:
	group="invariance"
	game.audio.process_usec_total=0
	game.audio.process_usec_max=0
	game.audio.process_samples=0
	game.audio.play_usec_total=0
	game.audio.play_usec_max=0
	game.audio.play_samples=0
	game.audio.pending_play_usec=0
	game.audio.frame_work_usec_total=0
	game.audio.frame_work_usec_max=0
	var a: Array=await replay(false)
	var b: Array=await replay(false)
	for i in range(1800): check(a[i]==b[i],"disabled/disabled exact state frame %d"%i)
	var c: Array=await replay(true)
	for i in range(1800): check(a[i]==c[i],"disabled/synthesized exact state frame %d"%i)
	game.audio.enabled=true
	benchmark.director=game.audio.measurements()

func stress_test() -> void:
	group="stress"
	game.start_run(37)
	game.set_physics_process(false)
	game.world.process_mode=Node.PROCESS_MODE_DISABLED
	game.audio.streams=streams.duplicate()
	game.audio.enabled=true
	var audio: Node=game.audio
	var at: Vector2=game.camera.position
	var enemies: Array[Node]=[]
	for i in range(96): enemies.append(make_enemy("turret",at+Vector2((i%12-6)*55,(i/12-4)*40)))
	audio.process_usec_total=0
	audio.process_usec_max=0
	audio.process_samples=0
	audio.play_usec_total=0
	audio.play_usec_max=0
	audio.play_samples=0
	audio.pending_play_usec=0
	audio.frame_work_usec_total=0
	audio.frame_work_usec_max=0
	var max_voices:=0
	for frame in range(180):
		for i in range(enemies.size()):
			var enemy: Node=enemies[i]
			if frame%30==i%30: game.spawn_bullet(enemy,Vector2.LEFT)
			if frame%40==i%40: enemy.receive_hit(enemy.polarity,1)
			if frame%90==i%90: game.add_crystals(1)
		if frame%30==0: game.play_sound("hurt",at)
		if frame%20==0: game.play_sound("absorb",at,0,1,0)
		if frame%12==0: game.play_sound("ui_move")
		var active:=0
		for voice: Dictionary in audio.voices:
			if voice.until>audio.clock_ms: active+=1
		max_voices=maxi(max_voices,active)
		await frames()
	check(max_voices<=32,"96-enemy stress obeys global limit")
	check(audio.history().any(func(e):return e.id=="hurt" and e.played),"stress hurt audible")
	check(audio.history().any(func(e):return e.id=="absorb" and e.played),"stress absorption audible")
	check(audio.history().any(func(e):return e.id=="ui_move" and e.played),"stress UI audible")
	benchmark.stress=audio.measurements()
	benchmark.stress.enemies=96
	benchmark.stress.frames=180
	benchmark.stress.max_voices=max_voices

# Decode imported QOA through the engine mixer for a separate post-import check.
# The source-WAV measurements below stay at 44100Hz; this probe uses mix rate.
static func decoded_pcm(stream: AudioStream) -> AudioStreamWAV:
	var rate := int(AudioServer.get_mix_rate())
	var count := int(round(stream.get_length() * rate))
	var playback := stream.instantiate_playback()
	playback.start()
	var pcm := PackedByteArray()
	pcm.resize(count * 4)
	var offset := 0
	while offset < count:
		var block := playback.mix_audio(1.0, mini(4096, count-offset))
		if block.is_empty(): break
		for value in block:
			pcm.encode_s16(offset*4, clampi(int(round(value.x*32768)), -32768, 32767))
			pcm.encode_s16(offset*4+2, clampi(int(round(value.y*32768)), -32768, 32767))
			offset += 1
	playback.stop()
	var result := AudioStreamWAV.new()
	result.format = AudioStreamWAV.FORMAT_16_BITS
	result.stereo = true
	result.mix_rate = rate
	result.data = pcm
	return result

func assets_test() -> void:
	group = "assets"
	var sine := AudioStreamWAV.new()
	sine.format = AudioStreamWAV.FORMAT_16_BITS
	sine.mix_rate = 44100
	var mono := PackedByteArray()
	var stereo := PackedByteArray()
	mono.resize(44100*2)
	stereo.resize(44100*4)
	for i in range(44100):
		var sample := roundi(8192*sin(TAU*1000*i/44100))
		mono.encode_s16(i*2, sample)
		stereo.encode_s16(i*4, sample)
		stereo.encode_s16(i*4+2, sample)
	sine.data = mono
	var mono_level := k_music_rms_db(sine)
	var analytical_gain := 1.0
	var frequency := TAU*1000/44100
	for c in k_coefficients(44100):
		var nr: float = c[0]+c[1]*cos(frequency)+c[2]*cos(2*frequency)
		var ni: float = -c[1]*sin(frequency)-c[2]*sin(2*frequency)
		var dr: float = 1+c[3]*cos(frequency)+c[4]*cos(2*frequency)
		var di: float = -c[3]*sin(frequency)-c[4]*sin(2*frequency)
		analytical_gain *= sqrt((nr*nr+ni*ni)/(dr*dr+di*di))
	check(absf(mono_level-linear_to_db(0.25/sqrt(2)*analytical_gain)) < 0.002, "K analytical 44100Hz sine response")
	sine.data = stereo
	sine.stereo = true
	check(absf(k_music_rms_db(sine)-mono_level-3.01029996) < 0.00001, "stereo K uses sum of channel mean squares")
	benchmark.assets_levels = preload("res://tests/audio_assets_checks.gd").run(self)
	# Fresh director: no source-WAV parsing or synchronous resource load at runtime.
	var initial := Main.new()
	initial.controls_path = OUT + "assets-controls.cfg"
	initial.audio_settings_path = OUT + "assets-audio.cfg"
	initial.audio_synthesis_override = 1
	initial.set_meta("sound_set_override", "assets")
	var began := Time.get_ticks_usec()
	root.add_child(initial)
	initial.set_physics_process(false)
	var audio: Node = initial.audio
	var effects_ready := 0.0
	var title_ready := 0.0
	while audio.streams.size() < 71 and Time.get_ticks_usec()-began < 20000000:
		test_progress()
		OS.delay_msec(2)
		await process_frame
		if effects_ready == 0 and Bank.SOUNDS.keys().all(func(id): return audio.streams.has(id)): effects_ready = (Time.get_ticks_usec()-began)/1000.0
		if title_ready == 0 and audio.streams.has("title"): title_ready = (Time.get_ticks_usec()-began)/1000.0
	check(effects_ready > 0 and effects_ready <= 1300, "asset effects ready <=1.3s")
	check(title_ready > 0 and title_ready <= 3000, "asset title ready <=3s")
	check(audio.asset_service_max_usec < 8000 and audio.asset_operation_max_usec < 8000, "asset main-thread service/operation each <8ms")
	check(audio.asset_stream_bytes == audio.asset_loaded.keys().reduce(func(n, id): return n+audio.stream_bytes(audio.streams[id]), 0), "resident PCM / OGG packet bytes measured")
	check(audio.asset_loaded.size() == 65 and audio.bank.snapshot().ids.size() == 6, "asset mode only synthesizes six ambient streams")
	var expected_synth_order: Array = (Bank.SOUNDS.keys() + Bank.MUSIC_IDS).filter(func(id): return not Assets.EFFECTS.has(id) and not Assets.MUSIC.has(id))
	check(audio.bank.snapshot().ids.keys() == expected_synth_order, "remaining synthesis keeps original order")
	for id: String in Bank.SOUNDS.keys() + Bank.MUSIC_IDS:
		check(audio.asset_loaded.has(id) == (Assets.EFFECTS.has(id) or Assets.MUSIC.has(id)), id + ": selected source")
		if audio.asset_loaded.has(id):
			var spec: Dictionary = Assets.EFFECTS.get(id, Assets.MUSIC.get(id, {}))
			check(audio.streams[id].resource_path == spec.path, id + ": plays imported source path")
		else: check(audio.streams[id].data == streams[id].data, id + ": unchanged synthesized stream")
	for id: String in Assets.EFFECTS:
		audio.stop_world()
		for voice: Dictionary in audio.voices: audio.stop_handle(voice.handle)
		audio.last_id.clear()
		audio.last_frame.clear()
		var handle: int = audio.play(id, null, -2.0, 1.1)
		check(handle >= 0, id + ": material playable")
		if handle < 0: continue
		var voice: Dictionary = audio.voices[handle % 32]
		var spec: Dictionary = Assets.EFFECTS[id]
		check(voice.player.stream == audio.streams[id] and is_equal_approx(voice.player.pitch_scale, 1.1*float(spec.pitch)) and is_equal_approx(voice.player.volume_db, -2.0+float(spec.gain_db)), id + ": stream / multiplied pitch / additive gain")
		check(absf(voice.until-audio.clock_ms-voice.player.stream.get_length()/voice.player.pitch_scale*1000) < 0.001, id + ": voice length uses actual pitch")
	audio.set_process(false)
	initial.state = "audio_settings"
	audio.set_music("region0", 1.0)
	check(is_equal_approx(audio.music[audio.music_slot].volume_db, -80.0+float(Assets.MUSIC.region0.gain_db)), "music gain offset also applies at playback start")
	audio.set_music("title", 1.0)
	for i in range(240): audio._process(1.0/60)
	check(is_equal_approx(audio.music[audio.music_slot].volume_db, Assets.MUSIC.title.gain_db), "music normal gain offset")
	initial.state = "paused"
	for i in range(60): audio._process(1.0/60)
	check(is_equal_approx(audio.music[audio.music_slot].volume_db, Assets.MUSIC.title.gain_db-10), "music duck preserves gain offset")
	initial.state = "lost"
	for i in range(600): audio._process(1.0/60)
	check(is_equal_approx(audio.music[audio.music_slot].volume_db, Assets.MUSIC.title.gain_db-9), "result -9dB preserves gain offset")
	initial.state = "title"
	for i in range(240): audio._process(1.0/60)
	check(is_equal_approx(audio.music[audio.music_slot].volume_db, Assets.MUSIC.title.gain_db), "result recovery preserves gain offset")
	benchmark.assets_startup = {"effects_ms": effects_ready, "title_ms": title_ready, "stream_bytes": audio.asset_stream_bytes, "service_max_ms": audio.asset_service_max_usec/1000.0, "operation_max_ms": audio.asset_operation_max_usec/1000.0, "setup_ms": audio.setup_ms, "synthesis": audio.bank.snapshot()}
	# The same 1800-frame replay with the actual material streams.
	var synth_streams := streams
	streams = audio.streams.duplicate()
	game.audio.sound_set = "assets"
	game.audio.asset_loaded = audio.asset_loaded.duplicate()
	var silent: Array = await replay(false)
	var audible: Array = await replay(true)
	for i in range(1800): check(silent[i] == audible[i], "disabled/assets exact state frame %d" % i)
	streams = synth_streams
	game.audio.asset_loaded.clear()
	game.audio.sound_set = "synth"
	initial.free()
	# Failure on one ID only; other IDs from the same source remain material.
	var director := preload("res://scripts/audio_director.gd").new()
	director.game = game
	director.synthesis_override = 1
	director.sound_set_override = "assets"
	director.asset_paths_override = {"shot_a": "res://assets/audio/sfx/missing-test.wav", "boss": "res://assets/audio/music/missing-test.ogg"}
	game.add_child(director)
	var deadline := Time.get_ticks_msec() + 20000
	while director.streams.size() < 71 and Time.get_ticks_msec() < deadline:
		test_progress()
		OS.delay_msec(2)
		await process_frame
	check(director.asset_warned.keys() == ["shot_a", "boss"] and not director.asset_loaded.has("shot_a") and director.asset_loaded.has("shot_b") and not director.asset_loaded.has("boss"), "only failed effect / OGG IDs warn once and fall back")
	check(director.streams.has("shot_a") and director.streams.shot_a.data == streams.shot_a.data, "failed ID receives exact synth PCM")
	check(director.asset_spec("shot_a").is_empty(), "fallback has no material pitch/gain")
	check(director.streams.has("boss") and director.streams.boss.data == streams.boss.data and director.asset_spec("boss").is_empty(), "failed OGG boss receives exact synth PCM without asset gain")
	director.free()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var real_cfg:=FileAccess.get_file_as_bytes("user://audio.cfg") if FileAccess.file_exists("user://audio.cfg") else PackedByteArray()
	await startup_test()
	group="synthesis"
	await synthesize()
	energy_test()
	game=Main.new()
	game.controls_path=OUT+"test-controls.cfg"
	game.audio_settings_path=OUT+"test-audio.cfg"
	game.audio_synthesis_override=0
	game.set_meta("sound_set_override", "synth")
	root.add_child(game)
	game.set_physics_process(false)
	game.audio.streams=streams.duplicate()
	await settings_test()
	await event_test()
	await overlap_test()
	await music_test()
	await sound_regression_test()
	await replay_test()
	await stress_test()
	print("AUDIO: legacy groups complete; checking materials")
	await assets_test()
	group="coverage"
	for id: String in Bank.SOUNDS:
		if id.begins_with("amb"): continue
		var logical:=id.trim_suffix("_a").trim_suffix("_b")
		check(event_ids.has(logical),logical+": event coverage")
	group="isolation"
	var after_cfg:=FileAccess.get_file_as_bytes("user://audio.cfg") if FileAccess.file_exists("user://audio.cfg") else PackedByteArray()
	check(real_cfg==after_cfg,"real user audio.cfg unchanged")
	check(game.audio.setup_ms<10,"main-thread audio setup <10ms")
	var buses:=AudioServer.bus_count
	game.free()
	game=Main.new()
	game.controls_path=OUT+"test-controls.cfg"
	game.audio_settings_path=OUT+"second-audio.cfg"
	game.audio_synthesis_override=0
	root.add_child(game)
	check(AudioServer.bus_count==buses,"repeated main does not duplicate buses")
	check(game.audio.bank.thread==null,"headless skips synthesis")
	check(game.audio.asset_queue.is_empty() and game.audio.asset_pending.is_empty() and game.audio.asset_loaded.is_empty(), "headless default skips material loading too")
	game.free()
	game=null
	FileAccess.open(OUT+"audio-results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"groups":groups,"events":event_ids.keys(),"waveforms":wave_metrics,"benchmark":benchmark},"\t"))
	FileAccess.open(OUT + "fix-music-trace.json", FileAccess.WRITE).store_string(JSON.stringify(music_trace))
	print("AUDIO RESULT: ",checks," checks, ",failures.size()," failures; groups=",groups)
	quit(0 if failures.is_empty() else 1)

func _finalize() -> void:
	if bank!=null: bank.shutdown()
	if is_instance_valid(game): game.free()
