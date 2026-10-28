extends RefCounted
## Pure local-coordinate data. No scene tree, global RNG, cache or game integration.
const T := preload("res://scripts/tuning.gd")
const G := preload("res://scripts/stage_generator.gd")
const L := preload("res://scripts/loot_generator.gd")
const Population := preload("res://scripts/enemy_population.gd")
const SIDES := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

# String hashing avoids signed multiplication overflow, including INT64_MAX seeds.
static func _key(seed_value: int, at: Vector2i, salt: String) -> int:
	return ("%d:%d:%d:%s" % [seed_value, at.x, at.y, salt]).hash()

static func region_at(seed_value: int, at: Vector2i) -> int:
	var offset := _key(seed_value, Vector2i.ZERO, "region")
	var x := floori(float(at.x + offset % 4) / T.SECTOR_REGION_SPAN)
	var y := floori(float(at.y + (offset / 4) % 4) / T.SECTOR_REGION_SPAN)
	return posmod(x + 2 * y + offset % 3, 3)

static func guardian_sectors(seed_value: int) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	for y in range(-4, 5):
		for x in range(-4, 5):
			if abs(x) + abs(y) in range(2, 5): candidates.append(Vector2i(x, y))
	candidates.sort_custom(func(a, b): return _key(seed_value, a, "guardian") < _key(seed_value, b, "guardian"))
	for a: Vector2i in candidates:
		for b: Vector2i in candidates:
			if region_at(seed_value, a) == region_at(seed_value, b) or Vector2(a).normalized().dot(Vector2(b).normalized()) > 0.5: continue
			for c: Vector2i in candidates:
				if region_at(seed_value, c) in [region_at(seed_value, a), region_at(seed_value, b)]: continue
				if Vector2(c).normalized().dot(Vector2(a).normalized()) <= 0.5 and Vector2(c).normalized().dot(Vector2(b).normalized()) <= 0.5:
					var result: Array[Vector2i] = [a, b, c]
					result.sort_custom(func(p, q): return region_at(seed_value, p) < region_at(seed_value, q))
					return result
	return []

# Canonical edge: right/down belongs to this cell, left/up to its neighbor.
# Gate rects are in world coordinates so independent callers obtain identical data.
static func boundary_gates(seed_value: int, at: Vector2i, side: Vector2i, reference: Vector2i = Vector2i.ZERO) -> Array:
	assert(side in SIDES)
	var owner := at + side if side in [Vector2i.LEFT, Vector2i.UP] else at
	var horizontal := side.x != 0
	var rng := RandomNumberGenerator.new()
	rng.seed = _key(seed_value, owner, "east" if horizontal else "south")
	var origin := Vector2(owner - reference) * T.SECTOR_SIZE
	var result: Array = []
	var positions: Array = []
	for i in range(rng.randi_range(1, 2)):
		for trial in range(100):
			var p := rng.randi_range(12, 90) * 32 if horizontal else rng.randi_range(2, 118) * 32
			if positions.any(func(q): return absi(p - q) < (448 if horizontal else 576)): continue
			positions.append(p)
			break
	positions.sort()
	for p: int in positions:
		if horizontal:
			var height := rng.randi_range(5, 8) * 32
			result.append({"axis": "x", "owner": owner, "rect": Rect2(origin + Vector2(T.SECTOR_SIZE.x, p - height), Vector2(0, height)), "floor": p, "height": height})
		else:
			result.append({"axis": "y", "owner": owner, "rect": Rect2(origin + Vector2(p, T.SECTOR_SIZE.y), Vector2(256, 0)), "x": p, "width": 256, "step": 128, "phase": 96})
	return result

static func generate(seed_value: int, at: Vector2i, attempt_limit: int = T.SECTOR_RETRIES) -> Dictionary:
	for attempt in range(clampi(attempt_limit, 0, T.SECTOR_RETRIES)):
		var rng := RandomNumberGenerator.new()
		rng.seed = _key(seed_value, at, "interior:%d" % attempt)
		var sector := _build(seed_value, at, rng, false)
		if not sector.is_empty():
			var graphs: Array = sector.get("_graphs", [])
			sector.erase("_graphs")
			return Population.decorate(L.decorate(sector, graphs[0] if graphs.size() == 2 else {}, graphs[1] if graphs.size() == 2 else {}))
	return generate_fallback(seed_value, at)

static func generate_fallback(seed_value: int, at: Vector2i) -> Dictionary:
	return Population.decorate(L.decorate(_fallback_build(seed_value, at)))

static func _shaft(s: Dictionary, holes: Array, x: int, top: int, bottom: int, gate: bool = false, width: int = 256) -> void:
	var rect := Rect2(x, top, width, bottom - top)
	holes.append(rect)
	var platforms: Array = []
	var ys: Array = []
	var anchors := [top, bottom]
	if gate: anchors = [96, 224, bottom] if top == 0 else [top, int(T.SECTOR_SIZE.y) - 32, int(T.SECTOR_SIZE.y)]
	for part in range(anchors.size() - 1):
		var first: int = anchors[part]
		var last: int = anchors[part + 1]
		if last - first < 96:
			if first < bottom: ys.append(first)
			continue
		var count := ceili(float(last - first) / 160)
		for i in range(count): ys.append(first + int(snappedf(float(last - first) * i / count, 32)))
	for y: int in ys:
		var shelf := Rect2(x, y, width, 16)
		platforms.append(shelf)
		s.solids.append(shelf)
	s.shafts.append({"rect": rect, "platforms": platforms, "gate": gate})
	s.protected_rects.append(rect.grow(96))

static func _tunnel(s: Dictionary, holes: Array, left: int, right: int, from_y: int, to_y: int, height: int) -> void:
	var pieces: Array = []
	for x in range(left, right, 64):
		var y := int(snappedf(lerpf(from_y, to_y, clampf(float(x - left) / maxf(right - left - 64, 64), 0, 1)), 32))
		var piece := Rect2(x, y - height, mini(64, right - x), height)
		pieces.append(piece)
		holes.append(piece)
		# Protect every step/entrance; ordinary chamber floors remain erodible.
		s.protected_rects.append(piece.grow(96))
	var bounds: Rect2 = pieces[0]
	for piece: Rect2 in pieces: bounds = bounds.merge(piece)
	s.tunnels.append({"rect": bounds, "pieces": pieces, "height": height})

static func _node(rect: Rect2, kind: String, id: int, region: int) -> Dictionary:
	return {"id": id, "rect": rect, "kind": kind, "region": region, "shelves": [], "floor_steps": [], "rocks": [], "approaches": []}

# An elbow is a shaft in the upper room and a stepped passage into the lower
# room. Its individual pieces, rather than its large bounding box, exclude rock.
static func _link(a: Dictionary, b: Dictionary, nodes: Array, rng) -> Dictionary:
	var direct := G._candidate(a, b, nodes, rng)
	if not direct.is_empty():
		return direct
	var upper: Dictionary = a if a.rect.end.y < b.rect.end.y else b
	var lower: Dictionary = b if upper == a else a
	var u: Rect2 = upper.rect
	var l: Rect2 = lower.rect
	if l.end.y - u.end.y < 96: return {}
	for trial in range(12):
		var bend: Rect2 = u if trial % 2 == 0 else l
		var x := G._pick(rng, int(bend.position.x + 32) / 32, int(bend.end.x - 288) / 32) * 32
		var shaft := Rect2(x, u.end.y, 256, l.end.y - u.end.y)
		var left: int
		var right: int
		var other: Rect2 = l if trial % 2 == 0 else u
		if other.end.x <= x:
			left = int(other.end.x) - 32
			right = x + 256
		elif other.position.x >= x + 256:
			left = x
			right = int(other.position.x) + 32
		else:
			continue
		var height := G._pick(rng, 5, 8) * 32
		var passage := Rect2(left, (l.end.y if trial % 2 == 0 else u.end.y) - height, right - left, height)
		var cuts: Array = [shaft, passage]
		if nodes.any(func(n): return n.id not in [a.id, b.id] and cuts.any(func(r): return r.grow(32).intersects(n.rect))): continue
		var pieces: Array = []
		for px in range(left, right, 64): pieces.append(Rect2(px, passage.position.y, mini(64, right - px), height))
		return {"a": upper.id, "b": lower.id, "type": "elbow", "rect": shaft.merge(passage), "shaft": shaft, "pieces": pieces, "height": height}
	return {}

static func _cuts(edge: Dictionary) -> Array:
	if edge.type == "shaft": return [edge.rect]
	return edge.pieces + ([edge.shaft] if edge.type == "elbow" else [])

static func _compatible(edge: Dictionary, chosen: Array, nodes: Array) -> bool:
	for other: Dictionary in chosen:
		for a: Rect2 in _cuts(edge):
			for b: Rect2 in _cuts(other):
				var overlap := a.grow(16).intersection(b.grow(16))
				if not overlap.has_area(): continue
				if not [edge.a, edge.b].any(func(id): return id in [other.a, other.b] and nodes[id].rect.grow(32).encloses(overlap)): return false
	return true

static func _layout(s: Dictionary, rng) -> Dictionary:
	for trial in range(10):
		var nodes: Array = []
		for entrance: Dictionary in s.entrances:
			nodes.append(_node(entrance.rect, "entrance", nodes.size(), s.region))
		var rooms: Array = []
		if s.coord == Vector2i.ZERO:
			rooms.append(_node(Rect2(G._pick(rng, 4, 22) * 32, 1120, 1152, 640), "start", nodes.size(), s.region))
		elif s.coord in guardian_sectors(s.seed):
			var w := G._pick(rng, 32, 44) * 32
			rooms.append(_node(Rect2(G._pick(rng, 14, (3648 - w) / 32) * 32, G._pick(rng, 12, 70) * 32, w, 576), "boss", nodes.size(), s.region))
		if not rooms.is_empty(): nodes.append(rooms[0])
		var wanted := G._pick(rng, 4, 7)
		for i in range(wanted):
			for attempt in range(180):
				var anchor: Rect2 = nodes[G._pick(rng, 0, nodes.size() - 1)].rect
				var w := G._pick(rng, 20, 36) * 32
				var h := G._pick(rng, 12, 16) * 32
				var x: int
				var floor_y: int
				var gap := G._pick(rng, 4, 16) * 32
				if G._pick(rng, 0, 2) < 2:
					x = int(anchor.end.x) + gap if G._pick(rng, 0, 1) else int(anchor.position.x) - gap - w
					floor_y = int(anchor.end.y) + G._pick(rng, -gap / 64, gap / 64) * 32
				else:
					x = int(anchor.position.x) + G._pick(rng, -(w - 320) / 32, (int(anchor.size.x) - 320) / 32) * 32
					floor_y = int(anchor.position.y) - gap if G._pick(rng, 0, 1) else int(anchor.end.y) + gap + h
				var rect := Rect2(x, floor_y - h, w, h)
				if not Rect2(384, 352, 3328, 2464).encloses(rect): continue
				if nodes.any(func(n): return rect.grow(63.9).intersects(n.rect)): continue
				if rooms.any(func(n): return n.rect.end.y == floor_y): continue
				var room := _node(rect, "normal", nodes.size(), s.region)
				nodes.append(room)
				rooms.append(room)
				break
		if rooms.filter(func(r): return r.kind == "normal").size() < (4 if rooms.is_empty() or rooms[0].kind == "normal" else 3): continue
		var candidates: Array = []
		for i in range(nodes.size()):
			for j in range(i + 1, nodes.size()):
				var edge := _link(nodes[i], nodes[j], nodes, rng)
				if edge.is_empty(): continue
				edge.weight = (_cuts(edge).reduce(func(total, r): return total + r.size.x + r.size.y, 0.0)) * G._pick(rng, 60, 160) / 100.0
				candidates.append(edge)
		candidates.sort_custom(func(a, b): return a.weight < b.weight)
		var reached := {0: true}
		var chosen: Array = []
		var remaining := candidates.duplicate()
		var incoming := {}
		while reached.size() < nodes.size():
			var index := remaining.find_custom(func(e): return reached.has(e.a) != reached.has(e.b) and (e.type == "tunnel" or not incoming.has(e.b)) and _compatible(e, chosen, nodes))
			if index < 0: break
			var edge: Dictionary = remaining.pop_at(index)
			chosen.append(edge)
			if edge.type != "tunnel": incoming[edge.b] = true
			reached[edge.a] = true
			reached[edge.b] = true
		if reached.size() != nodes.size(): continue
		G._shuffle(remaining, rng)
		var loops := G._pick(rng, 0, 3)
		var added := 0
		for edge: Dictionary in remaining:
			if added == loops: break
			if edge.type != "tunnel" and incoming.has(edge.b): continue
			if not _compatible(edge, chosen, nodes): continue
			chosen.append(edge)
			if edge.type != "tunnel": incoming[edge.b] = true
			added += 1
		var chambers: Array = rooms.map(func(r): return r.duplicate(true))
		for i in range(chambers.size()): chambers[i].id = i
		return {"rooms": chambers, "nodes": nodes, "edges": chosen, "candidates": candidates, "cycles": added}
	return {}

static func _build(seed_value: int, at: Vector2i, rng, fallback: bool) -> Dictionary:
	for layout_attempt in range(8):
		var sector := _build_candidate(seed_value, at, rng, fallback)
		if not sector.is_empty(): return sector
	return {}

static func _build_candidate(seed_value: int, at: Vector2i, rng, fallback: bool) -> Dictionary:
	var region := region_at(seed_value, at)
	var boss_id := guardian_sectors(seed_value).find(at)
	var s := {"seed": seed_value, "coord": at, "fallback": fallback, "region": region,
		"bounds": Rect2(Vector2.ZERO, T.SECTOR_SIZE), "start_position": T.SECTOR_START,
		"chambers": [], "entrances": [], "connections": [], "connection_candidates": [], "cycles": 0,
		"tunnels": [], "shafts": [], "solids": [], "spawns": [], "breakables": [],
		"erodible_surfaces": [], "protected_rects": [], "routes": [], "landmarks": [], "gates": {}, "biomes": [{"id": region, "name": T.BIOME_NAMES[region], "rect": Rect2(Vector2.ZERO, T.SECTOR_SIZE)}]}
	var holes: Array = []
	for side: Vector2i in SIDES:
		s.gates[side] = boundary_gates(seed_value, at, side)
		for gate: Dictionary in s.gates[side]:
			var rect: Rect2
			if side.x != 0:
				rect = Rect2(128 if side.x < 0 else T.SECTOR_SIZE.x - 448, gate.floor - gate.height, 320, gate.height)
				_tunnel(s, holes, 0 if side.x < 0 else int(rect.position.x), int(rect.end.x) if side.x < 0 else int(T.SECTOR_SIZE.x), gate.floor, gate.floor, gate.height)
			else:
				rect = Rect2(gate.x - 32, 64 if side.y < 0 else T.SECTOR_SIZE.y - 512, 320, 256)
				if side.y < 0: _shaft(s, holes, gate.x, 0, int(rect.end.y), true)
			s.entrances.append({"rect": rect, "sides": [side], "horizontal_floors": [gate.floor] if side.x != 0 else []})
			s.protected_rects.append(rect.grow(96))
	# Near a corner two independently owned gates may open into one vestibule.
	# Treat it as one node; otherwise each mouth excludes every path to the other.
	var merged := true
	while merged:
		merged = false
		for i in range(s.entrances.size()):
			for j in range(i + 1, s.entrances.size()):
				if not s.entrances[i].rect.grow(63.9).intersects(s.entrances[j].rect): continue
				s.entrances[i].rect = s.entrances[i].rect.merge(s.entrances[j].rect)
				s.entrances[i].sides.append_array(s.entrances[j].sides)
				s.entrances[i].horizontal_floors.append_array(s.entrances[j].horizontal_floors)
				if Vector2i.DOWN in s.entrances[i].sides and not s.entrances[i].horizontal_floors.is_empty():
					s.entrances[i].rect.size.y = s.entrances[i].horizontal_floors[0] - s.entrances[i].rect.position.y
				s.entrances.remove_at(j)
				merged = true
				break
			if merged: break
	for entrance: Dictionary in s.entrances:
		holes.append(entrance.rect)
		s.protected_rects.append(entrance.rect.grow(96))
	for gate: Dictionary in s.gates[Vector2i.UP]:
		for entrance: Dictionary in s.entrances:
			if entrance.rect.has_point(Vector2(gate.x + 128, 224)) and entrance.rect.end.y > 320:
				if entrance.rect.end.y < 416:
					# The existing 224px landing reaches this floor directly. A
					# 320px plate would have less than 92px of clearance below it.
					holes.append(Rect2(gate.x, 320, 256, entrance.rect.end.y - 320))
				else: _shaft(s, holes, gate.x, 320, int(entrance.rect.end.y))
	for gate: Dictionary in s.gates[Vector2i.DOWN]:
		for entrance: Dictionary in s.entrances:
			if Vector2i.DOWN in entrance.sides and gate.x + 128 >= entrance.rect.position.x and gate.x + 128 < entrance.rect.end.x:
				_shaft(s, holes, gate.x, int(entrance.rect.end.y), int(T.SECTOR_SIZE.y), true)
	var layout := _layout(s, rng)
	if layout.is_empty(): return {}
	s.chambers = layout.rooms
	s.connections = layout.edges
	s.connection_candidates = layout.candidates
	s.connection_nodes = layout.nodes
	s.cycles = layout.cycles
	for room: Dictionary in s.chambers:
		holes.append(room.rect)
		if room.kind != "normal": s.protected_rects.append(room.rect.grow(64))
		if room.kind == "boss":
			var pos := Vector2(G._pick(rng, int(room.rect.position.x + 256) / 32, int(room.rect.end.x - 256) / 32) * 32, room.rect.end.y - T.BOSS_SIZE.y / 2)
			s.spawns.append({"id": "guardian_%d" % boss_id, "kind": "boss", "boss_id": boss_id, "polarity": int(seed_value & 1), "position": pos, "patrol": Vector2(pos.x, pos.x), "chamber_id": room.id})
			s.landmarks.append({"id": boss_id, "position": pos})
	for edge: Dictionary in layout.edges:
		if edge.type in ["shaft", "elbow"]:
			var rect: Rect2 = edge.rect if edge.type == "shaft" else edge.shaft
			_shaft(s, holes, int(rect.position.x), int(rect.position.y), int(rect.end.y), false, int(rect.size.x))
		if edge.type in ["tunnel", "elbow"]:
			var bounds: Rect2 = edge.pieces[0]
			for piece: Rect2 in edge.pieces:
				holes.append(piece)
				s.protected_rects.append(piece.grow(96))
				bounds = bounds.merge(piece)
			s.tunnels.append({"rect": bounds, "pieces": edge.pieces, "height": edge.height})
	var shelves: Array = s.solids
	s.solids = G._carve(holes, T.SECTOR_SIZE) + shelves
	_bridge_floors(s)
	for room: Dictionary in s.chambers:
		if s.solids.filter(func(r): return r.size.y == 16 and room.rect.encloses(r)).size() > 4: return {}
	# Retry furnishing against the same carved layout, without throwing away a
	# sound tree because one randomly chosen step, block or enemy obstructs it.
	for furnishing in range(8):
		var finished := _finish(s.duplicate(true), rng)
		var graphs: Array = finished.get("_graphs", [])
		finished.erase("_graphs")
		if validate(finished, graphs).is_empty():
			# Hand the already checked graph to loot placement, then discard it.
			finished._graphs = graphs
			return finished
	return {}

static func _bridge_floors(s: Dictionary) -> void:
	# An elbow can enter the ceiling of its lower chamber. Bridge that open
	# portion to the ladder, so the horizontal branch retains a standing floor.
	for tunnel: Dictionary in s.tunnels:
		var bridges: Array = []
		for piece: Rect2 in tunnel.pieces:
			if G._supported(Vector2(piece.get_center().x, piece.end.y - 22), T.PLAYER_SIZE, s.solids): continue
			var spans: Array[Vector2] = [Vector2(piece.position.x, piece.end.x)]
			for rock: Rect2 in s.solids:
				if rock.size.y == 16 or rock.position.y >= piece.end.y + 92 or rock.end.y <= piece.end.y - 76: continue
				spans = G._subtract(spans, rock.position.x, rock.end.x)
			for span: Vector2 in spans:
				if span.y - span.x < 32: continue
				var bridge := Rect2(span.x, piece.end.y, span.y - span.x, 16)
				if not bridges.is_empty() and bridges[-1].end.x == bridge.position.x and bridges[-1].position.y == bridge.position.y: bridges[-1].size.x += bridge.size.x
				else: bridges.append(bridge)
		s.solids.append_array(bridges)

static func _finish(s: Dictionary, rng) -> Dictionary:
	if s.fallback: _fallback_decorate(s)
	else: G._decorate(s, rng)
	var anchor: Dictionary = s.chambers[0]
	s.start_position = T.SECTOR_START if s.coord == Vector2i.ZERO else Vector2(anchor.rect.position.x + 64, anchor.rect.end.y - 22)
	if s.coord != Vector2i.ZERO:
		for x in range(int(anchor.rect.position.x) + 32, int(anchor.rect.end.x) - 32, 32):
			var point := Vector2(x, anchor.rect.end.y - 22)
			if G._supported(point, T.PLAYER_SIZE, s.solids) and not G._embedded(point, T.PLAYER_SIZE, s.solids):
				s.start_position = point
				break
	s.protected_rects.append(Rect2(s.start_position + Vector2(-32, -10), Vector2(64, 128)))
	for room: Dictionary in s.chambers: G._add_surface(s, room.rect.position.x, room.rect.end.x, room.rect.end.y)
	var graph := G.navigation_graph(s)
	if not s.fallback and not G.connectivity_errors(s, false, graph).is_empty(): return {}
	var supports: Array = []
	for room: Dictionary in s.chambers:
		for surface: Rect2 in graph.nodes:
			for x: float in [surface.position.x + 32, surface.get_center().x, surface.end.x - 32]:
				var point := Vector2(x, surface.position.y - 22)
				if room.rect.has_point(point) and G._supported(point, T.PLAYER_SIZE, s.solids) and not G._embedded(point, T.PLAYER_SIZE, s.solids): room.approaches.append(point)
			if surface.position.y - 22 < room.rect.position.y or surface.position.y - 22 >= room.rect.end.y: continue
			var left := maxf(surface.position.x, room.rect.position.x)
			var right := minf(surface.end.x, room.rect.end.x)
			if right > left: supports.append(Rect2(left, surface.position.y, right - left, 0))
	var blocks: Array = []
	for room: Dictionary in s.chambers:
		if room.kind != "normal": continue
		for surface: Rect2 in supports:
			if not room.rect.has_point(Vector2(surface.get_center().x, surface.position.y - 22)): continue
			for x in range(int(surface.position.x) + 32, int(surface.end.x) - 32, 32): blocks.append(Rect2(x, surface.position.y - 32, 32, 32))
	var terrain := s.duplicate(false)
	var graphs: Array = []
	if s.fallback:
		# The emergency path enumerates sites without randomness.
		for block: Rect2 in blocks:
			if s.breakables.size() == T.SECTOR_BLOCK_COUNT: break
			if not G.block_is_valid(block, s): continue
			s.breakables.append(block)
			terrain.solids = s.solids + s.breakables
			var trial_graphs: Array = [G.navigation_graph(terrain), G.navigation_graph(terrain, true)]
			if not G.connectivity_errors(terrain, false, trial_graphs[0]).is_empty() or not G.connectivity_errors(terrain, true, trial_graphs[1]).is_empty(): s.breakables.pop_back()
	else:
		# Validate a sampled set once. Reuse the carved/furnished geometry if one
		# set blocks a return jump, rather than rebuilding a graph per candidate.
		for trial in range(6):
			s.breakables.clear()
			G._shuffle(blocks, rng)
			for block: Rect2 in blocks:
				if s.breakables.size() == T.SECTOR_BLOCK_COUNT: break
				if G.block_is_valid(block, s): s.breakables.append(block)
			terrain.solids = s.solids + s.breakables
			graphs = [G.navigation_graph(terrain, false, graph, s.breakables), G.navigation_graph(terrain, true)]
			if G.connectivity_errors(terrain, false, graphs[0]).is_empty() and G.connectivity_errors(terrain, true, graphs[1]).is_empty(): break
			graphs.clear()
		if graphs.is_empty(): return {}
	var placement := s.duplicate(false)
	# Match block_is_valid's enemy margin, including the full patrol body.
	placement.solids = s.solids + s.breakables.map(func(r): return Rect2(r.position - Vector2(32, 0), r.size + Vector2(64, 0)))
	G._populate(placement, rng, {"nodes": supports}, T.SECTOR_NORMAL_COUNT, T.CAVE_SAFE_RADIUS if s.coord == Vector2i.ZERO else 0.0)
	_place_hearts(s, graphs[0] if not graphs.is_empty() else G.navigation_graph(terrain))
	if not s.fallback: s._graphs = graphs
	return s

static func enemy_spawn_area(e: Dictionary) -> Rect2:
	return Population.area(e)

static func heart_site_valid(s: Dictionary, point: Vector2) -> bool:
	var standing := Rect2(point - T.PLAYER_SIZE / 2, T.PLAYER_SIZE)
	if not s.chambers.any(func(room): return room.kind == "normal" and room.rect.encloses(standing)): return false
	if not G._supported(point, T.PLAYER_SIZE, s.solids) or G._embedded(point, T.PLAYER_SIZE, s.solids + s.breakables): return false
	if s.breakables.any(func(r): return r.grow(4).intersects(standing)): return false
	if s.spawns.any(func(e): return enemy_spawn_area(e).grow(8).intersects(standing)): return false
	return true

static func _place_hearts(s: Dictionary, graph: Dictionary) -> void:
	s.hearts = []
	var rng := RandomNumberGenerator.new()
	rng.seed = _key(s.seed, s.coord, "hearts")
	var wanted := rng.randi_range(T.SECTOR_HEART_MIN, T.SECTOR_HEART_MAX)
	var candidates: Array[Vector2] = []
	for surface: Rect2 in graph.nodes:
		for x in range(ceili(surface.position.x / 32) * 32 + 16, int(surface.end.x) - 16, 32):
			var point := Vector2(x, surface.position.y - T.PLAYER_SIZE.y / 2)
			if heart_site_valid(s, point): candidates.append(point)
	G._shuffle(candidates, rng)
	for point: Vector2 in candidates:
		if s.hearts.size() >= wanted: break
		if s.hearts.any(func(h): return h.position.distance_to(point) < 128): continue
		s.hearts.append({"id": "heart_%d" % s.hearts.size(), "position": point})

static func heart_errors(s: Dictionary, graph: Dictionary = {}) -> Array[String]:
	var errors: Array[String] = []
	if not s.has("hearts") or not s.hearts is Array: return ["Missing hearts"]
	if s.hearts.size() > T.SECTOR_HEART_MAX: errors.append("Heart count")
	var ids := {}
	for h: Dictionary in s.hearts:
		if not h.has("id") or not h.has("position") or not h.position is Vector2:
			errors.append("Heart data")
			continue
		if ids.has(h.id): errors.append("Duplicate heart ID")
		ids[h.id] = true
		if not heart_site_valid(s, h.position): errors.append("Heart placement")
		if not graph.is_empty() and G.node_at(graph, h.position) < 0 and G.node_at(graph, h.position + Vector2(0, T.SURFACE_DEPTH)) < 0: errors.append("Heart unreachable")
	return errors

# A deterministic emergency layout: two ladder rails and isolated room floors.
# Arbitrary canonical gates join the rails, not a selected floor band.
static func _fallback_build(seed_value: int, at: Vector2i) -> Dictionary:
	var region := region_at(seed_value, at)
	var boss_id := guardian_sectors(seed_value).find(at)
	var s := {"seed": seed_value, "coord": at, "fallback": true, "region": region,
		"bounds": Rect2(Vector2.ZERO, T.SECTOR_SIZE), "start_position": T.SECTOR_START,
		"chambers": [], "entrances": [], "connections": [], "connection_candidates": [], "cycles": 0,
		"tunnels": [], "shafts": [], "solids": [], "spawns": [], "breakables": [],
		"erodible_surfaces": [], "protected_rects": [], "routes": [], "landmarks": [], "gates": {}, "biomes": [{"id": region, "name": T.BIOME_NAMES[region], "rect": Rect2(Vector2.ZERO, T.SECTOR_SIZE)}]}
	var holes: Array = []
	for floor_y: int in [864, 1760, 2656]:
		for x: int in [448, 2496]:
			var kind := "start" if at == Vector2i.ZERO and x == 448 and floor_y == 1760 else ("boss" if boss_id >= 0 and x == 2496 and floor_y == 1760 else "normal")
			var height := 640 if kind == "start" else (512 if floor_y == 864 else 576)
			var rect := Rect2(x, floor_y - height, 1152, height)
			var room := _node(rect, kind, s.chambers.size(), region)
			s.chambers.append(room)
			holes.append(rect)
			if kind != "normal": s.protected_rects.append(rect.grow(64))
			if kind == "boss":
				var pos := Vector2(3424, floor_y - T.BOSS_SIZE.y / 2)
				s.spawns.append({"id": "guardian_%d" % boss_id, "kind": "boss", "boss_id": boss_id, "polarity": int(seed_value & 1), "position": pos, "patrol": Vector2(pos.x, pos.x), "chamber_id": room.id})
				s.landmarks.append({"id": boss_id, "position": pos})
		_tunnel(s, holes, 288, 480, floor_y, floor_y, 192)
		_tunnel(s, holes, 1568, 2528, floor_y, floor_y, 192)
		_tunnel(s, holes, 3616, 3808, floor_y, floor_y, 192)
	for x: int in [64, 3776]:
		holes.append(Rect2(x, 64, 256, 2976))
		_shaft(s, holes, x, 160, 3040)
		var rail: Dictionary = s.shafts[-1]
		for shelf: Rect2 in rail.platforms: s.solids.erase(shelf)
		rail.platforms = rail.platforms.map(func(r): return Rect2(r.position + Vector2(128 if x == 64 else 0, 0), Vector2(128, 16)))
		s.solids.append_array(rail.platforms)
		for y: int in [864, 2656, 2944]: s.solids.append(Rect2(x + (128 if x == 64 else 0), y, 128, 16))
	for side: Vector2i in SIDES:
		s.gates[side] = boundary_gates(seed_value, at, side)
		for gate: Dictionary in s.gates[side]:
			if side.x != 0:
				_tunnel(s, holes, 0 if side.x < 0 else 3904, 192 if side.x < 0 else 4096, gate.floor, gate.floor, gate.height)
				s.solids.append(Rect2(64 if side.x < 0 else 3840, gate.floor, 192, 16))
			else:
				_shaft(s, holes, gate.x, 0 if side.y < 0 else 2944, 320 if side.y < 0 else 3072, true)
				_tunnel(s, holes, mini(gate.x, 192 if gate.x < 2048 else 3776), maxi(gate.x + 256, 320 if gate.x < 2048 else 3904), 320 if side.y < 0 else 2944, 320 if side.y < 0 else 2944, 192)
	var shelves: Array = s.solids
	s.solids = G._carve(holes, T.SECTOR_SIZE) + shelves
	_bridge_floors(s)
	return _finish(s, null)

static func _fallback_decorate(s: Dictionary) -> void:
	for room: Dictionary in s.chambers:
		var r: Rect2 = room.rect
		var shelf := Rect2(r.position.x + 160, r.end.y - 128, 192, 16)
		s.solids.append(shelf)
		room.shelves = s.solids.filter(func(p): return p.size.y == 16 and r.encloses(p))
		s.protected_rects.append(Rect2(shelf.get_center().x - 32, r.end.y - 32, 64, 128))
		if room.kind != "normal": continue
		var step := Rect2(r.position.x + 544, r.end.y - 64, 128, 64)
		room.floor_steps.append(step)
		s.solids.append(step)
		s.protected_rects.append(step.grow(96))
		var rock := Rect2(r.position.x + 864, r.end.y - 64, 96, 64)
		room.rocks.append(rock)
		s.solids.append(rock)

static func signature(s: Dictionary) -> String:
	return str(s)

static func gate_positions(s: Dictionary) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for side: Vector2i in SIDES:
		for g: Dictionary in s.gates[side]:
			if side.x != 0: points.append(Vector2(64 if side.x < 0 else T.SECTOR_SIZE.x - 64, g.floor - 22))
			else: points.append(Vector2(g.x + 128, (96 if side.y < 0 else T.SECTOR_SIZE.y - 32) - 22))
	return points

static func validate(s: Dictionary, generated_graphs: Array = []) -> Array[String]:
	var errors: Array[String] = []
	for key: String in ["bounds", "seed", "coord", "chambers", "solids", "shafts", "tunnels", "gates", "spawns", "breakables", "erodible_surfaces", "protected_rects", "start_position", "region"]:
		if not s.has(key): errors.append("Missing " + key)
	if not errors.is_empty(): return errors
	if s.get("bounds", Rect2()) != Rect2(Vector2.ZERO, T.SECTOR_SIZE): errors.append("Sector bounds")
	if s.region != region_at(s.seed, s.coord): errors.append("Sector region")
	if s.get("biomes", []) != [{"id": s.region, "name": T.BIOME_NAMES[s.region], "rect": s.bounds}]: errors.append("Sector biome metadata")
	if s.chambers.size() < 3: return ["Missing anchor chamber"]
	if s.coord == Vector2i.ZERO and s.start_position != T.SECTOR_START: errors.append("Local anchor")
	if s.chambers.size() not in range(4, 9): errors.append("Chamber count")
	for side: Vector2i in SIDES:
		if s.gates.get(side, []) != boundary_gates(s.seed, s.coord, side): errors.append("Canonical gate mismatch")
	var thick_solids: Array = s.solids.filter(func(r): return r.size.y != 16)
	for solid: Rect2 in s.solids:
		if not s.bounds.encloses(solid) or solid.size.x <= 0 or solid.size.y <= 0: errors.append("Solid bounds")
		for v: float in [solid.position.x, solid.position.y, solid.size.x]:
			if fmod(v, 32) != 0: errors.append("Terrain grid")
		if solid.size.y == 16:
			var inset := minf(16, solid.size.x / 4)
			for dy: float in [-76, 16]:
				if G._any_intersects(thick_solids, Rect2(solid.position + Vector2(inset, dy), Vector2(solid.size.x - inset * 2, 76)).grow(-0.1)): errors.append("Shelf clearance")
	var starts := 0
	var boss_rooms := 0
	var step_rooms := 0
	var rock_rooms := 0
	var normal_rooms := 0
	for room: Dictionary in s.chambers:
		var r: Rect2 = room.rect
		if room.id < 0 or room.id >= s.chambers.size() or s.chambers[room.id] != room or room.region != s.region: errors.append("Chamber identity")
		starts += int(room.kind == "start")
		boss_rooms += int(room.kind == "boss")
		if room.kind == "normal":
			normal_rooms += 1
			step_rooms += int(not room.floor_steps.is_empty())
			rock_rooms += int(not room.rocks.is_empty())
		if not s.bounds.encloses(r) or room.kind not in ["normal", "start", "boss"]: errors.append("Chamber placement/kind")
		if r.size.x < 640 or r.size.x > 1536 or r.size.y < 320 or r.size.y > 704: errors.append("Chamber dimensions")
		if room.kind == "start" and (s.coord != Vector2i.ZERO or r.size.x < 896 or r.size.y != T.CAVE_START_HEIGHT or not r.has_point(T.SECTOR_START)): errors.append("Start chamber")
		if room.kind == "boss" and (r.size.x < 1024 or r.size.x > 1408 or r.size.y < 576): errors.append("Boss chamber")
		if room.kind != "normal" and not s.protected_rects.any(func(p): return p.encloses(r)): errors.append("Unprotected special chamber")
		for other: Dictionary in s.chambers:
			if room.id < other.id and r.grow(63.9).intersects(other.rect): errors.append("Chamber rock gap")
		if room.shelves.size() < 1 or room.shelves.size() > 4: errors.append("Chamber shelf count")
		if room.shelves != s.solids.filter(func(p): return p.size.y == 16 and r.encloses(p)): errors.append("Shelf metadata")
		if room.floor_steps.size() > 3 or room.rocks.size() > 2: errors.append("Chamber feature count")
		for step: Rect2 in room.floor_steps:
			if not r.encloses(step) or not s.solids.has(step) or step.end.y != r.end.y or step.size.y < 32 or step.size.y > 128: errors.append("Floor step")
		for rock: Rect2 in room.rocks:
			if not r.encloses(rock) or not s.solids.has(rock) or (rock.position.y != r.position.y and rock.end.y != r.end.y) or (rock.position.y == r.position.y and r.end.y - rock.end.y < 160): errors.append("Rock clearance")
		for point: Vector2 in room.approaches:
			if not r.has_point(point) or not G._supported(point, T.PLAYER_SIZE, s.solids) or G._embedded(point, T.PLAYER_SIZE, s.solids): errors.append("Standing approach")
	if starts != int(s.coord == Vector2i.ZERO) or boss_rooms != int(s.coord in guardian_sectors(s.seed)): errors.append("Special chamber count")
	if step_rooms < normal_rooms * 0.5 or rock_rooms < normal_rooms * 0.3: errors.append("Chamber feature distribution")
	for shaft: Dictionary in s.shafts:
		if shaft.rect.size.x < 160 or shaft.rect.size.x > 320 or shaft.platforms.is_empty(): errors.append("Shaft dimensions")
		var platforms: Array = shaft.platforms
		for shelf: Rect2 in platforms:
			if not s.solids.has(shelf) or shelf.position.x < shaft.rect.position.x or shelf.end.x > shaft.rect.end.x: errors.append("Shaft platform missing")
		if not s.protected_rects.any(func(p): return p.encloses(shaft.rect.grow(96))): errors.append("Shaft protection")
		for i in range(1, platforms.size()):
			var a: Rect2 = platforms[i - 1]
			var b: Rect2 = platforms[i]
			if b.position.y - a.position.y < 96 or b.position.y - a.position.y > 160 or minf(a.end.x,b.end.x)-maxf(a.position.x,b.position.x)<54: errors.append("Shaft spacing")
	for tunnel: Dictionary in s.tunnels:
		for i in range(tunnel.pieces.size()):
			var piece: Rect2 = tunnel.pieces[i]
			if tunnel.height < 160 or tunnel.height > 256 or G._embedded(Vector2(piece.get_center().x, piece.end.y - 22), T.PLAYER_SIZE, s.solids) or not G._supported(Vector2(piece.get_center().x, piece.end.y - 22), T.PLAYER_SIZE, s.solids): errors.append("Tunnel clearance/support")
			if i > 0 and absf(piece.end.y - tunnel.pieces[i-1].end.y) > 64: errors.append("Tunnel step")
	for surface: Rect2 in s.erodible_surfaces:
		if surface.size.y != 64 or G.protected_rect(surface, s) or not G._has_rock_depth(Rect2(surface.position, surface.size * Vector2(1, 2)), s.solids): errors.append("Erosion/protection/depth")
		if not s.chambers.any(func(r): return r.rect.end.y == surface.position.y and surface.position.x >= r.rect.position.x and surface.end.x <= r.rect.end.x) or not G._supported(Vector2(surface.get_center().x, surface.position.y - 22), Vector2(surface.size.x, 44), s.solids): errors.append("Erosion exposed floor")
	var terrain := s.duplicate(false)
	terrain.solids = s.solids + s.breakables
	var loot_graph := {}
	for damaged: bool in [false, true]:
		var graph: Dictionary = generated_graphs[int(damaged)] if generated_graphs.size() == 2 else G.navigation_graph(terrain, damaged)
		if not damaged: loot_graph = graph
		errors.append_array(G.connectivity_errors(s, damaged, graph))
		for point: Vector2 in gate_positions(s):
			if G.node_at(graph, point) < 0: errors.append("Gate standing point")
		errors.append_array(heart_errors(s, graph))
	var kinds := {}
	var rooms := {}
	var ids := {}
	var bosses := 0
	for e: Dictionary in s.spawns:
		if e.kind not in G.NORMAL_KINDS + ["boss", "enhancer"] or e.polarity not in [0, 1]: errors.append("Enemy kind/color")
		if e.chamber_id < 0 or e.chamber_id >= s.chambers.size():
			errors.append("Enemy chamber ID")
			continue
		if ids.has(e.id): errors.append("Duplicate enemy ID")
		ids[e.id] = true
		var room: Dictionary = s.chambers[e.chamber_id]
		if e.kind == "boss":
			bosses += 1
			if guardian_sectors(s.seed).find(s.coord) != e.boss_id or room.kind != "boss" or e.boss_id != s.region: errors.append("Guardian assignment")
			if not s.get("landmarks", []).any(func(mark): return mark.id == e.boss_id and mark.position == e.position): errors.append("Guardian landmark")
		elif e.kind == "enhancer":
			if not Population.enhancer_valid(e,s): errors.append("Enhancer placement/coverage/reachability")
		else:
			kinds[e.kind] = kinds.get(e.kind, 0) + 1
			rooms[e.chamber_id] = rooms.get(e.chamber_id, 0) + 1
			if room.kind != "normal" or (s.coord == Vector2i.ZERO and e.position.distance_to(T.SECTOR_START) < 640): errors.append("Enemy safety")
			if not G.has_attack_sight(e, s): errors.append("Enemy sight")
		if e.kind == "enhancer":
			if e.patrol != Vector2(e.position.x-T.ENHANCER_DRIFT,e.position.x+T.ENHANCER_DRIFT): errors.append("Enhancer drift bounds")
		elif e.kind == "flyer":
			if not G.lane_is_clear(e.support, s.solids + s.breakables) or e.position.y != e.support.position.y - T.FLYER_ALTITUDE or e.patrol.x < e.support.position.x + 48 or e.patrol.y > e.support.end.x - 48 or e.patrol.x >= e.patrol.y: errors.append("Flight lane")
			if not room.rect.encloses(Rect2(e.position - T.ENEMY_SIZE / 2, T.ENEMY_SIZE)): errors.append("Flyer chamber bounds")
		else:
			var size: Vector2 = T.BOSS_SIZE if e.kind == "boss" else T.ENEMY_SIZE
			var center := Vector2((e.patrol.x + e.patrol.y) / 2, e.position.y)
			var body := Vector2(e.patrol.y - e.patrol.x + size.x, size.y)
			if not G._supported(center, body, s.solids) or G._embedded(center, body, s.solids + s.breakables): errors.append("Enemy support")
			if not room.rect.encloses(Rect2(e.position - size / 2, size)): errors.append("Enemy chamber bounds")
			if e.kind in ["boss", "turret", "builder", "breaker", "laser"] and e.patrol != Vector2(e.position.x, e.position.x): errors.append("Fixed enemy patrol")
			if e.kind == "builder" and not s.solids.any(func(r): return r.size.y != 16 and r.position.y == e.position.y + 22 and r.position.x <= e.position.x - 19 and r.end.x >= e.position.x + 19): errors.append("Builder thick support")
		if e.position.x < e.patrol.x or e.position.x > e.patrol.y: errors.append("Enemy outside patrol")
	var lanterns: int = s.spawns.filter(func(e): return e.kind == "enhancer").size()
	if lanterns > 1 or (s.has("loot") and s.coord == Vector2i.ZERO and lanterns != 1): errors.append("Enhancer count/first unlock")
	var count: int = s.spawns.size() - bosses - lanterns
	if count != T.SECTOR_NORMAL_COUNT or kinds.size() != 7: errors.append("Enemy count/kinds: %s" % kinds)
	var arc: int = kinds.get("breaker", 0) + kinds.get("flyer", 0) + kinds.get("laser", 0)
	if arc < count * 0.45 or arc > count * 0.60 or kinds.values().any(func(n): return n > count * 0.30): errors.append("Enemy ratios")
	if rooms.values().any(func(n): return n > 5): errors.append("Room enemy cap")
	if bosses != int(s.coord in guardian_sectors(s.seed)): errors.append("Guardian count")
	if s.get("landmarks", []).size() != bosses: errors.append("Landmark count")
	var fixture := s.duplicate(false)
	fixture.breakables = []
	for block: Rect2 in s.breakables:
		if not G.block_is_valid(block, fixture): errors.append("Breakable support/placement")
		fixture.breakables.append(block)
	if s.breakables.size() != T.SECTOR_BLOCK_COUNT: errors.append("Block count")
	errors.append_array(_shell_errors(s))
	if s.has("loot"): errors.append_array(L.errors(s,loot_graph))
	return errors

# Check the whole 32px strip: two neighbors retain 64px of rock outside openings.
static func _shell_errors(s: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var thick: Array = s.solids.filter(func(r): return r.size.y != 16)
	for side: Vector2i in SIDES:
		var length := int(T.SECTOR_SIZE.y if side.x != 0 else T.SECTOR_SIZE.x)
		var border := Rect2(0 if side.x < 0 else T.SECTOR_SIZE.x - 32, 0, 32, T.SECTOR_SIZE.y) if side.x != 0 else Rect2(0, 0 if side.y < 0 else T.SECTOR_SIZE.y - 32, T.SECTOR_SIZE.x, 32)
		var boundary_rock: Array = thick.filter(func(r): return r.intersects(border))
		for t in range(0, length, 32):
			var cell := Rect2(0 if side.x < 0 else T.SECTOR_SIZE.x - 32, t, 32, 32) if side.x != 0 else Rect2(t, 0 if side.y < 0 else T.SECTOR_SIZE.y - 32, 32, 32)
			var open := false
			for gate: Dictionary in s.gates[side]:
				if side.x != 0: open = open or (t >= gate.floor - gate.height and t < gate.floor)
				else: open = open or (t >= gate.x and t < gate.x + gate.width)
			var area := 0.0
			for r: Rect2 in boundary_rock: area += r.intersection(cell).get_area() if r.intersects(cell) else 0.0
			if (open and area != 0) or (not open and not is_equal_approx(area, cell.get_area())): errors.append("Boundary rock/opening mismatch")
	return errors

# Compose actual geometry, then use the same movement graph as the finite world.
static func combined_stage(sectors: Array) -> Dictionary:
	var merged := {"solids": [], "erodible_surfaces": [], "optional_surfaces": [], "navigation_bounds": [], "start_position": Vector2.ZERO}
	for s: Dictionary in sectors:
		var offset := Vector2(s.coord) * T.SECTOR_SIZE
		merged.navigation_bounds.append(Rect2(offset, T.SECTOR_SIZE))
		for field in ["solids", "erodible_surfaces"]:
			for r: Rect2 in s[field]: merged[field].append(Rect2(r.position + offset, r.size))
		for r: Rect2 in s.get("optional_surfaces", []): merged.optional_surfaces.append(Rect2(r.position + offset, r.size))
		for block: Rect2 in s.breakables: merged.solids.append(Rect2(block.position + offset, block.size))
		if s.coord == Vector2i.ZERO or merged.start_position == Vector2.ZERO: merged.start_position = s.start_position + offset
	return merged

static func navigation_graph(sectors: Array, damaged: bool = false, abilities: int = 0) -> Dictionary:
	return G.navigation_graph(combined_stage(sectors), damaged, {}, [], abilities)

static func seam_errors(a: Dictionary, b: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var side: Vector2i = b.coord - a.coord
	if side not in SIDES: return ["Non-adjacent sectors"]
	if a.seed != b.seed or a.gates[side] != b.gates[-side]: errors.append("Shared gate mismatch")
	errors.append_array(_shell_errors(a))
	errors.append_array(_shell_errors(b))
	# Inspect actual geometry around each opening. Local validation already proves
	# both complete interiors strongly connected; do not rebuild both interiors
	# for every edge of a large set. The 3x3 test also checks the full union graph.
	var union := combined_stage([a, b])
	for damaged: bool in [false, true]:
		var solids: Array = G.damaged_solids(union) if damaged else union.solids
		for gate: Dictionary in a.gates[side]:
			var r: Rect2 = gate.rect
			var area: Rect2
			var before: Vector2
			var after: Vector2
			if side.x != 0:
				area = Rect2(r.position.x - 192, r.position.y, 384, r.size.y + 192)
				before = Vector2(r.position.x - 64, r.end.y - 22)
				after = before + Vector2(128, 0)
			else:
				area = Rect2(r.position.x, r.position.y - 224, r.size.x, 480)
				before = Vector2(r.get_center().x, r.position.y - 32 - 22)
				after = before + Vector2(0, 128)
			var clipped: Array = []
			for solid: Rect2 in solids:
				if solid.intersects(area): clipped.append(solid.intersection(area))
			var graph := G.navigation_graph({"solids": clipped, "erodible_surfaces": [], "navigation_bounds": [area]})
			var first := G.node_at(graph, before)
			var last := G.node_at(graph, after)
			if first < 0 or last < 0 or not G._search(graph, first).has(last) or not G._search(graph, last).has(first): errors.append("Gate cannot be crossed in both directions")
	return errors

static func guardian_routes(sectors: Array, damaged: bool = false, generated_graph: Dictionary = {}) -> Array:
	var union := combined_stage(sectors)
	var graph := G.navigation_graph(union, damaged) if generated_graph.is_empty() else generated_graph
	var routes: Array = []
	for s: Dictionary in sectors:
		for e: Dictionary in s.spawns:
			if e.kind != "boss": continue
			var end: Vector2 = e.position + Vector2(s.coord) * T.SECTOR_SIZE + Vector2(0, T.BOSS_SIZE.y / 2 - 22)
			var origin := G.node_at(graph, union.start_position)
			var target := G.node_at(graph, end)
			routes.append({"boss_id": e.boss_id, "start": union.start_position, "end": end, "outward": G.path_steps(graph, origin, target, end), "returning": G.path_steps(graph, target, origin, union.start_position)})
	return routes
