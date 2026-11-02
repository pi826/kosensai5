extends "res://tests/test_tree.gd"
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game := preload("res://scripts/main.gd").new()
	game.audio_synthesis_override = 1
	game.controls_path = "res://builds/qa/sound/task8d/mix-controls.cfg"
	game.audio_settings_path = "res://builds/qa/sound/task8d/mix-audio.cfg"
	root.add_child(game)
	game.set_physics_process(false)
	game.world.process_mode = Node.PROCESS_MODE_DISABLED
	game.state = "playing"
	var began := Time.get_ticks_msec()
	while game.audio.streams.size() < 71 and Time.get_ticks_msec()-began < 20000:
		test_progress()
		OS.delay_msec(2)
		await process_frame
	game.audio.set_process(false)
	game.audio.settings.values = {"master":100,"bgm":100,"se":100}
	game.audio.settings.apply()
	game.audio.set_music("boss", 1.0)
	game.audio.music[game.audio.music_slot].volume_db = game.audio.music_asset_db(game.audio.music_slot)
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 2.0
	var effect_index := AudioServer.get_bus_effect_count(0)
	AudioServer.add_bus_effect(0, capture)
	var played := 0
	for id: String in preload("res://audio_tools/sfx_recipes.gd").H + preload("res://audio_tools/sfx_recipes.gd").M:
		if game.audio.play(id) >= 0: played += 1
	began = Time.get_ticks_msec()
	while Time.get_ticks_msec()-began < 600:
		OS.delay_msec(5)
		await process_frame
	var mixed := capture.get_buffer(capture.get_frames_available())
	var peak := 0.0
	for frame: Vector2 in mixed: peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
	AudioServer.remove_bus_effect(0, effect_index)
	var ok := mixed.size() > 0 and peak > 0.05 and peak <= db_to_linear(-0.5)+0.0001 and played == 16
	var result := {"frames":mixed.size(),"peak_dbfs":linear_to_db(peak),"played":played,"settings":{"master":100,"bgm":100,"se":100},"ok":ok}
	FileAccess.open("res://builds/qa/sound/task8d/mix-results.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("MIX RESULT: ",result)
	game.free()
	quit(0 if ok else 1)
