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
	if OS.get_cmdline_user_args().has("--sound"):
		output = "res://builds/qa/sound/"
		call_deferred("run_sound")
	elif OS.get_cmdline_user_args().has("--diagonal") or OS.get_cmdline_user_args().has("--shafts"):
		output = "res://builds/qa/diagonal/after-images/"
		if OS.get_cmdline_user_args().has("--before"): output = "res://builds/qa/diagonal/before-images/"
		if OS.get_cmdline_user_args().has("--shafts"):
			output = "res://builds/qa/shafts/%s-images/" % ("before" if OS.get_cmdline_user_args().has("--before") else "after")
			if OS.get_cmdline_user_args().has("--long-shaft"): output=output.replace("-images/","-long-images/")
		call_deferred("run_diagonal")
	elif OS.get_cmdline_user_args().has("--enemies"):
		output = "res://builds/qa/enemies/"
		call_deferred("run_enemies")
	elif OS.get_cmdline_user_args().has("--ui-map"):
		output = "res://builds/qa/ui_map/"
		call_deferred("run_ui_map")
	elif OS.get_cmdline_user_args().has("--boss-arrow"):
		output = "res://builds/qa/boss_arrow/"
		call_deferred("run_boss_arrow")
	elif OS.get_cmdline_user_args().has("--merchant"):
		output = "res://builds/qa/merchant/"
		call_deferred("run_merchant")
	elif OS.get_cmdline_user_args().has("--abilities"):
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

func run_sound() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	game = Main.new()
	game.controls_path = output+"visual-controls.cfg"
	game.audio_settings_path = output+"visual-audio.cfg"
	game.audio_synthesis_override = 0
	root.add_child(game)
	game.set_physics_process(false)
	for state in ["title","paused","lost","won"]:
		game.show_menu(state)
		await capture("sound-"+state)
		game.open_audio_settings()
		await capture("sound-"+state+"-panel")
		game.ui.audio_panel._close()
	game.show_menu("title")
	game.start_tutorial()
	await frames(2)
	game.tutorial_session.show_menu("paused")
	await capture("sound-tutorial-paused")
	game.tutorial_session.open_audio_settings()
	await capture("sound-tutorial-panel")
	game.finish_tutorial()
	await frames(2)
	FileAccess.open(output+"visual-results.json",FileAccess.WRITE).store_string(JSON.stringify({"captures":captures,"failures":failures,"renderer":RenderingServer.get_video_adapter_name()},"\t"))
	game.free()
	quit(0 if failures==0 else 1)

func run_boss_arrow() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	game = Main.new()
	game.controls_path = output + "visual_controls.cfg"
	root.add_child(game)
	game.start_run(37)
	game.elapsed = 9
	if not await show(T.SECTOR_START): quit(1); return
	for e in get_nodes_in_group("enemies"): e.set_physics_process(false)
	game.world.process_mode = Node.PROCESS_MODE_DISABLED
	# Defeats use the real reward/unlock handler. Positions below are QA fixtures.
	var normals := get_nodes_in_group("enemies").filter(func(e): return e.get_parent() == game.world and e.kind not in ["boss","enhancer"])
	for i in range(7): normals[i].receive_hit(1 - normals[i].polarity, 999)
	await capture("arrow_progress")
	for i in range(7, 10): normals[i].receive_hit(1 - normals[i].polarity, 999)
	var lantern = get_nodes_in_group("enhancers").filter(func(e):return e.get_parent()==game.world)[0]
	lantern.receive_hit(1-lantern.polarity,999)
	await capture("arrow_unlock")
	game.announcement_remaining = 0
	game.effects.show_player_health(game.player, 100, 70)
	game.player.hp = 70
	# One controlled record for repeatable directions, no terrain generation.
	game.boss_cycle.phase = "final"
	var id := 900
	var directions := {"right": Vector2.RIGHT, "left": Vector2.LEFT, "up": Vector2.UP,
		"down": Vector2.DOWN, "upper_right": Vector2(1, -1).normalized()}
	for name: String in directions:
		var point: Dictionary = game.stable_point(game.player.position + directions[name] * 8500)
		game.boss_cycle.records[id] = {"boss_id": id, "role": "final", "alive": true,
			"sector": point.sector, "sector_local": true, "position": point.local}
		if game.boss_arrow_state().is_empty(): failures += 1
		await capture("arrow_" + name)
	# Use an actual boss body to verify disappearance when the target is visible.
	var boss := Enemy.new()
	boss.game = game
	boss.kind = "boss"
	boss.boss_role = "final"
	boss.boss_id = id
	boss.spawn_id = "arrow_visual_boss"
	boss.position = game.player.position + Vector2(240, -40)
	game.world.add_child(boss)
	boss.set_physics_process(false)
	game._update_exploration()
	if not game.boss_arrow_state().is_empty(): failures += 1
	await capture("arrow_target_on_screen")
	FileAccess.open(output + "visual_results.json", FileAccess.WRITE).store_string(JSON.stringify({"captures": captures,
		"failures": failures, "renderer": RenderingServer.get_video_adapter_name(), "note": "directions and visible boss use controlled QA positions; kills use actual defeat handler"}, "\t"))
	game.free()
	print("BOSS ARROW VISUAL: %d captures, %d failures" % [captures, failures])
	quit(0 if failures == 0 else 1)

func run_merchant() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	game = Main.new()
	game.controls_path = output + "visual_controls.cfg"
	root.add_child(game)
	game.key_bindings.reset_defaults()
	game.start_run(37)
	game.elapsed = 9
	var npc = get_nodes_in_group("merchants").filter(func(m): return m.get_parent()==game.world and m.spawn.sector==Vector2i.ZERO)[0]
	await show(npc.position+Vector2(-56,0))
	game.loot_message_remaining = 0
	await capture("merchant_and_prompt")
	await show(T.SECTOR_START)
	await capture("merchant_map_hud")
	await show(npc.position+Vector2(-56,0))
	game.crystals = 250
	game.open_shop(npc)
	await capture("shop_buy_available")
	game.crystals = 5
	game.ui.shop_panel.refresh()
	await capture("shop_buy_insufficient")
	game.crystals = 600
	game.owned_equipment.rapid = true
	game.merchant_sold[npc.spawn.id] = true
	game.ui.shop_panel.refresh()
	await capture("shop_buy_owned_sold")
	for id: String in T.EQUIPMENT: game.owned_equipment[id] = true
	game.equip("weapon","triple")
	game.equip("armor","shell")
	game.equip("charm","homing")
	game.ui.shop_panel._switch_tab(false)
	await capture("equipment_all_slots")
	game.close_shop()
	game.show_menu("paused")
	await capture("pause_equipment_entry")
	game.open_equipment()
	await capture("pause_equipment")
	game.close_shop()
	game.resume_run()
	# Display fixture; no claims about play time or crystal income.
	await show(T.SECTOR_START)
	game.player.fire_normal()
	await frames(8)
	await capture("triple_barrel")
	game.potions = 2
	game.player.hp = 45
	game.use_potion()
	await capture("potion_healing")
	game.player.add_homing_charges(6)
	game.ui.update_hud()
	await capture("equipped_hud")
	game.free()
	print("MERCHANT VISUAL: %d captures, %d failures" % [captures,failures])
	quit(0 if failures==0 else 1)

func run_diagonal() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	var manifest_path := "res://builds/qa/shafts/capture-route.json" if OS.get_cmdline_user_args().has("--shafts") else "res://builds/qa/diagonal/capture-route.json"
	if OS.get_cmdline_user_args().has("--long-shaft"): manifest_path="res://builds/qa/shafts/capture-long-route.json"
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	game = Main.new()
	game.controls_path = output + "visual_controls.cfg"
	root.add_child(game)
	game.key_bindings.reset_defaults()
	game.start_run(int(manifest.seed))
	game.elapsed = 9
	game.set_physics_process(false)
	game.world.process_mode = Node.PROCESS_MODE_DISABLED
	for shot: Dictionary in manifest.shots:
		var point := Vector2(shot.x,shot.y)
		if not await show(point): quit(1); return
		game.world.process_mode = Node.PROCESS_MODE_DISABLED
		game.player.facing = int(shot.facing)
		game.announcement_remaining = 0
		game.loot_message_remaining = 0
		await capture(shot.name)
	if not manifest.get("maps",true):
		FileAccess.open(output+"visual-results.json",FileAccess.WRITE).store_string(JSON.stringify({"captures":captures,"failures":failures,"seed":manifest.seed,"note":"same observation positions, real terrain, physics disabled"},"\t"))
		game.free()
		print("SHAFT VISUAL: %d captures, %d failures" % [captures,failures])
		quit(0 if failures==0 else 1)
		return
	# Identical observation coordinates in both versions. These QA viewpoints
	# reveal real terrain; this is not a claim of manual or physical traversal.
	for visit: Dictionary in manifest.visits:
		if not await show(Vector2(visit.x,visit.y)): quit(1); return
		game.world.process_mode = Node.PROCESS_MODE_DISABLED
	game.open_map()
	game.ui.large_map.center_point = game.stable_point(T.SECTOR_SIZE/2)
	game.ui.large_map.zoom = 0.05
	await capture("large_map_same_route")
	game.close_map()
	game.open_map()
	game.ui.large_map.center_point = game.stable_point(T.SECTOR_SIZE/2)
	game.ui.large_map.zoom = 0.12
	await capture("large_map_connections")
	FileAccess.open(output+"visual-results.json",FileAccess.WRITE).store_string(JSON.stringify({"captures":captures,"failures":failures,"renderer":RenderingServer.get_video_adapter_name(),"seed":manifest.seed,"note":"same observation manifest before and after; real generated terrain and Task 7A map, physics disabled for repeatable views"},"\t"))
	game.free()
	print("DIAGONAL VISUAL: %d captures, %d failures" % [captures,failures])
	quit(0 if failures==0 else 1)

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
	var ordinary = loot.filter(func(i): return i.spawn.kind == "chest" and i.spawn.contents[0].kind != "ability")[0]
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


func run_ui_map() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	game = Main.new()
	game.controls_path = output + "visual_controls.cfg"
	root.add_child(game)
	game.key_bindings.reset_defaults()
	game.start_run(37)
	game.set_physics_process(false)
	game.show_menu("title")
	await capture("title")
	game.resume_run()
	game.elapsed = 9
	var npc = get_nodes_in_group("merchants").filter(func(m): return m.get_parent()==game.world and m.spawn.sector==Vector2i.ZERO)[0]
	game.player.position = npc.position + Vector2(-40, 0)
	game._update_camera(0, true)
	game._update_exploration()
	npc.spawn.stock = ["potion", "key", "rapid", "shell", "homing", "triple", "cushion"]
	game.crystals = 130
	game.owned_equipment.rapid = true
	game.merchant_sold[npc.spawn.id] = true
	game.open_shop(npc)
	await capture("shop_buy_mixed")
	var full_stock: Array = game.active_merchant.stock.duplicate()
	for equipment_count in [3, 4]:
		game.active_merchant.stock = ["potion", "key"] + full_stock.slice(2, 2 + equipment_count)
		game.ui.shop_panel._rebuild()
		await capture("shop_buy_%d_equipment" % equipment_count)
	game.active_merchant.stock = full_stock
	game.ui.shop_panel._rebuild()
	for id: String in T.EQUIPMENT: game.owned_equipment[id] = true
	for id: String in T.STARTER_EQUIPMENT: game.equip(T.EQUIPMENT[id].slot, id)
	game.ui.shop_panel._switch_tab(false)
	await capture("shop_equipment")
	game.close_shop()
	game.world.process_mode = Node.PROCESS_MODE_DISABLED
	await capture("hud_equipped")
	game.equip("armor", "")
	await capture("hud_available_equipment")
	game.show_menu("paused")
	await capture("pause_equipment_notice")
	game.start_run(37)
	game.set_physics_process(false)
	game.world.process_mode = Node.PROCESS_MODE_DISABLED
	game.open_map()
	await capture("map_start")
	game.close_map()
	var visits := [Vector2i(0,0), Vector2i(2,0), Vector2i(2,1), Vector2i(-1,1)]
	for sector: Vector2i in visits:
		var point := Vector2(sector) * T.SECTOR_SIZE + T.SECTOR_START
		if not await show(point): quit(1); return
		game.world.process_mode = Node.PROCESS_MODE_DISABLED
		# QA observation positions sample actual generated chambers, without changing terrain.
		for chamber: Dictionary in game.stream.loaded[sector].chambers:
			game.player.position = chamber.rect.get_center()
			game._update_camera(0, true)
			game._update_exploration()
	# Controlled discoveries make all boss marker types visible in the same QA map.
	for i in range(3):
		var point: Dictionary = game.stable_point(Vector2(5700 + i*400, 2600))
		game.discovered_bosses[700+i] = point
		game.boss_cycle.records[700+i] = {"boss_id":700+i,"role":["guardian","final","secret"][i],"alive":i!=1,"sector":point.sector,"position":point.local,"sector_local":true}
	game.defeated_bosses[701] = true
	game.open_map()
	game.ui.large_map.center_point = game.stable_point(Vector2(4096, 3072))
	await capture("map_explored")
	game.ui.large_map.change_zoom(2.5)
	await capture("map_zoom_in")
	game.ui.large_map.change_zoom(0.16)
	await capture("map_zoom_out")
	# Same worst-case population as the headless test, rendered by the normal GPU backend.
	var map = game.ui.large_map
	var base := Vector2i(20,20)
	for y in range(15):
		for x in range(20):
			var sector := base + Vector2i(x,y)
			var cells := {}
			for cy in range(24):
				for cx in range(32): cells[sector*Vector2i(32,24)+Vector2i(cx,cy)] = true
			game.explored_by_sector[sector] = cells
			var image := Image.create_empty(128,96,false,Image.FORMAT_RGBA8)
			image.fill(Color("293f43"))
			image.fill_rect(Rect2i(20,30,88,36),Color("0c1922"))
			game.explored_images[sector] = image
			game.map_sector_revisions[sector] = 1
	map.center_point = {"sector":base+Vector2i(10,7),"local":T.SECTOR_SIZE/2}
	map.zoom = T.LARGE_MAP_MIN_SCALE
	map.clear_cache()
	map.queue_redraw()
	await RenderingServer.frame_post_draw
	var cold: float = map.last_draw_ms
	var draw_samples: Array[float] = []
	var frame_samples: Array[float] = []
	for i in range(20):
		test_progress()
		var began := Time.get_ticks_usec()
		map.pan(Vector2(1,0))
		await RenderingServer.frame_post_draw
		draw_samples.append(map.last_draw_ms)
		frame_samples.append((Time.get_ticks_usec()-began)/1000.0)
	await capture("map_300_sector_benchmark")
	var metrics := {"sectors":300,"cells":230400,"cold_draw_cpu_ms":cold,"warm_draw_cpu_mean_ms":draw_samples.reduce(func(a,b): return a+b,0.0)/draw_samples.size(),"warm_draw_cpu_max_ms":draw_samples.max(),"frame_wall_mean_ms":frame_samples.reduce(func(a,b): return a+b,0.0)/frame_samples.size(),"frame_wall_max_ms":frame_samples.max(),"raster_bytes":300*128*96*4}
	FileAccess.open(output + "visual_results.json",FileAccess.WRITE).store_string(JSON.stringify({"captures":captures,"failures":failures,"renderer":RenderingServer.get_video_adapter_name(),"metrics":metrics,"note":"exploration uses QA observation positions in actual chambers and controlled boss discovery records; performance uses synthetic 300-sector records; frame wall includes scheduling, not isolated GPU time"},"\t"))
	game.free()
	print("UI MAP VISUAL: %d captures, %d failures; %s" % [captures,failures,JSON.stringify(metrics)])
	quit(0 if failures==0 else 1)

func run_enemies() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	game = Main.new()
	game.controls_path = output + "visual_controls.cfg"
	root.add_child(game)
	game.start_run(37)
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	game.world.process_mode = Node.PROCESS_MODE_DISABLED
	var source = get_nodes_in_group("enhancers").filter(func(e):return e.get_parent()==game.world and e.get_meta("sector")==Vector2i.ZERO)[0]
	var data: Dictionary = game.stream.loaded[Vector2i.ZERO]
	var descriptor: Dictionary = data.spawns.filter(func(e):return e.id==source.spawn_id)[0]
	# The geometry witness may stand inside a same-colour enemy. For readable
	# captures choose an equally reachable standing point outside all bodies.
	var observation := data.duplicate(false)
	observation.chambers=data.chambers.duplicate()
	var room: Dictionary = data.chambers[descriptor.chamber_id].duplicate(false)
	room.approaches=room.approaches.filter(func(point):
		var body := Rect2(point-T.PLAYER_SIZE/2,T.PLAYER_SIZE).grow(8)
		return not data.spawns.any(func(e):return S.enemy_spawn_area(e).intersects(body)))
	observation.chambers[descriptor.chamber_id]=room
	var witness: Dictionary = preload("res://scripts/stage_generator.gd").sight_witness(descriptor,observation)
	if witness.is_empty():
		printerr("FAIL: no clear observation witness")
		game.free()
		quit(1)
		return
	game.player.position = witness.target
	game.camera.position = source.position + Vector2(0,-60)
	game._update_exploration()
	await capture("enhancer_field_and_rings")
	await capture("arrow_locked_hint")
	var viewpoint: Vector2 = game.camera.position
	var counts := {}
	counts["stage0"] = get_nodes_in_group("enemies").filter(func(e):return e.get_parent()==game.world and not e.dead).size()
	await capture("population_stage0")
	source.receive_hit(1-source.polarity,999)
	# Physics is deliberately disabled in this fixture; refresh cached field
	# rings as normal actor physics would do on the next rendered frame.
	for enemy in get_nodes_in_group("enemies"):
		if enemy.get_parent()==game.world: enemy.queue_redraw()
	if not game.boss_arrow_unlocked or game.boss_arrow_state().is_empty(): failures += 1
	if game.boss_arrow_state().has("distance_text"): failures += 1
	await capture("arrow_unlocked_notice")
	game.announcement_remaining = 0
	await capture("arrow_only_no_distance")
	for level in [1,3]:
		game.boss_cycle.final_clears = level
		game.update_loop_scaling()
		if level==1: await capture("loop_increase_notice")
		game.camera.position=Vector2(-20000,-20000)
		var deadline := Time.get_ticks_msec()+30000
		while Time.get_ticks_msec()<deadline:
			game.stream._service_population_jobs()
			if game.stream.population_jobs.is_empty() and game.stream.population_waiting.is_empty(): break
			test_progress()
			OS.delay_msec(1)
		if not game.stream.population_jobs.is_empty() or not game.stream.population_waiting.is_empty(): failures+=1
		for i in range(240): game.stream._service_population(Time.get_ticks_usec()+5000)
		var player_area := Rect2(game.player.position-game.player.body_size/2,game.player.body_size)
		for enemy in get_nodes_in_group("enemies"):
			if enemy.get_parent()!=game.world or not enemy.spawn_id.contains(":extra_"): continue
			if Rect2(enemy.position-enemy.body_size/2,enemy.body_size).intersects(player_area):
				failures+=1
				printerr("FAIL: visual population overlaps player: ",enemy.spawn_id)
		game.camera.position=viewpoint
		game.announcement_remaining=0
		game.loot_message_remaining=0
		counts["stage%d" % level]=get_nodes_in_group("enemies").filter(func(e):return e.get_parent()==game.world and not e.dead).size()
		await capture("population_stage%d" % level)
	FileAccess.open(output+"visual_results.json",FileAccess.WRITE).store_string(JSON.stringify({"captures":captures,"failures":failures,"counts_all_loaded_sectors":counts,"renderer":RenderingServer.get_video_adapter_name(),"note":"seed 37 actual geometry and enemies; observation camera/standing witness fixed; levels 1 and 3 activated through production scaling and offscreen spawning"},"\t"))
	game.free()
	print("ENEMIES VISUAL: %d captures, %d failures" % [captures,failures])
	quit(0 if failures==0 else 1)
