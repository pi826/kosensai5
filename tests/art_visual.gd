extends "res://tests/test_tree.gd"
## Normal renderer QA with real generated terrain; controlled actor placements.
const Main := preload("res://scripts/main.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Art := preload("res://scripts/sprite_art.gd")
const S := preload("res://scripts/sector_generator.gd")
const OUT := "res://builds/qa/art/stage1/"
var game: Node2D
var failures: Array[String] = []
var captures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message); printerr("FAIL: "+message)

func frames(count: int) -> void:
	for i in range(count):
		test_progress()
		await process_frame

func capture(name: String) -> void:
	game.ui.update_hud()
	await frames(3)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUT+name+".png") == OK,"capture "+name)
	captures += 1

func refresh() -> void:
	for actor in get_nodes_in_group("combatants"): actor.queue_redraw()
	for chunk in game.terrain.draw_chunks.values(): chunk.queue_redraw()
	game.ui.update_hud()

func run() -> void:
	check(DisplayServer.get_name() != "headless","normal renderer required")
	if not failures.is_empty(): quit(1); return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var seed_value := 1
	while S.region_at(seed_value,Vector2i.ZERO) != 0: seed_value += 1
	game = Main.new()
	game.controls_path = OUT+"visual-controls.cfg"
	game.audio_settings_path = OUT+"visual-audio.cfg"
	game.audio_synthesis_override = 0
	root.add_child(game)
	game.start_run(seed_value)
	game.set_physics_process(false)
	game.world.process_mode = Node.PROCESS_MODE_DISABLED
	game.state = "playing"
	game.ui.menu.hide()
	game.elapsed = 12
	game.camera.position = game.player.position + Vector2(120,-140)
	game.camera.force_update_scroll()
	game._update_exploration()
	game.terrain.prepare_view(game.view_rect())
	game.stream.prepare_backdrop_view(game.view_rect())
	var fixtures := []
	for kind in ["walker","flyer"]:
		var e := Enemy.new()
		e.game = game; e.kind = kind; e.spawn_id = "art-qa-"+kind
		e.position = game.player.position + (Vector2(220,0) if kind == "walker" else Vector2(380,-120))
		e.facing = -1
		game.world.add_child(e)
		fixtures.append(e)
	# Warm shader, fonts and texture creation before measuring either art set.
	await frames(30)
	var load_deadline := Time.get_ticks_msec()+30000
	while not Art._pending.is_empty() and Time.get_ticks_msec()<load_deadline: await frames(1)
	check(Art._pending.is_empty(),"asynchronous sprite prewarm finished")
	var samples := {}
	for selected in ["shapes","sprites"]:
		Art.mode_override = selected
		refresh()
		await frames(20)
		var wall: Array[float] = []
		var draws: Array[float] = []
		for i in range(120):
			var began := Time.get_ticks_usec()
			for actor in get_nodes_in_group("combatants"): actor.tick_visuals(1.0/60.0)
			await RenderingServer.frame_post_draw
			wall.append((Time.get_ticks_usec()-began)/1000.0)
			draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			test_progress()
		wall.sort(); draws.sort()
		samples[selected] = {"samples":120,"wall_frame_mean_ms":wall.reduce(func(a,b):return a+b,0.0)/wall.size(),"wall_frame_p95_ms":wall[113],"wall_frame_max_ms":wall[-1],"draw_calls_median":draws[60]}
		if selected == "shapes": await capture("game-shapes")
	for color in [0,1]:
		game.player.polarity = color
		for e in fixtures: e.polarity = color
		refresh()
		await capture("game-"+("blue" if color == 0 else "orange"))
		check(game.player.art_sprite_drawn,"player sprite drawn")
		for e in fixtures: check(e.art_sprite_drawn,e.kind+" sprite drawn")
	var boss := Enemy.new()
	boss.game=game; boss.kind="boss"; boss.boss_id=999; boss.spawn_id="art-hud-boss"
	boss.position=game.player.position+Vector2(420,-220)
	game.world.add_child(boss)
	game.boss=boss
	for color in [0,1]:
		boss.polarity=color; game.player.polarity=color
		boss.queue_redraw(); game.player.queue_redraw()
		await capture("game-boss-hud-"+("blue" if color==0 else "orange"))
		check(game.ui.boss_color_icon.visible and not game.ui.boss_label.text.contains(" / "),"boss color icon replaces text")
	boss.free(); game.boss=null
	fixtures[0].lock_marked=true; fixtures[0].gauge=3
	fixtures[0].action="windup_shot"; fixtures[0].absorb_flash=0.2
	fixtures[0].queue_redraw()
	await capture("game-indicators")
	fixtures[0].action="idle"; fixtures[0].lock_marked=false; fixtures[0].absorb_flash=0
	# Per-ID missing image, repeated requests, and a healthy sibling in one frame.
	var broken := "res://assets/art/enemies/walker-blue.png"
	Art.path_overrides[broken] = OUT+"deliberately-missing.png"
	Art.texture(broken,broken)
	await frames(5)
	game.player.polarity = 0
	for e in fixtures: e.polarity = 0
	for i in range(3): check(Art.texture(broken,broken) == null,"missing ID falls back")
	check(Art._warnings.size() == 1,"one warning across repeated missing requests")
	refresh(); await capture("game-missing-walker")
	check(not fixtures[0].art_sprite_drawn and fixtures[1].art_sprite_drawn and game.player.art_sprite_drawn,"only missing walker falls back")
	Art.path_overrides.clear()
	refresh()
	# Actual screen distortion keeps advancing over sprites; shooting must not cancel it.
	game.boss_impact.start(game.player.position+Vector2(220,-60),"guardian")
	game.player.fire_normal()
	game.boss_impact.advance(0.15)
	check(game.boss_impact.active and game.boss_impact.ring_age >= 0.15,"impact survives firing with sprite set")
	await capture("game-impact")
	game.boss_impact.cancel()
	# Death uses the normal damage/delete path without retaining a collidable actor.
	fixtures[0].receive_hit(1-fixtures[0].polarity,999)
	game.world.process_mode=Node.PROCESS_MODE_INHERIT
	for actor in get_nodes_in_group("combatants"): actor.set_physics_process(false)
	await frames(3)
	check(not is_instance_valid(fixtures[0]),"dead actor removed immediately")
	check(not get_nodes_in_group("sprite_remnants").is_empty(),"visual death remnant exists")
	await capture("game-death")
	await create_timer(0.55).timeout
	check(get_nodes_in_group("sprite_remnants").is_empty(),"visual remnant expires without gameplay actor")
	var metrics := {"renderer":RenderingServer.get_video_adapter_name(),"seed":seed_value,"viewport":[1280,720],"sets":samples,"note":"same generated waterway scene, stationary camera/physics, actor visual clocks only; vsync disabled and uncapped, wall includes CPU/GPU scheduling, not isolated GPU time", "captures":captures,"failures":failures}
	FileAccess.open(OUT+"frame-time.json",FileAccess.WRITE).store_string(JSON.stringify(metrics,"\t"))
	game.free()
	print("ART VISUAL: %d captures, failures: %d" % [captures,failures.size()])
	quit(0 if failures.is_empty() else 1)
