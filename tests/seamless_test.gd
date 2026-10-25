extends SceneTree
const Main := preload("res://scripts/main.gd")
const T := preload("res://scripts/tuning.gd")

var game: Node2D
var checks := 0
var failures: Array[String] = []
var measurements: Dictionary = {}

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

func action(name: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = name
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func raw_e() -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_E
		event.physical_keycode = KEY_E
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()

func silence_enemies() -> void:
	for actor in get_nodes_in_group("enemies"):
		actor.set_physics_process(false)

func ground_at(x: float) -> float:
	var ground := INF
	for solid: Rect2 in game.stage.solids:
		if solid.size.y > 20 and solid.size.x > 64 and x >= solid.position.x and x < solid.end.x:
			ground = minf(ground, solid.position.y)
	return ground

func cross_region(boundary: float) -> void:
	game.start_run(37)
	silence_enemies()
	var floor_y := ground_at(boundary - 72)
	check(is_finite(floor_y), "Ground exists under region boundary %.0f" % boundary)
	game.player.position = Vector2(boundary - 72, floor_y - T.PLAYER_SIZE.y / 2)
	game.player.velocity = Vector2.ZERO
	game.player.hp = 88
	game.player.gauge = 5
	game.score = 200
	game._update_camera(0.0, true)
	await frames(3)
	var world_id: int = game.world.get_instance_id()
	var player_id: int = game.player.get_instance_id()
	var projectile_container_id: int = game.projectiles.get_instance_id()
	var terrain = game.world.get_children().filter(func(child): return child.has_method("mask_for_cell"))[0]
	terrain.explode(Vector2(boundary - 500, ground_at(boundary - 500) + 32), 60)
	var damaged: Dictionary = terrain.destroyed_cells.duplicate()
	var wall_id := -1
	for column in range(int(boundary + 320) / 32, int(boundary + 640) / 32):
		var x := float(column * 32)
		wall_id = terrain.place_wall(Rect2(x, ground_at(x) - 96, 32, 96), 123)
		if wall_id >= 0:
			break
	check(not damaged.is_empty() and wall_id >= 0, "Boundary fixture includes destroyed floor and installed wall")
	var wall_cells: Array = terrain.walls[wall_id].cells.duplicate()
	var wall_remaining: float = terrain.walls[wall_id].remaining
	var collision_id: int = terrain.collision_root.get_instance_id()
	var shapes: int = terrain.collision_root.get_child_count()
	var witness = get_nodes_in_group("enemies").filter(func(actor): return actor.kind != "boss")[0]
	witness.hp = 1
	witness.gauge = 3
	witness.action = "windup_special"
	witness.action_remaining = 0.4
	var witness_id: int = witness.get_instance_id()
	var witness_position: Vector2 = witness.position
	var from_biome: int = game.biome_at(game.player.position)
	var explored_before: int = game.explored_cells.size()
	action("move_right", true)
	action("jump", true)
	await frames(6)
	var bullet = game.spawn_bullet(game.player, Vector2.RIGHT)
	var bullet_id: int = bullet.get_instance_id()
	# Keep both warning and irradiation alive during actual boundary traversal.
	var flyer = get_nodes_in_group("enemies").filter(func(actor): return actor.kind == "flyer")[0]
	flyer.position = Vector2(boundary + 180, floor_y - T.FLYER_ALTITUDE)
	flyer.flight_center_y = flyer.position.y
	flyer.patrol = Vector2(boundary + 64, boundary + 352)
	flyer.hp = 1
	flyer.gauge = 3
	flyer.shot_clock = 100
	flyer.set_physics_process(true)
	var flyer_id: int = flyer.get_instance_id()
	var flyer_phase: float = flyer.flight_clock
	var flyer_position: Vector2 = flyer.position
	var laser_sources := get_nodes_in_group("enemies").filter(func(actor): return actor.kind == "laser")
	var source = laser_sources[0]
	source.position = Vector2(boundary + 300, floor_y - T.ENEMY_SIZE.y / 2)
	var warning = game.spawn_laser(source)
	var active = game.spawn_laser(source)
	# Aim away from the traversal player to observe persistence without changing HP/gauge.
	for beam in [warning, active]:
		beam.build_curve(Vector2(boundary + 328, floor_y - 26), Vector2(boundary + 560, floor_y - 180), 1)
		beam.clip_path()
	active.fire()
	var warning_id: int = warning.get_instance_id()
	var active_id: int = active.get_instance_id()
	var fixed_curve: PackedVector2Array = warning.curve.duplicate()
	var bomb = game.spawn_bomb_warning(source)
	bomb.target = Vector2(boundary + 600, floor_y)
	bomb.fire()
	var bomb_id: int = bomb.get_instance_id()
	var bomb_position: Vector2 = bomb.position
	game.show_damage(game.player.position - Vector2(0, 60), 1)
	var sequence: int = game.effects.damage_sequence
	var previous_player: Vector2 = game.player.position
	var previous_camera: Vector2 = game.camera.position
	var max_player_step := 0.0
	var max_camera_step := 0.0
	for index in range(12):
		await frames()
		max_player_step = maxf(max_player_step, game.player.position.distance_to(previous_player))
		max_camera_step = maxf(max_camera_step, game.camera.position.distance_to(previous_camera))
		previous_player = game.player.position
		previous_camera = game.camera.position
	action("move_right", false)
	action("jump", false)
	var context := "Boundary %.0f" % boundary
	check(game.player.position.x > boundary and game.biome_at(game.player.position) != from_biome, context + ": walk/jump crosses the region without interaction")
	check(game.world.get_instance_id() == world_id and game.player.get_instance_id() == player_id, context + ": world and player are never replaced")
	check(game.projectiles.get_instance_id() == projectile_container_id and terrain.collision_root.get_instance_id() == collision_id and terrain.collision_root.get_child_count() == shapes, context + ": collision and projectile containers stay loaded")
	check(is_instance_valid(bullet) and bullet.get_instance_id() == bullet_id and bullet.life < T.BULLET_LIFETIME and bullet.position.x > boundary, context + ": an actual projectile keeps flying across the boundary")
	check(witness.get_instance_id() == witness_id and witness.position == witness_position and witness.hp == 1 and witness.gauge == 3, context + ": existing enemy identity, health and gauge persist")
	check(witness.action == "windup_special" and is_equal_approx(witness.action_remaining, 0.4), context + ": crossing does not reset enemy windups")
	check(flyer.get_instance_id() == flyer_id and flyer.hp == 1 and flyer.gauge == 3 and flyer.flight_clock > flyer_phase and flyer.position != flyer_position, context + ": live flyer preserves HP, gauge and flight phase while moving")
	check(is_instance_valid(warning) and warning.get_instance_id() == warning_id and warning.phase == "warning" and warning.elapsed > 0 and warning.curve == fixed_curve, context + ": laser warning persists with fixed curve")
	check(is_instance_valid(active) and active.get_instance_id() == active_id and active.phase == "beam" and active.remaining < T.LASER_DURATION, context + ": irradiation persists and advances without reset")
	check(terrain.destroyed_cells == damaged and damaged.keys().all(func(cell): return not terrain.occupied.has(cell)), context + ": destroyed terrain remains destroyed")
	check(terrain.walls.has(wall_id) and terrain.walls[wall_id].cells == wall_cells and terrain.walls[wall_id].remaining < wall_remaining, context + ": wall and remaining lifetime persist")
	check(is_instance_valid(bomb) and bomb.get_instance_id() == bomb_id and bomb.phase == "flight" and bomb.position != bomb_position, context + ": bomb keeps flying without reinitialization")
	check(game.effects.damage_sequence == sequence and not game.effects.damage_numbers.is_empty(), context + ": crossing does not clear damage effects")
	check(game.player.hp == 88 and game.player.gauge == 5 and game.score == 200, context + ": player state and score persist")
	check(max_player_step < 24 and max_camera_step < 24, context + ": movement and camera never teleport")
	check(game.explored_cells.size() >= explored_before and game.ui.minimap.get_explored_cells().size() == game.explored_cells.size(), context + ": continuous terrain exploration matches the minimap")
	var before_e: Vector2 = game.player.position
	raw_e()
	await frames()
	check(game.player.position.distance_to(before_e) < 24 and game.world.get_instance_id() == world_id, context + ": E cannot warp the player or replace terrain")
	measurements[str(int(boundary))] = {"max_player_step": max_player_step, "max_camera_step": max_camera_step}

func warnings_and_map() -> void:
	game.start_run(37)
	silence_enemies()
	await frames(3)
	check(game.discovered_bosses.is_empty() and game.ui.minimap.get_visible_bosses().is_empty(), "The map initially hides all undiscovered guardians")
	var enemy = get_nodes_in_group("enemies").filter(func(actor): return actor.kind != "boss")[0]
	enemy.position = game.player.position + Vector2(400, 0)
	enemy.kind = "turret"
	enemy.patrol = Vector2(enemy.position.x, enemy.position.x)
	enemy.gauge = 0
	enemy.shot_clock = 0
	enemy.was_visible = false
	enemy.wake_delay = T.ENEMY_WAKE_DELAY
	enemy.set_physics_process(true)
	await frames(60)
	check(game.projectiles.get_child_count() == 0, "A newly visible enemy waits before attacking in the seamless world")
	await frames(10)
	check(enemy.action == "windup_shot" and game.projectiles.get_child_count() == 0, "An enemy visibly warns after waking up")
	await frames(30)
	check(game.projectiles.get_child_count() > 0, "The warning eventually launches an actual shot")
	silence_enemies()
	for bullet in game.projectiles.get_children():
		bullet.free()
	var explored: int = game.explored_cells.size()
	for landmark: Dictionary in game.stage.landmarks:
		game.player.position = landmark.position
		game.player.velocity = Vector2.ZERO
		game._update_camera(0.0, true)
		game._update_exploration()
		check(game.discovered_bosses.has(landmark.id), "A visible guardian is remembered on the terrain map")
		check(game.explored_cells.size() >= explored, "Previously explored terrain remains visible")
		explored = game.explored_cells.size()
	check(game.ui.minimap.get_visible_bosses().size() == 3, "All three discovered guardians appear on the minimap")
	game.start_run(37)
	await frames(3)
	var at: Vector2 = game.player.position
	var camera_at: Vector2 = game.camera.position
	var elapsed: float = game.elapsed
	game.show_menu("paused")
	raw_e()
	action("move_right", true)
	await frames(20)
	action("move_right", false)
	check(game.player.position == at and game.camera.position == camera_at and game.elapsed == elapsed, "Pause freezes the single world, camera and clock")
	game.open_key_settings()
	raw_e()
	await frames(5)
	check(game.player.position == at and game.elapsed == elapsed, "Settings consumes input without moving or rebuilding the world")
	game.close_key_settings()
	game.resume_run()
	check(game.discovered_bosses.is_empty() and game.ui.minimap.get_visible_bosses().is_empty(), "Restart clears guardian discovery")

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://builds/qa/seamless")
	game = Main.new()
	game.controls_path = "res://builds/qa/seamless/continuity_controls.cfg"
	root.add_child(game)
	game.key_bindings.reset_defaults()
	for boundary in [4096.0, 8192.0]:
		await cross_region(boundary)
	await warnings_and_map()
	game.queue_free()
	await frames(2)
	var report := {"checks": checks, "failures": failures, "measurements": measurements}
	var file := FileAccess.open("res://builds/qa/seamless/continuity_results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("SEAMLESS CONTINUITY: ", checks, " checks, ", failures.size(), " failures; ", measurements)
	quit(0 if failures.is_empty() else 1)
