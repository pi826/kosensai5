extends "res://tests/test_tree.gd"
const S := preload("res://scripts/sector_generator.gd")
const L := preload("res://scripts/loot_generator.gd")
const G := preload("res://scripts/stage_generator.gd")
const T := preload("res://scripts/tuning.gd")
const Physics := preload("res://tests/ability_physics_test.gd")
const Driver := preload("res://tests/ability_driver.gd")
var checks := 0
var failures: Array[String] = []
var branches := {}
var physics_cases: Array = []
var key_count := 0
var chest_count := 0
var generated := 0
var unbiased := {"sectors":0,"keys":0,"chests":0}

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		if failures.size() <= 30: printerr("FAIL: ", message)

func frames() -> void:
	test_progress()
	await physics_frame
	await process_frame

func input(action: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func inspect(s: Dictionary, graphs: bool) -> void:
	generated += 1
	check(S.validate(s).is_empty(), "sector geometry, loot separation and initial main routes seed=%d coord=%s" % [s.seed,s.coord])
	var ability_positions := L.ability_sectors(s.seed)
	for ability: int in ability_positions:
		if s.coord != ability_positions[ability]: continue
		check(s.loot.any(func(item): return item.kind == "chest" and item.contents.any(func(c): return c.kind == "ability" and c.ability == ability)), "correct ability chest exists at assigned sector")
	key_count += s.loot.filter(func(i): return i.kind == "key").size()
	chest_count += s.loot.filter(func(i): return i.kind == "chest" and i.contents[0].kind != "ability").size()
	for branch: Dictionary in s.detours:
		branches[branch.required] = branches.get(branch.required,0) + 1
		if physics_cases.filter(func(c): return c.branch.required == branch.required).size() < 3:
			physics_cases.append({"sector":s,"branch":branch})
		if not graphs: continue
		var stage := s.duplicate(false)
		stage.solids = s.solids + s.breakables
		var base := G.navigation_graph(stage)
		var source := G.node_at(base,s.start_position)
		var target := G.node_at(base,branch.position)
		check(not G._search(base,source).has(target), "detour unreachable without abilities")
		check(G._search(base,source,true).has(target), "detour has initial-ability return route")
		var required := G.navigation_graph(stage,false,{},[],branch.required)
		check(G._search(required,source).has(target) and G._search(required,source,true).has(target), "required ability graph reaches detour both ways")
		var prior := 0 if branch.required == T.ABILITY_DASH else T.ABILITY_DASH
		var previous := G.navigation_graph(stage,false,{},[],prior)
		check(not G._search(previous,source).has(target), "preceding ability combination cannot reach detour")
		check(G.connectivity_errors(stage,false,base).is_empty() and G.connectivity_errors(stage,true).is_empty(), "initial main route stays strongly connected before and after excavation")

func physical_branches() -> void:
	# Each sampled schedule is executed against the generated sector's real
	# collision geometry. These are explicit jump fixtures, separate from the
	# no-teleport start/key/chest/detour/return playthrough in abilities_test.
	for sample: Dictionary in physics_cases:
		var s: Dictionary = sample.sector
		var branch: Dictionary = sample.branch
		var fixture := Physics.Fixture.new()
		root.add_child(fixture)
		for rect: Rect2 in s.solids + s.breakables: Physics.add_fixture(fixture.world,rect,rect.size.y==16)
		fixture.player.position = branch.launch
		fixture.player.abilities = branch.required
		for i in range(4): await frames()
		var profile: Dictionary = branch.profile
		var landed := false
		input("jump",true)
		for frame in range(T.ABILITY_FLIGHT_FRAMES):
			if not profile.glide and frame == ceili(T.JUMP_SPEED/T.GRAVITY*60): input("jump",false)
			if frame == profile.dash:
				if profile.dash_up: input("move_up",true)
				input("dash",true)
			if frame == profile.dash+1:
				input("dash",false)
				input("move_up",false)
			var dx: float = branch.position.x-fixture.player.position.x
			Input.action_release("move_left")
			Input.action_release("move_right")
			if absf(dx)>2: Input.action_press("move_right" if dx>0 else "move_left")
			await frames()
			if frame > 2 and fixture.player.is_on_floor():
				landed = absf(fixture.player.position.y-branch.position.y)<2 and absf(dx)<T.DETOUR_WIDTH/2-16
				break
		check(landed, "real physics lands generated branch seed=%d coord=%s required=%d actual=%s target=%s" % [s.seed,s.coord,branch.required,fixture.player.position,branch.position])
		for action in ["jump","dash","move_up","move_left","move_right"]: input(action,false)
		fixture.free()

func run() -> void:
	for seed_value in range(64):
		test_progress()
		var positions := L.ability_sectors(seed_value)
		check(positions.size()==2 and positions[T.ABILITY_DASH]==Vector2i.ZERO and positions[T.ABILITY_DASH]!=positions[T.ABILITY_GLIDE], "two deterministic distinct ability sectors")
		for ability: int in positions:
			var at: Vector2i = positions[ability]
			var distance := maxi(absi(at.x),absi(at.y))
			var limits: Vector2i = T.ABILITY_SECTOR_DISTANCE[ability]
			check(distance>=limits.x and distance<=limits.y,"ability sector distance")
			var data := S.generate(seed_value,at)
			inspect(data, seed_value<8)
			if seed_value<8: check(S.signature(data)==S.signature(S.generate(seed_value,at)),"seed/coord generation reproducible independent of call order")
		var normal := S.generate(seed_value,Vector2i(5+seed_value%4,-5))
		inspect(normal,seed_value<8)
		if seed_value%8==0: print("ABILITY GENERATION PROGRESS ",seed_value," branches=",branches)
	check(key_count>chest_count,"generated keys slightly outnumber normal chests on average")
	check(branches.has(T.ABILITY_DASH) and branches.has(T.ABILITY_DASH | T.ABILITY_GLIDE),"both kinds of ability detours generated")
	# Count all chests on an unbiased square, including the two ability chests
	# when their assigned sectors fall in it (the earlier sample oversamples them).
	for seed_value in range(8):
		for y in range(-2,3):
			for x in range(-2,3):
				test_progress()
				var s := S.generate(seed_value,Vector2i(x,y))
				unbiased.sectors += 1
				unbiased.keys += s.loot.filter(func(i): return i.kind == "key").size()
				unbiased.chests += s.loot.filter(func(i): return i.kind == "chest").size()
				check(S.validate(s).is_empty(),"unbiased square loot and geometry validation")
	check(unbiased.keys>unbiased.chests and unbiased.keys<unbiased.chests*1.6,"keys slightly outnumber all chests including abilities in unbiased sectors")
	var original := S.generate(37,Vector2i.ZERO)
	var bad := original.duplicate(true)
	bad.loot[0].position = bad.breakables[0].get_center()
	check(not S.validate(bad).is_empty(),"reject loot overlapping a block")
	bad = original.duplicate(true)
	bad.loot = bad.loot.filter(func(i): return i.kind != "chest" or i.contents[0].kind != "ability")
	check(not S.validate(bad).is_empty(),"reject missing assigned ability chest")
	bad = original.duplicate(true)
	bad.loot = bad.loot.filter(func(i): return i.kind != "key")
	check(not S.validate(bad).is_empty(),"reject missing first key")
	await physical_branches()
	DirAccess.make_dir_recursive_absolute("res://builds/qa/abilities")
	FileAccess.open("res://.userdata/codex-delegation/task-20261103-64-generation.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"seeds":64,"sectors":generated,"branches":branches,"keys":key_count,"normal_chests":chest_count,"unbiased":unbiased,"physical_branches":physics_cases.size()},"\t"))
	print("ABILITY GENERATION: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
