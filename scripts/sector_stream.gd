extends RefCounted
## Only jobs create data. Only the main thread installs/removes Godot nodes.
const T := preload("res://scripts/tuning.gd")
const Job := preload("res://scripts/sector_job.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Backdrop := preload("res://scripts/world_backdrop.gd")
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

func _unload(at: Vector2i) -> void:
	var saved: Dictionary = game.terrain.snapshot(at)
	saved.actors = {}
	for enemy in game.get_tree().get_nodes_in_group("enemies"):
		if enemy.get_parent() != game.world or enemy.get_meta("sector", Vector2i(2147483647, 2147483647)) != at: continue
		if not enemy.dead and not enemy.is_queued_for_deletion():
			var actor := {}
			for field in ["hp", "gauge", "polarity", "position", "velocity", "facing", "shot_clock", "switch_clock", "build_clock", "flight_clock", "flight_center_y", "pattern"]: actor[field] = enemy.get(field)
			saved.actors[enemy.spawn_id] = actor
		enemy.cancel_attack()
		enemy.free()
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
	for key in ["solids", "spawns", "breakables", "erodible_surfaces", "protected_rects", "chambers", "tunnels", "shafts", "landmarks", "biomes", "navigation_bounds"]: game.stage[key] = []
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
		for key in ["solids", "breakables", "erodible_surfaces", "protected_rects", "tunnels", "shafts", "landmarks", "biomes"]: game.stage[key].append_array(data[key])
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
