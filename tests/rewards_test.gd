extends "res://tests/test_tree.gd"
const Main := preload("res://scripts/main.gd")
const T := preload("res://scripts/tuning.gd")
const S := preload("res://scripts/sector_generator.gd")
const Stream := preload("res://scripts/sector_stream.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Job := preload("res://scripts/sector_job.gd")
const Support := preload("res://tests/stream_test_support.gd")
var game: Node2D
var checks := 0
var failures: Array[String] = []

func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)
func frames(n: int = 1):
	for i in range(n):
		test_progress()
		await physics_frame
		test_progress()
		await process_frame
func freeze():
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	for e in get_nodes_in_group("enemies"): e.set_physics_process(false)
	for h in get_nodes_in_group("hearts"): h.set_physics_process(false)
func reset():
	game.start_run(37)
	freeze()
func enemies(at: Vector2i = Vector2i.ZERO) -> Array:
	return get_nodes_in_group("enemies").filter(func(e): return e.get_parent() == game.world and e.get_meta("sector", Vector2i(999,999)) == at and not e.dead and not e.is_queued_for_deletion())
func clear_bullets():
	for b in game.projectiles.get_children(): b.free()
func heart(id: String) -> Node2D:
	for h in get_nodes_in_group("hearts"):
		if h.get_parent() == game.world and h.spawn.id == id and not h.is_queued_for_deletion(): return h
	return null
func enemy(id: String) -> Node2D:
	for e in get_nodes_in_group("enemies"):
		if e.get_parent() == game.world and e.spawn_id == id and not e.dead and not e.is_queued_for_deletion(): return e
	return null
func offscreen():
	game.camera.position = Vector2(-100000, -100000)
	game.player.position = game.camera.position
func next_success(record: Dictionary, first: int = 0) -> int:
	for attempt in range(first, first + 1000):
		if Stream.respawn_roll(game.current_seed, record.id, record.stamp, attempt) < T.RESPAWN_PROBABILITY: return attempt
	return -1
func time_for(record: Dictionary, attempt: int) -> float:
	return record.removed_at + T.RESPAWN_MIN_TIME + attempt * T.RESPAWN_INTERVAL

func wall_at(e: Node2D) -> Rect2:
	return Rect2(floorf(e.position.x / 32) * 32, e.position.y + 22 - 64, 32, 64)

func respawn_enemy() -> Node2D:
	# Generated enemies often stand on protected jump steps. Use an actual,
	# legal builder-wall site as the original position for this combat fixture.
	var site := clear_wall_site()
	if not site.has_area(): return null
	var e = enemies()[0]
	e.position = Vector2(site.get_center().x, site.end.y - 22)
	e.patrol = Vector2(e.position.x, e.position.x)
	for spawn: Dictionary in game.stream.loaded[Vector2i.ZERO].spawns:
		if spawn.id == e.spawn_id:
			spawn.position = e.position
			spawn.patrol = e.patrol
	return e

func clear_wall_site() -> Rect2:
	for r: Rect2 in game.stream.loaded[Vector2i.ZERO].solids:
		if r.size.y == 16: continue
		for x in range(int(r.position.x) + 32, int(r.end.x) - 32, 32):
			var site := Rect2(x, r.position.y - 64, 32, 64)
			var body := Rect2(x + 16 - T.ENEMY_SIZE.x / 2, r.position.y - T.ENEMY_SIZE.y, T.ENEMY_SIZE.x, T.ENEMY_SIZE.y)
			if game.terrain.can_place_wall(site, 99) and Job.cells(body).all(func(c): return not game.terrain.occupied.has(c)): return site
	return Rect2()

func stocks():
	reset()
	var p = game.player
	for i in range(T.ABSORPTIONS_PER_CHARGE - 1):
		p.receive_hit(p.polarity, 999)
		check(p.gauge == i + 1 and p.homing_charges == 0 and p.hp == 100, "absorption progresses without damage")
	p.receive_hit(p.polarity, 999)
	check(p.homing_charges == 1 and p.gauge == 0, "four absorptions produce one stock")
	check(game.effects.charge_numbers.back().text == "誘導弾 +1", "absorption stock popup")
	for i in range(100): p.receive_hit(p.polarity, 999)
	check(p.homing_charges == 5 and p.gauge == 4, "cap is five with saturated absorption meter")
	var popup_count: int = game.effects.charge_numbers.size()
	p.receive_hit(p.polarity, 1)
	check(p.gauge == 4 and game.effects.charge_numbers.size() == popup_count, "full stock and meter stop without duplicate popup")
	check(p.add_homing_charges(100) == 0 and p.add_homing_charges(-1) == 0, "reward cannot exceed cap or subtract stocks")
	p.launch_homing()
	check(p.homing_charges == 4 and p.gauge == 4 and game.projectiles.get_child_count() == 4, "one key consumes one stock and retains saturated meter")
	clear_bullets()
	p.receive_hit(p.polarity, 1)
	check(p.homing_charges == 5 and p.gauge == 0, "next absorption converts the retained full meter")
	p.homing_charges = 0
	check(not p.launch_homing() and game.projectiles.get_child_count() == 0, "zero stock produces no missiles")
	var targets: Array = []
	for i in range(6):
		var e := Enemy.new()
		e.game = game
		e.polarity = 1 - p.polarity
		e.position = p.position + Vector2(60 + i * 65, -100)
		e.patrol = Vector2(e.position.x, e.position.x)
		game.world.add_child(e)
		e.set_physics_process(false)
		targets.append(e)
	p.homing_charges = 2
	p.gauge = 2
	game._update_lock_marks()
	check(game.lock_on_targets().size() == 4 and targets.filter(func(e): return e.lock_marked).size() == 4, "marks show four targets for the next volley")
	p.launch_homing()
	var counts := []
	for e in targets: counts.append(game.projectiles.get_children().filter(func(b): return b.target == e).size())
	check(game.projectiles.get_child_count() == 4 and counts.max() - counts.min() <= 1, "simultaneous volley assigns missiles evenly")
	check(game.projectiles.get_children().all(func(b): return b.polarity == p.polarity), "volley stores launch color")
	p.homing_charges = 0
	game._update_lock_marks()
	check(game.lock_on_targets().size() == 4, "flying targets stay marked with zero stock")
	# Change the next volley's candidates without changing the existing missiles.
	for target in targets: target.polarity = p.polarity
	targets[4].polarity = 1 - p.polarity
	p.homing_charges = 1
	check(game.lock_on_targets().size() == 5 and game.lock_on_targets().has(targets[4]), "marks are union of next volley and flying targets across color changes")
	p.homing_charges = 1
	clear_bullets()
	game.ui.update_hud()
	check(game.ui.gauge_label.text == "誘導弾 1/5  吸収2/4" and game.ui.gauge_bar.value == 2 and game.ui.gauge_bar.max_value == 4, "headless HUD fallback shows stock counts and separate absorption progress")
	for e in targets: e.free()
	p.homing_charges = 0
	var e = enemies()[0]
	var id: String = e.spawn_id
	e.receive_hit(1 - e.polarity, T.ENEMY_HP)
	game.actor_defeated(e)
	check(p.homing_charges == 1 and game.kills == 1 and game.score == T.ENEMY_SCORE, "normal defeat rewards one stock once")
	check(game.stream.missing.has(id) and game.effects.charge_numbers.back().text == "誘導弾 +1", "defeat records disappearance and popup")
	var at: Vector2i = S.guardian_sectors(37)[0]
	var data := Job.world_data(S.generate(37, at))
	var spawn: Dictionary = data.spawns.filter(func(s): return s.kind == "boss")[0]
	game.stream._spawn(spawn)
	var boss = enemy(spawn.id)
	boss.receive_hit(1 - boss.polarity, T.BOSS_HP)
	game.actor_defeated(boss)
	check(p.homing_charges == 3 and game.score == T.ENEMY_SCORE + T.BOSS_SCORE, "guardian rewards two stocks once")
	check(not game.stream.missing.has(spawn.id), "guardian never enters normal respawn schedule")
	await frames()

func hearts_and_boxes():
	reset()
	var hearts := get_nodes_in_group("hearts").filter(func(h): return h.get_parent() == game.world)
	check(not hearts.is_empty(), "initial neighbourhood contains hearts")
	var h = hearts[0]
	var id: String = h.spawn.id
	game.player.position = h.position
	check(not h.try_collect() and game.player.hp == 100 and not game.stream.missing.has(id), "full HP leaves heart untouched")
	game.player.hp = 50
	check(h.try_collect() and game.player.hp == 80 and game.stream.missing.has(id), "touch heals thirty and records collected heart")
	check(not h.try_collect(), "one heart cannot be collected twice in the same frame")
	check(game.effects.player_hp_numbers.back().text == "+30" and game.effects.health_display.remaining > 0, "heart uses HP popup and health bar")
	await frames()
	var second = hearts[1]
	game.player.position = second.position
	game.player.hp = 90
	check(second.try_collect() and game.player.hp == 100 and game.effects.player_hp_numbers.back().text == "+10", "heart clamps HP and displays actual healing")
	await frames()
	# Real swept player shots must trigger the reward through the terrain signal.
	for guided in [false, true]:
		reset()
		var rect: Rect2 = game.stream.loaded[Vector2i.ZERO].breakables[0]
		game.player.position = rect.get_center() - Vector2(64, 0)
		game.player.hp = 50
		game._update_camera(0, true)
		var hits := 1 if guided else T.TERRAIN_HP
		for i in range(hits):
			var b = game.spawn_bullet(game.player, Vector2.RIGHT, guided)
			b.position = rect.get_center() - Vector2(40, 0)
			if guided: b.target = null
			await frames(8)
		check(game.player.hp == 56 and game.stream.missing.has(Stream.block_id(rect)), "real player projectile destroys box and heals six guided=%s" % guided)
		check(game.effects.player_hp_numbers.back().text == "+6", "box healing popup guided=%s" % guided)
		clear_bullets()
	reset()
	var rect: Rect2 = game.stream.loaded[Vector2i.ZERO].breakables[0]
	game.player.hp = 50
	game.terrain.explode(rect.get_center())
	check(game.player.hp == 50 and game.stream.missing.has(Stream.block_id(rect)), "enemy explosion destroys box without healing")
	game.terrain.damage_at(rect.get_center(), 99, true)
	check(game.player.hp == 50, "destroyed box never heals twice")
	game.player.position = Vector2(-100000, -100000)
	var wall := clear_wall_site()
	var wall_id: int = game.terrain.place_wall(wall, 99)
	check(wall_id >= 0, "temporary wall fixture installs")
	game.terrain.damage_at(wall.get_center(), 99, true)
	check(not game.terrain.walls.has(wall_id) and game.player.hp == 50 and not game.stream.missing.has(Stream.block_id(wall)), "temporary wall destruction never heals or respawns")
	await frames()

func respawns():
	reset()
	var e = respawn_enemy()
	check(is_instance_valid(e), "respawn fixture has valid installed wall site at original position")
	var id: String = e.spawn_id
	var spawn_position: Vector2 = e.position
	e.receive_hit(1 - e.polarity, 99)
	await frames()
	var record: Dictionary = game.stream.missing[id]
	var success := next_success(record)
	check(success >= 0, "deterministic schedule contains successful trial")
	offscreen()
	game.elapsed = record.removed_at + T.RESPAWN_MIN_TIME - 0.001
	game.stream.update_rewards()
	check(game.stream.missing.has(id) and enemy(id) == null, "no revival before minimum delay")
	game.camera.position = record.area.get_center()
	game.elapsed = time_for(record, success)
	game.stream.update_rewards()
	check(enemy(id) == null and record.next_attempt == success + 1, "visible patrol area suppresses revival and consumes opportunity")
	success = next_success(record, record.next_attempt)
	game.camera.position = Vector2(record.area.end.x + T.VIEW_SIZE.x / 2 + T.RESPAWN_VIEW_MARGIN / 2, record.area.get_center().y)
	game.elapsed = time_for(record, success)
	game.stream.update_rewards()
	check(not game.view_rect().intersects(record.area) and enemy(id) == null, "expanded camera margin prevents just-offscreen revival")
	success = next_success(record, record.next_attempt)
	offscreen()
	game.player.position = record.area.get_center()
	game.elapsed = time_for(record, success)
	game.stream.update_rewards()
	check(enemy(id) == null, "overlapping player prevents revival even when camera is elsewhere")
	success = next_success(record, record.next_attempt)
	offscreen()
	var obstruction := wall_at(e) if is_instance_valid(e) else Rect2(floorf(spawn_position.x / 32) * 32, spawn_position.y + 22 - 64, 32, 64)
	var wall_id: int = game.terrain.place_wall(obstruction, 99)
	game.elapsed = time_for(record, success)
	game.stream.update_rewards()
	check(enemy(id) == null and wall_id >= 0, "installed wall prevents revival")
	game.terrain.remove_wall(wall_id)
	var blocker = enemies()[0]
	var old_position: Vector2 = blocker.position
	blocker.position = record.area.get_center()
	success = next_success(record, record.next_attempt)
	game.elapsed = time_for(record, success)
	game.stream.update_rewards()
	check(enemy(id) == null, "enemy body prevents revival")
	blocker.position = old_position
	success = next_success(record, record.next_attempt)
	game.elapsed = time_for(record, success) - 0.001
	game.stream.update_rewards()
	check(enemy(id) == null, "no roll before the next discrete opportunity")
	game.elapsed += 0.001
	game.stream.update_rewards()
	e = enemy(id)
	check(is_instance_valid(e) and e.position == spawn_position and e.hp == T.ENEMY_HP and e.gauge == 0, "offscreen revival restores original position full HP zero gauge")
	check(e.action == "idle" and not e.was_visible and e.wake_delay == T.ENEMY_WAKE_DELAY, "revived enemy starts with normal screen-entry wait")
	check(not game.stream.missing.has(id) and not game.defeated_enemies.has(id), "revived enemy clears absence and duplicate defeat records")
	e.set_physics_process(false)
	var kills: int = game.kills
	var score: int = game.score
	var stocks: int = game.player.homing_charges
	e.receive_hit(1 - e.polarity, 99)
	check(game.kills == kills + 1 and game.score == score + T.ENEMY_SCORE and game.player.homing_charges == stocks + 1, "revived enemy awards kills score and stock again")
	await frames()
	for attempt in range(40):
		var a := Stream.respawn_roll(37, id, record.stamp, attempt)
		check(a == Stream.respawn_roll(37, id, record.stamp, attempt) and a >= 0 and a < 1, "respawn random roll is reproducible attempt=%d" % attempt)
	check(Stream.respawn_roll(37, id, 0, 0) != Stream.respawn_roll(38, id, 0, 0) and Stream.respawn_roll(37, id, 0, 0) != Stream.respawn_roll(37, id, 1, 0), "seed and disappearance time alter random schedule")
	await unloaded_state()

func unloaded_state():
	reset()
	var at := Vector2i.ZERO
	# Select one local heart; a different fixed seed is allowed if sector zero has none.
	for seed_value in range(37, 50):
		if not game.stream.loaded[at].hearts.is_empty(): break
		game.start_run(seed_value + 1)
		freeze()
	var data: Dictionary = game.stream.loaded[at]
	check(not data.hearts.is_empty(), "unload fixture has local heart")
	var hs: Dictionary = data.hearts[0]
	game.player.position = hs.position
	game.player.hp = 1
	check(heart(hs.id).try_collect(), "collect local heart before unload")
	var e = enemies()[0]
	var enemy_id: String = e.spawn_id
	e.receive_hit(1 - e.polarity, 99)
	var rect: Rect2 = data.breakables[0]
	game.terrain.damage_at(rect.get_center(), 99, true)
	var surface: Rect2 = data.erodible_surfaces[-1]
	game.terrain.explode(surface.get_center(), 20)
	await frames()
	game.stream._unload(at)
	check(game.stream.states[at].blocks[rect.position] == 0 and game.stream.missing.has(hs.id) and game.defeated_enemies.has(enemy_id), "unload retains all three missing categories")
	var destroyed: Dictionary = game.stream.states[at].destroyed.duplicate()
	# Reload before minimum delay: none may return.
	check(await Support.ready(self, game, T.SECTOR_START), "reload sector before minimum delay")
	freeze()
	check(heart(hs.id) == null and enemy(enemy_id) == null and game.terrain.snapshot(at).blocks[rect.position] == 0, "early reload keeps heart enemy and box absent")
	game.stream._unload(at)
	offscreen()
	var survivor_id: String = game.stream.states[at].actors.keys()[0]
	var saved_actor: Dictionary = game.stream.states[at].actors[survivor_id]
	var survivor_position: Vector2 = saved_actor.position
	saved_actor.position = hs.position
	var heart_record: Dictionary = game.stream.missing[hs.id]
	game.elapsed = time_for(heart_record, next_success(heart_record))
	game.stream.update_rewards()
	check(game.stream.missing.has(hs.id), "saved enemy body prevents heart revival while unloaded")
	saved_actor.position = survivor_position
	var target_time := 0.0
	for id: String in [hs.id, enemy_id, Stream.block_id(rect)]:
		if not game.stream.missing.has(id): continue
		var record: Dictionary = game.stream.missing[id]
		target_time = maxf(target_time, time_for(record, next_success(record, record.next_attempt)))
	game.elapsed = target_time
	game.stream.update_rewards()
	check(not game.stream.missing.has(hs.id) and not game.defeated_enemies.has(enemy_id) and game.stream.states[at].blocks[rect.position] == T.TERRAIN_HP, "elapsed unloaded time revives all three from deterministic trials")
	check(await Support.ready(self, game, T.SECTOR_START), "reload after elapsed unloaded time")
	freeze()
	check(heart(hs.id) != null and enemy(enemy_id) != null and game.terrain.snapshot(at).blocks[rect.position] == T.TERRAIN_HP, "reloaded sector materializes revived heart enemy and full durability box")
	check(enemy(enemy_id).hp == T.ENEMY_HP and enemy(enemy_id).gauge == 0, "unloaded revived enemy starts fresh")
	check(game.terrain.snapshot(at).destroyed == destroyed, "erosion never respawns")
	# The rebuilt block's cells must also belong to the sector after another unload.
	game.stream._unload(at)
	check(Job.cells(rect).all(func(c): return not game.terrain.occupied.has(c)), "restored box cells disappear on the next unload")
	check(await Support.ready(self, game, T.SECTOR_START), "second reload keeps the restored full box")
	freeze()
	# Exercise a loaded heart and block's camera exclusion separately.
	for id: String in [hs.id, Stream.block_id(rect)]:
		if id == hs.id:
			game.player.position = hs.position
			game.player.hp = 1
			heart(hs.id).try_collect()
		else: game.terrain.damage_at(rect.get_center(), 99, true)
		await frames()
		var record: Dictionary = game.stream.missing[id]
		game.camera.position = record.area.get_center()
		game.player.position = Vector2(-100000, -100000)
		game.elapsed = time_for(record, next_success(record))
		game.stream.update_rewards()
		check(game.stream.missing.has(id), "visible heart/box does not return " + id)
		offscreen()
		game.elapsed = time_for(record, next_success(record, record.next_attempt))
		game.stream.update_rewards()
		check(not game.stream.missing.has(id), "offscreen heart/box returns " + id)
	game.player.receive_hit(1 - game.player.polarity, 999)
	await frames(2)
	check(game.state == "lost", "death opens retry")
	game.primary_action()
	freeze()
	check(game.stream.missing.is_empty() and game.stream.states.is_empty() and game.defeated_enemies.is_empty() and game.kills == 0 and game.score == 0 and game.player.homing_charges == 0 and game.player.gauge == 0, "retry resets all reward/respawn state")
	check(game.terrain.destroyed_cells.is_empty() and game.terrain.breakables.values().all(func(b): return b.hp == T.TERRAIN_HP), "retry restores original terrain and full boxes")

func run():
	game = Main.new()
	game.controls_path = "res://builds/qa/rewards/controls.cfg"
	root.add_child(game)
	await stocks()
	await hearts_and_boxes()
	await respawns()
	game.free()
	DirAccess.make_dir_recursive_absolute("res://builds/qa/rewards")
	FileAccess.open("res://builds/qa/rewards/rewards_results.json", FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures.size(), "failure_messages": failures}, "\t"))
	print("REWARDS TEST: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
