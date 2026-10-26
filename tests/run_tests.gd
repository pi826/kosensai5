extends SceneTree
const T := preload("res://scripts/tuning.gd")
const FIXTURE_SIZE := Vector2(12288, 3072)
const Actor := preload("res://scripts/combatant.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Terrain := preload("res://scripts/terrain.gd")
const WorldTerrain := preload("res://scripts/world_terrain.gd")
const Laser := preload("res://scripts/laser_beam.gd")
const Bomb := preload("res://scripts/bomb.gd")
const FIXTURE_ORIGIN := Vector2(5800, 1600)

class ObservedMain extends "res://scripts/main.gd":
	var result_menu_count := 0
	var guardian_fixtures: Array = []
	func start_run(seed_value: int) -> void:
		super.start_run(seed_value)
		# Combat fixtures exercise all victory orders independently of streaming travel.
		# Actual guardian loading/unloading is covered by streaming/playthrough tests.
		streaming_enabled = false
		if guardian_fixtures.is_empty():
			for at in preload("res://scripts/sector_generator.gd").guardian_sectors(seed_value):
				var data := preload("res://scripts/sector_job.gd").world_data(preload("res://scripts/sector_generator.gd").generate(seed_value, at))
				guardian_fixtures.append_array(data.spawns.filter(func(s): return s.kind == "boss"))
		for spawn: Dictionary in guardian_fixtures: stream._spawn(spawn)
	func show_menu(next_state: String) -> void:
		if next_state in ["won", "lost"]:
			result_menu_count += 1
		super.show_menu(next_state)

var checks := 0
var failures: Array[String] = []
var game: Node2D
var initial_exploration: Dictionary

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: ", message)

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func tap(action_name: String) -> void:
	var event := InputEventAction.new()
	event.action = action_name
	event.pressed = true
	Input.parse_input_event(event)

func run() -> void:
	var begun := Time.get_ticks_msec()
	for side in [0, 1]:
		for color in [0, 1]:
			var actor := Actor.new()
			actor.faction = side
			actor.polarity = color
			actor.hp = 20
			check(actor.receive_hit(color, 4) == "absorbed" and actor.hp == 20 and actor.gauge == 1, "shared absorption rule")
			check(actor.receive_hit(1 - color, 1) == "damaged" and actor.hp == 19, "shared damage rule")
			for i in range(20):
				actor.receive_hit(color, 4)
			check(actor.gauge == 8, "gauge capacity")
			check(actor.take_gauge() == 8 and actor.gauge == 0, "consume all charge")
			actor.free()
	var protected_actor := Actor.new()
	protected_actor.receive_hit(1, T.ENEMY_NORMAL_DAMAGE)
	protected_actor.receive_hit(1, T.ENEMY_NORMAL_DAMAGE)
	check(protected_actor.hp == T.PLAYER_HP - T.ENEMY_NORMAL_DAMAGE and T.INVULNERABILITY == 1.5, "1.5-second player hit protection")
	protected_actor.receive_hit(0, 1)
	check(protected_actor.gauge == 1, "can absorb during hit protection")
	protected_actor.free()
	check(T.ENEMY_HP == 2 and T.NORMAL_DAMAGE == 1, "normal enemies require two opposite-color normal shots")
	game = ObservedMain.new()
	game.controls_path = "res://builds/qa/unit_controls.cfg"
	root.add_child(game)
	game.key_bindings.reset_defaults()
	await frames(2)
	check(game.state == "title" and game.ui.menu.visible, "title opens")
	game.start_run(37)
	await frames(3)
	check(game.player.is_on_floor(), "player grounded on start floor")
	var raw_key := InputEventKey.new()
	raw_key.keycode = KEY_K
	raw_key.pressed = true
	Input.parse_input_event(raw_key)
	raw_key = InputEventKey.new()
	raw_key.keycode = KEY_K
	raw_key.pressed = false
	Input.parse_input_event(raw_key)
	Input.flush_buffered_events()
	check(game.player.polarity == 1, "short logical-key tap changes color before next physics tick")
	game.player.polarity = 0
	var initial_layout: Dictionary = game.stage.duplicate(true)
	initial_exploration = game.explored_cells.duplicate()
	prepare_fixture()
	var fixture_enemies := normal_enemies().slice(0, 3)
	var enemy = fixture_enemies[0]
	for index in range(fixture_enemies.size()):
		fixture_enemies[index].position = at([400, 640, 520][index], 618)
	enemy.polarity = 1
	game.player.polarity = 0
	var bullet = game.spawn_bullet(game.player, Vector2.RIGHT)
	game.player.polarity = 1
	check(bullet.polarity == 0, "projectile keeps launch color")
	await frames(25)
	check(enemy.hp == T.ENEMY_HP - T.NORMAL_DAMAGE, "swept projectile damages opposite-color body")
	check(game.effects.damage_sequence == 1 and game.effects.damage_numbers[0].amount == 1, "normal hit displays actual integer damage")
	game.player.polarity = 1
	game.spawn_bullet(game.player, Vector2.RIGHT)
	await frames(25)
	check(enemy.hp == T.ENEMY_HP - T.NORMAL_DAMAGE and enemy.gauge == 1, "same-color projectile feeds enemy")
	check(game.effects.damage_sequence == 1, "absorption produces no damage number")
	enemy.invulnerability = 1
	enemy.receive_hit(0, 4)
	check(game.effects.damage_sequence == 1 and enemy.hp == T.ENEMY_HP - T.NORMAL_DAMAGE, "protected hit produces no damage number")
	enemy.invulnerability = 0
	check(game.score == 0, "absorption awards no score")
	game.player.polarity = 0
	enemy.polarity = 0
	enemy.facing = -1
	game.spawn_bullet(enemy, Vector2.LEFT)
	await frames(55)
	check(game.player.hp == T.PLAYER_HP and game.player.gauge == 1, "enemy shot absorbed by player")
	clear_bullets()
	game.player.gauge = 0
	tap("special")
	await frames(2)
	Input.action_release("special")
	check(game.projectiles.get_child_count() == 0, "empty gauge produces no special")
	game.player.homing_charges = 3
	tap("special")
	await frames(2)
	Input.action_release("special")
	check(game.player.homing_charges == 2 and game.projectiles.get_child_count() == T.HOMING_VOLLEY_SIZE, "one stock fires one fixed-size volley")
	clear_bullets()
	var second = fixture_enemies[1]
	var third = fixture_enemies[2]
	enemy.position = at(430, 618)
	second.position = at(640, 618)
	third.position = at(520, 618)
	enemy.polarity = 1
	second.polarity = 1
	third.polarity = 0
	game.player.polarity = 0
	game.fire_special(game.player, 4)
	var assignments := {}
	for guided in game.projectiles.get_children():
		check(guided.target == enemy or guided.target == second, "homing avoids same-color target when opposites exist")
		assignments[guided.target.get_instance_id()] = int(assignments.get(guided.target.get_instance_id(), 0)) + 1
	check(assignments.size() == 2 and assignments.values().has(2), "homing distributes between opposite enemies")
	var guided = game.projectiles.get_child(0)
	var original_target = guided.target
	original_target.polarity = 0
	await frames(1)
	check(guided.target == original_target and guided.polarity == 0, "tracking persists after target color switch")
	original_target.dead = true
	await frames(1)
	check(guided.target != original_target, "homing reacquires defeated target")
	original_target.dead = false
	clear_bullets()
	var friendly_hp: int = second.hp
	var friendly_gauge: int = second.gauge
	enemy.facing = 1
	game.spawn_bullet(enemy, Vector2.RIGHT)
	await frames(55)
	check(second.hp == friendly_hp and second.gauge == friendly_gauge, "enemy projectiles neither damage nor charge other enemies")
	clear_bullets()
	# Charge-loop behaviour uses the actual enemy windup and actual guided projectiles.
	second.position.x = FIXTURE_ORIGIN.x + 2500
	third.position.x = FIXTURE_ORIGIN.x + 2700
	enemy.position = at(430, 618)
	enemy.polarity = 0
	game.fire_special(game.player, 1)
	check(game.projectiles.get_child(0).target == enemy, "homing falls back to a same-color enemy when no opposite is visible")
	clear_bullets()
	enemy.position.x = FIXTURE_ORIGIN.x + 2500
	game.fire_special(game.player, 1)
	var untargeted = game.projectiles.get_child(0)
	check(untargeted.target == null and untargeted.direction.is_equal_approx(Vector2(game.player.facing, 0)), "special flies forward when no enemy is visible")
	clear_bullets()
	enemy.position.x = FIXTURE_ORIGIN.x + 430
	enemy.kind = "turret"
	enemy.gauge = 8
	enemy.wake_delay = 0
	enemy.was_visible = true
	enemy.shot_clock = 10
	enemy.set_physics_process(true)
	game.player.gauge = 0
	game.player.homing_charges = 0
	await frames(1)
	check(enemy.action == "windup_special", "full enemy gauge starts special warning")
	await frames(25)
	check(game.projectiles.get_child_count() == 0 and enemy.gauge == 8, "enemy special respects warning duration")
	await frames(30)
	check(enemy.gauge == 0 and game.projectiles.get_child_count() == 8, "enemy expends full gauge on eight homing shots")
	enemy.set_physics_process(false)
	await frames(160)
	check((game.player.gauge > 0 or game.player.homing_charges > 0) and game.player.hp == T.PLAYER_HP, "enemy homing special can be absorbed and recycled")
	check(game.score == 0, "charge loop cannot farm score")
	clear_bullets()
	enemy.receive_hit(1 - enemy.polarity, 100)
	game.actor_defeated(enemy)
	game.actor_defeated(enemy)
	await frames(3)
	check(game.score == T.ENEMY_SCORE and game.kills == 1 and game.defeated_enemies.size() == 1, "normal enemy kill scores exactly once despite duplicate notifications")
	game.show_menu("paused")
	var paused_time: float = game.elapsed
	var paused_position: Vector2 = game.player.position
	Input.action_press("move_right")
	await frames(30)
	Input.action_release("move_right")
	check(game.player.position == paused_position and game.elapsed == paused_time, "pause freezes movement and timer")
	game.resume_run()
	Input.action_press("move_right")
	tap("jump")
	await frames(8)
	Input.action_release("jump")
	Input.action_release("move_right")
	check(game.player.position.x > paused_position.x and game.player.position.y < paused_position.y - 10, "keyboard actions move and jump")
	var old_color: int = game.player.polarity
	tap("switch_color")
	Input.action_press("shoot")
	await frames(1)
	Input.action_release("switch_color")
	Input.action_release("shoot")
	check(game.player.polarity == 1 - old_color, "can switch color in air while firing")
	# One-way shelves remain usable anywhere in the continuous world.
	game.player.position = at(640, 618)
	game.player.velocity = Vector2.ZERO
	var shelf := Terrain.new()
	shelf.bounds = Rect2(at(512, 512), Vector2(256, 16))
	game.world.add_child(shelf)
	await frames(3)
	tap("jump")
	await frames(38)
	check(game.player.is_on_floor() and absf(game.player.position.y - at(0, 490).y) < 0.5, "jump through underside and land on a vertical platform")
	game.start_run(37)
	await frames(3)
	check(game.stage == initial_layout and game.player.hp == T.PLAYER_HP and game.player.gauge == 0 and game.score == 0, "same-seed retry resets whole run")
	check(game.effects.damage_numbers.is_empty() and game.effects.damage_sequence == 0, "retry clears all damage numbers")
	check(game.total_enemies == normal_enemies().size() and game.total_enemies >= 6, "all generated normal enemies are instantiated")
	check(boss_enemies().size() == 3, "all three biome guardians are instantiated")
	var hidden = normal_enemies()[0]
	for actor in get_nodes_in_group("enemies"):
		actor.set_physics_process(false)
	hidden.set_physics_process(true)
	hidden.position = game.player.position + Vector2(3000, 0)
	await frames(120)
	check(game.projectiles.get_child_count() == 0 and hidden.action == "idle" and not hidden.was_visible, "offscreen enemies keep physics but do not attack")
	# A boss warning retains the old collision color until it completes.
	prepare_fixture()
	var guardian = boss_enemies()[0]
	guardian.position = at(780, 582)
	guardian.set_physics_process(true)
	game.player.position = at(560, 618)
	game._update_camera(1.0, true)
	await frames(3)
	game.boss.wake_delay = 0
	game.boss.switch_clock = 0
	game.boss.shot_clock = 10
	game.boss.action = "idle"
	var boss_old_color: int = game.boss.polarity
	await frames(1)
	check(game.boss.action == "windup_switch", "boss announces color change")
	await frames(25)
	check(game.boss.polarity == boss_old_color, "warning retains old color")
	await frames(28)
	check(game.boss.polarity != boss_old_color and game.boss.pattern == 1, "boss switches color and attack pattern after warning")
	for actor in get_nodes_in_group("enemies"):
		actor.set_physics_process(false)
	game.boss.polarity = 1
	game.player.polarity = 0
	game.player.position = Vector2(game.boss.position.x + 220, at(0, 618).y)
	game.player.facing = 1
	await frames(2)
	clear_bullets()
	game.fire_special(game.player, 2)
	check(game.projectiles.get_child(0).direction.x < 0, "homing launches toward target behind player")
	await frames(45)
	check(game.boss.hp == 72, "homing hits rear target without orbiting")
	check(game.ui.boss_hp_label.text == "72", "boss HUD displays remaining integer HP only")
	check(game.effects.damage_numbers.size() == 2 and game.effects.damage_numbers[0].amount == 4 and game.effects.damage_numbers[1].amount == 4, "homing hits display separate damage numbers")
	check(game.effects.damage_numbers[0].lane != game.effects.damage_numbers[1].lane, "simultaneous numbers use different horizontal lanes")
	await frames(60)
	check(game.effects.damage_numbers.is_empty(), "floating damage numbers expire")
	guardian.hp = T.BOSS_HP
	guardian.receive_hit(1 - guardian.polarity, 180)
	game.actor_defeated(guardian)
	game.actor_defeated(guardian)
	await frames(3)
	check(game.state == "playing" and game.score == T.BOSS_SCORE and game.defeated_bosses.size() == 1, "first guardian defeat adds score without ending exploration")
	check(game.defeated_enemies.size() == 1, "duplicate guardian notifications award neither score nor progress twice")
	check(game.effects.damage_numbers.size() == 1 and game.effects.damage_numbers[0].amount == 80, "lethal overkill displays HP removed and survives actor deletion")
	# Finish the other guardians in reverse ID order. The win condition depends
	# on three distinct guardians, not a fixed order or repeated notifications.
	var remaining := boss_enemies()
	remaining.sort_custom(func(a, b): return a.boss_id > b.boss_id)
	for index in range(remaining.size()):
		var next_guardian = remaining[index]
		next_guardian.position = at(780, 582)
		for actor in get_nodes_in_group("enemies"):
			actor.set_physics_process(false)
		next_guardian.receive_hit(1 - next_guardian.polarity, T.BOSS_HP)
		game.actor_defeated(next_guardian)
		await frames(3)
		check(game.defeated_bosses.size() == index + 2 and game.score == (index + 2) * T.BOSS_SCORE, "distinct guardian %d counted once" % (index + 2))
		check(game.state == ("won" if index == remaining.size() - 1 else "playing"), "clear requires all three distinct guardians")
	check(game.ui.menu.visible and game.defeated_bosses.size() == 3, "third guardian opens clear screen")
	game.primary_action()
	await frames(3)
	check(game.state == "playing" and game.score == 0 and game.kills == 0 and game.player.hp == T.PLAYER_HP and game.player.gauge == 0, "clear retry resets player and score")
	check(game.stage == initial_layout and game.defeated_bosses.is_empty() and game.defeated_enemies.is_empty(), "clear retry preserves seeded map and clears defeat records")
	check(game.explored_cells == initial_exploration and game.discovered_bosses.is_empty(), "clear retry resets explored map cells and hidden guardians")
	check(boss_enemies().size() == 3 and boss_enemies().all(func(actor): return actor.hp == T.BOSS_HP and not actor.dead), "clear retry revives all three guardians at full HP")
	var defeated_before_death = boss_enemies()[0]
	game.player.position = Vector2(FIXTURE_SIZE.x - 1400, 1800)
	game._update_camera(1.0, true)
	game._update_exploration()
	for actor in get_nodes_in_group("enemies"):
		actor.set_physics_process(false)
	defeated_before_death.receive_hit(1 - defeated_before_death.polarity, T.BOSS_HP)
	await frames(3)
	check(game.defeated_bosses.size() == 1 and game.explored_cells.size() > initial_exploration.size() and game.state == "playing", "death retry fixture includes a defeated guardian and explored map cells")
	game.player.gauge = 5
	game.effects.damage_numbers.clear()
	game.player.receive_hit(1 - game.player.polarity, T.PLAYER_HP)
	await frames(3)
	check(game.state == "lost" and game.ui.menu.visible, "player defeat opens retry screen")
	check(game.effects.damage_numbers.is_empty(), "enemy damage display does not add player popups")
	game.primary_action()
	await frames(3)
	check(game.state == "playing" and game.current_seed == 37 and game.player.hp == T.PLAYER_HP and game.player.gauge == 0 and game.score == 0, "death retry resets player and reuses seed")
	check(boss_enemies().size() == 3 and game.defeated_bosses.is_empty() and game.defeated_enemies.is_empty() and game.explored_cells == initial_exploration and game.discovered_bosses.is_empty(), "death retry revives guardians and resets exploration")
	await verify_two_hit_enemies()
	await verify_guardian_orders()
	await verify_aim_controls()
	await verify_platform_attacks()
	await verify_multi_lock()
	await verify_player_feedback()
	verify_ui_language()
	game.queue_free()
	await frames(2)
	var report := {"checks": checks, "failures": failures, "elapsed_ms": Time.get_ticks_msec() - begun}
	DirAccess.make_dir_recursive_absolute("res://builds/qa/seamless")
	var file := FileAccess.open("res://builds/qa/seamless/combat_results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("TEST RESULT: ", checks, " checks, ", failures.size(), " failures (", report.elapsed_ms, " ms)")
	quit(0 if failures.is_empty() else 1)

func at(x: float, y: float) -> Vector2:
	return FIXTURE_ORIGIN + Vector2(x, y)

func action_tap(action_name: String) -> void:
	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = action_name
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()

func verify_aim_controls() -> void:
	game.start_run(37)
	prepare_fixture()
	await frames(3)
	check(game.player.aim_angle() == 0, "a new run starts at zero elevation")
	for angle in [60.0, -60.0, 0.0]:
		action_tap("aim_cycle")
		check(game.player.aim_angle() == angle, "aim cycle advances to %d degrees" % angle)
		game.ui.update_hud()
		check(game.ui.angle_label.text == "射撃方向 " + T.AIM_NAMES[T.AIM_ANGLES.find(angle)], "HUD shows the current direction")
	game.player.set_physics_process(false)
	for index in range(3):
		var angle: float = [0.0, 60.0, -60.0][index]
		for facing in [-1, 1]:
			game.player.facing = facing
			game.player.shot_cooldown = 0
			game.player.set_physics_process(true)
			Input.action_press("shoot")
			await frames(1)
			Input.action_release("shoot")
			game.player.set_physics_process(false)
			check(game.projectiles.get_child_count() == 1, "held shooting produces one real shot")
			var bullet = game.projectiles.get_child(0)
			var expected := Vector2(facing * cos(deg_to_rad(angle)), -sin(deg_to_rad(angle)))
			check(bullet.direction.is_equal_approx(expected), "shot direction for facing %d at %d degrees" % [facing, angle])
			var offset: Vector2 = bullet.position - game.player.position
			check(offset.normalized().is_equal_approx(expected) and not Rect2(-T.PLAYER_SIZE / 2, T.PLAYER_SIZE).has_point(offset), "muzzle is outside the body along the firing direction")
			check(bullet.speed == T.PLAYER_BULLET_SPEED and bullet.damage == T.NORMAL_DAMAGE and is_equal_approx(game.player.shot_cooldown, T.SHOT_INTERVAL), "normal shot speed, damage and interval stay unchanged")
			clear_bullets()
		action_tap("aim_cycle")
	# Actual movement flips facing without resetting the selected elevation.
	action_tap("aim_cycle")
	game.player.set_physics_process(true)
	for action_name in ["move_left", "move_right"]:
		Input.action_press(action_name)
		await frames(6)
		Input.action_release(action_name)
		check(game.player.facing == (-1 if action_name == "move_left" else 1) and game.player.aim_angle() == 60, "movement changes facing and keeps elevation")
	game.show_menu("paused")
	action_tap("aim_cycle")
	check(game.player.aim_angle() == 60, "pause blocks angle changes")
	game.open_key_settings()
	action_tap("aim_cycle")
	check(game.player.aim_angle() == 60, "key settings block angle changes")
	game.close_key_settings()
	game.new_action()
	check(game.player.aim_angle() == 0, "restarting from pause resets elevation")
	action_tap("aim_cycle")
	game.player.receive_hit(1 - game.player.polarity, T.PLAYER_HP)
	await frames(3)
	game.primary_action()
	check(game.player.aim_angle() == 0, "death retry resets elevation")
	check(game.ui.controls_label.text.contains("L 射撃方向（前→上→下）") and game.ui.controls_label.text.contains("S / ↓ 薄い足場を降りる") and game.ui.gauge_label.text.begins_with("誘導弾"), "HUD help and stock use the new controls")

func verify_platform_attacks() -> void:
	for use_world in [false, true]:
		game.start_run(37)
		prepare_fixture()
		game.player.set_physics_process(false)
		var bounds := Rect2(at(512, 512), Vector2(256, 16))
		if use_world:
			var terrain := WorldTerrain.new()
			terrain.stage = {"bounds": game.stage.bounds, "solids": [bounds]}
			game.world.add_child(terrain)
			game.terrain = terrain
			check(terrain.collision_root.get_child(0).collision_layer == T.PLATFORM_LAYER, "world shelf uses dedicated layer")
		else:
			var terrain := Terrain.new()
			terrain.bounds = bounds
			game.world.add_child(terrain)
			check(terrain.collision_layer == T.PLATFORM_LAYER, "standalone shelf uses dedicated layer")
		await frames(3)
		var enemy = normal_enemies()[0]
		enemy.position = at(430, 618)
		for actor in [game.player, enemy]:
			for vertical in [-1, 1]:
				var direction := Vector2(0, vertical)
				var bullet = game.spawn_bullet(actor, direction)
				bullet.position = at(700, 472 if vertical == 1 else 568)
				await frames(12)
				check(not is_instance_valid(bullet), "faction %d shot is stopped by shelf from direction %d (world=%s)" % [actor.faction, vertical, use_world])
		for vertical in [-1, 1]:
			var beam := Laser.new()
			beam.game = game
			beam.source = enemy
			beam.curve = PackedVector2Array([at(700, 472 if vertical == 1 else 568), at(700, 568 if vertical == 1 else 472)])
			game.projectiles.add_child(beam)
			beam.set_physics_process(false)
			beam.clip_path()
			check(beam.path.size() == 2 and absf(beam.path[-1].y - at(0, 512 if vertical == 1 else 528).y) < 0.1, "laser warning stops at the shelf surface")
			beam.fire()
			check(absf(beam.path[-1].y - at(0, 512 if vertical == 1 else 528).y) < 0.1, "laser beam still stops at the shelf surface")
			beam.free()
		var bomb := Bomb.new()
		bomb.game = game
		bomb.source = enemy
		bomb.phase = "flight"
		bomb.position = at(700, 472)
		bomb.velocity = Vector2(0, 200)
		game.projectiles.add_child(bomb)
		var impact := [Vector2.ZERO]
		bomb.tree_exiting.connect(func(): impact[0] = bomb.position)
		await frames(20)
		check(not is_instance_valid(bomb) and absf(impact[0].y - at(0, 512).y) < 0.1, "breaker shell detonates on the thin shelf (world=%s)" % use_world)

func verify_multi_lock() -> void:
	game.start_run(37)
	prepare_fixture()
	await frames(3)
	var enemies := normal_enemies().slice(0, 3)
	for index in range(3):
		enemies[index].position = at([430, 520, 640][index], 618)
		enemies[index].polarity = 1
		enemies[index].hp = 100
	game.player.polarity = 0
	for amount in [0, 1, 2, 3, 4, 5]:
		game.player.homing_charges = amount
		game._update_lock_marks()
		var marked: Array = game.lock_on_targets()
		var expected := 3 if amount > 0 else 0
		check(marked.size() == expected, "preview shows the next volley for stock=%d" % amount)
		check(enemies.filter(func(actor): return actor.lock_marked).size() == marked.size(), "actual drawn mark flags match the preview")
		check(marked == enemies.slice(0, expected), "preview follows distance priority")
	game.player.homing_charges = 1
	action_tap("special")
	await frames(1)
	check(game.player.homing_charges == 0 and game.projectiles.get_child_count() == T.HOMING_VOLLEY_SIZE, "one stock fires four missiles")
	var counts := [0, 0, 0]
	for missile in game.projectiles.get_children():
		var index := enemies.find(missile.target)
		check(index >= 0, "each missile selects a visible opposite enemy")
		if index >= 0:
			counts[index] += 1
	check(counts == [2, 1, 1], "four missiles cover three enemies with assignment difference at most one")
	game._update_lock_marks()
	check(game.lock_on_targets().is_empty() and enemies.all(func(actor): return not actor.lock_marked), "preview clears when no next volley is available")
	# All missiles at enemy 0 rebalance using the current live counts.
	enemies[0].dead = true
	var first_missile = game.projectiles.get_child(0)
	await frames(1)
	check(first_missile.target == enemies[1], "defeated target reacquires the least-targeted live enemy with distance tie break")
	counts = [0, 0, 0]
	for missile in game.projectiles.get_children():
		var index := enemies.find(missile.target)
		if index >= 0:
			counts[index] += 1
	check(counts == [0, 2, 2], "simultaneous retargets update counts and break ties by distance")
	enemies[0].dead = false
	clear_bullets()
	game._update_lock_marks()
	check(game.lock_on_targets().is_empty() and enemies.all(func(actor): return not actor.lock_marked), "marks clear after missiles disappear with empty gauge")
	enemies[2].polarity = 0
	game.player.homing_charges = 1
	check(game.lock_on_targets() == enemies.slice(0, 2), "same-color enemy is excluded from preview when opposites exist")
	game.player.launch_homing()
	check(game.projectiles.get_children().all(func(missile): return missile.target != enemies[2]), "two opposites and one same-color enemy never assign to the same-color enemy")
	clear_bullets()
	for enemy in enemies:
		enemy.polarity = 0
	game.player.homing_charges = 2
	check(game.lock_on_targets() == enemies.slice(0, 3), "same-color candidates are available when no opposites exist")
	enemies[0].dead = true
	enemies[1].position.x += 3000
	check(game.lock_on_targets() == [enemies[2]], "dead and offscreen enemies are excluded")
	enemies[0].dead = false
	# The enemy path retains its speed, damage, spread and single player target.
	clear_bullets()
	game.fire_special(enemies[2], T.GAUGE_CAPACITY)
	check(game.projectiles.get_child_count() == T.GAUGE_CAPACITY, "enemy still launches its full gauge")
	for missile in game.projectiles.get_children():
		check(missile.target == game.player and missile.speed == T.ENEMY_HOMING_SPEED and missile.damage == T.ENEMY_HOMING_DAMAGE and missile.life == T.BULLET_LIFETIME, "enemy missile keeps its player target and combat values")
	var missile = game.projectiles.get_child(0)
	missile.target = null
	await frames(1)
	check(missile.target == game.player, "enemy reacquisition still selects only the player")
	clear_bullets()

func prepare_fixture() -> void:
	# Combat checks use a flat, clear piece of the same continuous physics world.
	# Procedural terrain traversal is checked separately by the exploration bot.
	for child in game.world.get_children():
		if child != game.player and child != game.projectiles and child != game.effects and not child.is_in_group("enemies"):
			child.free()
	for actor in get_nodes_in_group("enemies"):
		actor.set_physics_process(false)
		actor.position = Vector2(11000, 2500)
	var floor_block := Terrain.new()
	floor_block.bounds = Rect2(at(0, 640), Vector2(4000, 160))
	game.world.add_child(floor_block)
	game.player.position = at(210, 618)
	game.player.velocity = Vector2.ZERO
	game.player.facing = 1
	game._update_camera(1.0, true)

func normal_enemies() -> Array:
	return get_nodes_in_group("enemies").filter(func(actor): return actor.kind != "boss" and actor.get_parent() == game.world)

func boss_enemies() -> Array:
	return get_nodes_in_group("enemies").filter(func(actor): return actor.kind == "boss" and actor.get_parent() == game.world and not actor.is_queued_for_deletion())

func clear_bullets() -> void:
	for bullet in game.projectiles.get_children():
		bullet.free()

func two_hit_fixture(kind: String, color: int):
	game.start_run(37)
	prepare_fixture()
	game.player.set_physics_process(false)
	var enemy := Enemy.new()
	enemy.game = game
	enemy.kind = kind
	enemy.polarity = color
	enemy.spawn_id = "two_hit_%s_%d" % [kind, color]
	enemy.position = at(400, 618)
	game.world.add_child(enemy)
	enemy.set_physics_process(false)
	game.player.polarity = 1 - color
	game.player.facing = 1
	return enemy

func verify_two_hit_enemies() -> void:
	for kind in ["turret", "walker", "shifter", "flyer", "laser", "breaker", "builder"]:
		for color in [0, 1]:
			var enemy = two_hit_fixture(kind, color)
			await frames(3)
			var context := "%s color %d" % [kind, color]
			check(enemy.hp == 2 and enemy.max_hp == 2, context + ": default enemy HP is two")
			var first_shot = game.spawn_bullet(game.player, Vector2.RIGHT)
			check(not first_shot.homing and first_shot.damage == 1, context + ": first hit uses a real normal projectile")
			await frames(25)
			check(is_instance_valid(enemy) and not enemy.dead and enemy.hp == 1, context + ": survives the first opposite-color normal shot")
			check(not is_instance_valid(first_shot) and game.score == 0 and game.kills == 0, context + ": first shot is consumed without a kill award")
			check(game.effects.damage_sequence == 1 and game.effects.damage_numbers[0].amount == 1, context + ": first hit displays integer damage one")
			game.player.polarity = color
			var absorbed_shot = game.spawn_bullet(game.player, Vector2.RIGHT)
			await frames(25)
			check(is_instance_valid(enemy) and not enemy.dead and enemy.hp == 1 and enemy.gauge == 1, context + ": intervening same-color shot is absorbed without losing HP")
			check(not is_instance_valid(absorbed_shot) and game.effects.damage_sequence == 1 and game.score == 0, context + ": absorption consumes the shot without damage text or score")
			game.player.polarity = 1 - color
			var second_shot = game.spawn_bullet(game.player, Vector2.RIGHT)
			await frames(25)
			check(not is_instance_valid(enemy) and not is_instance_valid(second_shot), context + ": second opposite-color normal shot defeats the enemy")
			check(game.score == T.ENEMY_SCORE and game.kills == 1 and game.defeated_enemies.size() == 1, context + ": defeat awards score exactly once")
			check(game.effects.damage_sequence == 2 and not game.effects.damage_numbers.is_empty() and game.effects.damage_numbers[-1].amount == 1, context + ": lethal second hit displays one actual damage")
	var homing_enemy = two_hit_fixture("turret", 1)
	await frames(3)
	var guided_shot = game.spawn_bullet(game.player, Vector2.RIGHT, true, homing_enemy)
	check(guided_shot.homing and guided_shot.damage == T.HOMING_DAMAGE, "normal-enemy overkill uses a real homing projectile")
	await frames(40)
	check(not is_instance_valid(homing_enemy), "one homing shot defeats a default two-HP normal enemy")
	check(game.effects.damage_sequence == 1 and game.effects.damage_numbers.size() == 1 and game.effects.damage_numbers[0].amount == 2, "homing overkill displays only the two HP actually removed")

func verify_guardian_orders() -> void:
	var orders := [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]
	for order: Array in orders:
		game.start_run(37)
		await frames(3)
		var result_count: int = game.result_menu_count
		var guardians := boss_enemies()
		guardians.sort_custom(func(a, b): return a.boss_id < b.boss_id)
		for actor in get_nodes_in_group("enemies"):
			actor.set_physics_process(false)
		for index in range(order.size()):
			var guardian = guardians[order[index]]
			guardian.receive_hit(1 - guardian.polarity, T.BOSS_HP)
			game.actor_defeated(guardian)
			game.actor_defeated(guardian)
			await frames(3)
			var count := index + 1
			var context := "order %s after %d guardian(s)" % [str(order), count]
			check(game.defeated_bosses.size() == count and game.defeated_enemies.size() == count, context + ": unique progress")
			check(game.score == count * T.BOSS_SCORE, context + ": unique score")
			check(game.state == ("won" if count == 3 else "playing"), context + ": correct win state")
			check(game.result_menu_count == result_count + (1 if count == 3 else 0), context + ": result opens exactly once")
	# Both notifications arrive during one frame: player death takes precedence
	# over completing the third guardian, regardless of the queued finish order.
	game.start_run(37)
	await frames(3)
	var result_count: int = game.result_menu_count
	var guardians := boss_enemies()
	for actor in get_nodes_in_group("enemies"):
		actor.set_physics_process(false)
	for index in range(2):
		guardians[index].receive_hit(1 - guardians[index].polarity, T.BOSS_HP)
		await frames(3)
	var last_guardian = guardians[2]
	last_guardian.receive_hit(1 - last_guardian.polarity, T.BOSS_HP)
	game.player.receive_hit(1 - game.player.polarity, T.PLAYER_HP)
	game.actor_defeated(last_guardian)
	game.actor_defeated(game.player)
	await frames(3)
	check(game.state == "lost" and game.ui.menu.visible, "simultaneous final guardian and player deaths prefer loss")
	check(game.defeated_bosses.size() == 3 and game.score == 3 * T.BOSS_SCORE, "simultaneous deaths still count the final guardian once")
	check(game.result_menu_count == result_count + 1, "simultaneous deaths open one result screen")

func verify_player_feedback() -> void:
	game.start_run(37)
	prepare_fixture()
	await frames(3)
	var player = game.player
	var enemy = normal_enemies()[0]
	player.polarity = 0
	enemy.polarity = 0
	enemy.position = player.position
	await frames(3)
	check(player.hp == 100 and player.gauge == 0 and game.effects.health_display == null, "same-color body causes neither damage nor absorption nor HP popup")
	enemy.action = "windup_switch"
	enemy.next_polarity = 1
	await frames(2)
	check(player.hp == 100, "switch warning keeps the old body color")
	enemy.polarity = 1
	enemy.next_polarity = 0
	await frames(1)
	check(player.hp == 100 - T.CONTACT_DAMAGE and player.gauge == 0, "opposite normal body inflicts contact damage without pushing")
	check(player.position.distance_to(enemy.position) < 0.2, "bodies still overlap without physical repulsion")
	check(is_equal_approx(player.invulnerability, 1.5), "contact starts exactly 1.5 seconds of invulnerability")
	var hp_after_contact: int = player.hp
	var query_result: String = player.receive_hit(1, T.ENEMY_NORMAL_DAMAGE)
	check(query_result == "protected" and player.hp == hp_after_contact, "contact protection also blocks bullets")
	await frames(60)
	check(player.hp == hp_after_contact and player.invulnerability > 0.45, "contact stays protected beyond the former one second")
	check(player.receive_hit(0, 12) == "absorbed" and player.gauge == 1, "same-color attack absorbs during the longer protection")
	# Real shots hit during protection; absorption must precede the protection check.
	for color in [1, 0]:
		enemy.polarity = color
		var bullet = game.spawn_bullet(enemy, Vector2.RIGHT)
		bullet.position = player.position - Vector2(40, 0)
		await frames(12)
		check(not is_instance_valid(bullet) and player.hp == hp_after_contact, "real projectile resolves safely during invulnerability, color %d" % color)
	check(player.gauge == 2, "real same-color projectile still charges the protected player")
	enemy.polarity = 1
	await frames(3)
	check(player.hp == hp_after_contact and player.invulnerability > 0, "contact remains blocked just before 1.5 seconds")
	await frames(5)
	check(player.hp == hp_after_contact - T.CONTACT_DAMAGE, "sustained opposite contact damages again after protection expires")
	enemy.position.x += 400
	await frames(2) # Let the physics space publish the separated body before clearing protection.
	player.invulnerability = 0
	var guardian = boss_enemies()[0]
	guardian.position = player.position + Vector2(55, 0)
	guardian.polarity = player.polarity
	await frames(2)
	var before_boss: int = player.hp
	check(before_boss == hp_after_contact - T.CONTACT_DAMAGE, "same-color guardian contact causes no damage")
	guardian.polarity = 1 - player.polarity
	await frames(1)
	check(player.hp == before_boss - T.CONTACT_DAMAGE, "guardian contact uses its larger physical body and shared damage")
	guardian.position.x += 400
	player.invulnerability = 0
	player.hp = 70
	player.receive_hit(1 - player.polarity, 12)
	var display = game.effects.health_display
	var segments: Dictionary = display.bar_segments()
	check(display.visible and display.remaining == T.PLAYER_HP_DISPLAY_TIME, "damage immediately shows a timed HP bar")
	check(is_equal_approx(segments.green, 0.58 * T.PLAYER_HP_BAR_SIZE.x) and is_equal_approx(segments.red, 0.12 * T.PLAYER_HP_BAR_SIZE.x) and is_equal_approx(segments.gray, 0.30 * T.PLAYER_HP_BAR_SIZE.x), "green, red and gray reflect remaining, just lost and previously lost HP")
	var number: Dictionary = game.effects.player_hp_numbers[-1]
	check(number.text == "-12" and number.color == T.PLAYER_HP_COLORS.red, "player damage number is signed and red")
	check(number.at.y < player.position.y - T.PLAYER_SIZE.y / 2 and number.at.x < player.position.x, "player number starts above and to the left of the body")
	check(game.effects.damage_numbers.is_empty(), "player HP changes never enter yellow enemy damage numbers")
	var old_position: Vector2 = display.global_position
	player.position.x += 20
	await frames(2)
	check(absf(display.global_position.x - old_position.x - 20) < 0.2, "temporary HP bar follows player movement")
	game.show_menu("paused")
	var paused_remaining: float = display.remaining
	var paused_number_age: float = game.effects.player_hp_numbers[-1].age
	await frames(10)
	check(display.remaining == paused_remaining and game.effects.player_hp_numbers[-1].age == paused_number_age, "pause freezes player bar and numbers")
	game.resume_run()
	await frames(30)
	check(display.bar_segments().red < segments.red and display.bar_segments().gray > segments.gray, "recent red damage shrinks into the gray deficit")
	await frames(30)
	check(is_zero_approx(display.bar_segments().red) and game.effects.player_hp_numbers.is_empty(), "red damage finishes shrinking and number expires")
	check(player.heal(20) == 20 and player.hp == 78, "heal returns actual increase and changes HP")
	segments = display.bar_segments()
	check(display.visible and is_equal_approx(segments.green, 0.58 * T.PLAYER_HP_BAR_SIZE.x) and is_equal_approx(segments.healing, 0.20 * T.PLAYER_HP_BAR_SIZE.x) and is_zero_approx(segments.red) and is_equal_approx(segments.gray, 0.22 * T.PLAYER_HP_BAR_SIZE.x), "healing highlights exactly the new HP in bright green")
	check(game.effects.player_hp_numbers[-1].text == "+20" and game.effects.player_hp_numbers[-1].color == T.PLAYER_HP_COLORS.healing, "healing number is signed and green")
	game.ui.update_hud()
	check(game.ui.health_bar.value == 78, "top HP bar remains synchronized after healing")
	await frames(50)
	check(is_zero_approx(display.bar_segments().healing) and is_equal_approx(display.bar_segments().green, 0.78 * T.PLAYER_HP_BAR_SIZE.x), "healing highlight settles into the remaining HP")
	await frames(140)
	check(not display.visible and game.effects.player_hp_numbers.is_empty(), "bar and numbers disappear after a few seconds")
	check(player.heal(1000) == 22 and player.hp == 100 and game.effects.player_hp_numbers[-1].text == "+22", "healing clamps to maximum and displays only the actual gain")
	var count: int = game.effects.player_hp_numbers.size()
	check(player.heal(0) == 0 and player.heal(-5) == 0 and player.heal(20) == 0 and game.effects.player_hp_numbers.size() == count, "zero, negative and full-health healing create no popup")
	player.dead = true
	player.hp = 0
	check(player.heal(20) == 0 and player.hp == 0, "healing cannot revive a dead player")
	player.dead = false

func check_ui_language(node: Node) -> void:
	if node is Label or node is Button or node is LineEdit:
		var text: String = node.text
		var forbidden := ["SCORE", "TIME", "SEED", "PAUSED", "STAGE CLEAR", "TRY AGAIN", "WARDEN", "GUARDIANS", "MAP", "角度", "0°", "60°"]
		check(not forbidden.any(func(word): return text.contains(word)), "Japanese display: %s = %s" % [node.name, text])
	for child in node.get_children():
		check_ui_language(child)

func verify_ui_language() -> void:
	game.start_run(37)
	prepare_fixture()
	var guardian = boss_enemies()[0]
	guardian.position = game.player.position + Vector2(250, -36)
	game._update_exploration()
	game.ui.update_hud()
	check(game.ui.boss_label.visible and game.ui.boss_label.text.begins_with("ガーディアン"), "visible guardian has Japanese name")
	check(game.ui.objective_label.text.begins_with("ガーディアン"), "objective uses the same guardian name")
	for menu_state in ["title", "paused", "won", "lost"]:
		game.show_menu(menu_state)
		check_ui_language(game.ui)
		var expected: String = {"title": "CHROMA / SHIFT", "paused": "一時停止", "won": "クリア", "lost": "失敗"}[menu_state]
		check(game.ui.menu_title.text == expected, "menu title is localized: " + menu_state)
	game.open_key_settings()
	check_ui_language(game.ui.settings_panel)
	check(game.key_bindings.ACTIONS.aim_cycle == "射撃方向（前→上→下）", "key settings name describes the direction sequence")
	game.close_key_settings()
	game.resume_run()
	for index in range(3):
		game.player.aim_index = index
		game.ui.update_hud()
		check(game.ui.angle_label.text == "射撃方向 " + ["前", "上", "下"][index], "HUD names the selected direction")
	check(game.ui.controls_label.text.contains("L 射撃方向（前→上→下）") and game.ui.hint_label.text.contains("前→上→下"), "help and start hint describe the direction sequence")
