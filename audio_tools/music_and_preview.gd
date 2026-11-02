extends SceneTree
const DSP := preload("res://audio_tools/dsp.gd")
const Recipes := preload("res://audio_tools/sfx_recipes.gd")
const Baker := preload("res://audio_tools/bake_sfx.gd")
const Bank := preload("res://scripts/sound_bank.gd")
const Baseline := preload("res://builds/qa/sound/task8d/baseline-6902671/scripts/sound_bank.gd")
const Impact := preload("res://scripts/boss_impact.gd")
const OUT := "res://builds/qa/sound/preview-8d/"
const QA := "res://builds/qa/sound/task8d/"
const MUSIC := {
	"title": {"path": "res://assets/audio/music/hydrogene_traveling_the_sky.ogg", "loop_offset": 0.0},
	"region0": {"path": "res://assets/audio/music/hydrogene_spirits_forest_full.ogg", "loop_offset": 27.343741},
	"region1": {"path": "res://assets/audio/music/hydrogene_dangerous_cave.ogg", "loop_offset": 0.0},
	"region2": {"path": "res://assets/audio/music/hydrogene_volcanic_crater.ogg", "loop_offset": 0.0},
	"boss": {"path": "res://assets/audio/music/hydrogene_battle_theme_iv_full.ogg", "loop_offset": 1.741066},
}
func _initialize() -> void:
	call_deferred("run")

func collect(bank: RefCounted) -> Dictionary:
	var result := {}
	bank.start()
	while not bank.snapshot().complete:
		result.merge(bank.collect())
		OS.delay_msec(5)
	result.merge(bank.collect())
	bank.shutdown()
	return result

func run() -> void:
	var helper := Baker.new()
	var assignments: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(QA+"sfx-assignments.json"))
	var hashes: Dictionary = assignments.sha256
	var music := {}
	var music_metrics := {}
	for id: String in MUSIC:
		var spec: Dictionary = MUSIC[id].duplicate()
		var stream := AudioStreamOggVorbis.load_from_file(spec.path)
		var raw := DSP.decoded_pcm(stream)
		var level := DSP.k_music_rms_db(raw)
		spec.gain_db = -21.0-level
		spec.pitch = 1.0
		music[id] = spec
		hashes[spec.path] = helper.hash_file(spec.path)
		music_metrics[id] = {"decoded_k": level, "gain_db": spec.gain_db, "adjusted_k": level+spec.gain_db, "seconds": stream.get_length(), "loop_offset": spec.loop_offset}
		print("MUSIC ", id, " ", music_metrics[id])
		FileAccess.open(spec.path+".import", FileAccess.WRITE).store_string('[remap]\nimporter="oggvorbisstr"\ntype="AudioStreamOggVorbis"\n\n[params]\nloop=true\nloop_offset='+str(spec.loop_offset)+'\nbpm=0\nbeat_count=0\nbar_beats=4\n')
		var preview := AudioStreamWAV.new()
		preview.format = raw.format
		preview.stereo = true
		preview.mix_rate = raw.mix_rate
		var pcm := raw.data
		var gain := db_to_linear(spec.gain_db)
		for i in range(pcm.size()/2): pcm.encode_s16(i*2, clampi(roundi(pcm.decode_s16(i*2)*gain), -32768, 32767))
		# First play includes intro; second starts at the authored loop offset.
		var second := pcm.slice(roundi(spec.loop_offset*raw.mix_rate)*4)
		pcm.append_array(second)
		preview.data = pcm
		preview.save_to_wav(OUT+id+"-two-loops.wav")
	FileAccess.open(QA+"music-metrics.json", FileAccess.WRITE).store_string(JSON.stringify(music_metrics,"\t"))
	preload("res://audio_tools/asset_manifest.gd").write(assignments.effects, music, hashes)
	var synth := collect(Bank.new())
	var baseline := collect(Baseline.new())
	var synth_results := {}
	for id: String in synth:
		synth_results[id] = synth[id].data == baseline[id].data
		if not synth_results[id]: push_error("SYNTH PCM CHANGED: "+id)
	FileAccess.open(QA+"synth-byte-equality.json", FileAccess.WRITE).store_string(JSON.stringify(synth_results,"\t"))
	var sampler := PackedFloat64Array()
	var order := ""
	var ids: Array = Bank.SOUNDS.keys()
	ids.sort()
	for id: String in ids:
		order += "%9.3f  %s\n" % [sampler.size()/44100.0, id]
		var data: PackedFloat64Array
		if assignments.effects.has(id): data = helper.samples(assignments.effects[id].path)
		else:
			var s: AudioStreamWAV = synth[id]
			data.resize(roundi(s.get_length()*44100))
			for i in range(data.size()): data[i] = s.data.decode_s16(mini(s.data.size()/2-1,int(i*s.mix_rate/44100.0))*2)/32768.0
		sampler.append_array(data)
		sampler.resize(sampler.size()+22050)
		helper.pcm(data).save_to_wav(OUT+id+".wav")
	helper.pcm(sampler).save_to_wav(OUT+"se_sampler.wav")
	FileAccess.open(OUT+"se_sampler.txt", FileAccess.WRITE).store_string(order)
	for id: String in ["hurt", "heal", "potion", "bomb_explode", "enemy_defeat", "boss_defeat"]:
		var base: Dictionary = Recipes.BASE[id]
		var raw := helper.samples("res://builds/qa/sound/task8d/baseline-audio/"+base.source)
		var old := PackedFloat64Array()
		old.resize(ceili(raw.size()/float(base.pitch)))
		for i in range(old.size()):
			var p := minf(raw.size()-1, i*float(base.pitch))
			old[i] = lerpf(raw[int(p)],raw[mini(int(p)+1,raw.size()-1)],p-int(p))*db_to_linear(base.gain_db)
		helper.pcm(old).save_to_wav(OUT+id+"-8c.wav")
		old.resize(old.size()+22050)
		old.append_array(helper.samples(assignments.effects[id].path))
		helper.pcm(old).save_to_wav(OUT+id+"-8c-then-8d.wav")
	var impact := Impact.new()
	impact.depth = 0.22
	impact.hold = 0.85
	var boss := helper.samples(assignments.effects.boss_defeat.path)
	var slow := PackedFloat64Array()
	var p := 0.0
	var t := 0.0
	while p < boss.size()-1:
		slow.append(lerpf(boss[int(p)],boss[int(p)+1],p-int(p)))
		p += impact.factor(t)
		t += 1.0/44100
	impact.free()
	helper.pcm(slow).save_to_wav(OUT+"boss_defeat-slow.wav")
	helper.free()
	quit()
