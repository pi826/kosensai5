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
		for spawn: Dictionary in stage.spawns:
			all_kinds[spawn.kind] = true
			if spawn.kind == "boss":
				ids[spawn.boss_id] = true
		check(ids.size() == 3, "three unique guardian IDs seed %d" % seed_value)
		var highest_y := float(stage.start_position.y)
		for route: Dictionary in stage.routes:
			for point: Vector2 in route.points:
				highest_y = minf(highest_y, point.y)
		check(stage.start_position.y - highest_y >= 1536, "twelve normal-jump levels of vertical exploration seed %d" % seed_value)
		layouts[str(stage.solids)] = true
		fallback_count += int(stage.fallback)
	check(layouts.size() > 990, "seeds vary actual terrain geometry")
	check(all_kinds.size() == 4, "all three ordinary enemy types and guardian appear")
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
	for seed_value in [-2147483648, -1, 2147483647, 9223372036854775807]:
		var stage := Generator.generate(seed_value)
		check(Generator.validate(stage).is_empty() and Generator.signature(stage) == Generator.signature(Generator.generate(seed_value)), "signed and large seed %d" % seed_value)
	print("SEAMLESS GENERATION TEST: ", checks, " checks, ", failures.size(), " failures; 1000 seeds, ", layouts.size(), " geometries, fallback=", fallback_count)
	quit(0 if failures.is_empty() else 1)
