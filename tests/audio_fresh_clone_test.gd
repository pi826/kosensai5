extends "res://tests/test_tree.gd"
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game := preload("res://scripts/main.gd").new()
	game.audio_synthesis_override = 1
	game.set_meta("sound_set_override", "assets")
	game.controls_path = "user://fresh-controls.cfg"
	game.audio_settings_path = "user://fresh-audio.cfg"
	root.add_child(game)
	game.set_physics_process(false)
	var began := Time.get_ticks_usec()
	while game.audio.streams.size() < 71 and Time.get_ticks_usec()-began < 30000000:
		test_progress()
		OS.delay_msec(2)
		await process_frame
	var result := {"streams":game.audio.streams.size(),"loaded":game.audio.asset_loaded.size(),"warned":game.audio.asset_warned.size(),"seconds":(Time.get_ticks_usec()-began)/1000000.0}
	print("FRESH CLONE: ",result)
	var ok: bool = result.streams == 71 and result.loaded == 0 and result.warned == 65
	game.free()
	await process_frame
	OS.delay_msec(40)
	quit(0 if ok else 1)
