extends "res://tests/test_tree.gd"
const Main := preload("res://scripts/main.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Minimap := preload("res://scripts/minimap.gd")
const Combatant := preload("res://scripts/combatant.gd")
const T := preload("res://scripts/tuning.gd")
const Terrain := preload("res://scripts/world_terrain.gd")
const O := preload("res://scripts/origin_shift.gd")
var game: Node2D
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)

func frames(count: int = 1) -> void:
	for index in range(count):
		test_progress()
		await physics_frame
		test_progress()
		await process_frame

func freeze() -> void:
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	for actor in get_nodes_in_group("enemies"): actor.set_physics_process(false)

func world_enemies() -> Array:
	var out: Array = []
	for actor in get_nodes_in_group("enemies"):
		if actor.get_parent() == game.world and not actor.is_queued_for_deletion(): out.append(actor)
	return out

func marks_match() -> bool:
	var marked: Array = game.lock_on_targets()
	for actor in get_nodes_in_group("enemies"):
		if actor.lock_marked != marked.has(actor): return false
	return true

func check_is_on_screen() -> void:
	game.camera.position = Vector2(1234.5, -987.25)
	var view: Rect2 = game.view_rect()
	for inset in [0.0, 12.0, 20.0, 0.5, -8.0]:
		var area: Rect2 = view.grow(-inset)
		var points := [view.position, view.end, view.get_center(), area.position, area.end,
			Vector2(area.position.x, area.position.y + area.size.y / 2), Vector2(area.end.x, area.position.y + area.size.y / 2),
			Vector2(area.get_center().x, area.position.y), Vector2(area.get_center().x, area.end.y),
			area.position - Vector2(0.01, 0), area.position + Vector2(0.01, 0),
			area.end - Vector2(0.01, 0), area.end + Vector2(0.01, 0),
			Vector2(area.position.x, area.end.y - 0.01), Vector2(area.position.x, area.end.y + 0.01)]
		for point: Vector2 in points:
			check(game.is_on_screen(point, inset) == area.has_point(point), "is_on_screen matches grown view at %s inset %s" % [point, inset])

func check_lock_marks() -> void:
	var actors := world_enemies()
	var chosen: Array = []
	for index in range(mini(4, actors.size())):
		var actor = actors[index]
		actor.position = game.player.position + Vector2(120 + index * 70, index * 40)
		actor.polarity = 1 - game.player.polarity
		chosen.append(actor)
	check(chosen.size() >= 3, "enough enemies for lock marks")
	game.camera.position = game.player.position
	game.player.polarity = 0
	game.player.homing_charges = 0
	for bullet in game.projectiles.get_children(): bullet.free()
	game._update_lock_marks()
	check(marks_match(), "zero homing charges leave every lock mark consistent")
	check(game.lock_on_targets().is_empty() and not chosen[0].lock_marked, "zero homing charges mark no ordinary enemy")
	game.player.homing_charges = 1
	game._update_lock_marks()
	check(marks_match(), "homing charges keep every lock mark consistent")
	var marked: Array = game.lock_on_targets()
	check(not marked.is_empty() and marked.all(func(actor): return actor.lock_marked), "charged lock marks match the target list")
	if not marked.is_empty():
		var moved = marked[0]
		var home: Vector2 = moved.position
		moved.position = game.camera.position + Vector2(5000, 0)
		game._update_lock_marks()
		check(marks_match() and not moved.lock_marked, "leaving the view clears the old lock mark")
		moved.position = home
		game._update_lock_marks()
		check(marks_match() and moved.lock_marked, "re-entering the view restores the lock mark")
		moved.receive_hit(1 - moved.polarity, 9999)
		await frames(2)
		game._update_lock_marks()
		check(marks_match(), "defeating a marked enemy leaves consistent lock marks")
	game.player.homing_charges = 0
	for bullet in game.projectiles.get_children(): bullet.free()
	game._update_lock_marks()
	var target = null
	for actor in world_enemies():
		if game.is_on_screen(actor.global_position, 12) and not actor.dead:
			target = actor
			break
	check(target != null, "a visible target exists for the homing bullet")
	if target != null:
		var bullet = game.spawn_bullet(game.player, Vector2.RIGHT, true, target)
		game._update_lock_marks()
		check(marks_match() and target.lock_marked, "homing bullet target is marked without charges")
		bullet.queue_free()
		await frames(2)
		game._update_lock_marks()
		check(marks_match(), "removed homing bullet leaves consistent lock marks")

func check_minimap() -> void:
	game.player.position = T.SECTOR_START
	game.camera.position = T.SECTOR_START
	var minimap := Minimap.new()
	minimap.game = game
	minimap.size = Vector2(240, 170)
	root.add_child(minimap)
	minimap.update_map()
	var redraws: int = minimap._redraws
	minimap.update_map()
	check(minimap._redraws == redraws, "unchanged minimap state requests no redraw")
	var scale_factor: float = minimap.map_area().size.x / (T.SECTOR_SIZE.x * T.MAP_SECTOR_WIDTH)
	game.player.position.x += ceilf(1.0 / scale_factor) + 4
	minimap.update_map()
	check(minimap._redraws > redraws, "one map pixel of player movement requests a redraw")
	redraws = minimap._redraws
	game.terrain.revision += 1
	minimap.update_map()
	check(minimap._redraws > redraws, "terrain revision change requests a redraw")
	redraws = minimap._redraws
	minimap.update_map()
	check(minimap._redraws == redraws, "stable state after a redraw stays quiet")
	minimap._last_redraw_frame = Engine.get_process_frames() - T.MINIMAP_MAX_STALE_FRAMES
	minimap.update_map()
	check(minimap._redraws > redraws, "maximum stale age forces a redraw")
	minimap.free()

func check_exploration() -> void:
	game.player.position = T.SECTOR_START
	game.camera.position = T.SECTOR_START
	game.discovered_bosses.clear()
	var near := Enemy.new()
	near.game = game
	near.kind = "boss"
	near.boss_id = 900001
	near.spawn_id = "perf_boss_near"
	near.position = game.player.position + Vector2(140, 0)
	game.world.add_child(near)
	near.set_physics_process(false)
	var far := Enemy.new()
	var mid := Enemy.new()
	mid.game = game
	mid.kind = "boss"
	mid.boss_id = 900003
	mid.spawn_id = "perf_boss_mid"
	mid.position = game.player.position + Vector2(360, 0)
	game.world.add_child(mid)
	mid.set_physics_process(false)
	far.game = game
	far.kind = "boss"
	far.boss_id = 900002
	far.spawn_id = "perf_boss_far"
	far.position = game.player.position + Vector2(5000, 0)
	game.world.add_child(far)
	far.set_physics_process(false)
	game._update_exploration()
	check(game.discovered_bosses.has(near.boss_id), "visible boss is discovered")
	check(game.discovered_bosses.has(mid.boss_id), "second visible boss is discovered")
	check(not game.discovered_bosses.has(far.boss_id), "offscreen boss stays undiscovered")
	check(game.boss == near, "nearest visible boss becomes the current boss")
	near.free()
	mid.free()
	far.free()
	game.boss = null

func check_sector_data() -> void:
	var at := Vector2i.ZERO
	check(game.stream.loaded.has(at), "sector zero is loaded")
	for loaded_at: Vector2i in game.stream.loaded:
		var data: Dictionary = game.stream.loaded[loaded_at]
		for key in ["connection_candidates", "connection_nodes", "connections", "entrances", "cycles", "routes", "gates"]:
			check(not data.has(key), "loaded sector %s omits generation key %s" % [loaded_at, key])
		check(not game.terrain.sectors[loaded_at].data.has("routes") and not game.terrain.sectors[loaded_at].data.has("gates"), "terrain sector %s data omits generation keys" % loaded_at)
	var tail_key: Vector2i = game.stream.loaded.keys().back()
	var tail: Dictionary = game.stream.loaded[tail_key]
	game.stream.loaded.erase(tail_key)
	game.stream._refresh_stage()
	game.stream._append_stage(tail, game.stream.loaded.size() == 1)
	game.stream._count_total_enemies()
	var appended := var_to_str(game.stage)
	game.stream.loaded[tail_key] = tail
	game.stream._refresh_stage()
	var rebuilt := var_to_str(game.stage)
	check(appended == rebuilt, "incremental append matches a full stage rebuild")
	check(game.stage.chambers.size() > 0 and game.stage.chambers[0].has("id") and game.stage.spawns.size() > 0 and game.stage.spawns[0].has("chamber_id"), "stage keeps chamber and spawn identifiers")

func sorted_keys(keys: Array) -> Array:
	var out := keys.duplicate()
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or a.x == b.x and a.y < b.y)
	return out

func legacy_geometry(value, delta: Vector2):
	if value is Rect2: return Rect2(value.position + delta, value.size)
	if value is Vector2: return value + delta
	if value is Array:
		var out: Array = []
		for item in value: out.append(legacy_geometry(item, delta))
		return out
	if value is Dictionary:
		var out := {}
		for key in value:
			out[key] = value[key] + Vector2.ONE * delta.x if (key is String or key is StringName) and key == "patrol" else legacy_geometry(value[key], delta)
		return out
	return value

func check_geometry() -> void:
	var delta := Vector2(137.5, -91.25)
	var sectors := {}
	for at: Vector2i in game.stream.loaded: sectors[at] = game.stream.loaded[at]
	check(var_to_str(O.geometry(sectors, delta)) == var_to_str(legacy_geometry(sectors, delta)), "geometry matches the recursive implementation for every loaded sector")
	var probe := {"patrol": Vector2(12, -7), "nested": {"patrol": Vector2(2, 5), "rects": [Rect2(3, 4, 5, 6)]}, "points": PackedVector2Array([Vector2(1, 2), Vector2(3, 4)]), "scalar": 17}
	check(var_to_str(O.geometry(probe, delta)) == var_to_str(legacy_geometry(probe, delta)), "geometry preserves patrol, packed arrays and scalar values")

func canonical_map(source: Dictionary) -> Array:
	var out: Array = []
	for key in sorted_keys(source.keys()): out.append([key, source[key]])
	return out

func canonical_rows(source: Dictionary) -> Array:
	var out: Array = []
	for key in sorted_keys(source.keys()):
		var columns: Array = source[key].keys()
		columns.sort()
		out.append([key, columns])
	return out

func terrain_state() -> Dictionary:
	var terrain = game.terrain
	return {
		"occupied": sorted_keys(terrain.occupied.keys()),
		"tile_masks": canonical_map(terrain.tile_masks),
		"block_cells": canonical_map(terrain.block_cells),
		"breakables": terrain.breakables.size(),
		"surface_cells": sorted_keys(terrain.surface_cells.keys()),
		"row_cells": canonical_rows(terrain.row_cells),
		"draw_chunks": sorted_keys(terrain.draw_chunks.keys()),
		"sectors": sorted_keys(terrain.sectors.keys()),
		"collision_body_count": terrain.collision_body_count(),
	}

func reset_game(seed_value: int = 37) -> void:
	game.start_run(seed_value)
	freeze()
	await frames(2)

func sector_chunk_keys(at: Vector2i) -> Array[Vector2i]:
	var span := Vector2i(T.SECTOR_SIZE / Terrain.DRAW_CHUNK_SIZE)
	var keys: Array[Vector2i] = []
	for y in range(at.y * span.y, (at.y + 1) * span.y):
		for x in range(at.x * span.x, (at.x + 1) * span.x): keys.append(Vector2i(x, y))
	return keys

func unload_progress() -> Array:
	if game.terrain.unloading.is_empty(): return []
	return [int(game.terrain.unloading.stage), int(game.terrain.unloading.index), int(game.terrain.unloading.chunk_y), game.terrain.unloading.rows.size()]

func check_staged_unload() -> void:
	var target := Vector2i(1, 1)
	await reset_game()
	check(game.stream.loaded.has(target) and game.terrain.sectors.has(target), "staged unload fixture sector is loaded")
	game.stream._unload(target)
	var synchronous: Dictionary = terrain_state()
	await reset_game()
	check(game.stream.loaded.has(target) and game.terrain.sectors.has(target), "split unload fixture sector is loaded")
	var chunks_before: int = sector_chunk_keys(target).filter(func(key): return game.terrain.draw_chunks.has(key)).size()
	game.stream._begin_unload(target)
	var steps := 0
	while not game.terrain.unload_step(): steps += 1
	game.stream._finish_unload(target)
	var staged: Dictionary = terrain_state()
	check(steps > 0, "unload finishes through multiple steps")
	check(synchronous.occupied == staged.occupied, "split unload leaves the same occupied cells")
	check(synchronous.tile_masks == staged.tile_masks, "split unload leaves the same tile masks")
	check(synchronous.block_cells == staged.block_cells, "split unload leaves the same block cells")
	check(synchronous.breakables == staged.breakables, "split unload leaves the same breakable count")
	check(synchronous.surface_cells == staged.surface_cells, "split unload leaves the same surface cells")
	check(synchronous.row_cells == staged.row_cells, "split unload leaves the same row cells")
	check(synchronous.draw_chunks == staged.draw_chunks, "split unload leaves the same draw chunk keys")
	check(synchronous.sectors == staged.sectors, "split unload leaves the same sector keys")
	check(synchronous.collision_body_count == staged.collision_body_count, "split unload leaves the same collision body count")

	await reset_game()
	check(chunks_before > 0 and game.terrain.collision_body_count() > 0, "unload fixture owns chunks and bodies")
	game.stream._begin_unload(target)
	game.terrain.unload_step()
	check(not game.terrain.unloading.is_empty(), "unload remains active before the service checks")
	game.shift_origin(Vector2i(1, -1))
	var probe := Vector2i(2, 0)
	game.stream._launch(probe)
	var job: RefCounted = game.stream.jobs[probe]
	check(await wait_until(func(): return WorkerThreadPool.is_task_completed(job.task_id)), "probe job completes during the unload")
	var service_frames := 0
	while not game.terrain.unloading.is_empty() and service_frames < 128:
		var before := unload_progress()
		game.stream.service()
		var after := unload_progress()
		check(after != before, "active unload advances on every service frame")
		check(game.stream.jobs.has(probe) and game.stream.active_job == null, "service does not ingest a new job during unload")
		service_frames += 1
	check(service_frames > 0 and game.terrain.unloading.is_empty(), "service completes an unload after the origin shift")
	check(not game.stream.loaded.has(target) and not game.terrain.sectors.has(target), "shifted staged unload releases sector data")
	check(not sector_chunk_keys(target).any(func(key): return game.terrain.draw_chunks.has(key)), "shifted staged unload releases every sector chunk")
	check(not game.terrain.collision_sectors.has(target), "shifted staged unload releases the sector collision parent")

func cell_sector(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(cell.x * T.TILE_SIZE / T.SECTOR_SIZE.x), floori(cell.y * T.TILE_SIZE / T.SECTOR_SIZE.y))

func open_surface_in(at: Vector2i) -> Vector2i:
	for cell: Vector2i in game.terrain.surface_cells:
		if cell_sector(cell) != at: continue
		if game.terrain.occupied.has(cell + Vector2i.UP) or game.terrain.occupied.has(cell + Vector2i.UP * 2): continue
		return cell
	return Vector2i(2147483647, 2147483647)

func has_damage_target(at: Vector2i) -> bool:
	for cell: Vector2i in game.terrain.surface_cells:
		if cell_sector(cell) == at: return true
	for id: int in game.terrain.breakables:
		if not game.terrain.breakables[id].cells.is_empty() and cell_sector(game.terrain.breakables[id].cells[0]) == at: return true
	return false

func damage_target_in(at: Vector2i, excluded: Vector2i) -> bool:
	for cell: Vector2i in game.terrain.surface_cells:
		if cell == excluded or cell_sector(cell) != at: continue
		game.terrain.explode(game.terrain.pixel_of_cell(cell) + Vector2.ONE * T.TILE_SIZE / 2, 1.0)
		return game.terrain.destroyed_cells.has(cell)
	for id: int in game.terrain.breakables.keys():
		if game.terrain.breakables[id].cells.is_empty() or cell_sector(game.terrain.breakables[id].cells[0]) != at: continue
		game.terrain.damage_at(game.terrain.breakables[id].bounds.get_center(), T.TERRAIN_HP)
		return not game.terrain.breakables.has(id)
	return false

func support_fixture() -> Dictionary:
	for at: Vector2i in game.stream.loaded:
		var cell := open_surface_in(at)
		if cell.x == 2147483647: continue
		for adjacent in [at + Vector2i.RIGHT, at + Vector2i.LEFT, at + Vector2i.UP, at + Vector2i.DOWN]:
			if not game.stream.loaded.has(adjacent) or not has_damage_target(adjacent): continue
			for distant in [at + Vector2i.RIGHT * 2, at + Vector2i.LEFT * 2, at + Vector2i.UP * 2, at + Vector2i.DOWN * 2]:
				if game.stream.loaded.has(distant) and has_damage_target(distant): return {"sector": at, "cell": cell, "adjacent": adjacent, "distant": distant}
	return {}

func check_support_revisions() -> void:
	await reset_game()
	var fixture := support_fixture()
	check(not fixture.is_empty(), "support fixture has an offscreen floor with adjacent and distant sectors")
	if fixture.is_empty(): return
	var at: Vector2i = fixture.sector
	var floor_cell: Vector2i = fixture.cell
	var adjacent: Vector2i = fixture.adjacent
	var distant: Vector2i = fixture.distant
	var enemy := Enemy.new()
	enemy.game = game
	enemy.kind = "walker"
	enemy.spawn_id = "perf_support_walker"
	enemy.position = game.terrain.pixel_of_cell(floor_cell) + Vector2(T.TILE_SIZE / 2, -T.ENEMY_SIZE.y / 2 - 2)
	game.world.add_child(enemy)
	enemy.body_size = Vector2(16, T.ENEMY_SIZE.y)
	enemy.body_shape.size = enemy.body_size
	enemy.velocity = Vector2.ZERO
	enemy.resting_position = Vector2.INF
	enemy.resting_revision = -1
	enemy.support_seen = -1
	await frames(5)
	check(not game.is_on_screen(enemy.global_position, 20.0), "support walker stays offscreen")
	check(enemy.is_on_floor(), "support walker settles on the chosen floor")
	var serial: int = game.terrain.support_serial
	check(enemy.support_seen == serial and enemy.resting_revision == game.terrain.support_revision_at(enemy.position), "support walker records its local terrain revision")
	var adjacent_revision: int = enemy.resting_revision
	check(damage_target_in(adjacent, floor_cell), "adjacent sector terrain changes")
	await frames(1)
	check(enemy.resting_revision != adjacent_revision and enemy.resting_revision == game.terrain.support_revision_at(enemy.position), "adjacent terrain change rechecks support")
	check(enemy.support_seen == game.terrain.support_serial, "adjacent terrain change advances the seen support serial")
	var distant_revision: int = enemy.resting_revision
	check(damage_target_in(distant, floor_cell), "distant sector terrain changes")
	await frames(1)
	check(enemy.resting_revision == distant_revision, "terrain change two sectors away skips the support query")
	check(enemy.support_seen == game.terrain.support_serial, "distant terrain change still advances the seen support serial")
	var seen_before_shift: int = enemy.support_seen
	var revision_before_shift: int = enemy.resting_revision
	var position_before_shift: Vector2 = enemy.position
	var resting_before_shift: Vector2 = enemy.resting_position
	var delta: Vector2 = game.shift_origin(Vector2i(1, 0))
	await frames(1)
	check(enemy.support_seen == seen_before_shift and enemy.resting_revision == revision_before_shift, "origin shift does not request a support query")
	check(enemy.position == position_before_shift + delta and enemy.resting_position == resting_before_shift + delta, "origin shift moves the resting state with the walker")
	var fall_from: float = enemy.position.y
	check(game.terrain.surface_cells.has(floor_cell), "support walker floor survives unrelated changes")
	game.terrain.explode(game.terrain.pixel_of_cell(floor_cell) + Vector2.ONE * T.TILE_SIZE / 2, 1.0)
	check(game.terrain.destroyed_cells.has(floor_cell), "support walker floor is destroyed")
	await frames(4)
	check(not enemy.is_on_floor() and enemy.position.y > fall_from, "grounded offscreen enemy falls after its floor is removed")
	enemy.free()

func check_terrain() -> void:
	var at := Vector2i(1, 1)
	var terrain = game.terrain
	var area := Rect2(terrain.sector_offset(at), T.SECTOR_SIZE).grow(Terrain.DRAW_CHUNK_SIZE)
	var expected: Array = []
	for key: Vector2i in terrain.draw_chunks:
		if area.intersects(Rect2(terrain.pixel_of_chunk(key), Vector2.ONE * Terrain.DRAW_CHUNK_SIZE)): expected.append(key)
	var actual: Array = terrain._refresh_border(at, false)
	check(sorted_keys(actual) == sorted_keys(expected), "border refresh returns the full-scan chunk set")
	game.shift_origin(Vector2i(1, 0))
	area = Rect2(terrain.sector_offset(at), T.SECTOR_SIZE).grow(Terrain.DRAW_CHUNK_SIZE)
	expected = []
	for key: Vector2i in terrain.draw_chunks:
		if area.intersects(Rect2(terrain.pixel_of_chunk(key), Vector2.ONE * Terrain.DRAW_CHUNK_SIZE)): expected.append(key)
	actual = terrain._refresh_border(at, false)
	check(sorted_keys(actual) == sorted_keys(expected), "border refresh matches after origin shift")
	var bounds := Rect2(terrain.sector_offset(at), T.SECTOR_SIZE)
	var before: Array = []
	for key: Vector2i in terrain.draw_chunks:
		if bounds.has_point(terrain.pixel_of_chunk(key)): before.append(key)
	game.stream._unload(at)
	var remaining: Array = []
	for key: Vector2i in terrain.draw_chunks:
		if bounds.has_point(terrain.pixel_of_chunk(key)): remaining.append(key)
	check(before.size() > 0 and remaining.is_empty(), "unload after an origin shift removes every chunk owned by the sector")
	check(not terrain.sectors.has(at) and not game.stream.loaded.has(at), "unload releases sector data")

func check_tick_visuals() -> void:
	var actor := Combatant.new()
	root.add_child(actor)
	actor.set_physics_process(false)
	actor.art_time = 4.0
	actor.art_fire_remaining = 0.5
	actor.art_switch_remaining = 0.02
	actor.art_land_remaining = 0.0
	actor.invulnerability = 0.3
	actor.hit_flash = 0.0
	actor.absorb_flash = 0.7
	var delta := 0.125
	actor.tick_visuals(delta, false)
	check(actor.art_time == 4.0 + delta, "offscreen art clock advances")
	check(actor.art_fire_remaining == maxf(0, 0.5 - delta), "offscreen fire timer matches its formula")
	check(actor.art_switch_remaining == maxf(0, 0.02 - delta), "offscreen switch timer matches its formula")
	check(actor.art_land_remaining == 0.0, "zero land timer stays zero")
	check(actor.invulnerability == maxf(0.0, 0.3 - delta), "offscreen invulnerability matches its formula")
	check(actor.hit_flash == 0.0, "zero hit flash stays zero")
	check(actor.absorb_flash == maxf(0.0, 0.7 - delta), "offscreen absorb flash matches its formula")
	var time: float = actor.art_time
	actor.tick_visuals(delta, false)
	check(actor.art_time == time + delta and actor.art_fire_remaining == maxf(0, 0.5 - delta * 2), "offscreen timers keep advancing")
	actor.free()

func run() -> void:
	game = Main.new()
	game.controls_path = "res://builds/qa/perf/perf_controls.cfg"
	root.add_child(game)
	game.start_run(37)
	freeze()
	await frames(2)
	check_is_on_screen()
	await check_lock_marks()
	check_minimap()
	check_exploration()
	check_sector_data()
	check_geometry()
	check_terrain()
	await check_staged_unload()
	await check_support_revisions()
	check_tick_visuals()
	game.free()
	await frames(2)
	print("PERF BEHAVIOR: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
