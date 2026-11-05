extends "res://tests/test_tree.gd"
const Main := preload("res://scripts/main.gd")
const Driver := preload("res://tests/tutorial_driver.gd")
const T := preload("res://scripts/tuning.gd")
const Dynamite := preload("res://scripts/dynamite.gd")
var game: Node2D
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)
func frames(count: int) -> void:
	for i in range(count):
		test_progress()
		await physics_frame
		test_progress()
		await process_frame
func raw_key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func click(button: Button) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = button.get_global_rect().get_center()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		# Headless has a 64px host window; send viewport-local mouse coordinates.
		root.push_input(event, true)
		await frames(1)

func check_live_goal(practice: Node2D, context: String) -> void:
	for id: String in ["upper", "lower"]:
		var index := 0 if id == "upper" else 1
		check(not practice.defeated.has(id) or practice.goal() != T.TUTORIAL_AIM_TARGETS[index], context + ": goal avoids destroyed " + id)
	check(practice.marker.visible or practice.ok_remaining > 0, context + ": marker guides until completion")

func fire_aim_target(driver: RefCounted, id: String) -> void:
	driver.key("shoot", true)
	for tick in range(120):
		if driver.game.defeated.has(id): break
		await driver.frames(1)
	driver.key("shoot", false)
	check(driver.game.defeated.has(id), "physical shots defeated " + id)

func check_aim_route(ground_attempt: bool, lower_first: bool) -> void:
	game.start_tutorial()
	var practice: Node2D = game.tutorial_session
	var driver := Driver.new()
	driver.tree = self
	driver.game = practice
	await driver.reach_aim_lesson()
	check(practice.goal() == T.TUTORIAL_GOALS[4], "before climbing marker points to platform edge")
	await driver.walk(1340)
	if ground_attempt:
		check(practice.player.is_on_floor() and practice.player.position.y > 600 and practice.player.aim_index == 0, "reported route shoots forward from ground before climbing")
		# Change aim while the first shot is in flight: validation must use launch aim.
		driver.key("shoot", true)
		await driver.frames(1)
		driver.key("shoot", false)
		await driver.tap("aim_cycle")
		await driver.tap("aim_cycle")
		await driver.frames(35)
		check(not practice.defeated.has("lower") and is_instance_valid(practice.targets.lower) and practice.targets.lower.hp == T.ENEMY_HP, "ground forward shot leaves lower target at full HP despite switching to down")
		check(practice.lesson_text().contains("下の的は 下 向き") and practice.lesson_text().contains(practice.key_bindings.get_binding_text("aim_cycle")), "wrong direction gives current-key guidance")
		check(practice.ui.tutorial_label.text == practice.lesson_text(), "wrong-direction guidance reaches visible lesson panel")
		check(is_instance_valid(practice.targets.lower) and practice.targets.lower.hit_flash > 0, "wrong-direction hit flashes the surviving target")
		check_live_goal(practice, "after ground shot")
		await driver.tap("aim_cycle") # back to forward
	await driver.jump_right(1540)
	await driver.walk(1620)
	check(practice.goal() == T.TUTORIAL_AIM_TARGETS[0], "platform marker points to live upper target")
	await driver.tap("aim_cycle")
	if lower_first: await driver.tap("aim_cycle")
	var first := "lower" if lower_first else "upper"
	var second := "upper" if lower_first else "lower"
	await fire_aim_target(driver, first)
	check(practice.lesson == 4 and practice.ok_remaining <= 0, "one target alone waits")
	check_live_goal(practice, "after first " + first)
	check(practice.goal() == T.TUTORIAL_AIM_TARGETS[0 if lower_first else 1], "marker points to remaining " + second)
	await driver.tap("aim_cycle")
	if lower_first: await driver.tap("aim_cycle")
	await fire_aim_target(driver, second)
	check(practice.lesson == 4 and practice.ok_remaining > T.TUTORIAL_OK_TIME - 0.05 and practice.lesson_text().begins_with("OK"), "last target immediately shows OK without extra input")
	check_live_goal(practice, "both defeated")
	check(not practice.marker.visible, "completed aiming lesson hides marker")
	check(not practice.direction_hint().contains("目印"), "completed aiming lesson stops marker guidance")
	await driver.expect_lesson(5)
	check(driver.largest_step < T.MAX_FALL_SPEED / 60 + 1, "aim regression route uses continuous real physics")
	driver.release()
	checks += driver.checks
	failures.append_array(driver.failures)
	game.finish_tutorial()
	await frames(2)

func check_tool_lessons(practice: Node2D, driver: RefCounted) -> void:
	practice.set_physics_process(false)
	practice.player.position = Vector2(4600, 618)
	practice.player.velocity = Vector2.ZERO
	practice.player.gravity_sign = 1
	practice.player.up_direction = Vector2(0, -1)
	practice.player.flip_ready = true
	for index in range(10):
		practice.lesson = index
		practice.dynamite_stock = 2
		var before: int = practice.projectiles.get_children().size()
		await driver.tap("gravity_flip")
		await driver.tap("dynamite")
		check(practice.player.gravity_sign == 1, "lesson %d rejects gravity flip" % index)
		check(practice.dynamite_stock == 2 and practice.projectiles.get_children().size() == before, "lesson %d rejects dynamite" % index)

	practice.lesson = practice.GRAVITY_LESSON
	practice.player.position = Vector2(T.TUTORIAL_FLIP_MIN_X - 10, 618)
	practice.player.gravity_sign = 1
	practice.player.up_direction = Vector2(0, -1)
	practice.player.flip_ready = true
	await driver.tap("gravity_flip")
	check(practice.player.gravity_sign == 1, "gravity lesson rejects flips left of the minimum")
	practice.player.position = Vector2(T.TUTORIAL_FLIP_MIN_X + 10, 618)
	practice.player.velocity = Vector2.ZERO
	await driver.tap("gravity_flip")
	check(practice.player.gravity_sign == -1, "gravity lesson accepts flips at the minimum")

	practice.player.gravity_sign = 1
	practice.player.up_direction = Vector2(0, -1)
	practice.player.position = Vector2(T.TUTORIAL_GRAVITY_WALL.position.x - 40, 618)
	practice.player.velocity = Vector2.ZERO
	driver.key("jump", true)
	driver.key("move_right", true)
	await frames(75)
	driver.key("jump", false)
	driver.key("move_right", false)
	await frames(15)
	check(practice.player.position.x < T.TUTORIAL_GRAVITY_WALL.position.x - T.PLAYER_SIZE.x / 2 + 1, "gravity wall blocks a normal jump")

	practice.player.position = Vector2(5150, 618)
	practice.player.velocity = Vector2.ZERO
	practice.player.facing = 1
	practice.enter_lesson(practice.DYNAMITE_LESSON)
	check(practice.dynamite_stock == 1 and practice.dynamite_explosions == 0, "dynamite lesson resets its single stick")
	practice.set_physics_process(true)
	await driver.tap("dynamite")
	await frames(2)
	check(practice.dynamite_stock == 0 and practice.projectiles.get_children().any(func(item): return item.get_script() == Dynamite and not item.exploded), "practice throw consumes and launches a stick")
	await frames(120)
	check(practice.dynamite_explosions > 0 and practice.dynamite_stock == 1, "practice explosion restores one stick")
	check(not practice.terrain.occupied.has(practice.terrain.cell_at(Vector2(5280, 580))), "practice explosion opens the dynamite wall")

	for point in [Vector2(5100, 650), Vector2(4500, 330), Vector2(4820, 500)]:
		var cell: Vector2i = practice.terrain.cell_at(point)
		var had_cell: bool = practice.terrain.occupied.has(cell)
		var removed: Array[Vector2i] = practice.terrain.dynamite_dig(Rect2i(cell, Vector2i.ONE))
		check(had_cell and removed.is_empty() and practice.terrain.occupied.has(cell), "practice dynamite leaves protected terrain at %s" % point)

	practice.player.hp = 1
	practice.player.invulnerability = 0
	var stick := Dynamite.new()
	stick.game = practice
	stick.position = practice.player.position
	practice.projectiles.add_child(stick)
	await frames(1)
	stick.detonate()
	await frames(2)
	check(practice.player.hp == 1 and not practice.player.dead, "dynamite self-damage leaves practice HP at one")
	for item in practice.projectiles.get_children(): item.queue_free()
	practice.lesson = 0
	practice.player.position = T.TUTORIAL_START
	practice.player.velocity = Vector2.ZERO
	practice.player.gravity_sign = 1
	practice.player.up_direction = Vector2(0, -1)
	practice.player.flip_ready = true
	practice.set_physics_process(true)
	await frames(2)

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://builds/qa/tutorial")
	game = Main.new()
	game.controls_path = "res://builds/qa/tutorial/test_controls.cfg"
	root.add_child(game)
	game.key_bindings.reset_defaults()
	game.ui.seed_field.text = "37"
	game.score = 123
	game.elapsed = 7.5
	game.kills = 3
	var original_world: int = game.world.get_instance_id()
	var original_seed: int = game.current_seed
	var original_stage: Dictionary = game.stage.duplicate(true)
	await frames(3)
	await click(game.ui.tutorial_button)
	check(is_instance_valid(game.tutorial_session), "mouse title button starts tutorial")
	if not is_instance_valid(game.tutorial_session):
		game.free()
		quit(1)
		return
	var practice: Node2D = game.tutorial_session
	check(practice.stream == null and practice.boss_cycle == null and not practice.streaming_enabled, "fixed map has no generator, stream or boss progression")
	check(practice.stage.solids == T.TUTORIAL_SOLIDS, "hand-authored geometry used")
	check(practice.stage.bounds == T.TUTORIAL_BOUNDS, "extended tutorial bounds used")
	for point in [Vector2(5900, 650), Vector2(5990, 100), Vector2(5000, 100), Vector2(4420, 400), Vector2(4820, 500), Vector2(5280, 500)]:
		var cell: Vector2i = practice.terrain.cell_at(point)
		check(practice.terrain.occupied.has(cell) and practice.terrain.is_cell_solid(cell), "extended terrain collision exists at %s" % point)
	check(practice.get_world_2d() != game.get_world_2d(), "tutorial physics space is isolated from main terrain and actors")
	check(not game.world.visible and game.world.process_mode == Node.PROCESS_MODE_DISABLED, "main world hidden and suspended during tutorial")
	var initial_text: String = practice.lesson_text()
	check(game.key_bindings.try_bind("move_left", 0, KEY_U).is_empty(), "rebind move left")
	check(practice.lesson_text() != initial_text and practice.lesson_text().contains("U"), "current lesson text follows changed binding immediately")
	game.key_bindings.reset_defaults()
	var driver := Driver.new()
	driver.tree = self
	driver.game = practice
	await driver.run()
	checks += driver.checks
	failures.append_array(driver.failures)
	check(practice.ui.primary_button.text == "本編を始める" and practice.ui.title_button.visible, "completion offers main and title")
	await click(practice.ui.title_button)
	await frames(3)
	check(game.state == "title" and not is_instance_valid(game.tutorial_session), "completion returns to title")
	check(game.world.get_instance_id() == original_world and game.current_seed == original_seed and game.stage == original_stage, "original world seed and geometry unchanged")
	check(game.score == 123 and game.elapsed == 7.5 and game.kills == 3 and game.boss_cycle.final_clears == 0, "main counters unaffected by complete tutorial")
	# Select tutorial using the actual focused button and keyboard accept.
	for i in range(3):
		raw_key(KEY_TAB, true)
		await frames(1)
		raw_key(KEY_TAB, false)
		await frames(1)
	check(root.gui_get_focus_owner() == game.ui.tutorial_button, "Tab reaches tutorial from primary focus")
	raw_key(KEY_ENTER, true)
	await frames(1)
	raw_key(KEY_ENTER, false)
	await frames(3)
	check(is_instance_valid(game.tutorial_session), "keyboard title selection starts tutorial")
	practice = game.tutorial_session
	if is_instance_valid(practice):
		practice.set_physics_process(false)
		for action: String in ["move_left", "move_right", "jump", "move_down", "shoot", "aim_cycle", "switch_color", "special", "gravity_flip", "dynamite", "interact"]:
			var index: int = {"move_left":0,"move_right":0,"jump":1,"move_down":2,"shoot":3,"aim_cycle":4,"switch_color":5,"special":7,"gravity_flip":10,"dynamite":11,"interact":12}[action]
			practice.lesson = index
			var before: String = practice.lesson_text()
			check(game.key_bindings.try_bind(action, 0, KEY_U).is_empty(), "rebind tutorial action " + action)
			check(practice.lesson_text() != before and practice.lesson_text().contains("U"), "description reflects " + action)
			game.key_bindings.reset_defaults()
		for index in range(practice.LESSON_COUNT):
			practice.lesson = index
			practice.ui.update_hud()
			await frames(1)
			check(practice.ui.tutorial_label.get_minimum_size().y <= practice.ui.tutorial_label.size.y, "lesson %d text fits panel" % index)
			check(not practice.ui.tutorial_panel.get_global_rect().intersects(Rect2(24,18,1232,88)), "lesson %d panel avoids HUD" % index)
		practice.lesson = 0
		practice.set_physics_process(true)
		for i in range(4):
			practice.player.invulnerability = 0
			practice.player.receive_hit(1 - practice.player.polarity, 9999)
		check(practice.player.hp == 1 and not practice.player.dead, "repeated lethal hits leave HP one")
		driver.game = practice
		await driver.tap("pause_game")
		check(practice.state == "paused" and practice.ui.title_button.visible, "pause offers title")
		var paused_position: Vector2 = practice.player.position
		driver.key("move_right", true)
		await frames(20)
		driver.key("move_right", false)
		check(practice.player.position == paused_position and practice.lesson == 0, "pause freezes player and lesson")
		await click(practice.ui.settings_button)
		check(practice.state == "settings" and practice.key_bindings == game.key_bindings, "pause settings uses shared bindings")
		practice.close_key_settings()
		check(practice.state == "paused" and practice.lesson == 0, "settings returns to paused lesson")
		var prior_player_id: int = practice.player.get_instance_id()
		await click(practice.ui.new_button)
		await frames(3)
		practice = game.tutorial_session
		driver.game = practice
		check(practice.state == "playing" and practice.lesson == 0 and practice.player.hp == T.PLAYER_HP and practice.player.get_instance_id() != prior_player_id, "pause restart creates a fresh tutorial")
		await check_tool_lessons(practice, driver)
		await driver.tap("pause_game")
		check(practice.ui.menu_detail.text.contains("練習 1 / 13"), "pause reports all thirteen lessons")
		await click(practice.ui.title_button)
		await frames(3)
		check(game.state == "title" and not is_instance_valid(game.tutorial_session), "pause abort returns to title")
	game.primary_action()
	check(game.current_seed == 37 and game.score == 0 and game.elapsed == 0 and game.kills == 0 and game.boss_cycle.final_clears == 0, "main starts with selected seed and clean progress after tutorial")
	check(game.player.hp == T.PLAYER_HP and game.player.homing_charges == 0 and game.player.gauge == 0 and game.player.aim_index == 0, "main player starts clean")
	game.show_menu("title")
	game.ui.seed_field.text = "2026"
	game.start_tutorial()
	practice = game.tutorial_session
	check(game.key_bindings.try_bind("shoot", 0, KEY_R).is_empty(), "custom shoot key for second traversal")
	driver = Driver.new()
	driver.tree = self
	driver.game = practice
	await driver.run()
	checks += driver.checks
	failures.append_array(driver.failures)
	await click(practice.ui.primary_button)
	await frames(2)
	check(not is_instance_valid(game.tutorial_session) and game.state == "playing" and game.current_seed == 2026, "completion starts main with selected seed")
	check(game.score == 0 and game.kills == 0 and game.elapsed < 0.2 and game.player.hp == T.PLAYER_HP and game.player.homing_charges == 0, "completion starts a clean main run")
	check(game.key_bindings.get_key("shoot", 0) == KEY_R, "tutorial key changes carry into main")
	check(game.ui.controls_label.text.contains("R 射撃"), "main help refreshes shared bindings after tutorial")
	game.key_bindings.reset_defaults()
	await check_aim_route(true, false)
	await check_aim_route(false, true)
	await check_aim_route(true, true)
	game.free()
	print("TUTORIAL TEST: %d checks, %d failures" % [checks, failures.size()])
	FileAccess.open("res://builds/qa/tutorial/test_results.json", FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures}, "\t"))
	quit(0 if failures.is_empty() else 1)
