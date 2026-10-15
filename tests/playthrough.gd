extends SceneTree
## Exercises real walking, held jumps and passage inputs; no player teleports are used.
const T := preload("res://scripts/tuning.gd")
const Main := preload("res://scripts/main.gd")

var game: Node2D
var reports: Array = []
var failures: Array[String] = []
var checks := 0
var frames := 0
var jumps := 0
var passed_links: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> bool:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: ", message)
	return condition

func frame() -> void:
	# Combat difficulty is covered separately. This fixture isolates actual traversal physics.
	for enemy in get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)
	if is_instance_valid(game) and is_instance_valid(game.player):
		game.player.invulnerability = 10000.0
	await physics_frame
	await process_frame
	frames += 1
	for enemy in get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)

func action_event(action_name: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action_name
	event.pressed = pressed
	Input.parse_input_event(event)

func release_inputs() -> void:
	for action_name in ["move_right", "move_left", "jump", "shoot", "switch_color", "special", "interact"]:
		Input.action_release(action_name)

func local_player() -> Vector2:
	return game.player.position - Vector2(game.current_room().origin)

func stop() -> void:
	Input.action_release("move_left")
	Input.action_release("move_right")
	for tick in range(4):
		await frame()

func walk_to(target_x: float, tolerance: float = 5.0) -> bool:
	var expected_camera: Vector2 = game.camera.position
	for tick in range(420):
		var distance := target_x - local_player().x
		if absf(distance) <= tolerance:
			await stop()
			return check(game.camera.position.is_equal_approx(expected_camera), "Camera stays fixed during a walk inside room %d" % game.current_room_id)
		Input.action_release("move_left")
		Input.action_release("move_right")
		Input.action_press("move_right" if distance > 0 else "move_left")
		await frame()
	await stop()
	return check(false, "Walk timed out in room %d: wanted x %.1f, got %s" % [game.current_room_id, target_x, local_player()])

func wait_for_floor(max_frames: int = 120) -> bool:
	for tick in range(max_frames):
		if game.player.is_on_floor():
			return true
		await frame()
	return check(false, "No landing in room %d at %s" % [game.current_room_id, local_player()])

func jump_one_level() -> bool:
	if not await wait_for_floor():
		return false
	var before_y: float = local_player().y
	var expected_camera: Vector2 = game.camera.position
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
	if not check(left_floor and landed, "Held jump leaves the floor and lands in room %d" % game.current_room_id):
		return false
	if not check(local_player().y <= before_y - 100, "A normal jump reaches the next 128 px shelf in room %d: %.1f to %.1f" % [game.current_room_id, before_y, local_player().y]):
		return false
	return check(game.camera.position.is_equal_approx(expected_camera), "Camera stays fixed during vertical movement in room %d" % game.current_room_id)

func approach_door(door: Dictionary) -> bool:
	if not await walk_to(float(door.position.x)):
		return false
	if door.direction == "north":
		for level in range(4):
			if local_player().y <= 258 and game.player.is_on_floor():
				break
			if not await jump_one_level():
				return false
	else:
		# All ground passages are outside the ladder; walking there also drops from it.
		if not await wait_for_floor():
			return false
	var nearby: Dictionary = game.nearby_door()
	return check(not nearby.is_empty() and int(nearby.target) == int(door.target), "Room %d passage %s is reachable by movement and normal jumps" % [game.current_room_id, door.direction])

func key_event(key: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)

func travel_to(target_id: int) -> bool:
	var previous := int(game.current_room_id)
	var door: Dictionary = {}
	for item: Dictionary in game.current_room().doors:
		if int(item.target) == target_id:
			door = item
			break
	if not check(not door.is_empty(), "Rooms %d and %d have an explicit passage" % [previous, target_id]):
		return false
	if not await approach_door(door):
		return false
	for tick in range(120):
		if game.travel_cooldown <= 0:
			break
		await frame()
	var interact_key: int = game.key_bindings.get_key("interact", 0)
	key_event(interact_key, true)
	await frame()
	key_event(interact_key, false)
	for tick in range(3):
		await frame()
	if not check(game.current_room_id == target_id, "Configured passage input moves from room %d to room %d" % [previous, target_id]):
		return false
	passed_links["%d:%d" % [previous, target_id]] = true
	var room: Dictionary = game.current_room()
	check(game.camera.position.is_equal_approx(room.rect.get_center()), "Camera moves to the destination room centre")
	check(game.visited_rooms.has(target_id), "A traversed room is marked visited")
	var visible: Array = game.ui.minimap.get_visible_rooms()
	check(visible.size() == game.visited_rooms.size(), "Minimap contains exactly the visited rooms")
	for visible_room: Dictionary in visible:
		check(game.visited_rooms.has(int(visible_room.id)), "Minimap never reveals an unvisited room")
	return true

func find_path(start: int, target: int) -> Array:
	var queue: Array = [start]
	var previous: Dictionary = {start: -1}
	while not queue.is_empty():
		var room_id: int = queue.pop_front()
		if room_id == target:
			var path: Array = []
			while room_id != start:
				path.push_front(room_id)
				room_id = int(previous[room_id])
			return path
		for door: Dictionary in game.stage.rooms[room_id].doors:
			var next_id := int(door.target)
			if not previous.has(next_id):
				previous[next_id] = room_id
				queue.append(next_id)
	return []

func follow_path(target: int) -> bool:
	var path := find_path(game.current_room_id, target)
	if target != game.current_room_id and not check(not path.is_empty(), "A graph path exists to room %d" % target):
		return false
	for room_id: int in path:
		if not await travel_to(room_id):
			return false
	return true

func fall_recovery() -> bool:
	var north_door: Dictionary = {}
	for door: Dictionary in game.current_room().doors:
		if door.direction == "north":
			north_door = door
			break
	if north_door.is_empty():
		return check(false, "The start room offers a northward climb for the fall test")
	if not await approach_door(north_door):
		return false
	var top_y: float = local_player().y
	if not await walk_to(1120):
		return false
	if not await wait_for_floor():
		return false
	check(top_y < 260, "The fall test starts at the top of the three-shelf climb")
	check(absf(local_player().y - (T.ROOM_FLOOR_Y - T.PLAYER_SIZE.y / 2)) <= 1, "Falling off upper shelves returns to the safe ground floor")
	check(game.player.hp == T.PLAYER_HP, "An ordinary room fall does not cause damage")
	return check(game.current_room_id == game.stage.start_room, "Falling inside a room does not trigger an unintended passage")

func run_seed(stage_seed: int) -> bool:
	release_inputs()
	game.start_run(stage_seed)
	passed_links.clear()
	var initial_frames := frames
	var initial_jumps := jumps
	var initial_failures := failures.size()
	await frame()
	var start_room := int(game.stage.start_room)
	if not await fall_recovery():
		return false
	var boss_rooms: Array = []
	for room: Dictionary in game.stage.rooms:
		if int(room.get("boss_id", -1)) >= 0:
			boss_rooms.append(int(room.id))
	check(boss_rooms.size() == 3, "The map contains three distinct guardian destinations")
	for boss_room: int in boss_rooms:
		if not await follow_path(boss_room):
			return false
		check(int(game.current_room().boss_id) >= 0, "The selected guardian room is reachable")
		if not await follow_path(start_room):
			return false
		check(game.current_room_id == start_room, "The guardian route allows returning to the starting hub")
	# Optional loops are tested too, rather than only the BFS tree used above.
	for room: Dictionary in game.stage.rooms:
		for door: Dictionary in room.doors:
			var edge := "%d:%d" % [int(room.id), int(door.target)]
			if passed_links.has(edge):
				continue
			if not await follow_path(int(room.id)) or not await travel_to(int(door.target)):
				return false
	if not await follow_path(start_room):
		return false
	check(game.visited_rooms.size() == game.stage.rooms.size(), "All generated rooms are visited through actual passage inputs")
	check(game.player.hp == T.PLAYER_HP, "Exploration geometry leaves the player alive without required damage")
	check(game.defeated_bosses.is_empty(), "Reaching or leaving a guardian room never counts as defeating it")
	var result := {"seed": stage_seed, "passed": failures.size() == initial_failures,
		"physics_frames": frames - initial_frames, "simulated_seconds": game.elapsed,
		"normal_jumps": jumps - initial_jumps, "visited_rooms": game.visited_rooms.size(),
		"total_rooms": game.stage.rooms.size(), "directed_passages_walked": passed_links.size(),
		"guardian_rooms_reached_and_returned": boss_rooms.size(), "combat_disabled": true,
		"human_5_to_10_minute_combat_pacing_verified": false}
	reports.append(result)
	print("ROOM TRAVERSAL: ", JSON.stringify(result))
	return failures.size() == initial_failures

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://builds/qa/phase2")
	game = Main.new()
	game.controls_path = "res://builds/qa/phase2/traversal_controls.cfg"
	root.add_child(game)
	game.key_bindings.reset_defaults()
	await frame()
	for stage_seed in [1, 37, 2026]:
		if not await run_seed(stage_seed):
			printerr("Traversal stopped early for seed ", stage_seed)
			break
	release_inputs()
	var file := FileAccess.open("res://builds/qa/phase2/traversal_results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "runs": reports}, "\t"))
	game.queue_free()
	await physics_frame
	print("Room traversal checks: %d, failures: %d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
