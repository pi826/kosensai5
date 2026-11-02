extends "res://tests/test_tree.gd"
const Main := preload("res://scripts/main.gd")
const Enemy := preload("res://scripts/enemy.gd")
const T := preload("res://scripts/tuning.gd")
var game: Node2D
var checks := 0
var failures: Array = []
var timings := {}

func _initialize() -> void:
	if OS.get_cmdline_user_args().has("--stage3-art-qa"): call_deferred("run_stage3_art_qa")
	elif OS.get_cmdline_user_args().has("--stage2-art-qa"): call_deferred("run_art_qa")
	else: call_deferred("run")

func run_art_qa() -> void:
	await preload("res://tests/stage2_art_visual.gd").new().run(self)

func run_stage3_art_qa() -> void:
	await preload("res://tests/stage3_art_visual.gd").new().run(self)
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)

func freeze() -> void:
	game.set_physics_process(false)
	game.world.process_mode = Node.PROCESS_MODE_DISABLED
	game.boss_impact.set_process(false)
	game.audio.set_process(false)

func restored(label: String, original: Array) -> void:
	check([Engine.time_scale, AudioServer.playback_speed_scale, Engine.physics_ticks_per_second] == original, label+": exact global restore")
	check(not game.boss_impact.active and not game.boss_impact.visible and game.camera.offset == Vector2.ZERO, label+": layer / camera reset")

func retained(label: String, scales: Array) -> void:
	game.boss_impact.advance(0.0)
	check(game.boss_impact.active and game.state == "playing", label+": impact remains active")
	check([Engine.time_scale, AudioServer.playback_speed_scale, Engine.physics_ticks_per_second] == scales, label+": exact slow / audio / ticks retained")

func action_event(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	game.player._unhandled_input(event)

func regular_actions() -> void:
	game.start_run(37)
	game.streaming_enabled = false
	freeze()
	game.world.process_mode = Node.PROCESS_MODE_INHERIT
	for child in game.world.get_children(): child.set_physics_process(false)
	var p: Node = game.player
	p.position = Vector2(6000, -500)
	p.velocity = Vector2.ZERO
	var floor_body := StaticBody2D.new()
	floor_body.position = p.position+Vector2(0, 40)
	floor_body.collision_layer = 1
	var shape := CollisionShape2D.new()
	shape.shape = RectangleShape2D.new()
	shape.shape.size = Vector2(2000, 32)
	floor_body.add_child(shape)
	game.world.add_child(floor_body)
	await physics_frame
	await process_frame
	for i in range(8): p._physics_process(1.0/60.0)
	check(p.is_on_floor(), "ordinary action fixture grounded")
	game.boss_impact.override_enabled = 1
	game.boss_impact.start(p.position, "secret")
	game.boss_impact.set_process(false)
	game.boss_impact.advance(0.1)
	var scales := [Engine.time_scale, AudioServer.playback_speed_scale, Engine.physics_ticks_per_second]
	var enemy := Enemy.new()
	enemy.game = game
	enemy.position = p.position+Vector2(900, -200)
	game.world.add_child(enemy)
	enemy.set_physics_process(false)
	for actor: Node in [p, enemy]:
		for guided: bool in [false, true]:
			var bullet: Node = game.spawn_bullet(actor, Vector2.RIGHT, guided)
			retained(("player" if actor == p else "enemy")+(" homing" if guided else " normal"), scales)
			bullet.free()
	Input.action_press("move_right")
	p._physics_process(1.0/60.0)
	Input.action_release("move_right")
	check(p.velocity.x > 0, "movement exercised")
	retained("move", scales)
	action_event("jump")
	p._physics_process(1.0/60.0)
	check(p.velocity.y < 0, "ground jump exercised")
	retained("jump", scales)
	var color: int = p.polarity
	action_event("switch_color")
	check(p.polarity == 1-color, "color switch exercised")
	retained("switch", scales)
	p.abilities = T.ABILITY_DOUBLE | T.ABILITY_DASH | T.ABILITY_GLIDE
	p.coyote = 0.0
	action_event("jump")
	p._physics_process(1.0/60.0)
	check(p.air_jump_used, "air jump exercised")
	retained("air jump", scales)
	action_event("dash")
	p._physics_process(1.0/60.0)
	check(p.air_dash_used and p.dash_remaining > 0, "dash exercised")
	retained("dash", scales)
	p.dash_remaining = 0.0
	p.velocity.y = 200.0
	Input.action_press("jump")
	p._physics_process(1.0/60.0)
	Input.action_release("jump")
	check(p.gliding, "glide exercised")
	retained("glide", scales)
	check(p.receive_hit(p.polarity, 12) == "absorbed", "same color absorption exercised")
	retained("absorb", scales)
	p.invulnerability = 0.0
	var hp: int = p.hp
	check(p.receive_hit(1-p.polarity, 12) == "damaged" and p.hp < hp and not p.dead, "nonlethal damage exercised")
	retained("hurt", scales)
	check(p.heal(6) == 6, "healing exercised")
	retained("heal", scales)
	p.hp -= 40
	game.potions = 1
	game.use_potion()
	check(game.potions == 0, "potion exercised")
	retained("potion", scales)
	Input.action_press("shoot")
	p.shot_cooldown = 0.0
	p.homing_charges = 1
	action_event("special")
	p._physics_process(1.0/60.0)
	Input.action_release("shoot")
	check(p.shot_cooldown > 0 and p.homing_charges == 0, "held shooting and homing input exercised")
	retained("held fire and special", scales)
	game.boss_impact.cancel()
	floor_body.free()
	enemy.free()

func replay(enabled: bool) -> Array:
	# Run both logical replays inside one physics callback with the same cached
	# move_and_slide delta. 72Hz / fixed-60 frame boundaries alternate otherwise.
	var globals := [Engine.time_scale, AudioServer.playback_speed_scale, Engine.physics_ticks_per_second]
	Engine.time_scale = 1.0
	AudioServer.playback_speed_scale = 1.0
	Engine.physics_ticks_per_second = 60
	seed(73124)
	game.start_run(37)
	game.streaming_enabled = false
	freeze()
	game.world.process_mode = Node.PROCESS_MODE_INHERIT
	for child in game.world.get_children(): child.set_physics_process(false)
	await physics_frame
	await physics_frame
	game.boss_impact.override_enabled = 1 if enabled else 0
	var result := []
	for i in range(1800):
		test_progress()
		var p: Node = game.player
		p.invulnerability = 10000.0
		if i % 60 == 0: p.jump_buffer = 0.1
		if i == 20:
			var actor := Enemy.new()
			actor.game = game
			actor.kind = "boss"
			actor.boss_role = "guardian"
			actor.boss_id = 0
			actor.spawn_id = "impact-replay"
			actor.position = p.position+Vector2(180, 0)
			game.world.add_child(actor)
			actor.dead = true
			game.actor_defeated(actor)
			actor.queue_free()
		if game.boss_impact.active:
			game.boss_impact.set_process(false)
			game.boss_impact.advance(1.0/60.0)
		game._physics_process(1.0/60.0)
		p._physics_process(1.0/60.0)
		result.append(var_to_bytes([p.position,p.velocity,p.hp,p.polarity,p.homing_charges,game.score,game.crystals,game.keys,game.loot_drops,game.defeated_bosses,game.kills,game.elapsed]))
	game.boss_impact.cancel()
	Engine.time_scale = globals[0]
	AudioServer.playback_speed_scale = globals[1]
	Engine.physics_ticks_per_second = globals[2]
	return result

func run() -> void:
	game = Main.new()
	game.controls_path = "res://builds/qa/sound/task8d/impact-controls.cfg"
	game.audio_settings_path = "res://builds/qa/sound/task8d/impact-audio.cfg"
	game.audio_synthesis_override = 0
	root.add_child(game)
	freeze()
	var fx: Node = game.boss_impact
	game.state = "playing"
	fx.start(game.player.position, "guardian")
	check(not fx.active, "headless default skips effects")
	fx.override_enabled = 1
	var original := [0.9, 1.1, 72]
	Engine.time_scale = original[0]
	AudioServer.playback_speed_scale = original[1]
	Engine.physics_ticks_per_second = original[2]
	original = [Engine.time_scale, AudioServer.playback_speed_scale, Engine.physics_ticks_per_second]
	await regular_actions()
	restored("ordinary actions cleanup", original)
	game.start_run(37)
	freeze()
	for role: String in ["guardian", "final", "secret"]:
		fx.start(game.player.position, role)
		fx.set_process(false)
		var depth := 0.30 if role == "guardian" else 0.22
		var hold := 0.55 if role == "guardian" else 0.85
		check(fx.hold == hold and fx.depth == depth and fx.amplitude == (22.0 if role == "guardian" else 30.0), role+": tuning")
		for step in range(1, 151):
			fx.advance(0.01)
			var time := step*0.01
			if fx.active:
				var expected: float = fx.factor(time)
				check(absf(Engine.time_scale/original[0]-expected) < 0.000001, role+": time curve %d" % step)
				check(absf(AudioServer.playback_speed_scale/original[1]-expected) < 0.000001, role+": audio curve %d" % step)
				check(Engine.physics_ticks_per_second == original[2], role+": real physics tick rate retained")
			if time >= 0.05 and time < 0.05+hold: check(absf(Engine.time_scale-original[0]*depth) < 0.000001, role+": hold")
			if step == 129: check(fx.active, role+": still active before real end")
		restored(role, original)
	for state: String in ["paused", "map", "shop", "equipment", "settings", "audio_settings", "lost", "won", "title"]:
		game.state = "playing"
		fx.start(game.player.position, "secret")
		fx.advance(0.1)
		game.state = state
		restored(state, original)
	game.state = "playing"
	fx.start(game.player.position, "guardian")
	fx.advance(0.3)
	var speed: float = Engine.time_scale
	var new_point: Vector2 = game.player.position+Vector2(100, 50)
	fx.start(new_point, "secret")
	fx.set_process(false)
	check(is_equal_approx(fx.factor(0.0), speed/original[0]) and fx.ring_age == 0.0 and game.local_point(fx.center) == new_point, "successive defeat extends slow without speed jump and changes center")
	fx.advance(1.0)
	check(fx.active, "successive defeat extends duration")
	game.camera.force_update_scroll()
	var before: Vector2 = fx.screen_center()
	game.shift_origin(Vector2i(2, -1))
	check(fx.screen_center().distance_to(before) < 0.01, "world center survives origin shift")
	game.camera.position += Vector2(80, 0)
	game.camera.force_update_scroll()
	check(fx.screen_center().distance_to(before-Vector2(80, 0)) < 0.01, "world center tracks camera")
	fx.start(game.camera.position-Vector2(4000, 0), "guardian")
	check(fx.screen_center().x < 0, "offscreen defeat center stays outside viewport without clamping")
	fx.cancel()
	fx.start(game.player.position, "secret")
	game.player.dead = true
	fx.advance(0.01)
	restored("player death", original)
	game.player.dead = false
	fx.start(game.player.position, "guardian")
	game.start_run(37)
	freeze()
	restored("retry", original)
	game.state = "playing"
	fx.override_enabled = 1
	var actor := Enemy.new()
	actor.game = game
	actor.kind = "enhancer"
	actor.spawn_id = "no-impact"
	game.world.add_child(actor)
	game.actor_defeated(actor)
	check(not fx.active, "enhancer excluded")
	actor.queue_free()
	var normal := Enemy.new()
	normal.game = game
	normal.kind = "turret"
	normal.spawn_id = "no-impact-normal"
	game.world.add_child(normal)
	game.actor_defeated(normal)
	check(not fx.active, "normal enemy excluded")
	normal.queue_free()
	fx.start(game.player.position, "guardian")
	game.start_tutorial()
	check(not fx.active and game.tutorial_session.boss_impact == null, "tutorial entry cancels effect and tutorial has no effect")
	fx.start(game.player.position, "guardian")
	check(not fx.active, "tutorial host excludes effects")
	game.finish_tutorial()
	game.state = "playing"
	fx.override_enabled = 1
	game.boss_cycle.phase = "complete"
	game.ending = true
	fx.start(game.player.position, "secret")
	fx.set_process(false)
	game._finish_run()
	check(game.state == "playing", "clear screen waits for effect")
	fx.advance(1.51)
	await process_frame
	check(game.state == "won", "clear screen after effect")
	game.start_run(37)
	freeze()
	game.state = "playing"
	# Media clock continues existing voices for their actual slowed duration.
	game.audio.streams.hurt = AudioStreamWAV.load_from_file("res://assets/audio/sfx/hurt.wav")
	var handle: int = game.audio.play("hurt")
	var voice: Dictionary = game.audio.voices[handle%32]
	var until: float = voice.until
	var clock: float = game.audio.clock_ms
	Engine.time_scale = 0.3
	AudioServer.playback_speed_scale = 0.3
	game.audio._process(0.03)
	check(absf(game.audio.clock_ms-clock-30.0) < 0.0001 and voice.until == until, "voice deadline uses 30ms media for 100ms real")
	Engine.time_scale = original[0]
	AudioServer.playback_speed_scale = original[1]
	for id: String in ["hurt", "boss_defeat", "enemy_defeat"]:
		game.audio.music_ids = ["", ""]
		game.audio.music_gain = [1.0, 0.0]
		game.audio.music_target = [1.0, 0.0]
		game.audio.music[0].volume_db = 0.0
		game.audio.duck_db = 0.0
		game.audio.music_result_db = [0.0, 0.0]
		game.audio.trigger_impact_duck(id)
		check(game.audio.impact_duck_db == (-4.0 if id == "enemy_defeat" else -7.0), id+": immediate duck")
		check(is_equal_approx(game.audio.music[0].volume_db, -4.0 if id == "enemy_defeat" else -7.0), id+": output ducks immediately before next frame")
		game.audio.duck_db = -10.0
		game.audio.music_result_db = [-9.0, -9.0]
		game.audio.ending_started = true
		game.state = "paused"
		game.audio._process(0.01*Engine.time_scale)
		check(absf(game.audio.music[0].volume_db+14.0) < 0.001, "combined duck capped -14dB at output")
		game.audio._process(0.3*Engine.time_scale)
		check(game.audio.impact_duck_db == 0.0, "duck returns in 300ms real")
	game.audio.stop_world()
	var silent: Array = await replay(false)
	var audible: Array = await replay(true)
	for i in range(1800): check(silent[i] == audible[i], "effect off/on exact logical frame %d" % i)
	game.state = "playing"
	fx.override_enabled = 1
	fx.start(game.player.position, "guardian")
	# Run the production wall-clock path (not advance()) to measure duration.
	var began := Time.get_ticks_usec()
	while fx.active:
		test_progress()
		OS.delay_msec(2)
		await process_frame
	var seconds := (Time.get_ticks_usec()-began)/1000000.0
	timings.guardian_real_seconds = seconds
	check(seconds >= 1.3 and seconds < 1.6, "guardian real-time duration 1.3s")
	fx.start(game.player.position, "secret")
	fx.advance(0.1)
	game.free()
	game = null
	check([Engine.time_scale, AudioServer.playback_speed_scale, Engine.physics_ticks_per_second] == original, "exit tree restores exact globals")
	Engine.time_scale = 1.0
	AudioServer.playback_speed_scale = 1.0
	Engine.physics_ticks_per_second = 60
	FileAccess.open("res://builds/qa/sound/task8d/impact-results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"timings":timings},"\t"))
	print("IMPACT RESULT: ",checks," checks, ",failures.size()," failures ",timings)
	quit(0 if failures.is_empty() else 1)
