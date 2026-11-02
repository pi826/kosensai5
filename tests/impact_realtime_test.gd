extends "res://tests/test_tree.gd"
var ticks := 0
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game := preload("res://scripts/main.gd").new()
	game.audio_synthesis_override = 0
	game.impact_effect_override = 1
	game.controls_path = "res://builds/qa/sound/task8d/realtime-controls.cfg"
	game.audio_settings_path = "res://builds/qa/sound/task8d/realtime-audio.cfg"
	root.add_child(game)
	game.set_physics_process(false)
	game.world.process_mode = Node.PROCESS_MODE_DISABLED
	game.state = "playing"
	physics_frame.connect(func(): ticks += 1)
	var result := {"physics_interpolation_enabled":ProjectSettings.get_setting("physics/common/physics_interpolation", false)}
	var ok := true
	for role: String in ["guardian", "final", "secret"]:
		game.boss_impact.start(game.player.position, role)
		var began := Time.get_ticks_usec()
		while game.boss_impact.age < 0.1:
			await process_frame
			OS.delay_msec(1)
		var count_start := ticks
		var start := Time.get_ticks_usec()
		var speed_error := 0.0
		while game.boss_impact.age < 0.5:
			speed_error = maxf(speed_error, absf(Engine.time_scale-AudioServer.playback_speed_scale))
			await process_frame
			OS.delay_msec(1)
		var tick_rate := (ticks-count_start)/((Time.get_ticks_usec()-start)/1000000.0)
		while game.boss_impact.active:
			await process_frame
			OS.delay_msec(1)
		var duration := (Time.get_ticks_usec()-began)/1000000.0
		result[role] = {"real_physics_hz":tick_rate,"duration":duration,"speed_error":speed_error,"restored_ticks":Engine.physics_ticks_per_second}
		ok = ok and tick_rate >= 55 and tick_rate <= 65 and speed_error < 0.000001 and duration >= (1.3 if role == "guardian" else 1.5) and duration < (1.5 if role == "guardian" else 1.7)
	FileAccess.open("res://builds/qa/sound/task8d/realtime-results.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("REALTIME: ",result)
	game.free()
	quit(0 if ok else 1)
