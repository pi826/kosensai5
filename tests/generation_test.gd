extends SceneTree
const Generator := preload("res://scripts/stage_generator.gd")
const T := preload("res://scripts/tuning.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: ", message)

func rejected(stage: Dictionary, reason: String) -> void:
	check(not Generator.validate(stage).is_empty(), reason)

func run() -> void:
	var fallback_count := 0
	var layouts := {}
	var all_kinds := {}
	for seed_value in range(1000):
		var stage := Generator.generate(seed_value)
		var errors := Generator.validate(stage)
		check(errors.is_empty(), "valid seamless world seed %d: %s" % [seed_value, errors])
		check(Generator.signature(stage) == Generator.signature(Generator.generate(seed_value)), "reproducible world seed %d" % seed_value)
		check(not stage.has("rooms") and not stage.has("doors"), "no room graph or door transitions seed %d" % seed_value)
		check(stage.biomes.size() == 3 and stage.landmarks.size() == 3, "three regions and guardians seed %d" % seed_value)
		var ids := {}
		var counts := {}
		for spawn: Dictionary in stage.spawns:
			all_kinds[spawn.kind] = true
			counts[spawn.kind] = int(counts.get(spawn.kind, 0)) + 1
			if spawn.kind == "flyer":
				# Derive the swept body independently from its actual spawn/patrol data.
				var envelope := Rect2(Vector2(spawn.patrol.x - T.ENEMY_SIZE.x / 2, spawn.position.y - T.ENEMY_SIZE.y / 2 - T.FLYER_BOB_AMPLITUDE), Vector2(spawn.patrol.y - spawn.patrol.x + T.ENEMY_SIZE.x, T.ENEMY_SIZE.y + 2 * T.FLYER_BOB_AMPLITUDE)).grow(T.FLYER_CLEARANCE)
				check(stage.solids.all(func(solid): return not envelope.intersects(solid)), "clear flyer lane seed %d" % seed_value)
				check(spawn.position.y == stage.solids[spawn.floor_index].position.y - T.FLYER_ALTITUDE and spawn.patrol == Vector2(spawn.floor_index * Generator.FLOOR_WIDTH + T.FLYER_LANE_MARGIN, (spawn.floor_index + 1) * Generator.FLOOR_WIDTH - T.FLYER_LANE_MARGIN), "flyer altitude and patrol seed %d" % seed_value)
			if spawn.kind == "boss":
				ids[spawn.boss_id] = true
		check(ids.size() == 3, "three unique guardian IDs seed %d" % seed_value)
		check(counts.has("flyer") and counts.has("laser"), "both new enemy roles guaranteed seed %d" % seed_value)
		check(counts.has("breaker") and counts.has("builder"), "terrain enemy roles guaranteed seed %d" % seed_value)
		check(stage.breakables.size() >= 4, "at least four breakables seed %d" % seed_value)
		for block: Rect2 in stage.breakables:
			var fixture := stage.duplicate(false)
			fixture.breakables = stage.breakables.filter(func(other): return other != block)
			check(Generator.block_is_valid(block, fixture), "valid supported breakable seed %d" % seed_value)
		for spawn: Dictionary in stage.spawns:
			if spawn.kind == "flyer":
				var lane := Generator.flight_lane(stage.solids[spawn.floor_index])
				check(stage.solids.all(func(solid): return solid.size.y > 20 or solid.end.x <= lane.position.x or solid.position.x >= lane.end.x or solid.position.y < lane.end.y or solid.position.y - lane.end.y >= T.PLAYER_SIZE.y + 8), "player space below flyer seed %d" % seed_value)
				check(stage.breakables.all(func(block): return not lane.intersects(block)), "no breakable in flyer lane seed %d" % seed_value)
		var highest_y := float(stage.start_position.y)
		for route: Dictionary in stage.routes:
			for point: Vector2 in route.points:
				highest_y = minf(highest_y, point.y)
		check(stage.start_position.y - highest_y >= 1536, "twelve normal-jump levels of vertical exploration seed %d" % seed_value)
		layouts[str(stage.solids)] = true
		fallback_count += int(stage.fallback)
	check(layouts.size() > 990, "seeds vary actual terrain geometry")
	check(all_kinds.size() == 8, "all seven ordinary enemy types and guardian appear")
	check(fallback_count == 0, "ordinary seeds pass without fallback")
	for seed_value in range(10):
		var stage := Generator.generate_fallback(seed_value)
		check(stage.fallback and Generator.validate(stage).is_empty(), "verified continuous fallback seed %d" % seed_value)
		check(Generator.signature(stage) == Generator.signature(Generator.generate_fallback(seed_value)), "deterministic fallback seed %d" % seed_value)
	var broken := Generator.generate(1)
	broken.solids.remove_at(5)
	rejected(broken, "gap in safety floor rejected")
	broken = Generator.generate(1)
	broken.solids.append(Rect2(2000, 1024, 32, 1280))
	rejected(broken, "interior room-like dividing wall rejected")
	broken = Generator.generate(1)
	broken.solids.remove_at(32)
	rejected(broken, "missing outer boundary rejected")
	broken = Generator.generate(1)
	broken.solids.remove_at(34)
	rejected(broken, "missing first climbing shelf rejected")
	broken = Generator.generate(1)
	broken.solids.append(Rect2(3200, 128, 128, 16))
	rejected(broken, "unreachable shelf rejected")
	broken = Generator.generate(1)
	broken.spawns[3].position = broken.start_position
	rejected(broken, "enemy inside safe starting region rejected")
	broken = Generator.generate(1)
	broken.spawns[1].boss_id = 0
	rejected(broken, "duplicate guardian ID rejected")
	broken = Generator.generate(1)
	broken.spawns[0].boss_id = 2
	broken.spawns[2].boss_id = 0
	rejected(broken, "guardians swapped into the wrong regions rejected")
	broken = Generator.generate(1)
	broken.spawns[4].id = broken.spawns[3].id
	rejected(broken, "duplicate ordinary enemy ID rejected")
	broken = Generator.generate(1)
	broken.spawns[3].position.y -= 64
	rejected(broken, "unsupported enemy rejected")
	broken = Generator.generate(1)
	broken.spawns[3].patrol = Vector2(32, 12000)
	rejected(broken, "patrol leaving its supporting ground height rejected")
	broken = Generator.generate(1)
	broken.bounds = Rect2(0, 0, 4096, 3072)
	rejected(broken, "incorrect world bounds rejected")
	broken = Generator.generate(1)
	broken.routes[1].points.remove_at(1)
	rejected(broken, "jump route exceeding single-jump rise rejected")
	broken = Generator.generate(1)
	broken.routes[0].points[-1] = broken.start_position
	rejected(broken, "route missing its actual guardian rejected")
	broken = Generator.generate(1)
	broken.biomes[1].rect = broken.biomes[0].rect
	rejected(broken, "overlapping region extents rejected")
	broken = Generator.generate(1)
	broken.landmarks[0].position += Vector2(32, 0)
	rejected(broken, "landmark inconsistent with actual guardian rejected")
	broken = Generator.generate(1)
	var changed_geometry := broken.duplicate(true)
	changed_geometry.solids.append(Rect2(4096, 1536, 128, 16))
	check(Generator.signature(broken) != Generator.signature(changed_geometry), "signature covers terrain rather than only seed")
	var changed_color := broken.duplicate(true)
	changed_color.spawns[0].polarity = 1 - changed_color.spawns[0].polarity
	check(Generator.signature(broken) != Generator.signature(changed_color), "signature covers enemy colors")
	var changed_position := broken.duplicate(true)
	changed_position.spawns[3].position.x += 32
	check(Generator.signature(broken) != Generator.signature(changed_position), "signature covers enemy positions")
	for missing: String in Generator.REQUIRED_KINDS:
		broken = Generator.generate(1)
		broken.spawns = broken.spawns.filter(func(spawn): return spawn.kind != missing)
		rejected(broken, "missing required role rejected: " + missing)
	broken = Generator.generate(1)
	var flyer: Dictionary = broken.spawns.filter(func(spawn): return spawn.kind == "flyer")[0]
	broken.solids.append(Rect2(flyer.floor_index * Generator.FLOOR_WIDTH + 32, flyer.position.y, 320, 16))
	rejected(broken, "terrain crossing flyer lane rejected")
	broken = Generator.generate(1)
	flyer = broken.spawns.filter(func(spawn): return spawn.kind == "flyer")[0]
	var floor_rect: Rect2 = broken.solids[flyer.floor_index]
	broken.solids.append(Rect2(floor_rect.position.x + 32, floor_rect.position.y - 128, 320, 16))
	rejected(broken, "insufficient player clearance below flyer rejected")
	for invalid in [Rect2(0, 2272, 32, 32), Rect2(2304, 2208, 96, 96), Rect2(2304, 1920, 32, 32)]:
		broken = Generator.generate(1)
		broken.breakables.append(invalid)
		rejected(broken, "invalid protected/oversized/floating block rejected")
	broken = Generator.generate(1)
	var point: Vector2 = broken.routes[0].points[2]
	broken.breakables.append(Rect2(point.x - 32, point.y + T.PLAYER_SIZE.y / 2 - 32, 32, 32))
	rejected(broken, "block covering route waypoint rejected")
	broken = Generator.generate(1)
	broken.surface_exclusions = []
	rejected(broken, "missing protected climb and guardian ranges rejected")
	var altered := Generator.generate(1)
	var sig := Generator.signature(altered)
	altered.breakables.pop_back()
	check(sig != Generator.signature(altered), "signature includes breakables")
	altered = Generator.generate(1)
	sig = Generator.signature(altered)
	altered.surface_exclusions.pop_back()
	check(sig != Generator.signature(altered), "signature includes protection ranges")
	var changed_lane := Generator.generate(1)
	var original_signature := Generator.signature(changed_lane)
	changed_lane.spawns.filter(func(spawn): return spawn.kind == "flyer")[0].patrol.x += 1
	check(original_signature != Generator.signature(changed_lane), "signature covers flight lane")
	for seed_value in [-2147483648, -1, 2147483647, 9223372036854775807]:
		var stage := Generator.generate(seed_value)
		check(Generator.validate(stage).is_empty() and Generator.signature(stage) == Generator.signature(Generator.generate(seed_value)), "signed and large seed %d" % seed_value)
	print("SEAMLESS GENERATION TEST: ", checks, " checks, ", failures.size(), " failures; 1000 seeds, ", layouts.size(), " geometries, fallback=", fallback_count)
	quit(0 if failures.is_empty() else 1)
