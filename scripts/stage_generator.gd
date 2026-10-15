extends RefCounted
## Seeded, scene-independent generation of a connected three-region room graph.
const T := preload("res://scripts/tuning.gd")
const TILE_SIZE := T.TILE_SIZE
const ROOM_SIZE := T.ROOM_SIZE
const FLOOR_Y := T.ROOM_FLOOR_Y
const BIOME_NAMES := T.BIOME_NAMES
const DIRECTIONS := {"west": Vector2i(-1, 0), "east": Vector2i(1, 0), "north": Vector2i(0, -1), "south": Vector2i(0, 1)}
const OPPOSITE := {"west": "east", "east": "west", "north": "south", "south": "north"}
const DOOR_POSITIONS := {"west": Vector2(96, 592), "east": Vector2(1184, 592), "north": Vector2(640, 208), "south": Vector2(960, 592)}
const ARRIVALS := {"west": Vector2(192, 618), "east": Vector2(1088, 618), "north": Vector2(640, 234), "south": Vector2(832, 618)}
const SAFE_RADIUS := 192.0

static func generate(stage_seed: int, room_count_per_biome: int = T.ROOMS_PER_BIOME) -> Dictionary:
	var count := clampi(room_count_per_biome, 2, 8)
	var rng := RandomNumberGenerator.new()
	rng.seed = stage_seed
	for attempt in range(T.GENERATION_RETRIES):
		var stage := _build(stage_seed, count, rng, false)
		if not stage.is_empty() and validate(stage).is_empty():
			return stage
	return generate_fallback(stage_seed, count)

static func generate_fallback(stage_seed: int, room_count_per_biome: int = T.ROOMS_PER_BIOME) -> Dictionary:
	# Exposed so automated checks can exercise the final retry path directly.
	var rng := RandomNumberGenerator.new()
	rng.seed = stage_seed
	var stage := _build(stage_seed, clampi(room_count_per_biome, 2, 8), rng, true)
	assert(validate(stage).is_empty(), "Fallback geometry must remain valid")
	return stage

static func _build(stage_seed: int, count: int, rng: RandomNumberGenerator, fallback: bool) -> Dictionary:
	var rooms: Array[Dictionary] = [_empty_room(0, Vector2i.ZERO, 0)]
	var occupied := {Vector2i.ZERO: true}
	for biome in range(3):
		var first: Vector2i = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP][biome]
		var path: Array[Vector2i] = [first]
		occupied[first] = true
		if fallback:
			for step in range(2, count + 1):
				var point := first * step
				path.append(point)
				occupied[point] = true
		elif not _extend_branch(path, occupied, biome, count, rng):
			return {}
		var previous := 0
		for index in range(count):
			var room := _empty_room(rooms.size(), path[index], biome)
			room.name = "%s %d" % [BIOME_NAMES[biome], index + 1]
			if index == count - 1:
				room.boss_id = biome
				room.name = BIOME_NAMES[biome] + "・守護者の間"
			rooms.append(room)
			_connect(rooms, previous, room.id)
			previous = room.id
	var bounds: Rect2 = rooms[0].rect
	for room: Dictionary in rooms:
		_finish_room(room, rng, fallback)
		bounds = bounds.merge(room.rect)
	return {"seed": stage_seed, "rooms": rooms, "start_room": 0, "fallback": fallback, "bounds": bounds, "room_count_per_biome": count}

static func _extend_branch(path: Array[Vector2i], occupied: Dictionary, biome: int, count: int, rng: RandomNumberGenerator) -> bool:
	if path.size() >= count:
		return true
	var options: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	# Fisher-Yates uses only the run's private RNG, including during retries.
	for i in range(options.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var saved := options[i]
		options[i] = options[j]
		options[j] = saved
	# Every map includes at least two successive upward rooms.
	if biome == 2 and path.size() == 1:
		options = [Vector2i.UP]
	for offset: Vector2i in options:
		var candidate := path[-1] + offset
		if occupied.has(candidate):
			continue
		if (biome == 0 and candidate.x >= 0) or (biome == 1 and candidate.x <= 0) or (biome == 2 and candidate.y >= 0):
			continue
		occupied[candidate] = true
		path.append(candidate)
		if _extend_branch(path, occupied, biome, count, rng):
			return true
		path.pop_back()
		occupied.erase(candidate)
	return false

static func _empty_room(id: int, grid: Vector2i, biome: int) -> Dictionary:
	var origin := Vector2(grid) * ROOM_SIZE
	return {"id": id, "grid": grid, "origin": origin, "rect": Rect2(origin, ROOM_SIZE), "biome": biome, "boss_id": -1, "name": "分岐の広間", "doors": [], "solids": [], "spawns": []}

static func _connect(rooms: Array[Dictionary], a: int, b: int) -> void:
	var offset: Vector2i = rooms[b].grid - rooms[a].grid
	for direction: String in DIRECTIONS:
		if DIRECTIONS[direction] == offset:
			var reverse: String = OPPOSITE[direction]
			rooms[a].doors.append({"direction": direction, "target": b, "position": DOOR_POSITIONS[direction], "arrival": ARRIVALS[direction]})
			rooms[b].doors.append({"direction": reverse, "target": a, "position": DOOR_POSITIONS[reverse], "arrival": ARRIVALS[reverse]})
			return

static func _finish_room(room: Dictionary, rng: RandomNumberGenerator, fallback: bool) -> void:
	room.solids = [Rect2(0, FLOOR_Y, 1280, 96), Rect2(0, 0, 32, 736), Rect2(1248, 0, 32, 736), Rect2(0, 0, 1280, 160)]
	var has_north := false
	for door: Dictionary in room.doors:
		has_north = has_north or door.direction == "north"
	if has_north:
		var mirrored := false if fallback else rng.randi_range(0, 1) == 1
		for level in range(3):
			var left := 448.0 if (level % 2 == 0) != mirrored else 576.0
			room.solids.append(Rect2(left, 512 - 128 * level, 256, 16))
	elif room.id != 0:
		# Optional shelves leave the floor open for normal fire and safe drops.
		var side := 320.0 if fallback or rng.randi_range(0, 1) == 0 else 800.0
		room.solids.append(Rect2(side, 512, 192, 16))
		if not fallback and rng.randf() < 0.5:
			room.solids.append(Rect2(448 if side == 320 else 640, 384, 256, 16))
	if room.id == 0:
		return
	var sockets: Array[float] = [416.0, 608.0, 800.0, 512.0, 704.0, 896.0]
	if not fallback:
		for i in range(sockets.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var saved := sockets[i]
			sockets[i] = sockets[j]
			sockets[j] = saved
	var desired := 1 if room.boss_id >= 0 else 2
	var first_color := rng.randi_range(0, 1)
	for x: float in sockets:
		var boss: bool = room.boss_id >= 0
		var size: Vector2 = T.BOSS_SIZE if boss else T.ENEMY_SIZE
		var point := Vector2(x, FLOOR_Y - size.y / 2.0)
		if not _safe_spawn(point, room.doors):
			continue
		var clear := true
		var body := Rect2(point - size / 2.0, size).grow(-0.1)
		for solid: Rect2 in room.solids:
			if body.intersects(solid):
				clear = false
		if not clear:
			continue
		var separated := true
		for other: Dictionary in room.spawns:
			if absf(other.position.x - x) < 160.0:
				separated = false
		if not separated:
			continue
		var kinds := ["turret", "walker", "shifter"]
		var kind: String = "boss" if boss else kinds[rng.randi_range(0, 2)]
		if room.id <= 2 and not boss:
			kind = "walker" if room.spawns.size() == 1 else "turret"
		var patrol := Vector2(x, x)
		if kind == "walker":
			patrol = Vector2(x - 32, x + 32)
			if not _safe_spawn(Vector2(patrol.x, point.y), room.doors):
				patrol.x = x
			if not _safe_spawn(Vector2(patrol.y, point.y), room.doors):
				patrol.y = x
		room.spawns.append({"id": "room_%d_enemy_%d" % [room.id, room.spawns.size()], "kind": kind, "polarity": (first_color + room.spawns.size()) % 2, "position": point, "patrol": patrol, "boss_id": room.boss_id if boss else -1})
		if room.spawns.size() >= desired:
			break

static func _safe_spawn(point: Vector2, doors: Array) -> bool:
	for door: Dictionary in doors:
		if point.distance_to(door.arrival) < SAFE_RADIUS or point.distance_to(door.position) < SAFE_RADIUS:
			return false
	return true

static func validate(stage: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var rooms: Array = stage.get("rooms", [])
	if rooms.size() < 7 or stage.get("start_room", -1) != 0:
		errors.append("Missing start room or three regions")
		return errors
	var coordinates := {}
	var boss_ids := {}
	var enemy_ids := {}
	var computed_bounds: Rect2 = rooms[0].rect
	var biome_counts := [0, 0, 0]
	if rooms.size() != stage.get("room_count_per_biome", 4) * 3 + 1:
		errors.append("Unexpected number of rooms")
	for index in range(rooms.size()):
		var room: Dictionary = rooms[index]
		if room.get("id", -1) != index:
			errors.append("Room IDs must match array indexes")
		var grid: Vector2i = room.grid
		if coordinates.has(grid):
			errors.append("Overlapping rooms")
		coordinates[grid] = true
		computed_bounds = computed_bounds.merge(room.rect)
		if room.origin != Vector2(grid) * ROOM_SIZE or room.rect != Rect2(room.origin, ROOM_SIZE):
			errors.append("Room grid and world bounds disagree")
		if room.biome < 0 or room.biome > 2:
			errors.append("Invalid biome")
		else:
			biome_counts[room.biome] += 1
		_validate_geometry(room, errors)
		var used_directions := {}
		for door: Dictionary in room.doors:
			var direction: String = door.get("direction", "")
			var target: int = door.get("target", -1)
			if not DIRECTIONS.has(direction) or target < 0 or target >= rooms.size() or used_directions.has(direction):
				errors.append("Invalid or duplicate door")
				continue
			used_directions[direction] = true
			if rooms[target].grid != grid + DIRECTIONS[direction]:
				errors.append("Door destination is not an adjacent room")
			if door.position != DOOR_POSITIONS[direction] or door.arrival != ARRIVALS[direction]:
				errors.append("Door has an unsafe connector position")
			var reciprocal := false
			for other: Dictionary in rooms[target].doors:
				if other.target == index and other.direction == OPPOSITE[direction]:
					reciprocal = true
			if not reciprocal:
				errors.append("Door has no return connection")
		var local_bosses := 0
		for spawn: Dictionary in room.spawns:
			if index == 0:
				errors.append("Enemy in safe starting room")
			if enemy_ids.has(spawn.id):
				errors.append("Duplicate enemy ID")
			enemy_ids[spawn.id] = true
			if not ["turret", "walker", "shifter", "boss"].has(spawn.kind) or not [0, 1].has(spawn.polarity):
				errors.append("Invalid enemy kind or color")
			var size: Vector2 = T.BOSS_SIZE if spawn.kind == "boss" else T.ENEMY_SIZE
			if not is_equal_approx(spawn.position.y + size.y / 2.0, FLOOR_Y):
				errors.append("Enemy is not supported by the safety floor")
			if not _safe_spawn(spawn.position, room.doors):
				errors.append("Enemy near a door or arrival position")
			if spawn.patrol.x > spawn.position.x or spawn.patrol.y < spawn.position.x:
				errors.append("Enemy outside its patrol interval")
			if not _safe_spawn(Vector2(spawn.patrol.x, spawn.position.y), room.doors) or not _safe_spawn(Vector2(spawn.patrol.y, spawn.position.y), room.doors):
				errors.append("Patrol crosses a safe arrival area")
			var body := Rect2(spawn.position - size / 2.0, size).grow(-0.1)
			for solid: Rect2 in room.solids:
				if body.intersects(solid):
					errors.append("Enemy embedded in terrain")
			if spawn.kind == "boss":
				local_bosses += 1
				if spawn.boss_id != room.boss_id or spawn.boss_id != room.biome or boss_ids.has(spawn.boss_id):
					errors.append("Duplicate or misplaced guardian ID")
				boss_ids[spawn.boss_id] = true
		if room.boss_id >= 0 and local_bosses != 1:
			errors.append("Guardian room needs exactly one guardian")
		if room.boss_id >= 0 and room.doors.size() != 1:
			errors.append("Guardian must be at the end of a branch")
		if room.boss_id < 0 and local_bosses != 0:
			errors.append("Guardian outside guardian room")
		if index != 0 and room.spawns.is_empty():
			errors.append("Combat room has no enemy")
	if boss_ids.size() != 3 or not boss_ids.has(0) or not boss_ids.has(1) or not boss_ids.has(2):
		errors.append("Map needs three unique guardians")
	var expected_count: int = stage.get("room_count_per_biome", 4)
	if biome_counts != [expected_count + 1, expected_count, expected_count]:
		errors.append("Uneven region room counts")
	if computed_bounds != stage.get("bounds", Rect2()):
		errors.append("Stage bounds do not enclose exactly its rooms")
	var visited := {0: true}
	var queue: Array[int] = [0]
	while not queue.is_empty():
		var current: int = queue.pop_front()
		for door: Dictionary in rooms[current].doors:
			if door.target >= 0 and door.target < rooms.size() and not visited.has(door.target):
				visited[door.target] = true
				queue.append(door.target)
	if visited.size() != rooms.size():
		errors.append("Room graph is disconnected")
	return errors

static func _validate_geometry(room: Dictionary, errors: Array[String]) -> void:
	var solids: Array = room.solids
	var shell := [Rect2(0, FLOOR_Y, 1280, 96), Rect2(0, 0, 32, 736), Rect2(1248, 0, 32, 736), Rect2(0, 0, 1280, 160)]
	for required: Rect2 in shell:
		if not solids.has(required):
			errors.append("Missing safety floor, wall or ceiling")
	var surfaces: Array[Rect2] = [Rect2(32, FLOOR_Y, 1216, 0)]
	for solid: Rect2 in solids:
		if solid.size.x <= 0 or solid.size.y <= 0 or not Rect2(Vector2.ZERO, ROOM_SIZE).encloses(solid):
			errors.append("Invalid solid bounds")
		if fmod(solid.position.x, TILE_SIZE) != 0 or fmod(solid.position.y, TILE_SIZE) != 0 or fmod(solid.size.x, TILE_SIZE) != 0:
			errors.append("Terrain is not aligned with the 32-pixel grid")
		if solid.size.y > 20 and not shell.has(solid):
			errors.append("Unexpected solid blocks the open floor route")
		if solid.size.y <= 20:
			if solid.size.x < T.PLAYER_SIZE.x + 2 * T.LANDING_MARGIN or solid.position.y < 224:
				errors.append("Platform is too narrow or has insufficient head room")
			surfaces.append(Rect2(solid.position, Vector2(solid.size.x, 0)))
	# Shared landing columns give a collision-free single-jump route between levels.
	# Downward travel always lands on the continuous safety floor.
	var reached := {0: true}
	var changed := true
	while changed:
		changed = false
		for i in range(surfaces.size()):
			if reached.has(i):
				continue
			for j in reached.keys():
				var lower: Rect2 = surfaces[j]
				var upper: Rect2 = surfaces[i]
				var rise := lower.position.y - upper.position.y
				var overlap := minf(lower.end.x, upper.end.x) - maxf(lower.position.x, upper.position.x)
				if rise >= 0 and rise <= T.MAX_STEP_HEIGHT and overlap >= T.PLAYER_SIZE.x + 2 * T.LANDING_MARGIN:
					reached[i] = true
					changed = true
					break
	if reached.size() != surfaces.size():
		errors.append("Platform cannot be reached with a single jump per step")
	for door: Dictionary in room.doors:
		var body := Rect2(door.arrival - T.PLAYER_SIZE / 2.0, T.PLAYER_SIZE).grow(-0.1)
		for solid: Rect2 in solids:
			if body.intersects(solid):
				errors.append("Door arrival is embedded in terrain")
		var supported := false
		for i in reached:
			var surface: Rect2 = surfaces[i]
			if is_equal_approx(door.arrival.y + T.PLAYER_SIZE.y / 2.0, surface.position.y) and door.arrival.x >= surface.position.x + T.PLAYER_SIZE.x / 2.0 and door.arrival.x <= surface.end.x - T.PLAYER_SIZE.x / 2.0:
				supported = true
		if not supported:
			errors.append("Door arrival has no reachable landing surface")

static func signature(stage: Dictionary) -> String:
	var parts := PackedStringArray([str(stage.seed), str(stage.start_room), str(stage.fallback)])
	for room: Dictionary in stage.rooms:
		parts.append("%d:%s:%d:%d" % [room.id, room.grid, room.biome, room.boss_id])
		for door: Dictionary in room.doors:
			parts.append("D:%s:%d:%s:%s" % [door.direction, door.target, door.position, door.arrival])
		for solid: Rect2 in room.solids:
			parts.append("S:" + str(solid))
		for spawn: Dictionary in room.spawns:
			parts.append("E:%s:%s:%d:%s:%s:%d" % [spawn.id, spawn.kind, spawn.polarity, spawn.position, spawn.patrol, spawn.boss_id])
	return "|".join(parts)
