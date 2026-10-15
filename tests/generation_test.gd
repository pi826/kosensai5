extends SceneTree
const Generator := preload("res://scripts/stage_generator.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: ", message)

func run() -> void:
	var fallback_count := 0
	var layouts := {}
	var all_kinds := {}
	for seed_value in range(1000):
		var stage := Generator.generate(seed_value)
		var errors := Generator.validate(stage)
		check(errors.is_empty(), "valid room graph seed %d: %s" % [seed_value, errors])
		check(Generator.signature(stage) == Generator.signature(Generator.generate(seed_value)), "reproducible seed %d" % seed_value)
		check(stage.rooms.size() == 13, "three four-room regions plus hub seed %d" % seed_value)
		var vertical_links := 0
		var bosses := {}
		var grids := PackedStringArray()
		for room: Dictionary in stage.rooms:
			grids.append(str(room.grid))
			for door: Dictionary in room.doors:
				if door.direction == "north":
					vertical_links += 1
			for spawn: Dictionary in room.spawns:
				all_kinds[spawn.kind] = true
				if spawn.kind == "boss":
					bosses[spawn.boss_id] = room.id
		check(vertical_links >= 2, "multiple vertical connections seed %d" % seed_value)
		check(bosses.size() == 3, "three distinct miniboss rooms seed %d" % seed_value)
		layouts[";".join(grids)] = true
		if stage.fallback:
			fallback_count += 1
	check(layouts.size() > 100, "seeds vary room graph layouts")
	check(all_kinds.size() == 4, "all existing enemy kinds appear")
	check(fallback_count == 0, "ordinary seeds do not need fallback")
	for count in [2, 3, 5, 6, 8]:
		var stage := Generator.generate(321, count)
		check(stage.rooms.size() == count * 3 + 1 and Generator.validate(stage).is_empty(), "configurable room count %d" % count)
	for seed_value in range(10):
		var stage := Generator.generate_fallback(seed_value)
		check(stage.fallback and Generator.validate(stage).is_empty(), "verified fallback seed %d" % seed_value)
		check(Generator.signature(stage) == Generator.signature(Generator.generate_fallback(seed_value)), "deterministic fallback seed %d" % seed_value)
	var broken := Generator.generate(1)
	broken.rooms[0].doors[0].target = 12
	check(not Generator.validate(broken).is_empty(), "nonadjacent door rejected")
	broken = Generator.generate(1)
	broken.rooms[1].doors.pop_front()
	check(not Generator.validate(broken).is_empty(), "one-way connection rejected")
	broken = Generator.generate(1)
	broken.rooms[0].solids.pop_front()
	check(not Generator.validate(broken).is_empty(), "missing safety floor rejected")
	broken = Generator.generate(1)
	for i in range(broken.rooms[0].solids.size() - 1, -1, -1):
		if broken.rooms[0].solids[i].size.y <= 20:
			broken.rooms[0].solids.remove_at(i)
	check(not Generator.validate(broken).is_empty(), "unreachable northern entrance rejected")
	broken = Generator.generate(1)
	broken.rooms[1].spawns[0].position = broken.rooms[1].doors[0].arrival
	check(not Generator.validate(broken).is_empty(), "spawn at room arrival rejected")
	broken = Generator.generate(1)
	broken.rooms[4].spawns[0].boss_id = 1
	check(not Generator.validate(broken).is_empty(), "duplicate or misplaced guardian ID rejected")
	broken = Generator.generate(1)
	broken.rooms[2].grid = broken.rooms[1].grid
	check(not Generator.validate(broken).is_empty(), "overlapping rooms rejected")
	broken = Generator.generate(1)
	broken.rooms[1].spawns[0].position.y = 300
	check(not Generator.validate(broken).is_empty(), "unsupported enemy socket rejected")
	broken = Generator.generate(1)
	broken.rooms[2].solids.append(Rect2(640, 160, 32, 480))
	check(not Generator.validate(broken).is_empty(), "floor-blocking wall rejected")
	broken = Generator.generate(1)
	broken.bounds = Rect2(0, 0, 1280, 736)
	check(not Generator.validate(broken).is_empty(), "incorrect world bounds rejected")
	broken = Generator.generate(1)
	broken.rooms[1].spawns[0].id = broken.rooms[2].spawns[0].id
	check(not Generator.validate(broken).is_empty(), "duplicate enemy identity rejected")
	broken = Generator.generate(1)
	broken.rooms[0].solids.append(Rect2(448, 128, 256, 16))
	check(not Generator.validate(broken).is_empty(), "insufficient platform headroom rejected")
	for seed_value in [-2147483648, -1, 2147483647, 9223372036854775807]:
		var stage := Generator.generate(seed_value)
		check(Generator.validate(stage).is_empty() and Generator.signature(stage) == Generator.signature(Generator.generate(seed_value)), "signed and large seed %d" % seed_value)
	print("ROOM GENERATION TEST: ", checks, " checks, ", failures.size(), " failures; 1000 seeds, ", layouts.size(), " layouts, fallback=", fallback_count)
	quit(0 if failures.is_empty() else 1)
