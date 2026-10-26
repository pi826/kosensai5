extends "res://tests/test_tree.gd"
const Main := preload("res://scripts/main.gd")
const T := preload("res://scripts/tuning.gd")
const O := preload("res://scripts/origin_shift.gd")
const Job := preload("res://scripts/sector_job.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Support := preload("res://tests/stream_test_support.gd")
const S := preload("res://scripts/sector_generator.gd")
const G := preload("res://scripts/stage_generator.gd")
var game: Node2D
var checks := 0
var failures: Array[String] = []
var measurements: Array = []
const FAR := Vector2i(100000, -50000)
var base := T.SECTOR_SIZE * 2

class RecenterProbe extends Node:
	var game: Node2D
	var delta := Vector2.ZERO
	var after := {}
	func _physics_process(_dt: float):
		delta = game.maybe_shift_origin()
		after = {"position":game.player.position,"velocity":game.player.velocity,"floor":game.player.is_on_floor(),"drop":game.player.drop_remaining,"clear_y":game.player.drop_clear_y,"invulnerability":game.player.invulnerability,"relative":game.player.position-game.camera.position}
		set_physics_process(false)

func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)
func frames(count: int = 1):
	for i in range(count):
		test_progress()
		await physics_frame
		test_progress()
		await process_frame
func input(action: String, down: bool):
	var event := InputEventAction.new()
	event.action = action
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func freeze():
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	for actor in get_nodes_in_group("enemies"): actor.set_physics_process(false)
	game.world.process_mode = Node.PROCESS_MODE_INHERIT
func release():
	for action in ["move_right", "move_left", "jump", "move_down", "shoot"]: input(action, false)

func fixture(origin: Vector2i = Vector2i.ZERO, stacked: bool = false):
	release()
	game.start_run(37)
	freeze()
	game.stream.shutdown()
	for at: Vector2i in game.stream.loaded.keys(): game.stream._unload(at)
	game.origin_sector = origin
	game.stage.origin_sector = origin
	game.terrain.origin_sector = origin
	var at := origin + Vector2i(2, 2)
	var data := Job.world_data(S.generate(37, at), origin)
	data.solids = [Rect2(base + Vector2(0, 640), Vector2(4096, 256)), Rect2(base + Vector2(100, 400), Vector2(1800, 16))]
	if stacked: data.solids.append(Rect2(base + Vector2(100, 528), Vector2(1800, 16)))
	data.breakables = [Rect2(base + Vector2(1600, 576), Vector2(64, 64))]
	data.spawns = []
	data.hearts = []
	data.erodible_surfaces = []
	data.protected_rects = []
	var occupied := Job.cells(data.solids[0])
	var block := {"bounds": data.breakables[0], "cells": Job.cells(data.breakables[0]), "hp": T.TERRAIN_HP}
	occupied.append_array(block.cells)
	var grid := origin * Vector2i(T.SECTOR_SIZE/T.TILE_SIZE)
	occupied = O.cells(occupied,grid)
	block.cells = O.cells(block.cells,grid)
	var p := {"data": data, "occupied": occupied, "surfaces": {}, "destroyed": {}, "blocks": [block], "shelves": data.solids.slice(1), "collisions": data.solids}
	game.terrain.begin_sector(p)
	while not game.terrain.build_step(): pass
	game.stream.loaded[at] = data
	game.stream.center = at
	game.stream._add_backdrop(at)
	game.stream._refresh_stage()
	game.player.position = base + Vector2(2100, 618)
	game.player.velocity = Vector2.ZERO
	game._update_camera(0, true)
	await frames(2)

func movement(mode: String, shift: bool, origin: Vector2i = Vector2i.ZERO) -> Array:
	await fixture(origin, mode == "drop")
	if mode == "drop": game.player.position = base + Vector2(256, 378)
	if mode == "fall": game.player.position = base + Vector2(2100, 160)
	game.player.set_physics_process(true)
	await frames(3)
	input("move_right", true)
	if mode == "jump": input("jump", true)
	if mode == "drop": input("move_down", true)
	await frames(6 if mode != "drop" else 2)
	if mode == "drop": input("move_down", false)
	var before: Vector2 = game.player.position
	var velocity: Vector2 = game.player.velocity
	var on_floor: bool = game.player.is_on_floor()
	var drop: float = game.player.drop_remaining
	var clear_y: float = game.player.drop_clear_y
	game.player.invulnerability = 7
	game.camera.position += Vector2(31, -18)
	var relative: Vector2 = game.player.position - game.camera.position
	var offset := Vector2.ZERO
	var probe := RecenterProbe.new()
	if shift:
		probe.game = game
		probe.process_physics_priority = -100
		game.add_child(probe)
	await frames()
	if shift:
		offset = probe.delta
		check(offset == -base and game.origin_sector == origin + Vector2i(2,2), mode + " triggers at two sectors")
		check(probe.after.position == before + offset and probe.after.velocity == velocity, mode + " position and velocity preserved atomically")
		check(probe.after.floor == on_floor and probe.after.drop == drop and probe.after.invulnerability == 7, mode + " contacts, drop timer and invulnerability unchanged")
		check(probe.after.clear_y == clear_y + offset.y, mode + " drop clearance plane moves with the platforms")
		check(probe.after.relative == relative, mode + " camera catch-up offset preserved")
		check(game.stream.contains(game.player.position), mode + " loaded sector identity preserved")
		var synced := true
		for parent: Node2D in game.terrain.collision_sectors.values():
			for body: StaticBody2D in parent.get_children():
				synced = synced and PhysicsServer2D.body_get_state(body.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM) == body.global_transform
		check(synced, mode + " all retained collision transforms reach physics server in the same frame")
	probe.free()
	var trace: Array = []
	for i in range(100):
		if i == 8: input("jump", false)
		if i == 20: input("move_down", false)
		await frames()
		trace.append({"position": game.player.position - offset - base, "velocity": game.player.velocity, "floor": game.player.is_on_floor(), "drop": game.player.drop_remaining})
	var expected_y := 506 if mode == "drop" else 618
	check(game.player.is_on_floor() and absf(game.player.position.y - offset.y - base.y - expected_y) < 0.2, mode + " lands on correct floor or next thin shelf")
	release()
	return trace

func actor_at(kind: String, point: Vector2) -> Node2D:
	var e := Enemy.new()
	e.game = game
	e.kind = kind
	e.position = point
	e.spawn_id = "fixture:" + kind
	e.patrol = Vector2(point.x - 300, point.x + 300)
	e.set_meta("sector", game.stream.sector_at(point))
	e.set_meta("chamber_id", 0)
	game.world.add_child(e)
	e.set_physics_process(false)
	e.was_visible = true
	e.wake_delay = 0
	return e

func combat():
	await fixture(FAR)
	game.player.position = base + Vector2(900, 618)
	game._update_camera(0, true)
	var enemy := actor_at("turret", base + Vector2(1150, 618))
	enemy.polarity = 1 - game.player.polarity
	enemy._begin("windup_shot", 0.17)
	var flyer := actor_at("flyer", base + Vector2(950, 250))
	var builder := actor_at("builder", base + Vector2(1100, 618))
	builder.wall_plan = Rect2(base + Vector2(1024, 576), Vector2(32,64))
	builder._begin("windup_build", 0.3)
	var boss := actor_at("boss", base + Vector2(1000, 250))
	var heart_at := base + Vector2(1300, 550)
	game.stream._spawn_heart({"id":"origin-heart", "sector":game.stream.sector_at(heart_at), "position":heart_at})
	var hearts := get_nodes_in_group("hearts")
	var heart: Node2D = hearts[0] if not hearts.is_empty() else null
	if is_instance_valid(heart): heart.set_physics_process(false)
	boss.roam = Rect2(base + Vector2(800, 180), Vector2(400,120))
	boss.arena = Rect2(base, Vector2(1800,640))
	var wall: int = game.terrain.place_wall(Rect2(base + Vector2(1408, 576), Vector2(32,64)), 77)
	check(wall >= 0, "installed wall fixture")
	var normal: Node2D = game.spawn_bullet(game.player, Vector2.UP)
	var missile: Node2D = game.spawn_bullet(game.player, Vector2.UP, true, flyer)
	var beam: Node2D = game.spawn_laser(enemy)
	var bomb: Node2D = game.spawn_bomb_warning(enemy)
	bomb.fire()
	var warning: Node2D = game.spawn_bomb_warning(builder)
	for shot in game.projectiles.get_children(): shot.set_physics_process(false)
	normal.trail = PackedVector2Array([normal.position - Vector2(0,10), normal.position])
	game.effect(game.player.position, Color.WHITE, "hit")
	game.player.hp = 60
	game.player.heal(6)
	game.effects.show_damage(enemy.position, 1)
	game.effects.show_charge(game.player.position, 1)
	var c: PackedVector2Array = beam.curve.duplicate()
	var path: PackedVector2Array = beam.path.duplicate()
	var target: Vector2 = bomb.target
	var v: Vector2 = bomb.velocity
	var last: Vector2 = boss.position
	var at: Vector2i = game.stream.sector_at(game.player.position)
	game._update_exploration()
	game.discovered_bosses[900] = game.stable_point(boss.position)
	var map_before: Array = game.ui.minimap.guardian_marks()
	var explored: Dictionary = game.explored_cells.duplicate(true)
	var visited: Dictionary = game.visited_sectors.duplicate(true)
	var hp_time: float = game.effects.health_display.remaining
	var popup: Vector2 = game.effects.damage_numbers[0].at
	var display: Vector2 = game.effects.health_display.position
	var theme: Dictionary = game.terrain.theme_at(game.player.position)
	var block: Rect2 = game.stream.loaded[at].breakables[0]
	var block_id: String = game.stream.stable_block_id(block)
	game.terrain.damage_at(block.get_center(), 99)
	var missing: Dictionary = game.stream.missing.duplicate(true)
	var message: String = game.boss_cycle.spawn_message({"sector": at + Vector2i(3,-2), "region": 1, "role": "final"})
	var before_image: Image
	if OS.get_cmdline_user_args().has("--render"):
		game.world.process_mode = Node.PROCESS_MODE_DISABLED
		# Fixture mutations occurred with processing disabled. Flush their drawing
		# commands before taking the reference image, including fresh effects.
		var pending: Array[Node] = [game.world]
		while not pending.is_empty():
			var node: Node = pending.pop_back()
			if node is CanvasItem: node.queue_redraw()
			pending.append_array(node.get_children())
		game.ui.update_hud()
		test_progress()
		await process_frame
		test_progress()
		await RenderingServer.frame_post_draw
		before_image = root.get_texture().get_image()
		before_image.save_png("res://builds/qa/origin_shift/before.png")
	var d: Vector2 = game.maybe_shift_origin()
	if before_image != null:
		game.ui.update_hud()
		test_progress()
		await process_frame
		test_progress()
		await RenderingServer.frame_post_draw
		var after_image := root.get_texture().get_image()
		after_image.save_png("res://builds/qa/origin_shift/after.png")
		var a := before_image.get_data()
		var b := after_image.get_data()
		var changed := 0
		for i in range(a.size()):
			if a[i] != b[i]: changed += 1
		var fraction := float(changed)/a.size()
		check(fraction < 0.001, "rendered image remains continuous across shift")
		print("ORIGIN IMAGE changed_bytes=",changed," fraction=",fraction)
		game.world.process_mode = Node.PROCESS_MODE_INHERIT
	check(beam.curve == O.points(c,d) and beam.path == O.points(path,d) and beam.phase == "warning", "laser curve, clipped path and warning survive")
	check(bomb.target == target+d and bomb.velocity == v and bomb.phase == "flight" and warning.phase == "warning", "shell trajectory, landing marks and warning survive")
	check(missile.target == flyer and missile.homing and normal.trail[1] == normal.position, "missile target identity and bullet trails survive")
	check(builder.wall_plan.position == base+Vector2(1024,576)+d and builder.action == "windup_build" and builder.action_remaining == 0.3, "build plan and attack warning timer survive")
	check(enemy.action == "windup_shot" and enemy.action_remaining == 0.17 and flyer.flight_center_y == base.y+250+d.y, "enemy shot warning and flyer center survive")
	check(game.terrain.walls[wall].remaining == T.WALL_LIFETIME and game.terrain.wall_cells.has(game.terrain.cell_at(base+Vector2(1408,576)+d)), "wall collision cells and lifetime survive")
	check(is_instance_valid(heart) and heart.position == heart_at+d and heart.spawn.position == heart_at+d and heart.age == 0, "heart body, durable descriptor and bob phase survive")
	check(game.effects.damage_numbers[0].at == popup+d and game.effects.health_display.position == display+d and game.effects.health_display.remaining == hp_time, "effects and health display shift without aging")
	check(game.terrain.theme_at(game.player.position) == theme, "regional terrain theme is invariant")
	check(game.stream.missing == missing and game.stream.stable_block_id(Rect2(block.position+d,block.size)) == block_id, "respawn records and block identity invariant")
	var marks: Array = game.ui.minimap.guardian_marks()
	var same_marks := marks.size() == map_before.size()
	for i in range(marks.size()):
		same_marks = same_marks and marks[i].position.distance_to(map_before[i].position) < 0.001 and marks[i].direction.distance_to(map_before[i].direction) < 0.00001 and marks[i].offscreen == map_before[i].offscreen and marks[i].defeated == map_before[i].defeated
	check(game.explored_cells == explored and game.visited_sectors == visited and same_marks, "exploration, HUD count and minimap marks invariant")
	check(game.boss_cycle.spawn_message({"sector": at+Vector2i(3,-2), "region":1,"role":"final"}) == message, "spawn direction and sector distance invariant")
	game.camera.position += Vector2(0, -150)
	boss._move_boss(1.0/60)
	check(boss.roam.has_point(boss.position) and boss.position.distance_to(last+d) < 2, "boss continues movement within shifted range")
	var flyer_y: float = flyer.flight_center_y
	flyer._move_flyer(1.0/60)
	check(absf(flyer.position.y-flyer_y) <= T.FLYER_BOB_AMPLITUDE, "flyer continues bobbing around shifted center")
	var count: int = game.projectiles.get_child_count()
	enemy._complete_action()
	check(game.projectiles.get_child_count() == count+1, "enemy finishes existing shot warning after shift")
	var wall_count: int = game.terrain.walls.size()
	builder._complete_action()
	check(game.terrain.walls.size() == wall_count+1 and game.terrain.wall_cells.has(game.terrain.cell_at(base+Vector2(1024,576)+d)), "builder completes its existing warning at the shifted planned position")
	beam.fire()
	check(beam.phase == "beam" and not beam.path.is_empty(), "laser warning ignites after shift")
	var before: Vector2 = normal.position
	normal._physics_process(1.0/60)
	check(normal.position.distance_to(before) > 1 and not normal.is_queued_for_deletion(), "ordinary shot continues after shift")
	var previous: Vector2 = missile.position
	missile._physics_process(1.0/60)
	check(missile.target == flyer and missile.position.distance_to(previous) > 1, "missile continues tracking after shift")
	before = bomb.position
	bomb._physics_process(1.0/60)
	check(not bomb.exploded and bomb.position.distance_to(before) > 1, "shell flight continues after shift")
	game.stream._unload(at)
	var saved: Dictionary = game.stream.states[at].duplicate(true)
	game.shift_origin(Vector2i(-3,2))
	check(game.stream.states[at] == saved and game.stream.missing == missing, "unloaded state and respawn schedule unchanged by another shift")
	game.start_run(37)
	freeze()
	check(game.origin_sector == Vector2i.ZERO and game.origin_shift_count == 0 and game.stream.missing.is_empty(), "retry resets origin, shift count and respawn state")

func distant_stream():
	game.start_run(37)
	freeze()
	game.stream.shutdown()
	for at: Vector2i in game.stream.loaded.keys(): game.stream._unload(at)
	game.origin_sector = FAR
	game.stage.origin_sector = FAR
	game.terrain.origin_sector = FAR
	var ready := await Support.ready(self,game,T.SECTOR_START)
	check(ready, "very distant sector and neighbours generated at local coordinates")
	if not ready: return
	freeze()
	check(game.stream.loaded.has(FAR) and game.stream.loaded[FAR].bounds.position == Vector2.ZERO, "far generation never creates absolute pixel vectors")
	var data: Dictionary = game.stream.loaded[FAR]
	var graph := G.navigation_graph(data)
	var floors: Array = graph.nodes.filter(func(r): return r.size.x >= 512 and not G._any_intersects(data.solids + data.breakables, Rect2(r.get_center().x-64,r.position.y-180,256,180).grow(-0.1)))
	check(not floors.is_empty(), "actual very distant generation provides a clear walking surface")
	if floors.is_empty(): return
	var floor_rect: Rect2 = floors[0]
	game.player.position = Vector2(floor_rect.get_center().x,floor_rect.position.y-22)
	game.player.velocity = Vector2.ZERO
	game.player.invulnerability = 10000
	game.player.set_physics_process(true)
	await frames(3)
	var start_x: float = game.player.position.x
	input("move_right",true)
	await frames(24)
	release()
	var walked: float = game.player.position.x-start_x
	check(absf(walked-114.6666667)<0.2 and game.player.is_on_floor() and absf(game.player.position.y-(floor_rect.position.y-22))<0.2, "actual far-sector walking and grounding retain local precision")
	measurements.append({"actual_sector":[FAR.x,FAR.y],"walk_24_frames_px":walked,"expected_px":114.6666667,"floor_error_px":absf(game.player.position.y-(floor_rect.position.y-22))})
	freeze()
	var spawn: Dictionary = data.spawns.filter(func(s): return s.kind == "turret")[0]
	var turret = get_nodes_in_group("enemies").filter(func(a): return a.spawn_id == spawn.id)[0]
	var witness := G.sight_witness(spawn,data)
	turret.position = witness.position
	game.player.position = witness.target
	game.player.polarity = turret.polarity
	game.player.gauge = 0
	game.camera.position = (witness.position+witness.target)/2-Vector2(0,160)
	game.spawn_bullet(turret,(game.player.position-turret.position).normalized())
	for i in range(360):
		await frames()
		if game.player.gauge > 0: break
	check(game.player.gauge == 1, "actual far-sector enemy shot hits and is absorbed")
	game.player.polarity = 1-turret.polarity
	game.spawn_bullet(game.player,(turret.position-game.player.position).normalized(),true,turret)
	for i in range(360):
		await frames()
		if not is_instance_valid(turret) or turret.dead: break
	check(not is_instance_valid(turret) or turret.dead, "actual far-sector player missile tracks and defeats its target")
	var e: Node2D
	for actor in get_nodes_in_group("enemies"):
		if actor.get_meta("sector",Vector2i.ZERO) == FAR:
			e = actor
			break
	check(is_instance_valid(e), "far sector has a live enemy for persistence checks")
	if not is_instance_valid(e): return
	e.hp = 1
	e.gauge = 3
	var position: Vector2 = e.position
	var id: String = e.spawn_id
	var block: Rect2 = data.breakables[0]
	game.terrain.damage_at(block.get_center(),99)
	game.stream._unload(FAR)
	check(game.stream.states[FAR].actors[id].position == position and game.stream.states[FAR].blocks[block.position] == 0, "far sector stores enemy and broken box locally")
	ready = await Support.ready(self,game,T.SECTOR_START)
	check(ready, "far sector reload completes")
	if not ready: return
	freeze()
	var restored = get_nodes_in_group("enemies").filter(func(a):return a.spawn_id == id and not a.is_queued_for_deletion())[0]
	check(restored.position == position and restored.hp == 1 and restored.gauge == 3 and game.terrain.snapshot(FAR).blocks[block.position] == 0, "far enemy HP, gauge, position and destruction restored exactly")
	# A completed worker must be rebased from its own immutable origin.
	var at := FAR+Vector2i(2,0)
	game.stream._launch(at)
	var job: RefCounted = game.stream.jobs[at]
	game.shift_origin(Vector2i(1,-1))
	WorkerThreadPool.wait_for_task_completion(job.task_id)
	game.stream.jobs.erase(at)
	game.stream._take_result(job)
	check(job.result.data.bounds.position == game.stream.sector_offset(at), "in-flight generation result adapts to current origin after join")
	game.stream.shutdown()
	game.terrain.begin_sector(job.result)
	for i in range(5): game.terrain.build_step()
	game.stream.active_job = job
	game.shift_origin(Vector2i(-1,1))
	while not game.terrain.build_step(): pass
	game.stream.loaded[at] = job.result.data
	game.stream.active_job = null
	check(game.terrain.sectors[at].data.bounds.position == game.stream.sector_offset(at), "partially installed sector completes after origin shift")
	game.stream._unload(at)
	check(game.stream.states.has(at), "shifted partial sector unloads and saves normally")
	game.boss_cycle.phase = "final"
	var roles: Array[String] = ["final"]
	game.boss_cycle.request(roles)
	game.shift_origin(Vector2i(1,0))
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		game.boss_cycle.service()
		if game.boss_cycle.selection == null: break
		await frames()
		OS.delay_msec(1)
	check(game.boss_cycle.selection == null and game.boss_cycle.records.size() == 1, "far boss selection completes across a concurrent origin shift")
	if game.boss_cycle.selection != null or game.boss_cycle.records.size() != 1: return
	var record: Dictionary = game.boss_cycle.records.values()[0]
	check(record.sector_local and record.position.x >= 0 and record.position.x < T.SECTOR_SIZE.x and record.position.y >= 0 and record.position.y < T.SECTOR_SIZE.y, "far boss placement and roaming range stored in its sector")
	var records: Dictionary = game.boss_cycle.records.duplicate(true)
	var marks: Dictionary = game.discovered_bosses.duplicate(true)
	var message: String = game.boss_cycle.spawn_message(record)
	var phase: String = game.boss_cycle.phase
	game.shift_origin(Vector2i(-2,1))
	check(game.boss_cycle.records == records and game.discovered_bosses == marks and game.boss_cycle.phase == phase and game.boss_cycle.spawn_message(record) == message, "boss progression, locations, marks and spawn message invariant")
	print("ORIGIN SHIFT COST sectors=",game.stream.loaded.size()," max_ms=",game.origin_shift_times.max())

func run():
	DirAccess.make_dir_recursive_absolute("res://builds/qa/origin_shift")
	game = Main.new()
	game.controls_path = "res://builds/qa/origin_shift/controls.cfg"
	root.add_child(game)
	game.key_bindings.reset_defaults()
	for mode in ["walk", "jump", "fall", "drop"]:
		var control := await movement(mode,false)
		var shifted := await movement(mode,true)
		var far := await movement(mode,true,FAR)
		var max_error := 0.0
		var speed_error := 0.0
		var far_error := 0.0
		var contacts := true
		for i in range(control.size()):
			max_error = maxf(max_error,control[i].position.distance_to(shifted[i].position))
			max_error = maxf(max_error,shifted[i].position.distance_to(far[i].position))
			far_error = maxf(far_error,shifted[i].position.distance_to(far[i].position))
			speed_error = maxf(speed_error,control[i].velocity.distance_to(shifted[i].velocity))
			contacts = contacts and control[i].floor == shifted[i].floor and shifted[i].floor == far[i].floor
		check(max_error < 0.1 and speed_error < 0.1 and contacts, mode + " near/far physics traces match over 100 frames")
		check(far_error == 0.0, mode + " distant integer origin has exactly the same scene-space precision")
		measurements.append({"mode":mode,"max_position_difference_px":max_error,"near_far_difference_px":far_error,"max_velocity_difference":speed_error,"contacts_equal":contacts})
	await combat()
	await distant_stream()
	release()
	game.free()
	var report := {"checks":checks,"failures":failures,"measurements":measurements}
	FileAccess.open("res://builds/qa/origin_shift/results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("ORIGIN SHIFT TEST ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
