extends "res://tests/ability_physics_test.gd"
## Task 9D: steerable eight-way air dash, dash shake and afterimages, and the
## in-air shot-direction arrow that replaced the HUD readout.

func tap(action: String) -> void:
	input(action, true)
	input(action, false)

func release_all() -> void:
	for action in ["jump", "dash", "move_up", "move_down", "move_left", "move_right", "gravity_flip", "aim_cycle"]: input(action, false)

func airborne_dash(actions: Array) -> void:
	await reset(T.ABILITY_DASH, false)
	game.player.velocity = Vector2.ZERO
	game.player.facing = 1
	for action: String in actions: input(action, true)
	tap("dash")
	await frames()

func steering_tests() -> void:
	var cases := {
		[]: Vector2.RIGHT, ["move_right"]: Vector2.RIGHT, ["move_left"]: Vector2.LEFT, ["move_up"]: Vector2.UP, ["move_down"]: Vector2.DOWN,
		["move_up", "move_right"]: Vector2(1, -1).normalized(), ["move_up", "move_left"]: Vector2(-1, -1).normalized(),
		["move_down", "move_right"]: Vector2(1, 1).normalized(), ["move_down", "move_left"]: Vector2(-1, 1).normalized()}
	for actions: Array in cases:
		await airborne_dash(actions)
		check(game.player.dash_vector.is_equal_approx(cases[actions]) and is_equal_approx(game.player.velocity.length(), T.AIR_DASH_SPEED), "initial eight-way direction %s" % [actions])
		release_all()
	# Steer mid-dash: right, then up, then let go; time and speed stay fixed.
	await airborne_dash([])
	var path: Array[Vector2] = [game.player.position]
	await frames(2)
	path.append(game.player.position)
	input("move_up", true)
	await frames()
	check(game.player.dash_vector == Vector2.UP and game.player.velocity == Vector2.UP * T.AIR_DASH_SPEED, "holding a direction steers on the next frame")
	path.append(game.player.position)
	input("move_up", false)
	await frames()
	check(game.player.dash_vector == Vector2.UP, "releasing the keys keeps the steered direction")
	input("move_down", true)
	input("move_left", true)
	await frames()
	check(game.player.dash_vector.is_equal_approx(Vector2(-1, 1).normalized()) and game.player.facing == -1, "steering into a diagonal turns the facing")
	input("move_down", false)
	input("move_left", false)
	var count := 6 # Frames simulated since the dash key.
	while game.player.dash_remaining > 0 and count < 30:
		await frames()
		count += 1
	check(count == ceili(T.AIR_DASH_TIME * 60), "steering never extends the dash: %d frames" % count)
	check(absf(path[1].x - path[0].x - 2 * T.AIR_DASH_SPEED / 60) < 0.2 and absf(path[2].y - path[1].y + T.AIR_DASH_SPEED / 60) < 0.2, "each dash frame travels the full dash speed")
	release_all()
	# The last dash frame keeps its direction; the keys then only set the exit speed.
	await airborne_dash([])
	await frames(ceili(T.AIR_DASH_TIME * 60) - 2)
	check(game.player.dash_remaining > 0 and game.player.dash_remaining <= 1.0 / 60, "one dash frame remains")
	var before_last: Vector2 = game.player.position
	input("move_up", true)
	input("move_right", true)
	await frames()
	check(game.player.dash_vector == Vector2.RIGHT and game.player.dash_remaining == 0, "last dash frame is not steered")
	check(absf(game.player.position.y - before_last.y) < 0.01 and game.player.velocity.x == game.player.move_speed(), "last frame moves straight; held side key sets exit speed")
	release_all()
	# A held direction during the start frame is not a reason to re-trigger the dash.
	await airborne_dash(["move_right"])
	check(game.player.air_dash_used, "dash consumed")
	tap("dash")
	await frames()
	check(game.player.dash_remaining > 0 and game.player.dash_frames == 2, "dash key during a dash does not restart it")
	release_all()
	# Diagonal into a wall slides along it; straight into the wall ends.
	await reset(T.ABILITY_DASH, false)
	fixture(Rect2(70, -1000, 32, 2000))
	await frames()
	game.player.velocity = Vector2.ZERO
	input("move_up", true)
	input("move_right", true)
	tap("dash")
	var top: float = game.player.position.y
	await frames(6)
	check(game.player.is_on_wall() and game.player.dash_remaining > 0 and game.player.position.y < top - 60, "diagonal dash slides up the wall")
	input("move_up", false)
	await frames()
	check(game.player.dash_remaining == 0, "steering straight into the wall ends the dash")
	release_all()
	# Under flipped gravity, steering is still in screen directions.
	await reset(T.ABILITY_DASH, false)
	tap("gravity_flip")
	await frames()
	tap("dash")
	await frames()
	input("move_down", true)
	await frames()
	check(game.player.gravity_sign == -1 and game.player.dash_vector == Vector2.DOWN, "flipped gravity steers in screen space")
	for i in range(12):
		if game.player.dash_remaining <= 0: break
		await frames()
	check(game.player.velocity.y == 0.0, "flipped dash toward screen-down (against gravity) exits without vertical speed")
	release_all()

func afterimage_tests() -> void:
	await reset(T.ABILITY_DASH, false)
	game.player.velocity = Vector2.ZERO
	var start: Vector2 = game.player.global_position
	tap("dash")
	await frames()
	var trail: Node2D = game.dash_afterimages
	check(is_instance_valid(trail) and trail.get_parent() == game.effects and trail.images.size() == 1, "dash start records an afterimage on the effects layer")
	check(not trail.z_as_relative and trail.z_index == -1, "afterimages draw above terrain and behind actors")
	check(trail.to_global(trail.images[0].at) == start and trail.images[0].polarity == game.player.polarity, "first afterimage is at the dash start in the player's color")
	await frames(10)
	check(game.player.dash_remaining == 0 and trail.images.size() == 6, "one afterimage every %d physics frames: %d" % [T.DASH_AFTERIMAGE_INTERVAL, trail.images.size()])
	check(trail.alpha(trail.images[0]) < trail.alpha(trail.images[-1]) and trail.alpha(trail.images[-1]) <= T.DASH_AFTERIMAGE_ALPHA, "older afterimages are fainter")
	var spacing: float = trail.images[1].at.distance_to(trail.images[0].at)
	check(absf(spacing - 2 * T.AIR_DASH_SPEED / 60) < 0.2, "afterimages trail along the path")
	await frames(ceili(T.DASH_AFTERIMAGE_TIME * 60) + 1)
	check(trail.images.is_empty(), "afterimages vanish after %.2f s" % T.DASH_AFTERIMAGE_TIME)
	for i in range(T.DASH_AFTERIMAGE_MAX + 4): game.dash_afterimage(game.player)
	check(trail.images.size() == T.DASH_AFTERIMAGE_MAX, "afterimage count is capped")
	trail.clear()
	release_all()

func main_tests() -> void:
	release_all()
	if is_instance_valid(game): game.free()
	game = Main.new()
	game.controls_path = "user://dash_aim_test_controls.cfg"
	root.add_child(game)
	game.start_run(37)
	for enemy in get_nodes_in_group("enemies"): enemy.set_physics_process(false)
	await frames(3)
	var player: Node2D = game.player
	player.abilities = T.ABILITY_DASH
	# HUD: no color or direction readout.
	game.ui.update_hud()
	check(game.ui.get("angle_label") == null and game.ui.get("color_label") == null and game.ui.get("color_icon") == null, "HUD color and direction nodes are removed")
	check(game.ui.find_children("*", "Label", true, false).all(func(label): return not label.text.begins_with("射撃方向 ")), "no HUD readout of the shot direction")
	# Shake: offset only, from the dash start, exactly zero afterwards.
	check(game.camera.offset == Vector2.ZERO and not game.effects.aim_indicator_visible(), "run starts without shake or arrow")
	input("jump", true)
	await frames(6)
	tap("dash")
	await frames(2)
	check(player.dash_remaining > 0 or player.air_dash_used, "real run dash started")
	var offset: Vector2 = game.camera.offset
	check(offset != Vector2.ZERO and absf(offset.x) <= T.DASH_SHAKE_PIXELS and absf(offset.y) <= T.DASH_SHAKE_PIXELS, "dash shakes the camera by at most %.0f px: %s" % [T.DASH_SHAKE_PIXELS, offset])
	check(game.view_rect().get_center() == game.camera.position, "view rect (streaming, on-screen checks) ignores the shake")
	await frames(ceili(T.DASH_SHAKE_TIME * 60))
	check(game.camera.offset == Vector2.ZERO, "shake ends exactly at zero offset")
	input("move_down", true)
	await frames(2)
	check(game.camera.offset == Vector2.ZERO, "steering does not shake again")
	release_all()
	await frames(60)
	# Composition with the boss impact shake.
	game.impact_shake = Vector2(2, -1)
	game.shake_camera(T.DASH_SHAKE_PIXELS, T.DASH_SHAKE_TIME)
	check(game.camera.offset == Vector2(2, -1) + Vector2(0, T.DASH_SHAKE_PIXELS), "impact and dash shakes add up")
	game.boss_impact.cancel()
	check(game.impact_shake == Vector2.ZERO and game.camera.offset == Vector2(0, T.DASH_SHAKE_PIXELS), "impact cancel keeps a running dash shake")
	await frames(ceili(T.DASH_SHAKE_TIME * 60) + 1)
	check(game.camera.offset == Vector2.ZERO, "both shakes over: offset is zero")
	# Aim arrow: appears only on change, ahead of the player along the shot.
	check(player.aim_indicator_remaining == 0, "no arrow before any change")
	tap("aim_cycle")
	check(player.aim_index == 1 and player.aim_indicator_remaining == T.AIM_INDICATOR_TIME, "aim change starts the arrow timer")
	await frames()
	check(game.effects.aim_indicator_visible() and game.effects.aim_indicator_point() == player.position + player.shot_direction() * T.AIM_INDICATOR_DISTANCE, "arrow is ahead of the player along the shot")
	check(player.shot_direction().y < 0 and player.aim_indicator_alpha() == 1.0, "up aim arrow points up, fully opaque")
	player.facing = -player.facing
	check((game.effects.aim_indicator_point().x - player.position.x) * player.facing > 0, "arrow follows a turn to the other side")
	await frames(ceili(T.AIM_INDICATOR_SOLID * 60) - 2)
	check(player.aim_indicator_alpha() == 1.0, "arrow stays opaque for %.1f s" % T.AIM_INDICATOR_SOLID)
	await frames(3)
	check(player.aim_indicator_alpha() < 1.0 and game.effects.aim_indicator_visible(), "arrow then fades")
	tap("aim_cycle")
	check(player.aim_indicator_remaining == T.AIM_INDICATOR_TIME, "another change restarts the arrow")
	await frames(ceili(T.AIM_INDICATOR_TIME * 60) + 1)
	check(not game.effects.aim_indicator_visible(), "arrow disappears after %.1f s" % T.AIM_INDICATOR_TIME)
	player.gravity_sign = -1
	player.aim_index = 0
	tap("aim_cycle")
	await frames()
	check(game.effects.aim_indicator_point().y > player.position.y, "flipped up aim arrow points screen-down")
	player.gravity_sign = 1
	# Afterimages survive an origin shift with the world.
	game.dash_afterimage(player)
	var trail: Node2D = game.dash_afterimages
	var before: Vector2 = trail.to_global(trail.images[-1].at) - player.global_position
	var delta: Vector2 = game.shift_origin(Vector2i(1, 0))
	check(delta == Vector2(-T.SECTOR_SIZE.x, 0) and trail.to_global(trail.images[-1].at) - player.global_position == before, "origin shift moves afterimages with the world")
	# Death clears afterimages and hides the arrow.
	tap("aim_cycle")
	player.invulnerability = 0
	player.receive_neutral_hit(99999)
	await frames(2)
	check(trail.images.is_empty() and not game.effects.aim_indicator_visible(), "death clears afterimages and the arrow")
	game.primary_action()
	await frames(2)
	check(game.player.aim_indicator_remaining == 0 and not is_instance_valid(trail), "retry starts without arrow or afterimages")
	# The tutorial teaches aiming, so it shows the arrow too.
	game.start_tutorial()
	await frames(2)
	var practice: Node2D = game.tutorial_session
	tap("aim_cycle")
	await frames()
	check(practice.effects.aim_indicator_visible(), "tutorial shows the arrow on aim change")
	release_all()

func run() -> void:
	await steering_tests()
	await afterimage_tests()
	await main_tests()
	release_all()
	game.free()
	print("DASH AIM: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
