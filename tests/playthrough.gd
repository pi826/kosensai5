extends SceneTree
## Real walking and held jump inputs across a persistent continuous world; no warps.
const T := preload("res://scripts/tuning.gd")
const Main := preload("res://scripts/main.gd")
var game: Node2D
var reports: Array = []
var failures: Array[String] = []
var checks := 0
var frames := 0
var jumps := 0
var largest_camera_step := 0.0
var largest_player_step := 0.0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> bool:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: ", message)
	return condition

func frame() -> void:
	# This fixture isolates navigation; combat and damage have separate regressions.
	for enemy in get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)
	game.player.invulnerability = 10000
	var old_camera: Vector2 = game.camera.position
	var old_player: Vector2 = game.player.position
	await physics_frame
	await process_frame
	frames += 1
	largest_camera_step = maxf(largest_camera_step, old_camera.distance_to(game.camera.position))
	largest_player_step = maxf(largest_player_step, old_player.distance_to(game.player.position))
	for enemy in get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)

func action_event(action_name: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action_name
	event.pressed = pressed
	Input.parse_input_event(event)

func release_inputs() -> void:
	for action_name in ["move_right", "move_left", "jump", "shoot", "switch_color", "special"]:
		Input.action_release(action_name)

func stop() -> void:
	Input.action_release("move_left")
	Input.action_release("move_right")
	for tick in range(4):
		await frame()

func walk_to(target_x: float, tolerance: float = 10) -> bool:
	var jump_timer := 0
	var limit := int(absf(target_x - game.player.position.x) / T.MOVE_SPEED * 60) + 360
	for tick in range(limit):
		var distance: float = target_x - game.player.position.x
		if absf(distance) <= tolerance:
			await stop()
			action_event("jump", false)
			return true
		Input.action_release("move_left")
		Input.action_release("move_right")
		Input.action_press("move_right" if distance > 0 else "move_left")
		if jump_timer > 0:
			jump_timer -= 1
			if jump_timer == 0:
				action_event("jump", false)
		if game.player.is_on_floor() and game.player.is_on_wall() and jump_timer == 0:
			action_event("jump", true)
			jump_timer = 40
			jumps += 1
		await frame()
	await stop()
	action_event("jump", false)
	return check(false, "Walking timed out: target %.1f, player %s" % [target_x, game.player.position])

func wait_for_floor(limit: int = 180) -> bool:
	for tick in range(limit):
		if game.player.is_on_floor():
			return true
		await frame()
	return check(false, "No landing at %s" % game.player.position)

func jump_one_level(target: Vector2) -> bool:
	if not await walk_to(target.x) or not await wait_for_floor():
		return false
	var before_y: float = game.player.position.y
	action_event("jump", true)
	jumps += 1
	var left_floor := false
	var landed := false
	for tick in range(90):
		await frame()
		if not game.player.is_on_floor():
			left_floor = true
		elif left_floor:
			landed = true
			break
	action_event("jump", false)
	await frame()
	if not check(left_floor and landed, "Normal jump leaves its supporting surface and lands"):
		return false
	return check(game.player.position.y <= before_y - 100 and absf(game.player.position.y - target.y) < 2, "One normal jump reaches shelf %s, actual %s" % [target, game.player.position])

func follow_ground(points: Array) -> bool:
	for point: Vector2 in points:
		if not await walk_to(point.x):
			return false
	return await wait_for_floor()

func check_map() -> void:
	var shown: Array = game.ui.minimap.get_explored_cells()
	check(shown.size() == game.explored_cells.size(), "Minimap draws exactly the explored cells")
	var unvisited_found := false
	for cell in shown:
		if not game.explored_cells.has(cell):
			unvisited_found = true
	check(not unvisited_found, "Minimap never reveals an unexplored cell")
	check(game.ui.minimap.get_visible_bosses().size() == game.discovered_bosses.size(), "Minimap reveals only discovered guardians")

func run_seed(stage_seed: int, damaged: bool = false) -> bool:
	release_inputs()
	game.start_run(stage_seed)
	check(game.terrain.breakables.size() >= 4, "Traversal includes generated breakable obstacles")
	var blocks_before: Dictionary = game.terrain.breakables.duplicate(true)
	if damaged:
		# Dense overlapping blasts excavate the surface and any blocks in their radius.
		for x in range(80, int(T.WORLD_SIZE.x) - 64, 64):
			game.terrain.explode(Vector2(x, T.GROUND_Y + 32), 160)
		check(not game.terrain.destroyed_cells.is_empty(), "Damaged traversal contains extensive surface excavation")
	largest_camera_step = 0
	largest_player_step = 0
	var initial_frames := frames
	var initial_jumps := jumps
	var initial_failures := failures.size()
	var world_id: int = game.world.get_instance_id()
	var actor_ids: Array[int] = []
	for actor in get_nodes_in_group("enemies"):
		if actor.get_parent() == game.world:
			actor_ids.append(actor.get_instance_id())
	await frame()
	check(game.discovered_bosses.is_empty(), "No distant guardian is revealed at the starting point")
	check_map()
	var reached := {}
	for route: Dictionary in game.stage.routes:
		var id := int(route.boss_id)
		var points: Array = route.points
		if id == 1:
			for index in range(1, points.size()):
				if not await jump_one_level(points[index]):
					return false
		else:
			if not await follow_ground(points):
				return false
		var destination: Vector2 = points[-1]
		if not check(game.player.position.distance_to(destination) < 16, "Guardian %d is reached by walking and single jumps" % id):
			return false
		reached[id] = true
		check(game.discovered_bosses.has(id), "Reaching guardian %d discovers its map marker" % id)
		check_map()
		if id == 1:
			# Step off the highest shelf, then fall naturally onto the continuous floor.
			if not await walk_to(6784) or not await wait_for_floor():
				return false
			var landing_y: float = game.stage.start_position.y + (T.SURFACE_DEPTH if damaged else 0)
			check(absf(game.player.position.y - landing_y) < 2, "A fall from the upper guardian safely reaches the actual remaining ground")
			if not await walk_to(game.stage.start_position.x):
				return false
		else:
			var returning: Array = points.duplicate()
			returning.reverse()
			if not await follow_ground(returning):
				return false
		if not await wait_for_floor():
			return false
		check(game.player.position.distance_to(game.stage.start_position) < 16, "Guardian %d route allows a natural return to the starting point" % id)
		check(game.world.get_instance_id() == world_id, "The same world instance persists throughout the journey")
	for actor_id: int in actor_ids:
		check(is_instance_id_valid(actor_id), "An original enemy instance survives region crossings")
	check(reached.size() == 3 and game.discovered_bosses.size() == 3, "All three guardians are reached and discovered")
	check(game.player.hp == T.PLAYER_HP, "Exploration and ordinary falls do not require taking damage")
	check(game.defeated_bosses.is_empty() and game.defeated_enemies.is_empty(), "Navigation never counts as defeating an enemy")
	if not damaged:
		check(game.terrain.breakables == blocks_before, "Traversal succeeds with breakable obstacles intact and no shooting")
	check(largest_player_step < 25, "Player position changes only through continuous physics, max step %.2f" % largest_player_step)
	check(largest_camera_step < 25, "Camera follows continuously in both axes, max step %.2f" % largest_camera_step)
	var result := {"seed": stage_seed, "damaged_terrain": damaged, "passed": failures.size() == initial_failures,
		"physics_frames": frames - initial_frames, "simulated_seconds": game.elapsed,
		"normal_jumps": jumps - initial_jumps, "explored_cells": game.explored_cells.size(),
		"guardians_reached_and_returned": reached.size(), "world_instance_preserved": game.world.get_instance_id() == world_id,
		"largest_camera_step": largest_camera_step, "largest_player_step": largest_player_step,
		"combat_disabled": true, "human_5_to_10_minute_combat_pacing_verified": false}
	reports.append(result)
	print("SEAMLESS TRAVERSAL: ", JSON.stringify(result))
	return failures.size() == initial_failures

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://builds/qa/seamless")
	game = Main.new()
	game.controls_path = "res://builds/qa/seamless/traversal_controls.cfg"
	root.add_child(game)
	game.key_bindings.reset_defaults()
	await frame()
	for stage_seed in [1, 37, 2026]:
		if not await run_seed(stage_seed):
			printerr("Traversal stopped early for seed ", stage_seed)
			break
	if failures.is_empty():
		await run_seed(37, true)
	release_inputs()
	var file := FileAccess.open("res://builds/qa/seamless/traversal_results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "runs": reports}, "\t"))
	game.queue_free()
	await physics_frame
	print("Seamless traversal checks: %d, failures: %d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
