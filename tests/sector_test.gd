extends SceneTree
const S := preload("res://scripts/sector_generator.gd")
const G := preload("res://scripts/stage_generator.gd")
const T := preload("res://scripts/tuning.gd")
const Terrain := preload("res://scripts/world_terrain.gd")
var checks := 0
var failures: Array[String] = []
var timings: Array = []
var fallback_count := 0
var seed_first := 0
var seed_count := 200
var merge_batches := false
var stats := {"chambers": {}, "heights": {}, "enemies": {}, "blocks": {}, "hearts": {}, "kinds": {}, "regions": {}, "same_region": 0, "adjacent": 0, "generated": 0, "forced_fallbacks": 0}
var diversity := {"room_pairs": {}, "shaft_x": {}, "horizontal_floors": {}, "vertical_x": {}, "horizontal_count": {}, "vertical_count": {}, "gate_heights": {}, "connections": {}, "cycles": {}, "steps": {}, "protrusions": {}, "stalactites": {}, "shelves": {}, "enemies": {}, "blocks": {}}

func _initialize():
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--seed-first="): seed_first = arg.get_slice("=", 1).to_int()
		elif arg.begins_with("--seed-count="): seed_count = arg.get_slice("=", 1).to_int()
		elif arg == "--merge-batches": merge_batches = true
	call_deferred("run_merge" if merge_batches else "run")
func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures.append(message)
		if failures.size() <= 30: printerr("FAIL: ", message)

func histogram(field: String, value: int): stats[field][value] = stats[field].get(value, 0) + 1

func distinct(field: String, value): diversity[field][str(value)] = true

func record_diversity(s: Dictionary):
	var pairs := {}
	for room: Dictionary in s.chambers:
		pairs[str(Vector2(room.rect.position.x, room.rect.end.y))] = true
		for step: Rect2 in room.floor_steps: distinct("steps", step.position)
		for rock: Rect2 in room.rocks: distinct("stalactites" if rock.position.y == room.rect.position.y else "protrusions", rock.position)
		for shelf: Rect2 in room.shelves: distinct("shelves", shelf.position)
	for pair: String in pairs: diversity.room_pairs[pair] = diversity.room_pairs.get(pair, 0) + 1
	for shaft: Dictionary in s.shafts: distinct("shaft_x", shaft.rect.position.x)
	for side: Vector2i in S.SIDES:
		distinct("horizontal_count" if side.x != 0 else "vertical_count", s.gates[side].size())
		for gate: Dictionary in s.gates[side]:
			distinct("horizontal_floors" if side.x != 0 else "vertical_x", gate.floor if side.x != 0 else gate.x)
			if side.x != 0: distinct("gate_heights", gate.height)
	distinct("connections", s.connections.size())
	distinct("cycles", s.cycles)
	for e: Dictionary in s.spawns:
		if e.kind != "boss": distinct("enemies", e.position)
	for block: Rect2 in s.breakables: distinct("blocks", block.position)
	if not s.fallback:
		check(s.connections.size() - s.connection_nodes.size() + 1 == s.cycles and s.cycles in range(4), "tree plus 0..3 independent cycles")
		var reached := {0: true}
		for iteration in range(s.connection_nodes.size()):
			for edge: Dictionary in s.connections:
				if reached.has(edge.a) or reached.has(edge.b):
					reached[edge.a] = true
					reached[edge.b] = true
		check(reached.size() == s.connection_nodes.size(), "tree connects every mouth and chamber")

func measured(seed_value: int, at: Vector2i) -> Dictionary:
	var begin := Time.get_ticks_usec()
	var s := S.generate(seed_value, at)
	check(S.heart_errors(s).is_empty(), "heart sites exclude rock blocks and enemy patrol/flight areas")
	timings.append((Time.get_ticks_usec() - begin) / 1000.0)
	fallback_count += int(s.fallback)
	stats.generated += 1
	histogram("chambers", s.chambers.size())
	var heights := {}
	for room: Dictionary in s.chambers: heights[room.rect.end.y] = true
	histogram("heights", heights.size())
	check(heights.size() >= 4, "at least four chamber floor levels: seed=%d coord=%s fallback=%s" % [seed_value, at, s.fallback])
	record_diversity(s)
	histogram("blocks", s.breakables.size())
	histogram("hearts", s.hearts.size())
	var normals := 0
	for e: Dictionary in s.spawns:
		if e.kind == "boss": continue
		normals += 1
		stats.kinds[e.kind] = stats.kinds.get(e.kind, 0) + 1
	histogram("enemies", normals)
	stats.regions[s.region] = true
	return s

func verify_graph(sectors: Array, label: String):
	var union := S.combined_stage(sectors)
	for damaged: bool in [false, true]:
		var graph := S.navigation_graph(sectors, damaged)
		var errors := G.connectivity_errors(union, damaged, graph)
		check(errors.is_empty(), "%s graph damaged=%s: %s" % [label, damaged, errors.slice(0, 2)])
		for s: Dictionary in sectors:
			for p: Vector2 in S.gate_positions(s): check(G.node_at(graph, p + Vector2(s.coord) * T.SECTOR_SIZE) >= 0, label + " gate in union")

func run():
	if seed_first < 0 or seed_count <= 0 or seed_first + seed_count > 200:
		printerr("Invalid sector test seed range")
		quit(1)
		return
	for seed_value in range(seed_first, seed_first + seed_count):
		var sectors := {}
		var signatures := {}
		for y in range(-2, 3):
			for x in range(-2, 3):
				var at := Vector2i(x, y)
				var s := measured(seed_value, at)
				var errors := S.validate(s)
				check(errors.is_empty(), "%d %s validate %s" % [seed_value, at, errors.slice(0, 3)])
				sectors[at] = s
				signatures[at] = S.signature(s)
		# Revisit all cells in reverse order after unrelated far-away generation.
		var far := measured(seed_value, Vector2i(1000, -1000))
		check(S.validate(far).is_empty(), "far signed coordinate")
		var reverse_order: Array = sectors.keys()
		reverse_order.reverse()
		for at: Vector2i in reverse_order: check(signatures[at] == S.signature(S.generate(seed_value, at)), "order-independent %d %s" % [seed_value, at])
		for at: Vector2i in sectors:
			for side: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
				if not sectors.has(at + side): continue
				var a: Dictionary = sectors[at]
				var b: Dictionary = sectors[at + side]
				var errors := S.seam_errors(a, b)
				check(errors.is_empty(), "%d seam %s %s %s" % [seed_value, at, side, errors.slice(0, 2)])
				stats.adjacent += 1
				stats.same_region += int(a.region == b.region)
		var square: Array = []
		for y in range(-1, 2):
			for x in range(-1, 2): square.append(sectors[Vector2i(x, y)])
		verify_graph(square, "3x3 seed %d" % seed_value)
		var guardians := S.guardian_sectors(seed_value)
		check(guardians.size() == 3, "three guardian sectors")
		var regions := {}
		var route_sectors := {Vector2i.ZERO: sectors[Vector2i.ZERO]}
		for at: Vector2i in guardians:
			check(absi(at.x) + absi(at.y) >= 2 and absi(at.x) + absi(at.y) <= 4, "guardian Manhattan distance 2..4")
			regions[S.region_at(seed_value, at)] = true
			for other: Vector2i in guardians:
				if other != at: check(Vector2(at).normalized().dot(Vector2(other).normalized()) <= 0.50001, "guardian separation >=60 degrees")
			var current := Vector2i.ZERO
			# Include precisely a connected set of sectors along ordinary lattice walks.
			while current != at:
				if current.x != at.x: current.x += signi(at.x - current.x)
				else: current.y += signi(at.y - current.y)
				if not route_sectors.has(current): route_sectors[current] = sectors[current] if sectors.has(current) else measured(seed_value, current)
			var forced := S.generate_fallback(seed_value, at)
			stats.forced_fallbacks += 1
			check(S.validate(forced).is_empty(), "guardian deterministic fallback")
		check(regions.size() == 3, "guardians occupy distinct regions")
		var route_set: Array = route_sectors.values()
		for damaged: bool in [false, true]:
			var graph := S.navigation_graph(route_set, damaged)
			var routes := S.guardian_routes(route_set, damaged, graph)
			check(routes.size() == 3, "all guardian routes")
			for route: Dictionary in routes:
				check(not route.outward.is_empty() and G.route_is_valid(graph, route.outward, route.start, route.end), "guardian outward executable steps")
				check(not route.returning.is_empty() and G.route_is_valid(graph, route.returning, route.end, route.start), "guardian returning executable steps")
		var fallback := S.generate(seed_value, Vector2i.ZERO, 0)
		stats.forced_fallbacks += 1
		check(S.validate(fallback).is_empty(), "start deterministic fallback")
		check(S.signature(fallback) == S.signature(S.generate_fallback(seed_value, Vector2i.ZERO)), "fallback reproducibility")
		check(S.seam_errors(fallback, sectors[Vector2i.RIGHT]).is_empty(), "fallback to ordinary seam")
		if seed_value % 5 == 0: print("SECTOR PROGRESS ", seed_value, " failures=", failures.size())
		if failures.size() > 30:
			printerr("SECTOR TEST aborted after ", checks, " checks, ", failures.size(), " failures")
			quit(1)
			return
	for seed_value: int in [-1, -2147483648, 2147483647, 9223372036854775807]:
		var s := S.generate(seed_value, Vector2i(-1000, 1000))
		check(S.validate(s).is_empty(), "signed/extreme seed")
		check(S.signature(s) == S.signature(S.generate(seed_value, s.coord)), "signed/extreme determinism")
	# Corruption tests verify rejection, not merely agreement with generator metadata.
	var original := S.generate(37, Vector2i.ZERO)
	var bad := original.duplicate(true)
	bad.hearts = [{"id": "invalid", "position": T.SECTOR_START}]
	check(not S.validate(bad).is_empty(), "reject heart in start chamber")
	bad = original.duplicate(true)
	bad.solids.append(Rect2(768, 448, 128, 16))
	check(not S.validate(bad).is_empty(), "reject unreachable platform")
	bad = original.duplicate(true)
	bad.solids.append(Rect2(0, 0, 32, 32))
	bad.gates[Vector2i.RIGHT][0].floor += 32
	check(not S.validate(bad).is_empty(), "reject altered gate")
	check(not S.seam_errors(bad, S.generate(37, Vector2i.RIGHT)).is_empty(), "reject inconsistent shared seam")
	bad = original.duplicate(true)
	bad.solids = bad.solids.filter(func(r): return not r.has_point(Vector2(16,16)))
	check(not S.validate(bad).is_empty(), "reject missing border rock")
	bad = original.duplicate(true)
	bad.erodible_surfaces.append(Rect2(960, 1760, 128, 64))
	check(not S.validate(bad).is_empty(), "reject protected erosion")
	bad = original.duplicate(true)
	bad.spawns[0].position = T.SECTOR_START
	check(not S.validate(bad).is_empty(), "reject unsafe enemy")
	check(stats.regions.size() == 3, "all regions occur")
	check(fallback_count == 0, "zero ordinary fallback")
	var batch := seed_first != 0 or seed_count != 200
	if not batch: verify_diversity()
	write_report("sector_batch_%d_%d.json" % [seed_first, seed_count] if batch else "sector_results.json", not batch)

func write_report(name: String, with_overviews: bool):
	DirAccess.make_dir_recursive_absolute("res://builds/qa/sectors")
	if with_overviews:
		for seed_value: int in [1, 37, 2026]: overview(seed_value)
	var total := 0.0
	for ms: float in timings: total += ms
	var report := {"checks": checks, "failures": failures.size(), "failure_messages": failures, "seed_first": seed_first, "seed_count": seed_count, "fallback_count": fallback_count, "average_ms": total/timings.size(), "max_ms": timings.max(), "samples": timings.size(), "same_region_ratio": float(stats.same_region)/stats.adjacent, "statistics": stats, "diversity_sets": diversity, "timings_ms": timings}
	DirAccess.make_dir_recursive_absolute("res://builds/qa/sectors")
	var file := FileAccess.open("res://builds/qa/sectors/" + name, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	var summary := report.duplicate(false)
	summary.erase("diversity_sets")
	summary.erase("timings_ms")
	print("SECTOR RESULTS ", JSON.stringify(summary))
	print("SECTOR TEST: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)

# Independent processes may test disjoint seed ranges. Merge the raw sets and
# counts, then run the global diversity checks over all 200 seeds, not averages
# of per-batch cardinalities. The default command still runs the entire suite.
func run_merge():
	for first in range(0, 200, 25):
		var path := "res://builds/qa/sectors/sector_batch_%d_25.json" % first
		if not FileAccess.file_exists(path):
			printerr("Missing batch report: ", path)
			quit(1)
			return
		var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		checks += int(report.checks)
		failures.append_array(report.failure_messages)
		check(int(report.seed_first) == first and int(report.seed_count) == 25, "disjoint complete seed batch")
		timings.append_array(report.timings_ms)
		fallback_count += int(report.fallback_count)
		for field: String in ["chambers", "heights", "enemies", "blocks", "hearts", "kinds"]:
			for value: String in report.statistics[field]: stats[field][value] = stats[field].get(value, 0) + int(report.statistics[field][value])
		for region: String in report.statistics.regions: stats.regions[region] = true
		for field: String in ["same_region", "adjacent", "generated", "forced_fallbacks"]: stats[field] += int(report.statistics[field])
		for field: String in diversity:
			for value: String in report.diversity_sets[field]:
				if field == "room_pairs": diversity[field][value] = diversity[field].get(value, 0) + int(report.diversity_sets[field][value])
				else: diversity[field][value] = true
	check(stats.generated >= 5200 and stats.forced_fallbacks == 800 and stats.adjacent == 8000, "all 200 seeds and fallback/seam cases included")
	check(fallback_count == 0, "zero ordinary fallback in merged suite")
	verify_diversity()
	write_report("sector_results.json", true)
# Same projection as minimap.gd: biome background, actual solid rectangles,
# thin platforms and breakables in theme.edge, discovered bosses and white start.
# CPU Image drawing keeps this QA export reproducible under --headless as well.
func paint_rect(canvas: Image, rect: Rect2, color: Color):
	var pixels := Rect2i(Vector2i(rect.position.floor()), Vector2i(rect.size.ceil()))
	pixels.size.y = maxi(1, pixels.size.y)
	canvas.fill_rect(pixels.intersection(Rect2i(Vector2i.ZERO, canvas.get_size())), color)

func overview(seed_value: int):
	const SCALE := 0.125
	var size := Vector2i(T.SECTOR_SIZE * Vector2(5, 3) * SCALE)
	var canvas := Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
	var background := Color("080e15")
	canvas.fill(background)
	for y in range(-1, 2):
		for x in range(-2, 3):
			var sector := S.generate(seed_value, Vector2i(x, y))
			var offset := Vector2(x + 2, y + 1) * T.SECTOR_SIZE
			var theme: Dictionary = Terrain.THEMES[sector.region]
			var explored: Color = theme.back
			explored.a = 0.85
			paint_rect(canvas, Rect2(offset * SCALE, T.SECTOR_SIZE * SCALE), background.blend(explored))
			for solid: Rect2 in sector.solids + sector.breakables: paint_rect(canvas, Rect2((solid.position + offset) * SCALE, solid.size * SCALE), theme.edge)
			for boss: Dictionary in sector.landmarks:
				var point := Vector2i((boss.position + offset) * SCALE)
				for dy in range(-4, 5):
					for dx in range(-4 + absi(dy), 5 - absi(dy)): canvas.set_pixelv(point + Vector2i(dx, dy), Color("f0d8b2"))
	var start := Vector2i((T.SECTOR_START + T.SECTOR_SIZE * Vector2(2, 1)) * SCALE)
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if dx * dx + dy * dy <= 4: canvas.set_pixelv(start + Vector2i(dx, dy), Color.WHITE)
	var path := "res://builds/qa/sectors/overview_%d.png" % seed_value
	check(canvas.save_png(path) == OK, "overview saved %d" % seed_value)
	var loaded := Image.load_from_file(path)
	check(loaded != null and loaded.get_size() == size, "overview dimensions %d" % seed_value)

func verify_diversity():
	var heart_count := 0
	for count in stats.hearts: heart_count += int(count) * int(stats.hearts[count])
	check(stats.hearts.size() == 3 and float(heart_count) / stats.generated > 0.8 and float(heart_count) / stats.generated < 1.2, "0..2 hearts with average near one per sector")
	check(stats.chambers.size() >= 3, "at least three chamber counts")
	var maximum: int = diversity.room_pairs.values().max()
	check(maximum <= stats.generated * 0.05, "no room x/floor pair in more than 5% of sectors")
	for field: String in ["shaft_x", "horizontal_floors", "vertical_x"]: check(diversity[field].size() >= 20, field + " at least 20 positions")
	for field: String in ["horizontal_count", "vertical_count", "connections", "cycles"]: check(diversity[field].size() >= 2, field + " varies")
	check(diversity.gate_heights.size() == 4, "all four gate heights 160..256")
	for field: String in ["steps", "protrusions", "stalactites", "shelves"]: check(diversity[field].size() >= 100, field + " at least 100 relative positions")
	for field: String in ["enemies", "blocks"]: check(diversity[field].size() >= 1000, field + " at least 1000 relative positions")
	stats.diversity = {}
	for field: String in diversity: stats.diversity[field] = diversity[field].size()
	stats.diversity.max_room_pair_count = maximum
	stats.diversity.max_room_pair_ratio = float(maximum) / stats.generated
	stats.diversity.connections = diversity.connections.keys()
	stats.diversity.cycles = diversity.cycles.keys()
