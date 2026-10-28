extends "res://tests/test_tree.gd"
const Main := preload("res://scripts/main.gd")
const Enemy := preload("res://scripts/enemy.gd")
const S := preload("res://scripts/sector_generator.gd")
const P := preload("res://scripts/enemy_population.gd")
const G := preload("res://scripts/stage_generator.gd")
const T := preload("res://scripts/tuning.gd")
var checks := 0
var failures: Array[String] = []
var game: Node2D
var placed := 0
var samples := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: ",message)
func frames(count: int = 1):
	for i in range(count):
		test_progress()
		await physics_frame
		await process_frame
func population():
	for seed_value in range(200):
		test_progress()
		for at: Vector2i in [Vector2i.ZERO, Vector2i(seed_value%9-4, 3), Vector2i(-3,seed_value%9-4)]:
			var data := S.generate(seed_value,at)
			var lanterns: Array = data.spawns.filter(func(e): return e.kind=="enhancer")
			check(lanterns.size() <= 1,"at most one lantern per sector")
			if at == Vector2i.ZERO: check(lanterns.size()==1,"first lantern is in starting sector seed %d" % seed_value)
			else:
				samples += 1
				placed += lanterns.size()
			check(data.spawns.filter(func(e): return e.kind not in ["boss","enhancer"]).size()==14,"fourteen original enemies retained")
			check(S.validate(data).is_empty(),"independent full-sector validation seed %d %s" % [seed_value,at])
			for e: Dictionary in lanterns:
				check(P.enhancer_valid(e,data),"coverage, terrain, bodies, patrols, lanes and collectibles clear")
				check(P.reachable_shot(e,data) and G.has_attack_sight(e,data),"initial-ability reachable standing point has a clear homing shot")
				var near: Array = data.spawns.filter(func(other): return other.kind not in ["boss","enhancer"] and other.position.distance_to(e.position)<=T.ENHANCER_RADIUS)
				check(near.size()>=2,"at least two neighbors in field")
			if seed_value%20==0: check(S.signature(data)==S.signature(S.generate(seed_value,at)),"seed/coordinate reproducible")
		if seed_value%20==0: print("ENHANCER PLACEMENT ",seed_value)
	check(float(placed)/samples>0.5 and float(placed)/samples<0.7,"non-start mean near 0.6: %d/%d" % [placed,samples])
	for seed_value in range(20):
		var data := S.generate_fallback(seed_value,Vector2i.ZERO)
		check(S.validate(data).is_empty() and data.spawns.any(func(e):return e.kind=="enhancer"),"forced fallback keeps accessible first lantern")

func fixture(kind: String, at: Vector2) -> Node2D:
	var e := Enemy.new()
	e.game = game
	e.kind = kind
	e.position = at
	e.patrol = Vector2(at.x-T.ENHANCER_DRIFT,at.x+T.ENHANCER_DRIFT) if kind=="enhancer" else Vector2(at.x,at.x)
	e.spawn_id = "fixture:"+kind
	e.boss_id = 999
	game.world.add_child(e)
	e.set_physics_process(false)
	return e

func physical():
	game = Main.new()
	game.controls_path="res://builds/qa/enemies/enhancer_controls.cfg"
	root.add_child(game)
	game.start_run(37)
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	for e in get_nodes_in_group("enemies"): e.set_physics_process(false)
	var source = get_nodes_in_group("enhancers").filter(func(e):return e.get_parent()==game.world and e.get_meta("sector")==Vector2i.ZERO)[0]
	var start: Vector2 = source.position
	game.camera.position = start
	source.gauge = T.GAUGE_CAPACITY
	source.shot_clock = 0
	source.wake_delay = 0
	source.set_physics_process(true)
	var shot_count: int = game.projectiles.get_child_count()
	var lowest := INF
	var highest := -INF
	var safe := true
	for i in range(360):
		await frames()
		lowest = minf(lowest,source.position.y)
		highest = maxf(highest,source.position.y)
		safe = safe and absf(source.position.x-start.x)<=T.ENHANCER_DRIFT+0.01 and absf(source.position.y-start.y)<=T.ENHANCER_BOB_AMPLITUDE+0.01
		safe = safe and not G._embedded(source.position,source.body_size,game.stream.loaded[Vector2i.ZERO].solids+game.stream.loaded[Vector2i.ZERO].breakables)
	check(safe,"real physics stays in swept volume without embedding for 360 frames")
	check(highest-lowest>T.ENHANCER_BOB_AMPLITUDE,"real physics visibly floats up and down")
	check(game.projectiles.get_child_count()==shot_count and source.action=="idle","full gauge and zero shot timer never fire")
	source.set_physics_process(false)
	var buddy := fixture("turret",source.position+Vector2(100,0))
	var outside := fixture("walker",source.position+Vector2(T.ENHANCER_RADIUS+1,0))
	var boss := fixture("boss",source.position+Vector2(50,0))
	var lantern := fixture("enhancer",source.position)
	check(source.field_active() and buddy.enhanced() and not outside.enhanced(),"only field interior enhanced")
	check(not boss.enhanced() and not lantern.enhanced(),"bosses and other lanterns excluded")
	check(is_equal_approx(buddy._shot_interval(),T.ENEMY_SHOT_INTERVAL*T.ENHANCER_INTERVAL_RATIO),"attack interval times 0.6")
	buddy.shot_clock=1
	buddy._choose_attack(0.3)
	check(is_equal_approx(buddy.shot_clock,0.5),"actual attack timer advances faster inside field")
	check(buddy.hit_damage(4)==2 and buddy.hit_damage(3)==2 and buddy.hit_damage(1)==1,"half damage rounded upward, minimum one")
	buddy.hp=10
	buddy.receive_hit(1-buddy.polarity,4)
	check(buddy.hp==8,"real receive_hit applies damage reduction")
	buddy.receive_hit(buddy.polarity,4)
	check(buddy.hp==8 and buddy.gauge==1,"same-color absorption retained")
	lantern.free()
	game.camera.position += Vector2(5000,0)
	check(not source.field_active() and not buddy.enhanced() and buddy.hit_damage(4)==4,"offscreen lantern stops field immediately")
	game.camera.position=source.position
	source.dead=true
	check(not buddy.enhanced(),"dead source immediately removes enhancement")
	source.dead=false
	buddy.free()
	outside.free()
	boss.free()
	var data: Dictionary = game.stream.loaded[Vector2i.ZERO]
	var descriptor: Dictionary = data.spawns.filter(func(e):return e.id==source.spawn_id)[0]
	var observed := descriptor.duplicate(false)
	observed.position=source.position
	var witness := G.sight_witness(observed,data)
	game.player.position=witness.target
	game.player.polarity=1-source.polarity
	game.camera.position=(game.player.position+source.position)/2
	for e in get_nodes_in_group("enemies"):
		if e!=source: e.collision_layer=0
	var missile = game.spawn_bullet(game.player,(source.position-game.player.position).normalized(),true,source)
	for i in range(360):
		await frames()
		if source.hp<T.ENHANCER_HP or not is_instance_valid(missile): break
	check(source.hp==T.ENHANCER_HP-T.HOMING_DAMAGE,"real homing shot from initial-ability standing witness hits lantern")
	var old_score: int = game.score
	var old_crystals: int = game.crystals
	var id: String = source.spawn_id
	source.receive_hit(1-source.polarity,999)
	check(game.score==old_score+T.ENEMY_SCORE and game.crystals==old_crystals+5 and game.player.homing_charges==1,"lantern awards normal score, crystals and homing stock")
	check(game.stream.missing.has(id) and game.boss_arrow_unlocked,"normal 5C removal and arrow unlock")
	await frames(2)
	game.camera.position=Vector2(10000,10000)
	game.player.position=game.camera.position
	game.elapsed=T.RESPAWN_MIN_TIME+T.RESPAWN_INTERVAL*100
	game.stream.update_rewards()
	var returned: Array = get_nodes_in_group("enhancers").filter(func(e):return e.get_parent()==game.world and e.spawn_id==id)
	check(returned.size()==1 and not game.stream.missing.has(id),"5C probabilistic restoration uses same persistent ID")
	if not returned.is_empty():
		check(returned[0].hp==T.ENHANCER_HP and returned[0].gauge==0,"restored lantern full HP, empty gauge")
		game.boss_arrow_unlocked=false
		returned[0].receive_hit(1-returned[0].polarity,999)
		check(game.boss_arrow_unlocked and game.score==old_score+2*T.ENEMY_SCORE,"restored lantern can unlock and awards again")
	game.free()

func run():
	DirAccess.make_dir_recursive_absolute("res://builds/qa/enemies")
	population()
	await physical()
	var report := {"checks":checks,"failures":failures.size(),"messages":failures,"non_start_samples":samples,"lanterns":placed,"mean":float(placed)/samples}
	FileAccess.open("res://builds/qa/enemies/enhancer_results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("ENHANCER TEST: %d checks, %d failures; mean %.3f" % [checks,failures.size(),float(placed)/samples])
	quit(0 if failures.is_empty() else 1)
