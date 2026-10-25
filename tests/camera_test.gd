extends SceneTree
## Camera checks use the generated terrain and real player physics at 60 Hz.
const Main := preload("res://scripts/main.gd")
const T := preload("res://scripts/tuning.gd")
const SAFE_BOTTOM := 640.0 # Footer y=670 minus player half-height 22 and eight-pixel margin.
const MAX_CAMERA_STEP := 32.0 # Less than one tile per 60 Hz frame at maximum fall speed.
var game: Node2D
var checks := 0
var failures: Array[String] = []
var measurements := {}

func _initialize() -> void:
	call_deferred("run")

func frames(count: int = 1) -> void:
	for index in range(count):
		await physics_frame
		await process_frame

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: ", message)

func prepare(initial_position: Vector2) -> void:
	for action: String in ["move_left", "move_right", "jump", "shoot", "special", "interact"]:
		Input.action_release(action)
	game.start_run(37)
	for actor in get_nodes_in_group("enemies"):
		actor.set_physics_process(false)
	game.player.position = initial_position
	game.player.velocity = Vector2.ZERO
	game._update_camera(0.0, true)
	await frames(3)

func observe(sample: Dictionary, previous_camera: Vector2) -> void:
	var view: Rect2 = game.view_rect()
	var screen: Vector2 = game.player.position - view.position
	var body: Rect2 = Rect2(game.player.position - T.PLAYER_SIZE / 2, T.PLAYER_SIZE)
	var camera_bounds: Rect2 = Rect2(game.stage.bounds.position + T.VIEW_SIZE / 2, game.stage.bounds.size - T.VIEW_SIZE)
	sample.frames += 1
	sample.max_screen_y = maxf(sample.max_screen_y, screen.y)
	sample.min_screen_y = minf(sample.min_screen_y, screen.y)
	sample.max_camera_step = maxf(sample.max_camera_step, previous_camera.distance_to(game.camera.position))
	sample.max_fall_speed = maxf(sample.max_fall_speed, game.player.velocity.y)
	if not view.grow(-8).encloses(body):
		sample.body_outside_frames.append(sample.frames)
	if not camera_bounds.grow(0.01).has_point(game.camera.position):
		sample.camera_outside_frames.append(sample.frames)

func new_sample() -> Dictionary:
	return {"frames": 0, "max_screen_y": -INF, "min_screen_y": INF, "max_camera_step": 0.0, "max_fall_speed": 0.0, "body_outside_frames": [], "camera_outside_frames": []}

func assert_sample(sample: Dictionary, context: String) -> void:
	check(sample.body_outside_frames.is_empty(), context + ": whole player body remains visible with an eight-pixel viewport margin")
	check(sample.max_screen_y <= SAFE_BOTTOM, context + ": player remains above the footer while moving")
	check(sample.max_camera_step <= MAX_CAMERA_STEP, context + ": camera moves less than one tile per physics frame")
	check(sample.camera_outside_frames.is_empty(), context + ": camera remains inside world bounds")

func run() -> void:
	game = Main.new()
	game.controls_path = "res://builds/qa/camera_controls.cfg"
	root.add_child(game)
	game.key_bindings.reset_defaults()
	# The real highest central platform has its top at y=768. Moving this single
	# initial fixture to x=6900 clears every central shelf, leaving the generated
	# continuous floor beneath a 1,536-pixel fall. No coordinates change in flight.
	await prepare(Vector2(6900, 768 - T.PLAYER_SIZE.y / 2))
	var sample := new_sample()
	var landed := false
	for index in range(240):
		var previous: Vector2 = game.camera.position
		await frames()
		observe(sample, previous)
		if game.player.is_on_floor():
			landed = true
			break
	assert_sample(sample, "long free fall")
	check(landed, "long free fall lands on the generated continuous floor")
	check(sample.max_fall_speed >= T.MAX_FALL_SPEED - 0.1, "fall exercises the configured maximum fall speed")
	check(absf(game.player.position.x - 6900) < 0.1, "free fall never teleports or changes horizontal position")
	check(absf(game.player.position.y + T.PLAYER_SIZE.y / 2 - T.GROUND_Y) < 0.5, "landing uses the generated y=2304 floor")
	var landing_position: Vector2 = game.player.position
	var stable_positions: Array[float] = []
	var settle_max_step := 0.0
	var direction_changes := 0
	var last_direction := 0
	for index in range(150):
		var previous: Vector2 = game.camera.position
		await frames()
		settle_max_step = maxf(settle_max_step, previous.distance_to(game.camera.position))
		var difference: float = game.camera.position.y - previous.y
		var direction := int(signf(difference)) if absf(difference) > 0.05 else 0
		if direction != 0:
			if last_direction != 0 and direction != last_direction:
				direction_changes += 1
			last_direction = direction
		if index >= 120:
			stable_positions.append(game.camera.position.y)
	var final_jitter: float = stable_positions.max() - stable_positions.min()
	check(game.player.position.distance_to(landing_position) < 0.1, "player remains grounded throughout camera settling")
	check(settle_max_step <= MAX_CAMERA_STEP, "landing does not snap the camera when fall look-ahead ends")
	check(direction_changes <= 1, "camera settling has no repeated direction changes")
	check(final_jitter < 0.05, "camera is stationary after settling")
	sample["landing_settle_max_step"] = settle_max_step
	sample["landing_direction_changes"] = direction_changes
	sample["final_jitter"] = final_jitter
	measurements.long_fall = sample
	# The upward test starts on the real central floor. A single full jump passes
	# through the real one-way shelf at y=2176 and lands on its upper surface.
	await prepare(game.stage.start_position)
	var start_y: float = game.player.position.y
	var minimum_y := start_y
	var jump_sample := new_sample()
	var event := InputEventAction.new()
	event.action = "jump"
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	for index in range(45):
		var previous: Vector2 = game.camera.position
		await frames()
		observe(jump_sample, previous)
		minimum_y = minf(minimum_y, game.player.position.y)
	Input.action_release("jump")
	assert_sample(jump_sample, "upward platform jump")
	check(start_y - minimum_y > 160, "upward camera test exercises a full-height physical jump")
	check(game.player.is_on_floor() and absf(game.player.position.y + T.PLAYER_SIZE.y / 2 - (T.GROUND_Y - 128)) < 0.5, "jump lands on the first generated central shelf")
	measurements.upward_jump = jump_sample
	game.queue_free()
	await frames(2)
	DirAccess.make_dir_recursive_absolute("res://builds/qa/seamless")
	var report := {"checks": checks, "failures": failures, "measurements": measurements}
	var file := FileAccess.open("res://builds/qa/seamless/camera_results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("CAMERA RESULT: ", checks, " checks, ", failures.size(), " failures; ", measurements)
	quit(0 if failures.is_empty() else 1)
