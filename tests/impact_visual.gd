extends "res://tests/test_tree.gd"
const Main := preload("res://scripts/main.gd")
const Enemy := preload("res://scripts/enemy.gd")
var game: Node2D
func _initialize() -> void: call_deferred("run")
func run() -> void:
	game = Main.new()
	game.audio_synthesis_override = 1
	game.controls_path = "res://builds/qa/sound/task8d/visual-controls.cfg"
	game.audio_settings_path = "res://builds/qa/sound/task8d/visual-audio.cfg"
	root.add_child(game)
	game.start_run(37)
	game.set_physics_process(false)
	game.world.process_mode = Node.PROCESS_MODE_DISABLED
	game.state = "playing"
	game.ui.menu.hide()
	game.camera.position = game.player.position
	game.camera.force_update_scroll()
	var actor := Enemy.new()
	actor.game = game
	actor.kind = "boss"
	actor.boss_role = "secret"
	actor.boss_id = 999
	actor.spawn_id = "impact-visual"
	actor.position = game.camera.position+Vector2(180, -100)
	game.world.add_child(actor)
	var ready_deadline := Time.get_ticks_msec()+15000
	while (game.audio.streams.size() < 71 or game.audio.boss_inside < 0.35) and Time.get_ticks_msec() < ready_deadline:
		test_progress()
		OS.delay_msec(1)
		await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("res://builds/qa/sound/task8d/impact-before.png")
	# Real defeat path including rewards and audio, with a stable camera for QA.
	actor.receive_hit(1-actor.polarity, 9999)
	game.ui.update_hud()
	var began := Time.get_ticks_usec()
	var captured := []
	for seconds: float in [0.1, 0.3, 0.6, 1.0, 1.4]:
		while (Time.get_ticks_usec()-began)/1000000.0 < seconds:
			test_progress()
			await process_frame
		await RenderingServer.frame_post_draw
		var actual := (Time.get_ticks_usec()-began)/1000000.0
		var path := "res://builds/qa/sound/task8d/impact-%.1f.png" % seconds
		get_root().get_texture().get_image().save_png(path)
		captured.append({"requested":seconds,"actual":actual,"ring_age":game.boss_impact.ring_age,"time_scale":Engine.time_scale,"audio_scale":AudioServer.playback_speed_scale,"visible":game.boss_impact.visible,"boss_defeat_played":game.audio.history().any(func(event): return event.id == "boss_defeat" and event.played),"bgm_playing":game.audio.music.any(func(player): return player.playing)})
	game.free()
	await process_frame
	OS.delay_msec(40) # Let the audio mixer release stopped OGG playback objects.
	FileAccess.open("res://builds/qa/sound/task8d/visual-results.json",FileAccess.WRITE).store_string(JSON.stringify(captured,"\t"))
	print("IMPACT VISUAL: 5 captures ",captured)
	quit()
