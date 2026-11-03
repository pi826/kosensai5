extends "res://tests/test_tree.gd"
const S = preload("res://scripts/sector_generator.gd")
const G = preload("res://scripts/stage_generator.gd")
const T = preload("res://scripts/tuning.gd")
const Cycle = preload("res://scripts/boss_cycle.gd")
var checks := 0
var failures: Array[String] = []
var times: Array[float] = []
var fallback_count := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: ",message)
func inspect(data: Dictionary, forced: bool = false):
	check(S.validate(data).is_empty(), "arena validates %s %s: %s" % [data.seed,data.coord,S.validate(data)])
	var rooms: Array = data.chambers.filter(func(r): return r.kind == "boss")
	check(rooms.size() == 1,"one arena")
	if rooms.size() != 1: return
	var room: Dictionary = rooms[0]
	var r: Rect2 = room.rect
	var tiers: int = room.arena_tiers
	if data.fallback:
		check(r == T.ARENA_FALLBACK_RECT and tiers == 2,"fallback dimensions and tiers")
	else:
		check(r.size.x >= T.ARENA_WIDTH_MIN and r.size.x <= T.ARENA_WIDTH_MAX and fmod(r.size.x,64) == 0 and r.size.y == 1024 and tiers == 3,"random dimensions and tiers")
	check(not data.has("_arena_failed"),"no internal failure marker")
	for shelf: Rect2 in G.arena_shelves(r,tiers): check(room.shelves.has(shelf) and data.solids.has(shelf),"fixed shelf present")
	check(room.floor_steps.is_empty() and room.rocks.is_empty(),"arena has no steps or rocks")
	var zone := G.arena_zone(r,tiers)
	check(zone == Rect2(r.position.x+32,r.position.y+32,r.size.x-64,r.size.y-32-160),"zone spans ceiling+32 to floor-160")
	check(not (data.solids.filter(func(p): return p.size.y != 16)+data.breakables).any(func(p): return p.intersects(zone)),"zone clear of rocks and breakables")
	check(not data.breakables.any(func(p): return p.intersects(r)),"no arena breakable")
	check(not data.spawns.any(func(e): return e.kind != "boss" and r.has_point(e.position)),"no normal enemy or enhancer")
	for key in ["hearts","loot","merchants","detours"]:
		check(not data.get(key,[]).any(func(item): return r.has_point(item.position)),"no arena "+key)
	var guardian := S.guardian_sectors(data.seed).find(data.coord)
	var bosses: Array = data.spawns.filter(func(e): return e.kind == "boss")
	check(bosses.size() == int(guardian >= 0),"only guardian arena has initial spawn")
	check(data.landmarks.size() == bosses.size(),"only guardian arena has landmark")
	if not bosses.is_empty():
		var point := Vector2(r.get_center().x,r.end.y-T.BOSS_SIZE.y/2)
		check(bosses[0].position == point and data.landmarks[0].position == point,"guardian and landmark on floor centre")
	for role: String in ["guardian","final","secret"]:
		var roam := Cycle.roam_rect(data,zone,role,Vector2(zone.get_center().x,r.end.y-T.ARENA_BOSS_CENTER_HEIGHT),true)
		check(roam.has_area(),role+" roam exists")
		var half := Cycle.size_for(role)/2
		var body := roam.grow_individual(half.x,half.y,half.x,half.y)
		check(zone.encloses(body),"whole roaming body in zone "+role)
		check(roam.position.y >= r.end.y-22-T.CAMERA_VERTICAL_OFFSET-T.VIEW_SIZE.y/2+T.CAMERA_DEAD_ZONE.y+20,"roam visible above floor with camera dead zone "+role)
		check(roam.end.y+half.y <= r.end.y-160,"roam body keeps floor headroom "+role)
		check(not (data.solids.filter(func(p): return p.size.y != 16)+data.breakables).any(func(p): return p.intersects(body)),"roam body clear of rocks and breakables "+role)
	if forced: check(data.fallback and tiers == 2 and room.shelves.size() == 3,"forced fallback two shelf tiers")
func run():
	for seed_value in [1,37,2026,-17]:
		var guardians := S.guardian_sectors(seed_value)
		for at: Vector2i in guardians: check(S.is_arena_sector(seed_value,at,guardians),"guardian is arena")
		for y in range(-1,2):
			for x in range(-1,2): check(S.is_arena_sector(seed_value,Vector2i(x,y),guardians) == guardians.has(Vector2i(x,y)),"start exclusion")
		for by in range(-3,3):
			for bx in range(-3,3):
				var count := 0
				var expected := 0
				var block := Vector2i(bx,by)
				var pick := posmod(S._key(seed_value,block,"arena"),9)
				var picked := block*3+Vector2i(pick%3,pick/3)
				for y in range(3):
					for x in range(3):
						var at := block*3+Vector2i(x,y)
						var want := guardians.has(at) or (maxi(absi(at.x),absi(at.y)) > 1 and at == picked)
						check(S.is_arena_sector(seed_value,at,guardians) == want,"block pick and guardian override")
						check(S.is_arena_sector(seed_value,at,guardians) == S.is_arena_sector(seed_value,at),"deterministic optional guardians")
						count += int(S.is_arena_sector(seed_value,at,guardians))
						expected += int(want)
				check(count == expected,"one seeded pick per block plus explicit guardian overrides")
		var sample: Array[Vector2i] = guardians.duplicate()
		var extras := 0
		for x in range(-9,9):
			for y in range(-9,9):
				var at := Vector2i(x,y)
				if extras < 8 and S.is_arena_sector(seed_value,at,guardians) and not guardians.has(at):
					sample.append(at)
					extras += 1
		for at: Vector2i in sample:
			var start := Time.get_ticks_usec()
			var data := S.generate(seed_value,at)
			times.append((Time.get_ticks_usec()-start)/1000.0)
			fallback_count += int(data.fallback)
			inspect(data)
		for at: Vector2i in [Vector2i.ZERO,Vector2i.ONE,Vector2i(-1,0)]:
			if not S.is_arena_sector(seed_value,at,guardians): check(not S.generate(seed_value,at).chambers.any(func(r): return r.kind == "boss"),"no arena in ordinary sector")
		inspect(S.generate_fallback(seed_value,guardians[0]),true)
		for cycle in range(1,4):
			var types := Cycle.guardian_types(seed_value,cycle)
			check(types == Cycle.guardian_types(seed_value,cycle) and types.size() == 3 and T.GUARDIAN_TYPES.all(func(t): return types.has(t)),"three reproducible guardian types")
		var center := Vector2i(-2,3)
		for role_list in [["guardian","guardian","guardian"],["final"],["secret"]]:
			var roles: Array[String] = []
			roles.assign(role_list)
			var sites := Cycle.select_sites(seed_value,center,2,roles,guardians)
			check(sites.size() == roles.size() and sites == Cycle.select_sites(seed_value,center,2,roles,guardians),"complete reproducible selection")
			var regions := {}
			for site: Dictionary in sites:
				regions[site.region] = true
				var d: Vector2i = site.sector-center
				check(S.is_arena_sector(seed_value,site.sector,guardians) and maxi(absi(d.x),absi(d.y)) in range(2,6) and not guardians.has(site.sector),"arena ring 2..5 and exclusions")
				var half := Cycle.size_for(site.role)/2
				check(site.arena.encloses(site.roam.grow_individual(half.x,half.y,half.x,half.y)),"whole site body inside arena")
			if roles.size() == 3: check(regions.size() == 3 and sites.map(func(s): return s.boss_type) == Cycle.guardian_types(seed_value,2),"distinct regions and typed sites")
		var excluded := guardians.duplicate()
		for y in range(-5,6):
			for x in range(-5,6):
				var at := center+Vector2i(x,y)
				if S.is_arena_sector(seed_value,at,guardians) and not excluded.has(at): excluded.append(at)
		var expanded := Cycle.select_sites(seed_value,center,3,["guardian","guardian","guardian"],excluded)
		check(expanded.size() == 3,"expanded ring supplies all regions")
		for site: Dictionary in expanded:
			var d: Vector2i = site.sector-center
			check(maxi(absi(d.x),absi(d.y)) in range(6,9) and not excluded.has(site.sector),"fallback ring 6..8")
		test_progress()
		await process_frame
	var result := {"checks":checks,"failures":failures,"generated":times.size(),"fallbacks":fallback_count,"mean_ms":times.reduce(func(a,b): return a+b,0.0)/times.size(),"max_ms":times.max()}
	DirAccess.make_dir_recursive_absolute("res://builds/qa/bosses")
	FileAccess.open("res://builds/qa/bosses/arena-results.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("BOSS ARENA ",JSON.stringify(result))
	quit(int(not failures.is_empty()))


