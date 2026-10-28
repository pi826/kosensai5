extends RefCounted
## Seeded carving and geometry-derived navigation in a single persistent cave.
const T := preload("res://scripts/tuning.gd")
const Laser := preload("res://scripts/laser_beam.gd")
const SAFE_RADIUS := T.CAVE_SAFE_RADIUS
const NORMAL_KINDS := ["turret", "walker", "shifter", "flyer", "laser", "breaker", "builder"]
const REQUIRED_KINDS := NORMAL_KINDS

static func _pick(rng, first: int, last: int) -> int:
	return first if rng == null else rng.randi_range(first, last)

static func _shuffle(items: Array, rng) -> void:
	if rng == null: return
	for i in range(items.size() - 1, 0, -1):
		var j := _pick(rng, 0, i)
		var swap = items[i]
		items[i] = items[j]
		items[j] = swap

static func _candidate(a: Dictionary, b: Dictionary, rooms: Array, rng) -> Dictionary:
	var ar: Rect2 = a.rect
	var br: Rect2 = b.rect
	if ar.position.x > br.position.x:
		var swap = a
		a = b
		b = swap
		ar = a.rect
		br = b.rect
	var gap := br.position.x - ar.end.x
	var rise := absf(ar.end.y - br.end.y)
	if gap >= T.CAVE_TUNNEL_MIN_LENGTH and gap + 64 <= T.CAVE_TUNNEL_MAX_LENGTH and rise <= minf(gap / 2, 384):
		var height := _pick(rng, T.CAVE_TUNNEL_MIN_HEIGHT / 32, T.CAVE_TUNNEL_MAX_HEIGHT / 32) * 32
		var pieces: Array = []
		var left := int(ar.end.x - 32)
		var right := int(br.position.x + 32)
		for x in range(left, right, 64):
			var t := clampf(float(x + 32 - ar.end.x) / gap, 0, 1)
			var y := snappedf(lerpf(ar.end.y, br.end.y, t), 32)
			if x == left: y = ar.end.y
			if x + 64 >= right: y = br.end.y
			pieces.append(Rect2(x, y - height, mini(64, right - x), height))
		var bounds: Rect2 = pieces[0]
		for piece: Rect2 in pieces: bounds = bounds.merge(piece)
		var exclusion := bounds.grow(32)
		for room: Dictionary in rooms:
			if room.id != a.id and room.id != b.id and exclusion.intersects(room.rect): return {}
		return {"a": a.id, "b": b.id, "rect": bounds, "pieces": pieces, "height": height, "type": "tunnel"}
	if ar.end.y > br.end.y:
		var swap = a
		a = b
		b = swap
		ar = a.rect
		br = b.rect
	var left := maxi(int(ar.position.x), int(br.position.x)) + 32
	var right := mini(int(ar.end.x), int(br.end.x)) - 32
	if br.position.y - ar.end.y < T.CAVE_ROCK_GAP or right - left < 224: return {}
	var width := _pick(rng, T.CAVE_SHAFT_WIDTH_MIN / 32, mini(T.CAVE_SHAFT_WIDTH_MAX / 32, (right - left) / 32)) * 32
	var x := _pick(rng, left / 32, (right - width) / 32) * 32
	var rect := Rect2(x, ar.end.y, width, br.end.y - ar.end.y)
	var exclusion := rect.grow(32)
	for room: Dictionary in rooms:
		if room.id != a.id and room.id != b.id and exclusion.intersects(room.rect): return {}
	return {"a": a.id, "b": b.id, "rect": rect, "type": "shaft"}

static func _decorate(stage: Dictionary, rng) -> void:
	for room: Dictionary in stage.chambers:
		var r: Rect2 = room.rect
		room.shelves = stage.solids.filter(func(s): return s.size.y == 16 and r.encloses(s))
		var wanted := maxi(room.shelves.size(), _pick(rng, 1, T.CAVE_SHELF_MAX_COUNT))
		for attempt in range(120):
			if room.shelves.size() >= wanted: break
			var width := _pick(rng, 4, 8) * 32
			var x := _pick(rng, int(r.position.x + 32) / 32, int(r.end.x - width - 32) / 32) * 32
			var y := r.end.y - (_pick(rng, 5, 5) if room.kind == "boss" else _pick(rng, 3, 4)) * 32
			var shelf := Rect2(x, y, width, 16)
			var clearance := Rect2(x - 16, y - 96, width + 32, 192)
			if stage.solids.any(func(s): return clearance.intersects(s)): continue
			stage.solids.append(shelf)
			room.shelves.append(shelf)
		if room.kind == "normal":
			for i in range(_pick(rng, 1, T.CAVE_STEP_MAX_COUNT)):
				for attempt in range(40):
					var width := _pick(rng, 4, 8) * 32
					var height := _pick(rng, 1, 4) * 32
					var x := _pick(rng, int(r.position.x + 32) / 32, int(r.end.x - width - 32) / 32) * 32
					var step := Rect2(x, r.end.y - height, width, height)
					if stage.shafts.any(func(e): return e.rect.grow(32).intersects(step)) or stage.tunnels.any(func(e): return e.rect.grow(32).intersects(step)) or room.floor_steps.any(func(s): return s.grow(96).intersects(step)): continue
					if room.shelves.any(func(s): return Rect2(s.position - Vector2(16, 80), s.size + Vector2(32, 160)).intersects(step)): continue
					room.floor_steps.append(step)
					stage.solids.append(step)
					break
			for i in range(_pick(rng, 1, T.CAVE_ROCK_MAX_COUNT)):
				for attempt in range(40):
					var ceiling := _pick(rng, 0, 1) == 1
					var width := _pick(rng, 2, 5) * 32
					var height := _pick(rng, 2, mini(6, int((r.size.y - 224) / 32))) * 32
					var x := _pick(rng, int(r.position.x + 32) / 32, int(r.end.x - width - 32) / 32) * 32
					var rock := Rect2(x, r.position.y if ceiling else r.end.y - mini(height, 128), width, height if ceiling else mini(height, 128))
					if protected_rect(rock.grow(32), stage) or stage.solids.any(func(s): return s.intersects(rock.grow(64)) and r.encloses(s)): continue
					if ceiling and room.shelves.any(func(s): return Rect2(s.position - Vector2(32, 160), s.size + Vector2(64, 256)).intersects(rock)): continue
					if ceiling and (room.floor_steps + room.rocks).any(func(s): return s.end.y == r.end.y and s.position.x < rock.end.x and s.end.x > rock.position.x and s.position.y - rock.end.y < 160): continue
					if not ceiling and room.rocks.any(func(s): return s.position.y == r.position.y and s.position.x < rock.end.x and s.end.x > rock.position.x and rock.position.y - s.end.y < 160): continue
					room.rocks.append(rock)
					stage.solids.append(rock)
					break
		# Preserve launch surfaces below shelves and at both sides of solid steps after erosion.
		for shelf: Rect2 in room.shelves:
			var launch_x := snappedf(shelf.get_center().x, 32)
			stage.protected_rects.append(Rect2(launch_x - 32, r.end.y - 32, 64, 128))
		for step: Rect2 in room.floor_steps + room.rocks:
			if step.end.y == r.end.y: stage.protected_rects.append(Rect2(step.position.x - 64, step.position.y - 32, step.size.x + 128, step.size.y + 160))

static func _carve(holes: Array, size: Vector2 = T.SECTOR_SIZE) -> Array:
	var width := int(size.x / T.TILE_SIZE)
	var height := int(size.y / T.TILE_SIZE)
	var grid := PackedByteArray()
	grid.resize(width * height)
	for hole: Rect2 in holes:
		for y in range(int(hole.position.y / 32), int(hole.end.y / 32)):
			for x in range(int(hole.position.x / 32), int(hole.end.x / 32)): grid[y * width + x] = 1
	var rects: Array = []
	var previous := {}
	for y in range(height):
		var current := {}
		var x := 0
		while x < width:
			if grid[y * width + x] == 1:
				x += 1
				continue
			var first := x
			while x < width and grid[y * width + x] == 0: x += 1
			var key := Vector2i(first, x)
			if previous.has(key):
				var index: int = previous[key]
				var rect: Rect2 = rects[index]
				rect.size.y += 32
				rects[index] = rect
				current[key] = index
			else:
				current[key] = rects.size()
				rects.append(Rect2(first * 32, y * 32, (x - first) * 32, 32))
		previous = current
	return rects

static func protected_rect(rect: Rect2, stage: Dictionary) -> bool:
	return _any_intersects(stage.get("protected_rects", []),rect)

static func _add_surface(stage: Dictionary, left: float, right: float, y: float) -> void:
	var span_start := -1.0
	for x in range(int(left), int(right) + 1, 32):
		var cell := Rect2(x, y, 32, T.SURFACE_DEPTH)
		var valid := x < right and not protected_rect(cell, stage) and _has_rock_depth(Rect2(x,y,32,T.SURFACE_DEPTH*2),stage.solids) and _supported(Vector2(x + 16, y - 22), T.PLAYER_SIZE, stage.solids)
		if valid and span_start < 0: span_start = x
		if not valid and span_start >= 0:
			stage.erodible_surfaces.append(Rect2(span_start, y, x - span_start, T.SURFACE_DEPTH))
			span_start = -1

static func _has_rock_depth(depth: Rect2, solids: Array) -> bool:
	var covered := 0.0
	for solid: Rect2 in solids:
		if solid.size.y == 16: continue
		if solid.encloses(depth): return true
		if solid.intersects(depth): covered += solid.intersection(depth).get_area()
	return covered >= depth.get_area() - 0.1

static func flight_lane(floor_rect: Rect2) -> Rect2:
	var patrol := Vector2(floor_rect.position.x + T.FLYER_LANE_MARGIN, floor_rect.end.x - T.FLYER_LANE_MARGIN)
	var half := T.ENEMY_SIZE / 2 + Vector2(T.FLYER_CLEARANCE, T.FLYER_BOB_AMPLITUDE + T.FLYER_CLEARANCE)
	return Rect2(Vector2(patrol.x, floor_rect.position.y - T.FLYER_ALTITUDE) - half, Vector2(patrol.y - patrol.x, 0) + half * 2)

static func lane_is_clear(floor_rect: Rect2, solids: Array) -> bool:
	var lane := flight_lane(floor_rect)
	for solid: Rect2 in solids:
		if lane.intersects(solid): return false
		if solid.size.y == 16 and solid.position.x < lane.end.x and solid.end.x > lane.position.x and solid.position.y >= lane.end.y and solid.position.y - lane.end.y < T.PLAYER_SIZE.y + 8: return false
	return true

static func _populate(stage: Dictionary, rng, graph: Dictionary, normal_count: int = T.CAVE_NORMAL_COUNT, safe_radius: float = SAFE_RADIUS) -> void:
	var kinds: Array = []
	var arc_count := _pick(rng, ceili(normal_count * T.CAVE_ARC_RATIO), floori(normal_count * T.CAVE_MAX_ARC_RATIO))
	for i in range(arc_count): kinds.append(["breaker", "flyer", "laser"][i % 3])
	for i in range(normal_count - arc_count): kinds.append(["turret", "walker", "shifter", "builder"][i % 4])
	_shuffle(kinds, rng)
	var rooms: Array = stage.chambers.filter(func(r): return r.kind == "normal")
	var index := 0
	for kind: String in kinds:
		_shuffle(rooms, rng)
		var placed := false
		for room: Dictionary in rooms:
			if stage.spawns.filter(func(s): return s.get("chamber_id", -1) == room.id).size() >= T.CAVE_ENEMIES_PER_ROOM: continue
			var supports: Array = graph.nodes.filter(func(s): return room.rect.has_point(Vector2(s.get_center().x, s.position.y - 22)) and s.size.x >= (192 if kind == "flyer" else 64))
			_shuffle(supports, rng)
			for surface: Rect2 in supports:
				for trial in range(8):
					var x: float = _pick(rng, ceili((maxf(surface.position.x, room.rect.position.x) + 32) / 16), floori((minf(surface.end.x, room.rect.end.x) - 32) / 16)) * 16
					if rng == null:
						x += trial * 96
						if x > minf(surface.end.x, room.rect.end.x) - 32: continue
					var floor_rect := Rect2(x - 144, surface.position.y, 288, 32)
					if kind == "flyer":
						var width := _pick(rng, 6, mini(12, int(surface.size.x / 32))) * 32
						x = _pick(rng, ceili((maxf(surface.position.x, room.rect.position.x) + width / 2) / 16), floori((minf(surface.end.x, room.rect.end.x) - width / 2) / 16)) * 16
						if rng == null: x += trial * 96
						floor_rect = Rect2(x - width / 2, surface.position.y, width, 32)
						if floor_rect.position.x < surface.position.x or floor_rect.end.x > surface.end.x: continue
						if not lane_is_clear(floor_rect, stage.solids): continue
					var pos := Vector2(x, surface.position.y - (T.FLYER_ALTITUDE if kind == "flyer" else 22))
					var patrol := Vector2(x, x)
					if kind == "walker": patrol = Vector2(maxf(x - 48, surface.position.x + 24), minf(x + 48, surface.end.x - 24))
					if kind == "flyer": patrol = Vector2(floor_rect.position.x + T.FLYER_LANE_MARGIN, floor_rect.end.x - T.FLYER_LANE_MARGIN)
					if not room.rect.encloses(Rect2(pos - T.ENEMY_SIZE / 2, T.ENEMY_SIZE)): continue
					if kind != "flyer" and (not _supported(Vector2((patrol.x + patrol.y) / 2, pos.y), Vector2(patrol.y - patrol.x + 38, 44), stage.solids) or _embedded(Vector2((patrol.x + patrol.y) / 2, pos.y), Vector2(patrol.y - patrol.x + 38, 44), stage.solids)): continue
					if kind == "builder" and not stage.solids.any(func(s): return s.size.y != 16 and s.position.y == pos.y + 22 and s.position.x <= x - 19 and s.end.x >= x + 19): continue
					var spawn := {"id": "enemy_%d" % index, "kind": kind, "boss_id": -1, "polarity": _pick(rng, 0, 1), "position": pos, "patrol": patrol, "chamber_id": room.id, "support": floor_rect}
					if pos.distance_to(stage.start_position) < safe_radius: continue
					if stage.spawns.any(func(s): return s.position.distance_to(pos) < 80): continue
					if not has_attack_sight(spawn, stage): continue
					stage.spawns.append(spawn)
					placed = true
					break
				if placed: break
			if placed: break
		index += 1

static func _segment_clear(a: Vector2, b: Vector2, solids: Array) -> bool:
	var box := Rect2(a.min(b), (a - b).abs()).grow(0.01)
	for rect: Rect2 in solids:
		if not rect.intersects(box): continue
		if rect.has_point(a) or rect.has_point(b): return false
		if Geometry2D.segment_intersects_segment(a, b, rect.position, Vector2(rect.end.x, rect.position.y)) != null: return false
		if Geometry2D.segment_intersects_segment(a, b, Vector2(rect.end.x, rect.position.y), rect.end) != null: return false
		if Geometry2D.segment_intersects_segment(a, b, rect.end, Vector2(rect.position.x, rect.end.y)) != null: return false
		if Geometry2D.segment_intersects_segment(a, b, Vector2(rect.position.x, rect.end.y), rect.position) != null: return false
	return true

static func sight_witness(spawn: Dictionary, stage: Dictionary) -> Dictionary:
	var chamber_id: int = spawn.get("chamber_id", -1)
	if chamber_id < 0 or chamber_id >= stage.chambers.size(): return {}
	var obstacles: Array = stage.solids + stage.get("breakables", [])
	if spawn.kind == "enhancer":
		for point: Vector2 in stage.chambers[chamber_id].approaches:
			if not _supported(point,T.PLAYER_SIZE,stage.solids) or _embedded(point,T.PLAYER_SIZE,obstacles): continue
			if point.distance_to(spawn.position) > T.CAVE_SIGHT_DISTANCE: continue
			var view := Rect2(point-Vector2(T.VIEW_SIZE.x/2,T.VIEW_SIZE.y/2+T.CAMERA_VERTICAL_OFFSET),T.VIEW_SIZE).grow(-20)
			if not view.has_point(spawn.position): continue
			var path := homing_witness(point,spawn.position,obstacles)
			if not path.is_empty(): return {"position":spawn.position,"target":point,"homing":true,"points":path}
		return {}
	var xs: Array = [spawn.position.x]
	if spawn.kind in ["walker", "flyer"]: xs = [spawn.patrol.x, (spawn.patrol.x + spawn.patrol.y) / 2, spawn.patrol.y]
	for x: float in xs:
		var pos := Vector2(x, spawn.position.y)
		for target: Vector2 in stage.chambers[chamber_id].approaches:
			if pos.distance_to(target) > T.CAVE_SIGHT_DISTANCE or pos.distance_to(target) < 48: continue
			var facing := 1 if target.x > pos.x else -1
			var muzzle := pos + Vector2(facing * (T.ENEMY_SIZE.x / 2 + 9), -4)
			var points := PackedVector2Array([muzzle, target])
			if spawn.kind not in ["laser", "breaker"]:
				# The live enemy aims from its center, then launches from the offset muzzle.
				var direction := (target - pos).normalized()
				var closest := muzzle + direction * (target - muzzle).dot(direction)
				if not Rect2(target - T.PLAYER_SIZE / 2, T.PLAYER_SIZE).grow(-1).has_point(closest): continue
				points.append(muzzle)
				points.append(closest)
			if spawn.kind == "laser":
				points = Laser.curve_points(muzzle, target, facing)
			elif spawn.kind == "breaker":
				var launch := pos + Vector2(0, -T.ENEMY_SIZE.y / 2 - 8)
				var end := target + Vector2(0, T.PLAYER_SIZE.y / 2 - 1)
				var velocity := (end - launch) / T.BOMB_FLIGHT_TIME - Vector2(0, T.BOMB_GRAVITY * T.BOMB_FLIGHT_TIME / 2)
				points.clear()
				for tick in range(61):
					var t := tick / 60.0 * T.BOMB_FLIGHT_TIME
					points.append(launch + velocity * t + Vector2(0, T.BOMB_GRAVITY * t * t / 2))
			# Long curves test many segments; only rock near the whole path can block one.
			var nearby: Array = obstacles
			if points.size() > 4:
				var area := Rect2(points[0], Vector2.ZERO)
				for point: Vector2 in points: area = area.expand(point)
				area = area.grow(0.01)
				nearby = obstacles.filter(func(o): return o.intersects(area))
			var clear := true
			for i in range(1, points.size()):
				if not _segment_clear(points[i - 1], points[i], nearby):
					clear = false
					break
			if clear: return {"position": pos, "target": target, "facing": facing, "points": points}
	return {}

static func has_attack_sight(spawn: Dictionary, stage: Dictionary) -> bool:
	return not sight_witness(spawn, stage).is_empty()

static func block_is_valid(block: Rect2, stage: Dictionary, corridors: Array = []) -> bool:
	if block.size.x < 32 or block.size.y < 32 or block.size.x > 64 or block.size.y > 64: return false
	for value in [block.position.x, block.position.y, block.size.x, block.size.y]:
		if fmod(value, 32) != 0: return false
	if protected_rect(block.grow(1), stage) or _embedded(block.get_center(), block.size - Vector2.ONE * 0.1, stage.solids + stage.breakables): return false
	if not _supported(Vector2(block.get_center().x, block.end.y - 22), Vector2(block.size.x, 44), stage.solids): return false
	for spawn: Dictionary in stage.spawns:
		var body := Rect2(Vector2(spawn.patrol.x - 27, spawn.position.y - 30), Vector2(spawn.patrol.y - spawn.patrol.x + 54, 60))
		if block.intersects(body): return false
		if spawn.kind == "flyer" and block.intersects(flight_lane(spawn.support)): return false
	if corridors.is_empty(): corridors = _route_corridors(stage)
	return not corridors.any(func(c): return block.intersects(c))

static func _route_corridors(stage: Dictionary) -> Array:
	var corridors: Array = []
	for route: Dictionary in stage.routes:
		for key in ["outward", "returning"]:
			var previous: Vector2 = stage.start_position if key == "outward" else route.points[-1]
			for step: Dictionary in route[key]:
				var target: Vector2 = step.position if step.action == "walk" else step.target
				var corridor := Rect2(previous.min(target) - T.PLAYER_SIZE / 2 - Vector2(12, 0), (previous - target).abs() + T.PLAYER_SIZE + Vector2(24, 0))
				corridors.append(corridor)
				previous = target
	return corridors

# Every solid that can support or overlap a player standing inside the room.
static func _room_solids(room: Rect2, solids: Array) -> Array:
	var area := room.grow(64)
	var result: Array = []
	for solid: Rect2 in solids:
		if solid.intersects(area): result.append(solid)
	return result

static func _supported(point: Vector2, size: Vector2, solids: Array) -> bool:
	var spans: Array[Vector2] = []
	var left := point.x-size.x/2
	var right := point.x+size.x/2
	for solid: Rect2 in solids:
		if not is_equal_approx(point.y + size.y / 2, solid.position.y): continue
		if solid.position.x<=left and solid.end.x>=right: return true
		if solid.position.x<right and solid.end.x>left: spans.append(Vector2(solid.position.x,solid.end.x))
	spans.sort_custom(func(a, b): return a.x < b.x)
	var covered := point.x - size.x / 2
	for span: Vector2 in spans:
		if span.x <= covered and span.y > covered: covered = span.y
		if covered >= point.x + size.x / 2: return true
	return false

static func _embedded(point: Vector2, size: Vector2, solids: Array) -> bool:
	var body := Rect2(point - size / 2, size).grow(-0.1)
	return _any_intersects(solids,body)

static func _subtract(spans: Array[Vector2], left: float, right: float) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for span: Vector2 in spans:
		if right <= span.x or left >= span.y: result.append(span)
		else:
			if left > span.x: result.append(Vector2(span.x, left))
			if right < span.y: result.append(Vector2(right, span.y))
	return result

static func subtract_rects(solids: Array, cuts: Array) -> Array:
	var result: Array = solids.duplicate()
	for cut: Rect2 in cuts:
		var next: Array = []
		for rect: Rect2 in result:
			if rect.size.y == 16 or not rect.intersects(cut):
				next.append(rect)
				continue
			var overlap := rect.intersection(cut)
			if overlap.position.y > rect.position.y: next.append(Rect2(rect.position, Vector2(rect.size.x, overlap.position.y - rect.position.y)))
			if overlap.end.y < rect.end.y: next.append(Rect2(rect.position.x, overlap.end.y, rect.size.x, rect.end.y - overlap.end.y))
			if overlap.position.x > rect.position.x: next.append(Rect2(rect.position.x, overlap.position.y, overlap.position.x - rect.position.x, overlap.size.y))
			if overlap.end.x < rect.end.x: next.append(Rect2(overlap.end.x, overlap.position.y, rect.end.x - overlap.end.x, overlap.size.y))
		result = next
	return result

static func damaged_solids(stage: Dictionary) -> Array:
	return subtract_rects(stage.solids, stage.erodible_surfaces)

# Spatial buckets along x: lists the rects whose x-range, widened by margin, may reach a query range.
static func _x_buckets(rects: Array, margin: float) -> Dictionary:
	var buckets := {}
	for index in range(rects.size()):
		var rect: Rect2 = rects[index]
		for key in range(floori((rect.position.x - margin) / T.CAVE_NAV_BUCKET), floori((rect.end.x + margin) / T.CAVE_NAV_BUCKET) + 1):
			if not buckets.has(key): buckets[key] = []
			buckets[key].append(index)
	return buckets

# Candidates in their original order, so callers that depend on order behave as with the full list.
static func _x_near(rects: Array, buckets: Dictionary, left: float, right: float, cache: Dictionary = {}) -> Array:
	var span := Vector2i(floori(left/T.CAVE_NAV_BUCKET),floori(right/T.CAVE_NAV_BUCKET))
	if cache.has(span): return cache[span]
	var found := {}
	for key in range(span.x,span.y+1):
		for index: int in buckets.get(key, []): found[index] = true
	var indices: Array = found.keys()
	indices.sort()
	var result: Array = []
	for index: int in indices: result.append(rects[index])
	cache[span] = result
	return result

static func navigation_graph(stage: Dictionary, damaged: bool = false, previous: Dictionary = {}, changed: Array = [], abilities: int = 0, added_thin: bool = false) -> Dictionary:
	var solids: Array = damaged_solids(stage) if damaged else stage.solids
	var thick: Array = solids.filter(func(s): return s.size.y != 16)
	var thick_buckets := _x_buckets(thick, 0)
	var solid_buckets := _x_buckets(solids, 160)
	var thick_cache := {}
	var solid_cache := {}
	var surfaces: Array = []
	# An appended one-way shelf does not remove existing standing surfaces.
	# Only this explicit append path reuses nodes; independent validation does
	# the complete reconstruction, as before.
	var surface_solids: Array = solids
	if added_thin and not previous.is_empty() and not changed.is_empty() and changed.all(func(r): return r.size.y==16):
		surfaces.append_array(previous.nodes)
		surface_solids = changed
	for solid: Rect2 in surface_solids:
		var spans: Array[Vector2] = [Vector2(solid.position.x, solid.end.x)]
		if stage.has("navigation_bounds"):
			spans.clear()
			for area: Rect2 in stage.navigation_bounds:
				if solid.position.y < area.position.y + T.PLAYER_SIZE.y + 32 or solid.position.y > area.end.y: continue
				var left := maxf(solid.position.x, area.position.x)
				var right := minf(solid.end.x, area.end.x)
				if right > left: spans.append(Vector2(left, right))
		elif solid.position.y < T.PLAYER_SIZE.y + 32: continue
		for blocker: Rect2 in _x_near(thick, thick_buckets, solid.position.x, solid.end.x, thick_cache):
			if blocker.position.y < solid.position.y and blocker.end.y > solid.position.y - T.PLAYER_SIZE.y - 32:
				spans = _subtract(spans, blocker.position.x, blocker.end.x)
		for span: Vector2 in spans:
			if span.y - span.x >= T.PLAYER_SIZE.x: surfaces.append(Rect2(span.x, solid.position.y, span.y - span.x, 0))
	surfaces.sort_custom(func(a, b): return a.position.y < b.position.y or (a.position.y == b.position.y and a.position.x < b.position.x))
	var nodes: Array = []
	for surface: Rect2 in surfaces:
		if not nodes.is_empty() and nodes[-1].position.y == surface.position.y and surface.position.x <= nodes[-1].end.x:
			var merged: Rect2 = nodes[-1]
			merged.size.x = maxf(merged.end.x, surface.end.x) - merged.position.x
			nodes[-1] = merged
		else: nodes.append(surface)
	var edges: Array = []
	var previous_nodes := {}
	if not previous.is_empty():
		for i in range(previous.nodes.size()): previous_nodes[previous.nodes[i]] = i
	var node_ids := {}
	for i in range(nodes.size()): node_ids[nodes[i]] = i
	# Nodes are sorted by height, so reachable jump targets form one index window.
	var heights: Array = nodes.map(func(n): return n.position.y)
	for i in range(nodes.size()): edges.append([])
	for i in range(nodes.size()):
		var lower: Rect2 = nodes[i]
		# A block can only change commands in its x neighbourhood. Reuse other
		# source surfaces, remapping target surfaces if an unrelated floor split.
		var unchanged: bool = previous_nodes.has(lower)
		if unchanged:
			for r: Rect2 in changed:
				if r.position.x < lower.end.x + 160 and r.end.x > lower.position.x - 160:
					unchanged = false
					break
		if unchanged:
			for old: Dictionary in previous.edges[previous_nodes[lower]]:
				var edge := old.duplicate()
				var old_target: Rect2 = previous.nodes[old.to]
				edge.to = node_ids.get(old_target, -1)
				if edge.to < 0: edge.to = node_at({"nodes": nodes}, edge.target)
				if edge.to >= 0: edges[i].append(edge)
			continue
		var local_solids: Array = []
		var local_thick: Array = []
		var jump_solids: Array = []
		var jump_thick: Array = []
		for s: Rect2 in _x_near(solids, solid_buckets, lower.position.x, lower.end.x, solid_cache):
			if s.position.x >= lower.end.x + 160 or s.end.x <= lower.position.x - 160: continue
			local_solids.append(s)
			if s.size.y != 16: local_thick.append(s)
			if s.position.y < lower.position.y and s.end.y > lower.position.y - 256:
				jump_solids.append(s)
				if s.size.y != 16: jump_thick.append(s)
		for j in range(heights.bsearch(lower.position.y - T.MAX_STEP_HEIGHT, true), heights.bsearch(lower.position.y, false)):
			var upper: Rect2 = nodes[j]
			var rise := lower.position.y - upper.position.y
			var spans: Array[Vector2] = [Vector2(maxf(lower.position.x, upper.position.x), minf(lower.end.x, upper.end.x))]
			if spans[0].y - spans[0].x < T.PLAYER_SIZE.x + 2 * T.LANDING_MARGIN: spans.clear()
			for blocker: Rect2 in jump_thick:
				if spans.is_empty(): break
				if blocker.position.y < lower.position.y and blocker.end.y > lower.position.y - T.MAX_STEP_HEIGHT - T.LANDING_MARGIN - T.PLAYER_SIZE.y:
					spans = _subtract(spans, blocker.position.x, blocker.end.x)
			for span: Vector2 in spans:
				if rise == 0: break
				if span.y - span.x < T.PLAYER_SIZE.x + 2 * T.LANDING_MARGIN: continue
				var x := (span.x + span.y) / 2
				if _ledge_in_column(jump_solids, x, lower.position.y - T.MAX_STEP_HEIGHT, upper.position.y): continue
				edges[i].append({"to": j, "action": "jump", "x": x, "position": Vector2(x, lower.position.y - 22), "target": Vector2(x, upper.position.y - 22)})
				break
			var gap := maxf(lower.position.x, upper.position.x) - minf(lower.end.x, upper.end.x)
			if gap >= 0 and gap <= (96 if rise == 0 else 32) and rise <= 128:
				var direction := 1 if upper.position.x >= lower.end.x else -1
				if rise == 0:
					_add_hop(edges[i], j, lower, upper, direction, jump_solids)
					continue
				var inset_from := minf(32, lower.size.x / 2)
				var inset_to := minf(32, upper.size.x / 2)
				var from_x := lower.end.x - inset_from if direction > 0 else lower.position.x + inset_from
				var to_x := upper.position.x + inset_to if direction > 0 else upper.end.x - inset_to
				var head_height := 160 if rise > 0 and rise <= 64 else 224
				var head := Rect2(minf(from_x, to_x) - 15, lower.position.y - head_height, absf(to_x - from_x) + 30, head_height - rise)
				if not _any_intersects(jump_thick, head.grow(-0.1)):
					edges[i].append({"to": j, "action": "jump", "hold_frames": 4 if head_height == 160 else 40, "x": from_x, "position": Vector2(from_x, lower.position.y - 22), "target": Vector2(to_x, upper.position.y - 22)})
		var drop_xs: Array = [lower.get_center().x, lower.position.x + 32, lower.end.x - 32]
		for shelf: Rect2 in local_solids:
			if shelf.size.y == 16 and shelf.position.y == lower.position.y: drop_xs.append(shelf.get_center().x)
		var used_x := {}
		for x: float in drop_xs:
			if used_x.has(x): continue
			used_x[x] = true
			if x < lower.position.x + 15 or x > lower.end.x - 15: continue
			# Solid ground under this point cannot be dropped through.
			if _ledge_in_column(local_thick, x, lower.position.y - 0.5, lower.position.y + 0.5): continue
			_add_drop(edges[i], nodes, heights, local_solids, local_thick, lower, x, "drop_through")
		for direction in [-1, 1]:
			var edge_x: float = lower.position.x if direction < 0 else lower.end.x
			var x: float = edge_x + direction * (T.PLAYER_SIZE.x / 2 + T.CAVE_DROP_EXIT_MARGIN)
			var departure := Rect2(minf(x, edge_x) - 15, lower.position.y - 44, absf(x - edge_x) + 30, 44).grow(-0.1)
			if _any_intersects(jump_thick, departure): continue
			_add_drop(edges[i], nodes, heights, local_solids, local_thick, lower, x, "drop")
	var graph := {"nodes": nodes, "edges": edges, "abilities": abilities}
	if abilities != 0: _ability_edges(graph, solids, abilities)
	return graph

# Discrete 60 Hz schedules use the same impulses, acceleration, fall cap and
# dash duration as player.gd. Rectangular sweeps reject rock and early landings.
# Real CharacterBody2D measurements verify these schedules in abilities_test.
static func flight_profiles(abilities: int) -> Array:
	var out: Array = []
	for required in [T.ABILITY_DOUBLE, T.ABILITY_DASH, T.ABILITY_GLIDE, 3, 5, 6, 7]:
		if (abilities & required) != required: continue
		out.append({"required": required, "second": T.ABILITY_SECOND_JUMP_FRAME if required & T.ABILITY_DOUBLE else -1,
			"dash": (T.ABILITY_SECOND_JUMP_FRAME + T.ABILITY_DASH_FRAME if required & T.ABILITY_DOUBLE else T.ABILITY_DASH_FRAME) if required & T.ABILITY_DASH else -1,
			"glide": bool(required & T.ABILITY_GLIDE)})
	return out

static func ability_arc(from: Vector2, target: Rect2, solids: Array, profile: Dictionary) -> Dictionary:
	var half := T.PLAYER_SIZE / 2
	var point := from
	var speed := Vector2(0, -T.JUMP_SPEED)
	var dash_left := 0.0
	var dash_dir := 1.0 if target.get_center().x >= from.x else -1.0
	var minimum := point.y
	var samples: Array = [point]
	for frame in range(T.ABILITY_FLIGHT_FRAMES):
		var axis := signf(target.get_center().x - point.x) if absf(target.get_center().x - point.x) > 2 else 0.0
		speed.x = move_toward(speed.x, axis * T.MOVE_SPEED, (T.AIR_ACCELERATION if axis != 0 else T.AIR_DECELERATION) / 60.0)
		if frame == profile.second: speed.y = -T.JUMP_SPEED * T.DOUBLE_JUMP_RATIO
		speed.y = minf(speed.y + (T.GRAVITY if speed.y < 0 else T.FALL_GRAVITY) / 60.0, T.MAX_FALL_SPEED)
		if profile.glide and speed.y > 0: speed.y = minf(speed.y, T.GLIDE_FALL_SPEED)
		if frame == profile.dash: dash_left = T.AIR_DASH_TIME
		var was_dashing := dash_left > 0
		if dash_left > 0:
			speed = Vector2(dash_dir * T.AIR_DASH_SPEED, 0)
			dash_left = maxf(0, dash_left - 1.0 / 60)
		var next := point + speed / 60.0
		if was_dashing and dash_left <= 0: speed.x = axis * T.MOVE_SPEED
		var sweep := Rect2(point - half, T.PLAYER_SIZE).merge(Rect2(next - half, T.PLAYER_SIZE)).grow(-0.1)
		for solid: Rect2 in solids:
			if solid.size.y == 16:
				if speed.y <= 0 or point.y + half.y > solid.position.y + 0.1 or next.y + half.y < solid.position.y: continue
				if next.x + half.x <= solid.position.x or next.x - half.x >= solid.end.x: continue
				if solid.position.y == target.position.y and next.x >= target.position.x + half.x + 2 and next.x <= target.end.x - half.x - 2:
					return {"frames": frame + 1, "height": from.y - minimum, "position": Vector2(next.x, target.position.y - half.y), "samples": samples}
				return {}
			if not solid.intersects(sweep): continue
			if speed.y > 0 and point.y + half.y <= solid.position.y + 0.1 and next.y + half.y >= solid.position.y and solid.position.y == target.position.y and next.x >= target.position.x + half.x + 2 and next.x <= target.end.x - half.x - 2:
				return {"frames": frame + 1, "height": from.y - minimum, "position": Vector2(next.x, target.position.y - half.y), "samples": samples}
			return {}
		point = next
		minimum = minf(minimum, point.y)
		samples.append(point)
	return {}

static func ability_edge(lower: Rect2, upper: Rect2, solids: Array, abilities: int, profiles: Array = [], spatial: Dictionary = {}) -> Dictionary:
	if lower.size.x < 48 or upper.size.x < 48: return {}
	if lower.position.y - upper.position.y > 320 or upper.position.y - lower.position.y > 640: return {}
	var tx := upper.get_center().x
	var fx := clampf(tx, lower.position.x + 24, lower.end.x - 24)
	if absf(fx - tx) > 1200: return {}
	var near: Array = []
	var filtered := false
	if profiles.is_empty(): profiles = flight_profiles(abilities)
	for profile: Dictionary in profiles:
		var measured: Array = T.ABILITY_HOP_PROFILES[profile.required]
		if lower.position.y - upper.position.y > measured[0] - T.LANDING_MARGIN: continue
		var extra: float = maxf(0, upper.position.y - lower.position.y) / T.GLIDE_FALL_SPEED * T.MOVE_SPEED if profile.glide else maxf(0, upper.position.y - lower.position.y)
		if absf(fx - upper.get_center().x) > measured[1] + extra - T.HOP_REACH_MARGIN: continue
		# Most surface pairs fail the measured bounds. Filter obstacles only
		# once a profile can actually cover this height and distance.
		if not filtered:
			var candidates: Array = solids
			if not spatial.is_empty():
				candidates = _x_near(spatial.solids,spatial.buckets,minf(fx,tx)-96,maxf(fx,tx)+96,spatial.cache).duplicate()
				candidates.append(upper)
			for r: Rect2 in candidates:
				if r.position.x < maxf(fx, tx) + 96 and r.end.x > minf(fx, tx) - 96 and r.position.y < lower.position.y + 700 and r.end.y > lower.position.y - 400: near.append(r)
			filtered = true
		var from := Vector2(fx, lower.position.y - 22)
		var arc := ability_arc(from, upper, near, profile)
		if not arc.is_empty():
			return {"action": "ability_jump", "x": fx, "position": from, "target": arc.position, "profile": profile, "required": profile.required, "frames": arc.frames}
	return {}

# Cheap rejection before trying ability arcs: the ordinary graph would already
# connect this shelf by one of its same-column jumps. Use the identical margins
# and obstruction rules; full graph validation still runs on accepted shelves.
static func initial_jump_reaches(nodes: Array, upper: Rect2, solids: Array) -> bool:
	solids = solids.filter(func(r): return r.position.x<upper.end.x+15 and r.end.x>upper.position.x-15)
	var thick: Array = solids.filter(func(r): return r.size.y!=16)
	for lower: Rect2 in nodes:
		if lower.end.x<=upper.position.x or lower.position.x>=upper.end.x: continue
		var rise := lower.position.y-upper.position.y
		if rise<0:
			var xs: Array = [lower.get_center().x,lower.position.x+32,lower.end.x-32]
			for solid: Rect2 in solids:
				if solid.size.y==16 and solid.position.y==lower.position.y: xs.append(solid.get_center().x)
			for x: float in xs:
				if x<lower.position.x+15 or x>lower.end.x-15 or x<upper.position.x+15 or x>upper.end.x-15: continue
				if _ledge_in_column(thick,x,lower.position.y-0.5,lower.position.y+0.5): continue
				var edges: Array = []
				_add_drop(edges,[upper],[upper.position.y],solids,thick,lower,x,"drop_through")
				if not edges.is_empty(): return true
		if rise<=0 or rise>T.MAX_STEP_HEIGHT: continue
		var spans: Array[Vector2] = [Vector2(maxf(lower.position.x,upper.position.x),minf(lower.end.x,upper.end.x))]
		if spans[0].y-spans[0].x<T.PLAYER_SIZE.x+2*T.LANDING_MARGIN: continue
		var nearby: Array = []
		for solid: Rect2 in solids:
			if solid.position.y>=lower.position.y or solid.end.y<=lower.position.y-256: continue
			nearby.append(solid)
			if solid.size.y!=16 and solid.end.y>lower.position.y-T.MAX_STEP_HEIGHT-T.LANDING_MARGIN-T.PLAYER_SIZE.y:
				spans=_subtract(spans,solid.position.x,solid.end.x)
		for span: Vector2 in spans:
			if span.y-span.x>=T.PLAYER_SIZE.x+2*T.LANDING_MARGIN and not _ledge_in_column(nearby,(span.x+span.y)/2,lower.position.y-T.MAX_STEP_HEIGHT,upper.position.y): return true
	return false

static func _ability_edges(graph: Dictionary, solids: Array, abilities: int) -> void:
	for i in range(graph.nodes.size()):
		for j in range(graph.nodes.size()):
			if i == j or graph.edges[i].any(func(e): return e.to == j): continue
			var edge := ability_edge(graph.nodes[i], graph.nodes[j], solids, abilities)
			if not edge.is_empty():
				edge.to = j
				graph.edges[i].append(edge)

# Crosses a gap between floors of the same height with the lowest measured hop that reaches.
# A thin platform under that arc would catch the falling player and rock would stop the head,
# and a higher hop only widens that region, so either one rules the crossing out.
static func _add_hop(edges: Array, to: int, lower: Rect2, upper: Rect2, direction: int, solids: Array) -> void:
	var from_x := lower.end.x - minf(16, lower.size.x / 2) if direction > 0 else lower.position.x + minf(16, lower.size.x / 2)
	var to_x := upper.position.x + minf(16, upper.size.x / 2) if direction > 0 else upper.end.x - minf(16, upper.size.x / 2)
	var distance := absf(to_x - from_x)
	for profile: Array in T.HOP_PROFILES:
		if profile[2] < distance + T.HOP_REACH_MARGIN: continue
		var rise: float = profile[1] + 4
		var left := minf(from_x, to_x) - T.PLAYER_SIZE.x / 2
		var feet := Rect2(left, lower.position.y - rise, distance + T.PLAYER_SIZE.x, rise).grow(-0.1)
		var head := Rect2(left, lower.position.y - rise - T.PLAYER_SIZE.y, distance + T.PLAYER_SIZE.x, rise + T.PLAYER_SIZE.y).grow(-0.1)
		for solid: Rect2 in solids:
			if solid.intersects(feet if solid.size.y == 16 else head): return
		edges.append({"to": to, "action": "jump", "hold_frames": profile[0], "x": from_x, "position": Vector2(from_x, lower.position.y - 22), "target": Vector2(to_x, upper.position.y - 22)})
		return

static func _any_intersects(rects: Array, area: Rect2) -> bool:
	for rect: Rect2 in rects:
		if rect.intersects(area): return true
	return false

# True when a rect's top edge lies strictly between above and below within the player's column at x.
static func _ledge_in_column(rects: Array, x: float, above: float, below: float) -> bool:
	for rect: Rect2 in rects:
		if rect.position.y > above and rect.position.y < below and rect.position.x < x + 15 and rect.end.x > x - 15: return true
	return false

static func _add_drop(edges: Array, nodes: Array, heights: Array, solids: Array, thick: Array, lower: Rect2, x: float, action: String) -> void:
	var y := INF
	for solid: Rect2 in solids:
		if solid.position.y > lower.position.y and solid.position.x < x + 15 and solid.end.x > x - 15: y = minf(y, solid.position.y)
	if not is_finite(y): return
	var column := Rect2(x - 15, lower.position.y - 44, 30, y - lower.position.y + 43.9)
	if _any_intersects(thick, column): return
	for j in range(heights.bsearch(y, true), heights.bsearch(y, false)):
		var target: Rect2 = nodes[j]
		if target.position.y == y and x >= target.position.x + 15 and x <= target.end.x - 15:
			edges.append({"to": j, "action": action, "x": x, "position": Vector2(x, lower.position.y - 22), "target": Vector2(x, y - 22)})
			return

static func node_at(graph: Dictionary, point: Vector2) -> int:
	for id in range(graph.nodes.size()):
		var rect: Rect2 = graph.nodes[id]
		if absf(rect.position.y - point.y - 22) < 0.5 and point.x >= rect.position.x + 15 and point.x <= rect.end.x - 15: return id
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
		if edge.action in ["jump", "drop_through", "ability_jump"]: result.append({"action": "walk", "x": edge.x, "position": edge.position})
		result.append(edge)
	result.append({"action": "walk", "x": end.x, "position": end})
	return result

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

static func connectivity_errors(stage: Dictionary, damaged: bool = false, graph: Dictionary = {}) -> Array[String]:
	var errors: Array[String] = []
	if graph.is_empty(): graph = navigation_graph(stage, damaged)
	var origin := node_at(graph, stage.start_position)
	var forward := _search(graph, origin)
	var backward := _search(graph, origin, true)
	for i in range(graph.nodes.size()):
		if stage.get("optional_surfaces", []).any(func(r): return r.position.y == graph.nodes[i].position.y and r.position.x <= graph.nodes[i].position.x and r.end.x >= graph.nodes[i].end.x): continue
		if not forward.has(i) or not backward.has(i): errors.append("Surface not strongly connected%s: %s" % [" after excavation" if damaged else "", graph.nodes[i]])
	if origin < 0: errors.append("Start missing from navigation graph")
	return errors

static func homing_witness(from: Vector2, target: Vector2, obstacles: Array) -> PackedVector2Array:
	# Match the actual guided muzzle (-4px vertically), turn rate and swept rays.
	# A center-to-center line alone can incorrectly clear a shelf corner.
	var direction := (target-from).normalized()
	var point := from+Vector2(signf(direction.x)*(T.PLAYER_SIZE.x/2+T.MUZZLE_CLEARANCE),-4)
	var path := PackedVector2Array([point])
	var body := Rect2(target-T.ENEMY_SIZE/2,T.ENEMY_SIZE)
	var delta := 1.0/60.0
	for i in range(ceili(T.BULLET_LIFETIME/delta)):
		var turn := clampf(angle_difference(direction.angle(),(target-point).angle()),-T.HOMING_TURN_RATE*delta,T.HOMING_TURN_RATE*delta)
		direction=direction.rotated(turn).normalized()
		var next := point+direction*T.PLAYER_HOMING_SPEED*delta
		if not _segment_clear(point,next,obstacles): return PackedVector2Array()
		path.append(next)
		if not _segment_clear(point,next,[body]): return path
		point=next
	return PackedVector2Array()
