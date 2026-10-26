extends "res://tests/test_tree.gd"
const Main := preload("res://scripts/main.gd")
const Terrain := preload("res://scripts/terrain.gd")
const WorldTerrain := preload("res://scripts/world_terrain.gd")
const T := preload("res://scripts/tuning.gd")
var game: Node2D
var checks := 0
var failures: Array[String] = []
var measurements := {}
const FIXTURE_ORIGIN := Vector2(5800, 1600)
const FLOOR_CENTER := 618.0

func _initialize() -> void:
	call_deferred("run")

func frames(count: int = 1) -> void:
	for i in range(count):
		test_progress()
		await physics_frame
		test_progress()
		await process_frame

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: ", message)

func input_action(action: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func key_event(key: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func reset_player() -> void:
	for action in ["move_left", "move_right", "jump", "move_down", "shoot", "switch_color", "aim_cycle", "special"]:
		input_action(action, false)
	game.start_run(37)
	game.streaming_enabled = false
	for enemy in get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)
	for child in game.world.get_children():
		if child != game.player and child != game.projectiles and child != game.effects and not child.is_in_group("enemies"):
			child.free()
	for enemy in get_nodes_in_group("enemies"):
		enemy.position = Vector2(11000, 2400)
	fixture(Rect2(0, 640, 4000, 160))
	game.player.position = FIXTURE_ORIGIN + Vector2(210, FLOOR_CENTER)
	game.player.velocity = Vector2.ZERO
	game._update_camera(1.0, true)
	await frames(3)

func fixture(bounds: Rect2) -> void:
	var block := Terrain.new()
	block.bounds = Rect2(bounds.position + FIXTURE_ORIGIN, bounds.size)
	game.world.add_child(block)

func jump_height(short_tap: bool) -> float:
	await reset_player()
	var initial: float = game.player.position.y
	var minimum := initial
	input_action("jump", true)
	if short_tap:
		input_action("jump", false)
	var landed_at := 0
	for i in range(50):
		await frames()
		minimum = minf(minimum, game.player.position.y)
		if i > 2 and game.player.is_on_floor() and landed_at == 0:
			landed_at = i + 1
	input_action("jump", false)
	measurements["short_airtime" if short_tap else "full_airtime"] = landed_at / 60.0
	return initial - minimum

func run() -> void:
	game = Main.new()
	game.controls_path = "res://builds/qa/movement_controls.cfg"
	root.add_child(game)
	game.key_bindings.reset_defaults()
	await reset_player()
	input_action("move_right", true)
	await frames()
	check(game.player.velocity.x > 0 and game.player.velocity.x < T.MOVE_SPEED, "movement accelerates without jumping to full speed")
	await frames(5)
	check(is_equal_approx(game.player.velocity.x, T.MOVE_SPEED), "full ground speed in six frames")
	input_action("move_right", false)
	await frames(3)
	check(is_zero_approx(game.player.velocity.x), "ground stop within three frames")
	var full_height := await jump_height(false)
	var short_height := await jump_height(true)
	measurements.full_height = full_height
	measurements.short_height = short_height
	check(absf(full_height - 170.0747) <= 6.0, "full jump preserves Task 4B height within six pixels")
	check(short_height > 25 and short_height < full_height * 0.6, "short tap creates a low jump")
	check(measurements.full_airtime >= (32.0 / 60) * 1.25 and measurements.full_airtime <= (32.0 / 60) * 1.35, "full airtime is 1.25 to 1.35 times the measured Task 4B jump")
	check(is_equal_approx(T.MAX_STEP_HEIGHT, T.JUMP_SPEED * T.JUMP_SPEED / (2 * T.GRAVITY) - T.LANDING_MARGIN), "reach validation derives height from the new physics")
	await reset_player()
	game.key_bindings.try_bind("jump", 1, KEY_Q)
	key_event(KEY_SPACE, true)
	await frames(3)
	key_event(KEY_Q, true)
	key_event(KEY_SPACE, false)
	await frames()
	check(game.player.velocity.y < -T.JUMP_CUT_SPEED, "holding a second jump key prevents early cut")
	key_event(KEY_Q, false)
	await frames()
	check(game.player.velocity.y > -T.JUMP_CUT_SPEED, "releasing both jump keys cuts the ascent")
	game.key_bindings.reset_defaults()
	await reset_player()
	input_action("move_right", true)
	await frames(6)
	input_action("jump", true)
	await frames(3)
	input_action("move_right", false)
	var release_x: float = game.player.position.x
	await frames(2)
	check(is_zero_approx(game.player.velocity.x) and game.player.position.x - release_x < 8, "air control stops horizontal drift within two frames")
	# Coyote time is measured after walking off a real shelf.
	for delay in [2, 9]:
		await reset_player()
		fixture(Rect2(0, 500, 150, 16))
		game.player.position = FIXTURE_ORIGIN + Vector2(130, 478)
		await frames(3)
		input_action("move_right", true)
		for i in range(30):
			await frames()
			if not game.player.is_on_floor():
				break
		input_action("move_right", false)
		await frames(delay)
		input_action("jump", true)
		await frames()
		check((game.player.velocity.y < 0) == (delay == 2), "coyote jump allowed briefly, rejected after timeout (%d frames)" % delay)
	# A short tap just before landing must stay short when the buffered jump executes.
	await reset_player()
	game.player.position = FIXTURE_ORIGIN + Vector2(210, 564)
	game.player.velocity = Vector2(0, 250)
	await frames()
	game.player.coyote = 0.0 # Teleporting above the floor must not carry floor grace.
	input_action("jump", true)
	input_action("jump", false)
	var buffered_min := FIXTURE_ORIGIN.y + FLOOR_CENTER
	var jumped := false
	for i in range(35):
		await frames()
		if game.player.velocity.y < 0:
			jumped = true
		if jumped:
			buffered_min = minf(buffered_min, game.player.position.y)
	check(jumped, "pre-landing input buffer starts jump")
	check(FIXTURE_ORIGIN.y + FLOOR_CENTER - buffered_min < 90, "released buffered jump retains short-jump intent")
	# Correct grazing head collisions on either side, but do not bypass a solid roof.
	for offset in [-2, 2, -4, 4, -6, 6, -10, 10, 50]:
		await reset_player()
		fixture(Rect2(260, 480, 100, 32))
		var start_x: float = 260.0 - T.PLAYER_SIZE.x / 2 + absf(offset)
		if offset < 0:
			start_x = 360.0 + T.PLAYER_SIZE.x / 2 - absf(offset)
		if offset == 50:
			start_x = 310
		game.player.position.x = FIXTURE_ORIGIN.x + start_x
		input_action("jump", true)
		var minimum := FIXTURE_ORIGIN.y + FLOOR_CENTER
		for i in range(38):
			await frames()
			minimum = minf(minimum, game.player.position.y)
		var corrected: bool = absi(offset) <= 6
		check((minimum < FIXTURE_ORIGIN.y + 500) == corrected, "ceiling correction only clears grazing corners (%d px)" % offset)
	await reset_player()
	fixture(Rect2(260, 480, 100, 32))
	fixture(Rect2(210, 450, 20, 190))
	game.player.position.x = FIXTURE_ORIGIN.x + 247
	input_action("jump", true)
	var corner_min := FIXTURE_ORIGIN.y + FLOOR_CENTER
	for i in range(38):
		await frames()
		corner_min = minf(corner_min, game.player.position.y)
	check(corner_min > FIXTURE_ORIGIN.y + 520 and game.player.position.x >= FIXTURE_ORIGIN.x + 245, "ceiling correction never pushes into adjacent wall")
	# Integer HP bar and different incoming damage amounts.
	await reset_player()
	game.player.receive_hit(1, T.ENEMY_NORMAL_DAMAGE)
	game.ui.update_hud()
	check(game.player.hp == 88 and game.ui.health_bar.value == 88, "normal hit changes integer HP and bar")
	game.player.invulnerability = 0
	game.player.receive_hit(1, T.ENEMY_HOMING_DAMAGE)
	game.ui.update_hud()
	check(game.player.hp == 70 and game.ui.health_label.text.contains("70 / 100"), "homing damage is an integer amount")
	game.show_menu("paused")
	var paused_time: float = game.elapsed
	game.open_key_settings()
	check(game.state == "settings" and game.ui.settings_overlay.visible, "settings opens from pause")
	await frames(3)
	check(game.elapsed == paused_time, "settings keeps the run paused")
	check(game.key_bindings.try_bind("switch_color", 0, KEY_V).is_empty(), "binding model accepts remap")
	game.close_key_settings()
	check(game.state == "paused" and game.ui.controls_label.text.contains("V 色切替"), "closing settings restores pause and refreshes help")
	game.resume_run()
	var event := InputEventKey.new()
	event.keycode = KEY_V
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	check(game.player.polarity == 1, "remapped key performs gameplay action")
	await verify_drop_through()
	await verify_cave_hops()
	game.queue_free()
	await frames(2)
	DirAccess.make_dir_recursive_absolute("res://builds/qa/seamless")
	var report := {"checks": checks, "failures": failures, "measurements": measurements}
	var file := FileAccess.open("res://builds/qa/seamless/movement_results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("MOVEMENT RESULT: ", checks, " checks, ", failures.size(), " failures; ", measurements)
	quit(0 if failures.is_empty() else 1)

func verify_cave_hops() -> void:
	# Measure the actual player, including acceleration from rest and release timing.
	var profiles: Array = []
	for profile: Array in T.HOP_PROFILES:
		await reset_player()
		var start: Vector2 = game.player.position
		var minimum := start.y
		input_action("move_right", true)
		input_action("jump", true)
		var landed := false
		for index in range(60):
			if index == profile[0]: input_action("jump", false)
			await frames()
			minimum = minf(minimum, game.player.position.y)
			if index > 0 and game.player.is_on_floor():
				landed = true
				break
		var rise := start.y - minimum
		var reach: float = game.player.position.x - start.x
		profiles.append({"hold_frames":profile[0], "rise":rise, "reach":reach})
		check(landed and absf(rise-profile[1]) < 0.2, "hop profile %d rise matches actual physics" % profile[0])
		check(landed and absf(reach-profile[2]) < 0.3, "hop profile %d reach matches actual physics" % profile[0])
	measurements.hop_profiles = profiles
	var generator := preload("res://scripts/stage_generator.gd")
	var driver := preload("res://tests/cave_driver.gd").new()
	driver.tree = self
	driver.game = game
	# Cross a 32px hole below a shelf 96px above, in both directions.
	for direction in [1,-1]:
		await reset_player()
		for child in game.world.get_children():
			if child is Terrain: child.free()
		var solids: Array = [Rect2(0,640,256,160),Rect2(288,640,736,160),Rect2(224,544,160,16)]
		for index in range(solids.size()):
			var rect: Rect2 = solids[index]
			solids[index] = Rect2(rect.position+FIXTURE_ORIGIN,rect.size)
		var terrain := WorldTerrain.new()
		terrain.stage = {"bounds":game.stage.bounds,"solids":solids}
		game.world.add_child(terrain)
		game.terrain = terrain
		var lower := Rect2(FIXTURE_ORIGIN+Vector2(0 if direction>0 else 288,640),Vector2(256 if direction>0 else 736,0))
		var upper := Rect2(FIXTURE_ORIGIN+Vector2(288 if direction>0 else 0,640),Vector2(736 if direction>0 else 256,0))
		var edges: Array = []
		generator._add_hop(edges,0,lower,upper,direction,[solids[2]])
		check(edges.size()==1 and edges[0].hold_frames==1,"lowest hop chosen under a shelf, direction %d" % direction)
		if edges.is_empty(): continue
		game.player.position = edges[0].position
		game.player.velocity = Vector2.ZERO
		await frames(3)
		check(await driver.step(edges[0]),"actual hop lands below the shelf, direction %d: %s" % [direction,driver.error])
		driver.release()
		var blocked: Array = []
		generator._add_hop(blocked,0,lower,upper,direction,[Rect2(FIXTURE_ORIGIN+Vector2(224,544),Vector2(160,32))])
		check(blocked.is_empty(),"solid roof rejects the same hop, direction %d" % direction)
		blocked.clear()
		# The slower jump travels farther; a 96px gap now requires the >96px-high profile.
		var farther := Rect2(upper.position+Vector2(direction*64,0),upper.size)
		generator._add_hop(blocked,0,lower,farther,direction,[solids[2]])
		check(blocked.is_empty(),"higher hop that lands on the overhead shelf is rejected, direction %d" % direction)

func drop_fixture(world_terrain: bool) -> CharacterBody2D:
	await reset_player()
	var shelves: Array[Rect2] = [
		Rect2(FIXTURE_ORIGIN + Vector2(80, 384), Vector2(360, 16)),
		Rect2(FIXTURE_ORIGIN + Vector2(80, 512), Vector2(360, 16)),
	]
	if world_terrain:
		var terrain := WorldTerrain.new()
		terrain.stage = {"bounds": game.stage.bounds, "solids": shelves}
		game.world.add_child(terrain)
		game.terrain = terrain
	else:
		for shelf in shelves:
			fixture(Rect2(shelf.position - FIXTURE_ORIGIN, shelf.size))
	game.player.position = FIXTURE_ORIGIN + Vector2(210, 362)
	game.player.velocity = Vector2.ZERO
	var enemy: CharacterBody2D = get_nodes_in_group("enemies").filter(func(actor): return actor.get_parent() == game.world and actor.kind != "boss")[0]
	enemy.kind = "turret"
	enemy.position = FIXTURE_ORIGIN + Vector2(350, 362)
	enemy.velocity = Vector2.ZERO
	enemy.shot_clock = 100
	enemy.set_physics_process(true)
	await frames(4)
	check(game.player.is_on_floor() and enemy.is_on_floor(), "player and enemy stand on shelf (world=%s)" % world_terrain)
	return enemy

func verify_drop_through() -> void:
	for use_world in [false, true]:
		var context := " (world=%s)" % use_world
		var enemy := await drop_fixture(use_world)
		var initial_x: float = game.player.position.x
		var enemy_y := enemy.position.y
		# A tap descends to the next shelf rather than walking off its edge.
		key_event(KEY_S, true)
		await frames(1)
		key_event(KEY_S, false)
		check(game.player.drop_remaining > 0 and not game.player.collision_mask & T.PLATFORM_LAYER, "drop temporarily removes only player shelf collision" + context)
		check(game.player.collision_mask & 1 and game.player.collision_mask & T.WALL_LAYER, "solid terrain and walls stay in the player mask" + context)
		key_event(KEY_SPACE, true)
		await frames(1)
		key_event(KEY_SPACE, false)
		check(game.player.velocity.y > 0 and game.player.coyote == 0, "jump immediately after dropping cannot use coyote time" + context)
		var enemy_stayed := true
		for index in range(30):
			await frames(1)
			enemy_stayed = enemy_stayed and enemy.is_on_floor() and absf(enemy.position.y - enemy_y) < 0.2
		check(game.player.is_on_floor() and absf(game.player.position.y - (FIXTURE_ORIGIN.y + 490)) < 0.2 and absf(game.player.position.x - initial_x) < 0.1, "tap drops vertically to the next shelf" + context)
		check(game.player.drop_remaining == 0 and game.player.collision_mask & T.PLATFORM_LAYER, "shelf collision returns after the whole body clears" + context)
		check(enemy_stayed, "enemy stays grounded throughout and after player's drop" + context)
		enemy = await drop_fixture(use_world)
		enemy_y = enemy.position.y
		key_event(KEY_DOWN, true)
		enemy_stayed = true
		for index in range(55):
			await frames(1)
			enemy_stayed = enemy_stayed and enemy.is_on_floor() and absf(enemy.position.y - enemy_y) < 0.2
		key_event(KEY_DOWN, false)
		check(game.player.is_on_floor() and absf(game.player.position.y - (FIXTURE_ORIGIN.y + FLOOR_CENTER)) < 0.2, "held down passes through stacked shelves and lands on solid floor" + context)
		check(enemy_stayed, "held down does not change enemy shelf collision" + context)
		key_event(KEY_S, true)
		await frames(12)
		key_event(KEY_S, false)
		check(game.player.is_on_floor() and game.player.drop_remaining == 0 and absf(game.player.position.y - (FIXTURE_ORIGIN.y + FLOOR_CENTER)) < 0.2, "down does nothing on a thick floor" + context)
		# Re-use the same physical shelves from below, with down released.
		input_action("jump", true)
		await frames(38)
		input_action("jump", false)
		check(game.player.is_on_floor() and absf(game.player.position.y - (FIXTURE_ORIGIN.y + 490)) < 0.2, "jump still crosses the shelf underside and lands on top" + context)
		check(game.player.collision_mask & T.PLATFORM_LAYER, "normal collision remains enabled after jumping through" + context)
	# Thick blocks and temporary walls use their original solid layers.
	for layer in [1, T.WALL_LAYER]:
		await reset_player()
		fixture(Rect2(80, 512, 360, 64))
		var block: StaticBody2D = game.world.get_child(game.world.get_child_count() - 1)
		block.collision_layer = layer
		game.player.position = FIXTURE_ORIGIN + Vector2(210, 490)
		await frames(4)
		input_action("move_down", true)
		await frames(15)
		input_action("move_down", false)
		check(game.player.is_on_floor() and game.player.drop_remaining == 0 and absf(game.player.position.y - (FIXTURE_ORIGIN.y + 490)) < 0.2, "down cannot bypass a block/wall on layer %d" % layer)
