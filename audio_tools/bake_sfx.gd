extends SceneTree
## Offline only. No importer dependency; seeded synthesis, fixed order, PCM16.
const Recipes := preload("res://audio_tools/sfx_recipes.gd")
const DSP := preload("res://audio_tools/dsp.gd")
const Bank := preload("res://scripts/sound_bank.gd")
const RATE := 44100
const OUT := "res://builds/qa/sound/task8d/"
var cache := {}
var synth := {}
var metrics := {}

func _initialize() -> void:
	call_deferred("run")

func decode(path: String) -> AudioStreamWAV:
	if path.ends_with(".wav"):
		return AudioStreamWAV.load_from_file(path, {"compress/mode": 0, "edit/trim": false, "edit/normalize": false})
	return DSP.decoded_pcm(AudioStreamOggVorbis.load_from_file(path))

func samples(path: String) -> PackedFloat64Array:
	if cache.has(path): return cache[path]
	var stream := decode(path)
	var channels := 2 if stream.stereo else 1
	var data := PackedFloat64Array()
	data.resize(int(round(stream.get_length() * RATE)))
	var pcm := stream.data
	for i in range(data.size()):
		var p := minf(i * stream.mix_rate / float(RATE), pcm.size() / (2 * channels) - 1)
		var j := int(p)
		var k := mini(j+1, pcm.size() / (2*channels)-1)
		for c in range(channels): data[i] += lerpf(pcm.decode_s16((j*channels+c)*2), pcm.decode_s16((k*channels+c)*2), p-j) / (32768.0*channels)
	cache[path] = data
	return data

func layer_samples(spec: Dictionary, n: int, seed_value: int) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	result.resize(n)
	var input := PackedFloat64Array()
	if spec.has("source"): input = samples("res://assets/audio/source/" + spec.source)
	elif spec.synth in ["win", "lose"]:
		var stream: AudioStreamWAV = synth[spec.synth]
		var bytes := stream.data
		input.resize(int(round(stream.get_length()*RATE)))
		for i in range(input.size()): input[i] = bytes.decode_s16(mini(bytes.size()/2-1, int(i*stream.mix_rate/float(RATE)))*2)/32768.0
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var phase := 0.0
	var source_position := 0.0
	var low := 0.0
	var hp_low := 0.0
	var lp_a := 1.0-exp(-TAU*float(spec.get("lp", 16000.0))/RATE)
	var hp_a := 1.0-exp(-TAU*float(spec.get("hp", 24.0))/RATE)
	var duration := float(spec.get("duration", n/float(RATE)))
	for i in range(n):
		var t := i / float(RATE)
		var v := 0.0
		if not input.is_empty():
			var p := source_position if spec.has("pitch_end") else i*float(spec.get("pitch",1.0))
			source_position += lerpf(float(spec.get("pitch", 1.0)), float(spec.get("pitch_end", spec.get("pitch", 1.0))), minf(1.0,t/float(spec.get("pitch_seconds", duration))))
			if p < input.size()-1: v = lerpf(input[int(p)], input[int(p)+1], p-int(p))
			if spec.has("duration"): v *= clampf((duration-t)/0.008, 0.0, 1.0)
		elif t < duration:
			var f := float(spec.get("frequency", 120.0))
			var u := t/duration
			var envelope := minf(1.0, t/float(spec.get("attack", 0.0007))) * pow(1.0-u, float(spec.get("envelope_power", 2.0)))
			match spec.synth:
				"sub":
					f = lerpf(f, float(spec.get("end", 38.0)), minf(1.0, t/float(spec.get("sweep", 0.18))))
					phase += TAU*f/RATE
					v = tanh(2.5*sin(phase)) * envelope
				"noise": v = rng.randf_range(-1.0, 1.0)*envelope
				"sweep":
					f = lerpf(f, float(spec.get("end", 80.0)), u)
					phase += TAU*f/RATE
					v = sin(phase)*envelope
				"bell", "arp":
					if spec.synth == "arp":
						var ratios: Array = spec.get("ratios", [1.0, 1.25, 1.5, 2.0])
						var note_seconds := float(spec.get("note_seconds", 0.14))
						var note := mini(ratios.size()-1, int(t/note_seconds))
						if spec.get("descending", false): note = ratios.size()-1-note
						f *= float(ratios[note])
						envelope *= exp(-fmod(t, note_seconds)*16.0)
					phase += TAU*f/RATE
					v = (sin(phase)+0.28*sin(phase*2.001)+0.13*sin(phase*3.99))*envelope
		if spec.has("gate_hz") and t >= float(spec.get("gate_after", 0.0)):
			# Rounded interruptions rather than discontinuous cuts.
			v *= smoothstep(0.12, 0.3, fmod(t*float(spec.gate_hz),1.0))
		if spec.get("rise_filter", false):
			lp_a = 1.0-exp(-TAU*lerpf(900.0, float(spec.get("lp",8000.0)), minf(1.0,t/duration))/RATE)
		low += lp_a*(v-low)
		hp_low += hp_a*(low-hp_low)
		result[i] = low-hp_low
	if spec.has("echo"):
		var dry := result.duplicate()
		for repeat in range(1, 4):
			var delay := int(RATE*float(spec.echo)*repeat)
			var lp := 0.0
			var bass := 0.0
			for i in range(n-delay):
				lp += 0.25*(dry[i]-lp)
				bass += 0.045*(lp-bass)
				result[i+delay] += (lp-bass)*pow(0.38, repeat)
	return result

func pcm(values: PackedFloat64Array, gain: float = 1.0) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	var bytes := PackedByteArray()
	bytes.resize(values.size()*2)
	for i in range(values.size()): bytes.encode_s16(i*2, clampi(roundi(values[i]*gain*32768), -32768, 32767))
	stream.data = bytes
	return stream

func hash_file(path: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(FileAccess.get_file_as_bytes(path))
	return ctx.finish().hex_encode()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var bank := Bank.new()
	bank.start(Bank.MUSIC_IDS)
	while not bank.snapshot().complete:
		synth.merge(bank.collect())
		OS.delay_msec(5)
	synth.merge(bank.collect())
	bank.shutdown()
	var effects := {}
	var hashes := {}
	for id: String in Recipes.all():
		var recipe: Dictionary = Recipes.all()[id]
		var values := PackedFloat64Array()
		values.resize(roundi(recipe.seconds*RATE))
		for j in range(recipe.layers.size()):
			var layer: Dictionary = recipe.layers[j]
			var data := layer_samples(layer, values.size(), id.hash()+j)
			var delay := roundi(float(layer.get("delay", 0.0))*RATE)
			for i in range(values.size()-delay): values[i+delay] += data[i]*float(layer.gain)
		var average := 0.0
		for value in values: average += value/values.size()
		for i in range(values.size()):
			values[i] = tanh((values[i]-average)*1.8) * minf(1.0, (values.size()-1-i)/(RATE*0.008))
		var target: float = recipe.target_k
		var old_k := -100.0
		if Recipes.BASE.has(id):
			var base: Dictionary = Recipes.BASE[id]
			old_k = Recipes.BASE_K[id]
			if Recipes.QUIET.has(id): target = old_k
			elif Recipes.UI.has(id): target = old_k+2.0
			elif id in ["shot_a", "shot_b"]: target = old_k+5.5
		var raw := pcm(values)
		var gain := db_to_linear(target-DSP.k_effect_max50_db(raw))
		var peak := 0.0
		for value in values: peak = maxf(peak, absf(value))
		gain = minf(gain, db_to_linear(-1.05)/maxf(0.0001, peak))
		var stream := pcm(values, gain)
		var path := "res://assets/audio/sfx/"+id+".wav"
		stream.save_to_wav(path)
		FileAccess.open(path+".import", FileAccess.WRITE).store_string('[remap]\nimporter="wav"\ntype="AudioStreamWAV"\n\n[params]\nforce/8_bit=false\nforce/mono=false\nforce/max_rate=false\nedit/trim=false\nedit/normalize=false\nedit/loop_mode=1\ncompress/mode=0\n')
		effects[id] = {"path": path, "pitch": 1.0, "gain_db": 0.0}
		hashes[path] = hash_file(path)
		metrics[id] = {"k": DSP.k_effect_max50_db(stream), "old_k": old_k, "seconds": stream.get_length(), "peak": linear_to_db(peak*gain), "layers": recipe.layers.size()}
		print("BAKED ", id, " ", metrics[id])
	FileAccess.open(OUT+"sfx-metrics.json", FileAccess.WRITE).store_string(JSON.stringify(metrics, "\t"))
	FileAccess.open(OUT+"sfx-assignments.json", FileAccess.WRITE).store_string(JSON.stringify({"effects": effects, "sha256": hashes}, "\t"))
	FileAccess.open(OUT+"recipes.json", FileAccess.WRITE).store_string(JSON.stringify(Recipes.all(), "\t"))
	var existing: Dictionary = load("res://scripts/sound_assets.gd").get_script_constant_map()
	for spec: Dictionary in existing.MUSIC.values(): hashes[spec.path] = hash_file(spec.path)
	preload("res://audio_tools/asset_manifest.gd").write(effects, existing.MUSIC, hashes)
	quit()
