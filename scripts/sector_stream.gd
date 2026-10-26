extends RefCounted
## Only jobs create data. Only the main thread installs/removes Godot nodes.
const T := preload("res://scripts/tuning.gd")
const Job := preload("res://scripts/sector_job.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Backdrop := preload("res://scripts/world_backdrop.gd")
const Heart := preload("res://scripts/heart.gd")
const S := preload("res://scripts/sector_generator.gd")
var missing: Dictionary = {}
var game: Node2D
var loaded: Dictionary = {}
var states: Dictionary = {}
var jobs: Dictionary = {}
var waiting: Array[Vector2i] = []
var active_job: RefCounted
var actor_index := 0
var backdrops: Dictionary = {}
var generation_times: Array[float] = []
var service_times: Array[float] = []
var hold_frames := 0
var unload_count := 0
var center := Vector2i.ZERO
var priority_point := Vector2.ZERO

static func coord_at(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / T.SECTOR_SIZE.x), floori(point.y / T.SECTOR_SIZE.y))

static func distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

func shutdown() -> void:
	for job: RefCounted in jobs.values(): WorkerThreadPool.wait_for_task_completion(job.task_id)
	jobs.clear()
	waiting.clear()
	active_job = null

func initialize() -> void:
	# Start all nine data jobs before waiting; initialization never exposes an incomplete sector.
	for y in range(-1, 2):
		for x in range(-1, 2): _launch(Vector2i(x, y))
	for at: Vector2i in jobs.keys():
		var job: RefCounted = jobs[at]
		WorkerThreadPool.wait_for_task_completion(job.task_id)
		generation_times.append(job.generation_ms)
		game.terrain.begin_sector(job.result)
		while not game.terrain.build_step(): pass
		loaded[at] = job.result.data
		_add_backdrop(at)
		for spawn: Dictionary in loaded[at].spawns: _spawn(spawn)
		for h: Dictionary in loaded[at].hearts: _spawn_heart(h)
	jobs.clear()
	_refresh_stage()

func _launch(at: Vector2i) -> void:
	var job := Job.new()
	job.seed_value = game.current_seed
	job.coord = at
	job.saved = states.get(at, {}).duplicate(true)
	jobs[at] = job
	job.task_id = WorkerThreadPool.add_task(job.run, false, "sector %s" % at)

func request_around(point: Vector2, velocity: Vector2 = Vector2.ZERO) -> void:
	center = coord_at(point)
	var ahead := Vector2(signf(velocity.x)*T.MOVE_SPEED,signf(velocity.y)*T.MAX_FALL_SPEED)
	priority_point = point+ahead*T.STREAM_LOOK_AHEAD_SECONDS
	for y in range(-T.STREAM_LOAD_RADIUS, T.STREAM_LOAD_RADIUS + 1):
		for x in range(-T.STREAM_LOAD_RADIUS, T.STREAM_LOAD_RADIUS + 1):
			var at := center + Vector2i(x, y)
			if not loaded.has(at) and not jobs.has(at) and not waiting.has(at) and (active_job == null or active_job.coord != at): waiting.append(at)
	waiting = waiting.filter(func(at): return distance(at, center) <= T.STREAM_LOAD_RADIUS)
	waiting.sort_custom(func(a, b): return priority_score(a) < priority_score(b))
	while jobs.size() < T.STREAM_WORKERS and not waiting.is_empty(): _launch(waiting.pop_front())

func priority_score(at: Vector2i) -> float:
	return (Vector2(at)*T.SECTOR_SIZE+T.SECTOR_SIZE/2).distance_squared_to(priority_point)

func service() -> void:
	var begin := Time.get_ticks_usec()
	var until := begin + int(T.STREAM_BUDGET_MS * 1000)
	var redraws := 0
	while not game.terrain.pending_redraw.is_empty() and redraws < T.STREAM_DRAW_CHUNKS_PER_FRAME:
		var key: Vector2i = game.terrain.pending_redraw.pop_front()
		if game.terrain.draw_chunks.has(key): game.terrain.draw_chunks[key].queue_redraw()
		redraws += 1
	if active_job == null:
		var candidates: Array = jobs.keys()
		candidates.sort_custom(func(a, b): return priority_score(a) < priority_score(b))
		for at: Vector2i in candidates:
			var job: RefCounted = jobs[at]
			if not WorkerThreadPool.is_task_completed(job.task_id): continue
			WorkerThreadPool.wait_for_task_completion(job.task_id)
			jobs.erase(at)
			generation_times.append(job.generation_ms)
			if distance(at, center) >= T.STREAM_UNLOAD_DISTANCE: continue
			active_job = job
			actor_index = 0
			game.terrain.begin_sector(job.result)
			break
	while active_job != null and Time.get_ticks_usec() < until:
		if not game.terrain.building.is_empty():
			if game.terrain.building.phase == 5:
				if redraws >= T.STREAM_DRAW_CHUNKS_PER_FRAME: break
				redraws += 1
			game.terrain.build_step()
			continue
		var data: Dictionary = active_job.result.data
		if actor_index < data.spawns.size():
			_spawn(data.spawns[actor_index])
			actor_index += 1
			continue
		loaded[active_job.coord] = data
		for h: Dictionary in data.hearts: _spawn_heart(h)
		_add_backdrop(active_job.coord)
		active_job = null
		_refresh_stage()
		break
	# At most one distant sector per frame; retain a one-sector hysteresis band.
	if active_job == null:
		for at: Vector2i in loaded.keys():
			if distance(at, center) >= T.STREAM_UNLOAD_DISTANCE:
				_unload(at)
				break
	service_times.append((Time.get_ticks_usec() - begin) / 1000.0)
	if service_times.size() > T.STREAM_METRIC_SAMPLES: service_times.pop_front()

func _add_backdrop(at: Vector2i) -> void:
	var background := Backdrop.new()
	background.stage = {"seed": game.current_seed, "bounds": Rect2(Vector2(at) * T.SECTOR_SIZE, T.SECTOR_SIZE), "streaming": true}
	game.world.add_child(background)
	backdrops[at] = background

func _spawn(spawn: Dictionary) -> void:
	if game.defeated_enemies.has(spawn.id): return
	var enemy := Enemy.new()
	enemy.game = game
	enemy.kind = spawn.kind
	enemy.polarity = spawn.polarity
	enemy.patrol = spawn.patrol
	enemy.position = spawn.position
	enemy.boss_id = spawn.boss_id
	enemy.spawn_id = spawn.id
	enemy.set_meta("sector", spawn.sector)
	game.world.add_child(enemy)
	var saved: Dictionary = states.get(spawn.sector, {}).get("actors", {}).get(spawn.id, {})
	for field: String in saved: enemy.set(field, saved[field])
	# Temporary warnings are intentionally discarded on unload. Visibility always wakes normally.
	enemy.was_visible = false
	enemy.action = "idle"
	enemy.wake_delay = T.ENEMY_WAKE_DELAY

func _spawn_heart(spawn: Dictionary) -> void:
	if missing.has(spawn.id): return
	var heart := Heart.new()
	heart.game = game
	heart.spawn = spawn
	heart.position = spawn.position
	heart.z_index = 1
	heart.add_to_group("hearts")
	game.world.add_child(heart)

func _remember(id: String, category: String, at: Vector2i, descriptor: Dictionary, area: Rect2) -> void:
	if missing.has(id): return
	missing[id] = {"id": id, "category": category, "sector": at, "descriptor": descriptor.duplicate(true), "area": area,
		"removed_at": game.elapsed, "stamp": roundi(game.elapsed * 1000000.0), "next_attempt": 0}

func remember_enemy(actor: CharacterBody2D) -> void:
	var at: Vector2i = actor.get_meta("sector", coord_at(actor.position))
	if not loaded.has(at): return
	for spawn: Dictionary in loaded[at].spawns:
		if spawn.id == actor.spawn_id and spawn.kind != "boss":
			_remember(spawn.id, "enemy", at, spawn, S.enemy_spawn_area(spawn))
			return

static func block_id(rect: Rect2) -> String:
	return "block:%d:%d" % [int(rect.position.x), int(rect.position.y)]

func remember_block(rect: Rect2) -> void:
	var at := coord_at(rect.get_center())
	if loaded.has(at) and loaded[at].breakables.has(rect): _remember(block_id(rect), "block", at, {"bounds": rect}, rect)

func remember_heart(spawn: Dictionary) -> void:
	_remember(spawn.id, "heart", spawn.sector, spawn, Rect2(spawn.position - T.HEART_SIZE / 2, T.HEART_SIZE).grow(T.HEART_BOB_HEIGHT))

static func respawn_roll(seed_value: int, id: String, stamp: int, attempt: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d:%s:%d:%d:respawn" % [seed_value, id, stamp, attempt]).hash()
	return rng.randf()

func _return_area_clear(record: Dictionary) -> bool:
	var area: Rect2 = record.area
	if game.view_rect().grow(T.RESPAWN_VIEW_MARGIN).intersects(area): return false
	if is_instance_valid(game.player) and Rect2(game.player.position - game.player.body_size / 2, game.player.body_size).intersects(area): return false
	for actor in game.get_tree().get_nodes_in_group("enemies"):
		if actor.get_parent() != game.world or actor.dead or actor.is_queued_for_deletion(): continue
		if Rect2(actor.position - actor.body_size / 2, actor.body_size).intersects(area): return false
	if not loaded.has(record.sector):
		for actor: Dictionary in states.get(record.sector, {}).get("actors", {}).values():
			var size: Vector2 = actor.get("body_size", T.ENEMY_SIZE)
			if Rect2(actor.position - size / 2, size).intersects(area): return false
	for cell: Vector2i in Job.cells(area):
		if game.terrain.wall_cells.has(cell): return false
		if loaded.has(record.sector) and game.terrain.occupied.has(cell): return false
	# Never restore a grounded enemy into the void after erosion. Floors stay destroyed.
	if record.category == "enemy" and record.descriptor.kind != "flyer":
		var floor_area := Rect2(area.position + Vector2(0, area.size.y), Vector2(area.size.x, 1))
		for cell: Vector2i in Job.cells(floor_area):
			if loaded.has(record.sector):
				if game.terrain.destroyed_cells.has(cell): return false
			elif states.get(record.sector, {}).get("destroyed", {}).has(cell): return false
	return true

func update_rewards() -> void:
	for id: String in missing.keys():
		var record: Dictionary = missing[id]
		var age: float = game.elapsed - record.removed_at
		if age < T.RESPAWN_MIN_TIME: continue
		var at: Vector2i = record.sector
		# A job owns its saved snapshot. Wait until installation before changing its contents.
		if jobs.has(at) or (active_job != null and active_job.coord == at): continue
		var last := floori((age - T.RESPAWN_MIN_TIME) / T.RESPAWN_INTERVAL)
		if record.next_attempt > last: continue
		var first: int = record.next_attempt
		record.next_attempt = last + 1
		if not _return_area_clear(record): continue
		for attempt in range(first, last + 1):
			if respawn_roll(game.current_seed, id, record.stamp, attempt) >= T.RESPAWN_PROBABILITY: continue
			_restore(record)
			missing.erase(id)
			break

func _restore(record: Dictionary) -> void:
	var at: Vector2i = record.sector
	match record.category:
		"enemy":
			game.defeated_enemies.erase(record.id)
			if states.has(at): states[at].get("actors", {}).erase(record.id)
			if loaded.has(at): _spawn(record.descriptor)
		"block":
			var rect: Rect2 = record.descriptor.bounds
			if states.has(at): states[at].blocks[rect.position] = T.TERRAIN_HP
			if loaded.has(at): game.terrain.restore_block(at, rect)
		"heart":
			# _spawn_heart checks missing, so clear this record before installation.
			missing.erase(record.id)
			if loaded.has(at): _spawn_heart(record.descriptor)

func _unload(at: Vector2i) -> void:
	var saved: Dictionary = game.terrain.snapshot(at)
	saved.actors = {}
	for enemy in game.get_tree().get_nodes_in_group("enemies"):
		if enemy.get_parent() != game.world or enemy.get_meta("sector", Vector2i(2147483647, 2147483647)) != at: continue
		if not enemy.dead and not enemy.is_queued_for_deletion():
			var actor := {}
			for field in ["hp", "gauge", "polarity", "position", "velocity", "facing", "shot_clock", "switch_clock", "build_clock", "flight_clock", "flight_center_y", "pattern", "body_size"]: actor[field] = enemy.get(field)
			saved.actors[enemy.spawn_id] = actor
		enemy.cancel_attack()
		enemy.free()
	for heart in game.get_tree().get_nodes_in_group("hearts"):
		if heart.get_parent() == game.world and heart.spawn.sector == at: heart.free()
	for cell: Vector2i in game.explored_by_sector.get(at, {}):
		game.explored_geometry[cell] = game.terrain.map_geometry(Rect2(Vector2(cell) * T.MAP_CELL_SIZE, Vector2.ONE * T.MAP_CELL_SIZE))
	states[at] = saved
	game.terrain.unload(at)
	if backdrops.has(at):
		backdrops[at].free()
		backdrops.erase(at)
	loaded.erase(at)
	unload_count += 1
	for projectile in game.projectiles.get_children():
		if coord_at(projectile.global_position) == at or projectile.get_meta("source_sector", Vector2i(2147483647,2147483647)) == at: projectile.queue_free()
	_refresh_stage()

func _refresh_stage() -> void:
	# Compatibility view used by geometry queries/tests. It is the union of ready sectors,
	# never an enclosing rectangle treated as a guarantee that holes are loaded.
	for key in ["solids", "spawns", "hearts", "breakables", "erodible_surfaces", "protected_rects", "chambers", "tunnels", "shafts", "landmarks", "biomes", "navigation_bounds"]: game.stage[key] = []
	var first := true
	for data: Dictionary in loaded.values():
		game.stage.bounds = data.bounds if first else game.stage.bounds.merge(data.bounds)
		first = false
		game.stage.navigation_bounds.append(data.bounds)
		var base: int = game.stage.chambers.size()
		for chamber: Dictionary in data.chambers:
			var merged := chamber.duplicate(false)
			merged.id += base
			game.stage.chambers.append(merged)
		for spawn: Dictionary in data.spawns:
			var merged := spawn.duplicate(false)
			merged.chamber_id += base
			game.stage.spawns.append(merged)
		for key in ["solids", "hearts", "breakables", "erodible_surfaces", "protected_rects", "tunnels", "shafts", "landmarks", "biomes"]: game.stage[key].append_array(data[key])
	game.total_enemies = game.get_tree().get_nodes_in_group("enemies").filter(func(e): return e.get_parent() == game.world and e.kind != "boss").size()

func contains(point: Vector2) -> bool:
	return loaded.has(coord_at(point))

func contains_rect(rect: Rect2) -> bool:
	var start := coord_at(rect.position)
	# Half-open rectangles: subtract an integer sector, not a tiny pixel epsilon
	# that rounds away in float32 when the player travels farther from the origin.
	var end := Vector2i(ceili(rect.end.x/T.SECTOR_SIZE.x)-1,ceili(rect.end.y/T.SECTOR_SIZE.y)-1)
	for y in range(start.y, end.y + 1):
		for x in range(start.x, end.x + 1):
			if not loaded.has(Vector2i(x, y)): return false
	return true

func neighbourhood_ready(point: Vector2, delta: float) -> bool:
	# Reserve all eight neighbours before crossing, including a possible input
	# acceleration or ceiling correction in the player's next physics callback.
	var margin := Vector2(T.MOVE_SPEED,T.MAX_FALL_SPEED)*delta+Vector2.ONE*T.CEILING_CORRECTION
	var first := coord_at(point-margin)-Vector2i.ONE
	var last := coord_at(point+margin)+Vector2i.ONE
	return contains_rect(Rect2(Vector2(first)*T.SECTOR_SIZE,Vector2(last-first+Vector2i.ONE)*T.SECTOR_SIZE))
