extends "res://tests/test_tree.gd"
const Main := preload("res://scripts/main.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Tutorial := preload("res://scripts/tutorial.gd")
const S := preload("res://scripts/sector_generator.gd")
const P := preload("res://scripts/enemy_population.gd")
const G := preload("res://scripts/stage_generator.gd")
const T := preload("res://scripts/tuning.gd")
const Support := preload("res://tests/stream_test_support.gd")
var checks := 0
var failures: Array[String] = []
var game: Node2D
var reserve_times: Array = []
var distribution := {}
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
func enemies(at: Vector2i) -> Array:
	return get_nodes_in_group("enemies").filter(func(e):return e.get_parent()==game.world and not e.dead and not e.is_queued_for_deletion() and e.kind!="boss" and e.get_meta("sector",Vector2i(999,999))==at)
func freeze():
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	for e in get_nodes_in_group("enemies"): e.set_physics_process(false)
func prepare_population():
	var deadline := Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline:
		game.stream._service_population_jobs()
		if game.stream.population_jobs.is_empty() and game.stream.population_waiting.is_empty(): return true
		await frames()
		OS.delay_msec(1)
	check(false,"population worker deadline")
	return false
func flush_population():
	await prepare_population()
	for i in range(100):
		game.stream._service_population(Time.get_ticks_usec()+100000)
		freeze()
		if game.stream.population_queue.is_empty(): break
		await frames()

func placement():
	for seed_value in Array(range(120))+[444]:
		test_progress()
		var at := Vector2i.ZERO if seed_value%3==0 else Vector2i(seed_value%7-3,seed_value%5-2)
		var data := S.generate(seed_value,at)
		var begin := Time.get_ticks_usec()
		var extras := P.reserve(data)
		reserve_times.append((Time.get_ticks_usec()-begin)/1000.0)
		var base: Array = data.spawns.filter(func(e):return e.kind!="boss")
		check(extras.size()==base.size()*(T.LOOP_COUNT_CAP-1),"full reserve population seed %d: %d/%d" % [seed_value,extras.size(),base.size()*(T.LOOP_COUNT_CAP-1)])
		var blocked := P.occupied(data.spawns)
		var fixed := P.obstacles(data)
		var ids := {}
		check(extras.all(func(e):return e.spawn_stage<=T.LOOP_COUNT_CAP-1),"reserve never computes stages beyond the cap")
		for level in range(1,T.LOOP_COUNT_CAP):
			check(extras.filter(func(e):return e.spawn_stage<=level).size()==base.size()*level,"stage %d count is base times 1+n" % level)
		for e: Dictionary in extras:
			check(not ids.has(e.id),"extra IDs unique across all stages")
			ids[e.id]=true
			var volume := P.area(e)
			check(not G._any_intersects(fixed,volume) and not G._any_intersects(blocked,volume),"extra avoids terrain/loot/bodies/patrols/flight lanes seed %d" % seed_value)
			check(data.chambers[e.chamber_id].kind=="normal" and data.chambers[e.chamber_id].rect.encloses(volume),"extra stays outside start/boss chambers")
			check(at!=Vector2i.ZERO or not volume.grow(T.CAVE_SAFE_RADIUS).has_point(T.SECTOR_START),"extra avoids start radius")
			check(G.has_attack_sight(e,data),"extra has original attack-sight witness")
			if e.kind=="flyer":
				check(P.lane_clear(e,data.solids+data.breakables) and not G._any_intersects(blocked,P.flight_lane(e)),"extra flight lane clear")
			else:
				check(G._supported(volume.get_center(),volume.size,data.solids),"extra full patrol has support")
			blocked.append(volume.grow(T.ENEMY_PLACEMENT_MARGIN))
			if e.kind=="flyer": blocked.append(P.flight_lane(e))
			distribution[e.kind]=distribution.get(e.kind,0)+1
		if seed_value%10==0:
			check(str(extras)==str(P.reserve(data)),"reserve reproducible from seed/sector/stage")
			print("LOOP PLACEMENT ",seed_value)

func movement_ticks(originals: Array, level: int):
	var walker = originals.filter(func(e):return e.kind=="walker")[0]
	var probe := Enemy.new()
	probe.game=game
	probe.kind="walker"
	probe.spawn_id="movement_probe"
	probe.patrol=walker.patrol
	probe.position=Vector2((walker.patrol.x+walker.patrol.y)/2,walker.position.y)
	game.world.add_child(probe)
	probe.was_visible=true
	probe.wake_delay=0
	probe.shot_clock=1000
	probe.set_meta("patrol_direction",1)
	game.camera.position=probe.position
	var start_x: float = probe.position.x
	await frames(10)
	check(absf(probe.position.x-start_x-T.PATROL_SPEED*(1.0+0.1*level)*10.0/60.0)<0.02,"actual ten physics ticks scale walker speed at level %d" % level)
	probe.free()
	var flyer = originals.filter(func(e):return e.kind=="flyer")[0]
	probe=Enemy.new()
	probe.game=game
	probe.kind="flyer"
	probe.spawn_id="flight_probe"
	probe.patrol=flyer.patrol
	probe.position=Vector2((flyer.patrol.x+flyer.patrol.y)/2,flyer.flight_center_y)
	game.world.add_child(probe)
	probe.set_physics_process(false)
	probe.set_meta("patrol_direction",1)
	start_x=probe.position.x
	for i in range(10): probe._move_flyer(1.0/60.0)
	check(absf(probe.position.x-start_x-T.FLYER_SPEED*(1.0+0.1*level)*10.0/60.0)<0.02,"actual ten flyer updates scale flight speed at level %d" % level)
	probe.free()
	game.camera.position=Vector2(-20000,-20000)
	probe=Enemy.new()
	probe.game=game
	probe.kind="turret"
	probe.spawn_id="clock_probe"
	game.world.add_child(probe)
	probe.set_physics_process(false)
	probe.shot_clock=1
	probe._choose_attack(0.2)
	check(is_equal_approx(probe.shot_clock,1-0.2*(1.0+0.15*level)),"actual attack timer advances at scaled rate")
	probe.free()

func scaling():
	game=Main.new()
	game.controls_path="res://builds/qa/enemies/loop_controls.cfg"
	root.add_child(game)
	game.start_run(37)
	freeze()
	var originals: Array = enemies(Vector2i.ZERO)
	var sleeping = enemies(Vector2i(-1,0)).filter(func(e):return e.kind=="turret")[0]
	var sleeping_id: String = sleeping.spawn_id
	sleeping.hp=1
	game.stream._unload(Vector2i(-1,0))
	var victim = originals.filter(func(e):return e.kind=="turret")[0]
	victim.hp-=1
	var source := Enemy.new()
	source.game=game
	source.kind="boss"
	source.boss_role="final"
	source.spawn_id="loop_final_fixture"
	source.boss_id=800
	source.position=Vector2(-20000,-20000)
	game.world.add_child(source)
	source.set_physics_process(false)
	var boss_hp: int = source.max_hp
	for clears in range(4):
		if clears>0:
			# Real progression entry point; discard only the asynchronous site search.
			game.boss_cycle.defeated(source)
			game.boss_cycle.shutdown()
		var count_level: int = (clears+1)/2
		var stat_level: int = clears/2
		check(game.enemy_count_level()==count_level,"final defeat increments the enemy count stage")
		check(game.enemy_stat_level()==stat_level,"final defeat increments the enemy stat stage")
		check(source.max_hp==boss_hp and source.outgoing_damage(12)==12 and source.movement_ratio()==1,"boss stats excluded")
		check(victim.hp==victim.max_hp-1,"living enemy retains damage deficit at clear %d" % clears)
		for e in originals:
			var base: int = T.ENHANCER_HP if e.kind=="enhancer" else T.ENEMY_HP
			check(e.max_hp==base*(1+2*stat_level),"all original kinds HP at clear %d: %s" % [clears,e.kind])
			for damage: int in [T.ENEMY_NORMAL_DAMAGE,T.ENEMY_HOMING_DAMAGE,T.LASER_DAMAGE,T.BOMB_DAMAGE,T.CONTACT_DAMAGE]:
				check(e.outgoing_damage(damage)==roundi(damage*(1.0+0.2*stat_level)),"all outgoing damage paths scale")
			check(is_equal_approx(e.movement_ratio(),1.0+0.1*stat_level),"patrol and flight speed scale")
			# Disable nearby fields for the interval measurement by observing offscreen.
			game.camera.position=Vector2(-20000,-20000)
			check(is_equal_approx(e.attack_rate(),1.0+0.15*stat_level),"attack interval denominator scales")
		await movement_ticks(originals,stat_level)
		var missile_target := Enemy.new()
		missile_target.game=game
		missile_target.kind="turret"
		missile_target.spawn_id="missile_fixture_%d" % clears
		game.world.add_child(missile_target)
		missile_target.set_physics_process(false)
		for shot in range(stat_level): missile_target.receive_hit(1-missile_target.polarity,T.HOMING_DAMAGE)
		check(not missile_target.dead,"clear %d needs more than %d homing hits" % [clears,stat_level])
		missile_target.receive_hit(1-missile_target.polarity,T.HOMING_DAMAGE)
		check(missile_target.dead,"homing hits required are 1/1/2/2")
		await frames(2)
		if clears>0:
			var expected_notice: String = T.LOOP_COUNT_NOTICE if clears%2==1 else T.LOOP_STAT_NOTICE
			check(game.loot_message==expected_notice and game.loot_message_remaining>0,"clear %d shows the matching scale notice" % clears)
			if clears==1:
				game.stream._service_population_jobs()
				game.shift_origin(Vector2i(1,0))
				check(game.stream.population_sources[Vector2i.ZERO].coord==Vector2i.ZERO,"population worker input remains sector-local during origin shift")
			check(await prepare_population(),"immutable population jobs complete")
			check(game.stream.loaded[Vector2i.ZERO].reinforcements.all(func(e):return e.id.begins_with("0,0:") and Rect2(game.stream.sector_offset(Vector2i.ZERO),T.SECTOR_SIZE).has_point(e.position)),"worker output installs at current origin with stable IDs")
			if clears%2==1:
				var extra: Dictionary = game.stream.loaded[Vector2i.ZERO].reinforcements.filter(func(e):return e.spawn_stage==count_level)[0]
				game.camera.position=extra.position
				game.player.position=extra.position
				await flush_population()
				check(not enemies(Vector2i.ZERO).any(func(e):return e.spawn_id==extra.id),"new enemy cannot suddenly appear on screen or inside margin")
			game.camera.position=Vector2(-20000,-20000)
			game.player.position=game.camera.position
			await flush_population()
			check(enemies(Vector2i.ZERO).size()==originals.size()*(1+count_level),"loaded sector reaches full multiplied population after leaving view")
	# Real projectile producers preserve scaled launch damage, including source death.
	var bullet = game.spawn_bullet(victim,Vector2.RIGHT)
	var guided = game.spawn_bullet(victim,Vector2.RIGHT,true,game.player)
	var laser = game.spawn_laser(victim)
	var bomb = game.spawn_bomb_warning(victim)
	check(bullet.damage==14 and guided.damage==22 and laser.damage==17 and bomb.damage==19,"bullet/guided/laser/bomb producers use the final stat-stage damage")
	for shot in [bullet,guided,laser,bomb]: shot.free()
	game.player.hp=100
	game.player.invulnerability=0
	game.player.polarity=1-victim.polarity
	game.player.position=victim.position
	await frames(2)
	game.player._check_enemy_contact()
	check(game.player.hp==88,"real contact query uses scaled final stat-stage damage")
	game.camera.position=Vector2(-20000,-20000)
	game.player.position=game.camera.position
	check(await Support.ready(self,game,game.stream.sector_offset(Vector2i(-1,0))+T.SECTOR_START),"reload sector saved at stage zero after three clears")
	freeze()
	var awakened: Array = enemies(Vector2i(-1,0)).filter(func(e):return e.spawn_id==sleeping_id)
	check(awakened.size()==1 and awakened[0].max_hp==6 and awakened[0].hp==5,"unloaded living enemy upgrades while preserving one point of damage")
	game.camera.position=Vector2(-20000,-20000)
	game.player.position=game.camera.position
	await flush_population()
	# Unload a wounded original and an added enemy; advance levels on an unloaded snapshot.
	var extra_actor = enemies(Vector2i.ZERO).filter(func(e):return e.spawn_id.contains(":extra_"))[0]
	var extra_id: String = extra_actor.spawn_id
	extra_actor.hp-=3
	extra_actor.gauge=2
	var position: Vector2 = extra_actor.position
	game.stream._unload(Vector2i.ZERO)
	check(game.stream.states[Vector2i.ZERO].actors[extra_id].hp==T.ENEMY_HP*3-3,"extra enemy state persisted on unload")
	game.shift_origin(Vector2i(2,-3))
	check(await Support.ready(self,game,game.stream.sector_offset(Vector2i.ZERO)+T.SECTOR_START),"reload after origin shift")
	freeze()
	game.camera.position=Vector2(-20000,-20000)
	game.player.position=game.camera.position
	await flush_population()
	var restored: Array = enemies(Vector2i.ZERO).filter(func(e):return e.spawn_id==extra_id)
	check(restored.size()==1 and restored[0].hp==3 and restored[0].gauge==2 and restored[0].position.is_equal_approx(position-Vector2(2,-3)*T.SECTOR_SIZE),"added enemy HP/gauge/position survives reload and origin move")
	if not restored.is_empty():
		restored[0].receive_hit(1-restored[0].polarity,999)
		check(game.stream.missing.has(extra_id) and game.defeated_enemies.has(extra_id),"added enemy uses normal defeat/respawn records")
		await frames(2)
		game.elapsed+=1000
		game.stream.update_rewards()
		check(enemies(Vector2i.ZERO).any(func(e):return e.spawn_id==extra_id and e.hp==6),"added enemy respawns at current stat-stage full HP")
	# A sector not previously loaded gets the same current stats and population.
	check(await Support.ready(self,game,game.stream.sector_offset(Vector2i(4,0))+T.SECTOR_START),"new sector at three clears loads from worker")
	freeze()
	game.camera.position=Vector2(-20000,-20000)
	game.player.position=game.camera.position
	await flush_population()
	var later := enemies(Vector2i(4,0))
	var later_spawns: Array = game.stream.loaded[Vector2i(4,0)].spawns.filter(func(e):return e.kind!="boss")
	var later_base: int = later_spawns.filter(func(e):return int(e.get("spawn_stage",0))==0).size()
	check(later.size()==later_spawns.size() and later_spawns.size()==later_base*3,"later sector uses the full count-stage population")
	check(later.all(func(e):return e.max_hp==(18 if e.kind=="enhancer" else 6)),"later sector uses the final stat-stage HP")
	var tutorial := Tutorial.new()
	tutorial.key_bindings=game.key_bindings
	root.add_child(tutorial)
	tutorial.set_physics_process(false)
	check(tutorial.enemy_count_level()==0 and tutorial.enemy_stat_level()==0,"tutorial never scales")
	tutorial.update_loop_scaling()
	check(get_nodes_in_group("enemies").filter(func(e):return e.get_parent()==tutorial.world).all(func(e):return e.max_hp==T.ENEMY_HP),"tutorial targets retain their original HP")
	tutorial.free()
	game.start_run(37)
	freeze()
	check(game.enemy_count_level()==0 and game.enemy_stat_level()==0 and enemies(Vector2i.ZERO).size()==15 and game.stream.pending_population.is_empty(),"retry restores base population and stages")
	check(enemies(Vector2i.ZERO).all(func(e):return e.hp==(6 if e.kind=="enhancer" else 2)),"retry restores base HP")
	game.free()

func run():
	DirAccess.make_dir_recursive_absolute("res://builds/qa/enemies")
	placement()
	await scaling()
	var report := {"checks":checks,"failures":failures.size(),"messages":failures,"reserve_mean_ms":reserve_times.reduce(func(a,b):return a+b,0.0)/reserve_times.size(),"reserve_max_ms":reserve_times.max(),"distribution":distribution}
	FileAccess.open("res://builds/qa/enemies/loop_results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("LOOP SCALING TEST: %d checks, %d failures; %s" % [checks,failures.size(),JSON.stringify(report)])
	quit(0 if failures.is_empty() else 1)
