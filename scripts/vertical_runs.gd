extends RefCounted
## Shared geometry measurement for generation, validation and before/after QA.
const G := preload("res://scripts/stage_generator.gd")
const MIN_HEIGHT := 128.0
const EXIT_RUN := 256.0

static func _overlap_x(a: Rect2, b: Rect2) -> bool:
	return minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x) >= 54

static func columns(s: Dictionary) -> Array:
	var result: Array = s.shafts.map(func(q): return q.rect)
	# Vestibules continue the column vertically; their 32px lip is not a side exit.
	for i in range(result.size()):
		var c: Rect2 = result[i]
		for entry: Dictionary in s.get("entrances", []):
			var r: Rect2 = entry.rect
			if _overlap_x(c, r) and r.position.y <= c.end.y and r.end.y >= c.position.y:
				c = Rect2(c.position.x, minf(c.position.y, r.position.y), c.size.x, maxf(c.end.y, r.end.y) - minf(c.position.y, r.position.y))
		result[i] = c
	var changed := true
	while changed:
		changed = false
		for i in range(result.size()):
			for j in range(i + 1, result.size()):
				var a: Rect2 = result[i]
				var b: Rect2 = result[j]
				if _overlap_x(a, b) and a.position.y <= b.end.y and b.position.y <= a.end.y:
					result[i] = a.merge(b)
					result.remove_at(j)
					changed = true
					break
			if changed: break
	return result

static func _floor(solids: Array, x: float, y: float, cache: Dictionary) -> bool:
	var key := Vector2(x,y)
	if cache.has(key): return cache[key]
	# Chamber floor steps remain genuine standing floors. Follow their tops;
	# checking only the undecorated room floor would misclassify them as walls.
	for offset: int in [0,32,64,96,128,-32,-64]:
		var floor_y := y - offset
		if not G._supported(Vector2(x, floor_y - 22), Vector2(20,44), solids): continue
		var blocked := false
		var clearance := Rect2(x-10,floor_y-MIN_HEIGHT,20,MIN_HEIGHT).grow(-0.1)
		for rock: Rect2 in solids:
			if rock.size.y != 16 and rock.intersects(clearance):
				blocked = true
				break
		if not blocked:
			cache[key]=true
			return true
	cache[key]=false
	return false

static func _passages(s: Dictionary) -> Dictionary:
	var groups: Array = []
	for room: Dictionary in s.chambers: groups.append({"pieces": [room.rect], "entry": false})
	for tunnel: Dictionary in s.tunnels: groups.append({"pieces": tunnel.pieces, "entry": false})
	for entry: Dictionary in s.get("entrances", []): groups.append({"pieces": [entry.rect], "entry": true})
	var passage_pieces: Array = []
	var entries: Array = []
	for group: Dictionary in groups:
		passage_pieces.append_array(group.pieces)
		for _piece in group.pieces: entries.append(group.entry)
	return {"entries": entries, "pieces": passage_pieces, "at_x": {}, "solids_at_x": {}, "piece_bins": _bins(passage_pieces,0,true), "solid_bins": _bins(s.solids,10)}

static func _bins(rects: Array, margin: float = 0, indices: bool = false) -> Dictionary:
	var bins := {}
	for i in range(rects.size()):
		var r: Rect2 = rects[i]
		for key in range(floori((r.position.x-margin)/64),floori((r.end.x+margin)/64)+1):
			if not bins.has(key): bins[key]=[]
			bins[key].append(i if indices else r)
	return bins

static func mouths(s: Dictionary, c: Rect2, floor_cache: Dictionary, buckets: Dictionary, query_cache: Dictionary, passages: Dictionary = {}) -> Array:
	var result: Array = []
	if passages.is_empty(): passages = _passages(s)
	for direction: int in [-1, 1]:
		var wall: float = c.position.x if direction < 0 else c.end.x
		var far := wall + direction * EXIT_RUN
		var continuations := {}
		for mouth_index: int in passages.piece_bins.get(floori(wall/64),[]):
			var mouth: Rect2 = passages.pieces[mouth_index]
			if mouth.position.x>wall or mouth.end.x<wall: continue
			if mouth.size.y < MIN_HEIGHT: continue
			var cursor := wall
			var previous := mouth
			var connected := true
			while absf(cursor - wall) < EXIT_RUN:
				var x := cursor + direction * 16
				# Keep original piece order: the first supported continuation wins.
				# These exact-x lists are shared by all columns and mouths.
				if not passages.at_x.has(x):
					var at_x: Array = []
					for piece_index: int in passages.piece_bins.get(floori(x/64),[]):
						var p: Rect2 = passages.pieces[piece_index]
						if p.position.x <= x and p.end.x >= x: at_x.append(p)
					passages.at_x[x] = at_x
					var nearby: Array = []
					for rock: Rect2 in passages.solid_bins.get(floori(x/64),[]):
						if rock.position.x >= x+10 or rock.end.x <= x-10: continue
						nearby.append(rock)
					passages.solids_at_x[x] = nearby
				var candidates: Array = passages.at_x[x]
				var index := -1
				for i in range(candidates.size()):
					var candidate: Rect2 = candidates[i]
					if minf(previous.end.y,candidate.end.y)-maxf(previous.position.y,candidate.position.y) >= MIN_HEIGHT and _floor(passages.solids_at_x[x],x,candidate.end.y,floor_cache):
						index = i
						break
				if index < 0: connected = false; break
				var p: Rect2 = candidates[index]
				previous = p
				cursor += direction * 32
			if not connected: continue
			# A wide gate vestibule only counts if its far side continues into
			# another real connection. A blind alcove cannot reset the run.
			if passages.entries[mouth_index]:
				if not continuations.has(previous):
					continuations[previous] = _continues(s, c, previous, far, direction)
				if not continuations[previous]: continue
			var top := maxf(c.position.y, mouth.position.y)
			var bottom := minf(c.end.y, mouth.end.y)
			var intervals: Array[Vector2] = [Vector2(top,bottom)]
			for rock: Rect2 in passages.solid_bins.get(floori(wall/64),[]):
				if rock.size.y == 16 or rock.position.x >= wall+1 or rock.end.x <= wall-1: continue
				intervals = G._subtract(intervals,rock.position.y,rock.end.y)
			for interval: Vector2 in intervals:
				if interval.y-interval.x >= MIN_HEIGHT: result.append(interval)
	result.sort_custom(func(a, b): return a.x < b.x)
	return result

static func _continues(s: Dictionary, c: Rect2, previous: Rect2, far: float, direction: int) -> bool:
	for q: Dictionary in s.shafts:
		var r: Rect2 = q.rect
		if r != c and (r.position.x >= far - 16 if direction > 0 else r.end.x <= far + 16) and r.grow(1).intersects(previous): return true
	for t: Dictionary in s.tunnels:
		for p: Rect2 in t.pieces:
			if (p.end.x >= far if direction > 0 else p.position.x <= far) and p.intersects(previous): return true
	return false

static func measure(s: Dictionary) -> Dictionary:
	var runs: Array = []
	var gate_runs := {Vector2i.UP: [], Vector2i.DOWN: []}
	var details: Array = []
	var floor_cache := {}
	var buckets := {}
	var query_cache := {}
	var passages := _passages(s)
	for c: Rect2 in columns(s):
		var openings := mouths(s, c, floor_cache, buckets, query_cache, passages)
		var cursor := c.position.y
		var local_runs: Array = []
		for opening: Vector2 in openings:
			if opening.x > cursor: local_runs.append(Vector2(cursor, opening.x))
			cursor = maxf(cursor, opening.y)
		if cursor < c.end.y: local_runs.append(Vector2(cursor, c.end.y))
		for run: Vector2 in local_runs: runs.append(run.y - run.x)
		details.append({"column": c, "mouths": openings, "runs": local_runs})
		for side: Vector2i in [Vector2i.UP, Vector2i.DOWN]:
			for gate: Dictionary in s.gates.get(side, []):
				if not _overlap_x(c, Rect2(gate.x, 0, gate.width, s.bounds.size.y)): continue
				if (side.y < 0 and c.position.y != 0) or (side.y > 0 and c.end.y != s.bounds.end.y): continue
				var distance := c.size.y
				if not openings.is_empty(): distance = openings[0].x if side.y < 0 else s.bounds.end.y - openings[-1].y
				gate_runs[side].append({"x": gate.x, "length": distance})
	return {"runs": runs, "gates": gate_runs, "columns": details}

static func errors(s: Dictionary, limit: float) -> Array[String]:
	var result: Array[String] = []
	var m := measure(s)
	for length: float in m.runs:
		if length > limit: result.append("Vertical run exceeds limit: %d" % length)
	for side: Vector2i in m.gates:
		for expected: Dictionary in s.gates.get(side, []):
			if not m.gates[side].any(func(g): return g.x == expected.x): result.append("Missing vertical gate column")
		for gate: Dictionary in m.gates[side]:
			if gate.length > limit / 2: result.append("Vertical gate run exceeds half limit: %d" % gate.length)
	return result
