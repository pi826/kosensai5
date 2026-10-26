extends "res://tests/test_tree.gd"
const Main := preload("res://scripts/main.gd")
const Driver := preload("res://tests/tutorial_driver.gd")
const T := preload("res://scripts/tuning.gd")
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
	check(practice.get_world_2d() != game.get_world_2d(), "tutorial physics space is isolated from main terrain and actors")
	check(not game.world.visible and game.world.process_mode == Node.PROCESS_MODE_DISABLED, "main world hidden and suspended during tutorial")
	var initial_text: String = practice.lesson_text()
	check(game.key_bindings.try_bind("move_left", 0, KEY_Q).is_empty(), "rebind move left")
	check(practice.lesson_text() != initial_text and practice.lesson_text().contains("Q"), "current lesson text follows changed binding immediately")
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
		for action: String in ["move_left", "move_right", "jump", "move_down", "shoot", "aim_cycle", "switch_color", "special", "interact"]:
			var index: int = {"move_left":0,"move_right":0,"jump":1,"move_down":2,"shoot":3,"aim_cycle":4,"switch_color":5,"special":7,"interact":10}[action]
			practice.lesson = index
			var before: String = practice.lesson_text()
			check(game.key_bindings.try_bind(action, 0, KEY_Q).is_empty(), "rebind tutorial action " + action)
			check(practice.lesson_text() != before and practice.lesson_text().contains("Q"), "description reflects " + action)
			game.key_bindings.reset_defaults()
		for index in range(11):
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
		await driver.tap("pause_game")
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
	game.free()
	print("TUTORIAL TEST: %d checks, %d failures" % [checks, failures.size()])
	FileAccess.open("res://builds/qa/tutorial/test_results.json", FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures}, "\t"))
	quit(0 if failures.is_empty() else 1)
