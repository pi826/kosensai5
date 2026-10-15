extends SceneTree
const T := preload("res://scripts/tuning.gd")
const Actor := preload("res://scripts/combatant.gd")
const Enemy := preload("res://scripts/enemy.gd")

class ObservedMain extends "res://scripts/main.gd":
	var result_menu_count := 0
	func show_menu(next_state: String) -> void:
		if next_state in ["won", "lost"]:
			result_menu_count += 1
		super.show_menu(next_state)

var checks := 0
var failures: Array[String] = []
var game: Node2D

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
	check(protected_actor.hp == T.PLAYER_HP - T.ENEMY_NORMAL_DAMAGE, "one-second player hit protection")
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
	raw_key.keycode = KEY_X
	raw_key.pressed = true
	Input.parse_input_event(raw_key)
	raw_key = InputEventKey.new()
	raw_key.keycode = KEY_X
	raw_key.pressed = false
	Input.parse_input_event(raw_key)
	Input.flush_buffered_events()
	check(game.player.polarity == 1, "short logical-key tap changes color before next physics tick")
	game.player.polarity = 0
	var initial_layout: Dictionary = game.stage.duplicate(true)
	var fixture_enemies := normal_enemies().slice(0, 3)
	var enemy = fixture_enemies[0]
	for actor in get_nodes_in_group("enemies"):
		actor.set_physics_process(false)
	for index in range(fixture_enemies.size()):
		fixture_enemies[index].room_id = 0
		fixture_enemies[index].position = Vector2([400, 640, 520][index], 618)
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
	game.player.gauge = 3
	tap("special")
	await frames(2)
	Input.action_release("special")
	check(game.player.gauge == 0 and game.projectiles.get_child_count() == 3, "partial gauge fires exactly stored number")
	clear_bullets()
	var second = fixture_enemies[1]
	var third = fixture_enemies[2]
	enemy.position = Vector2(430, 618)
	second.position = Vector2(640, 618)
	third.position = Vector2(520, 618)
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
	second.position.x = 2500
	third.position.x = 2700
	enemy.position = Vector2(430, 618)
	enemy.polarity = 0
	game.fire_special(game.player, 1)
	check(game.projectiles.get_child(0).target == enemy, "homing falls back to a same-color enemy when no opposite is visible")
	clear_bullets()
	enemy.position.x = 2500
	game.fire_special(game.player, 1)
	var untargeted = game.projectiles.get_child(0)
	check(untargeted.target == null and untargeted.direction.is_equal_approx(Vector2(game.player.facing, 0)), "special flies forward when no enemy is visible")
	clear_bullets()
	enemy.position.x = 430
	enemy.kind = "turret"
	enemy.gauge = 8
	enemy.wake_delay = 0
	enemy.was_visible = true
	enemy.shot_clock = 10
	enemy.set_physics_process(true)
	game.player.gauge = 0
	await frames(1)
	check(enemy.action == "windup_special", "full enemy gauge starts special warning")
	await frames(25)
	check(game.projectiles.get_child_count() == 0 and enemy.gauge == 8, "enemy special respects warning duration")
	await frames(30)
	check(enemy.gauge == 0 and game.projectiles.get_child_count() == 8, "enemy expends full gauge on eight homing shots")
	enemy.set_physics_process(false)
	await frames(160)
	check(game.player.gauge > 0 and game.player.hp == T.PLAYER_HP, "enemy homing special can be absorbed and recycled")
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
	# The hub's first upward platform remains reachable from its safety floor.
	game.player.position = Vector2(640, T.ROOM_FLOOR_Y - T.PLAYER_SIZE.y / 2)
	game.player.velocity = Vector2.ZERO
	await frames(3)
	tap("jump")
	await frames(38)
	check(game.player.is_on_floor() and absf(game.player.position.y - (512 - T.PLAYER_SIZE.y / 2)) < 0.5, "jump through underside and land on first vertical platform")
	game.start_run(37)
	await frames(3)
	check(game.stage == initial_layout and game.player.hp == T.PLAYER_HP and game.player.gauge == 0 and game.score == 0, "same-seed retry resets whole run")
	check(game.effects.damage_numbers.is_empty() and game.effects.damage_sequence == 0, "retry clears all damage numbers")
	check(game.total_enemies == normal_enemies().size() and game.total_enemies >= 6, "all generated normal enemies are instantiated")
	check(boss_enemies().size() == 3, "all three biome guardians are instantiated")
	var hidden = normal_enemies()[0]
	await frames(180)
	check(game.projectiles.get_child_count() == 0 and hidden.action == "idle" and not hidden.is_physics_processing(), "enemies in other rooms do not fire")
	# A boss warning retains the old collision color until it completes.
	var guardian = boss_enemies()[0]
	guardian.room_id = 0
	guardian.position = Vector2(780, 582)
	game._set_current_room(0)
	game.player.position = Vector2(560, 618)
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
	game.player.position = Vector2(game.boss.position.x + 220, 618)
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
		next_guardian.room_id = 0
		next_guardian.position = Vector2(780, 582)
		game._set_current_room(0)
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
	check(game.visited_rooms.size() == 1 and game.visited_rooms.has(0), "clear retry resets exploration to the hub")
	check(boss_enemies().size() == 3 and boss_enemies().all(func(actor): return actor.hp == T.BOSS_HP and not actor.dead), "clear retry revives all three guardians at full HP")
	var defeated_before_death = boss_enemies()[0]
	game._set_current_room(defeated_before_death.room_id)
	game.player.position = game.current_room().origin + Vector2(560, 618)
	for actor in get_nodes_in_group("enemies"):
		actor.set_physics_process(false)
	defeated_before_death.receive_hit(1 - defeated_before_death.polarity, T.BOSS_HP)
	await frames(3)
	check(game.defeated_bosses.size() == 1 and game.visited_rooms.size() == 2 and game.state == "playing", "death retry fixture includes a defeated guardian and explored room")
	game.player.gauge = 5
	game.effects.damage_numbers.clear()
	game.player.receive_hit(1 - game.player.polarity, T.PLAYER_HP)
	await frames(3)
	check(game.state == "lost" and game.ui.menu.visible, "player defeat opens retry screen")
	check(game.effects.damage_numbers.is_empty(), "enemy damage display does not add player popups")
	game.primary_action()
	await frames(3)
	check(game.state == "playing" and game.current_seed == 37 and game.player.hp == T.PLAYER_HP and game.player.gauge == 0 and game.score == 0, "death retry resets player and reuses seed")
	check(boss_enemies().size() == 3 and game.defeated_bosses.is_empty() and game.defeated_enemies.is_empty() and game.visited_rooms.size() == 1 and game.visited_rooms.has(0), "death retry revives guardians and resets exploration")
	await verify_two_hit_enemies()
	await verify_guardian_orders()
	game.queue_free()
	await frames(2)
	var report := {"checks": checks, "failures": failures, "elapsed_ms": Time.get_ticks_msec() - begun}
	DirAccess.make_dir_recursive_absolute("res://builds/qa/phase2")
	var file := FileAccess.open("res://builds/qa/phase2/combat_results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("TEST RESULT: ", checks, " checks, ", failures.size(), " failures (", report.elapsed_ms, " ms)")
	quit(0 if failures.is_empty() else 1)

func normal_enemies() -> Array:
	return get_nodes_in_group("enemies").filter(func(actor): return actor.kind != "boss" and actor.get_parent() == game.world)

func boss_enemies() -> Array:
	return get_nodes_in_group("enemies").filter(func(actor): return actor.kind == "boss" and actor.get_parent() == game.world and not actor.is_queued_for_deletion())

func clear_bullets() -> void:
	for bullet in game.projectiles.get_children():
		bullet.free()

func two_hit_fixture(kind: String, color: int):
	game.start_run(37)
	game.player.set_physics_process(false)
	for actor in get_nodes_in_group("enemies"):
		actor.set_physics_process(false)
	var enemy := Enemy.new()
	enemy.game = game
	enemy.kind = kind
	enemy.polarity = color
	enemy.room_id = game.current_room_id
	enemy.spawn_id = "two_hit_%s_%d" % [kind, color]
	enemy.position = Vector2(400, T.ROOM_FLOOR_Y - T.ENEMY_SIZE.y / 2)
	game.world.add_child(enemy)
	enemy.set_physics_process(false)
	game.player.polarity = 1 - color
	game.player.facing = 1
	return enemy

func verify_two_hit_enemies() -> void:
	for kind in ["turret", "walker", "shifter"]:
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
