extends SceneTree
const Main := preload("res://scripts/main.gd")
const Terrain := preload("res://scripts/world_terrain.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Laser := preload("res://scripts/laser_beam.gd")
const Bomb := preload("res://scripts/bomb.gd")
const Generator := preload("res://scripts/stage_generator.gd")
const T := preload("res://scripts/tuning.gd")
const FLOOR_Y := 2304.0
var game: Node2D
var checks := 0
var failures: Array[String] = []
var performance: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL: ", message)

func frames(count: int = 1) -> void:
	for index in range(count):
		await physics_frame
		await process_frame

func action(name: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = name
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func fixture(blocks: bool = false, step: bool = false) -> void:
	for name in ["move_left", "move_right", "jump", "shoot"]:
		Input.action_release(name)
	game.start_run(37)
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	for child in game.world.get_children():
		if child != game.player and child != game.projectiles and child != game.effects:
			child.free()
	game.stage.solids = []
	for index in range(32):
		var top := FLOOR_Y - (64 if step and index == 7 else 0)
		game.stage.solids.append(Rect2(index * 384, top, 384, T.WORLD_SIZE.y - top))
	# Isolated destruction/combat fixture. Its explicit floors and exclusions do
	# not depend on any generated tower coordinates.
	game.stage.floors = game.stage.solids.duplicate()
	game.stage.towers = []
	game.stage.bridges = []
	game.stage.surface_exclusions = [Vector2(0,96),Vector2(384,1152),Vector2(5696,6592),Vector2(11136,11904),Vector2(12192,12288)]
	game.stage.solids.append(Rect2(0, 0, 32, T.WORLD_SIZE.y))
	game.stage.solids.append(Rect2(T.WORLD_SIZE.x - 32, 0, 32, T.WORLD_SIZE.y))
	game.stage.solids.append(Rect2(3008, FLOOR_Y - 128, 192, 16))
	game.stage.breakables = [Rect2(2496, FLOOR_Y - 64, 64, 64)] if blocks else []
	game.terrain = Terrain.new()
	game.terrain.stage = game.stage
	game.world.add_child(game.terrain)
	game.player.position = Vector2(2352, FLOOR_Y - T.PLAYER_SIZE.y / 2)
	game.player.velocity = Vector2.ZERO
	game.player.polarity = 0
	game.player.facing = 1
	game.camera.position = Vector2(2600, 2120)
	game.ui.minimap.update_map()
	await frames(3)

func spawn(kind: String, x: float = 2400) -> CharacterBody2D:
	var enemy := Enemy.new()
	enemy.game = game
	enemy.kind = kind
	enemy.spawn_id = "terrain_" + kind + str(x)
	enemy.position = Vector2(x, FLOOR_Y - T.ENEMY_SIZE.y / 2)
	enemy.patrol = Vector2(x, x)
	game.world.add_child(enemy)
	enemy.set_physics_process(false)
	return enemy

func ray(from: Vector2, to: Vector2, mask: int) -> Dictionary:
	return game.get_world_2d().direct_space_state.intersect_ray(PhysicsRayQueryParameters2D.create(from, to, mask))

func verify_surface() -> void:
	await fixture()
	var stage_before := Generator.signature(game.stage)
	var center := Vector2(2512, FLOOR_Y + 32)
	var neighbour := Vector2i(76, 72)
	var old_mask: int = game.terrain.tile_masks[neighbour]
	var removed: Array = game.terrain.explode(center, 60)
	check(not removed.is_empty(), "blast removes surface cells")
	check(removed.all(func(cell): return (Vector2(cell) * 32 + Vector2(16, 16)).distance_to(center) <= 60), "only cell centers inside radius are removed")
	check(removed.all(func(cell): return cell.y in [72, 73]), "only top two rows are destructible")
	check(game.terrain.tile_masks[neighbour] != old_mask, "eight-neighbour tile connectivity refreshes")
	check(removed.all(func(cell): return not game.terrain.occupied.has(cell) and not game.terrain.tile_masks.has(cell)), "destroyed cells disappear from occupancy and drawing")
	await frames(2)
	check(ray(Vector2(2512, 2290), Vector2(2512, 2355), 1).is_empty(), "physics ray passes through destroyed surface")
	check(not ray(Vector2(2512, 2290), Vector2(2512, 2390), 1).is_empty(), "deep floor still blocks rays")
	game.player.position = Vector2(2512, FLOOR_Y - T.PLAYER_SIZE.y / 2)
	game.player.set_physics_process(true)
	await frames(35)
	check(game.player.is_on_floor() and absf(game.player.position.y - (FLOOR_Y + 64 - T.PLAYER_SIZE.y / 2)) < 0.2, "player actually falls 64px into destroyed floor")
	var ground_enemy = spawn("turret", 2512)
	ground_enemy.set_physics_process(true)
	ground_enemy.shot_clock = 100
	await frames(35)
	check(absf(ground_enemy.position.y - (FLOOR_Y + 64 - T.ENEMY_SIZE.y / 2)) < 0.2, "unsupported ground enemy falls onto deep floor")
	var flyer = spawn("flyer", 2512)
	flyer.position.y = FLOOR_Y - T.FLYER_ALTITUDE
	flyer.flight_center_y = flyer.position.y
	flyer.patrol = Vector2(2480, 2560)
	flyer.shot_clock = 100
	flyer.set_physics_process(true)
	await frames(60)
	check(absf(flyer.position.y - flyer.flight_center_y) <= T.FLYER_BOB_AMPLITUDE + 0.1, "flyer stays aloft over damaged floor")
	for x in [16, 768, 6144, 11520, 12272]:
		var cell := Vector2i(floori(x / 32.0), 72)
		game.terrain.explode(Vector2(x, FLOOR_Y + 32), 128)
		check(game.terrain.occupied.has(cell), "protected floor survives blast x=%d" % x)
	game.terrain.explode(Vector2(3104, FLOOR_Y - 128), 120)
	await frames(2)
	check(not ray(Vector2(3104, FLOOR_Y - 150), Vector2(3104, FLOOR_Y - 100), 1).is_empty(), "thin optional shelf cannot be destroyed")
	game.terrain.explode(Vector2(16, 800), 120)
	await frames(2)
	check(not ray(Vector2(80, 800), Vector2(0, 800), 1).is_empty(), "outer wall cannot be destroyed")
	game.terrain.explode(Vector2(2512, FLOOR_Y + 96), 180)
	check(game.terrain.occupied.has(Vector2i(78, 74)), "repeated deeper blasts never excavate below 64px")
	check(Generator.signature(game.stage) == stage_before, "runtime damage never mutates generated stage data")

func verify_jump_and_walk() -> void:
	await fixture(false, true)
	for x in [2608, 2640, 2672]:
		game.terrain.explode(Vector2(x, FLOOR_Y + 32), 38)
	game.player.position = Vector2(2624, FLOOR_Y + 64 - T.PLAYER_SIZE.y / 2)
	game.player.set_physics_process(true)
	await frames(5)
	check(game.player.is_on_floor(), "worst-case hole has a solid bottom")
	action("jump", true)
	action("move_right", true)
	await frames(40)
	action("jump", false)
	action("move_right", false)
	await frames(12)
	check(game.player.position.x > 2710 and game.player.is_on_floor() and absf(game.player.position.y - (FLOOR_Y - 64 - T.PLAYER_SIZE.y / 2)) < 0.2, "real normal-jump input escapes 64px hole beside 64px higher floor")
	await fixture()
	game.player.position.x = 1560
	game.player.set_physics_process(true)
	await frames(5)
	action("move_right", true)
	var max_speed := 0.0
	var max_offset := 0.0
	var min_speed := T.MOVE_SPEED
	for index in range(240):
		await frames()
		max_speed = maxf(max_speed, game.player.velocity.x)
		max_offset = maxf(max_offset, absf(game.player.position.y - (FLOOR_Y - T.PLAYER_SIZE.y / 2)))
		if index > 10:
			min_speed = minf(min_speed, game.player.velocity.x)
	action("move_right", false)
	check(max_speed == T.MOVE_SPEED and min_speed == T.MOVE_SPEED and game.player.position.x > 2800, "merged floor rows allow continuous full-speed walking across cell and floor seams")
	check(max_offset < 0.1, "flat surface walking has no vertical seam jitter")

func shoot_block(guided: bool) -> void:
	game.player.position = Vector2(2400, FLOOR_Y - 22)
	game.spawn_bullet(game.player, Vector2.RIGHT, guided)
	await frames(16)

func verify_blocks() -> void:
	await fixture(true)
	await shoot_block(false)
	check(game.terrain.breakables.size() == 1 and game.terrain.breakables[0].hp == 2, "first real normal bullet reduces block durability")
	await shoot_block(false)
	check(game.terrain.breakables.size() == 1 and game.terrain.breakables[0].hp == 1, "second real normal bullet leaves block standing")
	await shoot_block(false)
	check(game.terrain.breakables.is_empty(), "third real normal bullet destroys block")
	await fixture(true)
	await shoot_block(true)
	check(game.terrain.breakables.is_empty(), "one real guided bullet destroys block")
	await fixture(true)
	var enemy = spawn("turret", 2400)
	enemy.facing = 1
	game.player.position.x = 2700
	var bullet = game.spawn_bullet(enemy, Vector2.RIGHT)
	await frames(30)
	check(not is_instance_valid(bullet) and game.terrain.breakables[0].hp == 3 and game.player.hp == T.PLAYER_HP, "block intercepts enemy bullet without taking damage")
	var laser := Laser.new()
	laser.game = game
	laser.source = enemy
	laser.curve = PackedVector2Array([Vector2(2400, FLOOR_Y - 22), Vector2(2700, FLOOR_Y - 22)])
	game.projectiles.add_child(laser)
	laser.set_physics_process(false)
	laser.clip_path()
	check(laser.path[-1].x == 2496 and game.terrain.breakables[0].hp == 3, "laser clips on block without damaging it")
	game.terrain.explode(Vector2(2528, FLOOR_Y - 32), 44)
	check(game.terrain.breakables.is_empty(), "blast destroys breakable whose center is in radius")
	await fixture(true)
	game.terrain.explode(Vector2(2460, FLOOR_Y - 32), 44)
	check(game.terrain.breakables.size() == 1, "blast excludes block center outside radius")
	await fixture()
	for index in range(5):
		game.terrain.damage_at(Vector2(2512, FLOOR_Y + 16), T.HOMING_DAMAGE)
	check(game.terrain.occupied.has(Vector2i(78, 72)), "player bullets cannot damage floor surface")

func verify_wall_plans() -> void:
	await fixture()
	var builder = spawn("builder", 2400)
	game.player.position.x = 2784
	var plan: Rect2 = game.terrain.find_wall_plan(builder, game.player)
	check(plan.has_area() and plan.size == Vector2(32, 96) and plan.end.y == FLOOR_Y, "builder chooses grounded three-cell wall")
	check(plan.position.x > builder.position.x and plan.end.x <= game.player.position.x - T.PLAYER_SIZE.x / 2 - 48, "wall lies between builder and player with 48px separation")
	check(game.terrain.confirm_wall_plan(plan, builder, game.player), "planned wall passes completion recheck")
	game.player.position = plan.get_center()
	check(not game.terrain.confirm_wall_plan(plan, builder, game.player), "moved player invalidates warning at completion")
	check(game.terrain.place_wall(plan, builder.get_instance_id()) == -1, "wall never encloses player body")
	game.player.position = Vector2(2784, FLOOR_Y - 22)
	var blocker = spawn("turret", plan.get_center().x)
	check(not game.terrain.can_place_wall(plan, builder.get_instance_id()), "wall never encloses any enemy body")
	blocker.free()
	check(game.terrain.place_wall(Rect2(2496, FLOOR_Y - 128, 32, 96), builder.get_instance_id()) == -1, "floating wall is rejected")
	check(game.terrain.place_wall(Rect2(2496, FLOOR_Y - 128, 32, 128), builder.get_instance_id()) == -1, "wall taller than 96px is rejected")
	check(game.terrain.place_wall(Rect2(2496, FLOOR_Y - 16, 32, 64), builder.get_instance_id()) == -1, "wall off grid or embedded in terrain is rejected")
	for x in [736, 6112, 11488]:
		check(game.terrain.place_wall(Rect2(x, FLOOR_Y - 96, 32, 96), builder.get_instance_id()) == -1, "protected column rejects wall x=%d" % x)
	var id: int = game.terrain.place_wall(plan, builder.get_instance_id())
	check(id >= 0, "valid wall is placed")
	check(game.terrain.place_wall(plan, builder.get_instance_id()) == -1, "overlapping walls are rejected")
	var plan2: Rect2 = game.terrain.find_wall_plan(builder, game.player)
	check(plan2.has_area() and game.terrain.place_wall(plan2, builder.get_instance_id()) >= 0, "builder can own a second wall")
	check(game.terrain.find_wall_plan(builder, game.player) == Rect2() and game.terrain.place_wall(Rect2(2624, FLOOR_Y - 96, 32, 96), builder.get_instance_id()) == -1, "builder cannot own a third live wall")
	builder.receive_hit(1 - builder.polarity, T.ENEMY_HP)
	await frames(2)
	check(game.terrain.walls.size() == 2, "walls survive owner defeat")
	var remaining: float = game.terrain.walls[id].remaining
	game.show_menu("paused")
	await frames(90)
	check(game.terrain.walls[id].remaining == remaining, "pause freezes wall lifetime")
	game.open_key_settings()
	await frames(20)
	check(game.terrain.walls[id].remaining == remaining, "key settings freezes wall lifetime")
	game.close_key_settings()
	game.resume_run()
	await frames(int((remaining - 0.1) * 60))
	check(game.terrain.walls.has(id), "wall remains until almost eight seconds")
	await frames(10)
	check(game.terrain.walls.is_empty() and game.terrain.wall_cells.is_empty(), "walls expire after configured eight seconds")
	# Low ceiling reduces a planned wall to two cells, then rejects less than two.
	await fixture()
	builder = spawn("builder", 2400)
	game.player.position.x = 2784
	for x in range(2496, 2625, 32):
		game.terrain.occupied[Vector2i(x / 32, 69)] = true
	plan = game.terrain.find_wall_plan(builder, game.player)
	check(plan.size.y == 64, "obstacle above shrinks wall to two cells")
	for x in range(2496, 2625, 32):
		game.terrain.occupied[Vector2i(x / 32, 70)] = true
	check(not game.terrain.find_wall_plan(builder, game.player).has_area(), "less than two cells of clearance prevents placement")

func verify_wall_collisions() -> void:
	await fixture()
	var wall := Rect2(2496, FLOOR_Y - 96, 32, 96)
	var id: int = game.terrain.place_wall(wall, 99)
	await frames(2)
	check(not ray(Vector2(2400, 2280), Vector2(2600, 2280), 8).is_empty(), "wall has dedicated physics layer")
	check(ray(Vector2(2400, 2280), Vector2(2600, 2280), 1).is_empty(), "wall is absent from enemy projectile and laser terrain mask")
	game.player.set_physics_process(true)
	action("move_right", true)
	await frames(50)
	action("move_right", false)
	check(game.player.position.x < wall.position.x - T.PLAYER_SIZE.x / 2 + 0.1 and game.player.is_on_wall(), "wall stops moving player body")
	game.player.set_physics_process(false)
	for remaining in [2, 1, 0]:
		await shoot_block(false)
		check(game.terrain.walls.is_empty() if remaining == 0 else game.terrain.walls[id].hp == remaining, "real player bullet damages wall: remaining %d" % remaining)
	await fixture()
	id = game.terrain.place_wall(wall, 99)
	game.player.position.x = 2700
	var enemy = spawn("turret", 2400)
	enemy.facing = 1
	var bullet = game.spawn_bullet(enemy, Vector2.RIGHT)
	await frames(32)
	check(is_instance_valid(bullet) and bullet.position.x > wall.end.x and game.terrain.walls[id].hp == 3, "enemy bullet passes wall without damaging it")
	var laser := Laser.new()
	laser.game = game
	laser.source = enemy
	laser.curve = PackedVector2Array([Vector2(2400, 2280), Vector2(2700, 2280)])
	game.projectiles.add_child(laser)
	laser.set_physics_process(false)
	laser.clip_path()
	check(laser.path[-1] == Vector2(2700, 2280), "laser passes through installed wall")
	var walker = spawn("walker", 2464)
	walker.patrol = Vector2(2368, 2624)
	walker.was_visible = true
	walker.wake_delay = 0
	walker.shot_clock = 100
	walker.set_meta("patrol_direction", 1)
	walker.set_physics_process(true)
	await frames(36)
	check(walker.position.x < 2464 and walker.get_meta("patrol_direction") == -1, "wall stops enemy body and walker reverses direction")
	game.terrain.explode(Vector2(2512, FLOOR_Y - 48), 80)
	check(game.terrain.walls.is_empty(), "explosion removes installed wall cells")
	await fixture()
	id = game.terrain.place_wall(wall, 99)
	game.terrain.explode(Vector2(2512, FLOOR_Y - 16), 20)
	check(game.terrain.walls[id].cells.size() == 2 and not game.terrain.wall_cells.has(Vector2i(78, 71)), "blast removes only in-radius wall cells")
	await fixture()
	id = game.terrain.place_wall(wall, 99)
	await shoot_block(true)
	check(game.terrain.walls.is_empty(), "one guided bullet destroys installed wall")

func verify_builder_actions() -> void:
	await fixture()
	var builder = spawn("builder", 2400)
	game.player.position.x = 2784
	builder.was_visible = true
	builder.wake_delay = 0
	builder.shot_clock = 0
	builder.build_clock = 0
	builder.gauge = T.GAUGE_CAPACITY
	builder.set_physics_process(true)
	await frames()
	check(builder.action == "windup_special" and not builder.wall_plan.has_area(), "full gauge takes priority over building and normal shooting")
	await frames(50)
	for bullet in game.projectiles.get_children():
		bullet.free()
	await frames()
	check(builder.action == "windup_build" and builder.wall_plan.has_area(), "builder warns before placement after special")
	check(game.terrain.walls.is_empty(), "build warning is exclusive and places nothing early")
	var plan: Rect2 = builder.wall_plan
	game.player.position = plan.get_center()
	await frames(40)
	check(game.terrain.walls.is_empty() and builder.action == "idle", "completion rechecks moved player and cancels unsafe plan")
	game.player.position = Vector2(2784, FLOOR_Y - 22)
	builder.build_clock = 0
	builder.shot_clock = 0
	await frames()
	check(builder.action == "windup_build", "build takes priority over ready normal shot")
	await frames(38)
	check(game.terrain.walls.size() == 1, "completed build warning creates actual wall")
	await frames()
	check(builder.action == "windup_shot", "builder retains normal shooting after building")
	builder.cancel_attack()
	builder.build_clock = 0
	game.camera.position.x = 9000
	await frames(120)
	check(builder.action == "idle" and not builder.wall_plan.has_area(), "offscreen builder neither warns nor builds")
	game.camera.position.x = 2600
	await frames(60)
	check(builder.wake_delay > 0 and builder.action == "idle", "builder re-entry respects wake delay")
	await frames(10)
	check(builder.action == "windup_build", "builder starts warning after waking")
	game.camera.position.x = 9000
	await frames(2)
	check(builder.action == "idle" and not builder.wall_plan.has_area(), "screen exit clears build outline")

func verify_bombs() -> void:
	await fixture()
	var breaker = spawn("breaker", 2400)
	game.player.position.x = 2800
	breaker.was_visible = true
	breaker.wake_delay = 0
	breaker.shot_clock = 0
	breaker.set_physics_process(true)
	await frames()
	var bomb = breaker.bomb
	check(is_instance_valid(bomb) and breaker.action == "windup_bomb" and bomb.phase == "warning", "breaker starts exclusive bomb warning")
	var target: Vector2 = bomb.target
	game.player.position.x = 3000
	breaker.polarity = 1
	await frames(30)
	check(bomb.phase == "warning" and bomb.target == target and bomb.polarity == 0, "warning lasts 0.6 seconds and fixes target feet and color")
	await frames(8)
	check(bomb.phase == "flight", "bomb launches after warning")
	var remaining_position: Vector2 = bomb.position
	game.show_menu("paused")
	await frames(45)
	check(bomb.position == remaining_position, "pause freezes flying bomb")
	game.open_key_settings()
	await frames(15)
	check(bomb.position == remaining_position, "key settings freezes flying bomb")
	game.close_key_settings()
	game.resume_run()
	var impact: Array[Vector2] = []
	bomb.tree_exiting.connect(func(): impact.append(bomb.global_position))
	breaker.receive_hit(0, T.ENEMY_HP) # Enemy switched to color 1 above.
	await frames(65)
	check(not is_instance_valid(bomb) and impact.size() == 1 and impact[0].distance_to(target) < 3, "parabola hits fixed floor target near one second even after source defeat")
	for color in [0, 1]:
		await fixture()
		breaker = spawn("breaker", 2400)
		game.player.position.x = 2560
		game.player.polarity = color
		bomb = game.spawn_bomb_warning(breaker)
		bomb.target = game.player.position + Vector2(0, 22)
		bomb.fire()
		var near_enemy = spawn("turret", 2560)
		await frames(75)
		check(not is_instance_valid(bomb), "actual bomb collides and explodes color %d" % color)
		check(game.player.hp == T.PLAYER_HP - (T.BOMB_DAMAGE if color == 1 else 0) and game.player.gauge == (1 if color == 0 else 0), "direct hit and blast apply exactly one color hit %d" % color)
		check(near_enemy.hp == T.ENEMY_HP and near_enemy.gauge == 0, "blast never damages or charges enemy %d" % color)
	await fixture()
	breaker = spawn("breaker", 2400)
	game.player.position.x = 2800
	var wall_id: int = game.terrain.place_wall(Rect2(2496, FLOOR_Y - 96, 32, 96), 99)
	bomb = game.spawn_bomb_warning(breaker)
	bomb.target = Vector2(2800, FLOOR_Y)
	bomb.fire()
	await frames(22)
	check(is_instance_valid(bomb) and bomb.position.x > 2528 and game.terrain.walls.has(wall_id), "bomb passes installed wall during actual flight")
	game.camera.position.x = 9000
	breaker.set_physics_process(true)
	breaker.shot_clock = 0
	await frames(5)
	check(breaker.action == "idle" and not is_instance_valid(breaker.bomb), "offscreen breaker cannot start warning")
	game.camera.position.x = 2600
	await frames(60)
	check(breaker.wake_delay > 0 and breaker.action == "idle", "breaker re-entry waits 1.1 seconds")
	await frames(10)
	var warning = breaker.bomb
	check(is_instance_valid(warning) and warning.phase == "warning", "breaker warns after wake")
	game.camera.position.x = 9000
	await frames(2)
	check(not is_instance_valid(warning) and breaker.action == "idle", "offscreen exit cancels bomb warning and target marker")
	await fixture()
	breaker = spawn("breaker", 2400)
	bomb = game.spawn_bomb_warning(breaker)
	bomb.fire()
	bomb.position = Vector2(12280, 1000)
	bomb.velocity = Vector2(1000, 0)
	await frames(2)
	check(not is_instance_valid(bomb), "bomb outside world is removed")

func verify_intervals() -> void:
	await fixture()
	var breaker = spawn("breaker", 2400)
	game.player.position.x = 2800
	breaker.set_physics_process(true)
	await frames(int((T.ENEMY_WAKE_DELAY + T.BOMB_INTERVAL) * 60) - 5)
	check(breaker.action == "idle" and game.projectiles.get_child_count() == 0, "breaker waits wake delay plus configured 3.2 second interval")
	await frames(10)
	check(breaker.action == "windup_bomb", "breaker warns once its initial interval expires")
	var remaining: float = breaker.action_remaining
	var warning = breaker.bomb
	var warning_elapsed: float = warning.elapsed
	game.show_menu("paused")
	await frames(40)
	check(breaker.action_remaining == remaining and warning.elapsed == warning_elapsed, "pause freezes bomb warning and target marker clock")
	game.resume_run()
	await fixture()
	var builder = spawn("builder", 2400)
	game.player.position.x = 2784
	builder.set_physics_process(true)
	# Normal shot windups consume time but do not delay the separate build interval.
	await frames(int((T.ENEMY_WAKE_DELAY + T.BUILD_INTERVAL) * 60) - 5)
	check(builder.action != "windup_build" and game.terrain.walls.is_empty(), "builder waits its own configured 4.5 second interval")
	await frames(10)
	check(builder.action == "windup_build", "builder interval advances while performing normal-shot warnings")
	remaining = builder.action_remaining
	var plan: Rect2 = builder.wall_plan
	game.show_menu("paused")
	await frames(40)
	check(builder.action_remaining == remaining and builder.wall_plan == plan and game.terrain.walls.is_empty(), "pause freezes build warning without placing wall")
	game.resume_run()

func verify_map_retry_performance() -> void:
	await fixture(true)
	var area := Rect2(2432, 2176, 128, 128)
	var minimap = game.ui.minimap
	var before: Array = minimap._geometry_for_cell(Vector2i(19, 17)).duplicate()
	check(not before.is_empty(), "minimap initially includes breakable block")
	game.terrain.damage_at(Vector2(2512, 2256), 4)
	minimap.update_map()
	check(minimap._geometry_for_cell(Vector2i(19, 17)).is_empty(), "minimap invalidates destroyed block cache")
	before = game.terrain.map_geometry(area)
	var id: int = game.terrain.place_wall(Rect2(2496, FLOOR_Y - 96, 32, 96), 99)
	check(id >= 0 and game.terrain.map_geometry(area) == before, "temporary wall never appears in minimap geometry")
	area = Rect2(2432, 2304, 128, 128)
	minimap.update_map()
	var count: int = minimap._geometry_for_cell(Vector2i(19, 18)).size()
	game.terrain.explode(Vector2(2464, FLOOR_Y + 32), 50)
	minimap.update_map()
	check(minimap._geometry_for_cell(Vector2i(19, 18)).size() < count, "minimap cache reflects destroyed floor cells")
	# Twenty destructive blasts on fresh columns, including collision/drawing refresh.
	await fixture()
	var samples: Array[int] = []
	for index in range(20):
		var started := Time.get_ticks_usec()
		game.terrain.explode(Vector2(1600 + index * 128, FLOOR_Y + 32), 60)
		samples.append(Time.get_ticks_usec() - started)
		await frames()
	var total := 0
	for sample in samples:
		total += sample
	performance = {"blasts": 20, "total_ms": total / 1000.0, "mean_ms": total / 20000.0, "max_ms": samples.max() / 1000.0, "includes": "cell removal, changed-row collisions, 8-neighbour masks and chunk redraw scheduling"}
	print("BLAST PERFORMANCE: ", JSON.stringify(performance))
	check(game.terrain.destroyed_cells.size() > 100, "performance samples actually destroy fresh floor cells")
	game.start_run(37)
	game.set_physics_process(false)
	for actor in get_nodes_in_group("enemies"):
		actor.set_physics_process(false)
	var pristine: Dictionary = game.terrain.occupied.duplicate()
	var pristine_masks: Dictionary = game.terrain.tile_masks.duplicate()
	var pristine_blocks: Dictionary = game.terrain.breakables.duplicate(true)
	var pristine_map: Array = game.terrain.map_geometry(Rect2(0, 0, T.WORLD_SIZE.x, T.WORLD_SIZE.y))
	var mutable_floor: Rect2 = game.stage.floors.filter(func(f): return not game.terrain._protected(f.position.x, f.end.x))[0]
	game.terrain.explode(Vector2(mutable_floor.get_center().x, FLOOR_Y + 32), 160)
	var bridge: Rect2 = game.stage.bridges[0].rect
	var plan := Rect2(floorf(bridge.get_center().x / 32) * 32, bridge.position.y - 96, 32, 96)
	var wall: int = game.terrain.place_wall(plan, 99)
	check(wall >= 0, "retry fixture contains installed wall")
	var source = get_nodes_in_group("enemies").filter(func(actor): return actor.kind == "breaker")[0]
	var flying = game.spawn_bomb_warning(source)
	flying.fire()
	check(not game.terrain.destroyed_cells.is_empty() and game.terrain.walls.size() > 0 and game.projectiles.get_child_count() > 0, "retry fixture contains changed floor, wall and bomb")
	game.player.receive_hit(1 - game.player.polarity, T.PLAYER_HP)
	await frames(3)
	check(game.state == "lost", "actual death opens retry result")
	game.primary_action()
	for actor in get_nodes_in_group("enemies"):
		actor.set_physics_process(false)
	await frames(2)
	check(game.terrain.occupied == pristine and game.terrain.tile_masks == pristine_masks and game.terrain.breakables == pristine_blocks, "retry completely restores original terrain, masks, blocks and durability")
	check(game.terrain.map_geometry(Rect2(0, 0, T.WORLD_SIZE.x, T.WORLD_SIZE.y)) == pristine_map, "retry restores complete minimap geometry")
	check(game.terrain.walls.is_empty() and game.terrain.destroyed_cells.is_empty() and game.projectiles.get_child_count() == 0 and not is_instance_valid(flying), "retry leaves no walls, destroyed cells or flying bombs")
	game.ui.minimap.update_map()
	check(game.ui.minimap._terrain_version[0] == game.terrain.get_instance_id(), "same-seed retry refreshes minimap terrain identity")

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://builds/qa/phase3")
	game = Main.new()
	game.controls_path = "res://builds/qa/phase3/terrain_controls.cfg"
	root.add_child(game)
	game.key_bindings.reset_defaults()
	await verify_surface()
	await verify_jump_and_walk()
	await verify_blocks()
	await verify_wall_plans()
	await verify_wall_collisions()
	await verify_builder_actions()
	await verify_bombs()
	await verify_intervals()
	await verify_map_retry_performance()
	var report := {"checks": checks, "failures": failures, "performance": performance}
	FileAccess.open("res://builds/qa/phase3/terrain_results.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	game.free()
	await frames(2)
	print("TERRAIN CHANGE TEST: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
