extends SceneTree
const Main := preload("res://scripts/main.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Terrain := preload("res://scripts/terrain.gd")
const Laser := preload("res://scripts/laser_beam.gd")
const T := preload("res://scripts/tuning.gd")
const FLOOR_Y := 2304.0
var game: Node2D
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: ", message)

func frames(count: int) -> void:
	for index in range(count):
		await physics_frame
		await process_frame

func fixture() -> void:
	game.start_run(37)
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	for child in game.world.get_children():
		if child != game.player and child != game.projectiles and child != game.effects:
			child.free()
	var floor_body := Terrain.new()
	floor_body.bounds = Rect2(4800, FLOOR_Y, 3200, 768)
	game.world.add_child(floor_body)
	game.player.position = Vector2(5400, FLOOR_Y - T.PLAYER_SIZE.y / 2)
	game.player.velocity = Vector2.ZERO
	game.player.polarity = 0
	game.camera.position = Vector2(5680, 2100)
	await frames(3)

func spawn(kind: String) -> CharacterBody2D:
	var enemy := Enemy.new()
	enemy.game = game
	enemy.kind = kind
	enemy.spawn_id = "fixture_" + kind
	enemy.polarity = 0
	enemy.position = Vector2(5800, FLOOR_Y - (T.FLYER_ALTITUDE if kind == "flyer" else T.ENEMY_SIZE.y / 2))
	enemy.patrol = Vector2(5640, 5928) if kind == "flyer" else Vector2(5800, 5800)
	game.world.add_child(enemy)
	return enemy

func begin_laser(enemy: CharacterBody2D) -> Node2D:
	enemy.was_visible = true
	enemy.wake_delay = 0
	enemy.shot_clock = 0
	await frames(1)
	return enemy.laser_beam

func verify_flyer() -> void:
	await fixture()
	var flyer = spawn("flyer")
	flyer.shot_clock = 100
	var center: float = flyer.position.y
	var min_y := center
	var max_y := center
	var min_x: float = flyer.position.x
	var max_x := min_x
	var in_lane := true
	var clear := true
	for index in range(480):
		await frames(1)
		min_y = minf(min_y, flyer.position.y)
		max_y = maxf(max_y, flyer.position.y)
		min_x = minf(min_x, flyer.position.x)
		max_x = maxf(max_x, flyer.position.x)
		in_lane = in_lane and flyer.position.x >= flyer.patrol.x and flyer.position.x <= flyer.patrol.y
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = flyer.get_child(0).shape
		query.transform = flyer.global_transform
		query.collision_mask = 1 | T.PLATFORM_LAYER
		clear = clear and flyer.get_world_2d().direct_space_state.intersect_shape(query).is_empty()
	check(in_lane and max_x - min_x > 280, "flyer reverses within its horizontal lane over eight seconds")
	check(min_y >= center - T.FLYER_BOB_AMPLITUDE - 0.1 and max_y <= center + T.FLYER_BOB_AMPLITUDE + 0.1 and max_y - min_y > 31, "flyer bobs without falling")
	check(clear and flyer.velocity == Vector2.ZERO, "flyer never intersects terrain or gains gravity velocity")
	game.camera.position.x = 9000
	flyer.shot_clock = 0
	var parked: Vector2 = flyer.position
	var phase: float = flyer.flight_clock
	await frames(180)
	check(flyer.position == parked and flyer.flight_clock == phase and flyer.action == "idle" and game.projectiles.get_child_count() == 0, "offscreen flyer waits in place without attacking")
	game.camera.position.x = 5680
	await frames(60)
	check(game.projectiles.get_child_count() == 0 and flyer.wake_delay > 0, "flyer re-entry takes the full wake delay")
	await frames(10)
	check(flyer.action == "windup_shot", "flyer uses the shared normal-shot warning")
	await frames(30)
	check(game.projectiles.get_child_count() == 1, "flyer launches an actual normal projectile after warning")
	for bullet in game.projectiles.get_children():
		bullet.free()
	flyer.set_physics_process(false)
	flyer.position = Vector2(5800, center)
	game.player.facing = 1
	game.player.polarity = 1
	game.player.position = Vector2(5400, FLOOR_Y - T.PLAYER_SIZE.y / 2)
	game.spawn_bullet(game.player, Vector2.RIGHT)
	await frames(40)
	check(flyer.hp == T.ENEMY_HP, "standing horizontal shot passes below flyer")
	game.player.position.y = FLOOR_Y - 65
	game.spawn_bullet(game.player, Vector2.RIGHT)
	await frames(35)
	check(flyer.hp == T.ENEMY_HP, "short-jump horizontal shot passes below flyer")
	game.player.position.y = FLOOR_Y - 192 # Actual full jump apex center is approximately floor -192.
	game.spawn_bullet(game.player, Vector2.RIGHT)
	await frames(35)
	check(flyer.hp == T.ENEMY_HP - T.NORMAL_DAMAGE, "horizontal shot at high-jump apex reaches flyer")

func verify_laser_timing() -> void:
	await fixture()
	var enemy = spawn("laser")
	var awake_frames := int(ceil(T.ENEMY_WAKE_DELAY * 60))
	await frames(awake_frames - 2)
	check(enemy.action == "idle" and game.projectiles.get_child_count() == 0, "laser respects wake delay")
	await frames(4)
	check(enemy.shot_clock > T.LASER_INTERVAL - 0.1, "laser interval starts after waking")
	await frames(int(T.LASER_INTERVAL * 60) - 6)
	check(enemy.action == "idle", "laser waits its own 2.6 second interval")
	await frames(10)
	var beam = enemy.laser_beam
	check(is_instance_valid(beam) and beam.phase == "warning" and enemy.action == "windup_laser", "laser enters warning before irradiation")
	var curve: PackedVector2Array = beam.curve.duplicate()
	var deviation := 0.0
	for point in curve:
		deviation = maxf(deviation, point.distance_to(Geometry2D.get_closest_point_to_segment(point, curve[0], curve[-1])))
	var chord: float = curve[0].distance_to(curve[-1])
	check(deviation >= clampf(chord * T.LASER_CURVE_RATIO, T.LASER_CURVE_MIN, T.LASER_CURVE_MAX) * 0.49, "quadratic laser bends by at least half its control-point offset")
	check(curve[curve.size() / 2].y < (curve[0].y + curve[-1].y) / 2, "nonvertical curve bends upward")
	game.player.position.x -= 50
	enemy.polarity = 1
	var warning_remaining: float = enemy.action_remaining
	var elapsed: float = beam.elapsed
	game.show_menu("paused")
	await frames(45)
	check(enemy.action_remaining == warning_remaining and beam.elapsed == elapsed and beam.phase == "warning", "pause freezes laser warning")
	game.open_key_settings()
	await frames(20)
	check(enemy.action_remaining == warning_remaining and beam.elapsed == elapsed, "key settings freezes laser warning")
	game.close_key_settings()
	game.resume_run()
	var count := 0
	while is_instance_valid(beam) and beam.phase == "warning" and count < 60:
		await frames(1)
		count += 1
	check(absf(count / 60.0 - warning_remaining) <= 2.0 / 60, "warning lasts the configured physics time")
	check(is_instance_valid(beam) and beam.phase == "beam" and beam.curve == curve and beam.polarity == 0, "irradiation preserves warning target, curve and launch color")
	var remaining: float = beam.remaining
	game.show_menu("paused")
	await frames(30)
	check(beam.remaining == remaining, "pause freezes active irradiation")
	game.resume_run()
	count = 0
	while is_instance_valid(beam) and count < 30:
		await frames(1)
		count += 1
	check(absf(count / 60.0 - remaining) <= 2.0 / 60, "beam expires after configured irradiation time")
	check(enemy.action == "idle" and enemy.shot_clock > T.LASER_INTERVAL - 0.1, "laser completes before scheduling another attack")
	var vertical := Laser.new()
	vertical.build_curve(Vector2(0, 300), Vector2(0, 100), -1)
	check(vertical.curve[T.LASER_SEGMENTS / 2].x < -40, "nearly vertical laser bends toward enemy facing")
	vertical.free()

func verify_hits() -> void:
	for color in [0, 1]:
		await fixture()
		var enemy = spawn("laser")
		game.player.polarity = color
		var beam = await begin_laser(enemy)
		await frames(30)
		check(game.player.hp == T.PLAYER_HP and game.player.gauge == 0, "warning does not hit color %d" % color)
		await frames(10)
		check(is_instance_valid(beam) and beam.contacted, "beam registers first contact color %d" % color)
		if color == 0:
			check(game.player.hp == T.PLAYER_HP and game.player.gauge == 1, "same-color beam absorbs once")
		else:
			check(game.player.hp == T.PLAYER_HP - T.LASER_DAMAGE and game.player.gauge == 0, "opposite-color beam deals LASER_DAMAGE once")
		# Remove hit protection each frame so a repeated-hit bug cannot hide behind it.
		for index in range(12):
			game.player.invulnerability = 0
			await frames(1)
		check(game.player.hp == T.PLAYER_HP - (T.LASER_DAMAGE if color == 1 else 0) and game.player.gauge == (1 if color == 0 else 0), "continuous overlap cannot hit or absorb twice color %d" % color)
	await fixture()
	var enemy = spawn("laser")
	game.player.polarity = 1
	game.player.invulnerability = 10
	var beam = await begin_laser(enemy)
	await frames(40)
	check(beam.contacted and game.player.hp == T.PLAYER_HP, "invulnerable player consumes the single contact as protected")
	game.player.invulnerability = 0
	await frames(10)
	check(game.player.hp == T.PLAYER_HP, "protected contact never retries after protection ends")
	check(Laser.segment_touches_rect(Vector2(-20, -5), Vector2(20, -5), Rect2(0, 0, 10, 10), 6), "beam radius reaches a nearby rectangle")
	check(not Laser.segment_touches_rect(Vector2(-20, -7), Vector2(20, -7), Rect2(0, 0, 10, 10), 6), "beam radius excludes a separated rectangle")

func verify_clipping_and_cancellation() -> void:
	await fixture()
	var enemy = spawn("laser")
	var beam = await begin_laser(enemy)
	var original_path: PackedVector2Array = beam.path.duplicate()
	var wall := Terrain.new()
	wall.bounds = Rect2(5600, 1800, 32, 504)
	game.world.add_child(wall)
	await frames(3)
	check(beam.path == original_path, "warning path stays fixed until irradiation")
	await frames(35)
	check(beam.phase == "beam" and beam.path[-1].x >= 5631 and beam.path.size() < beam.curve.size(), "irradiation refresh clips the first terrain intersection")
	await frames(18)
	check(game.player.gauge == 0 and game.player.hp == T.PLAYER_HP, "terrain shields the player behind it")
	beam = await begin_laser(enemy)
	check(beam.path[-1].x >= 5631 and beam.path.size() < beam.curve.size(), "warning also clips against existing terrain")
	game.camera.position.x = 9000
	await frames(2)
	check(not is_instance_valid(beam) and enemy.action == "idle", "leaving screen removes laser warning")
	await frames(180)
	check(game.projectiles.get_child_count() == 0 and not enemy.was_visible, "offscreen laser never warns or fires")
	game.camera.position.x = 5680
	enemy.shot_clock = 0
	await frames(60)
	check(enemy.action == "idle" and enemy.wake_delay > 0, "laser re-entry restarts wake delay")
	await frames(10)
	beam = enemy.laser_beam
	check(is_instance_valid(beam) and beam.phase == "warning", "laser warns after re-entry delay")
	enemy.receive_hit(1, T.ENEMY_HP)
	check(beam.is_queued_for_deletion() and not beam.visible, "defeated source immediately hides and queues its warning for removal")
	await frames(2)
	check(not is_instance_valid(beam), "source defeat removes warning node")
	for cause in ["offscreen", "defeat"]:
		await fixture()
		enemy = spawn("laser")
		beam = await begin_laser(enemy)
		await frames(38)
		check(is_instance_valid(beam) and beam.phase == "beam", "active beam fixture for " + cause)
		if cause == "offscreen":
			game.camera.position.x = 9000
		else:
			enemy.receive_hit(1, T.ENEMY_HP)
		await frames(2)
		check(not is_instance_valid(beam), "active beam removed on " + cause)
	await fixture()
	enemy = spawn("laser")
	beam = game.spawn_laser(enemy)
	beam.build_curve(Vector2(5800, 2100), Vector2(13000, 2100), 1)
	beam.clip_path()
	check(beam.path[-1].x <= T.WORLD_SIZE.x and beam.path.size() < beam.curve.size(), "curve stops at world boundary")
	var old_world: Node2D = game.world
	game.start_run(37)
	await frames(2)
	check(not is_instance_valid(beam) and not is_instance_valid(old_world) and game.projectiles.get_child_count() == 0, "retry clears every old laser and its world")

func verify_shared_special() -> void:
	for kind in ["flyer", "laser"]:
		await fixture()
		var enemy = spawn(kind)
		enemy.was_visible = true
		enemy.wake_delay = 0
		enemy.shot_clock = 0
		enemy.gauge = T.GAUGE_CAPACITY
		await frames(1)
		check(enemy.action == "windup_special" and game.projectiles.get_child_count() == 0, kind + " uses exclusive shared special warning")
		await frames(50)
		check(enemy.gauge == 0 and game.projectiles.get_child_count() == T.GAUGE_CAPACITY, kind + " spends gauge on shared guided projectiles")

func run() -> void:
	game = Main.new()
	game.controls_path = "res://builds/qa/phase3/enemy_controls.cfg"
	root.add_child(game)
	await verify_flyer()
	await verify_laser_timing()
	await verify_hits()
	await verify_clipping_and_cancellation()
	await verify_shared_special()
	game.free()
	await frames(2)
	print("ENEMY TYPES TEST: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
