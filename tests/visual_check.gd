extends "res://tests/test_tree.gd"
const Main := preload("res://scripts/main.gd")
const T := preload("res://scripts/tuning.gd")
const S := preload("res://scripts/sector_generator.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Support := preload("res://tests/stream_test_support.gd")
const OUTPUT := "res://builds/qa/rewards/"
var game: Node2D
var failures := 0
var captures := 0
var output := OUTPUT
func _initialize():
	if OS.get_cmdline_user_args().has("--abilities"):
		output = "res://builds/qa/abilities/"
		call_deferred("run_abilities")
	elif OS.get_cmdline_user_args().has("--tutorial"):
		output = "res://builds/qa/tutorial/"
		call_deferred("run_tutorial")
	elif OS.get_cmdline_user_args().has("--streaming"):
		output = "res://builds/qa/streaming/"
		call_deferred("run_streaming")
	elif OS.get_cmdline_user_args().has("--rewards"): call_deferred("run")
	else:
		output = "res://builds/qa/bosses/"
		call_deferred("run_bosses")

func action_input(action: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func run_abilities() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	game = Main.new()
	game.controls_path = output + "visual_controls.cfg"
	root.add_child(game)
	game.key_bindings.reset_defaults()
	game.start_run(37)
	game.elapsed = 9
	var loot: Array = get_nodes_in_group("loot").filter(func(i): return i.get_parent() == game.world and i.spawn.sector == Vector2i.ZERO)
	var key = loot.filter(func(i): return i.spawn.kind == "key")[0]
	var chest = loot.filter(func(i): return i.spawn.kind == "chest" and i.spawn.contents[0].kind == "ability")[0]
	await show(key.position - Vector2(64, 0))
	await capture("key_and_map")
	await show(chest.position - Vector2(32, 0))
	await capture("ability_chest_closed")
	game.player.position = chest.position
	chest.try_open()
	await capture("key_required")
	game.keys = 1
	chest.try_open()
	game.player.position = chest.position - Vector2(56,0)
	await capture("ability_learned_and_open_chest")
	for ability: int in [T.ABILITY_DASH,T.ABILITY_GLIDE]:
		game.grant_loot({"kind":"ability","ability":ability})
		await capture("dash_learned" if ability==T.ABILITY_DASH else "glide_learned")
	var ordinary = loot.filter(func(i): return i.spawn.kind == "chest" and i.spawn.contents[0].kind == "crystal")[0]
	await show(ordinary.position - Vector2(56, 0))
	await capture("normal_chest_closed")
	game.keys = 1
	ordinary.try_open()
	await capture("normal_chest_open_crystals")
	var branch: Dictionary = game.stream.loaded[Vector2i.ZERO].detours[0]
	await show(branch.position - Vector2(0, 80))
	await capture("detour")
	var room: Dictionary = game.stream.loaded[Vector2i.ZERO].chambers.filter(func(r): return r.kind == "start")[0]
	var start := Vector2(room.rect.position.x + 64, room.rect.end.y - 22)
	await show(start)
	game.loot_message_remaining = 0
	game.streaming_enabled = false
	game.player.abilities = 7
	game.player.set_physics_process(true)
	game.set_physics_process(true)
	await frames(3)
	action_input("jump",true)
	await frames(T.ABILITY_SECOND_JUMP_FRAME)
	action_input("jump",false)
	action_input("jump",true)
	await frames(8)
	if not game.player.air_jump_used: failures += 1
	await capture("double_jump")
	game.player.facing = 1
	action_input("dash",true)
	await frames(3)
	if game.player.dash_remaining <= 0: failures += 1
	await capture("air_dash")
	action_input("dash",false)
	action_input("jump",false)
	await frames(35)
	# Rendering fixture for held-jump glide, with an already spent air jump.
	game.player.position = start - Vector2(-180,250)
	game.player.velocity = Vector2(0,180)
	await frames(1)
	game.player.coyote = 0
	game.player.air_jump_used = true
	action_input("jump",true)
	await frames(5)
	if not game.player.gliding: failures += 1
	await capture("glide")
	action_input("jump",false)
	game.player.set_physics_process(false)
	game.set_physics_process(false)
	game.keys = 3
	game.add_crystals(150)
	await capture("hud_crystals_keys")
	game.show_menu("lost")
	await capture("result_crystals")
	FileAccess.open(output + "visual_results.json", FileAccess.WRITE).store_string(JSON.stringify({"captures":captures,"failures":failures,"renderer":RenderingServer.get_video_adapter_name()},"\t"))
	game.free()
	print("ABILITY VISUAL CHECK: %d captures, %d failures" % [captures,failures])
	quit(0 if failures == 0 else 1)

func run_tutorial():
	DirAccess.make_dir_recursive_absolute(output)
	var host := Main.new()
	host.controls_path = output + "visual_controls.cfg"
	root.add_child(host)
	host.key_bindings.reset_defaults()
	game = host
	await capture("title")
	host.start_tutorial()
	game = host.tutorial_session
	game.show_menu("paused")
	await capture("paused")
	game.resume_run()
	var driver := preload("res://tests/tutorial_driver.gd").new()
	driver.tree = self
	driver.game = game
	driver.capture = capture
	await driver.run()
	failures += driver.failures.size()
	FileAccess.open(output + "visual_results.json", FileAccess.WRITE).store_string(JSON.stringify({"captures": captures, "failures": failures, "input_checks": driver.checks, "renderer": RenderingServer.get_video_adapter_name()}, "\t"))
	host.free()
	print("VISUAL CHECK: %d captures, %d failures" % [captures, failures])
	quit(0 if failures == 0 else 1)
func frames(n: int):
	for i in range(n):
		test_progress()
		await physics_frame
		test_progress()
		await process_frame
func capture(name: String):
	game.ui.update_hud()
	await frames(2)
	test_progress()
	await RenderingServer.frame_post_draw
	var code := root.get_texture().get_image().save_png(output + name + ".png")
	captures += 1
	if code != OK:
		failures += 1
		printerr("CAPTURE FAILED ", name)
	else: print("CAPTURE ", name)
func show(point: Vector2) -> bool:
	if not await Support.ready(self, game, point):
		failures += 1
		return false
	game.player.position = point
	game.player.velocity = Vector2.ZERO
	game._update_camera(0, true)
	game._update_exploration()
	game.ui.update_hud()
	await frames(3)
	return true
func run():
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	game = Main.new()
	game.controls_path = OUTPUT + "visual_controls.cfg"
	root.add_child(game)
	game.start_run(37)
	var h = get_nodes_in_group("hearts").filter(func(n): return n.get_parent() == game.world)[0]
	await show(h.position - Vector2(96, 0))
	await capture("heart")
	game.player.hp = 50
	game.player.position = h.position
	h.try_collect()
	await capture("heart_heal")
	var rect: Rect2 = game.stream.loaded[Vector2i.ZERO].breakables[0]
	await show(rect.get_center() - Vector2(64, 6))
	game.player.hp = 50
	var bullet = game.spawn_bullet(game.player, Vector2.RIGHT, true)
	bullet.position = rect.get_center() - Vector2(40, 0)
	await frames(8)
	if game.player.hp != 56: failures += 1
	await capture("box_heal")
	game.player.homing_charges = 3
	game.player.gauge = 2
	game.elapsed = 9.0
	await capture("stocks_absorption")
	var target = get_nodes_in_group("enemies").filter(func(e): return e.get_parent() == game.world and e.kind != "boss" and not e.dead)[0]
	await show(target.position - Vector2(100, 0))
	game.player.homing_charges = 1
	target.receive_hit(1 - target.polarity, T.ENEMY_HP)
	await capture("defeat_stock")
	game.start_run(37)
	var room: Dictionary = game.stream.loaded[Vector2i.ZERO].chambers.filter(func(r): return r.kind == "start")[0]
	await show(Vector2(room.rect.position.x + 160, room.rect.end.y - 22))
	game.elapsed = 9.0
	game.player.polarity = 0
	game.player.homing_charges = 3
	game.player.gauge = 2
	for i in range(4):
		var e := Enemy.new()
		e.game = game
		e.polarity = 1
		e.kind = "flyer"
		e.position = game.player.position + Vector2(280 + i * 40, -i * 120)
		e.patrol = Vector2(e.position.x, e.position.x)
		game.world.add_child(e)
		e.set_physics_process(false)
	game._update_lock_marks()
	game.player.launch_homing()
	await frames(8)
	if game.projectiles.get_child_count() != T.HOMING_VOLLEY_SIZE or game.player.homing_charges != 2: failures += 1
	await capture("volley")
	FileAccess.open(OUTPUT + "visual_results.json", FileAccess.WRITE).store_string(JSON.stringify({"captures": captures, "failures": failures, "renderer": RenderingServer.get_video_adapter_name()}, "\t"))
	game.free()
	print("VISUAL CHECK: ", captures, " captures, ", failures, " failures")
	quit(0 if failures == 0 else 1)

# Keep the Task 5B streaming captures available with -- --streaming.
func boss_actor(id: int) -> Node2D:
	for e in get_nodes_in_group("enemies"):
		if e.get_parent() == game.world and e.kind == "boss" and e.boss_id == id and not e.dead and not e.is_queued_for_deletion(): return e
	return null

func wait_boss_selection():
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		game.boss_cycle.service()
		if game.boss_cycle.selection == null: return
		await frames(1)
		OS.delay_msec(1)
	failures += 1

func kill_boss(e: Node2D):
	if not require_boss(e): return
	e.receive_hit(1-e.polarity,9999)
	await frames(2)
	await wait_boss_selection()

func live_records(role: String) -> Array:
	return game.boss_cycle.records.values().filter(func(r): return r.role == role and r.alive)

func show_boss(record: Dictionary) -> Node2D:
	if not await show(game.boss_cycle.world_record(record).position + Vector2(240, 25)): return null
	game.player.invulnerability = 10000
	if not await wait_until(func(): return is_instance_valid(boss_actor(record.boss_id))):
		failures += 1
		printerr("FAIL: visual boss detection timed out")
		return null
	return boss_actor(record.boss_id)

func require_boss(e: Node2D) -> bool:
	if is_instance_valid(e): return true
	failures += 1
	printerr("FAIL: visual guardian/boss missing after sector preparation")
	quit(1)
	return false

func kill_guardians():
	for record: Dictionary in live_records("guardian"):
		var e = await show_boss(record)
		if not require_boss(e): return
		await kill_boss(e)

func run_bosses():
	DirAccess.make_dir_recursive_absolute(output)
	game = Main.new()
	game.controls_path = output + "visual_controls.cfg"
	root.add_child(game)
	game.start_run(37)
	game.elapsed = 9
	for at: Vector2i in S.guardian_sectors(37):
		await show(Vector2(at)*T.SECTOR_SIZE+T.SECTOR_START)
		var id := S.guardian_sectors(37).find(at)
		var e = boss_actor(id)
		if not require_boss(e): return
		await show(e.position+Vector2(240,25))
		game.player.invulnerability = 10000
		if id == 0:
			await capture("guardian_move_before")
			var before: Vector2 = e.position
			e.set_physics_process(true)
			await frames(100)
			e.set_physics_process(false)
			if before.distance_to(e.position) < 10: failures += 1
			await capture("guardian_move_after")
		await kill_boss(e)
	await capture("final_spawn")
	await capture("final_map_edge")
	var final: Dictionary = live_records("final")[0]
	var e = await show_boss(final)
	if not require_boss(e): return
	game.announcement_remaining = 0
	e.set_physics_process(true)
	await frames(100)
	e.set_physics_process(false)
	await capture("final_boss")
	await capture("final_map_inside")
	await kill_boss(e)
	await capture("guardian_revival")
	for cycle in range(2):
		await kill_guardians()
		e = await show_boss(live_records("final")[0])
		await kill_boss(e)
	await capture("secret_spawn")
	e = await show_boss(live_records("secret")[0])
	if not require_boss(e): return
	game.announcement_remaining = 0
	e.set_physics_process(true)
	await frames(100)
	e.set_physics_process(false)
	await capture("secret_boss")
	game.elapsed = 1062
	await kill_boss(e)
	await capture("clear_result")
	if game.state != "won": failures += 1
	FileAccess.open(output+"visual_results.json",FileAccess.WRITE).store_string(JSON.stringify({"captures":captures,"failures":failures,"renderer":RenderingServer.get_video_adapter_name(),"note":"boss progression and time are controlled QA fixtures"},"\t"))
	game.free()
	print("VISUAL CHECK: %d captures, %d failures" % [captures,failures])
	quit(0 if failures==0 else 1)

func run_streaming():
	DirAccess.make_dir_recursive_absolute(output)
	game = Main.new()
	game.controls_path = output + "visual_controls.cfg"
	root.add_child(game)
	game.start_run(37)
	await show(T.SECTOR_START)
	await capture("start")
	var gate: Dictionary = S.boundary_gates(37,Vector2i.ZERO,Vector2i.RIGHT)[0]
	await show(Vector2(gate.rect.position.x,gate.rect.end.y-22))
	await capture("seam_horizontal")
	gate = S.boundary_gates(37,Vector2i.ZERO,Vector2i.DOWN)[0]
	await show(Vector2(gate.rect.position.x+128,gate.rect.position.y-54))
	await capture("seam_vertical")
	var at: Vector2i = S.guardian_sectors(37)[0]
	await show(Vector2(at)*T.SECTOR_SIZE+T.SECTOR_START)
	var guardian = get_nodes_in_group("enemies").filter(func(e): return e.kind=="boss" and e.get_meta("sector",Vector2i.ZERO)==at)[0]
	await show(guardian.position+Vector2(160,T.BOSS_SIZE.y/2-22))
	guardian.receive_hit(1-guardian.polarity,4)
	game.ui.update_hud()
	await frames(2)
	await capture("guardian")
	await show(T.SECTOR_START)
	for y in range(-8,20):
		for x in range(-12,32):
			var cell := Vector2i(x,y)
			if (Vector2(cell)*T.MAP_CELL_SIZE-game.player.position).length()<1800: game.explored_cells[cell]=true
	game.ui.minimap.update_map()
	await frames(3)
	await capture("map_offscreen_guardian")
	await show(Vector2(50,-20)*T.SECTOR_SIZE+T.SECTOR_START)
	var far: Dictionary = game.stream.loaded[Vector2i(50,-20)]
	await show(far.start_position)
	var bullet=game.spawn_bullet(game.player,Vector2.RIGHT)
	bullet.set_physics_process(false)
	bullet.position=game.player.position+Vector2(90,-4)
	await frames(2)
	await capture("far_sector")
	game.show_menu("paused")
	await frames(3)
	await capture("paused")
	game.kills=12
	for id in range(3): game.defeated_bosses[id]=true
	game.show_menu("won")
	await frames(3)
	await capture("result")
	FileAccess.open(output+"visual_results.json",FileAccess.WRITE).store_string(JSON.stringify({"captures":8,"failures":failures,"renderer":RenderingServer.get_video_adapter_name()},"\t"))
	game.free()
	print("VISUAL CHECK: 8 captures, ", failures, " failures")
	quit(0 if failures==0 else 1)
