extends RefCounted
## One continuous, seeded world. All terrain and spawn positions use world coordinates.
const T := preload("res://scripts/tuning.gd")
const WORLD_SIZE := T.WORLD_SIZE
const GROUND_Y := T.GROUND_Y
const START_X := T.WORLD_START_X
const FLOOR_WIDTH := 384.0
const FLOOR_COUNT := 32
const CLIMB_STEP := 128.0
const CLIMB_LEVELS := 12
const SAFE_RADIUS := 640.0

static func generate(stage_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = stage_seed
	for attempt in range(T.GENERATION_RETRIES):
		var stage := _build(stage_seed, rng, false)
		if validate(stage).is_empty():
			return stage
	return generate_fallback(stage_seed)

static func generate_fallback(stage_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = stage_seed
	var stage := _build(stage_seed, rng, true)
	assert(validate(stage).is_empty(), "Fallback world must remain traversable")
	return stage

static func _build(stage_seed: int, rng: RandomNumberGenerator, fallback: bool) -> Dictionary:
	var bounds := Rect2(Vector2.ZERO, WORLD_SIZE)
	var solids: Array[Rect2] = []
	var heights: Array[float] = []
	var previous := GROUND_Y
	for index in range(FLOOR_COUNT):
		var safe_plateau: bool = index in [0, 1, 2, 3, 14, 15, 16, 17, 28, 29, 30, 31]
		var top := GROUND_Y if fallback or safe_plateau else clampf(previous + 32 * rng.randi_range(-1, 1), GROUND_Y - 64, GROUND_Y + 64)
		heights.append(top)
		solids.append(Rect2(index * FLOOR_WIDTH, top, FLOOR_WIDTH, WORLD_SIZE.y - top))
		previous = top
	# Only the outside boundary is walled; no room shells or loading gates exist.
	solids.append(Rect2(0, 0, 32, WORLD_SIZE.y))
	solids.append(Rect2(WORLD_SIZE.x - 32, 0, 32, WORLD_SIZE.y))
	for level in range(1, CLIMB_LEVELS + 1):
		var width := 768.0 if level == CLIMB_LEVELS else 384.0
		var shift := 0.0 if fallback or level == CLIMB_LEVELS else float(rng.randi_range(-2, 2) * T.TILE_SIZE)
		solids.append(Rect2(START_X - width / 2 + shift, GROUND_Y - level * CLIMB_STEP, width, 16))
	# Elevated optional paths always have safe ground beneath them.
	for index: int in [5, 8, 11, 20, 23, 26]:
		var left := index * FLOOR_WIDTH + 32
		var width := 320.0 if fallback else float(rng.randi_range(8, 11) * T.TILE_SIZE)
		solids.append(Rect2(left, heights[index] - CLIMB_STEP, width, 16))
		if not fallback and rng.randf() < 0.7:
			solids.append(Rect2(left + 64, heights[index] - CLIMB_STEP * 2, width - 64, 16))
	var start := Vector2(START_X, GROUND_Y - T.PLAYER_SIZE.y / 2)
	var spawns: Array[Dictionary] = []
	var landmarks: Array[Dictionary] = []
	var boss_xs := [768.0, START_X, 11520.0]
	for boss_id in range(3):
		var support_y := GROUND_Y - CLIMB_LEVELS * CLIMB_STEP if boss_id == 1 else GROUND_Y
		var point := Vector2(boss_xs[boss_id], support_y - T.BOSS_SIZE.y / 2)
		spawns.append({"id": "guardian_%d" % boss_id, "kind": "boss", "polarity": rng.randi_range(0, 1), "position": point, "patrol": Vector2(point.x, point.x), "boss_id": boss_id})
		landmarks.append({"id": boss_id, "position": point, "name": T.BIOME_NAMES[boss_id] + "の守護者"})
	var kinds := ["turret", "walker", "shifter"]
	for index in range(2, FLOOR_COUNT - 1):
		var center_x := index * FLOOR_WIDTH + FLOOR_WIDTH / 2
		if absf(center_x - START_X) < SAFE_RADIUS or absf(center_x - 768) < 384 or absf(center_x - 11520) < 384:
			continue
		var offset := 0 if fallback else rng.randi_range(-2, 2) * T.TILE_SIZE
		var point := Vector2(center_x + offset, heights[index] - T.ENEMY_SIZE.y / 2)
		var kind: String = kinds[rng.randi_range(0, 2)]
		var patrol := Vector2(point.x, point.x)
		if kind == "walker":
			patrol = Vector2(maxf(index * FLOOR_WIDTH + 48, point.x - 80), minf((index + 1) * FLOOR_WIDTH - 48, point.x + 80))
		spawns.append({"id": "enemy_%d" % index, "kind": kind, "polarity": rng.randi_range(0, 1), "position": point, "patrol": patrol, "boss_id": -1})
	var biomes: Array[Dictionary] = []
	for biome_id in range(3):
		biomes.append({"id": biome_id, "name": T.BIOME_NAMES[biome_id], "rect": Rect2(biome_id * 4096, 0, 4096, WORLD_SIZE.y)})
	var routes: Array[Dictionary] = []
	for boss_id in range(3):
		var points: Array[Vector2] = [start]
		if boss_id == 1:
			for level in range(1, CLIMB_LEVELS + 1):
				points.append(Vector2(START_X, GROUND_Y - level * CLIMB_STEP - T.PLAYER_SIZE.y / 2))
		else:
			var indexes := range(15, 1, -1) if boss_id == 0 else range(16, 30)
			for index: int in indexes:
				points.append(Vector2(index * FLOOR_WIDTH + FLOOR_WIDTH / 2, heights[index] - T.PLAYER_SIZE.y / 2))
			points.append(Vector2(boss_xs[boss_id], GROUND_Y - T.PLAYER_SIZE.y / 2))
		routes.append({"boss_id": boss_id, "points": points})
	return {"seed": stage_seed, "bounds": bounds, "start_position": start, "solids": solids, "spawns": spawns, "biomes": biomes, "landmarks": landmarks, "routes": routes, "fallback": fallback}

static func _supported(point: Vector2, body_size: Vector2, solids: Array) -> bool:
	var foot_y := point.y + body_size.y / 2
	var intervals: Array[Vector2] = []
	for solid: Rect2 in solids:
		if is_equal_approx(foot_y, solid.position.y):
			intervals.append(Vector2(solid.position.x, solid.end.x))
	intervals.sort_custom(func(a: Vector2, b: Vector2): return a.x < b.x)
	var covered_x := point.x - body_size.x / 2
	for interval: Vector2 in intervals:
		if interval.x <= covered_x and interval.y > covered_x:
			covered_x = interval.y
		if covered_x >= point.x + body_size.x / 2:
			return true
	return false

static func _embedded(point: Vector2, body_size: Vector2, solids: Array) -> bool:
	var body := Rect2(point - body_size / 2, body_size).grow(-0.1)
	for solid: Rect2 in solids:
		if body.intersects(solid):
			return true
	return false

static func validate(stage: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var bounds: Rect2 = stage.get("bounds", Rect2())
	var solids: Array = stage.get("solids", [])
	var spawns: Array = stage.get("spawns", [])
	if bounds != Rect2(Vector2.ZERO, WORLD_SIZE) or solids.is_empty():
		errors.append("Invalid continuous world bounds or missing terrain")
		return errors
	var floors: Array[Rect2] = []
	var platforms: Array[Rect2] = []
	for solid: Rect2 in solids:
		if solid.size.x <= 0 or solid.size.y <= 0 or not bounds.encloses(solid):
			errors.append("Invalid solid bounds")
		if fmod(solid.position.x, T.TILE_SIZE) != 0 or fmod(solid.position.y, T.TILE_SIZE) != 0 or fmod(solid.size.x, T.TILE_SIZE) != 0:
			errors.append("Terrain must align to the 32 px grid")
		if solid.size.y <= 20:
			platforms.append(solid)
			if solid.size.y != 16 or solid.size.x < T.PLAYER_SIZE.x + T.LANDING_MARGIN * 2 or solid.position.y < T.PLAYER_SIZE.y + 32:
				errors.append("Platform has insufficient landing or head space")
		elif solid.end.y == bounds.end.y and solid.size.x >= 128:
			floors.append(solid)
		elif solid != Rect2(0, 0, 32, WORLD_SIZE.y) and solid != Rect2(WORLD_SIZE.x - 32, 0, 32, WORLD_SIZE.y):
			errors.append("Interior solid wall blocks the open world")
	if not solids.has(Rect2(0, 0, 32, WORLD_SIZE.y)) or not solids.has(Rect2(WORLD_SIZE.x - 32, 0, 32, WORLD_SIZE.y)):
		errors.append("Missing outer world boundaries")
	floors.sort_custom(func(a: Rect2, b: Rect2): return a.position.x < b.position.x)
	var end_x := 0.0
	var last_y := GROUND_Y
	for floor_rect: Rect2 in floors:
		if not is_equal_approx(floor_rect.position.x, end_x):
			errors.append("Safety floor contains a gap or overlap")
		if absf(floor_rect.position.y - last_y) > 64 or absf(floor_rect.position.y - GROUND_Y) > 64:
			errors.append("Ground step exceeds the guaranteed single-jump route")
		end_x = floor_rect.end.x
		last_y = floor_rect.position.y
	if not is_equal_approx(end_x, bounds.end.x):
		errors.append("Safety floor does not span the whole world")
	# Reachability uses overlapping landing columns, measured against the player's jump.
	var reached: Array[Rect2] = floors.duplicate()
	var pending: Array[Rect2] = platforms.duplicate()
	var changed := true
	while changed:
		changed = false
		for index in range(pending.size() - 1, -1, -1):
			var upper: Rect2 = pending[index]
			for lower: Rect2 in reached:
				var rise := lower.position.y - upper.position.y
				var overlap := minf(lower.end.x, upper.end.x) - maxf(lower.position.x, upper.position.x)
				if rise > 0 and rise <= T.MAX_STEP_HEIGHT and overlap >= T.PLAYER_SIZE.x + 2 * T.LANDING_MARGIN:
					reached.append(upper)
					pending.remove_at(index)
					changed = true
					break
	if not pending.is_empty():
		errors.append("A shelf is unreachable with normal single jumps")
	var start: Vector2 = stage.get("start_position", Vector2(-1, -1))
	if not _supported(start, T.PLAYER_SIZE, solids) or _embedded(start, T.PLAYER_SIZE, solids):
		errors.append("Start is unsupported or inside terrain")
	var ids := {}
	var guardians := {}
	for spawn: Dictionary in spawns:
		var id: String = spawn.get("id", "")
		var kind: String = spawn.get("kind", "")
		var point: Vector2 = spawn.get("position", Vector2(-1, -1))
		var size: Vector2 = T.BOSS_SIZE if kind == "boss" else T.ENEMY_SIZE
		var patrol: Vector2 = spawn.get("patrol", Vector2(-1, -1))
		if id.is_empty() or ids.has(id):
			errors.append("Enemy identity must be unique")
		ids[id] = true
		if not ["boss", "turret", "walker", "shifter"].has(kind) or not [0, 1].has(spawn.get("polarity", -1)):
			errors.append("Invalid enemy kind or color")
		if not _supported(point, size, solids) or _embedded(point, size, solids):
			errors.append("Enemy is unsupported or embedded in terrain")
		var patrol_center := Vector2((patrol.x + patrol.y) / 2, point.y)
		var patrol_body := Vector2(patrol.y - patrol.x + size.x, size.y)
		if patrol.x > point.x or patrol.y < point.x or not _supported(patrol_center, patrol_body, solids) or _embedded(patrol_center, patrol_body, solids):
			errors.append("Enemy patrol leaves its supporting surface")
		if point.distance_to(start) < SAFE_RADIUS:
			errors.append("Enemy inside the safe starting region")
		var boss_id: int = spawn.get("boss_id", -1)
		if kind == "boss":
			if boss_id < 0 or boss_id > 2 or guardians.has(boss_id):
				errors.append("Invalid or duplicate guardian ID")
			if int(point.x / (WORLD_SIZE.x / 3)) != boss_id:
				errors.append("Each guardian must occupy its own region")
			guardians[boss_id] = point
		elif boss_id != -1:
			errors.append("Normal enemy has a guardian ID")
	if guardians.size() != 3 or not guardians.has(0) or not guardians.has(1) or not guardians.has(2):
		errors.append("The world requires three unique guardians")
	var biomes: Array = stage.get("biomes", [])
	if biomes.size() != 3:
		errors.append("The world requires three regions")
	else:
		for index in range(3):
			if biomes[index].get("id", -1) != index or biomes[index].get("rect", Rect2()) != Rect2(index * 4096, 0, 4096, WORLD_SIZE.y):
				errors.append("Regions must cover the open world without seams")
	var landmarks: Array = stage.get("landmarks", [])
	var known_landmarks := {}
	for landmark: Dictionary in landmarks:
		var id: int = landmark.get("id", -1)
		if not guardians.has(id) or known_landmarks.has(id) or landmark.get("position", Vector2(-1, -1)) != guardians.get(id):
			errors.append("Landmark must identify a unique guardian spawn")
		known_landmarks[id] = true
	if known_landmarks.size() != 3:
		errors.append("Missing guardian landmarks")
	var route_ids := {}
	for route: Dictionary in stage.get("routes", []):
		var id: int = route.get("boss_id", -1)
		var points: Array = route.get("points", [])
		if not guardians.has(id) or route_ids.has(id) or points.size() < 2:
			errors.append("Invalid or duplicate guardian route")
			continue
		route_ids[id] = true
		if points[0] != start:
			errors.append("Every route must start at the safe starting point")
		for index in range(points.size()):
			var point: Vector2 = points[index]
			if not _supported(point, T.PLAYER_SIZE, solids) or _embedded(point, T.PLAYER_SIZE, solids):
				errors.append("Route waypoint is unsupported or embedded")
			if index > 0:
				var previous: Vector2 = points[index - 1]
				if absf(point.x - previous.x) > FLOOR_WIDTH or absf(point.y - previous.y) > T.MAX_STEP_HEIGHT:
					errors.append("Route exceeds walking or single-jump reach")
		var target: Vector2 = guardians[id] + Vector2(0, T.BOSS_SIZE.y / 2 - T.PLAYER_SIZE.y / 2)
		if points[-1] != target:
			errors.append("Route does not reach the guardian supporting surface")
	if route_ids.size() != 3:
		errors.append("Every guardian needs a reversible walking and jumping route")
	return errors

static func signature(stage: Dictionary) -> String:
	var parts := PackedStringArray([str(stage.seed), str(stage.bounds), str(stage.start_position), str(stage.fallback)])
	for solid: Rect2 in stage.solids:
		parts.append("S:" + str(solid))
	for spawn: Dictionary in stage.spawns:
		parts.append("E:%s:%s:%d:%s:%s:%d" % [spawn.id, spawn.kind, spawn.polarity, spawn.position, spawn.patrol, spawn.boss_id])
	for biome: Dictionary in stage.biomes:
		parts.append("B:%d:%s:%s" % [biome.id, biome.name, biome.rect])
	for landmark: Dictionary in stage.landmarks:
		parts.append("L:%d:%s:%s" % [landmark.id, landmark.position, landmark.name])
	for route: Dictionary in stage.routes:
		parts.append("R:%d:%s" % [route.boss_id, str(route.points)])
	return "|".join(parts)
