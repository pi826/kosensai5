extends "res://tests/test_tree.gd"
const Main := preload("res://scripts/main.gd")
const T := preload("res://scripts/tuning.gd")
const S := preload("res://scripts/sector_generator.gd")
const Stream := preload("res://scripts/sector_stream.gd")
const Support := preload("res://tests/stream_test_support.gd")
const G := preload("res://scripts/stage_generator.gd")
var game: Node2D
var checks := 0
var failures: Array[String] = []
var starts: Array = []

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
func enemies(at: Vector2i) -> Array:
	return get_nodes_in_group("enemies").filter(func(e): return e.get_parent() == game.world and e.get_meta("sector", Vector2i(999,999)) == at and not e.dead and not e.is_queued_for_deletion())

func state_and_map():
	game.start_run(37)
	await Support.ready(self, game, T.SECTOR_START)
	var at := Vector2i.ZERO
	var origin_actor_ids: Array = enemies(at).map(func(e): return e.get_instance_id())
	await Support.ready(self,game,T.SECTOR_START+Vector2(T.SECTOR_SIZE.x,0))
	await Support.ready(self,game,T.SECTOR_START)
	check(origin_actor_ids == enemies(at).map(func(e):return e.get_instance_id()),"boundary backtracking retains actors inside hysteresis band")
	var data: Dictionary = game.stream.loaded[at]
	var blocks: Array = game.terrain.sectors[at].blocks
	var first: Dictionary = game.terrain.breakables[blocks[0]]
	var partial: Dictionary = game.terrain.breakables[blocks[1]]
	var broken_at: Vector2 = first.bounds.get_center()
	var partial_at: Vector2 = partial.bounds.get_center()
	game.terrain.damage_at(broken_at, T.TERRAIN_HP)
	game.terrain.damage_at(partial_at, 1)
	var surface: Rect2 = data.erodible_surfaces[0]
	game.terrain.explode(surface.get_center(), 45)
	var destroyed: Dictionary = game.terrain.snapshot(at).destroyed.duplicate()
	check(not destroyed.is_empty(), "real explosion removes sector floor")
	var dead_enemy = enemies(at)[0]
	var survivor = enemies(at)[1]
	var dead_id: String = dead_enemy.spawn_id
	var survivor_id: String = survivor.spawn_id
	var survivor_at: Vector2 = survivor.position
	dead_enemy.receive_hit(1 - dead_enemy.polarity, 100)
	survivor.receive_hit(1 - survivor.polarity, 1)
	for i in range(3): survivor.receive_hit(survivor.polarity, 1)
	check(survivor.hp == 1 and survivor.gauge == 3 and game.kills == 1, "real color hits leave HP/gauge and one defeated enemy")
	var cell := Vector2i((broken_at / T.MAP_CELL_SIZE).floor())
	game.explored_cells[cell] = true
	game.explored_by_sector.get_or_add(at, {})[cell] = true
	var geometry: Array = game.terrain.map_geometry(Rect2(Vector2(cell) * T.MAP_CELL_SIZE, Vector2.ONE * T.MAP_CELL_SIZE))
	var bullet = game.spawn_bullet(game.player, Vector2.RIGHT)
	var old_projectiles: int = game.projectiles.get_instance_id()
	var world_id: int = game.world.get_instance_id()
	check(await Support.ready(self, game, Vector2(50,-20) * T.SECTOR_SIZE + T.SECTOR_START), "far signed coordinates prepare terrain and actors")
	game.maybe_shift_origin()
	for i in range(80):
		game.stream.service()
		await frames()
	check(not game.stream.loaded.has(at) and not game.terrain.sectors.has(at), "sector beyond hysteresis distance is actually released")
	check(not is_instance_valid(bullet), "projectile in unloaded sector disappears")
	check(game.stream.states.has(at) and game.stream.states[at].destroyed == destroyed, "state stored under signed integer sector key")
	var cell_corner := Vector2(cell-game.map_origin()) * T.MAP_CELL_SIZE
	var fragments: Array = game.map_geometry(Rect2(cell_corner, Vector2.ONE*T.MAP_CELL_SIZE))
	check(preload("res://scripts/origin_shift.gd").geometry(fragments,-cell_corner) == preload("res://scripts/origin_shift.gd").geometry(geometry,-Vector2(cell)*T.MAP_CELL_SIZE), "explored terrain remains on map while unloaded")
	check(game.stream.loaded.size() <= 49, "resident geometry is bounded by hysteresis window")
	var far: Dictionary = game.stream.loaded[Vector2i(50,-20)]
	var graph := G.navigation_graph(far)
	var floor_candidates: Array = graph.nodes.filter(func(r): return r.size.x >= 512 and not G._any_intersects(far.solids + far.breakables,Rect2(r.get_center().x-64,r.position.y-180,256,180).grow(-0.1)))
	check(not floor_candidates.is_empty(), "far sector has a clear physical walking surface")
	var floor_rect: Rect2 = floor_candidates[0]
	game.player.position = Vector2(floor_rect.get_center().x,floor_rect.position.y-22)
	game.player.invulnerability = 10000
	game._update_camera(0,true)
	Support.release(self,game)
	var from_x: float = game.player.position.x
	Input.action_press("move_right")
	await frames(24)
	Input.action_release("move_right")
	check(game.player.position.x > from_x+100 and absf(game.player.position.y-(floor_rect.position.y-22))<0.1, "real walking and floor collision work at (50,-20)")
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	var far_spawn: Dictionary = far.spawns.filter(func(e): return e.kind=="turret")[0]
	var witness := G.sight_witness(far_spawn,far)
	var far_enemy = enemies(Vector2i(50,-20)).filter(func(e):return e.spawn_id==far_spawn.id)[0]
	far_enemy.position = witness.position
	game.player.position = witness.target
	game.player.polarity = far_enemy.polarity
	game.player.gauge = 0
	game.camera.position = (witness.position+witness.target)/2-Vector2(0,160)
	game.spawn_bullet(far_enemy,(game.player.position-far_enemy.position).normalized())
	for i in range(360):
		await frames()
		if game.player.gauge>0: break
	check(game.player.gauge==1, "actual far-sector enemy projectile hits and is absorbed")
	check(await Support.ready(self, game, T.SECTOR_START-Vector2(game.origin_sector)*T.SECTOR_SIZE), "origin sector reloads")
	game.maybe_shift_origin()
	check(game.world.get_instance_id() == world_id and game.projectiles.get_instance_id() == old_projectiles, "streaming retains world and projectile containers")
	check(game.terrain.snapshot(at).destroyed == destroyed and destroyed.keys().all(func(c): return not game.terrain.occupied.has(c)), "destroyed floor and collisions stay removed")
	check(not game.terrain.block_cells.has(Vector2i((broken_at / T.TILE_SIZE).floor())), "destroyed block stays absent")
	var partial_id: int = game.terrain.block_cells[Vector2i((partial_at / T.TILE_SIZE).floor())]
	check(game.terrain.breakables[partial_id].hp == 2, "partial block durability survives")
	check(not enemies(at).any(func(e): return e.spawn_id == dead_id), "defeated normal enemy stays absent")
	var survivors := enemies(at).filter(func(e): return e.spawn_id == survivor_id)
	check(survivors.size() == 1 and survivors[0].hp == 1 and survivors[0].gauge == 3 and survivors[0].position == survivor_at, "survivor HP gauge and position restored with sector-qualified identity")
	var ids: Array = enemies(at).map(func(e): return e.spawn_id)
	check(ids.size() == T.SECTOR_NORMAL_COUNT - 1 and ids.all(func(id): return id.begins_with("0,0:")), "persistent enemy IDs include coordinates")
	for guardian_coord: Vector2i in S.guardian_sectors(37):
		await Support.ready(self,game,Vector2(guardian_coord)*T.SECTOR_SIZE+T.SECTOR_START)
		var guardian_data: Dictionary = game.stream.loaded[guardian_coord]
		var room: Rect2 = guardian_data.chambers.filter(func(r):return r.kind=="boss")[0].rect
		var floor_cells: Array[Vector2i] = []
		for x in range(int(room.position.x/T.TILE_SIZE),int(room.end.x/T.TILE_SIZE)):
			for y in [int(room.end.y/T.TILE_SIZE),int(room.end.y/T.TILE_SIZE)+1]:
				var floor_cell:=Vector2i(x,y)
				if game.terrain.occupied.has(floor_cell): floor_cells.append(floor_cell)
		for x in range(int(room.position.x)+16,int(room.end.x),64): game.terrain.explode(Vector2(x,room.end.y+32),60)
		check(not floor_cells.is_empty() and floor_cells.all(func(c):return game.terrain.occupied.has(c)),"actual guardian floor remains protected after explosions: %s" % guardian_coord)
	var guardian_at: Vector2i = S.guardian_sectors(37)[0]
	check(await Support.ready(self, game, Vector2(guardian_at) * T.SECTOR_SIZE + T.SECTOR_START), "guardian sector prepared")
	var guardians: Array = enemies(guardian_at).filter(func(e): return e.kind == "boss")
	check(guardians.size() == 1, "canonical guardian sector contains one guardian")
	var guardian_id: int = guardians[0].boss_id
	game.discovered_bosses[guardian_id] = game.stable_point(guardians[0].position)
	guardians[0].receive_hit(1 - guardians[0].polarity, 1000)
	await frames(2)
	check(await Support.ready(self, game, Vector2(-50,20) * T.SECTOR_SIZE + T.SECTOR_START), "leave defeated guardian far behind")
	check(game.defeated_bosses.has(guardian_id), "guardian defeat remains global across sector unload")
	var map = game.ui.minimap
	var area: Rect2 = map.world_area()
	check(area.get_center().is_equal_approx(game.player.position) and is_equal_approx(area.size.x, T.SECTOR_SIZE.x * T.MAP_SECTOR_WIDTH), "map is player centered with a fixed extent")
	var marks: Array = map.guardian_marks()
	check(marks.size() == 1 and marks[0].offscreen and marks[0].defeated and map.map_area().has_point(marks[0].position), "discovered offscreen guardian has edge direction and defeated mark")
	check(map.displayed_cells().all(func(c): return game.explored_cells.has(c)), "map displays explored cells alone")
	game._update_exploration()
	game.ui.update_hud()
	check(game.ui.progress_label.text.contains("区画") and not game.ui.progress_label.text.contains("%"), "HUD uses visited sector count")
	game.show_menu("paused")
	check(game.ui.menu_detail.text.contains("区画") and not game.ui.menu_detail.text.contains("%"), "pause uses sector count")
	game.show_menu("lost")
	check(game.ui.menu_detail.text.contains("通常敵 1撃破") and game.ui.menu_detail.text.contains("区画"), "result shows kills without a finite total")
	game.start_run(37)
	game.set_physics_process(false)
	check(game.stream.states.is_empty() and game.defeated_enemies.is_empty() and game.defeated_bosses.is_empty(), "same-seed retry clears every sector and defeat state")
	check(game.terrain.destroyed_cells.is_empty() and game.terrain.breakables.values().all(func(b): return b.hp == T.TERRAIN_HP), "retry restores floors and all block durability")
	check(game.visited_sectors.size() == 1 and game.discovered_bosses.is_empty(), "retry resets exploration and discovered guardians")

func run():
	DirAccess.make_dir_recursive_absolute("res://builds/qa/streaming")
	var precision_stream:=Stream.new()
	for y in range(-1,2):
		for x in range(62,65): precision_stream.loaded[Vector2i(x,y)]={}
	var far_rect:=Rect2(Vector2(62,-1)*T.SECTOR_SIZE,T.SECTOR_SIZE*3)
	check(precision_stream.contains_rect(far_rect),"exact far-sector rectangle does not request an extra column after a float epsilon rounds away")
	precision_stream.loaded.erase(Vector2i(64,1))
	check(not precision_stream.contains_rect(far_rect),"far rectangle still rejects a missing diagonal sector")
	game = Main.new()
	game.controls_path = "res://builds/qa/streaming/state_controls.cfg"
	root.add_child(game)
	for value in [1,37,2026]:
		game.start_run(value)
		game.set_physics_process(false)
		check(game.stream.loaded.size() == 9 and game.stream.contains_rect(Rect2(-T.SECTOR_SIZE, T.SECTOR_SIZE * 3)), "start prepares all eight neighbours seed %d" % value)
		check(game.player.position == T.SECTOR_START, "canonical sector-zero start")
		for at in [Vector2i(-1,-1),Vector2i.ZERO]:
			var cell := Vector2i((Vector2(at+Vector2i.ONE)*T.SECTOR_SIZE/T.TILE_SIZE).floor())-Vector2i.ONE
			check(game.terrain.tile_masks.get(cell,0)==255,"stored eight-neighbour mask connects all four sectors at signed corner %s" % at)
		starts.append(game.last_start_metrics.duplicate())
	await state_and_map()
	FileAccess.open("res://builds/qa/streaming/state_results.json", FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"starts":starts},"\t"))
	game.free()
	print("STREAMING TEST: %d checks, %d failures; starts=%s" % [checks,failures.size(),starts])
	quit(0 if failures.is_empty() else 1)
