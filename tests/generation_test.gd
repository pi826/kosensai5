extends SceneTree
const G := preload("res://scripts/stage_generator.gd")
const T := preload("res://scripts/tuning.gd")
var checks := 0
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)
func rejected(s: Dictionary, message: String): check(not G.validate(s).is_empty(), message)
func run():
	var layouts := {}
	var chamber_counts := {}
	var room_pairs := {}
	var boss_regions := [{},{},{}]
	var enemy_layouts := {}
	var enemy_positions := {}
	var block_positions := {}
	var block_layouts := {}
	var fallback_count := 0
	var samples: Array = []
	var seed_reports := {}
	for value in range(1000):
		var begin := Time.get_ticks_usec()
		var s := G.generate(value)
		samples.append((Time.get_ticks_usec() - begin) / 1000.0)
		check(G.validate(s).is_empty(), "validate seed %d" % value)
		check(G.signature(s) == G.signature(G.generate(value)), "deterministic seed %d" % value)
		check(not s.has("rooms") and not s.has("doors"), "single collision world")
		check(s.chambers.size() >= 14 and s.chambers.size() <= 22, "chamber count")
		check(G.cycle_count(s) >= 3, "independent cycles")
		# Distribution assertions are per-seed unless explicitly aggregated below.
		chamber_counts[s.chambers.size()] = true
		var heights := {}
		var degrees := {}
		var step_rooms := 0
		var rock_rooms := 0
		var normal_rooms := 0
		var shelf_counts := {}
		for room: Dictionary in s.chambers:
			heights[room.rect.end.y] = true
			shelf_counts[room.shelves.size()] = true
			if room.kind != "start":
				var pair := Vector2(room.rect.get_center().x,room.rect.end.y)
				room_pairs[pair] = room_pairs.get(pair,0) + 1
			if room.kind == "boss": boss_regions[room.region][room.band] = true
			if room.kind == "normal":
				normal_rooms += 1
				step_rooms += int(not room.floor_steps.is_empty())
				rock_rooms += int(not room.rocks.is_empty())
		for edge: Dictionary in s.tunnels+s.shafts:
			degrees[edge.a] = degrees.get(edge.a,0)+1
			degrees[edge.b] = degrees.get(edge.b,0)+1
		check(heights.size()>=8,"eight distinct floor heights")
		check(s.tunnels.size()+s.shafts.size()<s.connection_candidates.size(),"unselected candidate connections")
		check(G.cycle_count(s)>=3 and G.cycle_count(s)<=8,"three to eight independent cycles")
		check(degrees.values().any(func(n):return n<=2) and degrees.values().any(func(n):return n>=3),"mixed connection degrees")
		check(step_rooms>=normal_rooms*0.5,"half of ordinary chambers have floor steps")
		check(rock_rooms>=normal_rooms*0.3,"thirty percent of ordinary chambers have rocks")
		check(shelf_counts.size()>1,"varied shelf counts")
		check(s.tunnels.any(func(e):return s.chambers[e.a].rect.end.y!=s.chambers[e.b].rect.end.y),"tunnel between different floor heights")
		var enemies: Array = s.spawns.filter(func(e):return e.kind!="boss").map(func(e):return e.position)
		for point: Vector2 in enemies: enemy_positions[point]=true
		for block: Rect2 in s.breakables: block_positions[block.position]=true
		enemies.sort_custom(func(a,b):return a.x<b.x or (a.x==b.x and a.y<b.y))
		enemy_layouts[str(enemies)] = true
		var block_set: Array = s.breakables.map(func(b):return b.position)
		block_set.sort_custom(func(a,b):return a.x<b.x or (a.x==b.x and a.y<b.y))
		block_layouts[str(block_set)] = true

		var bands := [{}, {}, {}]
		var boss_bands := {}
		for room: Dictionary in s.chambers:
			check(room.rect.size.x >= 640 and room.rect.size.x <= 1536 and room.rect.size.y >= 320 and room.rect.size.y <= 704, "room dimensions")
			bands[room.region][room.band] = true
			if room.kind == "boss": boss_bands[room.band] = true
			if room.kind == "start": check(room.rect.end.y == T.GROUND_Y and room.rect.size.x >= 896 and room.rect.has_point(s.start_position), "start chamber")
		check(bands.all(func(b): return b.size() >= 2) and boss_bands.size() >= 2, "height band distribution")
		var kinds := {}
		var rooms := {}
		var normals := 0
		for enemy: Dictionary in s.spawns:
			if enemy.kind == "boss":
				check(int(enemy.position.x / 4096) == enemy.boss_id, "boss region")
				continue
			normals += 1
			kinds[enemy.kind] = kinds.get(enemy.kind, 0) + 1
			rooms[enemy.chamber_id] = rooms.get(enemy.chamber_id, 0) + 1
			check(s.chambers[enemy.chamber_id].kind == "normal", "no normals in start/boss chambers")
			check(G.has_attack_sight(enemy, s), "attack sight " + enemy.id)
			if enemy.kind == "flyer":
				var lane := G.flight_lane(enemy.support)
				check((s.solids + s.breakables).all(func(r): return not lane.intersects(r)), "actual flyer sweep is clear")
		check(normals >= 36 and normals <= 44 and kinds.size() == 7, "normal count and seven roles")
		var ratio: float = float(kinds.get("breaker", 0) + kinds.get("flyer", 0) + kinds.get("laser", 0)) / normals
		check(ratio >= 0.45 and ratio <= 0.60, 'arc and flight ratio 45..60 percent')
		check(kinds.values().all(func(n):return n<=normals*0.30),'each enemy kind is at most thirty percent')
		check(rooms.values().all(func(n): return n <= 5), "room cap")
		var regions := {}
		for block: Rect2 in s.breakables:
			regions[int(block.get_center().x / 4096)] = true
			var fixture := s.duplicate(false)
			fixture.breakables = s.breakables.filter(func(r): return r != block)
			check(G.block_is_valid(block, fixture), "supported block outside routes and enemies")
		check(s.breakables.size() >= 6 and regions.size() >= 2, "block count and region spread")
		layouts[str(s.solids)] = true
		fallback_count += int(s.fallback)
		if value in [1,37]: seed_reports[value] = {"chambers": s.chambers.size(), "floor_heights": heights.size(), "edges": s.tunnels.size()+s.shafts.size(), "candidates": s.connection_candidates.size(), "cycles": G.cycle_count(s), "kinds": kinds, "arc_ratio": ratio}
		if value % 100 == 0: print("GENERATION PROGRESS ", value)
	check(chamber_counts.size()>=3,'at least three chamber counts across seeds')
	check(room_pairs.values().max()<=10,'no ordinary coordinate pair repeats more than ten seeds')
	check(boss_regions.all(func(b):return b.size()>=2),'each region has bosses in multiple bands across seeds')
	check(enemy_positions.size()>2000 and block_positions.size()>1000,'diverse actual enemy and block coordinates')
	check(enemy_layouts.size()==1000 and block_layouts.size()==1000,'one thousand distinct enemy and block position layouts')
	check(layouts.size() == 1000, "1000 distinct geometries")
	check(fallback_count == 0, "zero ordinary fallback")
	for value in [0,1,37,2026,-1,-2147483648,2147483647,9223372036854775807]:
		var s := G.generate(value)
		check(G.validate(s).is_empty() and G.signature(s) == G.signature(G.generate(value)), "signed/large seed")
		var fallback := G.generate_fallback(value)
		check(G.validate(fallback).is_empty() and G.signature(fallback) == G.signature(G.generate_fallback(value)), "fixed verified fallback")
		if value == 2026:
			var kinds := {}
			for enemy: Dictionary in s.spawns:
				if enemy.kind != "boss": kinds[enemy.kind] = kinds.get(enemy.kind,0)+1
			seed_reports[value] = {"chambers": s.chambers.size(), "floor_heights": distinct_heights(s), "edges": s.tunnels.size()+s.shafts.size(), "candidates": s.connection_candidates.size(), "cycles": G.cycle_count(s), "kinds": kinds, "arc_ratio": float(kinds.breaker+kinds.flyer+kinds.laser)/(s.spawns.size()-3)}
	var s := G.generate(37)
	var dg := G.navigation_graph(s,true)
	for route: Dictionary in s.routes:
		var end: Vector2 = route.points[-1]
		var outward := G.path_steps(dg,G.node_at(dg,s.start_position),G.node_at(dg,end),end)
		var returning := G.path_steps(dg,G.node_at(dg,end),G.node_at(dg,s.start_position),s.start_position)
		check(G.route_is_valid(dg,outward,s.start_position,end) and G.route_is_valid(dg,returning,end,s.start_position),"damaged executable route")
	var broken := s.duplicate(true)
	broken.solids.append(Rect2(32, 256, 512, 16))
	rejected(broken, "unreachable chamber/shelf")
	broken = s.duplicate(true)
	broken.solids.append(Rect2(1504, 2560, 256, 16))
	broken.solids.append(Rect2(1504, 2208, 32, 352))
	rejected(broken, "fall destination without return")
	broken = s.duplicate(true)
	broken.tunnels = []
	rejected(broken, "insufficient cycles")
	broken = s.duplicate(true)
	var enemy: Dictionary = broken.spawns.filter(func(e): return e.kind == "turret")[0]
	broken.chambers[enemy.chamber_id].approaches = [Vector2(32,32)]
	rejected(broken, "no visible approach")
	broken = s.duplicate(true)
	broken.spawns[0].position.x = 9000
	rejected(broken, "boss outside region")
	broken = s.duplicate(true)
	var shelf: Rect2 = broken.solids.filter(func(r): return r.size.y == 16)[0]
	broken.solids.append(Rect2(shelf.position - Vector2(0,32), Vector2(shelf.size.x,32)))
	rejected(broken, "insufficient platform headroom")
	broken = s.duplicate(true)
	broken.spawns[3].position = s.start_position
	broken.spawns[3].chamber_id = 0
	rejected(broken, "ordinary enemy in start chamber")
	broken = s.duplicate(true)
	broken.solids = G.subtract_rects(broken.solids, [Rect2(0,0,32,32)])
	rejected(broken, "missing outer rock")
	for key in ["connection_candidates","solids","protected_rects","erodible_surfaces","breakables","chambers","tunnels","shafts","routes"]:
		broken = s.duplicate(true)
		broken[key].pop_back()
		check(G.signature(s) != G.signature(broken), "signature covers " + key)
	broken = s.duplicate(true)
	broken.spawns[3].polarity = 1 - broken.spawns[3].polarity
	check(G.signature(s) != G.signature(broken), "signature color")
	broken = s.duplicate(true)
	broken.spawns[3].position.x += 32
	check(G.signature(s) != G.signature(broken), "signature position")
	for mutate in ["protection","identity","patrol","landmark","route","region","required_kind","block"]:
		broken=s.duplicate(true)
		match mutate:
			"protection": broken.protected_rects=[]
			"identity": broken.spawns[4].id=broken.spawns[3].id
			"patrol": broken.spawns[3].patrol=Vector2(32,12000)
			"landmark": broken.landmarks[0].position.x+=32
			"route": broken.routes[0].outward=[]
			"region": broken.biomes[1].rect=broken.biomes[0].rect
			"required_kind": broken.spawns=broken.spawns.filter(func(e): return e.kind!="builder")
			"block": broken.breakables.append(Rect2(6144,2272,96,96))
		rejected(broken,"invalid "+mutate)
	# Cover both movement types explicitly, regardless of the first ordinary spawn's kind.
	for kind in ["flyer","walker"]:
		broken = s.duplicate(true)
		var patroller: Dictionary = broken.spawns.filter(func(e):return e.kind==kind)[0]
		patroller.patrol = Vector2(32,12000)
		rejected(broken,"invalid explicit " + kind + " patrol")
	var total := 0.0
	for sample: float in samples: total += sample
	var report := {"checks": checks,"failures": failures,"seeds":1000,"geometries": layouts.size(),"fallback":fallback_count,"generation_mean_ms":total/1000,"generation_max_ms":samples.max(),"seed_reports":seed_reports,"chamber_counts":chamber_counts.keys(),"max_coordinate_repetitions":room_pairs.values().max(),"enemy_layouts":enemy_layouts.size(),"enemy_positions":enemy_positions.size(),"block_positions":block_positions.size(),"block_layouts":block_layouts.size(),"boss_region_bands":boss_regions}
	FileAccess.open("res://builds/qa/caves/generation_results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("CAVE GENERATION: ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func distinct_heights(s: Dictionary) -> int:
	var heights := {}
	for room: Dictionary in s.chambers: heights[room.rect.end.y]=true
	return heights.size()
