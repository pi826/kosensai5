extends RefCounted
const Assets := preload("res://scripts/sound_assets.gd")
const Bank := preload("res://scripts/sound_bank.gd")
const Recipes := preload("res://audio_tools/sfx_recipes.gd")
const DSP := preload("res://audio_tools/dsp.gd")
const Baker := preload("res://audio_tools/bake_sfx.gd")

static func run(t: SceneTree) -> Dictionary:
	t.check(Assets.EFFECTS.size() == 60 and Assets.MUSIC.size() == 5, "exact 60 baked effects / 5 OGG tracks")
	for id: String in Bank.SOUNDS:
		t.check(Assets.EFFECTS.has(id) != Assets.SYNTH_EFFECTS.has(id), id+": exactly one effect source")
	for id: String in Bank.MUSIC_IDS:
		t.check(Assets.MUSIC.has(id) != Assets.SYNTH_MUSIC.has(id), id+": exactly one music source")
	t.check(Assets.SYNTH_EFFECTS.size() == 6 and Assets.SYNTH_MUSIC.is_empty(), "only six ambient effects stay synthesized")
	var source_bytes := {}
	for path: String in Assets.SHA256:
		t.test_progress()
		t.check(FileAccess.file_exists(path), path+": file exists")
		var config := ConfigFile.new()
		t.check(config.load(path+".import") == OK, path+": import exists")
		if path.ends_with(".ogg"):
			t.check(config.get_value("params", "loop", false), path+": OGG loop import")
		else:
			t.check(config.get_value("params", "edit/trim", true) == false and config.get_value("params", "edit/normalize", true) == false, path+": trim/normalize disabled")
			t.check(config.get_value("params", "compress/mode", -1) == 0 and config.get_value("params", "edit/loop_mode", -1) == 1, path+": PCM / no loop")
		var bytes := FileAccess.get_file_as_bytes(path)
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(bytes)
		t.check(hash.finish().hex_encode() == Assets.SHA256[path], path+": SHA256")
		source_bytes[path] = bytes
	var metrics := {"effects": {}, "music": {}, "correlations": {}, "spectral_ratios": {}}
	var effect_streams := {}
	var baker := Baker.new()
	# Calibrate the band meter with a known 4% tone energy mixture. A pure tone
	# must be rejected by the 5% rule, while an unrelated tone must not leak in.
	var calibration := PackedFloat64Array()
	# One second includes enough cycles for the +/-3% band to capture >99%
	# despite rectangular-window leakage; the production meter stays unchanged.
	calibration.resize(44100)
	for i in range(calibration.size()): calibration[i] = 0.5*sin(TAU*660.0*i/44100.0)
	t.check(DSP.band_energy_ratio(baker.pcm(calibration),[660.0,825.0,990.0]) > 0.99, "band meter detects pure 660Hz")
	for i in range(calibration.size()): calibration[i] = 0.5*(sqrt(0.04)*sin(TAU*660.0*i/44100.0)+sqrt(0.96)*sin(TAU*3000.0*i/44100.0))
	t.check(absf(DSP.band_energy_ratio(baker.pcm(calibration),[660.0,825.0,990.0])-0.04) < 0.005, "band meter measures 4 percent energy mixture")
	var credits := FileAccess.get_file_as_string("res://assets/audio/CREDITS.md")
	t.check(FileAccess.file_exists("res://assets/audio/source/.gdignore"), "original layers excluded from import/export")
	for name: String in Recipes.SOURCE_SHA256:
		var path := "res://assets/audio/source/"+name
		t.check(baker.hash_file(path) == Recipes.SOURCE_SHA256[name] and credits.contains(name), name+": unchanged original source SHA / credit")
	var all_recipes := Recipes.all()
	for id: String in Assets.EFFECTS:
		t.test_progress()
		var spec: Dictionary = Assets.EFFECTS[id]
		var stream := load(spec.path) as AudioStreamWAV
		t.check(stream != null, id+": imported effect exists")
		if stream == null: continue
		effect_streams[id] = stream
		t.check(stream.mix_rate == 44100 and not stream.stereo and stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, id+": mono PCM16 44100Hz / no loop")
		var raw := AudioStreamWAV.load_from_buffer(source_bytes[spec.path], {"compress/mode": 0})
		t.check(stream.data == raw.data, id+": no trimming or normalization")
		var recipe: Dictionary = all_recipes[id]
		var minimum := 1 if Recipes.UI.has(id) or Recipes.QUIET.has(id) else (4 if Recipes.H.has(id) else (3 if Recipes.M.has(id) else 2))
		t.check(recipe.layers.size() >= minimum, id+": layer count")
		if Recipes.UI.has(id) or Recipes.QUIET.has(id):
			t.check(recipe.layers.all(func(layer): return layer.has("source")), id+": UI / quiet uses original material without a bell")
		if id in ["enemy_defeat", "block_break", "boss_hit", "laser_fire"]:
			t.check(recipe.layers.all(func(layer): return not layer.get("synth", "") in ["bell", "arp"]), id+": no melodic layer")
		if id in ["key", "item_get", "ability_get", "arrow_unlock", "charge"]:
			t.check(recipe.layers.all(func(layer): return layer.get("synth", "") != "sub"), id+": no reward sub")
		for layer: Dictionary in recipe.layers:
			if layer.has("source"):
				t.check(FileAccess.file_exists("res://assets/audio/source/"+layer.source) and credits.contains(layer.source), id+": stored and credited source "+layer.source)
		var actual := DSP.k_effect_max50_db(stream, spec.pitch, spec.gain_db)
		var peak := 0.0
		var pcm := stream.data
		for i in range(pcm.size()/2): peak = maxf(peak, absf(pcm.decode_s16(i*2)/32768.0))
		var peak_db := linear_to_db(peak)+float(spec.gain_db)
		t.check(peak_db <= -1.0+0.000001, id+": peak <= -1dBFS")
		var maximum := 2.8 if Recipes.H.has(id) else (0.9 if id == "enemy_defeat" else (1.2 if Recipes.M.has(id) else 10.0))
		if id in ["shot_a", "shot_b"]: maximum = 0.25
		if id in ["jump", "air_jump"]: maximum = 0.3
		t.check(stream.get_length() <= maximum, id+": duration limit")
		var old_k := -100.0
		var low := DSP.low_band(stream)
		var old_low := -100.0
		if Recipes.BASE.has(id):
			var base: Dictionary = Recipes.BASE[id]
			old_k = Recipes.BASE_K[id]
			old_low = Recipes.BASE_LOW[id]
			var baseline_path: String = "res://builds/qa/sound/task8d/baseline-audio/"+base.source
			if FileAccess.file_exists(baseline_path):
				var old: AudioStreamWAV = baker.decode(baseline_path)
				t.check(absf(DSP.k_effect_max50_db(old, base.pitch, base.gain_db)-old_k) < 0.000001 and absf(DSP.low_band(old, base.pitch, base.gain_db)-old_low) < 0.000001, id+": frozen 8C meters agree with archived PCM")
		if Recipes.H.has(id):
			t.check(actual >= -8.0, id+": heavy K >= -8dB")
			t.check(low >= -14.0 and low-old_low >= 6.0, id+": heavy low band >= -14dBFS / +6dB vs 8C")
		elif Recipes.M.has(id): t.check(actual >= -12.0, id+": medium K >= -12dB")
		if id in ["enemy_defeat", "block_break", "boss_hit"]:
			t.check(low >= -20.0 and low-old_low >= 6.0, id+": medium low band >= -20dBFS / +6dB vs 8C")
		if id in ["shot_a", "shot_b"]: t.check(actual-old_k >= 4.0 and actual-old_k <= 7.0, id+": shot +4..7dB vs 8C")
		if Recipes.UI.has(id): t.check(actual-old_k <= 3.0, id+": UI <= +3dB vs 8C")
		if Recipes.QUIET.has(id): t.check(actual-old_k <= 1.0, id+": enemy <= +1dB vs 8C")
		if id in ["heal", "potion"]:
			t.check(stream.get_length() >= 0.9 and stream.get_length() <= 1.6, id+": recovery length")
			var notes: Array = []
			var onsets := 0
			var frequencies := [523.25, 654.0625, 784.875, 1046.5]
			for j in range(4):
				var energies: Array = []
				for f: float in frequencies: energies.append(DSP.tone_energy(stream, f, j*0.14+0.015))
				notes.append(frequencies[energies.find(energies.max())])
				var before := DSP.tone_energy(stream, frequencies[j], maxf(0.0,j*0.14-0.065), 0.04) if j > 0 else 0.0
				if energies[j] > before*1.1: onsets += 1
			t.check(notes[0] < notes[1] and notes[1] < notes[2] and notes[2] < notes[3], id+": measured ascending pitches")
			t.check(onsets >= 3, id+": at least three measured note attacks")
			metrics.effects[id+"_notes"] = {"notes":notes,"attacks":onsets}
		if id == "hurt":
			var attack := 0
			while attack < pcm.size()/2 and absf(pcm.decode_s16(attack*2)/32768.0) < 0.05: attack += 1
			t.check(attack/44100.0 <= 0.002 and stream.get_length() >= 0.25 and stream.get_length() <= 0.5, "hurt: <=2ms attack and 0.25..0.5s")
			var early := 35
			var late := 35
			for f in range(35, 151, 5):
				if DSP.tone_energy(stream, f, 0.02) > DSP.tone_energy(stream, early, 0.02): early=f
				if DSP.tone_energy(stream, f, 0.21) > DSP.tone_energy(stream, late, 0.21): late=f
			t.check(early > late, "hurt: measured descending low pitch")
			metrics.effects.hurt_pitch = {"early":early,"late":late,"attack_ms":attack/44.1}
		metrics.effects[id] = {"asset_k":actual,"old_k":old_k,"peak_dbfs":peak_db,"low":low,"old_low":old_low,"seconds":stream.get_length()}
	# Explicit pairwise checks keep a common loud sub from replacing identities.
	for family: Array in [["boss_defeat", "boss_appear", "bomb_explode", "enhancer_defeat", "death"], ["enemy_defeat", "block_break", "boss_hit"]]:
		for i in range(family.size()):
			for j in range(i+1,family.size()):
				var label: String = family[i]+" / "+family[j]
				var value := absf(DSP.correlation(effect_streams[family[i]],effect_streams[family[j]]))
				t.check(value <= 0.6, label+": absolute first-400ms correlation <= 0.6 (%.6f)" % value)
				metrics.correlations[label] = value
	for family: Array in [["enemy_defeat", "block_break", "boss_hit", "laser_fire"], ["land", "ui_move", "glide", "dash", "empty", "enemy_warn", "air_jump"]]:
		var centers := [660.0,825.0,990.0] if family.has("laser_fire") else [660.0,1320.0,2640.0]
		var ceiling := 0.05 if family.has("laser_fire") else 0.15
		for id: String in family:
			t.test_progress()
			var ratio := DSP.band_energy_ratio(effect_streams[id],centers)
			t.check(ratio <= ceiling, id+": specified +/-3%% bands <= %.0f%% (%.4f%%)" % [ceiling*100,ratio*100])
			metrics.spectral_ratios[id] = ratio
	# Optional color bells are absent in these recipes: their layer energy is 0%.
	for id: String in ["switch_a", "switch_b", "absorb_a", "absorb_b"]:
		t.check(all_recipes[id].layers.all(func(layer): return layer.get("synth", "") != "bell"), id+": bell layer energy 0% <=35%")
	for id: String in Assets.MUSIC:
		t.test_progress()
		var spec: Dictionary = Assets.MUSIC[id]
		var stream := load(spec.path) as AudioStreamOggVorbis
		t.check(stream != null, id+": imported OGG music exists")
		if stream == null: continue
		t.check(stream.loop and absf(stream.loop_offset-spec.loop_offset) < 0.000001, id+": loop / authored offset")
		var config := ConfigFile.new()
		config.load(spec.path+".import")
		t.check(absf(config.get_value("params", "loop_offset", -1)-spec.loop_offset) < 0.000001, id+": explicit import loop offset")
		var decoded := DSP.k_music_rms_db(DSP.decoded_pcm(stream), spec.gain_db)
		t.check(absf(decoded+21.0) <= 0.5, id+": decoded stereo K = -21 +/-0.5dB")
		metrics.music[id] = {"decoded_k":decoded,"gain_db":spec.gain_db}
	baker.free()
	return metrics
