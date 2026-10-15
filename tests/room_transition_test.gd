extends SceneTree
## Passage boundaries, inactive-room state and control remapping on the real scene.
const Main := preload("res://scripts/main.gd")
const T := preload("res://scripts/tuning.gd")

var game: Node2D
var checks := 0
var failures: Array[String] = []
var report: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> bool:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: ", message)
	return condition

func frame() -> void:
	if is_instance_valid(game.player):
		game.player.invulnerability = 10000
	await physics_frame
	await process_frame

func frames(count: int) -> void:
	for tick in range(count):
		await frame()

func key_event(key: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)

func tap_key(key: int) -> void:
	key_event(key, true)
	await frame()
	key_event(key, false)
	await frames(2)

func release_inputs() -> void:
	for action_name in ["move_left", "move_right", "jump", "shoot", "special", "interact", "pause_game"]:
		Input.action_release(action_name)

func passage_to(target: int) -> Dictionary:
	for door: Dictionary in game.current_room().doors:
		if int(door.target) == target:
			return door
	return {}

func place_at_door(target: int) -> bool:
	var door := passage_to(target)
	if not check(not door.is_empty(), "Fixture has a linked passage to room %d" % target):
		return false
	game.player.position = Vector2(game.current_room().origin) + Vector2(door.position) + Vector2(0, 26)
	game.player.velocity = Vector2.ZERO
	return true

func travel(target: int, key: int = KEY_E) -> bool:
	if not place_at_door(target):
		return false
	for tick in range(90):
		if game.travel_cooldown <= 0:
			break
		await frame()
	await tap_key(key)
	return check(game.current_room_id == target, "Raw %s enters room %d" % [OS.get_keycode_string(key), target])

func room_enemy(room_id: int):
	for enemy in get_nodes_in_group("enemies"):
		if enemy.get_parent() == game.world and int(enemy.room_id) == room_id:
			return enemy
	return null

func test_travel_and_enemy_state() -> void:
	game.start_run(37)
	game.player.set_physics_process(false)
	var start_room := int(game.current_room_id)
	var first_target := int(game.current_room().doors[0].target)
	var enemy = room_enemy(first_target)
	if not check(is_instance_valid(enemy), "The first region contains a real enemy fixture"):
		return
	enemy.hp = 7
	enemy.gauge = 3
	enemy.action = "windup_special"
	enemy.action_remaining = 0.4
	enemy.shot_clock = 0.0
	enemy.switch_clock = 100.0
	enemy.velocity = Vector2(12, -40)
	var dormant_position: Vector2 = enemy.position
	var visible: Array = game.ui.minimap.get_visible_rooms()
	check(visible.size() == 1 and int(visible[0].id) == start_room, "Only the starting room appears on a fresh minimap")
	for room: Dictionary in visible:
		check(int(room.get("boss_id", -1)) < 0, "Unvisited guardian destinations are hidden")
	await tap_key(KEY_E)
	check(game.current_room_id == start_room, "Interaction far from a passage does not travel")
	await frames(90)
	check(enemy.position.is_equal_approx(dormant_position), "Inactive enemies do not fall or patrol")
	check(enemy.action == "windup_special" and is_equal_approx(enemy.action_remaining, 0.4), "Inactive enemy windups do not advance")
	check(enemy.gauge == 3 and enemy.hp == 7, "Inactive enemy health and gauge remain unchanged")
	check(is_zero_approx(enemy.shot_clock) and is_equal_approx(enemy.switch_clock, 100.0), "Inactive attack and switch timers do not advance")
	check(game.projectiles.get_child_count() == 0, "Inactive enemies cannot shoot into another room")
	if not place_at_door(first_target):
		return
	var bullet = game.spawn_bullet(game.player, Vector2.RIGHT)
	bullet.set_physics_process(false)
	game.show_damage(game.player.position, 4)
	game.player.jump_buffer = 0.1
	game.player.coyote = 0.1
	game.player.pending_special = true
	game.player.jump_cut_requested = true
	check(game.projectiles.get_child_count() == 1 and game.effects.damage_numbers.size() == 1, "The transition fixture contains a projectile and damage number")
	key_event(KEY_E, true)
	# A second input in the same frame must not queue a second transition.
	key_event(KEY_E, true)
	var entered_tick := -1
	var warning_tick := -1
	var shot_tick := -1
	var checked_entry := false
	for tick in range(125):
		await frame()
		if tick == 0:
			key_event(KEY_E, false)
		if game.current_room_id != first_target:
			continue
		if entered_tick < 0:
			entered_tick = tick
		if not checked_entry:
			checked_entry = true
			check(game.projectiles.get_child_count() == 0, "Room travel clears old projectiles")
			check(game.effects.damage_numbers.is_empty(), "Room travel clears old damage numbers")
			check(game.player.jump_buffer == 0 and game.player.coyote == 0, "Room travel clears buffered jump and coyote state")
			check(not game.player.pending_special and not game.player.jump_cut_requested, "Room travel clears queued special and jump-cut inputs")
			check(not game.travel_pending and game.travel_cooldown > 0, "One transition completes with a cooldown")
			place_at_door(start_room)
			check(not game.try_travel(), "An immediate reciprocal transition is blocked by cooldown")
			key_event(KEY_E, true)
			key_event(KEY_E, false)
		if enemy.action == "windup_shot" and warning_tick < 0:
			warning_tick = tick - entered_tick
		if game.projectiles.get_child_count() > 0:
			shot_tick = tick - entered_tick
			break
	check(game.current_room_id == first_target, "Repeated passage inputs do not bounce the player back")
	check(warning_tick >= ceili(T.ENEMY_WAKE_DELAY * 60) - 2, "An activated enemy waits for its wake delay before showing its shot warning")
	check(shot_tick >= ceili((T.ENEMY_WAKE_DELAY + T.SHOT_WARNING) * 60) - 2, "An activated enemy cannot fire before wake delay plus warning")
	check(shot_tick > warning_tick and shot_tick < 125, "An activated enemy eventually completes its visible shot warning")
	report["enemy_warning_after_entry_frames"] = warning_tick
	report["enemy_first_shot_after_entry_frames"] = shot_tick
	enemy.hp = 5
	enemy.gauge = 4
	if not await travel(start_room):
		return
	await frames(60)
	check(enemy.hp == 5 and enemy.gauge == 4, "A living enemy retains partial health and absorbed gauge while its room is inactive")
	if not await travel(first_target):
		return
	check(enemy.hp == 5 and enemy.gauge == 4, "Re-entering a room preserves a living enemy's health and gauge")
	check(game.ui.minimap.get_visible_rooms().size() == 2, "Entering a new region reveals that room and no unexplored neighbours")
	place_at_door(start_room)
	await frames(30)
	game.show_menu("paused")
	await tap_key(KEY_E)
	check(game.current_room_id == first_target and game.state == "paused", "Interaction while paused cannot travel")
	game.open_key_settings()
	await tap_key(KEY_E)
	check(game.current_room_id == first_target and game.state == "settings", "Interaction while key settings are open cannot travel")
	game.close_key_settings()
	game.resume_run()
	check(game.key_bindings.try_bind("interact", 0, KEY_F).is_empty(), "Interaction can be rebound to F")
	game.ui.refresh_bindings()
	check(game.ui.controls_label.text.contains("F 部屋移動"), "The footer displays the changed interaction key")
	check(game.key_bindings.get_binding_text("interact") == "F", "Passage captions read the changed key binding")
	check(game.ui.hint_label.text.contains(" F で部屋移動"), "The exploration hint displays the changed key")
	await tap_key(KEY_E)
	check(game.current_room_id == first_target, "The old E binding no longer moves through a passage")
	await travel(start_room, KEY_F)
	# Discover one guardian through real passage input; other guardian rooms remain hidden.
	for room_id in range(1, 5):
		if not await travel(room_id, KEY_F):
			return
	var discovered_guardians: Array = game.ui.minimap.get_visible_rooms().filter(func(room: Dictionary) -> bool: return int(room.get("boss_id", -1)) >= 0)
	check(discovered_guardians.size() == 1 and int(discovered_guardians[0].boss_id) == 0, "Only the guardian room that was entered is discovered")
	check(game.defeated_bosses.is_empty(), "Discovering a guardian never counts as defeating it")
	game.key_bindings.reset_defaults()
	game.ui.refresh_bindings()

func test_room_boundaries() -> void:
	release_inputs()
	game.start_run(37)
	game.player.set_physics_process(true)
	var origin: Vector2 = game.current_room().origin
	for local_y in [190.0, 400.0, 618.0]:
		game.player.position = origin + Vector2(64, local_y)
		check(game.player.test_move(game.player.global_transform, Vector2(-96, 0)), "The west wall blocks movement at y %.0f" % local_y)
		game.player.position = origin + Vector2(1216, local_y)
		check(game.player.test_move(game.player.global_transform, Vector2(96, 0)), "The east wall blocks movement at y %.0f" % local_y)
	game.player.position = origin + Vector2(1120, 618)
	check(game.player.test_move(game.player.global_transform, Vector2(0, 96)), "The floor blocks falling out of the room")
	game.player.position = origin + Vector2(640, 200)
	check(game.player.test_move(game.player.global_transform, Vector2(0, -96)), "The ceiling blocks leaving through the roof")
	for action_name in ["move_left", "move_right"]:
		game.player.position = origin + Vector2(96 if action_name == "move_left" else 1184, 618)
		game.player.velocity = Vector2.ZERO
		Input.action_press(action_name)
		await frames(60)
		var jump := InputEventAction.new()
		jump.action = "jump"
		jump.pressed = true
		Input.parse_input_event(jump)
		var stayed_inside := true
		for tick in range(60):
			await frame()
			var local: Vector2 = game.player.position - origin
			stayed_inside = stayed_inside and local.x >= 47 - 0.5 and local.x <= 1233 + 0.5 and local.y >= 182 - 0.5 and local.y <= 618 + 0.5
		check(stayed_inside, "Walking and jumping against %s cannot leave the room" % action_name)
		release_inputs()
	game.player.position = origin + Vector2(640, 234)
	game.player.velocity = Vector2.ZERO
	await frames(5)
	var jump := InputEventAction.new()
	jump.action = "jump"
	jump.pressed = true
	Input.parse_input_event(jump)
	var minimum_y := 234.0
	for tick in range(60):
		await frame()
		minimum_y = minf(minimum_y, game.player.position.y - origin.y)
	check(minimum_y >= 181.5 and minimum_y < 200, "A jump from the highest shelf reaches and stops at the solid ceiling")
	release_inputs()
	game.player.position = origin + Vector2(1120, 300)
	game.player.velocity = Vector2.ZERO
	await frames(90)
	check(absf(game.player.position.y - origin.y - 618) <= 0.5, "A free fall stops safely on the room floor")
	check(game.current_room_id == game.stage.start_room, "Wall and ceiling contact never changes the active room")
	report["highest_jump_centre_y"] = minimum_y

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://builds/qa/phase2")
	game = Main.new()
	game.controls_path = "res://builds/qa/phase2/transition_controls.cfg"
	root.add_child(game)
	game.key_bindings.reset_defaults()
	await frame()
	await test_travel_and_enemy_state()
	await test_room_boundaries()
	release_inputs()
	report["seed"] = 37
	report["checks"] = checks
	report["failures"] = failures
	var file := FileAccess.open("res://builds/qa/phase2/transition_results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	game.queue_free()
	await physics_frame
	print("Room transition checks: %d, failures: %d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
