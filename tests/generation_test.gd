extends SceneTree
const G := preload("res://scripts/stage_generator.gd")
const T := preload("res://scripts/tuning.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL: ", message)
func rejected(stage: Dictionary, reason: String) -> void:
	check(not G.validate(stage).is_empty(), reason)
func run() -> void:
	var fallback_count := 0
	var layouts := {}
	var position_counts: Array = [{},{},{},{},{},{},{},{}]
	var count_sequences := {}
	var enemy_compositions := {}
	var all_kinds := {}
	var triple_worlds := 0
	var minimum_gap := INF
	var maximum_gap := 0.0
	var samples: Array = []
	for seed_value in range(1000):
		var stage := G.generate(seed_value)
		check(G.validate(stage).is_empty(), "valid seed %d" % seed_value)
		check(G.signature(stage) == G.signature(G.generate(seed_value)), "reproducible seed %d" % seed_value)
		check(not stage.has("rooms") and not stage.has("doors"), "no room transitions")
		check(stage.towers.size() >= 8 and stage.towers.size() <= 10, "tower count")
		check(stage.start_position.x == 6144 and stage.bounds.size == Vector2(12288, 3072), "world dimensions and starting X")
		check(G.connectivity_errors(stage).is_empty(), "all required surfaces strongly connected and valley inaccessible")
		check(G.connectivity_errors(stage, true).is_empty(), "fully excavated floor retains round trips")
		var counts := {}
		var bridge_enemies := 0
		var floor_enemies := 0
		for spawn: Dictionary in stage.spawns:
			counts[spawn.kind] = int(counts.get(spawn.kind, 0)) + 1
			all_kinds[spawn.kind] = true
			if spawn.kind != "boss":
				if stage.bridges.any(func(b): return b.rect == spawn.support): bridge_enemies += 1
				if stage.floors.has(spawn.support): floor_enemies += 1
			if spawn.kind == "flyer":
				check(G.lane_is_clear(spawn.support, stage.solids), "clear bridge flight lane")
				check(spawn.position.y == spawn.support.position.y - T.FLYER_ALTITUDE, "flyer altitude")
		for kind in G.NORMAL_KINDS: check(counts.get(kind, 0) >= 1, "each seed has " + kind)
		check(stage.spawns.size() - 3 >= 20 and stage.spawns.size() - 3 <= 30, "normal enemy count")
		check(bridge_enemies >= ceili((stage.spawns.size() - 3) * 0.3), "at least 30 percent of normal enemies on bridges")
		check(floor_enemies <= floori((stage.spawns.size() - 3) * 0.2), "at most 20 percent of normal enemies on tower bottoms")
		var composition: Array = []
		for kind in G.NORMAL_KINDS: composition.append(counts.get(kind,0))
		enemy_compositions[str(composition)] = true
		check(stage.breakables.size() >= 4, "four or more blocks")
		var block_regions := {}
		for block: Rect2 in stage.breakables:
			check(G.doorway_clearance(stage, block), "blocks clear all doorways")
			block_regions[int(block.get_center().x / 4096)] = true
		check(block_regions.size() >= 2, "blocks span at least two regions")
		var heights := {}
		var bridge_counts := {}
		var previous: Array = []
		var sequence: Array = []
		for id in range(stage.towers.size() - 1):
			var links: Array = stage.bridges.filter(func(b): return b.left_tower == id)
			position_counts[id][links.size()] = true
			sequence.append(links.size())
			bridge_counts[links.size()] = true
			check(links.size() >= 1 and links.size() <= 3, "each adjacent pair connected")
			var ys: Array = []
			for bridge: Dictionary in links:
				ys.append(bridge.rect.position.y)
				heights[bridge.rect.position.y] = true
				check(stage.solids.has(bridge.rect), "bridge collision exists")
				check(bridge.rect.size.x >= 256 and bridge.rect.size.x <= 1024, "bridge length")
				minimum_gap = minf(minimum_gap,bridge.rect.size.x)
				maximum_gap = maxf(maximum_gap,bridge.rect.size.x)
				for tid in [bridge.left_tower, bridge.right_tower]: check(stage.towers[tid].entrances.any(func(d): return d.bridge_id == bridge.id), "bridge endpoint opening")
			ys.sort()
			check(ys != previous, "adjacent bridge height sets differ")
			previous = ys
		check(heights.size() >= 4 and bridge_counts.has(1) and bridge_counts.size() >= 2, "nonuniform bridge heights and counts")
		count_sequences[str(sequence)] = true
		if bridge_counts.has(3): triple_worlds += 1
		if seed_value in [1,37]: samples.append({"seed":seed_value,"bridges":sequence,"enemies":counts,"bridge_enemies":bridge_enemies,"floor_enemies":floor_enemies})
		var level_sequences := {}
		var prior_levels: Array = []
		for tower: Dictionary in stage.towers:
			check(tower.outer.size.x >= 512 and tower.outer.size.x <= 832 and tower.interior.size.x == tower.outer.size.x - 128, "tower dimensions")
			check(tower.roof_y >= 640 and tower.roof_y <= 1664 and tower.roof.size.x <= tower.interior.size.x - 96, "roof height and descent hatch")
			for door: Dictionary in tower.entrances: check(door.rect.size == Vector2(64,128) and door.landing.position.y == door.y and door.landing.size.x >= 160, "level entrance landing")
			var levels: Array = []
			var widths := {}
			for platform: Rect2 in tower.platforms:
				levels.append(T.GROUND_Y - platform.position.y)
				widths[platform.size.x] = true
				check(platform.size.x >= 160 and platform.size.x <= tower.interior.size.x - 96, "platform width range")
			check(levels[0] == 96, "first platform 96 pixels above bottom")
			check(widths.size() >= 2,"platform widths vary within every tower")
			check(levels != prior_levels, "adjacent tower height sequences differ")
			prior_levels = levels
			level_sequences[str(levels)] = true
			var walls: Array = stage.inner_walls.filter(func(w): return tower.interior.encloses(w))
			check(walls.any(func(w): return w.size.x >= 96 and w.size.x <= 224 and w.size.y >= 32 and w.size.y <= 64 and (w.position.x == tower.interior.position.x or w.end.x == tower.interior.end.x)), "overhanging inner ledge per tower")
			check(walls.any(func(w): return w.size.x >= 32 and w.size.x <= 64 and w.size.y >= 96 and w.size.y <= 256), "vertical inner wall dimensions per tower")
		check(level_sequences.size() >= 7, "seven distinct tower height sequences per world")
		for boss: Dictionary in stage.spawns.filter(func(s): return s.kind == "boss"):
			var tower: Dictionary = stage.towers[boss.tower_id]
			check(stage.towers.all(func(t): return t.region != tower.region or t.id == tower.id or t.roof_y > tower.roof_y), "guardian on unique highest tower")
		for route: Dictionary in stage.routes: check(not route.outward.is_empty() and not route["return"].is_empty(), "explicit outbound and return actions")
		fallback_count += int(stage.fallback)
		layouts[str(stage.solids)] = true
		if (seed_value + 1) % 100 == 0: print("GENERATION PROGRESS: ",seed_value + 1," / 1000")
	check(fallback_count == 0, "zero fallback for 1000 seeds")
	check(layouts.size() == 1000, "1000 distinct geometries")
	for id in range(8):
		for count in [1,2,3]: check(position_counts[id].has(count), "bridge count %d appears at gap %d" % [count,id])
	check(triple_worlds >= 200, "at least 20 percent of worlds have triple bridges")
	check(count_sequences.size() >= 100, "at least 100 bridge count sequences")
	check(enemy_compositions.size() >= 100, "at least 100 enemy compositions")
	check(minimum_gap <= 384 and maximum_gap >= 960, "wide bridge length distribution")
	for kind in G.NORMAL_KINDS + ["boss"]: check(all_kinds.has(kind), "all-seed kind coverage " + kind)
	var base := G.generate(37)
	var broken: Dictionary
	broken = base.duplicate(true)
	broken.towers[0].entrances.clear()
	rejected(broken, "bridge without opening")
	broken = base.duplicate(true)
	broken.bridges = broken.bridges.filter(func(b): return b.left_tower != 0)
	rejected(broken, "unbridged adjacent pair")
	broken = base.duplicate(true)
	broken.towers[0].entrances.append({"bridge_id": -1,"side":"left","y":2048,"rect":Rect2(0,1920,64,128),"landing":Rect2(64,2048,160,16)})
	rejected(broken, "unbridged wall opening")
	broken = base.duplicate(true)
	broken.solids.append(Rect2(256, 128, 160, 16))
	rejected(broken, "unreachable platform")
	broken = base.duplicate(true)
	var t: Dictionary = broken.towers[0]
	broken.solids.append(Rect2(t.interior.position.x, t.roof_y + 64, t.interior.size.x, 32))
	rejected(broken, "tower blocks descent")
	broken = base.duplicate(true)
	var boss: Dictionary = broken.spawns.filter(func(s): return s.kind == "boss")[0]
	boss.position.y += 32
	rejected(broken, "guardian not on highest roof")
	broken = base.duplicate(true)
	for bridge: Dictionary in broken.bridges: bridge.rect.position.y = 2016
	rejected(broken, "identical bridge heights")
	broken = base.duplicate(true)
	var gap: Rect2 = broken.bridges[0].rect
	broken.solids.erase(gap)
	rejected(broken, "bridge gap opens a drop to valley")
	broken = base.duplicate(true)
	broken.spawns = broken.spawns.filter(func(s): return s.kind != "turret")
	rejected(broken, "every one of seven kinds is required")
	broken = base.duplicate(true)
	broken.breakables.append(Rect2(1024,128,64,64))
	rejected(broken, "unsupported block")
	broken = base.duplicate(true)
	broken.breakables.append(Rect2(base.start_position.x,2304-32,96,32))
	rejected(broken, "oversize protected block")
	broken = base.duplicate(true)
	broken.spawns.filter(func(s): return s.kind == "flyer")[0].position.y += 32
	rejected(broken, "incorrect flyer altitude")
	for seed_value in [1,37,2026]:
		var fixed := G.generate_fallback(seed_value)
		check(G.validate(fixed).is_empty(), "fixed fallback validates")
		check(G.signature(fixed) == G.signature(G.generate_fallback(seed_value)), "fallback reproducibility")
	for seed_value in [-1,-2026,-9223372036854775807,9223372036854775807,4294967296,2026]:
		var unusual := G.generate(seed_value)
		check(G.validate(unusual).is_empty(), "unusual seed validates: %d" % seed_value)
		check(G.signature(unusual) == G.signature(G.generate(seed_value)), "unusual seed reproduces: %d" % seed_value)
		if seed_value == 2026:
			var counts := {}
			var sequence: Array = []
			var bridge_enemies := 0
			var floor_enemies := 0
			for spawn: Dictionary in unusual.spawns:
				counts[spawn.kind] = int(counts.get(spawn.kind,0)) + 1
				if spawn.kind != "boss" and unusual.bridges.any(func(b): return b.rect == spawn.support): bridge_enemies += 1
				if spawn.kind != "boss" and unusual.floors.has(spawn.support): floor_enemies += 1
			for id in range(8): sequence.append(unusual.bridges.filter(func(b): return b.left_tower == id).size())
			samples.append({"seed":seed_value,"bridges":sequence,"enemies":counts,"bridge_enemies":bridge_enemies,"floor_enemies":floor_enemies})
	for change in ["terrain","color","position","block"]:
		broken = base.duplicate(true)
		match change:
			"terrain": broken.solids[0].position.y += 32
			"color": broken.spawns[0].polarity = 1 - broken.spawns[0].polarity
			"position": broken.spawns[0].position.x += 32
			"block": broken.breakables[0].position.x += 32
		check(G.signature(base) != G.signature(broken), "signature distinguishes " + change)
	var fixed_a := G.generate_fallback(1)
	var fixed_b := G.generate_fallback(2026)
	check(fixed_a.solids == fixed_b.solids and fixed_a.spawns == fixed_b.spawns, "fallback geometry/population independent of seed")
	var stats := {"seeds":1000,"fallbacks":fallback_count,"triple_worlds":triple_worlds,"bridge_count_sequences":count_sequences.size(),"enemy_compositions":enemy_compositions.size(),"minimum_gap":minimum_gap,"maximum_gap":maximum_gap,"position_counts":position_counts,"samples":samples,"checks":checks,"failures":failures.size()}
	DirAccess.make_dir_recursive_absolute("res://builds/qa/towers")
	FileAccess.open("res://builds/qa/towers/generation_stats.json",FileAccess.WRITE).store_string(JSON.stringify(stats,"\t"))
	print("GENERATION STATISTICS: ",JSON.stringify(stats))
	print("TOWER GENERATION TEST: %d checks, %d failures; 1000 seeds, %d geometries, fallback=%d" % [checks,failures.size(),layouts.size(),fallback_count])
	quit(0 if failures.is_empty() else 1)
