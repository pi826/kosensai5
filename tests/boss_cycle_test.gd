extends "res://tests/test_tree.gd"
const Main := preload("res://scripts/main.gd")
const T := preload("res://scripts/tuning.gd")
const S := preload("res://scripts/sector_generator.gd")
const G := preload("res://scripts/stage_generator.gd")
const Job := preload("res://scripts/sector_job.gd")
const Cycle := preload("res://scripts/boss_cycle.gd")
const Stream := preload("res://scripts/sector_stream.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Support := preload("res://tests/stream_test_support.gd")
const Driver := preload("res://tests/stream_driver.gd")
class ObservedMain extends "res://scripts/main.gd":
	var result_menus := 0
	func show_menu(next_state: String) -> void:
		if next_state in ["won", "lost"]: result_menus += 1
		super.show_menu(next_state)
var game: Node2D
var checks := 0
var failures: Array[String] = []
var travel := {}
var unloaded_boss_spawns := 0

func _initialize(): call_deferred("run")
func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)
	return ok
func frames(n: int = 1):
	for i in range(n):
		for b in game.projectiles.get_children(): b.set_physics_process(false)
		test_progress()
		await physics_frame
		test_progress()
		await process_frame
func freeze():
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	for e in get_nodes_in_group("enemies"): e.set_physics_process(false)
func clear_bullets():
	for b in game.projectiles.get_children(): b.free()
func actor(id: int) -> Node2D:
	for e in get_nodes_in_group("enemies"):
		if e.get_parent() == game.world and e.kind == "boss" and e.boss_id == id and not e.dead and not e.is_queued_for_deletion(): return e
	return null
func settle():
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		var pending: RefCounted = game.boss_cycle.selection
		if pending != null and WorkerThreadPool.is_task_completed(pending.task_id):
			for site: Dictionary in pending.result:
				if not game.stream.loaded.has(site.sector): unloaded_boss_spawns += 1
		game.boss_cycle.service()
		if game.boss_cycle.selection == null: return
		await frames()
		OS.delay_msec(1)
	check(false, "boss selection completed within watchdog")
func load_boss(record: Dictionary, player_at: Vector2 = Vector2.INF) -> Node2D:
	var point: Vector2 = game.boss_cycle.world_record(record).position if player_at == Vector2.INF else player_at
	check(await Support.ready(self, game, point), "boss sector and its neighbours stream in")
	freeze()
	await frames(2)
	var e = actor(record.boss_id)
	check(is_instance_valid(e), "live boss installed from run record")
	return e
func defeat(e: Node2D):
	if not check(is_instance_valid(e), "boss exists before defeat"): return
	e.receive_hit(1 - e.polarity, 9999)
	game.actor_defeated(e)
	await frames(2)
	await settle()
func current(role: String) -> Array:
	return game.boss_cycle.records.values().filter(func(r): return r.role == role and r.alive)

func selection_checks():
	for seed_value in [1, 37, 2026, -17]:
		var excluded := S.guardian_sectors(seed_value)
		for at: Vector2i in excluded:
			var initial := Job.world_data(S.generate(seed_value,at))
			var spawn: Dictionary = initial.spawns.filter(func(s): return s.kind == "boss")[0]
			var room: Dictionary = initial.chambers[spawn.chamber_id]
			var zone := G.arena_zone(room.rect,room.arena_tiers)
			var lane := Cycle.roam_rect(initial,zone,"guardian",Vector2(zone.get_center().x,room.rect.end.y-T.ARENA_BOSS_CENTER_HEIGHT),true)
			check(lane.has_area() and zone.encloses(lane.grow_individual(T.BOSS_SIZE.x/2,T.BOSS_SIZE.y/2,T.BOSS_SIZE.x/2,T.BOSS_SIZE.y/2)), "initial guardian whole roaming body stays in arena zone")
		var center := Vector2i(-2, 3)
		var roles: Array[String] = ["guardian", "guardian", "guardian"]
		var sites := Cycle.select_sites(seed_value, center, 2, roles, excluded)
		check(sites.size() == 3, "three legal distinct-region sites seed %d" % seed_value)
		check(sites == Cycle.select_sites(seed_value, center, 2, roles, excluded), "placement reproducible seed %d" % seed_value)
		var regions := {}
		for site: Dictionary in sites:
			regions[site.region] = true
			var data := Job.world_data(S.generate(seed_value, site.sector))
			check(Stream.distance(center, site.sector) in range(2, 6) and not excluded.has(site.sector), "ring 2..5 and no old sector")
			check(data.chambers[site.chamber_id].kind == "boss" and S.is_arena_sector(seed_value,site.sector), "dedicated arena selected")
			check(site.arena.encloses(site.roam.grow_individual(T.BOSS_SIZE.x/2, T.BOSS_SIZE.y/2, T.BOSS_SIZE.x/2, T.BOSS_SIZE.y/2)), "whole roaming body stays inside chamber")
		check(regions.size() == 3, "revivals occupy all three regions")
		for role: String in ["final", "secret"]:
			var singles: Array[String] = [role]
			var single := Cycle.select_sites(seed_value, center, 1, singles, excluded)
			check(single.size() == 1 and single == Cycle.select_sites(seed_value, center, 1, singles, excluded), "reproducible " + role)

func movement_and_attack(e: Node2D):
	clear_bullets()
	e.signature_clock = 10000
	var role: String = e.boss_role
	var data: Dictionary = game.stream.loaded[e.get_meta("sector")]
	check(e.max_hp == Cycle.hp_for(role) and e.body_size == Cycle.size_for(role), role + " size and HP")
	check(e.roam.has_area(), role + " has an obstacle-free movement range")
	game.player.position = e.position + Vector2(230, 10)
	game.player.invulnerability = 10000
	game._update_camera(0, true)
	game._update_exploration()
	game.ui.update_hud()
	check(game.ui.boss_label.text.begins_with(Cycle.name_for(role)) and game.ui.boss_hp_label.text == str(e.hp), role + " name and integer HP in HUD")
	e.set_physics_process(true)
	e.shot_clock = 0
	e.switch_clock = 100
	e.was_visible = false
	var origin: Vector2 = e.position
	await frames(30)
	check(game.projectiles.get_child_count() == 0 and e.wake_delay > 0, role + " wake delay prevents immediate firing")
	var warnings := 0
	var inside := true
	var clear := true
	var warning_motion := false
	var last: Vector2 = e.position
	for tick in range(600):
		await frames()
		var body := Rect2(e.position - e.body_size/2, e.body_size).grow(-0.1)
		inside = inside and e.arena.encloses(body)
		clear = clear and not (data.solids.filter(func(r): return r.size.y != 16) + data.breakables).any(func(r): return r.intersects(body))
		if e.action.begins_with("windup"):
			warnings += 1
			if last.distance_to(e.position) > 0.1: warning_motion = true
		last = e.position
	check(origin.distance_to(e.position) > 10 and e.move_clock > 9, role + " moves for real physics frames")
	check(inside and clear, role + " never escapes or overlaps rock shelves or boxes")
	check(warnings > 0 and warning_motion and game.projectiles.get_child_count() > 0, role + " moves during telegraphed attacks")
	e.set_physics_process(false)
	clear_bullets()
	for pattern in [0, 1]:
		e.pattern = pattern
		e.action = "idle"
		e.wake_delay = 0
		e.was_visible = true
		e.switch_clock = 100
		e.shot_clock = 0
		# The movement check can leave the boss beyond the test camera.
		game.player.position = e.position + Vector2(230, 10)
		game.camera.position = e.position
		e.set_physics_process(true)
		await frames()
		check(e.action == "windup_shot" and game.projectiles.get_child_count() == 0, role + " shot is warned")
		await frames(29)
		e.set_physics_process(false)
		var boss_color: int = e.polarity
		var fan_count := 7 if role == "secret" else 5
		var first: Array = game.projectiles.get_children()
		var guided := 1 if role != "guardian" and (pattern == 1 or role == "secret") else 0
		check(first.size() == fan_count + guided, role + " first volley pattern %d" % pattern)
		check(first.all(func(b): return b.polarity == boss_color), role + " first volley uses boss color pattern %d" % pattern)
		check(first.filter(func(b): return b.homing).size() == guided, role + " guided mixture")
		e.set_physics_process(true)
		await frames(ceili(T.BOSS_SECOND_VOLLEY_DELAY*60)+2)
		e.set_physics_process(false)
		var all_bullets: Array = game.projectiles.get_children()
		var second: Array = all_bullets.slice(first.size())
		var expects_second: bool = role != "guardian" or pattern == 1
		check(second.size() == (fan_count if expects_second else 0), role + " second volley pattern %d" % pattern)
		check(second.all(func(b): return not b.homing and b.polarity == 1-boss_color), role + " second volley opposite color without homing pattern %d" % pattern)
		if expects_second:
			check(e.action == "idle", role + " second volley returns to idle pattern %d" % pattern)
		clear_bullets()
	e.action = "idle"
	e.gauge = T.GAUGE_CAPACITY
	e._choose_attack(0)
	check(e.action == "windup_special", role + " absorbed full gauge announces guided volley")
	e._complete_action()
	check(game.projectiles.get_child_count() == T.GAUGE_CAPACITY, role + " full gauge fires guided volley")
	clear_bullets()
	e.action = "idle"
	e.switch_clock = 0
	e._choose_attack(0)
	var old_color: int = e.polarity
	check(e.action == "windup_switch" and e.polarity == old_color, role + " color change is telegraphed")
	e._complete_action()
	check(e.polarity == 1-old_color, role + " changes color after warning")
	game.player.position = e.arena.position - Vector2(64, 64)
	game.camera.position = e.position + Vector2(5000, 5000)
	e.shot_clock = 0
	e.set_physics_process(true)
	await frames(180)
	e.set_physics_process(false)
	check(game.projectiles.get_child_count() == 0 and e.action == "idle" and not e.was_visible, role + " offscreen cannot attack")
	game.player.position = e.position
	game.player.polarity = e.polarity
	game.player.invulnerability = 0
	await frames(2)
	var hp: int = game.player.hp
	game.player._check_enemy_contact()
	check(game.player.hp == hp, role + " same-color body contact is safe")
	game.player.polarity = 1-e.polarity
	game.player._check_enemy_contact()
	check(game.player.hp == hp-T.CONTACT_DAMAGE and game.player.invulnerability == T.INVULNERABILITY, role + " opposite body contact and invulnerability")
	game.player.hp = T.PLAYER_HP
	game.player.position += Vector2(250, 0)

func persistence(record: Dictionary):
	var e = actor(record.boss_id)
	e.hp = 17
	e.gauge = 3
	var position: Vector2 = e.position
	var clock: float = e.move_clock
	var local_position: Vector2 = position - game.stream.sector_offset(record.sector)
	# Keep the player outside the arena so streaming the sector back in does not
	# consume the restored wake delay.
	var outside: Vector2 = e.arena.position - Vector2(200, 200)
	game.stream._unload(record.sector)
	var restored_position: Vector2 = game.boss_cycle.world_record(record).position
	# World/local conversion uses float32 vectors. Require the exact stored local
	# coordinates and restored representation, plus a separate subpixel bound.
	check(record.hp == 17 and record.position == local_position and record.saved.position == local_position and record.saved.gauge == 3, "unload captures boss HP position and gauge in run state")
	check(restored_position.distance_to(position) < 0.001, "boss world/local coordinate roundtrip stays within 0.001px")
	e = await load_boss(record, outside)
	check(e.hp == 17 and e.gauge == 3 and e.position == restored_position and e.move_clock == clock and e.wake_delay == T.ENEMY_WAKE_DELAY, "reload preserves live boss and restores wake delay")
	e.hp = e.max_hp

func route_to(record: Dictionary):
	# The route planner's small test graph uses the original frame.
	record = record.duplicate(true)
	record.position += Vector2(record.sector) * T.SECTOR_SIZE
	record.arena.position += Vector2(record.sector) * T.SECTOR_SIZE
	var source: Vector2i = game.stream.sector_at(game.player.position)
	var source_data := S.generate(game.current_seed, source)
	var sectors := {source: source_data}
	var source_spawn: Dictionary = source_data.spawns.filter(func(s): return s.kind == "boss")[0]
	var start: Vector2 = source_spawn.position + Vector2(source)*T.SECTOR_SIZE + Vector2(0,T.BOSS_SIZE.y/2-22)
	var at := source
	while at != record.sector:
		if at.x != record.sector.x: at.x += signi(record.sector.x-at.x)
		else: at.y += signi(record.sector.y-at.y)
		sectors[at] = S.generate(game.current_seed, at)
	var graph := S.navigation_graph(sectors.values())
	var origin := G.node_at(graph, start)
	var target := -1
	var endpoint := Vector2.ZERO
	var nearest := INF
	for i in range(graph.nodes.size()):
		var floor_rect: Rect2 = graph.nodes[i]
		var p := Vector2(clampf(record.position.x, floor_rect.position.x+16, floor_rect.end.x-16), floor_rect.position.y-22)
		if record.arena.encloses(Rect2(p-T.PLAYER_SIZE/2,T.PLAYER_SIZE)) and p.distance_to(record.position) < nearest:
			nearest = p.distance_to(record.position)
			target = i
			endpoint = p
	var commands := G.path_steps(graph, origin, target, endpoint)
	check(origin >= 0 and target >= 0 and not commands.is_empty(), "real navigation graph connects last guardian to final-boss chamber")
	check(not G.path_steps(graph, target, origin, start).is_empty(), "boss chamber also has a return route")
	check(await Support.ready(self, game, start-Vector2(game.origin_sector)*T.SECTOR_SIZE), "route starts on the last guardian chamber's standing floor")
	Support.release(self, game)
	var driver := Driver.new()
	driver.tree = self
	driver.game = game
	var world_id: int = game.world.get_instance_id()
	var arrived := false
	var replans: Array[String] = []
	# A jump can land on a higher intervening shelf. Replan from the actual
	# supported position; never teleport or modify geometry to satisfy a route.
	for attempt in range(8):
		if await driver.follow(commands):
			arrived = true
			break
		replans.append(driver.error)
		var actual := G.node_at(graph,driver.point())
		if actual < 0: break
		commands = G.path_steps(graph,actual,target,endpoint)
		if commands.is_empty(): break
		print("BOSS ROUTE REPLAN from ",game.player.position,": ",driver.error)
	check(arrived, "actual movement follows generated boss route: " + driver.error)
	check(driver.point().distance_to(endpoint) < 8 and record.arena.has_point(driver.point()), "player physically arrives inside final-boss chamber")
	check(driver.max_player_step < 25 and game.world.get_instance_id() == world_id and driver.incomplete_views == 0, "boss route uses continuous loaded terrain without warps")
	travel = {"frames": driver.frames, "jumps": driver.jumps, "max_step": driver.max_player_step, "start_sector":str(source),"boss_sector":str(record.sector),"endpoint": str(endpoint),"replans":replans}
	driver.release()
	freeze()

func run():
	DirAccess.make_dir_recursive_absolute("res://builds/qa/bosses")
	selection_checks()
	game = ObservedMain.new()
	game.controls_path = "res://builds/qa/bosses/test_controls.cfg"
	root.add_child(game)
	game.start_run(37)
	freeze()
	for at: Vector2i in S.guardian_sectors(37):
		check(await Support.ready(self, game, Vector2(at-game.origin_sector)*T.SECTOR_SIZE+T.SECTOR_START), "initial guardian sector loads")
		freeze()
		var id := S.guardian_sectors(37).find(at)
		var e = actor(id)
		if id == 0:
			await movement_and_attack(e)
			await persistence(game.boss_cycle.records[id])
		await defeat(actor(id))
	check(game.state == "playing" and not game.ui.menu.visible and game.boss_cycle.phase == "final", "three guardians unlock final boss without clear")
	var first: Dictionary = current("final")[0]
	var delta: Vector2i = first.sector - game.stream.sector_at(game.player.position)
	check(Stream.distance(first.sector, game.stream.sector_at(game.player.position)) in range(2,6), "final-boss distance measured from last guardian defeat")
	check(game.announcement == game.boss_cycle.spawn_message(first) and game.announcement.contains(T.BIOME_NAMES[first.region]) and game.announcement.contains("約%d区画先" % maxi(absi(delta.x),absi(delta.y))), "spawn banner has region direction and distance")
	game.ui.update_hud()
	check(game.ui.announcement_label.visible and game.ui.objective_label.text == "ラスボスを倒せ（1回目）", "banner and first final-boss objective displayed")
	var mark: Array = game.ui.minimap.guardian_marks().filter(func(m): return m.id == first.boss_id)
	check(mark.size() == 1 and mark[0].offscreen and mark[0].role == "final", "undiscovered final boss has map edge direction")
	if game.stream.loaded.has(first.sector): game.stream._unload(first.sector)
	check(actor(first.boss_id) == null, "unloaded spawn has no actor yet")
	await route_to(first)
	for cycle in range(1,4):
		var record: Dictionary = current("final")[0]
		var e = await load_boss(record)
		check(not get_nodes_in_group("enemies").any(func(n): return n.get_parent() == game.world and n.kind != "boss" and not n.is_queued_for_deletion() and (n.get_meta("sector",Vector2i.ZERO) == record.sector and n.get_meta("chamber_id",-1) == record.chamber_id)), "boss arena suppresses ordinary enemies")
		if cycle == 1:
			var normal: Dictionary = game.stream.loaded[record.sector].spawns.filter(func(s): return s.kind != "boss")[0].duplicate(true)
			normal.id = "arena_respawn_fixture"
			normal.chamber_id = record.chamber_id
			normal.position = game.boss_cycle.world_record(record).position
			game.stream._spawn(normal)
			check(not get_nodes_in_group("enemies").any(func(n): return n.get_parent() == game.world and n.spawn_id == normal.id), "future normal spawn is suppressed inside boss chamber")
			var camera_at: Vector2 = game.camera.position
			game.camera.position += Vector2(50000,50000)
			check(not game.stream._return_area_clear({"category":"enemy","descriptor":normal,"area":Rect2(normal.position-T.ENEMY_SIZE/2,T.ENEMY_SIZE),"sector":record.sector}), "5C normal respawn is blocked even outside the view")
			game.camera.position = camera_at
			await movement_and_attack(e)
			await persistence(record)
			e = actor(record.boss_id)
		var old_sectors: Array = game.boss_cycle.used_sectors.duplicate()
		var score_before: int = game.score
		game.player.homing_charges = 0
		await defeat(e)
		check(game.score == score_before+T.FINAL_BOSS_SCORE and game.player.homing_charges == T.FINAL_BOSS_CHARGE_REWARD, "final boss score and stock rewarded once")
		check(game.boss_cycle.final_clears == cycle and not record.alive and not game.stream.missing.has(record.id), "final boss count persists and bypasses 5C respawn")
		game.stream._unload(record.sector)
		await Support.ready(self,game,game.boss_cycle.world_record(record).position)
		freeze()
		check(actor(record.boss_id) == null, "defeated boss never returns on sector reload")
		if cycle == 3: break
		var guardians := current("guardian")
		check(guardians.size() == 3 and guardians.all(func(r): return not old_sectors.has(r.sector)), "three guardians revive in wholly new sectors")
		var regions := {}
		for r: Dictionary in guardians: regions[r.region] = true
		check(regions.size() == 3 and guardians.all(func(r): return game.discovered_bosses.has(r.boss_id)), "revived guardians in three regions are marked before discovery")
		game.ui.update_hud()
		check(game.announcement.begins_with("ガーディアンが復活した！") and game.ui.objective_label.text == "ガーディアン 0 / 3 撃破（%d周目）" % (cycle+1), "revival announcement and new round objective")
		for r: Dictionary in guardians:
			var guardian = await load_boss(r)
			await defeat(guardian)
		check(current("final").size() == 1 and not old_sectors.has(current("final")[0].sector), "next final boss spawns in another sector")
	check(game.boss_cycle.phase == "secret" and current("guardian").is_empty() and current("secret").size() == 1, "third final defeat spawns secret boss without guardians")
	check(unloaded_boss_spawns > 0, "cycle actually selected never-installed bosses in currently unloaded sectors")
	var secret: Dictionary = current("secret")[0]
	check(game.announcement.begins_with("裏ボスが") and game.discovered_bosses.has(secret.boss_id), "secret spawn banner and undiscovered map mark")
	var last = await load_boss(secret)
	await movement_and_attack(last)
	await persistence(secret)
	game.player.homing_charges = 0
	game.elapsed = 1234
	await defeat(actor(secret.boss_id))
	check(game.state == "won" and game.ui.menu_title.text == "クリア" and game.ui.menu.visible, "secret defeat opens clear screen")
	check(game.score == 28000 and game.player.homing_charges == T.SECRET_BOSS_CHARGE_REWARD, "all thirteen bosses total 28000 points")
	check(game.ui.menu_detail.text.contains("028000") and game.ui.menu_detail.text.contains("20:34") and game.ui.menu_detail.text.contains("ラスボス 3回") and game.ui.menu_detail.text.contains("ガーディアン 9体") and game.ui.menu_detail.text.contains("裏ボス 1体"), "results include score time and all boss counts")
	game.primary_action()
	freeze()
	check(game.boss_cycle.phase == "guardians" and game.boss_cycle.round_number == 1 and game.boss_cycle.final_clears == 0 and game.defeated_bosses.is_empty() and game.score == 0, "retry resets complete boss progression")
	check(game.boss_cycle.guardian_ids == [0,1,2] and game.boss_cycle.used_sectors == S.guardian_sectors(37) and game.discovered_bosses.is_empty(), "retry restores only original seeded guardian locations")
	# Either notification order must resolve simultaneous deaths as one loss.
	for player_first in [false, true]:
		var fixture := Enemy.new()
		fixture.game = game
		fixture.kind = "boss"
		fixture.boss_role = "secret"
		fixture.boss_id = 99
		fixture.spawn_id = "secret_death_fixture"
		game.world.add_child(fixture)
		fixture.set_physics_process(false)
		var menu_count: int = game.result_menus
		if player_first: game.player.receive_hit(1-game.player.polarity,9999)
		fixture.receive_hit(1-fixture.polarity,9999)
		if not player_first: game.player.receive_hit(1-game.player.polarity,9999)
		game.actor_defeated(fixture)
		game.actor_defeated(game.player)
		await frames(2)
		check(game.state == "lost" and game.result_menus == menu_count+1, "simultaneous player and secret boss deaths prefer one loss screen")
		game.primary_action()
		freeze()
		check(game.boss_cycle.final_clears == 0 and game.boss_cycle.secret_kills == 0 and game.boss_cycle.phase == "guardians", "death retry also resets boss cycle")
	game.free()
	FileAccess.open("res://builds/qa/bosses/boss_results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures.size(),"messages":failures,"travel":travel,"spawned_while_unloaded":unloaded_boss_spawns},"\t"))
	print("BOSS CYCLE TEST: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
