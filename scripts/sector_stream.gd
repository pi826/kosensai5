extends RefCounted
## Only jobs create data. Only the main thread installs/removes Godot nodes.
const T := preload("res://scripts/tuning.gd")
const Job := preload("res://scripts/sector_job.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Backdrop := preload("res://scripts/world_backdrop.gd")
const Heart := preload("res://scripts/heart.gd")
const Loot := preload("res://scripts/loot.gd")
const Merchant := preload("res://scripts/merchant.gd")
const S := preload("res://scripts/sector_generator.gd")
const O := preload("res://scripts/origin_shift.gd")
const PopulationJob := preload("res://scripts/population_job.gd")
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
var service_did_work := false # Explicit work, independent of the nonzero polling duration.
var hold_frames := 0
var unload_count := 0
var center := Vector2i.ZERO
var priority_point := Vector2.ZERO
var pending_population: Dictionary = {} # IDs and integer sectors survive origin shifts.
var population_queue: Array[String] = []
var population_sources: Dictionary = {} # Immutable, sector-local; never rebased.
var population_jobs: Dictionary = {}
var population_waiting: Array[Vector2i] = []
var population_times: Array[float] = []
var live_normals: Dictionary = {} # Weak references, also preventing duplicate restores.

func _service_population_jobs() -> void:
	for at: Vector2i in population_jobs.keys():
		var job: RefCounted = population_jobs[at]
		if not WorkerThreadPool.is_task_completed(job.task_id): continue
		service_did_work = true
		WorkerThreadPool.wait_for_task_completion(job.task_id)
		population_jobs.erase(at)
		population_times.append(job.generation_ms)
		if not loaded.has(at): continue
		var descriptors: Array = O.geometry(job.result,sector_offset(at))
		for spawn: Dictionary in descriptors:
			spawn.id = "%d,%d:%s" % [at.x,at.y,spawn.id]
			spawn.sector = at
		loaded[at].reinforcements = descriptors
		_queue_population(loaded[at])
		_refresh_stage()
	while population_jobs.size()<T.LOOP_POPULATION_WORKERS and not population_waiting.is_empty():
		var at: Vector2i = population_waiting.pop_front()
		if not loaded.has(at) or not population_sources.has(at): continue
		var job := PopulationJob.new()
		service_did_work = true
		job.data = population_sources[at]
		population_jobs[at] = job
		job.task_id = WorkerThreadPool.add_task(job.run,false,"enemy population %s" % at)

func queue_population() -> void:
	for data: Dictionary in loaded.values(): _queue_population(data)
	_refresh_stage()

func _queue_population(data: Dictionary) -> void:
	var level: int = mini(game.enemy_loop_level(), T.LOOP_COUNT_CAP-1)
	if level>0 and not data.has("reinforcements"):
		if not population_jobs.has(data.coord) and not population_waiting.has(data.coord): population_waiting.append(data.coord)
		return
	var ids := {}
	for spawn: Dictionary in data.spawns: ids[spawn.id] = true
	for spawn: Dictionary in data.get("reinforcements", []):
		if spawn.spawn_stage > level or ids.has(spawn.id): continue
		data.spawns.append(spawn)
		ids[spawn.id] = true
		_defer_population(spawn)

func _defer_population(spawn: Dictionary) -> void:
	if pending_population.has(spawn.id): return
	pending_population[spawn.id] = spawn.sector
	population_queue.append(spawn.id)

func _service_population(until: int) -> void:
	for i in range(mini(population_queue.size(), T.LOOP_POPULATION_BATCH)):
		if Time.get_ticks_usec() >= until: break
		service_did_work = true # Includes deferred/rejected population attempts.
		var id: String = population_queue.pop_front()
		var at: Vector2i = pending_population[id]
		if not loaded.has(at) or game.defeated_enemies.has(id):
			pending_population.erase(id)
			continue
		var index: int = loaded[at].spawns.find_custom(func(e): return e.id == id)
		if index < 0:
			pending_population.erase(id)
			continue
		var spawn: Dictionary = loaded[at].spawns[index]
		if game.boss_cycle.blocks_normal(spawn):
			pending_population.erase(id)
			continue
		var record := {"category":"enemy", "sector":at, "descriptor":spawn, "area":S.enemy_spawn_area(spawn)}
		if not _return_area_clear(record):
			population_queue.append(id)
			continue
		pending_population.erase(id)
		_spawn(spawn)

static func coord_at(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / T.SECTOR_SIZE.x), floori(point.y / T.SECTOR_SIZE.y))

func sector_at(point: Vector2) -> Vector2i:
	return _origin() + coord_at(point)

func _origin() -> Vector2i:
	return game.origin_sector if is_instance_valid(game) else Vector2i.ZERO

func sector_offset(at: Vector2i) -> Vector2:
	return O.offset(at, game.origin_sector)

func _take_result(job: RefCounted) -> void:
	# The worker's origin is immutable. Never touch its result before joining it.
	if job.origin != game.origin_sector:
		O.payload(job.result, O.offset(job.origin, game.origin_sector))
		job.origin = game.origin_sector

func shift_origin(delta: Vector2) -> void:
	priority_point += delta
	for at: Vector2i in loaded:
		loaded[at] = O.geometry(loaded[at], delta)
		game.terrain.sectors[at].data = loaded[at]
	if active_job != null:
		O.payload(active_job.result, delta, false)
		active_job.origin = game.origin_sector
	for background: Node2D in backdrops.values():
		background.stage.bounds.position += delta
		background.stage.origin_sector = game.origin_sector
		for chunk: Node2D in background.get_children():
			chunk.position += delta
			chunk.bounds.position += delta
	_refresh_stage()

static func distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

func shutdown() -> void:
	for job: RefCounted in jobs.values(): WorkerThreadPool.wait_for_task_completion(job.task_id)
	for job: RefCounted in population_jobs.values(): WorkerThreadPool.wait_for_task_completion(job.task_id)
	population_jobs.clear()
	population_sources.clear()
	population_waiting.clear()
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
		_take_result(job)
		game.terrain.begin_sector(job.result)
		while not game.terrain.build_step(): pass
		loaded[at] = job.result.data
		population_sources[at] = job.result.population_data
		_add_backdrop(at)
		for spawn: Dictionary in loaded[at].spawns: _spawn(spawn)
		_queue_population(loaded[at])
		install_bosses(at)
		for h: Dictionary in loaded[at].hearts: _spawn_heart(h)
		install_loot(at)
	jobs.clear()
	_refresh_stage()

func _launch(at: Vector2i) -> void:
	var job := Job.new()
	job.seed_value = game.current_seed
	job.coord = at
	job.origin = game.origin_sector
	job.saved = states.get(at, {}).duplicate(true)
	jobs[at] = job
	job.task_id = WorkerThreadPool.add_task(job.run, false, "sector %s" % at)

func request_around(point: Vector2, velocity: Vector2 = Vector2.ZERO) -> void:
	center = sector_at(point)
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
	return (sector_offset(at)+T.SECTOR_SIZE/2).distance_squared_to(priority_point)

func service() -> void:
	var begin := Time.get_ticks_usec()
	service_did_work = false
	var until := begin + int(T.STREAM_BUDGET_MS * 1000)
	if active_job == null:
		var candidates: Array = jobs.keys()
		candidates.sort_custom(func(a, b): return priority_score(a) < priority_score(b))
		for at: Vector2i in candidates:
			var job: RefCounted = jobs[at]
			if not WorkerThreadPool.is_task_completed(job.task_id): continue
			service_did_work = true
			WorkerThreadPool.wait_for_task_completion(job.task_id)
			jobs.erase(at)
			generation_times.append(job.generation_ms)
			if distance(at, center) >= T.STREAM_UNLOAD_DISTANCE: continue
			_take_result(job)
			active_job = job
			actor_index = 0
			game.terrain.begin_sector(job.result)
			break
	while active_job != null and Time.get_ticks_usec() < until:
		service_did_work = true
		if not game.terrain.building.is_empty():
			game.terrain.build_step()
			continue
		var data: Dictionary = active_job.result.data
		if actor_index < data.spawns.size():
			_spawn(data.spawns[actor_index])
			actor_index += 1
			continue
		loaded[active_job.coord] = data
		population_sources[active_job.coord] = active_job.result.population_data
		_queue_population(data)
		install_bosses(active_job.coord)
		for h: Dictionary in data.hearts: _spawn_heart(h)
		install_loot(active_job.coord)
		_add_backdrop(active_job.coord)
		active_job = null
		_refresh_stage()
		break
	# At most one distant sector per frame; retain a one-sector hysteresis band.
	if active_job == null:
		for at: Vector2i in loaded.keys():
			if distance(at, center) >= T.STREAM_UNLOAD_DISTANCE:
				service_did_work = true
				_unload(at)
				break
	_service_population_jobs()
	_service_population(until)
	service_times.append((Time.get_ticks_usec() - begin) / 1000.0)
	if service_times.size() > T.STREAM_METRIC_SAMPLES: service_times.pop_front()

func _add_backdrop(at: Vector2i) -> void:
	var background := Backdrop.new()
	background.stage = {"seed": game.current_seed, "bounds": Rect2(sector_offset(at), T.SECTOR_SIZE), "streaming": true, "origin_sector": game.origin_sector}
	game.world.add_child(background)
	backdrops[at] = background

func prepare_backdrop_view(area: Rect2) -> void:
	for at: Vector2i in _view_sectors(area):
		if backdrops.has(at): backdrops[at].prepare_view(area)

func backdrop_view_is_current(area: Rect2, rendered: bool = false) -> bool:
	for at: Vector2i in _view_sectors(area):
		if not backdrops.has(at): continue # Sector completion is checked separately.
		for chunk: Node2D in backdrops[at].view_chunks(area):
			if not chunk.visible or rendered and not chunk.drawn: return false
	return true

func _view_sectors(area: Rect2) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var first := sector_at(area.position)
	var last := sector_at(area.end - Vector2.ONE * 0.01)
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1): result.append(Vector2i(x, y))
	return result

func _spawn(spawn: Dictionary) -> void:
	if game.defeated_enemies.has(spawn.id): return
	if spawn.kind!="boss" and live_normals.has(spawn.id):
		var current = live_normals[spawn.id].get_ref()
		if is_instance_valid(current) and not current.dead and not current.is_queued_for_deletion(): return
	if spawn.get("spawn_stage",0) > 0 and is_instance_valid(game.player) and game.view_rect().grow(T.RESPAWN_VIEW_MARGIN).intersects(S.enemy_spawn_area(spawn)):
		_defer_population(spawn)
		return
	var record: Dictionary = {}
	if spawn.kind == "boss":
		if game.boss_cycle.records.has(spawn.boss_id):
			record = game.boss_cycle.world_record(game.boss_cycle.records[spawn.boss_id])
		else:
			var data: Dictionary = loaded.get(spawn.sector, {})
			if data.is_empty() and active_job != null and active_job.coord == spawn.sector: data = active_job.result.data
			record = game.boss_cycle.world_record(game.boss_cycle.initial_spawn(spawn, data))
		if record.is_empty() or not record.alive: return
		if game.get_tree().get_nodes_in_group("enemies").any(func(e): return e.get_parent() == game.world and e.spawn_id == spawn.id and not e.is_queued_for_deletion()): return
	elif game.boss_cycle.blocks_normal(spawn): return
	var enemy := Enemy.new()
	enemy.game = game
	enemy.kind = spawn.kind
	enemy.polarity = spawn.polarity
	enemy.patrol = spawn.patrol
	enemy.position = spawn.position
	enemy.boss_id = spawn.boss_id
	enemy.spawn_id = spawn.id
	if not record.is_empty():
		enemy.boss_role = record.role
		enemy.arena = record.arena
		enemy.roam = record.roam
		enemy.position = record.position
	enemy.set_meta("sector", spawn.sector)
	enemy.set_meta("chamber_id", spawn.chamber_id)
	game.world.add_child(enemy)
	if spawn.kind!="boss": live_normals[spawn.id] = weakref(enemy)
	var saved: Dictionary = O.actor(states.get(spawn.sector, {}).get("actors", {}).get(spawn.id, {}), sector_offset(spawn.sector))
	if not record.is_empty():
		saved = record.saved
		enemy.hp = record.hp
	for field: String in saved: enemy.set(field, saved[field])
	enemy.apply_loop(game.enemy_loop_level())
	# Temporary warnings are intentionally discarded on unload. Visibility always wakes normally.
	enemy.was_visible = false
	enemy.action = "idle"
	enemy.wake_delay = T.ENEMY_WAKE_DELAY

func install_bosses(at: Vector2i) -> void:
	if not loaded.has(at): return
	for enemy in game.get_tree().get_nodes_in_group("enemies"):
		if enemy.get_parent() != game.world or enemy.kind == "boss" or enemy.get_meta("sector", Vector2i(999999,999999)) != at: continue
		var descriptor := {"sector": at, "chamber_id": enemy.get_meta("chamber_id", -1), "position": enemy.position}
		if game.boss_cycle.blocks_normal(descriptor):
			enemy.cancel_attack()
			enemy.set_physics_process(false)
			enemy.queue_free()
	for record: Dictionary in game.boss_cycle.records.values():
		if record.sector == at and record.alive: _spawn(game.boss_cycle.world_record(record))

func _spawn_heart(spawn: Dictionary) -> void:
	if missing.has(spawn.id): return
	var heart := Heart.new()
	heart.game = game
	heart.spawn = spawn
	heart.position = spawn.position
	heart.z_index = 1
	heart.add_to_group("hearts")
	game.world.add_child(heart)

func _spawn_loot(spawn: Dictionary) -> void:
	if spawn.kind != "chest" and game.loot_taken.has(spawn.id): return
	for item in game.get_tree().get_nodes_in_group("loot"):
		if item.get_parent() == game.world and item.spawn.id == spawn.id: return
	var item := Loot.new()
	item.game = game
	item.spawn = spawn.duplicate(true)
	item.position = spawn.position
	item.z_index = 1
	game.world.add_child(item)

func spawn_loot_drop(drop: Dictionary) -> void:
	if not loaded.has(drop.sector): return
	var spawn := drop.duplicate(true)
	spawn.position = game.local_point(drop)
	_spawn_loot(spawn)

func install_loot(at: Vector2i) -> void:
	for spawn: Dictionary in loaded[at].get("loot", []): _spawn_loot(spawn)
	for spawn: Dictionary in loaded[at].get("merchants", []):
		if game.get_tree().get_nodes_in_group("merchants").any(func(m): return m.get_parent() == game.world and m.spawn.id == spawn.id): continue
		var merchant := Merchant.new()
		merchant.game = game
		merchant.spawn = spawn.duplicate(true)
		merchant.position = spawn.position
		merchant.z_index = 1
		game.world.add_child(merchant)
	for drop: Dictionary in game.loot_drops.values():
		if drop.sector == at: spawn_loot_drop(drop)

func _remember(id: String, category: String, at: Vector2i, descriptor: Dictionary, area: Rect2) -> void:
	if missing.has(id): return
	missing[id] = {"id": id, "category": category, "sector": at, "descriptor": O.geometry(descriptor, -sector_offset(at)), "area": Rect2(area.position - sector_offset(at), area.size), "sector_local": true,
		"removed_at": game.elapsed, "stamp": roundi(game.elapsed * 1000000.0), "next_attempt": 0}

func remember_enemy(actor: CharacterBody2D) -> void:
	var at: Vector2i = actor.get_meta("sector", sector_at(actor.position))
	if not loaded.has(at): return
	for spawn: Dictionary in loaded[at].spawns:
		if spawn.id == actor.spawn_id and spawn.kind != "boss":
			_remember(spawn.id, "enemy", at, spawn, S.enemy_spawn_area(spawn))
			return

static func block_id(rect: Rect2) -> String:
	return "block:%d:%d" % [int(rect.position.x), int(rect.position.y)]

func stable_block_id(rect: Rect2) -> String:
	# Scalar arithmetic is float64; never round an absolute position through Vector2.
	return "block:%d:%d" % [int(rect.position.x) + int(game.origin_sector.x) * int(T.SECTOR_SIZE.x), int(rect.position.y) + int(game.origin_sector.y) * int(T.SECTOR_SIZE.y)]

func remember_block(rect: Rect2) -> void:
	var at := sector_at(rect.get_center())
	if loaded.has(at) and loaded[at].breakables.has(rect): _remember(stable_block_id(rect), "block", at, {"bounds": rect}, rect)

func remember_heart(spawn: Dictionary) -> void:
	_remember(spawn.id, "heart", spawn.sector, spawn, Rect2(spawn.position - T.HEART_SIZE / 2, T.HEART_SIZE).grow(T.HEART_BOB_HEIGHT))

static func respawn_roll(seed_value: int, id: String, stamp: int, attempt: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d:%s:%d:%d:respawn" % [seed_value, id, stamp, attempt]).hash()
	return rng.randf()

func _return_area_clear(record: Dictionary) -> bool:
	if record.category == "enemy" and game.boss_cycle.blocks_normal(record.descriptor, record.get("sector_local", false)): return false
	if record.get("sector_local", false) and not loaded.has(record.sector) and distance(record.sector, center) >= T.STREAM_UNLOAD_DISTANCE:
		# Distant saved sectors are checked entirely in sector coordinates.
		# Converting them to scene vectors would reintroduce float32 rounding.
		for actor: Dictionary in states.get(record.sector, {}).get("actors", {}).values():
			var size: Vector2 = actor.get("body_size", T.ENEMY_SIZE)
			if Rect2(actor.position - size / 2, size).intersects(record.area): return false
		if record.category == "enemy" and record.descriptor.kind not in ["flyer", "enhancer"]:
			var floor_area := Rect2(record.area.position + Vector2(0, record.area.size.y), Vector2(record.area.size.x, 1))
			for cell: Vector2i in Job.cells(floor_area):
				if states.get(record.sector, {}).get("destroyed", {}).has(cell): return false
		return true
	var area: Rect2 = record.area
	if record.get("sector_local", false): area.position += sector_offset(record.sector)
	if game.view_rect().grow(T.RESPAWN_VIEW_MARGIN).intersects(area): return false
	if is_instance_valid(game.player) and Rect2(game.player.position - game.player.body_size / 2, game.player.body_size).intersects(area): return false
	for actor in game.get_tree().get_nodes_in_group("enemies"):
		if actor.get_parent() != game.world or actor.dead or actor.is_queued_for_deletion(): continue
		if Rect2(actor.position - actor.body_size / 2, actor.body_size).intersects(area): return false
	if not loaded.has(record.sector):
		for actor: Dictionary in states.get(record.sector, {}).get("actors", {}).values():
			var size: Vector2 = actor.get("body_size", T.ENEMY_SIZE)
			if Rect2(actor.position + sector_offset(record.sector) - size / 2, size).intersects(area): return false
	for cell: Vector2i in game.terrain._cells_in(area):
		if game.terrain.wall_cells.has(cell): return false
		if loaded.has(record.sector) and game.terrain.occupied.has(cell): return false
	# Never restore a grounded enemy into the void after erosion. Floors stay destroyed.
	if record.category == "enemy" and record.descriptor.kind not in ["flyer", "enhancer"]:
		var floor_area := Rect2(area.position + Vector2(0, area.size.y), Vector2(area.size.x, 1))
		for cell: Vector2i in game.terrain._cells_in(floor_area):
			if loaded.has(record.sector):
				if game.terrain.destroyed_cells.has(cell): return false
			elif states.get(record.sector, {}).get("destroyed", {}).has(cell - record.sector * Vector2i(T.SECTOR_SIZE / T.TILE_SIZE)): return false
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
	var descriptor: Dictionary = O.geometry(record.descriptor, sector_offset(at)) if loaded.has(at) else record.descriptor
	match record.category:
		"enemy":
			game.defeated_enemies.erase(record.id)
			if states.has(at): states[at].get("actors", {}).erase(record.id)
			if loaded.has(at):
				if not loaded[at].spawns.any(func(e):return e.id==record.id): loaded[at].spawns.append(descriptor)
				_spawn(descriptor)
		"block":
			var rect: Rect2 = descriptor.bounds
			if states.has(at): states[at].blocks[record.descriptor.bounds.position] = T.TERRAIN_HP
			if loaded.has(at): game.terrain.restore_block(at, rect)
		"heart":
			# _spawn_heart checks missing, so clear this record before installation.
			missing.erase(record.id)
			if loaded.has(at): _spawn_heart(descriptor)

func _unload(at: Vector2i) -> void:
	population_sources.erase(at)
	var saved: Dictionary = game.terrain.snapshot(at)
	saved.actors = {}
	for enemy in game.get_tree().get_nodes_in_group("enemies"):
		if enemy.get_parent() != game.world or enemy.get_meta("sector", Vector2i(2147483647, 2147483647)) != at: continue
		if not enemy.dead and not enemy.is_queued_for_deletion():
			var actor := {}
			for field in ["hp", "max_hp", "loop_level", "gauge", "polarity", "position", "velocity", "facing", "shot_clock", "switch_clock", "build_clock", "flight_clock", "flight_center_y", "pattern", "body_size", "move_clock", "move_direction"]: actor[field] = enemy.get(field)
			saved.actors[enemy.spawn_id] = actor
			if enemy.kind == "boss": game.boss_cycle.remember(enemy, actor)
		enemy.cancel_attack()
		live_normals.erase(enemy.spawn_id)
		enemy.free()
	for heart in game.get_tree().get_nodes_in_group("hearts"):
		if heart.get_parent() == game.world and heart.spawn.sector == at: heart.free()
	for item in game.get_tree().get_nodes_in_group("loot"):
		if item.get_parent() == game.world and item.spawn.sector == at: item.free()
	for merchant in game.get_tree().get_nodes_in_group("merchants"):
		if merchant.get_parent() == game.world and merchant.spawn.sector == at: merchant.free()
	for cell: Vector2i in game.explored_by_sector.get(at, {}):
		game.record_map_cell(cell)
	states[at] = O.snapshot(saved, -sector_offset(at))
	game.terrain.unload(at)
	if backdrops.has(at):
		backdrops[at].free()
		backdrops.erase(at)
	loaded.erase(at)
	unload_count += 1
	for projectile in game.projectiles.get_children():
		if sector_at(projectile.global_position) == at or projectile.get_meta("source_sector", Vector2i(2147483647,2147483647)) == at: projectile.queue_free()
	_refresh_stage()

func _refresh_stage() -> void:
	# Compatibility view used by geometry queries/tests. It is the union of ready sectors,
	# never an enclosing rectangle treated as a guarantee that holes are loaded.
	for key in ["solids", "spawns", "hearts", "loot", "merchants", "detours", "optional_surfaces", "breakables", "erodible_surfaces", "protected_rects", "chambers", "tunnels", "shafts", "landmarks", "biomes", "navigation_bounds"]: game.stage[key] = []
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
		for key in ["loot", "merchants", "detours", "optional_surfaces"]: game.stage[key].append_array(data.get(key, []))
	game.total_enemies = game.get_tree().get_nodes_in_group("enemies").filter(func(e): return e.get_parent() == game.world and e.kind != "boss").size()

func contains(point: Vector2) -> bool:
	return loaded.has(sector_at(point))

func contains_rect(rect: Rect2) -> bool:
	var start := sector_at(rect.position)
	# Half-open rectangles: subtract an integer sector, not a tiny pixel epsilon
	# that rounds away in float32 when the player travels farther from the origin.
	var end: Vector2i = _origin() + Vector2i(ceili(rect.end.x/T.SECTOR_SIZE.x)-1,ceili(rect.end.y/T.SECTOR_SIZE.y)-1)
	for y in range(start.y, end.y + 1):
		for x in range(start.x, end.x + 1):
			if not loaded.has(Vector2i(x, y)): return false
	return true

func neighbourhood_ready(point: Vector2, delta: float) -> bool:
	# Reserve all eight neighbours before crossing, including a possible input
	# acceleration or ceiling correction in the player's next physics callback.
	var margin := Vector2(T.AIR_DASH_SPEED,T.MAX_FALL_SPEED)*delta+Vector2.ONE*T.CEILING_CORRECTION
	var first := sector_at(point-margin)-Vector2i.ONE
	var last := sector_at(point+margin)+Vector2i.ONE
	return contains_rect(Rect2(sector_offset(first),Vector2(last-first+Vector2i.ONE)*T.SECTOR_SIZE))
