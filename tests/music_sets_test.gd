extends "res://tests/test_tree.gd"
const Assets := preload("res://scripts/sound_assets.gd")
const MusicSets := preload("res://scripts/music_sets.gd")
const Bank := preload("res://scripts/sound_bank.gd")
const DSP := preload("res://audio_tools/dsp.gd")
const Main := preload("res://scripts/main.gd")
var OUT := "res://builds/qa/sound/task9g/test-%s-%d/" % [Time.get_datetime_string_from_system().replace(":", ""), OS.get_process_id()]
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)

func sha256(path: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(FileAccess.get_file_as_bytes(path))
	return context.finish().hex_encode()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_check_tables()
	_check_assets()
	await _check_synth_boss()
	for set_name: String in MusicSets.SETS:
		await _check_director(set_name)
	await _check_synth_override()
	_check_unknown()
	print("MUSIC SETS RESULT: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)

func _check_tables() -> void:
	for set_name: String in MusicSets.SETS:
		var table: Dictionary = MusicSets.music(set_name)
		var synth: Array = MusicSets.synth_music(set_name)
		check(table.size() + synth.size() == Bank.MUSIC_IDS.size(), set_name + ": five music IDs assigned once")
		for id: String in Bank.MUSIC_IDS:
			check(table.has(id) != synth.has(id), set_name + "/" + id + ": exactly one of material or synth")
		for id in synth:
			check(Bank.MUSIC_IDS.has(id), set_name + ": synth ID is a music ID: " + str(id))
	check(not MusicSets.is_known("bogus") and MusicSets.normalize("bogus") == "standard", "unknown set normalizes to standard")
	check(MusicSets.normalize("dark") == "dark" and MusicSets.normalize("junkala") == "junkala", "known sets normalize unchanged")
	check(MusicSets.music("standard") == Assets.MUSIC, "standard set is the generated asset table")

func _check_assets() -> void:
	for set_name: String in MusicSets.SETS:
		var table: Dictionary = MusicSets.music(set_name)
		for id: String in table:
			var spec: Dictionary = table[id]
			check(FileAccess.file_exists(spec.path), set_name + "/" + id + ": file exists")
			check(MusicSets.SHA256.get(spec.path, "") == sha256(spec.path), set_name + "/" + id + ": SHA-256")
			var config := ConfigFile.new()
			check(config.load(spec.path + ".import") == OK, set_name + "/" + id + ": import exists")
			if spec.path.ends_with(".ogg"):
				check(bool(config.get_value("params", "loop", false)), set_name + "/" + id + ": OGG loop import")
				check(absf(float(config.get_value("params", "loop_offset", -1.0)) - float(spec.loop_offset)) < 0.000001, set_name + "/" + id + ": explicit import loop offset")
				var stream := load(spec.path) as AudioStreamOggVorbis
				check(stream != null and stream.loop and absf(stream.loop_offset - float(spec.loop_offset)) < 0.000001, set_name + "/" + id + ": runtime loop offset")
			else:
				check(int(config.get_value("params", "compress/mode", -1)) == 2, set_name + "/" + id + ": QOA import")
				check(int(config.get_value("params", "edit/loop_mode", -1)) == 2, set_name + "/" + id + ": full-length loop import")
				check(int(config.get_value("params", "edit/loop_begin", -1)) == 0, set_name + "/" + id + ": loop begins at zero")
				var stream := load(spec.path) as AudioStreamWAV
				check(stream != null and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stream.loop_begin == 0, set_name + "/" + id + ": runtime full loop")
				check(stream != null and absf(stream.loop_end - stream.get_length() * stream.mix_rate) <= 2.0, set_name + "/" + id + ": loop end covers the full length")
			var decoded := DSP.decoded_pcm(load(spec.path) as AudioStream)
			var k := DSP.k_music_rms_db(decoded, float(spec.gain_db))
			check(absf(k + 21.0) <= 0.5, set_name + "/" + id + ": decoded K = -21 +/-0.5dB (%.3f)" % k)

func _check_synth_boss() -> void:
	var bank := Bank.new()
	var skip: Array = Assets.EFFECTS.keys()
	for id: String in MusicSets.music("junkala"): skip.append(id)
	bank.start(skip)
	var boss: AudioStream = null
	for i in range(4000):
		var got := bank.collect()
		if got.has("boss"):
			boss = got["boss"]
			break
		test_progress()
		OS.delay_msec(5)
		await process_frame
	check(boss != null, "junkala boss synthesized")
	if boss != null:
		var decoded := DSP.decoded_pcm(boss)
		var k := DSP.k_music_rms_db(decoded, MusicSets.synth_gain_db("junkala"))
		check(absf(k + 21.0) <= 0.5, "junkala/boss synth: decoded K = -21 +/-0.5dB (%.3f)" % k)
	bank.shutdown()

func _check_director(set_name: String) -> void:
	var game := Main.new()
	game.controls_path = OUT + set_name + "-controls.cfg"
	game.audio_settings_path = OUT + set_name + "-audio.cfg"
	game.audio_synthesis_override = 1
	game.set_meta("sound_set_override", "assets")
	game.set_meta("music_set_override", set_name)
	root.add_child(game)
	game.set_physics_process(false)
	var audio: Node = game.audio
	check(audio.music_set == set_name, set_name + ": director selects requested set")
	var material: Dictionary = MusicSets.music(set_name)
	var began := Time.get_ticks_usec()
	while (audio.streams.size() < 71 or not audio.asset_pending.is_empty() or not audio.asset_queue.is_empty()) and Time.get_ticks_usec() - began < 20000000:
		test_progress()
		OS.delay_msec(2)
		await process_frame
	check(audio.asset_loaded.size() == Assets.EFFECTS.size() + material.size(), set_name + ": effects plus only the set's material tracks load")
	check(audio.streams.size() == 71, set_name + ": all 71 streams ready")
	var other: Dictionary = {}
	for name: String in MusicSets.SETS:
		if name == set_name: continue
		for id: String in MusicSets.music(name):
			other[MusicSets.music(name)[id].path] = true
	for id: String in Bank.MUSIC_IDS:
		if material.has(id):
			check(audio.asset_loaded.has(id), set_name + "/" + id + ": material loaded")
			check(audio.streams[id].resource_path == material[id].path, set_name + "/" + id + ": selected set path")
			check(not other.has(audio.streams[id].resource_path), set_name + "/" + id + ": other set path not loaded")
			check(is_equal_approx(audio.music_gain_db(id), float(material[id].gain_db)), set_name + "/" + id + ": material gain")
		else:
			check(not audio.asset_loaded.has(id), set_name + "/" + id + ": synthesized instead of loaded")
			check(audio.streams[id].resource_path == "", set_name + "/" + id + ": synth stream has no asset path")
			check(is_equal_approx(audio.music_gain_db(id), MusicSets.synth_gain_db(set_name)), set_name + "/" + id + ": synth gain")
	check(audio.measurements().assets.music_set == set_name, set_name + ": diagnostics report music_set")
	game.free()
	await process_frame

func _check_synth_override() -> void:
	var game := Main.new()
	game.controls_path = OUT + "synth-controls.cfg"
	game.audio_settings_path = OUT + "synth-audio.cfg"
	game.audio_synthesis_override = 1
	game.set_meta("sound_set_override", "synth")
	game.set_meta("music_set_override", "junkala")
	root.add_child(game)
	game.set_physics_process(false)
	var audio: Node = game.audio
	check(audio.sound_set == "synth" and audio.music_set == "junkala", "synth override keeps the selected set name")
	check(audio.asset_loaded.is_empty() and audio.asset_queue.is_empty() and audio.asset_pending.is_empty(), "synth override never queues material imports")
	for id: String in Bank.MUSIC_IDS:
		check(audio.music_gain_db(id) == 0.0, id + ": synth music has no asset gain")
	var began := Time.get_ticks_usec()
	while audio.streams.size() < 71 and Time.get_ticks_usec() - began < 20000000:
		test_progress()
		OS.delay_msec(2)
		await process_frame
	check(audio.streams.size() == 71, "synth override produces all 71 streams")
	for id: String in Bank.MUSIC_IDS:
		check(audio.streams.has(id) and audio.streams[id].resource_path == "", id + ": music is synthesized")
	game.free()
	await process_frame

func _check_unknown() -> void:
	var game := Main.new()
	game.controls_path = OUT + "unknown-controls.cfg"
	game.audio_settings_path = OUT + "unknown-audio.cfg"
	game.audio_synthesis_override = 1
	game.set_meta("sound_set_override", "synth")
	game.set_meta("music_set_override", "bogus")
	root.add_child(game)
	game.set_physics_process(false)
	var audio: Node = game.audio
	check(audio.music_set == "standard", "unknown music set falls back to standard")
	check(audio.music_set_warned and audio.music_set_warnings == 1, "unknown music set warns once")
	game.free()
