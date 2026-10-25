extends RefCounted
## Seeded carving and geometry-derived navigation in a single persistent cave.
const T := preload("res://scripts/tuning.gd")
const Laser := preload("res://scripts/laser_beam.gd")
const WORLD_SIZE := T.WORLD_SIZE
const GROUND_Y := T.GROUND_Y
const START_X := T.WORLD_START_X
const SAFE_RADIUS := T.CAVE_SAFE_RADIUS
const NORMAL_KINDS := ["turret", "walker", "shifter", "flyer", "laser", "breaker", "builder"]
const REQUIRED_KINDS := NORMAL_KINDS

static func generate(stage_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = stage_seed
	for attempt in range(T.GENERATION_RETRIES):
		var stage := _build(stage_seed, rng, false)
		if stage.is_empty(): continue
		var graph: Dictionary = stage.get("_navigation", {})
		stage.erase("_navigation")
		if validate(stage, graph).is_empty(): return stage
	return generate_fallback(stage_seed)

static func generate_fallback(stage_seed: int) -> Dictionary:
	var stage: Dictionary = preload("res://scripts/cave_fallback.gd").data()
	stage.seed = stage_seed
	return stage

static func _pick(rng, first: int, last: int) -> int:
	return first if rng == null else rng.randi_range(first, last)

static func _shuffle(items: Array, rng) -> void:
	if rng == null: return
	for i in range(items.size() - 1, 0, -1):
		var j := _pick(rng, 0, i)
		var swap = items[i]
		items[i] = items[j]
		items[j] = swap

static func _band(y: float) -> int:
	return 0 if y <= T.CAVE_FLOOR_BANDS[0].y else (1 if y <= T.CAVE_FLOOR_BANDS[1].y else 2)

static func _connections_compatible(candidate: Dictionary, chosen: Array, rooms: Array) -> bool:
	for edge: Dictionary in chosen:
		var overlap: Rect2 = candidate.rect.intersection(edge.rect)
		if not overlap.has_area(): continue
		var in_room := false
		for id in [candidate.a, candidate.b]:
			if id in [edge.a, edge.b] and rooms[id].rect.encloses(overlap): in_room = true
		if not in_room: return false
	return true

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

static func _layout(rng) -> Dictionary:
	for trial in range(T.CAVE_LAYOUT_TRIALS):
		var rooms: Array = []
		var count := _pick(rng, T.CAVE_COUNT_MIN, T.CAVE_COUNT_MAX)
		var start_width := _pick(rng, 28, 44) * 32
		var start_left := _pick(rng, int((START_X - start_width + 96) / 32), int((START_X - 96) / 32)) * 32
		rooms.append({"id": 0, "rect": Rect2(start_left, GROUND_Y - T.CAVE_START_HEIGHT, start_width, T.CAVE_START_HEIGHT), "kind": "start"})
		var boss_bands := [0, 1, 2]
		_shuffle(boss_bands, rng)
		var failed := false
		for i in range(1, count):
			var placed := false
			for attempt in range(T.CAVE_ROOM_TRIALS):
				var boss := i <= 3
				var width := _pick(rng, (T.CAVE_BOSS_WIDTH_MIN if boss else T.CAVE_ROOM_WIDTH_MIN) / 32, (T.CAVE_BOSS_WIDTH_MAX if boss else T.CAVE_ROOM_WIDTH_MAX) / 32) * 32
				var height := _pick(rng, (T.CAVE_BOSS_HEIGHT_MIN if boss else T.CAVE_ROOM_HEIGHT_MIN) / 32, T.CAVE_ROOM_HEIGHT_MAX / 32) * 32
				var x: int
				var y: int
				if boss:
					x = _pick(rng, (i - 1) * 128 + 2, i * 128 - 2 - width / 32) * 32
					var limits: Vector2i = T.CAVE_FLOOR_BANDS[boss_bands[i - 1]]
					y = _pick(rng, maxi(limits.x, height + 64) / 32, limits.y / 32) * 32
				else:
					# Grow beside, above or below a placed chamber, within tunnel or shaft reach,
					# so most layouts have enough connection candidates on the first trial.
					var anchor: Rect2 = rooms[_pick(rng, 0, rooms.size() - 1)].rect
					if _pick(rng, 0, 2) < 2:
						var gap := _pick(rng, T.CAVE_TUNNEL_MIN_LENGTH / 32, (T.CAVE_TUNNEL_MAX_LENGTH - 64) / 32) * 32
						x = int(anchor.end.x) + gap if _pick(rng, 0, 1) == 1 else int(anchor.position.x) - gap - width
						var rise := mini(gap / 2, 384) / 32
						y = int(anchor.end.y) + _pick(rng, -rise, rise) * 32
					else:
						x = int(anchor.position.x) + _pick(rng, -(width - 288) / 32, (int(anchor.size.x) - 288) / 32) * 32
						var gap := _pick(rng, T.CAVE_ROCK_GAP / 32, 16) * 32
						y = int(anchor.position.y) - gap if _pick(rng, 0, 1) == 1 else int(anchor.end.y) + gap + height
					if x < 64 or x + width > WORLD_SIZE.x - 64 or y < maxi(T.CAVE_FLOOR_BANDS[0].x, height + 64) or y > T.CAVE_FLOOR_BANDS[2].y: continue
				var rect := Rect2(x, y - height, width, height)
				var exclusion := rect.grow(T.CAVE_ROCK_GAP - 0.1)
				var overlaps := false
				for room: Dictionary in rooms:
					if exclusion.intersects(room.rect):
						overlaps = true
						break
				if overlaps: continue
				rooms.append({"id": i, "rect": rect, "kind": "boss" if boss else "normal"})
				placed = true
				break
			if not placed:
				failed = true
				break
		if failed: continue
		var candidates: Array = []
		for i in range(rooms.size()):
			for j in range(i + 1, rooms.size()):
				var candidate := _candidate(rooms[i], rooms[j], rooms, rng)
				if not candidate.is_empty(): candidates.append(candidate)
		if candidates.size() < count + 3: continue
		# Random edge costs favor local links and avoid long crossing shafts during tree growth.
		for candidate: Dictionary in candidates:
			var length: float = candidate.rect.size.x if candidate.type == "tunnel" else candidate.rect.size.y
			candidate.weight = length * _pick(rng, 60, 160) / 100.0
		candidates.sort_custom(func(a,b): return a.weight < b.weight)
		var reached := {0: true}
		var tree: Array = []
		var remaining := candidates.duplicate()
		var incoming := {}
		while reached.size() < count:
			var index := remaining.find_custom(func(e): return (reached.has(e.a) != reached.has(e.b)) and (e.type != "shaft" or not incoming.has(e.b)) and _connections_compatible(e, tree, rooms))
			if index < 0: break
			var edge: Dictionary = remaining.pop_at(index)
			tree.append(edge)
			if edge.type == 'shaft': incoming[edge.b] = true
			reached[edge.a] = true
			reached[edge.b] = true
		if reached.size() != count: continue
		var extras := remaining.filter(func(e):return e.type != "shaft" or not incoming.has(e.b))
		_shuffle(extras, rng)
		if extras.size() < 3: continue
		var loops := _pick(rng, 3, mini(8, extras.size()))
		var added := 0
		for edge: Dictionary in extras:
			if added >= loops: break
			if edge.type == "shaft" and incoming.has(edge.b): continue
			if not _connections_compatible(edge, tree, rooms): continue
			tree.append(edge)
			if edge.type == "shaft": incoming[edge.b] = true
			added += 1
		if added < 3 or tree.size() >= candidates.size(): continue
		var degrees := {}
		for edge: Dictionary in tree:
			degrees[edge.a] = degrees.get(edge.a, 0) + 1
			degrees[edge.b] = degrees.get(edge.b, 0) + 1
		if not degrees.values().any(func(n): return n <= 2): continue
		var bands := [{}, {}, {}]
		for room: Dictionary in rooms:
			room.region = clampi(int(room.rect.get_center().x / 4096), 0, 2)
			room.band = _band(room.rect.end.y)
			room.approaches = []
			room.shelves = []
			room.floor_steps = []
			room.rocks = []
			bands[room.region][room.band] = true
		if not bands.all(func(b): return b.size() >= 2): continue
		if not tree.any(func(e): return e.type == "tunnel" and rooms[e.a].rect.end.y != rooms[e.b].rect.end.y): continue
		return {"rooms": rooms, "edges": tree, "candidates": candidates}
	return {}

static func _build(stage_seed: int, rng, fallback: bool) -> Dictionary:
	var layout := _layout(rng)
	if layout.is_empty(): return {}
	var stage := {"seed": stage_seed, "fallback": fallback, "bounds": Rect2(Vector2.ZERO, WORLD_SIZE),
		"start_position": Vector2(START_X, GROUND_Y - T.PLAYER_SIZE.y / 2),
		"chambers": layout.rooms, "connection_candidates": layout.candidates, "tunnels": [], "shafts": [], "solids": [], "spawns": [], "breakables": [],
		"erodible_surfaces": [], "protected_rects": [], "routes": [], "biomes": [], "landmarks": []}
	var holes: Array = []
	var shelves: Array = []
	for room: Dictionary in stage.chambers:
		holes.append(room.rect)
		if room.kind != "normal": stage.protected_rects.append(room.rect.grow(T.SURFACE_DEPTH))
		if room.kind == "boss":
			var id: int = room.region
			var x := _pick(rng, int(room.rect.position.x + 288) / 32, int(room.rect.end.x - 288) / 32) * 32
			var pos := Vector2(x, room.rect.end.y - T.BOSS_SIZE.y / 2)
			stage.spawns.append({"id": "guardian_%d" % id, "kind": "boss", "boss_id": id, "polarity": _pick(rng, 0, 1), "position": pos, "patrol": Vector2(x, x), "chamber_id": room.id})
			stage.landmarks.append({"id": id, "position": pos, "name": T.BIOME_NAMES[id] + "の守護者"})
	for edge: Dictionary in layout.edges:
		var a: Dictionary = stage.chambers[edge.a]
		var b: Dictionary = stage.chambers[edge.b]
		if edge.type == "tunnel":
			edge.id = stage.tunnels.size()
			stage.tunnels.append(edge)
			holes.append_array(edge.pieces)
			if a.rect.end.y != b.rect.end.y: stage.protected_rects.append(edge.rect.grow(96))
			for room: Dictionary in [a, b]:
				var x: float = room.rect.end.x if room == a else room.rect.position.x
				stage.protected_rects.append(Rect2(x - 96, room.rect.end.y - edge.height - 32, 192, edge.height + 160))
		else:
			edge.id = stage.shafts.size()
			var rect: Rect2 = edge.rect
			var platforms: Array = [Rect2(rect.position.x, rect.position.y, rect.size.x, 16)]
			# Bottom-aligned landings keep at most four shelves in the receiving chamber.
			var first_y := rect.end.y - floorf(b.rect.size.y / T.CAVE_SHAFT_STEP) * T.CAVE_SHAFT_STEP
			if first_y - rect.position.y < 96: first_y = rect.position.y + 96
			var anchors := [rect.position.y, first_y, rect.end.y]
			for part in range(anchors.size() - 1):
				var distance: float = anchors[part + 1] - anchors[part]
				var steps := ceili(distance / T.CAVE_SHAFT_STEP)
				for i in range(1, steps + 1):
					var y: float = anchors[part] + snappedf(distance * i / steps, 32)
					if y == rect.end.y: continue
					var min_width := ceili((rect.size.x + T.PLAYER_SIZE.x + 2 * T.LANDING_MARGIN) / 64) * 32
					var w := _pick(rng, min_width / 32, mini(int(rect.size.x), 256) / 32) * 32
					var x := _pick(rng, int(rect.position.x) / 32, int(rect.end.x - w) / 32) * 32
					platforms.append(Rect2(x, y, w, 16))
			edge.platforms = platforms
			stage.shafts.append(edge)
			shelves.append_array(platforms)
			holes.append(rect)
			stage.protected_rects.append(Rect2(rect.position.x - 96, rect.position.y - 96, rect.size.x + 192, rect.size.y + 256))
	stage.solids = _carve(holes)
	stage.solids.append_array(shelves)
	_decorate(stage, rng)
	for room: Dictionary in stage.chambers:
		_add_surface(stage, room.rect.position.x, room.rect.end.x, room.rect.end.y)
		for step: Rect2 in room.floor_steps: _add_surface(stage, step.position.x, step.end.x, step.position.y)
	for tunnel: Dictionary in stage.tunnels:
		for piece: Rect2 in tunnel.pieces: _add_surface(stage, piece.position.x, piece.end.x, piece.end.y)
	for region in range(3): stage.biomes.append({"id": region, "name": T.BIOME_NAMES[region], "rect": Rect2(region * 4096, 0, 4096, WORLD_SIZE.y)})
	var graph := navigation_graph(stage)
	stage._navigation = graph
	# Standing transit points include the entrances and each exposed floor/platform segment.
	for room: Dictionary in stage.chambers:
		var nearby := _room_solids(room.rect, stage.solids)
		for surface: Rect2 in graph.nodes:
			for x in [surface.position.x + 32, surface.get_center().x, surface.end.x - 32]:
				var point := Vector2(x, surface.position.y - 22)
				if x >= surface.position.x + 15 and x <= surface.end.x - 15 and room.rect.has_point(point) and _supported(point, T.PLAYER_SIZE, nearby) and not _embedded(point, T.PLAYER_SIZE, nearby): room.approaches.append(point)
	for landmark: Dictionary in stage.landmarks:
		var end: Vector2 = landmark.position + Vector2(0, T.BOSS_SIZE.y / 2 - 22)
		var origin := node_at(graph, stage.start_position)
		var target := node_at(graph, end)
		stage.routes.append({"boss_id": landmark.id, "outward": path_steps(graph, origin, target, end), "returning": path_steps(graph, target, origin, stage.start_position), "points": [stage.start_position, end]})
	_populate(stage, rng, graph)
	var block_candidates: Array = []
	for room: Dictionary in stage.chambers:
		if room.kind != "normal": continue
		for surface: Rect2 in graph.nodes:
			if not room.rect.has_point(Vector2(surface.get_center().x, surface.position.y - 22)): continue
			for x in range(int(surface.position.x) + 32, int(surface.end.x) - 32, 32):
				block_candidates.append(Rect2(x, surface.position.y - 32, 32, 32))
	_shuffle(block_candidates, rng)
	var shooters: Array = stage.spawns.filter(func(s): return s.kind != "boss")
	var witnesses: Array = shooters.map(func(s): return sight_witness(s, stage))
	var corridors := _route_corridors(stage)
	for block: Rect2 in block_candidates:
		if stage.breakables.size() >= T.CAVE_BLOCK_TARGET: break
		if block_is_valid(block, stage, corridors):
			stage.breakables.append(block)
			var clear := true
			for wi in range(witnesses.size()):
				var witness: Dictionary = witnesses[wi]
				if witness.is_empty():
					clear = false
					break
				var points: PackedVector2Array = witness.points
				for i in range(1, points.size()):
					if not _segment_clear(points[i - 1], points[i], [block]):
						var replacement := sight_witness(shooters[wi], stage)
						clear = not replacement.is_empty()
						if clear: witnesses[wi] = replacement
						break
				if not clear: break
			if not clear: stage.breakables.pop_back()
	return stage

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

static func _carve(holes: Array) -> Array:
	var width := int(WORLD_SIZE.x / T.TILE_SIZE)
	var height := int(WORLD_SIZE.y / T.TILE_SIZE)
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
	return stage.get("protected_rects", []).any(func(p): return p.intersects(rect))

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

static func _populate(stage: Dictionary, rng, graph: Dictionary) -> void:
	var kinds: Array = []
	var arc_count := _pick(rng, ceili(T.CAVE_NORMAL_COUNT * T.CAVE_ARC_RATIO), floori(T.CAVE_NORMAL_COUNT * T.CAVE_MAX_ARC_RATIO))
	for i in range(arc_count): kinds.append(["breaker", "flyer", "laser"][i % 3])
	for i in range(T.CAVE_NORMAL_COUNT - arc_count): kinds.append(["turret", "walker", "shifter", "builder"][i % 4])
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
					var floor_rect := Rect2(x - 144, surface.position.y, 288, 32)
					if kind == "flyer":
						var width := _pick(rng, 6, mini(12, int(surface.size.x / 32))) * 32
						x = _pick(rng, ceili((maxf(surface.position.x, room.rect.position.x) + width / 2) / 16), floori((minf(surface.end.x, room.rect.end.x) - width / 2) / 16)) * 16
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
					if pos.distance_to(stage.start_position) < SAFE_RADIUS: continue
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
	return solids.any(func(s): return body.intersects(s))

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
static func _x_near(rects: Array, buckets: Dictionary, left: float, right: float) -> Array:
	var found := {}
	for key in range(floori(left / T.CAVE_NAV_BUCKET), floori(right / T.CAVE_NAV_BUCKET) + 1):
		for index: int in buckets.get(key, []): found[index] = true
	var indices: Array = found.keys()
	indices.sort()
	return indices.map(func(i): return rects[i])

static func navigation_graph(stage: Dictionary, damaged: bool = false) -> Dictionary:
	var solids: Array = damaged_solids(stage) if damaged else stage.solids
	var thick: Array = solids.filter(func(s): return s.size.y != 16)
	var thick_buckets := _x_buckets(thick, 0)
	var solid_buckets := _x_buckets(solids, 160)
	var surfaces: Array = []
	for solid: Rect2 in solids:
		if solid.position.y < T.PLAYER_SIZE.y + 32: continue
		var spans: Array[Vector2] = [Vector2(solid.position.x, solid.end.x)]
		for blocker: Rect2 in _x_near(thick, thick_buckets, solid.position.x, solid.end.x):
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
	# Nodes are sorted by height, so reachable jump targets form one index window.
	var heights: Array = nodes.map(func(n): return n.position.y)
	for i in range(nodes.size()): edges.append([])
	for i in range(nodes.size()):
		var lower: Rect2 = nodes[i]
		var local_solids: Array = []
		var local_thick: Array = []
		var jump_solids: Array = []
		var jump_thick: Array = []
		for s: Rect2 in _x_near(solids, solid_buckets, lower.position.x, lower.end.x):
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
	return {"nodes": nodes, "edges": edges}

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
		if edge.action in ["jump", "drop_through"]: result.append({"action": "walk", "x": edge.x, "position": edge.position})
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
		if not forward.has(i) or not backward.has(i): errors.append("Surface not strongly connected%s: %s" % [" after excavation" if damaged else "", graph.nodes[i]])
	if origin < 0: errors.append("Start missing from navigation graph")
	return errors

static func cycle_count(stage: Dictionary) -> int:
	var visited := {}
	var components := 0
	var edges: Array = stage.tunnels + stage.shafts
	for room: Dictionary in stage.chambers:
		if visited.has(room.id): continue
		components += 1
		var queue := [room.id]
		visited[room.id] = true
		while not queue.is_empty():
			var id = queue.pop_back()
			for edge: Dictionary in edges:
				var next: int = edge.b if edge.a == id else (edge.a if edge.b == id else -1)
				if next >= 0 and not visited.has(next):
					visited[next] = true
					queue.append(next)
	return edges.size() - stage.chambers.size() + components if components == 1 else -1

static func layout_errors(stage: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var heights := {}
	var step_rooms := 0
	var rock_rooms := 0
	var ordinary_rooms := 0
	var shelf_counts := {}
	for room: Dictionary in stage.chambers:
		var r: Rect2 = room.rect
		heights[r.end.y] = true
		if room.band != _band(r.end.y): errors.append("Band disagrees with floor range")
		for other: Dictionary in stage.chambers:
			if room.id < other.id and r.grow(T.CAVE_ROCK_GAP - 0.1).intersects(other.rect): errors.append("Chambers overlap or rock gap is less than 64")
		var steps: Array = room.get("floor_steps", [])
		var rocks: Array = room.get("rocks", [])
		var actual_shelves: Array = stage.solids.filter(func(s):return s.size.y==16 and r.encloses(s))
		if actual_shelves.size() != room.get("shelves",[]).size(): errors.append("Chamber shelf metadata omits a physical platform")
		if steps.size() > 3 or rocks.size() > 2: errors.append("Too many chamber features")
		for step: Rect2 in steps:
			if not r.encloses(step) or not stage.solids.has(step) or step.end.y != r.end.y or step.size.y < 32 or step.size.y > 128: errors.append("Invalid floor step")
		for rock: Rect2 in rocks:
			if not r.encloses(rock) or not stage.solids.has(rock) or (rock.end.y != r.end.y and (rock.position.y != r.position.y or r.end.y - rock.end.y < 160)): errors.append('Invalid rock or hanging clearance')
			if rock.position.y == r.position.y:
				for floor_feature: Rect2 in steps + rocks:
					if floor_feature.end.y == r.end.y and floor_feature.position.x < rock.end.x and floor_feature.end.x > rock.position.x and floor_feature.position.y-rock.end.y<T.CAVE_ROCK_CLEARANCE: errors.append('Hanging rock lacks clearance over raised floor')
		for solid: Rect2 in stage.solids:
			if solid.size.y != 16 and r.intersects(solid) and not steps.has(solid) and not rocks.has(solid): errors.append("Unspecified obstruction inside chamber")
		shelf_counts[room.get("shelves", []).size()] = true
		if room.kind == "normal":
			ordinary_rooms += 1
			step_rooms += int(not steps.is_empty())
			rock_rooms += int(not rocks.is_empty())
	if heights.size() < 8: errors.append("Fewer than eight floor heights")
	if step_rooms < ordinary_rooms * 0.5: errors.append("Fewer than half of normal chambers have steps")
	if rock_rooms < ordinary_rooms * 0.3: errors.append("Too few chambers have rocks")
	if shelf_counts.size() < 2: errors.append("Uniform shelf count")
	var candidates: Array = stage.get("connection_candidates", [])
	var edges: Array = stage.tunnels + stage.shafts
	if edges.size() >= candidates.size(): errors.append("All candidate connections were carved")
	var degrees := {}
	var different_heights := false
	var pairs := {}
	for edge: Dictionary in edges:
		if edge.a < 0 or edge.b < 0 or edge.a >= stage.chambers.size() or edge.b >= stage.chambers.size(): continue
		var pair := Vector2i(mini(edge.a, edge.b), maxi(edge.a, edge.b))
		if pairs.has(pair): errors.append("Duplicate connection")
		pairs[pair] = true
		if not candidates.any(func(c): return c.a == edge.a and c.b == edge.b and c.type == edge.get("type", "")): errors.append("Connection absent from candidates")
		degrees[edge.a] = degrees.get(edge.a, 0) + 1
		degrees[edge.b] = degrees.get(edge.b, 0) + 1
		for room: Dictionary in stage.chambers:
			if room.id != edge.a and room.id != edge.b and edge.rect.intersects(room.rect): errors.append("Connection pierces another chamber")
		if stage.tunnels.has(edge):
			var a: Rect2 = stage.chambers[edge.a].rect
			var b: Rect2 = stage.chambers[edge.b].rect
			different_heights = different_heights or a.end.y != b.end.y
			var pieces: Array = edge.get("pieces", [])
			if pieces.is_empty():
				errors.append("Missing tunnel floor profile")
				continue
			if pieces[0].end.y != a.end.y or pieces[-1].end.y != b.end.y: errors.append("Tunnel floor misses entrance")
			for i in range(pieces.size()):
				var piece: Rect2 = pieces[i]
				if piece.size.y != edge.height or _embedded(Vector2(piece.get_center().x, piece.end.y - 22), T.PLAYER_SIZE, stage.solids): errors.append("Blocked tunnel floor")
				if i > 0 and (piece.position.x != pieces[i-1].end.x or absf(piece.end.y - pieces[i-1].end.y) > 64): errors.append("Tunnel floor step exceeds 64")
		else:
			var a: Rect2 = stage.chambers[edge.a].rect
			var b: Rect2 = stage.chambers[edge.b].rect
			if edge.rect.position.x < maxf(a.position.x, b.position.x) or edge.rect.end.x > minf(a.end.x, b.end.x): errors.append("Shaft outside chamber overlap")
	if not different_heights: errors.append("No tunnel between different floor heights")
	if not degrees.values().any(func(n): return n <= 2) or not degrees.values().any(func(n): return n >= 3): errors.append("Uniform connection degree")
	if cycle_count(stage) > T.CAVE_MAX_CYCLES: errors.append("Too many independent cycles")
	return errors

static func validate(stage: Dictionary, generated_graph: Dictionary = {}) -> Array[String]:
	var errors: Array[String] = []
	if stage.get("bounds", Rect2()) != Rect2(Vector2.ZERO, WORLD_SIZE): errors.append("Invalid world bounds")
	for key in ["chambers", "tunnels", "shafts", "solids", "spawns", "erodible_surfaces", "protected_rects", "breakables", "routes", "landmarks", "biomes"]:
		if not stage.has(key): errors.append("Missing " + key)
	if not errors.is_empty(): return errors
	errors.append_array(layout_errors(stage))
	if stage.chambers.size() < 14 or stage.chambers.size() > 22: errors.append("Chamber count")
	var bands := [{}, {}, {}]
	var boss_bands := {}
	var starts := 0
	for i in range(stage.chambers.size()):
		var room: Dictionary = stage.chambers[i]
		var r: Rect2 = room.rect
		if room.id != i or room.region != clampi(int(r.get_center().x / 4096), 0, 2) or room.band < 0 or room.band > 2:
			errors.append("Chamber identity/region/band")
			continue
		bands[room.region][room.band] = true
		if r.size.x < 640 or r.size.x > 1536 or r.size.y < 320 or r.size.y > 704: errors.append("Chamber dimensions")
		if room.kind == "start":
			starts += 1
			if r.size.x < 896 or r.end.y != GROUND_Y or START_X < r.position.x or START_X > r.end.x: errors.append("Invalid start chamber")
		if room.kind == "boss":
			boss_bands[room.band] = true
			if r.size.x < 1024 or r.size.x > 1408 or r.size.y < 576 or r.size.y > 704: errors.append("Boss chamber dimensions")
		if room.kind != "normal" and not stage.protected_rects.any(func(p): return p.encloses(r)): errors.append("Unprotected start/boss chamber")
		var shelf_count := 0
		for shelf: Rect2 in room.get("shelves", []):
			if stage.solids.has(shelf) and r.encloses(shelf): shelf_count += 1
		if shelf_count < 1 or shelf_count > 4: errors.append("Chamber shelf count")
		var nearby := _room_solids(r, stage.solids)
		for point: Vector2 in room.approaches:
			if not r.has_point(point) or not _supported(point,T.PLAYER_SIZE,nearby) or _embedded(point,T.PLAYER_SIZE,nearby): errors.append("Approach is not a standing transit point")
	for region in bands:
		if region.size() < 2: errors.append("Region lacks height bands")
	if starts != 1 or boss_bands.size() < 2: errors.append("Start/boss band distribution")
	if stage.start_position != Vector2(START_X, GROUND_Y - 22) or not _supported(stage.start_position, T.PLAYER_SIZE, stage.solids) or _embedded(stage.start_position, T.PLAYER_SIZE, stage.solids): errors.append("Invalid player start")
	if cycle_count(stage) < T.CAVE_MIN_CYCLES: errors.append("Insufficient independent cycles or disconnected chamber network")
	for edge: Dictionary in stage.tunnels + stage.shafts:
		if edge.a < 0 or edge.b < 0 or edge.a >= stage.chambers.size() or edge.b >= stage.chambers.size():
			errors.append("Invalid connection")
			continue
		var r: Rect2 = edge.rect
		var a_room: Rect2 = stage.chambers[edge.a].rect
		var b_room: Rect2 = stage.chambers[edge.b].rect
		if stage.tunnels.has(edge):
			if not r.intersects(a_room) or not r.intersects(b_room): errors.append("Tunnel does not connect its chambers")
			for pair in [[a_room.end.x, a_room.end.y], [b_room.position.x, b_room.end.y]]:
				var required := Rect2(pair[0]-96,pair[1],192,64)
				if not stage.protected_rects.any(func(p): return p.encloses(required)): errors.append("Unprotected tunnel entrance")
			if edge.height < 160 or edge.height > 256 or r.size.x < 128 or r.size.x > 1024: errors.append("Tunnel dimensions")
		else:
			var mouth_guard := Rect2(r.position.x-96,r.position.y-96,r.size.x+192,192)
			if not stage.protected_rects.any(func(p): return p.encloses(mouth_guard)): errors.append("Unprotected shaft mouth")
			if r.position.y != a_room.end.y or r.end.y != b_room.end.y or not _segment_clear(Vector2(r.get_center().x,r.position.y+1),Vector2(r.get_center().x,r.end.y-1),stage.solids.filter(func(s): return s.size.y!=16)): errors.append("Blocked shaft")
			if r.size.x < 160 or r.size.x > 320 or edge.platforms.is_empty() or not stage.solids.has(edge.platforms[0]) or edge.platforms[0].position.y != r.position.y: errors.append("Shaft dimensions or missing mouth lid")
			for i in range(1, edge.platforms.size()):
				var a: Rect2 = edge.platforms[i - 1]
				var b: Rect2 = edge.platforms[i]
				if b.position.y - a.position.y < 96 or b.position.y - a.position.y > 160 or minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x) < T.PLAYER_SIZE.x + 2 * T.LANDING_MARGIN: errors.append("Shaft spacing/overlap")
	var thick: Array = stage.solids.filter(func(s): return s.size.y != 16)
	var thick_buckets := _x_buckets(thick, 0)
	for solid: Rect2 in stage.solids:
		if not stage.bounds.encloses(solid) or solid.size.x <= 0 or solid.size.y <= 0: errors.append("Solid bounds")
		for v in [solid.position.x, solid.position.y, solid.size.x]:
			if fmod(v, 32) != 0: errors.append("Terrain grid")
		if solid.size.y == 16:
			for dy in [-T.PLAYER_SIZE.y - 32, 16]:
				var space := Rect2(solid.position + Vector2(16, dy), Vector2(solid.size.x - 32, T.PLAYER_SIZE.y + 32)).grow(-0.1)
				if _x_near(thick, thick_buckets, space.position.x, space.end.x).any(func(s): return s.intersects(space)): errors.append("Platform lacks space above/below")
	for shell: Rect2 in [Rect2(0, 0, WORLD_SIZE.x, 64), Rect2(0, WORLD_SIZE.y - 64, WORLD_SIZE.x, 64), Rect2(0, 0, 64, WORLD_SIZE.y), Rect2(WORLD_SIZE.x - 64, 0, 64, WORLD_SIZE.y)]:
		var covered := 0.0
		for solid: Rect2 in stage.solids:
			if solid.size.y != 16 and shell.intersects(solid): covered += shell.intersection(solid).get_area()
		if not is_equal_approx(covered, shell.get_area()): errors.append("Outer rock shell missing")
	for surface: Rect2 in stage.erodible_surfaces:
		if surface.size.y != T.SURFACE_DEPTH or protected_rect(surface, stage): errors.append("Invalid erodible surface/protection")
		var floors: Array = []
		for room: Dictionary in stage.chambers:
			floors.append(Rect2(room.rect.position.x, room.rect.end.y, room.rect.size.x, 0))
			for step: Rect2 in room.get("floor_steps", []): floors.append(step)
		for tunnel: Dictionary in stage.tunnels:
			for piece: Rect2 in tunnel.pieces: floors.append(Rect2(piece.position.x, piece.end.y, piece.size.x, 0))
		if not floors.any(func(f): return surface.position.y == f.position.y and surface.position.x >= f.position.x and surface.end.x <= f.end.x): errors.append("Only chamber/tunnel floors may erode")
		if not _supported(Vector2(surface.get_center().x, surface.position.y - 22), Vector2(surface.size.x, 44), stage.solids): errors.append("Erosion is not an exposed floor")
	var graph := navigation_graph(stage) if generated_graph.is_empty() else generated_graph
	errors.append_array(connectivity_errors(stage, false, graph))
	errors.append_array(connectivity_errors(stage, true))
	var ids := {}
	var bosses := {}
	var counts := {}
	var room_counts := {}
	var ordinary := 0
	var outside := 0
	for spawn: Dictionary in stage.spawns:
		if ids.has(spawn.id): errors.append("Duplicate enemy ID")
		ids[spawn.id] = true
		if spawn.polarity not in [0, 1] or spawn.kind not in NORMAL_KINDS + ["boss"]: errors.append("Invalid enemy kind/color")
		var size: Vector2 = T.BOSS_SIZE if spawn.kind == "boss" else T.ENEMY_SIZE
		var room_id: int = spawn.get("chamber_id", -1)
		if room_id < 0 or room_id >= stage.chambers.size():
			outside += 1
		else:
			var room: Dictionary = stage.chambers[room_id]
			if not room.rect.encloses(Rect2(spawn.position - size / 2, size)): errors.append("Enemy outside assigned chamber")
			if spawn.kind == "boss":
				if room.kind != "boss" or int(spawn.position.x / 4096) != spawn.boss_id: errors.append("Boss outside region/chamber")
			elif room.kind != "normal": errors.append("Ordinary enemy in start/boss chamber")
		if spawn.kind == "boss":
			if bosses.has(spawn.boss_id) or spawn.boss_id not in [0, 1, 2]: errors.append("Invalid boss IDs")
			bosses[spawn.boss_id] = spawn
		else:
			ordinary += 1
			counts[spawn.kind] = counts.get(spawn.kind, 0) + 1
			room_counts[room_id] = room_counts.get(room_id, 0) + 1
			if spawn.position.distance_to(stage.start_position) < SAFE_RADIUS: errors.append("Enemy inside start safety radius")
			if not has_attack_sight(spawn, stage): errors.append("Enemy has no attack sight: " + spawn.id)
		if spawn.kind == "flyer":
			# The live flyer uses spawn.patrol, not support, to determine its sweep.
			var allowed_patrol := Vector2(spawn.support.position.x + T.FLYER_LANE_MARGIN, spawn.support.end.x - T.FLYER_LANE_MARGIN)
			if spawn.patrol.x < allowed_patrol.x or spawn.patrol.y > allowed_patrol.y or spawn.patrol.x >= spawn.patrol.y: errors.append("Flyer patrol outside validated lane")
			if not lane_is_clear(spawn.support, stage.solids + stage.breakables) or spawn.position.y != spawn.support.position.y - T.FLYER_ALTITUDE or spawn.position.x < spawn.patrol.x or spawn.position.x > spawn.patrol.y: errors.append("Flyer lane/altitude")
		else:
			if spawn.position.x < spawn.patrol.x or spawn.position.x > spawn.patrol.y: errors.append("Spawn outside patrol")
			var center := Vector2((spawn.patrol.x + spawn.patrol.y) / 2, spawn.position.y)
			var body := Vector2(spawn.patrol.y - spawn.patrol.x + size.x, size.y)
			if not _supported(center, body, stage.solids) or _embedded(center, body, stage.solids + stage.breakables): errors.append("Unsupported/embedded enemy patrol")
			if spawn.kind in ["turret", "laser", "breaker", "builder", "boss"] and spawn.patrol != Vector2(spawn.position.x, spawn.position.x): errors.append("Fixed enemy patrol")
			if spawn.kind == "builder" and not stage.solids.any(func(s): return s.size.y != 16 and s.position.y == spawn.position.y + 22 and s.position.x <= spawn.position.x - 19 and s.end.x >= spawn.position.x + 19): errors.append("Builder needs thick floor")
	if ordinary < 36 or ordinary > 44: errors.append("Normal enemy count")
	if outside > ordinary * 0.25: errors.append("Too many enemies outside chambers")
	for count in room_counts.values():
		if count > T.CAVE_ENEMIES_PER_ROOM: errors.append("Chamber enemy cap")
	for kind: String in REQUIRED_KINDS:
		if not counts.has(kind): errors.append("Missing enemy kind " + kind)
	if counts.get("breaker", 0) + counts.get("flyer", 0) + counts.get("laser", 0) < ordinary * T.CAVE_ARC_RATIO: errors.append("Arc/flight ratio")
	var arc_total: int = counts.get('breaker',0) + counts.get('flyer',0) + counts.get('laser',0)
	if arc_total > ordinary * T.CAVE_MAX_ARC_RATIO: errors.append('Arc/flight ratio exceeds upper bound')
	for count in counts.values():
		if count > ordinary * T.CAVE_MAX_KIND_RATIO: errors.append('One enemy kind exceeds 30 percent')
	if bosses.size() != 3 or stage.landmarks.size() != 3 or stage.routes.size() != 3: errors.append("Boss/landmark/route count")
	var route_ids := {}
	for route: Dictionary in stage.routes:
		if not bosses.has(route.boss_id) or route_ids.has(route.boss_id):
			errors.append("Route boss ID")
			continue
		route_ids[route.boss_id] = true
		var end: Vector2 = bosses[route.boss_id].position + Vector2(0, T.BOSS_SIZE.y / 2 - 22)
		if not route_is_valid(graph, route.outward, stage.start_position, end) or not route_is_valid(graph, route.returning, end, stage.start_position): errors.append("Invalid executable boss route")
	for landmark: Dictionary in stage.landmarks:
		if not bosses.has(landmark.id) or bosses[landmark.id].position != landmark.position: errors.append("Landmark mismatch")
	if stage.biomes.size() != 3: errors.append("Region count")
	else:
		for i in range(3):
			if stage.biomes[i].id != i or stage.biomes[i].rect != Rect2(i * 4096, 0, 4096, WORLD_SIZE.y): errors.append("Region boundaries")
	var block_regions := {}
	var fixture := stage.duplicate(false)
	fixture.breakables = []
	for block: Rect2 in stage.breakables:
		if not block_is_valid(block, fixture): errors.append("Invalid breakable block")
		block_regions[int(block.get_center().x / 4096)] = true
		fixture.breakables.append(block)
	if stage.breakables.size() < T.BREAKABLE_MIN_COUNT or block_regions.size() < 2: errors.append("Block count/region spread")
	return errors

static func signature(stage: Dictionary) -> String:
	return str([stage.seed, stage.fallback, stage.bounds, stage.start_position, stage.chambers, stage.get("connection_candidates", []), stage.tunnels, stage.shafts, stage.solids, stage.erodible_surfaces, stage.protected_rects, stage.spawns, stage.breakables, stage.routes, stage.biomes, stage.landmarks])
