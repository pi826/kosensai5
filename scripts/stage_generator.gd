extends RefCounted
## Buildings, bridges and explicit navigation in one persistent world.
const T := preload("res://scripts/tuning.gd")
const WORLD_SIZE := T.WORLD_SIZE
const GROUND_Y := T.GROUND_Y
const START_X := T.WORLD_START_X
const SAFE_RADIUS := 640.0
const NORMAL_KINDS := ["turret", "walker", "shifter", "flyer", "laser", "breaker", "builder"]
const REQUIRED_KINDS := NORMAL_KINDS

static func protected_column(left: float, right: float, exclusions: Array) -> bool:
	for interval: Vector2 in exclusions:
		if left < interval.y and right > interval.x: return true
	return false

static func flight_lane(floor_rect: Rect2) -> Rect2:
	var patrol := Vector2(floor_rect.position.x + T.FLYER_LANE_MARGIN, floor_rect.end.x - T.FLYER_LANE_MARGIN)
	var half := T.ENEMY_SIZE / 2 + Vector2(T.FLYER_CLEARANCE, T.FLYER_BOB_AMPLITUDE + T.FLYER_CLEARANCE)
	return Rect2(Vector2(patrol.x, floor_rect.position.y - T.FLYER_ALTITUDE) - half, Vector2(patrol.y - patrol.x, 0) + half * 2)

static func lane_is_clear(floor_rect: Rect2, solids: Array) -> bool:
	var lane := flight_lane(floor_rect)
	if not Rect2(Vector2.ZERO, WORLD_SIZE).encloses(lane): return false
	for solid: Rect2 in solids:
		if lane.intersects(solid): return false
		if solid.size.y <= 20 and solid.position.x < lane.end.x and solid.end.x > lane.position.x and solid.position.y >= lane.end.y and solid.position.y - lane.end.y < T.PLAYER_SIZE.y + 8: return false
	return true

static func generate(stage_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = stage_seed
	for attempt in range(T.GENERATION_RETRIES):
		var stage := _build(stage_seed, rng, false)
		if validate(stage).is_empty(): return stage
	return generate_fallback(stage_seed)

class FixedChoices extends RefCounted:
	# Explicit cyclic choices, not a random stream or a seed search.
	var cursor := 0
	func randi_range(low: int, high: int) -> int:
		const CHOICES = [0,2,1,1,0,2,2,0,1,2,1,0,1,2,0,0,2,1,1,0,2,1,2,0]
		var value: int = CHOICES[cursor % CHOICES.size()]
		cursor += 1
		return low + value % (high - low + 1)

static func generate_fallback(stage_seed: int) -> Dictionary:
	var stage := _build(stage_seed, FixedChoices.new(), true)
	assert(validate(stage).is_empty(), str(validate(stage)))
	return stage
static func _build(stage_seed: int, rng: RefCounted, fallback: bool) -> Dictionary:
	var stage := {"seed": stage_seed, "bounds": Rect2(Vector2.ZERO, WORLD_SIZE), "start_position": Vector2(START_X, GROUND_Y - T.PLAYER_SIZE.y / 2), "solids": [], "towers": [], "bridges": [], "spawns": [], "biomes": [], "landmarks": [], "routes": [], "fallback": fallback, "surface_exclusions": [], "breakables": [], "floors": [], "valleys": [], "inner_walls": []}
	var boss_ids: Array[int] = []
	for region in range(3):
		boss_ids.append(region * 3 + rng.randi_range(0, 2))
		stage.biomes.append({"id": region, "name": T.BIOME_NAMES[region], "rect": Rect2(region * 4096, 0, 4096, WORLD_SIZE.y)})
	for id in range(T.TOWER_COUNT):
		var width: int = rng.randi_range(T.TOWER_MIN_WIDTH / 32, T.TOWER_MAX_WIDTH / 32) * 32
		var left: int = T.TOWER_ANCHORS[id] + rng.randi_range(-T.TOWER_POSITION_JITTER / 32, T.TOWER_POSITION_JITTER / 32) * 32
		if id == 0: left = 0
		if id == T.TOWER_START_ID: left = T.TOWER_ANCHORS[id]
		if id == 8: left = int(WORLD_SIZE.x) - width
		var region := int(id / 3)
		left = clampi(left, region * 4096 + (T.REGION_BRIDGE_CLEARANCE if region > 0 else 0), (region + 1) * 4096 - width - (T.REGION_BRIDGE_CLEARANCE if region < 2 else 0))
		if id > 0:
			var preceding: Rect2 = stage.towers[-1].outer
			left = clampi(left, int(preceding.end.x) + T.BRIDGE_MIN_LENGTH, int(preceding.end.x) + T.BRIDGE_MAX_LENGTH)
		var boss := boss_ids.has(id)
		var roof: int = rng.randi_range((T.TOWER_MIN_ROOF if boss else T.TOWER_OTHER_MIN_ROOF) / 32, (T.TOWER_BOSS_MAX_ROOF if boss else T.TOWER_OTHER_MAX_ROOF) / 32) * 32
		var inner := Rect2(left + T.TOWER_WALL, roof, width - 2 * T.TOWER_WALL, GROUND_Y - roof)
		stage.towers.append({"id": id, "outer": Rect2(left, roof - T.TOWER_PARAPET, width, WORLD_SIZE.y - roof + T.TOWER_PARAPET), "interior": inner, "roof_y": roof, "region": region, "entrances": [], "boss": boss, "start": id == T.TOWER_START_ID, "platforms": [], "roof": Rect2(), "floor": Rect2(inner.position.x, GROUND_Y, inner.size.x, WORLD_SIZE.y - GROUND_Y)})
	var previous: Array = []
	for id in range(T.TOWER_COUNT - 1):
		var a: Dictionary = stage.towers[id]
		var b: Dictionary = stage.towers[id + 1]
		var available: Array = []
		var minimum: int = ceili(float(maxi(a.roof_y, b.roof_y) + T.BRIDGE_DOOR_HEIGHT + 32) / T.BRIDGE_HEIGHT_GRID) * T.BRIDGE_HEIGHT_GRID
		for y in range(minimum, int(GROUND_Y - T.TOWER_FIRST_STEP - T.TOWER_STEPS[0]) + 1, T.BRIDGE_HEIGHT_GRID):
			if not previous.has(y): available.append(y)
		var options := {1: [], 2: [], 3: []}
		for i in range(available.size()):
			options[1].append([available[i]])
			for j in range(i + 1, available.size()):
				if available[j] - available[i] < T.BRIDGE_MIN_SEPARATION: continue
				options[2].append([available[i], available[j]])
				for k in range(j + 1, available.size()):
					if available[k] - available[j] >= T.BRIDGE_MIN_SEPARATION: options[3].append([available[i], available[j], available[k]])
		var possible: Array = [1, 2, 3].filter(func(n): return not options[n].is_empty())
		var count: int = possible[rng.randi_range(0, possible.size() - 1)]
		var heights: Array = options[count][rng.randi_range(0, options[count].size() - 1)]
		previous = heights.duplicate()
		for y: int in heights:
			var rect := Rect2(a.outer.end.x, y, b.outer.position.x - a.outer.end.x, 16)
			var bridge := {"id": stage.bridges.size(), "rect": rect, "left_tower": id, "right_tower": id + 1}
			stage.bridges.append(bridge)
			stage.solids.append(rect)
			a.entrances.append({"bridge_id": bridge.id, "side": "right", "y": y, "rect": Rect2(a.interior.end.x, y - T.BRIDGE_DOOR_HEIGHT, T.TOWER_WALL, T.BRIDGE_DOOR_HEIGHT)})
			b.entrances.append({"bridge_id": bridge.id, "side": "left", "y": y, "rect": Rect2(b.outer.position.x, y - T.BRIDGE_DOOR_HEIGHT, T.TOWER_WALL, T.BRIDGE_DOOR_HEIGHT)})
		var valley := Rect2(a.outer.end.x, GROUND_Y, b.outer.position.x - a.outer.end.x, WORLD_SIZE.y - GROUND_Y)
		stage.valleys.append(valley)
		stage.solids.append(valley)
	for tower: Dictionary in stage.towers:
		var inner: Rect2 = tower.interior
		stage.solids.append(tower.floor)
		stage.floors.append(tower.floor)
		for side in ["left", "right"]:
			for wall: Rect2 in exterior_segments(tower, side): stage.solids.append(wall)
		var storeys := _storeys(tower, rng)
		tower.levels = storeys
		var wall_left: bool = rng.randi_range(0, 1) == 0
		for door: Dictionary in tower.entrances:
			if door.y == storeys[1]: wall_left = door.side == "left"
		for index in range(storeys.size()):
			var y: int = storeys[index]
			var alignment: int = rng.randi_range(0, 2)
			for door: Dictionary in tower.entrances:
				if door.y == y: alignment = 0 if door.side == "left" else 1
			if index == 0: alignment = 1 if wall_left else 0
			if index == 1: alignment = 0 if wall_left else 1
			var minimum_width: int = maxi(T.PLATFORM_MIN_WIDTH, ceili((inner.size.x + T.PLAYER_SIZE.x + 2 * T.LANDING_MARGIN) / 64) * 32)
			var maximum_width: int = int(inner.size.x) - (2 * T.PLATFORM_MIN_GAP if alignment == 2 else T.TOWER_DROP_GAP)
			var width: int = rng.randi_range(minimum_width / 32, maxi(minimum_width, maximum_width) / 32) * 32
			var x: float = inner.position.x if alignment == 0 else inner.end.x - width
			if alignment == 2: x = inner.position.x + floorf((inner.size.x - width) / 64) * 32
			var shelf := Rect2(x, y, width, T.PLATFORM_THICKNESS)
			tower.platforms.append(shelf)
			if y == tower.roof_y:
				tower.roof = shelf
			stage.solids.append(shelf)
			for door: Dictionary in tower.entrances:
				if door.y == y: door.landing = shelf
		_add_inner_walls(stage, tower, rng)
		if tower.start or tower.boss: stage.surface_exclusions.append(Vector2(tower.outer.position.x, tower.outer.end.x))
		if tower.boss:
			var point := Vector2(tower.roof.get_center().x, tower.roof_y - T.BOSS_SIZE.y / 2)
			stage.spawns.append({"id": "guardian_%d" % tower.region, "kind": "boss", "polarity": rng.randi_range(0, 1), "position": point, "patrol": Vector2(point.x, point.x), "boss_id": tower.region, "tower_id": tower.id})
			stage.landmarks.append({"id": tower.region, "position": point, "name": T.BIOME_NAMES[tower.region] + "の守護者"})
	_populate(stage, rng)
	var graph := navigation_graph(stage)
	var origin := node_at(graph, stage.start_position)
	for landmark: Dictionary in stage.landmarks:
		var destination: Vector2 = landmark.position + Vector2(0, T.BOSS_SIZE.y / 2 - T.PLAYER_SIZE.y / 2)
		var target := node_at(graph, destination)
		stage.routes.append({"boss_id": landmark.id, "outward": path_steps(graph, origin, target, destination), "return": path_steps(graph, target, origin, stage.start_position), "points": [stage.start_position, destination]})
	var candidates: Array = []
	for tower: Dictionary in stage.towers:
		for support: Rect2 in [tower.floor] + tower.platforms:
			if support.position.y != GROUND_Y and not tower.entrances.any(func(d): return d.y == support.position.y): continue
			for x in range(int(support.position.x) + 32, int(support.end.x) - 32, 32): candidates.append(Rect2(x, support.position.y - 32, 32, 32))
	for bridge: Dictionary in stage.bridges:
		for x in range(int(bridge.rect.position.x) + 32, int(bridge.rect.end.x) - 32, 32): candidates.append(Rect2(x, bridge.rect.position.y - 32, 32, 32))
	_shuffle(candidates, rng)
	var block_regions := {}
	for distinct_region in [true, false]:
		for block: Rect2 in candidates:
			if stage.breakables.size() >= T.WORLD_BLOCK_TARGET: break
			var region := int(block.get_center().x / 4096)
			if distinct_region and block_regions.has(region): continue
			if block_is_valid(block, stage):
				stage.breakables.append(block)
				block_regions[region] = true
	return stage

static func _shuffle(values: Array, rng: RefCounted) -> void:
	for i in range(values.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var value = values[i]
		values[i] = values[j]
		values[j] = value

static func _fillable(distance: int) -> bool:
	return distance == 0 or (distance >= T.TOWER_STEPS[0] and distance % T.TILE_SIZE == 0)

static func _storeys(tower: Dictionary, rng: RefCounted) -> Array[int]:
	var anchors: Array[int] = [int(tower.roof_y)]
	for door: Dictionary in tower.entrances:
		if not anchors.has(int(door.y)): anchors.append(int(door.y))
	anchors.sort()
	anchors.reverse()
	var levels: Array[int] = [int(GROUND_Y) - T.TOWER_FIRST_STEP]
	for anchor in anchors:
		while levels[-1] > anchor:
			var options: Array = T.TOWER_STEPS.filter(func(step): return _fillable(levels[-1] - anchor - step))
			levels.append(levels[-1] - options[rng.randi_range(0, options.size() - 1)])
	return levels

static func _add_inner_walls(stage: Dictionary, tower: Dictionary, rng: RefCounted) -> void:
	var ledges: Array = []
	var verticals: Array = []
	var inner: Rect2 = tower.interior
	for i in range(1, tower.platforms.size() - 1):
		var platform: Rect2 = tower.platforms[i]
		for left_side in [true, false]:
			var x: float = inner.position.x if left_side else inner.end.x - T.TOWER_INNER_LEDGE
			if platform.position.x > x or platform.end.x < x + T.TOWER_INNER_LEDGE: continue
			var ledge := Rect2(x, platform.position.y, T.TOWER_INNER_LEDGE, T.TOWER_LEDGE_DEPTH)
			if _wall_fits(ledge, tower): ledges.append(ledge)
			for width in range(T.INNER_WALL_MIN_WIDTH, T.INNER_WALL_MAX_WIDTH + 1, 32):
				for height in range(T.INNER_WALL_MIN_HEIGHT, T.INNER_WALL_MAX_HEIGHT + 1, 32):
					var wall := Rect2(inner.position.x if left_side else inner.end.x - width, platform.position.y, width, height)
					if _wall_fits(wall, tower): verticals.append(wall)
	if not ledges.is_empty():
		var ledge: Rect2 = ledges[rng.randi_range(0, ledges.size() - 1)]
		stage.inner_walls.append(ledge)
		stage.solids.append(ledge)
	if not verticals.is_empty():
		var wall: Rect2 = verticals[rng.randi_range(0, verticals.size() - 1)]
		stage.inner_walls.append(wall)
		stage.solids.append(wall)

static func _wall_fits(wall: Rect2, tower: Dictionary) -> bool:
	if wall.end.y > GROUND_Y - T.PLAYER_SIZE.y - 32: return false
	for platform: Rect2 in tower.platforms:
		if platform.position.y > wall.position.y and platform.position.y < wall.end.y + T.PLAYER_SIZE.y + 32 and platform.position.x < wall.end.x and platform.end.x > wall.position.x: return false
	for door: Dictionary in tower.entrances:
		if wall.intersects(door.rect.grow_individual(T.BRIDGE_DOOR_MARGIN, 0, T.BRIDGE_DOOR_MARGIN, 0)): return false
	return true

static func exterior_segments(tower: Dictionary, side: String) -> Array[Rect2]:
	var result: Array[Rect2] = []
	var x: float = tower.outer.position.x if side == "left" else tower.interior.end.x
	var openings: Array = tower.entrances.filter(func(d): return d.side == side)
	openings.sort_custom(func(a, b): return a.y < b.y)
	var y: float = tower.roof_y - T.TOWER_PARAPET
	for door: Dictionary in openings:
		result.append(Rect2(x, y, T.TOWER_WALL, door.y - T.BRIDGE_DOOR_HEIGHT - y))
		y = door.y
	result.append(Rect2(x, y, T.TOWER_WALL, WORLD_SIZE.y - y))
	return result

static func doorway_clearance(stage: Dictionary, rect: Rect2) -> bool:
	for tower: Dictionary in stage.get("towers", []):
		for door: Dictionary in tower.entrances:
			if door.rect.grow_individual(T.BRIDGE_DOOR_MARGIN, 0, T.BRIDGE_DOOR_MARGIN, 0).intersects(rect): return false
	return true

static func _populate(stage: Dictionary, rng: RefCounted) -> void:
	var supports: Array = []
	var bridge_supports: Array = []
	for bridge: Dictionary in stage.bridges: bridge_supports.append({"rect": bridge.rect, "zone": "bridge"})
	for tower: Dictionary in stage.towers:
		if tower.start: continue
		supports.append({"rect": tower.floor, "zone": "floor"})
		if not tower.boss: supports.append({"rect": tower.roof, "zone": "roof"})
		for door: Dictionary in tower.entrances: supports.append({"rect": door.landing, "zone": "landing"})
		for wall: Rect2 in stage.inner_walls:
			if wall.position.x >= tower.interior.position.x and wall.end.x <= tower.interior.end.x: supports.append({"rect": wall, "zone": "wall"})
	_shuffle(bridge_supports, rng)
	# Reserve the bridge quota, then draw from a shuffled mixture of all locations.
	var bridge_quota := ceili(T.WORLD_NORMAL_ENEMIES * T.BRIDGE_ENEMY_MIN_RATIO)
	for pass_index in range(2):
		for candidate: Dictionary in bridge_supports:
			if stage.spawns.size() - 3 >= bridge_quota: break
			_spawn_random(stage, candidate, rng)
		_shuffle(bridge_supports, rng)
	supports.append_array(bridge_supports)
	supports.append_array(bridge_supports)
	_shuffle(supports, rng)
	var floor_count := 0
	for candidate: Dictionary in supports:
		if stage.spawns.size() >= T.WORLD_NORMAL_ENEMIES + 3: break
		if candidate.zone == "floor" and floor_count >= floori(T.WORLD_NORMAL_ENEMIES * T.FLOOR_ENEMY_MAX_RATIO): continue
		if not _spawn_random(stage, candidate, rng).is_empty() and candidate.zone == "floor": floor_count += 1
	# Replace surplus kinds using the same support/embedding/lane checks.
	for required: String in REQUIRED_KINDS:
		if stage.spawns.any(func(s): return s.kind == required): continue
		var choices: Array = stage.spawns.filter(func(s): return s.kind != "boss" and stage.spawns.filter(func(other): return other.kind == s.kind).size() > 1)
		_shuffle(choices, rng)
		for old: Dictionary in choices:
			if required == "flyer" and (old.zone != "bridge" or not lane_is_clear(old.support, stage.solids)): continue
			stage.spawns.erase(old)
			var replacement := _spawn(stage, required, old.support, rng)
			if replacement.is_empty():
				stage.spawns.append(old)
				continue
			replacement.id = old.id
			replacement.zone = old.zone
			break

static func _spawn_random(stage: Dictionary, candidate: Dictionary, rng: RefCounted) -> Dictionary:
	var kinds: Array = NORMAL_KINDS.filter(func(kind): return kind != "flyer" or (candidate.zone == "bridge" and lane_is_clear(candidate.rect, stage.solids)))
	_shuffle(kinds, rng)
	for kind: String in kinds:
		var spawn := _spawn(stage, kind, candidate.rect, rng)
		if not spawn.is_empty():
			spawn.zone = candidate.zone
			return spawn
	return {}

static func _spawn(stage: Dictionary, kind: String, support: Rect2, rng: RefCounted) -> Dictionary:
	if support.size.x < T.ENEMY_SIZE.x or (kind == "walker" and support.size.x < 2 * T.FLYER_LANE_MARGIN): return {}
	var point := Vector2(support.get_center().x, support.position.y - (T.FLYER_ALTITUDE if kind == "flyer" else T.ENEMY_SIZE.y / 2))
	if point.distance_to(stage.start_position) < SAFE_RADIUS: return {}
	var start: Rect2 = stage.towers[T.TOWER_START_ID].interior
	if point.x > start.position.x and point.x < start.end.x: return {}
	var patrol := Vector2(point.x, point.x)
	if kind == "walker": patrol = Vector2(maxf(support.position.x + 48, point.x - 80), minf(support.end.x - 48, point.x + 80))
	if kind == "flyer": patrol = Vector2(support.position.x + T.FLYER_LANE_MARGIN, support.end.x - T.FLYER_LANE_MARGIN)
	var body := Rect2(Vector2(patrol.x - T.ENEMY_SIZE.x / 2, point.y - T.ENEMY_SIZE.y / 2), Vector2(patrol.y - patrol.x + T.ENEMY_SIZE.x, T.ENEMY_SIZE.y))
	if kind != "flyer" and _embedded(body.get_center(), body.size, stage.solids): return {}
	for other: Dictionary in stage.spawns:
		if other.position.distance_to(point) < 96: return {}
	var spawn := {"id": "enemy_%d" % stage.spawns.size(), "kind": kind, "position": point, "patrol": patrol, "polarity": rng.randi_range(0, 1), "boss_id": -1, "floor_index": stage.solids.find(support), "support": support}
	stage.spawns.append(spawn)
	return spawn

static func block_is_valid(block: Rect2, stage: Dictionary) -> bool:
	if block.size.x < 32 or block.size.y < 32 or block.size.x > 64 or block.size.y > 64: return false
	for value in [block.position.x, block.position.y, block.size.x, block.size.y]:
		if fmod(value, 32) != 0: return false
	if absf(block.get_center().x - START_X) < SAFE_RADIUS or not doorway_clearance(stage, block): return false
	if not _supported(block.get_center(), block.size, stage.solids) or _embedded(block.get_center(), block.size, stage.solids): return false
	for other: Rect2 in stage.get("breakables", []):
		if block.intersects(other): return false
	for spawn: Dictionary in stage.spawns:
		if spawn.kind == "flyer":
			if block.intersects(flight_lane(spawn.support)): return false
		else:
			var size: Vector2 = T.BOSS_SIZE if spawn.kind == "boss" else T.ENEMY_SIZE
			if block.intersects(Rect2(Vector2(spawn.patrol.x - size.x / 2, spawn.position.y - size.y / 2), Vector2(spawn.patrol.y - spawn.patrol.x + size.x, size.y))): return false
	for route: Dictionary in stage.routes:
		for steps: Array in [route.outward, route["return"]]:
			var current: Vector2 = stage.start_position if steps == route.outward else route.points[-1]
			for step: Dictionary in steps:
				for key in ["position", "target"]:
					if step.has(key) and block.intersects(Rect2(step[key] - T.PLAYER_SIZE / 2 - Vector2(16, 0), T.PLAYER_SIZE + Vector2(32, 0))): return false
				if step.action == "walk":
					var corridor := Rect2(Vector2(minf(current.x,step.position.x) - T.PLAYER_SIZE.x / 2 - 16,current.y - T.PLAYER_SIZE.y / 2),Vector2(absf(current.x - step.position.x) + T.PLAYER_SIZE.x + 32,T.PLAYER_SIZE.y))
					if block.intersects(corridor): return false
					current = step.position
				else: current = step.target
	return true

static func _supported(point: Vector2, size: Vector2, solids: Array) -> bool:
	var spans: Array[Vector2] = []
	for solid: Rect2 in solids:
		if is_equal_approx(point.y + size.y / 2, solid.position.y): spans.append(Vector2(solid.position.x, solid.end.x))
	spans.sort_custom(func(a, b): return a.x < b.x)
	var covered := point.x - size.x / 2
	for span: Vector2 in spans:
		if span.x <= covered and span.y > covered: covered = span.y
		if covered >= point.x + size.x / 2: return true
	return false

static func _embedded(point: Vector2, size: Vector2, solids: Array) -> bool:
	var body := Rect2(point - size / 2, size).grow(-0.1)
	for solid: Rect2 in solids:
		if body.intersects(solid): return true
	return false

# Horizontal spans are split by solid headroom blockers, then coalesced only
# across level, unobstructed seams (landing -> sill -> bridge -> opposite sill).
static func _subtract(spans: Array[Vector2], left: float, right: float) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for span: Vector2 in spans:
		if right <= span.x or left >= span.y: result.append(span)
		else:
			if left > span.x: result.append(Vector2(span.x, left))
			if right < span.y: result.append(Vector2(right, span.y))
	return result

static func damaged_solids(stage: Dictionary) -> Array:
	var result: Array = []
	for solid: Rect2 in stage.solids:
		if not stage.floors.has(solid):
			result.append(solid)
			continue
		for x in range(int(solid.position.x), int(solid.end.x), 32):
			var depth := 0 if protected_column(x, x + 32, stage.surface_exclusions) else T.SURFACE_DEPTH
			result.append(Rect2(x, solid.position.y + depth, 32, solid.size.y - depth))
	return result

static func navigation_graph(stage: Dictionary, damaged: bool = false) -> Dictionary:
	var solids: Array = damaged_solids(stage) if damaged else stage.solids
	var thick: Array = solids.filter(func(s): return s.size.y > 20)
	var surfaces: Array[Rect2] = []
	for solid: Rect2 in solids:
		var spans: Array[Vector2] = [Vector2(solid.position.x, solid.end.x)]
		for blocker: Rect2 in thick:
			if blocker.position.y < solid.position.y and blocker.end.y > solid.position.y - T.PLAYER_SIZE.y - 32:
				spans = _subtract(spans, blocker.position.x, blocker.end.x)
		for span: Vector2 in spans:
			if span.y - span.x >= T.PLAYER_SIZE.x: surfaces.append(Rect2(span.x, solid.position.y, span.y - span.x, 0))
	surfaces.sort_custom(func(a, b): return a.position.y < b.position.y or (a.position.y == b.position.y and a.position.x < b.position.x))
	var nodes: Array[Rect2] = []
	for surface: Rect2 in surfaces:
		if not nodes.is_empty() and nodes[-1].position.y == surface.position.y and surface.position.x <= nodes[-1].end.x:
			var merged: Rect2 = nodes[-1]
			merged.size.x = maxf(merged.end.x, surface.end.x) - merged.position.x
			nodes[-1] = merged
		else: nodes.append(surface)
	var edges: Array = []
	for i in range(nodes.size()): edges.append([])
	for i in range(nodes.size()):
		var lower: Rect2 = nodes[i]
		for j in range(nodes.size()):
			var upper: Rect2 = nodes[j]
			var rise := lower.position.y - upper.position.y
			if rise <= 0 or rise > T.MAX_STEP_HEIGHT: continue
			var overlap: Array[Vector2] = [Vector2(maxf(lower.position.x, upper.position.x), minf(lower.end.x, upper.end.x))]
			if overlap[0].y - overlap[0].x < T.PLAYER_SIZE.x + 2 * T.LANDING_MARGIN: continue
			for blocker: Rect2 in thick:
				if blocker.position.y < lower.position.y and blocker.end.y > lower.position.y - T.JUMP_SPEED * T.JUMP_SPEED / (2 * T.GRAVITY) - T.PLAYER_SIZE.y:
					overlap = _subtract(overlap, blocker.position.x, blocker.end.x)
			for span: Vector2 in overlap:
				if span.y - span.x >= T.PLAYER_SIZE.x + 2 * T.LANDING_MARGIN:
					var x := (span.x + span.y) / 2
					edges[i].append({"to": j, "action": "jump", "x": x, "position": Vector2(x, lower.position.y - T.PLAYER_SIZE.y / 2), "target": Vector2(x, upper.position.y - T.PLAYER_SIZE.y / 2)})
					break
		for direction in [-1, 1]:
			for extra in [0, T.TILE_SIZE, 2 * T.TILE_SIZE]:
				var x: float = (lower.position.x if direction < 0 else lower.end.x) + direction * (T.PLAYER_SIZE.x / 2 + T.DROP_EXIT_MARGIN + extra)
				var point := Vector2(x, lower.position.y - T.PLAYER_SIZE.y / 2)
				if _embedded(point, T.PLAYER_SIZE, thick): continue
				var edge_x: float = lower.position.x if direction < 0 else lower.end.x
				var departure := Rect2(Vector2(minf(x,edge_x) - T.PLAYER_SIZE.x / 2,lower.position.y - T.PLAYER_SIZE.y),Vector2(absf(x - edge_x) + T.PLAYER_SIZE.x,T.PLAYER_SIZE.y)).grow(-0.1)
				if thick.any(func(s): return s.intersects(departure)): continue
				if solids.any(func(s): return s.position.y == lower.position.y and s.position.x < x + T.PLAYER_SIZE.x / 2 and s.end.x > x - T.PLAYER_SIZE.x / 2): continue
				var target := -1
				var y := INF
				# Even a partial intersection catches the body on a one-way platform.
				# Never skip that first collision to claim a lower landing.
				for solid: Rect2 in solids:
					if solid.position.y > lower.position.y and solid.position.y < y and solid.position.x < x + T.PLAYER_SIZE.x / 2 and solid.end.x > x - T.PLAYER_SIZE.x / 2: y = solid.position.y
				for j in range(nodes.size()):
					var surface: Rect2 = nodes[j]
					if surface.position.y == y and x - T.PLAYER_SIZE.x / 2 - T.LANDING_MARGIN >= surface.position.x and x + T.PLAYER_SIZE.x / 2 + T.LANDING_MARGIN <= surface.end.x: target = j
				if target >= 0:
					var swept_clear := true
					for solid: Rect2 in solids:
						if solid.position.y <= lower.position.y or solid.position.y >= y: continue
						var distance := solid.position.y - lower.position.y
						var terminal_distance := T.MAX_FALL_SPEED * T.MAX_FALL_SPEED / (2 * T.FALL_GRAVITY)
						var fall_time := sqrt(2 * distance / T.FALL_GRAVITY) if distance <= terminal_distance else T.MAX_FALL_SPEED / T.FALL_GRAVITY + (distance - terminal_distance) / T.MAX_FALL_SPEED
						var travel := minf(absf(x - edge_x),T.PLAYER_SIZE.x / 2 + T.MOVE_SPEED * fall_time)
						var falling_x: float = edge_x + direction * travel
						if solid.position.x < falling_x + T.PLAYER_SIZE.x / 2 + T.LANDING_MARGIN and solid.end.x > falling_x - T.PLAYER_SIZE.x / 2 - T.LANDING_MARGIN:
							swept_clear = false
							break
					if not swept_clear: continue
					var column := Rect2(x - T.PLAYER_SIZE.x / 2, lower.position.y - T.PLAYER_SIZE.y, T.PLAYER_SIZE.x, y - lower.position.y + T.PLAYER_SIZE.y - 0.1)
					if thick.any(func(s): return s.intersects(column)): continue
					edges[i].append({"to": target, "action": "drop", "x": x, "position": point, "target": Vector2(x, y - T.PLAYER_SIZE.y / 2)})
					break
	return {"nodes": nodes, "edges": edges}

static func node_at(graph: Dictionary, point: Vector2) -> int:
	for id in range(graph.nodes.size()):
		var rect: Rect2 = graph.nodes[id]
		if absf(rect.position.y - point.y - T.PLAYER_SIZE.y / 2) < 0.5 and point.x >= rect.position.x + T.PLAYER_SIZE.x / 2 and point.x <= rect.end.x - T.PLAYER_SIZE.x / 2: return id
	return -1

static func _search(graph: Dictionary, origin: int, reverse: bool = false) -> Dictionary:
	if origin < 0: return {}
	var adjacent: Array = graph.edges
	if reverse:
		adjacent = []
		for i in range(graph.nodes.size()): adjacent.append([])
		for i in range(graph.nodes.size()):
			for edge: Dictionary in graph.edges[i]: adjacent[edge.to].append({"to": i})
	var found := {origin: {}}
	var queue := [origin]
	var index := 0
	while index < queue.size():
		var id: int = queue[index]
		index += 1
		for edge: Dictionary in adjacent[id]:
			if not found.has(edge.to):
				found[edge.to] = {"from": id, "edge": edge}
				queue.append(edge.to)
	return found

static func path_steps(graph: Dictionary, origin: int, target: int, end: Vector2) -> Array:
	var found := _search(graph, origin)
	if not found.has(target): return []
	var sequence: Array = []
	var id := target
	while id != origin:
		sequence.push_front(found[id].edge.duplicate())
		id = found[id].from
	var result: Array = []
	for edge: Dictionary in sequence:
		if edge.action == "jump": result.append({"action": "walk", "x": edge.x, "position": edge.position})
		result.append(edge)
	result.append({"action": "walk", "x": end.x, "position": end})
	return result

static func connectivity_errors(stage: Dictionary, damaged: bool = false) -> Array[String]:
	var errors: Array[String] = []
	var graph := navigation_graph(stage, damaged)
	var origin := node_at(graph, stage.start_position)
	var forward := _search(graph, origin)
	var backward := _search(graph, origin, true)
	var targets: Array[Vector2] = [stage.start_position]
	for tower: Dictionary in stage.towers:
		targets.append(Vector2(tower.platforms[0].get_center().x, GROUND_Y + (T.SURFACE_DEPTH if damaged and not tower.start and not tower.boss else 0) - T.PLAYER_SIZE.y / 2))
		for platform: Rect2 in tower.platforms: targets.append(Vector2(platform.get_center().x, platform.position.y - T.PLAYER_SIZE.y / 2))
		for door: Dictionary in tower.entrances: targets.append(Vector2(door.landing.get_center().x, door.y - T.PLAYER_SIZE.y / 2))
	for bridge: Dictionary in stage.bridges: targets.append(Vector2(bridge.rect.get_center().x, bridge.rect.position.y - T.PLAYER_SIZE.y / 2))
	for landmark: Dictionary in stage.landmarks: targets.append(landmark.position + Vector2(0, T.BOSS_SIZE.y / 2 - T.PLAYER_SIZE.y / 2))
	for solid: Rect2 in stage.solids:
		if solid.size.y <= 20: targets.append(Vector2(solid.get_center().x, solid.position.y - T.PLAYER_SIZE.y / 2))
	for point: Vector2 in targets:
		var id := node_at(graph, point)
		if not forward.has(id) or not backward.has(id): errors.append("Surface is not strongly connected%s at %s" % [" after excavation" if damaged else "", point])
	for valley: Rect2 in stage.valleys:
		for id in forward:
			var node: Rect2 = graph.nodes[id]
			if node.position.y == GROUND_Y and node.position.x < valley.end.x and node.end.x > valley.position.x: errors.append("Valley floor is reachable")
	return errors

static func validate(stage: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if stage.get("bounds", Rect2()) != Rect2(Vector2.ZERO, WORLD_SIZE) or stage.get("towers", []).size() != T.TOWER_COUNT: return ["Invalid bounds or tower count"]
	var solids: Array = stage.solids
	for solid: Rect2 in solids:
		if solid.size.x <= 0 or solid.size.y <= 0 or not stage.bounds.encloses(solid): errors.append("Invalid solid bounds")
		for value in [solid.position.x, solid.position.y, solid.size.x]:
			if fmod(value, 32) != 0: errors.append("Terrain is off grid")
		for valley: Rect2 in stage.valleys:
			if solid.position.x < valley.end.x and solid.end.x > valley.position.x and not stage.valleys.has(solid) and not stage.bridges.any(func(b): return b.rect == solid): errors.append("Only bridges and valley floor may occupy a tower gap")
	var all_heights := {}
	var counts := {}
	var previous_set: Array = []
	for index in range(T.TOWER_COUNT - 1):
		var bridges: Array = stage.bridges.filter(func(b): return b.left_tower == index and b.right_tower == index + 1)
		if bridges.is_empty() or bridges.size() > 3: errors.append("Adjacent towers need one to three bridges")
		counts[bridges.size()] = true
		var heights: Array = []
		for bridge: Dictionary in bridges:
			var a: Dictionary = stage.towers[index]
			var b: Dictionary = stage.towers[index + 1]
			var rect: Rect2 = bridge.rect
			var y := rect.position.y
			if rect.position.x != a.outer.end.x or rect.end.x != b.outer.position.x or rect.size.y != 16 or not solids.has(rect): errors.append("Bridge has a gap or missing collision")
			if y < maxi(a.roof_y, b.roof_y) + T.BRIDGE_DOOR_HEIGHT + 32 or y > GROUND_Y - 160: errors.append("Invalid bridge height")
			for other in heights:
				if absf(other - y) < T.BRIDGE_MIN_SEPARATION: errors.append("Bridges are too close vertically")
			heights.append(y)
			all_heights[y] = true
			for tower: Dictionary in [a, b]:
				var doors: Array = tower.entrances.filter(func(d): return d.bridge_id == bridge.id and d.y == y and d.side == ("right" if tower.id == index else "left"))
				if doors.size() != 1: errors.append("Bridge has no matching opening")
				elif not doors[0].has("landing") or doors[0].landing.size.x < 160: errors.append("Opening has no landing")
		heights.sort()
		if heights == previous_set: errors.append("Adjacent bridge height sets must differ")
		previous_set = heights
	if all_heights.size() < 4 or not counts.has(1) or counts.size() < 2: errors.append("Bridge heights/counts lack variety")
	var distinct_levels := {}
	var preceding_levels: Array = []
	for tower: Dictionary in stage.towers:
		var inner: Rect2 = tower.interior
		if tower.outer.size.x < T.TOWER_MIN_WIDTH or tower.outer.size.x > T.TOWER_MAX_WIDTH or inner.size.x != tower.outer.size.x - 128: errors.append("Invalid tower width")
		if tower.roof_y < T.TOWER_MIN_ROOF or tower.roof_y > T.TOWER_MAX_ROOF or not solids.has(tower.floor): errors.append("Invalid tower roof or floor")
		if tower.id < T.TOWER_COUNT - 1:
			var gap: float = stage.towers[tower.id + 1].outer.position.x - tower.outer.end.x
			if gap < T.BRIDGE_MIN_LENGTH or gap > T.BRIDGE_MAX_LENGTH: errors.append("Invalid tower gap")
		for side in ["left", "right"]:
			for wall: Rect2 in exterior_segments(tower, side):
				if not solids.has(wall): errors.append("Exterior wall is open away from a bridge")
		for door: Dictionary in tower.entrances:
			if not stage.bridges.any(func(b): return b.id == door.bridge_id and b.rect.position.y == door.y and (b.left_tower == tower.id or b.right_tower == tower.id)): errors.append("Opening has no bridge")
			var expected := Rect2(tower.outer.position.x if door.side == "left" else inner.end.x, door.y - T.BRIDGE_DOOR_HEIGHT, T.TOWER_WALL, T.BRIDGE_DOOR_HEIGHT)
			if door.rect != expected or solids.any(func(s): return s.intersects(expected)): errors.append("Opening is blocked or misplaced")
		var walls: Array = stage.inner_walls.filter(func(w): return inner.encloses(w))
		if not walls.any(func(w): return w.size.x >= 96 and w.size.x <= 224 and w.size.y >= 32 and w.size.y <= 64 and (w.position.x == inner.position.x or w.end.x == inner.end.x)): errors.append("Tower needs an overhanging solid ledge")
		if not walls.any(func(w): return w.size.x >= T.INNER_WALL_MIN_WIDTH and w.size.x <= T.INNER_WALL_MAX_WIDTH and w.size.y >= T.INNER_WALL_MIN_HEIGHT and w.size.y <= T.INNER_WALL_MAX_HEIGHT): errors.append("Tower needs a vertical inner wall")
		for wall: Rect2 in walls:
			if not solids.has(wall) or not _wall_fits(wall, tower) or not tower.platforms.any(func(p): return p.position.y == wall.position.y and p.position.x <= wall.position.x and p.end.x >= wall.end.x): errors.append("Inner wall lacks support or obstructs standing clearance/entrance")
		if tower.roof.size.x > inner.size.x - 96 or not solids.has(tower.roof): errors.append("Roof needs a descent hatch")
		if inner.position.x != tower.outer.position.x + T.TOWER_WALL or inner.end.x != tower.outer.end.x - T.TOWER_WALL or inner.position.y != tower.roof_y or inner.end.y != GROUND_Y: errors.append("Invalid tower interior")
		var levels: Array = []
		var platform_widths := {}
		for index in range(tower.platforms.size()):
			var platform: Rect2 = tower.platforms[index]
			platform_widths[platform.size.x] = true
			levels.append(platform.position.y)
			var rise: float = GROUND_Y - platform.position.y if index == 0 else tower.platforms[index - 1].position.y - platform.position.y
			if rise < T.TOWER_STEPS[0] or rise > T.TOWER_STEPS[-1] or (index == 0 and rise != T.TOWER_FIRST_STEP) or platform.size.x < T.PLATFORM_MIN_WIDTH or platform.size.x > inner.size.x - T.PLATFORM_MIN_GAP or platform.position.x < inner.position.x or platform.end.x > inner.end.x or maxf(platform.position.x - inner.position.x, inner.end.x - platform.end.x) < T.PLATFORM_MIN_GAP: errors.append("Invalid storey spacing, width or descent gap")
			if index > 0 and minf(platform.end.x, tower.platforms[index - 1].end.x) - maxf(platform.position.x, tower.platforms[index - 1].position.x) < T.PLAYER_SIZE.x + 2 * T.LANDING_MARGIN: errors.append("Consecutive platforms lack jump overlap")
			# Solid shelves reduce clearance by their thickness, unlike one-way decks.
			for wall: Rect2 in stage.inner_walls:
				if wall.position.y < platform.position.y and wall.end.y > platform.position.y - T.PLAYER_SIZE.y - 32 and wall.position.x < platform.end.x and wall.end.x > platform.position.x: errors.append("Solid ledge leaves insufficient standing headroom")
		if levels == preceding_levels: errors.append("Adjacent towers share storey heights")
		if platform_widths.size() < 2: errors.append("Tower platform widths lack variety")
		preceding_levels = levels
		distinct_levels[str(levels)] = true
	if distinct_levels.size() < 7: errors.append("Too few distinct tower storey sequences")
	var ids := {}
	var kinds := {}
	var bosses := {}
	var normals := 0
	var bridge_enemies := 0
	var floor_enemies := 0
	for spawn: Dictionary in stage.spawns:
		if ids.has(spawn.id): errors.append("Duplicate enemy ID")
		ids[spawn.id] = true
		kinds[spawn.kind] = true
		if not [0, 1].has(spawn.polarity): errors.append("Invalid polarity")
		var size: Vector2 = T.BOSS_SIZE if spawn.kind == "boss" else T.ENEMY_SIZE
		if spawn.kind == "flyer":
			if not stage.bridges.any(func(b): return b.rect == spawn.support) or not lane_is_clear(spawn.support, solids) or spawn.position.y != spawn.support.position.y - T.FLYER_ALTITUDE or spawn.patrol != Vector2(spawn.support.position.x + T.FLYER_LANE_MARGIN, spawn.support.end.x - T.FLYER_LANE_MARGIN): errors.append("Invalid flight lane")
		else:
			var center := Vector2((spawn.patrol.x + spawn.patrol.y) / 2, spawn.position.y)
			var body := Vector2(spawn.patrol.y - spawn.patrol.x + size.x, size.y)
			if not _supported(center, body, solids) or _embedded(center, body, solids): errors.append("Unsupported or embedded enemy patrol")
		if spawn.position.distance_to(stage.start_position) < SAFE_RADIUS: errors.append("Enemy in starting safe radius")
		if spawn.kind == "boss":
			if bosses.has(spawn.boss_id): errors.append("Duplicate guardian")
			bosses[spawn.boss_id] = true
			var tower: Dictionary = stage.towers[spawn.tower_id]
			if int(spawn.position.x / 4096) != spawn.boss_id or tower.region != spawn.boss_id or tower.interior.size.x < 512 or GROUND_Y - tower.roof_y < 1152 or spawn.position.y + T.BOSS_SIZE.y / 2 != tower.roof_y: errors.append("Guardian is not on its region's roof")
			for other: Dictionary in stage.towers:
				if other.region == tower.region and other.id != tower.id and other.roof_y <= tower.roof_y: errors.append("Guardian tower is not uniquely highest")
		else:
			normals += 1
			if stage.bridges.any(func(b): return b.rect == spawn.support): bridge_enemies += 1
			if stage.floors.has(spawn.support): floor_enemies += 1
			if not NORMAL_KINDS.has(spawn.kind) or spawn.boss_id != -1: errors.append("Invalid normal enemy")
			var start: Rect2 = stage.towers[T.TOWER_START_ID].interior
			if spawn.position.x > start.position.x and spawn.position.x < start.end.x: errors.append("Normal enemy inside starting tower")
	if bosses.size() != 3 or normals < 20 or normals > 30: errors.append("Incorrect enemy count")
	if bridge_enemies < ceili(normals * T.BRIDGE_ENEMY_MIN_RATIO) or floor_enemies > floori(normals * T.FLOOR_ENEMY_MAX_RATIO): errors.append("Enemy placement lacks bridge/floor balance")
	for kind in REQUIRED_KINDS:
		if not kinds.has(kind): errors.append("Missing required enemy: " + kind)
	if stage.breakables.size() < T.BREAKABLE_MIN_COUNT: errors.append("Too few breakable blocks")
	var fixture := stage.duplicate(false)
	fixture.breakables = []
	var block_regions := {}
	for block: Rect2 in stage.breakables:
		if not block_is_valid(block, fixture): errors.append("Invalid breakable block")
		fixture.breakables.append(block)
		block_regions[int(block.get_center().x / 4096)] = true
	if block_regions.size() < 2: errors.append("Breakables need at least two regions")
	if not _supported(stage.start_position, T.PLAYER_SIZE, solids) or _embedded(stage.start_position, T.PLAYER_SIZE, solids): errors.append("Invalid start")
	if stage.biomes.size() != 3 or stage.landmarks.size() != 3 or stage.routes.size() != 3: errors.append("Missing regions, landmarks or routes")
	else:
		for id in range(3):
			if stage.biomes[id].id != id or stage.biomes[id].rect != Rect2(id * 4096, 0, 4096, WORLD_SIZE.y): errors.append("Regions must cover fixed thirds of the world")
	var route_graph := navigation_graph(stage)
	var route_ids := {}
	for route: Dictionary in stage.routes:
		if route.outward.is_empty() or route["return"].is_empty(): errors.append("Missing outbound or return route")
		if route_ids.has(route.boss_id): errors.append("Duplicate guardian route")
		route_ids[route.boss_id] = true
		var guardian: Array = stage.spawns.filter(func(s): return s.kind == "boss" and s.boss_id == route.boss_id)
		if guardian.size() != 1: errors.append("Unknown route guardian")
		else:
			var end: Vector2 = guardian[0].position + Vector2(0, T.BOSS_SIZE.y / 2 - T.PLAYER_SIZE.y / 2)
			if not route_is_valid(route_graph, route.outward, stage.start_position, end) or not route_is_valid(route_graph, route["return"], end, stage.start_position): errors.append("Invalid physical route actions")
	errors.append_array(connectivity_errors(stage))
	errors.append_array(connectivity_errors(stage, true))
	return errors

static func route_is_valid(graph: Dictionary, steps: Array, start: Vector2, end: Vector2) -> bool:
	var current := start
	for step: Dictionary in steps:
		var from := node_at(graph, current)
		if step.get("action", "") == "walk":
			if not step.has("position") or step.x != step.position.x or node_at(graph, step.position) != from or from < 0: return false
			current = step.position
		else:
			if from < 0 or not graph.edges[from].any(func(e): return e.action == step.get("action", "") and e.x == step.get("x", INF) and e.target == step.get("target", Vector2.INF)): return false
			current = step.target
	return current == end

static func signature(stage: Dictionary) -> String:
	return str([stage.seed, stage.bounds, stage.start_position, stage.fallback, stage.towers, stage.bridges, stage.solids, stage.spawns, stage.breakables, stage.surface_exclusions, stage.routes, stage.biomes, stage.landmarks, stage.inner_walls, stage.valleys, stage.floors])
