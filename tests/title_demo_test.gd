extends "res://tests/test_tree.gd"
const Main := preload("res://scripts/main.gd")
const T := preload("res://scripts/tuning.gd")
var game: Node2D
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)
	return ok

func frames(n: int = 1) -> void:
	for i in range(n):
		test_progress()
		await physics_frame
		await process_frame

func key(code: int, pressed: bool = true) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func tap(code: int) -> void:
	key(code)
	key(code, false)

func mouse_button(at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	root.push_input(event, true)

func motion(at: Vector2, relative: Vector2 = Vector2.ZERO) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.relative = relative
	root.push_input(event, true)

func begin_demo(seed_text: String = "") -> bool:
	game.show_menu("title")
	if not seed_text.is_empty(): game.ui.seed_field.text = seed_text
	game.title_idle = T.TITLE_DEMO_IDLE - 0.01
	await frames(4)
	return game.title_demo_playing()

func check_blocked(label: String) -> void:
	game.title_idle = T.TITLE_DEMO_IDLE - 0.01
	await frames(4)
	check(not game.title_demo_playing(), label + " does not start title demo")
	check(game.title_idle == 0.0, label + " resets title idle")

func check_demo_launch() -> void:
	check(await begin_demo(), "idle title starts demo")
	check(game.state == "title", "demo keeps title state")
	check(game.title_demo.visible and game.title_demo.video.is_playing(), "demo shows playing video")
	check(game.title_demo.demo_panel.is_visible_in_tree(), "demo badge panel is visible")
	check(game.title_demo.demo_label.is_visible_in_tree() and game.title_demo.demo_label.text == "DEMO", "demo label is visible")
	check(game.title_demo.hint.is_visible_in_tree() and game.title_demo.hint.text.contains("すぐに遊べます"), "demo shows dismissal hint")
	check(game.ui.menu.visible, "menu remains under demo")
	check_demo_visuals()
	game.title_demo.stop()
	game.title_demo.video_path = T.TITLE_DEMO_PATH

func check_demo_visuals() -> void:
	var demo: CanvasLayer = game.title_demo
	var badge_rect: Rect2 = demo.demo_panel.get_global_rect()
	check(badge_rect.position.y >= 104.0, "demo badge is below video HUD")
	check(absf(badge_rect.get_center().x - T.VIEW_SIZE.x * 0.5) <= 2.0, "demo badge is horizontally centered")

	var band_rect: Rect2 = demo.hint_band.get_global_rect()
	check(demo.hint_band.is_visible_in_tree(), "demo hint band is visible")
	check(is_equal_approx(band_rect.position.y, 632.0) and is_equal_approx(band_rect.end.y, 684.0), "demo hint band spans y=632..684")
	var hint_min: Vector2 = demo.hint.get_minimum_size()
	check(hint_min.x <= band_rect.size.x and hint_min.y <= band_rect.size.y, "demo hint minimum size fits band")

	demo.blink_clock = 0.0
	demo._process(0.31)
	check(is_equal_approx(demo.demo_panel.modulate.a, 0.55), "demo badge dims to alpha 0.55")
	check(demo.demo_panel.modulate.a >= 0.5, "demo badge keeps readable minimum alpha")
	demo._process(0.29)
	check(is_equal_approx(demo.demo_panel.modulate.a, 1.0), "demo badge bright phase uses full opacity")

func check_title_input_reset() -> void:
	game.show_menu("title")
	game.title_idle = 5.0
	tap(KEY_A)
	check(game.title_idle == 0.0, "title key resets idle")
	game.title_idle = 5.0
	motion(Vector2(700, 400), Vector2(3, 0))
	await frames(1)
	check(game.title_idle < 0.1, "title mouse motion resets idle")

func check_blocked_states() -> void:
	game.show_menu("title")
	game.open_key_settings()
	await check_blocked("key settings")
	game.close_key_settings()
	await frames(2)

	game.open_audio_settings()
	await check_blocked("audio settings")
	game.close_audio_settings()
	await frames(2)

	game.start_tutorial()
	await frames(4)
	check(is_instance_valid(game.tutorial_session), "tutorial session starts for idle guard")
	await check_blocked("tutorial")
	game.finish_tutorial()
	await frames(3)

	game.start_run(37)
	await frames(3)
	await check_blocked("main run")
	game.show_menu("paused")
	await check_blocked("pause")
	game.show_menu("lost")
	await check_blocked("result")
	game.show_menu("title")
	await frames(2)

func check_demo_dismissal() -> void:
	game.key_bindings.reset_defaults()
	check(await begin_demo("2027"), "key dismissal begins from demo")
	tap(KEY_SPACE)
	await frames(1)
	check(not game.title_demo_playing(), "jump key stops demo")
	check(game.state == "playing" and game.current_seed == 2027, "jump key starts seed field run")
	var player: Node = game.player
	check(is_instance_valid(player) and player.jump_buffer == 0.0 and not player.pending_dash and not player.pending_flip, "jump press does not leak into play")

	check(await begin_demo("2028"), "click dismissal begins from demo")
	var target: Vector2 = game.ui.new_button.get_global_rect().get_center()
	motion(target)
	mouse_button(target, true)
	mouse_button(target, false)
	await frames(2)
	check(not game.title_demo_playing(), "mouse press stops demo")
	check(game.state == "playing" and game.current_seed == 2028, "mouse press starts seed field run")
	check(game.ui.seed_field.text == "2028", "new-map button is not clicked under demo")

	check(await begin_demo("2029"), "motion test begins from demo")
	motion(Vector2(700, 400), Vector2(5, 0))
	await frames(2)
	check(game.title_demo_playing(), "mouse motion alone leaves demo playing")
	game.title_demo.stop()

func check_demo_finish_and_missing() -> void:
	check(await begin_demo("2030"), "finish test begins from demo")
	game.title_demo.video.finished.emit()
	check(game.state == "title" and game.title_idle == 0.0, "video finish returns to title and resets idle")
	await frames(2)
	check(not game.title_demo_playing() and not game.title_demo.visible, "video finish hides demo")
	check(game.ui.menu.visible, "video finish restores title menu")

	game.show_menu("title")
	game.title_demo.video_path = "res://assets/video/missing_title_demo.ogv"
	check(not game.title_demo.start(), "missing demo path reports no start")
	game.title_idle = T.TITLE_DEMO_IDLE - 0.01
	await frames(4)
	check(not game.title_demo_playing() and game.title_idle < 0.1, "missing demo path starts nothing")
	game.title_demo.video_path = T.TITLE_DEMO_PATH

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://builds/qa/demo")
	game = Main.new()
	game.controls_path = "res://builds/qa/demo/test_controls.cfg"
	root.add_child(game)
	await frames(3)
	game.key_bindings.reset_defaults()
	await check_demo_launch()
	await check_title_input_reset()
	await check_blocked_states()
	await check_demo_dismissal()
	await check_demo_finish_and_missing()
	game.free()
	FileAccess.open("res://builds/qa/demo/title_demo_results.json", FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures}, "\t"))
	print("TITLE DEMO TEST: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
