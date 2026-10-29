extends RefCounted
## Pure local-coordinate data. No scene tree, global RNG, cache or game integration.
const T := preload("res://scripts/tuning.gd")
const G := preload("res://scripts/stage_generator.gd")
const L := preload("res://scripts/loot_generator.gd")
const Population := preload("res://scripts/enemy_population.gd")
const Vertical := preload("res://scripts/vertical_runs.gd")
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
	var diagonal := _diagonal(a, b, nodes, rng)
	if not diagonal.is_empty(): return diagonal
	var gentle := _gentle(a, b, nodes, rng)
	if not gentle.is_empty(): return gentle
	var long_direct := {}
	for trial in range(4):
		var direct := G._candidate(a, b, nodes, rng)
		if direct.is_empty() or direct.type != "shaft": break
		if direct.rect.size.y > T.VERTICAL_RUN_MAX: break
		if _gate_connection(direct, a, b):
			if direct.rect.size.y<=T.VERTICAL_DIRECT_LINK_PREFERRED_MAX: return direct
			long_direct=direct
			break
	var upper: Dictionary = a if a.rect.end.y < b.rect.end.y else b
	var lower: Dictionary = b if upper == a else a
	var u: Rect2 = upper.rect
	var l: Rect2 = lower.rect
	if l.end.y - u.end.y < 96 or l.end.y - u.end.y > T.VERTICAL_RUN_MAX: return long_direct
	var obstacles: Array = []
	for n: Dictionary in nodes:
		if n.id != a.id and n.id != b.id: obstacles.append(n.rect)
	var sites_by_bend: Array = []
	var gate_xs: Array = a.get("vertical_gate_x", []) + b.get("vertical_gate_x", [])
	for bend: Rect2 in [u,l]:
		var sites: Array = range(int(bend.position.x)+32,int(bend.end.x)-255,32)
		if not gate_xs.is_empty():
			var allowed: Array = []
			for px: int in sites:
				var clear := true
				for gate_x: float in gate_xs:
					if px < gate_x + 256 + T.VERTICAL_EXIT_RUN and px + 256 > gate_x - T.VERTICAL_EXIT_RUN:
						clear = false
						break
				if clear: allowed.append(px)
			sites = allowed
		sites_by_bend.append(sites)
	for trial in range(12):
		var bend: Rect2 = u if trial % 2 == 0 else l
		var sites: Array = sites_by_bend[trial % 2]
		if sites.is_empty(): continue
		var x: int = sites[G._pick(rng,0,sites.size()-1)]
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
		var run := right-left-256
		var ramp_rise := maxi(0,mini(run / T.GENTLE_RAMP_TREAD,mini(T.GENTLE_RAMP_RISE_MAX / 32,int(l.end.y-u.end.y-96) / 32))) * 32
		var bend_floor := int(l.end.y)-ramp_rise if trial%2==0 else int(u.end.y)+ramp_rise
		if trial%2==0: shaft.size.y=bend_floor-shaft.position.y
		else: shaft=Rect2(x,bend_floor,256,l.end.y-bend_floor)
		# Height was already drawn. A colliding shaft rejects the same union
		# without allocating its ramp pieces, and consumes no further RNG.
		var margin := T.CAVE_ROCK_GAP-0.1 if ramp_rise>0 else 32.0
		if G._any_intersects(obstacles, shaft.grow(margin)): continue
		var pieces: Array = []
		if other.end.x <= x:
			pieces=_ramp_pieces(left,x,int(other.end.y),bend_floor,height)
			pieces.append_array(_ramp_pieces(x,x+256,bend_floor,bend_floor,height))
		else:
			pieces=_ramp_pieces(x,x+256,bend_floor,bend_floor,height)
			pieces.append_array(_ramp_pieces(x+256,right,bend_floor,int(other.end.y),height))
		if _pieces_intersect(pieces, obstacles, margin): continue
		var bounds := shaft
		for p: Rect2 in pieces: bounds=bounds.merge(p)
		var edge := {"a": upper.id, "b": lower.id, "type": "elbow", "rect": bounds, "shaft": shaft, "pieces": pieces, "height": height, "gentle_leg":ramp_rise>0}
		if _gate_connection(edge, a, b): return edge
	return long_direct

# Keep the continuation of a vertical gate away from its column. The resulting
# standing vestibule leads to another part of the cave, rather than a blind lip.
static func _gate_connection(edge: Dictionary, a: Dictionary, b: Dictionary) -> bool:
	var shaft: Rect2 = edge.rect if edge.type == "shaft" else edge.shaft
	for n: Dictionary in [a, b]:
		for x: float in n.get("vertical_gate_x", []):
			if shaft.position.x < x + 256 + T.VERTICAL_EXIT_RUN and shaft.end.x > x - T.VERTICAL_EXIT_RUN: return false
	return true

static func _ramp_pieces(left: int, right: int, from_y: int, to_y: int, height: int) -> Array:
	var count := maxi(1,(right-left) / T.GENTLE_TREAD_MIN)
	var pieces: Array = []
	for i in range(count):
		var x := left+i*T.GENTLE_TREAD_MIN
		var y := from_y+roundi(float((to_y-from_y) / 32)*i/maxi(count-1,1))*32
		pieces.append(Rect2(x,y-height,right-x if i==count-1 else T.GENTLE_TREAD_MIN,height))
	return pieces

static func _gentle(a: Dictionary, b: Dictionary, nodes: Array, rng) -> Dictionary:
	if a.rect.position.x > b.rect.position.x:
		var swap := a
		a = b
		b = swap
	var left := int(a.rect.end.x) - 32
	var right := int(b.rect.position.x) + 32
	var run := right - left
	var rise := int(b.rect.end.y - a.rect.end.y)
	var count := run / T.GENTLE_TREAD_MIN
	if b.rect.position.x - a.rect.end.x < T.CAVE_ROCK_GAP or run > T.GENTLE_LENGTH_MAX or count < 2 or absi(rise) > (count - 1) * T.GENTLE_STEP_MAX: return {}
	var height := G._pick(rng, T.GENTLE_HEIGHT_MIN / 32, T.GENTLE_HEIGHT_MAX / 32) * 32
	var pieces: Array = []
	for i in range(count):
		var x := left + i * T.GENTLE_TREAD_MIN
		var y := int(a.rect.end.y) + roundi(float(rise / 32) * i / (count - 1)) * 32
		pieces.append(Rect2(x, y - height, right - x if i == count - 1 else T.GENTLE_TREAD_MIN, height))
	if _crosses_nodes(pieces, nodes, a.id, b.id, T.CAVE_ROCK_GAP - 0.1): return {}
	var bounds: Rect2 = pieces[0]
	for p: Rect2 in pieces: bounds = bounds.merge(p)
	return {"a":a.id,"b":b.id,"type":"tunnel","rect":bounds,"pieces":pieces,"height":height}

static func _diagonal(a: Dictionary, b: Dictionary, nodes: Array, rng) -> Dictionary:
	if a.rect.position.x > b.rect.position.x:
		var swap := a
		a = b
		b = swap
	var ar: Rect2 = a.rect
	var br: Rect2 = b.rect
	var left := int(ar.end.x) - 32
	var right := int(br.position.x) + 32
	var run := right - left
	var rise := int(absf(br.end.y - ar.end.y))
	if br.position.x - ar.end.x < T.CAVE_ROCK_GAP or run < T.DIAGONAL_LENGTH_MIN or run > T.DIAGONAL_LENGTH_MAX or rise < T.DIAGONAL_RISE_MIN: return {}
	var angle := rad_to_deg(atan2(rise, run))
	if angle < T.DIAGONAL_ANGLE_MIN or angle > T.DIAGONAL_ANGLE_MAX: return {}
	var count := maxi(ceili(float(run) / T.DIAGONAL_TREAD_TARGET), ceili(float(rise) / T.DIAGONAL_STEP_MAX) + 1)
	if count * T.DIAGONAL_TREAD_MIN > run: return {}
	var widths: Array[int] = []
	widths.resize(count)
	widths.fill(T.DIAGONAL_TREAD_MIN)
	var remaining := (run - count * T.DIAGONAL_TREAD_MIN) / 32
	while remaining > 0:
		var eligible: Array = range(count).filter(func(i): return widths[i] < T.DIAGONAL_TREAD_MAX)
		if eligible.is_empty(): return {}
		widths[eligible[G._pick(rng, 0, eligible.size() - 1)]] += 32
		remaining -= 1
	var height := G._pick(rng, T.DIAGONAL_HEIGHT_MIN / 32, T.DIAGONAL_HEIGHT_MAX / 32) * 32
	var units := rise / 32
	var climbed := 0
	var direction := signi(int(br.end.y - ar.end.y))
	var pieces: Array = []
	var x := left
	for i in range(count):
		if i > 0:
			var next := roundi(float(units) * i / (count - 1)) + G._pick(rng, -1, 1)
			climbed = clampi(next, maxi(climbed, units - (count - i - 1) * (T.DIAGONAL_STEP_MAX / 32)), mini(climbed + T.DIAGONAL_STEP_MAX / 32, units))
		var y := int(ar.end.y) + direction * climbed * 32
		pieces.append(Rect2(x, y - height, widths[i], height))
		x += widths[i]
	var bounds: Rect2 = pieces[0]
	for piece: Rect2 in pieces: bounds = bounds.merge(piece)
	if _crosses_nodes(pieces, nodes, a.id, b.id, 32): return {}
	# Reject a long accidental plateau before carving, rather than retrying furnishings.
	var flat := 0.0
	var previous_y := INF
	for piece: Rect2 in pieces:
		flat = flat + piece.size.x if piece.end.y == previous_y else piece.size.x
		if flat > T.DIAGONAL_LANDING_MAX: return {}
		previous_y = piece.end.y
	return {"a": a.id, "b": b.id, "type": "diagonal", "rect": bounds, "pieces": pieces, "height": height}

static func _cuts(edge: Dictionary) -> Array:
	if edge.type == "shaft": return [edge.rect]
	return edge.pieces + ([edge.shaft] if edge.type == "elbow" else [])

# Grow each cut once; the old nested Callables grew it again for every node.
static func _crosses_nodes(cuts: Array, nodes: Array, a: int, b: int, margin: float) -> bool:
	var obstacles: Array = []
	for n: Dictionary in nodes:
		if n.id != a and n.id != b: obstacles.append(n.rect)
	return _pieces_intersect(cuts, obstacles, margin)

static func _pieces_intersect(cuts: Array, obstacles: Array, margin: float) -> bool:
	for cut: Rect2 in cuts:
		if G._any_intersects(obstacles, cut.grow(margin)): return true
	return false

static func _compatible(edge: Dictionary, chosen: Array, nodes: Array) -> bool:
	for other: Dictionary in chosen:
		var margin: float = T.CAVE_ROCK_GAP / 2.0 - 0.05 if "tunnel" in [edge.type, other.type] or edge.get("gentle_leg",false) or other.get("gentle_leg",false) else 16.0
		if not edge.rect.grow(margin).intersects(other.rect.grow(margin)): continue
		for a: Rect2 in _cuts(edge):
			for b: Rect2 in _cuts(other):
				var overlap := a.grow(margin).intersection(b.grow(margin))
				if not overlap.has_area(): continue
				var shared := false
				for id: int in [edge.a, edge.b]:
					if (id == other.a or id == other.b) and nodes[id].rect.grow(32).encloses(overlap):
						shared = true
						break
				if not shared: return false
	return true

static func _layout(s: Dictionary, rng) -> Dictionary:
	for trial in range(10):
		var nodes: Array = []
		for entrance: Dictionary in s.entrances:
			var n := _node(entrance.rect, "entrance", nodes.size(), s.region)
			n.vertical_gate_x = []
			for side: Vector2i in [Vector2i.UP, Vector2i.DOWN]:
				if side not in entrance.sides: continue
				for gate: Dictionary in s.gates[side]:
					if gate.x + 128 >= entrance.rect.position.x and gate.x + 128 < entrance.rect.end.x: n.vertical_gate_x.append(gate.x)
			nodes.append(n)
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
				if anchor.end.y <= 512: gap = G._pick(rng,12,28) * 32
				if G._pick(rng, 0, T.DIAGONAL_LATERAL_ROOM_WEIGHT) < T.DIAGONAL_LATERAL_ROOM_WEIGHT:
					x = int(anchor.end.x) + gap if G._pick(rng, 0, 1) else int(anchor.position.x) - gap - w
					if rng.randf() < T.DIAGONAL_ROOM_CHANCE:
						var offset := int(snappedf((gap + 64) * rng.randf_range(T.DIAGONAL_ROOM_SLOPE_MIN, T.DIAGONAL_ROOM_SLOPE_MAX), 32))
						var direction := -1 if G._pick(rng,0,1) else 1
						if anchor.end.y <= 512: direction = 1
						elif anchor.end.y >= 2816: direction = -1
						floor_y = int(anchor.end.y) + offset * direction
					else:
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
				if edge.type == "diagonal": edge.weight *= T.DIAGONAL_WEIGHT
				elif edge.type == "tunnel": edge.weight *= T.GENTLE_WEIGHT
				elif edge.type=="shaft" and edge.rect.size.y>T.VERTICAL_DIRECT_LINK_PREFERRED_MAX: edge.weight*=T.VERTICAL_LONG_LINK_WEIGHT
				candidates.append(edge)
		candidates.sort_custom(func(a, b): return a.weight < b.weight)
		var reached := {0: true}
		var chosen: Array = []
		var remaining := candidates.duplicate()
		var incoming := {}
		while reached.size() < nodes.size():
			var index := -1
			for i in range(remaining.size()):
				var e: Dictionary = remaining[i]
				if reached.has(e.a) != reached.has(e.b) and (e.type in ["tunnel", "diagonal"] or not incoming.has(e.b)) and _compatible(e, chosen, nodes):
					index = i
					break
			if index < 0: break
			var edge: Dictionary = remaining.pop_at(index)
			chosen.append(edge)
			if edge.type not in ["tunnel", "diagonal"]: incoming[edge.b] = true
			reached[edge.a] = true
			reached[edge.b] = true
		if reached.size() != nodes.size(): continue
		G._shuffle(remaining, rng)
		remaining.sort_custom(func(a,b): return int(a.type not in ["tunnel","diagonal"]) < int(b.type not in ["tunnel","diagonal"]))
		var loops := G._pick(rng, 0, 3)
		var added := 0
		for edge: Dictionary in remaining:
			if added == loops: break
			if edge.type=="shaft" and edge.rect.size.y>T.VERTICAL_DIRECT_LINK_PREFERRED_MAX: continue
			if edge.type not in ["tunnel", "diagonal"] and incoming.has(edge.b): continue
			if not _compatible(edge, chosen, nodes): continue
			chosen.append(edge)
			if edge.type not in ["tunnel", "diagonal"]: incoming[edge.b] = true
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
			var entrance_floor: int = gate.get("floor",0)
			if side.x != 0:
				rect = Rect2(128 if side.x < 0 else T.SECTOR_SIZE.x - 448, gate.floor - gate.height, 320, gate.height)
				if gate.floor == int(T.SECTOR_SIZE.y)-T.VERTICAL_RUN_MAX/2-32:
					# A 32px step after the fixed boundary approach keeps a merged
					# bottom vestibule within the half-limit, with a solid tread.
					entrance_floor=gate.floor+32
					rect=Rect2(192 if side.x<0 else T.SECTOR_SIZE.x-448,entrance_floor-gate.height,256,gate.height)
					_tunnel(s,holes,0 if side.x<0 else 3904,192 if side.x<0 else 4096,gate.floor,gate.floor,gate.height)
					_tunnel(s,holes,192 if side.x<0 else 3648,448 if side.x<0 else 3904,entrance_floor,entrance_floor,gate.height)
				else:
					_tunnel(s, holes, 0 if side.x < 0 else int(rect.position.x), int(rect.end.x) if side.x < 0 else int(T.SECTOR_SIZE.x), gate.floor, gate.floor, gate.height)
			else:
				var entry_x: int = gate.x - 32 if gate.x < T.SECTOR_SIZE.x / 2 else gate.x + 288 - T.VERTICAL_VESTIBULE_WIDTH
				rect = Rect2(clampi(entry_x,32,int(T.SECTOR_SIZE.x)-32-T.VERTICAL_VESTIBULE_WIDTH), 64 if side.y < 0 else T.SECTOR_SIZE.y - 512, T.VERTICAL_VESTIBULE_WIDTH, T.VERTICAL_TOP_ENTRY_HEIGHT if side.y < 0 else 256)
			s.entrances.append({"rect": rect, "sides": [side], "horizontal_floors": [entrance_floor] if side.x != 0 else []})
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
				if (Vector2i.DOWN in s.entrances[i].sides or Vector2i.UP in s.entrances[i].sides) and not s.entrances[i].horizontal_floors.is_empty():
					s.entrances[i].rect.size.y = s.entrances[i].horizontal_floors[0] - s.entrances[i].rect.position.y
				s.entrances.remove_at(j)
				merged = true
				break
			if merged: break
	for entrance: Dictionary in s.entrances:
		holes.append(entrance.rect)
		s.protected_rects.append(entrance.rect.grow(96))
	# Carve gate columns after vestibule merging, so their floor and shelves
	# agree with a nearby horizontal gate.
	for gate: Dictionary in s.gates[Vector2i.UP]:
		for entrance: Dictionary in s.entrances:
			if entrance.rect.has_point(Vector2(gate.x+128,224)):
				_shaft(s,holes,gate.x,0,int(entrance.rect.end.y),true)
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
		if edge.type in ["tunnel", "elbow", "diagonal"]:
			var bounds: Rect2 = edge.pieces[0]
			for piece: Rect2 in edge.pieces:
				holes.append(piece)
				s.protected_rects.append(piece.grow(96))
				bounds = bounds.merge(piece)
			s.tunnels.append({"rect": bounds, "pieces": edge.pieces, "height": edge.height})
	var shelves: Array = s.solids
	s.solids = G._carve(holes, T.SECTOR_SIZE) + shelves
	_bridge_floors(s)
	_trim_gate_steps(s)
	_repair_gate_aprons(s)
	# Furnishings cannot repair an already unsupported passage floor.
	if not _tunnel_support_errors(s).is_empty(): return {}
	if not Vertical.errors(s, T.VERTICAL_RUN_MAX).is_empty(): return {}
	for room: Dictionary in s.chambers:
		if s.solids.filter(func(r): return r.size.y == 16 and room.rect.encloses(r)).size() > 4: return {}
	# Retry furnishing against the same carved layout, without throwing away a
	# sound tree because one randomly chosen step, block or enemy obstructs it.
	for furnishing in range(8):
		var finished := _finish(s.duplicate(true), rng)
		var graphs: Array = finished.get("_graphs", [])
		finished.erase("_graphs")
		var failure_list := validate(finished, graphs)
		if failure_list.is_empty():
			# Hand the already checked graph to loot placement, then discard it.
			finished._graphs = graphs
			return finished
	return {}

static func _trim_gate_steps(s: Dictionary) -> void:
	# Keep a landing beside (rather than 32px directly under) the horizontal
	# approach when a bottom gate shares its stepped corner vestibule.
	for side: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT]:
		if not s.gates[side].any(func(g): return g.floor==int(T.SECTOR_SIZE.y)-T.VERTICAL_RUN_MAX/2-32): continue
		for shaft: Dictionary in s.shafts:
			if not shaft.gate: continue
			for i in range(shaft.platforms.size()):
				var p: Rect2 = shaft.platforms[i]
				if p.position.y != int(T.SECTOR_SIZE.y)-T.VERTICAL_RUN_MAX/2: continue
				var cut: Rect2 = p
				if side.x<0 and p.position.x<192 and p.end.x>192: cut=Rect2(192,p.position.y,p.end.x-192,16)
				elif side.x>0 and p.position.x<3904 and p.end.x>3904: cut=Rect2(p.position,Vector2(3904-p.position.x,16))
				if cut==p: continue
				var index: int = s.solids.find(p)
				if index < 0: continue
				shaft.platforms[i]=cut
				s.solids[index]=cut

static func _repair_gate_aprons(s: Dictionary) -> void:
	# An elbow can undercut the floor of a wide top vestibule. Continue its
	# ladder to the real floor instead of leaving an unreachable last jump.
	# Only already empty space is used; no additional rock is carved.
	var thick: Array = s.solids.filter(func(r): return r.size.y!=16)
	for shaft: Dictionary in s.shafts.duplicate():
		var r: Rect2 = shaft.rect
		if not shaft.gate or r.position.y!=0: continue
		var bottom := INF
		for rock: Rect2 in thick:
			if minf(rock.end.x,r.end.x)-maxf(rock.position.x,r.position.x)<64: continue
			if rock.position.y>=r.end.y and rock.position.y<=r.end.y+T.CAVE_TUNNEL_MAX_HEIGHT: bottom=minf(bottom,rock.position.y)
		if bottom==INF or bottom<=r.end.y: continue
		var extended := Rect2(r.position,Vector2(r.size.x,bottom))
		if thick.any(func(rock): return rock.intersects(extended.grow(-0.1))): continue
		for plate: Rect2 in shaft.platforms: s.solids.erase(plate)
		s.shafts.erase(shaft)
		_shaft(s,[],int(r.position.x),0,int(bottom),true,int(r.size.x))

static func _bridge_floors(s: Dictionary) -> void:
	# An elbow can enter the ceiling of its lower chamber. Bridge that open
	# portion to the ladder, so the horizontal branch retains a standing floor.
	for tunnel: Dictionary in s.tunnels:
		var bridges: Array = []
		for piece: Rect2 in tunnel.pieces:
			if G._supported(Vector2(piece.get_center().x, piece.end.y - 22), T.PLAYER_SIZE, s.solids): continue
			# A merged vestibule can leave only 32/64px of air under a tread.
			# Fill that unusable sliver with rock; a one-way plate there would
			# violate the existing clearance test against the rock underneath.
			for x in range(int(piece.position.x),int(piece.end.x),32):
				if G._supported(Vector2(x+16,piece.end.y-22),Vector2(32,44),s.solids): continue
				var bottoms: Array = s.solids.filter(func(r): return r.size.y!=16 and r.position.x<=x and r.end.x>=x+32 and r.position.y>piece.end.y and r.position.y<=piece.end.y+64)
				if bottoms.is_empty(): continue
				var floor_y: float = bottoms.map(func(r): return r.position.y).min()
				s.solids.append(Rect2(x,piece.end.y,32,floor_y-piece.end.y))
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
	if not s.fallback:
		var normal: Array = s.chambers.filter(func(r): return r.kind=="normal")
		if normal.filter(func(r): return not r.floor_steps.is_empty()).size()<normal.size()*0.5 or normal.filter(func(r): return not r.rocks.is_empty()).size()<normal.size()*0.3: return {}
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
			if s.breakables.size() != T.SECTOR_BLOCK_COUNT: continue
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

static func _heart_site_valid(s: Dictionary, point: Vector2, solids: Array, blocked: Array) -> bool:
	var standing := Rect2(point - T.PLAYER_SIZE / 2, T.PLAYER_SIZE)
	var inside := false
	for room: Dictionary in s.chambers:
		if room.kind == "normal" and room.rect.encloses(standing):
			inside = true
			break
	if not inside: return false
	if not G._supported(point, T.PLAYER_SIZE, solids) or G._embedded(point, T.PLAYER_SIZE, solids) or G._embedded(point, T.PLAYER_SIZE, s.breakables): return false
	return not G._any_intersects(blocked, standing)

static func _place_hearts(s: Dictionary, graph: Dictionary) -> void:
	s.hearts = []
	var rng := RandomNumberGenerator.new()
	rng.seed = _key(s.seed, s.coord, "hearts")
	var wanted := rng.randi_range(T.SECTOR_HEART_MIN, T.SECTOR_HEART_MAX)
	var candidates: Array[Vector2] = []
	var blocked: Array = []
	for r: Rect2 in s.breakables: blocked.append(r.grow(4))
	for e: Dictionary in s.spawns: blocked.append(enemy_spawn_area(e).grow(8))
	var buckets := G._x_buckets(s.solids, 0)
	var cache := {}
	for surface: Rect2 in graph.nodes:
		for x in range(ceili(surface.position.x / 32) * 32 + 16, int(surface.end.x) - 16, 32):
			var point := Vector2(x, surface.position.y - T.PLAYER_SIZE.y / 2)
			var nearby := G._x_near(s.solids, buckets, x - T.PLAYER_SIZE.x / 2, x + T.PLAYER_SIZE.x / 2, cache)
			if _heart_site_valid(s, point, nearby, blocked): candidates.append(point)
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
			var height := 640 if kind == "start" else (480 if floor_y == 864 else 576)
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
	# Both rails continue to other cave regions at the top and bottom. In
	# particular, gates close to a rail must not form a long shared column.
	for y: int in [320,2944]: _tunnel(s,holes,192,3904,y,y,192)
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
	errors.append_array(diagonal_errors(s))
	errors.append_array(Vertical.errors(s, T.VERTICAL_RUN_MAX))
	if s.get("bounds", Rect2()) != Rect2(Vector2.ZERO, T.SECTOR_SIZE): errors.append("Sector bounds")
	if s.region != region_at(s.seed, s.coord): errors.append("Sector region")
	if s.get("biomes", []) != [{"id": s.region, "name": T.BIOME_NAMES[s.region], "rect": s.bounds}]: errors.append("Sector biome metadata")
	if s.chambers.size() < 3:
		errors.append("Missing anchor chamber")
		return errors
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
		if room.kind != "normal" and not G._any_encloses(s.protected_rects, r): errors.append("Unprotected special chamber")
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
		if not G._any_encloses(s.protected_rects, shaft.rect.grow(96)): errors.append("Shaft protection")
		for i in range(1, platforms.size()):
			var a: Rect2 = platforms[i - 1]
			var b: Rect2 = platforms[i]
			if b.position.y - a.position.y < 96 or b.position.y - a.position.y > 160 or minf(a.end.x,b.end.x)-maxf(a.position.x,b.position.x)<54: errors.append("Shaft spacing")
	errors.append_array(_tunnel_support_errors(s))
	for surface: Rect2 in s.erodible_surfaces:
		if surface.size.y != 64 or G.protected_rect(surface, s) or not G._has_rock_depth(Rect2(surface.position, surface.size * Vector2(1, 2)), s.solids): errors.append("Erosion/protection/depth")
		if not s.chambers.any(func(r): return r.rect.end.y == surface.position.y and surface.position.x >= r.rect.position.x and surface.end.x <= r.rect.end.x) or not G._supported(Vector2(surface.get_center().x, surface.position.y - 22), Vector2(surface.size.x, 44), s.solids): errors.append("Erosion exposed floor")
	var terrain := s.duplicate(false)
	terrain.solids = s.solids + s.breakables
	var loot_graph := {}
	for damaged: bool in [false, true]:
		var graph_terrain := terrain
		if damaged:
			var eroded := s.duplicate(false)
			eroded.solids=G.damaged_solids(s)
			errors.append_array(Vertical.errors(eroded,T.VERTICAL_RUN_MAX))
			if generated_graphs.size() != 2:
				graph_terrain = terrain.duplicate(false)
				# Subtraction preserves order and treats each rectangle independently.
				# Share the eroded rock with the vertical check; breakables stay graph-only.
				graph_terrain.solids = eroded.solids + G.subtract_rects(s.breakables,s.erodible_surfaces)
		var graph: Dictionary = generated_graphs[int(damaged)] if generated_graphs.size() == 2 else G.navigation_graph(graph_terrain)
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

static func _tunnel_support_errors(s: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for tunnel: Dictionary in s.tunnels:
		for i in range(tunnel.pieces.size()):
			var piece: Rect2 = tunnel.pieces[i]
			if tunnel.height < 160 or tunnel.height > 256 or G._embedded(Vector2(piece.get_center().x,piece.end.y-22),T.PLAYER_SIZE,s.solids) or not G._supported(Vector2(piece.get_center().x,piece.end.y-22),T.PLAYER_SIZE,s.solids): errors.append("Tunnel clearance/support")
			if i>0 and absf(piece.end.y-tunnel.pieces[i-1].end.y)>64: errors.append("Tunnel step")
	return errors

static func diagonal_errors(s: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var nodes: Array = s.get("connection_nodes", [])
	for edge: Dictionary in s.get("connections", []):
		if edge.type not in ["shaft", "elbow", "tunnel", "diagonal"]:
			errors.append("Unknown connection type")
			continue
		if edge.type == "elbow" and edge.get("gentle_leg",false):
			errors.append_array(_gentle_leg_errors(s,edge,nodes))
		if edge.type not in ["diagonal", "tunnel"]: continue
		var gentle: bool = edge.type == "tunnel"
		if not edge.has("pieces") or edge.pieces.size() < 2 or edge.a not in range(nodes.size()) or edge.b not in range(nodes.size()):
			errors.append("Diagonal metadata")
			continue
		var first: Rect2 = edge.pieces[0]
		var last: Rect2 = edge.pieces[-1]
		var run := last.end.x - first.position.x
		var rise := last.end.y - first.end.y
		var angle := rad_to_deg(atan2(absf(rise), run))
		if gentle:
			if run > T.GENTLE_LENGTH_MAX or absf(rise) > run * 0.5: errors.append("Gentle angle/length")
		elif run < T.DIAGONAL_LENGTH_MIN or run > T.DIAGONAL_LENGTH_MAX or absf(rise) < T.DIAGONAL_RISE_MIN or angle < T.DIAGONAL_ANGLE_MIN or angle > T.DIAGONAL_ANGLE_MAX: errors.append("Diagonal angle/length")
		if edge.height < (T.GENTLE_HEIGHT_MIN if gentle else T.DIAGONAL_HEIGHT_MIN) or edge.height > (T.GENTLE_HEIGHT_MAX if gentle else T.DIAGONAL_HEIGHT_MAX): errors.append("Diagonal ceiling height")
		var mouth_ok: bool = first.position.x == nodes[edge.a].rect.end.x-32 and last.end.x == nodes[edge.b].rect.position.x+32
		if not mouth_ok or first.end.y != nodes[edge.a].rect.end.y or last.end.y != nodes[edge.b].rect.end.y: errors.append("Diagonal mouths")
		var bounds := first
		var flat := 0.0
		for i in range(edge.pieces.size()):
			var p: Rect2 = edge.pieces[i]
			bounds = bounds.merge(p)
			if p.size.x < (T.GENTLE_TREAD_MIN if gentle else T.DIAGONAL_TREAD_MIN) or (not gentle and p.size.x > T.DIAGONAL_TREAD_MAX) or p.size.y != edge.height: errors.append("Diagonal tread/clearance")
			for v: float in [p.position.x, p.position.y, p.size.x, p.size.y]:
				if fmod(v, 32) != 0: errors.append("Diagonal grid")
			flat = flat + p.size.x if i > 0 and p.end.y == edge.pieces[i-1].end.y else p.size.x
			if not gentle and flat > T.DIAGONAL_LANDING_MAX: errors.append("Diagonal landing length")
			if i > 0:
				var previous: Rect2 = edge.pieces[i-1]
				var delta := p.end.y - previous.end.y
				if p.position.x != previous.end.x or absf(delta) > (T.GENTLE_STEP_MAX if gentle else T.DIAGONAL_STEP_MAX) or delta * rise < 0: errors.append("Diagonal step/continuity")
			if not s.bounds.encloses(p) or G._any_thick_intersects(s.solids, p.grow(-0.1)): errors.append("Diagonal carved clearance")
			if not G._any_encloses(s.protected_rects, p.grow(96)): errors.append("Diagonal protection")
			if nodes.any(func(n): return n.id not in [edge.a, edge.b] and p.grow(T.CAVE_ROCK_GAP - 0.1 if gentle else 32).intersects(n.rect)): errors.append("Diagonal crosses chamber")
		if bounds != edge.rect or not s.tunnels.any(func(t): return t.pieces == edge.pieces and t.height == edge.height): errors.append("Diagonal terrain metadata")
		if not _compatible(edge, s.connections.filter(func(other): return other != edge), nodes): errors.append("Diagonal crosses connection")
	return errors

static func _gentle_leg_errors(s: Dictionary, edge: Dictionary, nodes: Array) -> Array[String]:
	var errors: Array[String] = []
	if edge.a==edge.b or edge.a not in range(nodes.size()) or edge.b not in range(nodes.size()) or edge.get("pieces",[]).size()<2 or not edge.has("shaft"): return ["Gentle elbow metadata"]
	var shaft: Rect2 = edge.shaft
	var u: Rect2 = nodes[edge.a].rect
	var l: Rect2 = nodes[edge.b].rect
	var other: Rect2
	var floor_y: float
	if shaft.position.y==u.end.y and shaft.end.y<l.end.y:
		other=l
		floor_y=shaft.end.y
	elif shaft.end.y==l.end.y and shaft.position.y>u.end.y:
		other=u
		floor_y=shaft.position.y
	else: return ["Gentle elbow shaft endpoints"]
	var first: Rect2 = edge.pieces[0]
	var last: Rect2 = edge.pieces[-1]
	if other.end.x<=shaft.position.x:
		if first.position.x!=other.end.x-32 or first.end.y!=other.end.y or last.end.x!=shaft.end.x or last.end.y!=floor_y: errors.append("Gentle elbow mouths")
	elif other.position.x>=shaft.end.x:
		if first.position.x!=shaft.position.x or first.end.y!=floor_y or last.end.x!=other.position.x+32 or last.end.y!=other.end.y: errors.append("Gentle elbow mouths")
	else: errors.append("Gentle elbow overlap")
	var rise := last.end.y-first.end.y
	if absf(rise)>(last.end.x-first.position.x)*0.5 or edge.height<T.GENTLE_HEIGHT_MIN or edge.height>T.GENTLE_HEIGHT_MAX: errors.append("Gentle elbow angle/ceiling")
	var bounds := shaft
	for i in range(edge.pieces.size()):
		var p: Rect2 = edge.pieces[i]
		bounds=bounds.merge(p)
		if p.size.x<T.GENTLE_TREAD_MIN or p.size.y!=edge.height: errors.append("Gentle elbow tread")
		for value: float in [p.position.x,p.position.y,p.size.x,p.size.y]:
			if fmod(value,32)!=0: errors.append("Gentle elbow grid")
		if i>0:
			var prev: Rect2 = edge.pieces[i-1]
			if p.position.x!=prev.end.x or absf(p.end.y-prev.end.y)>T.GENTLE_STEP_MAX or (p.end.y-prev.end.y)*rise<0: errors.append("Gentle elbow step")
		if not s.bounds.encloses(p) or G._any_thick_intersects(s.solids, p.grow(-0.1)): errors.append("Gentle elbow clearance")
		if not G._any_encloses(s.protected_rects, p.grow(96)): errors.append("Gentle elbow protection")
		if nodes.any(func(n): return n.id not in [edge.a,edge.b] and p.grow(T.CAVE_ROCK_GAP-0.1).intersects(n.rect)): errors.append("Gentle elbow crosses chamber")
	if bounds!=edge.rect or not s.tunnels.any(func(t): return t.pieces==edge.pieces and t.height==edge.height): errors.append("Gentle elbow terrain metadata")
	if not _compatible(edge,s.connections.filter(func(e): return e!=edge),nodes): errors.append("Gentle elbow crosses connection")
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
