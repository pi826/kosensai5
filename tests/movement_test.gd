extends SceneTree
const Main := preload("res://scripts/main.gd")
const Terrain := preload("res://scripts/terrain.gd")
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
		await physics_frame
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
	for action in ["move_left", "move_right", "jump", "shoot", "switch_color", "special"]:
		input_action(action, false)
	game.start_run(37)
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
	check(full_height > 140 and full_height < 190, "full jump is taller than the original prototype")
	check(short_height > 25 and short_height < full_height * 0.6, "short tap creates a low jump")
	check(measurements.full_airtime < 0.75, "taller jump still lands promptly")
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
	game.queue_free()
	await frames(2)
	DirAccess.make_dir_recursive_absolute("res://builds/qa/seamless")
	var report := {"checks": checks, "failures": failures, "measurements": measurements}
	var file := FileAccess.open("res://builds/qa/seamless/movement_results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("MOVEMENT RESULT: ", checks, " checks, ", failures.size(), " failures; ", measurements)
	quit(0 if failures.is_empty() else 1)
