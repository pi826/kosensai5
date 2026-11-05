extends "res://tests/test_tree.gd"
const Main = preload("res://scripts/main.gd")
const T = preload("res://scripts/tuning.gd")
const S = preload("res://scripts/sector_generator.gd")
const G = preload("res://scripts/stage_generator.gd")
const Cycle = preload("res://scripts/boss_cycle.gd")
const Support = preload("res://tests/stream_test_support.gd")
const STEP := 1.0 / 60.0
var game: Node2D
var boss: CharacterBody2D
var checks := 0
var failures: Array[String] = []
var summon_screen_results: Array = []
var wander_results := {}
var route_timing_result := {}
func _initialize(): call_deferred("run")
func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: ",message)
	return ok
func frames(n: int = 1):
	for i in range(n):
		if is_instance_valid(boss): game.camera.position = boss.position
		for bullet in game.projectiles.get_children(): bullet.set_physics_process(false)
		test_progress()
		await physics_frame
		test_progress()
		await process_frame
func clear_bullets():
	for b in game.projectiles.get_children(): b.free()
func minions() -> Array:
	return get_nodes_in_group("enemies").filter(func(e): return e.get_parent() == game.world and e.get_meta("summoned_by",-1) == boss.boss_id and not e.dead and not e.is_queued_for_deletion())
func reset_boss(role: String = "guardian"):
	boss.set_physics_process(false)
	boss.cancel_attack()
	boss.boss_role = role
	boss.position = boss.roam.get_center()
	boss.wake_delay = 0
	boss.was_visible = true
	boss.switch_clock = 1000
	boss.shot_clock = 1000
	boss.signature_clock = 0
	boss.gauge = 0
	boss.hp = boss.max_hp
	boss.summon_wave = 0
	boss.summons_to_restore = 0
	game.player.position = boss.position+Vector2(200,40)
	game.player.invulnerability = 10000
	game.camera.position = boss.position
	clear_bullets()
func start_pattern(boss_type: String):
	boss.boss_type = boss_type
	boss.signature_clock = 0
	boss._choose_attack(0)
	boss.set_physics_process(true)
func spin_checks(role: String):
	reset_boss(role)
	var before_direction: int = boss.spin_direction
	start_pattern("spinner")
	check(boss.action == "windup_spin" and boss.spin_direction == -before_direction,"spin warns and reverses direction "+role)
	check(boss.signature_clock == T.BOSS_SIGNATURE_INTERVAL[role],"signature timer reset "+role)
	await frames(37)
	check(boss.action == "spinning","spin warning completes "+role)
	var arms: int = T.BOSS_SPIN_ARMS[role]
	var previous_count := 0
	var volleys := 0
	var first_angle := 0.0
	var angle_difference := 0.0
	for tick in range(40):
		await frames()
		var bullets: Array = game.projectiles.get_children()
		if bullets.size() > previous_count:
			check(bullets.size()-previous_count == arms,"one spin volley has expected arms "+role)
			for k in range(arms): check(bullets[previous_count+k].polarity == (boss.polarity if k%2 == 0 else 1-boss.polarity),"alternating spin colors "+role)
			if volleys == 0: first_angle = bullets[previous_count].direction.angle()
			elif volleys == 1: angle_difference = angle_difference_signed(first_angle,bullets[previous_count].direction.angle())
			volleys += 1
			previous_count = bullets.size()
			if volleys == 2: break
	check(volleys == 2 and absf(angle_difference-boss.spin_direction*T.BOSS_SPIN_SPEED[role]*T.BOSS_SPIN_SHOT_INTERVAL[role]) < 0.02,"spin angular increment between volleys "+role)
	var old_colors: Array = game.projectiles.get_children().map(func(b): return b.polarity)
	boss.polarity = 1-boss.polarity
	check(game.projectiles.get_children().map(func(b): return b.polarity) == old_colors,"fired spin colors remain fixed "+role)
	# Actual combat absorption and damage for a color-overridden projectile.
	var sample = game.projectiles.get_child(0)
	var hp: int = game.player.hp
	game.player.polarity = sample.polarity
	game.player.gauge = 0
	game.player.homing_charges = 0
	check(game.player.receive_hit(sample.polarity,sample.damage) == "absorbed" and game.player.hp == hp and game.player.gauge == 1,"same color spin shot absorbed")
	game.player.invulnerability = 0
	game.player.polarity = 1-sample.polarity
	check(game.player.receive_hit(sample.polarity,sample.damage) == "damaged" and game.player.hp == hp-sample.damage,"opposite spin shot damages")
	game.player.invulnerability = 10000
	await frames(230)
	boss.set_physics_process(false)
	check(boss.action == "idle","spinning ends idle "+role)
func angle_difference_signed(a: float,b: float) -> float: return wrapf(b-a,-PI,PI)
func clear_minions():
	for e in minions(): e.free()
func finish_summon():
	var before := minions().size()
	boss.set_physics_process(false)
	boss._physics_process(T.BOSS_SUMMON_WARNING-0.01)
	check(boss.action == "windup_summon" and minions().size() == before,"no summons before full warning")
	boss._physics_process(0.02)
	for e in minions(): e.set_physics_process(false)
	check(boss.action == "idle","summon warning completes into idle")
func check_placement(children: Array, previous: Array = []):
	for i in range(children.size()):
		var e = children[i]
		var body := Rect2(e.position-e.body_size/2,e.body_size)
		check(e.kind == ("walker" if i%2 == 0 else "flyer") and e.polarity == (boss.polarity+i)%2,"alternating minion kind and color")
		check(boss.arena.encloses(body),"minion wholly inside arena")
		check(e.get_meta("summoned_by") == boss.boss_id and e.get_meta("sector") == boss.get_meta("sector") and e.get_meta("chamber_id") == -1 and e.boss_id == -1 and e.spawn_id.begins_with("summon:%d:" % boss.boss_id),"minion ownership metadata and ID")
		check(not game.stream.live_normals.has(e.spawn_id) and e.wake_delay > 0,"minions bypass normal registry and wake normally")
		check(absf(e.position.x-game.player.position.x) >= 256,"summon at least 256px horizontally from player")
		check(not (game.stage.solids.filter(func(r): return r.size.y != 16)+game.stage.breakables).any(func(r): return r.intersects(body)),"summon avoids rock and breakables")
		if e.kind == "walker":
			check(absf(e.position.y+e.body_size.y/2-boss.arena.end.y) < 0.1,"walker stands on arena floor")
			check(e.patrol == Vector2(maxf(boss.arena.position.x+64,e.position.x-192),minf(boss.arena.end.x-64,e.position.x+192)),"walker retains clamped patrol")
		else:
			check(e.flight_center_y == boss.arena.end.y-T.ARENA_FLYER_HEIGHT and absf(e.position.y-e.flight_center_y) <= T.FLYER_BOB_AMPLITUDE,"flyer 400px above arena floor")
			check(e.patrol == Vector2(boss.arena.position.x+160,boss.arena.end.x-160),"flyer retains flight lane")
		for j in range(i):
			var other = children[j]
			check(not body.intersects(Rect2(other.position-other.body_size/2,other.body_size)),"new summon bodies do not overlap")
			if other.kind == e.kind: check(absf(e.position.x-other.position.x) >= T.ENEMY_SIZE.x+64,"same-tier centres at least ENEMY_SIZE.x + 64 apart")
		for other in previous:
			check(not body.intersects(Rect2(other.position-other.body_size/2,other.body_size)),"new wave avoids living survivors")
func no_more_summons():
	var before := minions().size()
	boss.switch_clock = 1000
	boss.gauge = 0
	boss.shot_clock = 0
	for tick in range(1200):
		boss._choose_attack(1.0/60)
		if boss.action == "windup_summon":
			check(false,"no periodic summon over twenty seconds")
			break
		boss.cancel_attack()
	check(minions().size() == before and boss.action == "idle","twenty seconds do not add summons")
func check_screen_placement(children: Array, label: String, existing: Array):
	var tiers: Array = []
	for e in children:
		var body := Rect2(e.position-e.body_size/2,e.body_size)
		check(game.view_rect().grow(-16).encloses(body),"whole summoned body 16px inside current screen "+label)
		check(absf(e.position.x-game.player.position.x) >= 256,"screen summon retains 256px distance "+label)
		var overlaps := existing.any(func(other): return not other.dead and body.intersects(Rect2(other.position-other.body_size/2,other.body_size)))
		tiers.append("b" if overlaps else "a")
	summon_screen_results.append({"position":label,"tiers":tiers,"x":children.map(func(e): return e.position.x-game.player.position.x)})
	print("SUMMON SCREEN ",JSON.stringify(summon_screen_results.back()))
func check_summon_activity(children: Array, label: String):
	var starts := children.map(func(e): return e.position)
	var visible := children.map(func(_e): return false)
	var active := visible.duplicate()
	for e in children: e.set_physics_process(true)
	# Keep the real floor camera fixed; frames() would follow the boss instead.
	for tick in range(int((T.ENEMY_WAKE_DELAY+1.0)*60)):
		for bullet in game.projectiles.get_children(): bullet.set_physics_process(false)
		test_progress()
		await physics_frame
		await process_frame
		for i in range(children.size()):
			var e = children[i]
			visible[i] = visible[i] or e.was_visible
			active[i] = active[i] or e.position.distance_to(starts[i]) > 1.0 or (e.kind == "walker" and e.action.begins_with("windup"))
	for i in range(children.size()):
		children[i].set_physics_process(false)
		check(visible[i],"summon becomes visible within wake delay plus one second "+label)
		check(active[i],"summon moves or walker warns within wake delay plus one second "+label)
func summon_checks():
	# Original signature delay and warning still gate the first five.
	reset_boss()
	boss.boss_type = "summoner"
	boss.signature_clock = T.BOSS_SIGNATURE_DELAY
	boss._choose_attack(T.BOSS_SIGNATURE_DELAY-0.01)
	check(boss.action == "idle" and minions().is_empty(),"first wave waits for signature delay")
	boss._choose_attack(0.02)
	check(boss.action == "windup_summon" and minions().is_empty(),"summoning warns before spawning")
	finish_summon()
	check(minions().size() == 5 and boss.summon_wave == 1,"first warning completes exactly five and wave one")
	check_placement(minions())
	no_more_summons()
	var survivors := minions()
	boss.hp = boss.max_hp/2
	boss.switch_clock = 0
	boss.gauge = T.GAUGE_CAPACITY
	boss.shot_clock = 0
	boss.signature_clock = 100
	boss._choose_attack(0)
	check(boss.action == "windup_summon","exact half HP wave precedes switch full gauge signature and shot")
	finish_summon()
	check(minions().size() == 10 and boss.summon_wave == 2,"second wave adds five with all survivors alive")
	check_placement(minions().slice(5),survivors)
	boss.hp = 1
	no_more_summons()
	game.summon_minions(boss,10)
	check(game.alive_summons(boss) == 10,"guardian cap remains ten at execution")
	var victim = minions()[0]
	var id: String = victim.spawn_id
	var prior := [game.crystals,game.score,game.kills,game.defeated_enemies.size()]
	game.player.homing_charges = 0
	victim.receive_hit(1-victim.polarity,9999)
	game.actor_defeated(victim)
	check([game.crystals,game.score,game.kills,game.defeated_enemies.size()] == prior,"summon kill gives no crystals score kills or defeated record")
	check(game.player.homing_charges == T.ENEMY_CHARGE_REWARD and not game.stream.missing.has(id),"summon kill gives charge once and no respawn record")
	await frames(2)
	clear_minions()
	# Actual spawn positions at floor centre and both edges; deterministic replay.
	for relative_x: float in [boss.arena.size.x/2,32,boss.arena.size.x-32]:
		reset_boss()
		game.player.position = Vector2(boss.arena.position.x+relative_x,boss.arena.end.y-game.player.body_size.y/2)
		game.player.velocity = Vector2.ZERO
		game._update_camera(0,true)
		var label := "centre" if relative_x == boss.arena.size.x/2 else ("left" if relative_x == 32 else "right")
		var existing := get_nodes_in_group("enemies").filter(func(e): return e.get_parent() == game.world and not e.dead)
		boss.boss_type = "summoner"
		# The boss itself can be offscreen at the arena edges. Exercise the
		# shared placement entry point without moving the real player camera.
		game.summon_minions(boss,5)
		for e in minions(): e.set_physics_process(false)
		check(minions().size() == 5,"five spawn for each player floor position")
		check_placement(minions())
		check_screen_placement(minions(),label+" wave 1",existing)
		var positions := minions().map(func(e): return e.position)
		clear_minions()
		game.summon_minions(boss,5)
		check(minions().map(func(e): return e.position) == positions,"same player arena and actors give deterministic placement")
		for e in minions(): e.set_physics_process(false)
		var first := minions()
		game.summon_minions(boss,5)
		for e in minions(): e.set_physics_process(false)
		check(minions().size() == 10,"five survivors plus five screen summons "+label)
		check_placement(minions().slice(5),first)
		check_screen_placement(minions().slice(5),label+" wave 2",existing+first)
		await check_summon_activity(minions(),label+" both waves")
		clear_minions()
	# A visible half-screen holds all three walkers even on just one side.
	check(T.VIEW_SIZE.x/2-16-T.ENEMY_SIZE.x/2-2*(T.ENEMY_SIZE.x+64) >= 256,"visible half-screen holds three distant walkers")
	check(T.VIEW_SIZE.x/2-16-T.ENEMY_SIZE.x/2-(T.ENEMY_SIZE.x+64) >= 256,"visible half-screen holds two distant flyers")
	# HP crossing during an attack never interrupts it, nor bypasses waking/visibility.
	reset_boss()
	boss.boss_type = "summoner"
	boss.summon_wave = 1
	boss.hp = boss.max_hp/2
	boss._begin("windup_shot",T.SHOT_WARNING)
	boss._physics_process(0.01)
	check(boss.action == "windup_shot","half HP does not interrupt executing attack")
	boss._complete_action()
	boss.wake_delay = 0.2
	boss._physics_process(0.01)
	check(boss.action == "idle","half HP waits for wake delay")
	boss.wake_delay = 0
	var camera_position: Vector2 = game.camera.position
	game.camera.position += Vector2(10000,0)
	boss._physics_process(0.01)
	check(boss.action == "idle","half HP waits offscreen")
	game.camera.position = camera_position
	boss.was_visible = true
	boss._physics_process(0.01)
	check(boss.action == "windup_summon","half HP begins after current attack and wake")
	boss.cancel_attack()
	check(boss.summon_wave == 1,"cancelled warning does not consume second wave")
	boss._choose_attack(0)
	finish_summon()
	check(boss.summon_wave == 2 and minions().size() == 5,"second wave adds five even with no survivors")
	clear_minions()
	reset_boss()
	boss.boss_type = "summoner"
	boss.hp = boss.max_hp/2
	boss.signature_clock = T.BOSS_SIGNATURE_DELAY
	boss._choose_attack(T.BOSS_SIGNATURE_DELAY-0.01)
	check(boss.action == "idle","early half HP retains first wave delay")
	boss.switch_clock = 0
	boss.gauge = T.GAUGE_CAPACITY
	boss._choose_attack(0.02)
	check(boss.action == "windup_summon" and boss.summon_wave == 0,"early half HP first begins wave one")
	finish_summon()
	check(minions().size() == 5 and boss.summon_wave == 1,"early half HP completes first five")
	boss._choose_attack(0)
	check(boss.action == "windup_summon" and boss.summon_wave == 1,"early half HP selects second wave next")
	finish_summon()
	check(minions().size() == 10 and boss.summon_wave == 2,"early half HP produces ten in two warnings")
	clear_minions()
	reset_boss()
	boss.boss_type = "summoner"
	boss.summon_wave = 1
	boss.summons_to_restore = 3
	boss.hp = boss.max_hp/2
	boss.switch_clock = 0
	boss.gauge = T.GAUGE_CAPACITY
	boss._choose_attack(0)
	check(boss.summon_restoring and boss.summon_count == 3,"restoration precedes simultaneous half HP wave")
	finish_summon()
	check(boss.summon_wave == 1 and boss.summons_to_restore == 0 and minions().size() == 3,"urgent restoration does not consume half HP wave")
	boss._choose_attack(0)
	finish_summon()
	check(boss.summon_wave == 2 and minions().size() == 8,"half HP wave follows urgent restoration")
	clear_minions()
	var fresh = boss.get_script().new()
	check(fresh.summon_wave == 0 and fresh.summons_to_restore == 0,"new guardian instance starts from wave one")
	fresh.free()
	placement_obstacle_checks()
func placement_obstacle_checks():
	var original_arena: Rect2 = boss.arena
	var original_position: Vector2 = boss.position
	var original_size: Vector2 = boss.body_size
	var original_player: Vector2 = game.player.position
	var original_camera: Vector2 = game.camera.position
	var original_solids: Array = game.stage.solids
	var original_breakables: Array = game.stage.breakables
	# Synthetic geometry exercises the obstacle path, absent from normal arenas.
	boss.arena = Rect2(0,0,1664,1024)
	boss.position = Vector2(832,664)
	game.player.position = Vector2(832,1002)
	game.player.velocity = Vector2.ZERO
	game._update_camera(0,true)
	game.stage.solids = [Rect2(0,960,260,64)]
	game.stage.breakables = [Rect2(1300,580,364,80)]
	game.summon_minions(boss,5)
	for e in minions(): e.set_physics_process(false)
	check(minions().size() == 5,"obstacles still allow five minions")
	check_placement(minions())
	check(minions()[0].position.x >= 279,"floor rock excludes leftmost walker candidate")
	check(minions()[1].position.x <= 1281,"breakable excludes rightmost flyer candidate")
	clear_minions()
	game.stage.solids = []
	game.stage.breakables = []
	# Both extremes are equally far. Tier a must avoid the occupied left end.
	boss.position = Vector2(227,664)
	boss.body_size = Vector2(38,1024)
	game.summon_minions(boss,5)
	check(minions().size() == 5 and minions()[0].position.x == 1437,"tier a prefers clear right endpoint over equally distant occupied left")
	check_screen_placement(minions(),"synthetic a",[boss])
	clear_minions()
	# Leave clear space only NEAR the player: tier b must still preserve 256px.
	var blockers: Array = []
	for x in [0,1664]:
		var blocker = boss.get_script().new()
		blocker.game = game
		blocker.kind = "walker"
		blocker.position = Vector2(x,512)
		game.world.add_child(blocker)
		blocker.set_physics_process(false)
		blocker.body_size = Vector2(1200,1024)
		blockers.append(blocker)
	game.summon_minions(boss,5)
	check(minions().size() == 5 and minions()[0].position.x == 227,"tier b beats clear near-player lanes and ties left")
	check_screen_placement(minions(),"synthetic b",[boss]+blockers)
	for i in range(minions().size()):
		for j in range(i):
			if minions()[i].kind == minions()[j].kind: check(absf(minions()[i].position.x-minions()[j].position.x) >= 102,"tier b preserves hard same-wave spacing")
	clear_minions()
	for blocker in blockers: blocker.free()
	boss.body_size = original_size
	# A farther valid arena endpoint is offscreen. Only near-player lanes
	# remain visible, so c must win over the farther d endpoint at x=64.
	game.camera.position = Vector2(1350,822)
	game.stage.solids = [Rect2(1088,0,576,1024)]
	game.summon_minions(boss,5)
	check(minions().size() == 5 and minions()[0].position.x == 1069 and minions()[1].position.x == 1069,"tier c chooses visible near endpoint before farther offscreen arena endpoint")
	for e in minions():
		var body := Rect2(e.position-e.body_size/2,e.body_size)
		check(game.view_rect().grow(-16).encloses(body),"tier c beats d with whole body visible")
		check(absf(e.position.x-game.player.position.x) < 256,"tier c relaxes distance only after a and b fail")
		check(not body.intersects(Rect2(game.player.position-game.player.body_size/2,game.player.body_size)),"tier c excludes player body")
		check(not game.stage.solids[0].intersects(body),"tier c retains hard terrain exclusion")
	clear_minions()
	# This deliberately undersized room has no candidate >=256px away.
	boss.arena = Rect2(0,0,600,832)
	boss.position = Vector2(300,400)
	game.player.position = Vector2(300,810)
	game._update_camera(0,true)
	game.stage.solids = []
	game.stage.breakables = []
	game.summon_minions(boss,5)
	for e in minions(): e.set_physics_process(false)
	check(minions().size() == 5,"undersized room uses remaining candidates")
	check(minions()[0].position.x == 64 and minions()[1].position.x == 160,"tier c keeps screen bounds when 256px impossible, farthest endpoint ties left")
	for i in range(minions().size()):
		var e = minions()[i]
		check(boss.arena.encloses(Rect2(e.position-e.body_size/2,e.body_size)),"fallback body inside arena")
		check(game.view_rect().grow(-16).encloses(Rect2(e.position-e.body_size/2,e.body_size)),"tier c keeps entire body inside screen")
		check(not Rect2(game.player.position-game.player.body_size/2,game.player.body_size).intersects(Rect2(e.position-e.body_size/2,e.body_size)),"tier c never overlaps player")
		for j in range(i):
			var other = minions()[j]
			check(not Rect2(e.position-e.body_size/2,e.body_size).intersects(Rect2(other.position-other.body_size/2,other.body_size)),"fallback bodies remain distinct")
			if e.kind == other.kind: check(absf(e.position.x-other.position.x) >= T.ENEMY_SIZE.x+64,"fallback preserves same-tier spacing")
	clear_minions()
	game.camera.position += Vector2(10000,0)
	game.summon_minions(boss,5)
	check(minions().size() == 5 and minions()[0].position.x == 64 and minions()[1].position.x == 160,"tier d retains arena endpoints when screen has no hard-valid lane")
	clear_minions()
	boss.arena = original_arena
	boss.position = original_position
	boss.body_size = original_size
	game.player.position = original_player
	game.camera.position = original_camera
	game.stage.solids = original_solids
	game.stage.breakables = original_breakables
func charge_checks():
	reset_boss()
	game.player.position = Vector2(boss.arena.end.x-100,boss.arena.end.y-100)
	start_pattern("charger")
	var origin := boss.position
	var target: Vector2 = boss.charge_target
	check(boss.action == "windup_charge","charge warns")
	game.player.position = boss.position-Vector2(240,20)
	await frames(30)
	check(boss.position == origin and boss.charge_target == target and boss.velocity == Vector2.ZERO,"charge warning stationary and target fixed")
	await frames(16)
	check(boss.action == "charging","charge starts after warning")
	var rock_clear := true
	var inside := true
	for tick in range(100):
		await frames()
		var body := Rect2(boss.position-boss.body_size/2,boss.body_size).grow(-0.1)
		inside = inside and boss.arena.encloses(body)
		rock_clear = rock_clear and not game.stream.loaded[boss.get_meta("sector")].solids.any(func(r): return r.size.y != 16 and r.intersects(body))
		if boss.action != "charging": break
	check(inside and rock_clear,"charge body stays in arena and outside rocks")
	check(boss.action == "charge_recover","charge enters recovery")
	var recovered_at := boss.position
	await frames(20)
	check(boss.action == "charge_recover" and boss.position == recovered_at,"recovery stationary")
	await frames(11)
	check(boss.action == "idle","recovery ends idle")
	var max_step := 0.0
	for tick in range(300):
		var previous := boss.position
		await frames()
		max_step = maxf(max_step,previous.distance_to(boss.position))
		if boss.position.distance_to(boss.position.clamp(boss.wander_area().position,boss.wander_area().end)) < 0.5: break
	boss.set_physics_process(false)
	check(max_step <= T.BOSS_RETURN_SPEED/60+1,"return has no teleport frame")
	check(boss.position.distance_to(boss.position.clamp(boss.wander_area().position,boss.wander_area().end)) < 0.5,"returns into the wander area within five seconds")
	# Expiry and collision paths both recover rather than snapping into roam.
	boss._begin("charging",0.001)
	boss.charge_target = boss.position+Vector2(0,100)
	boss.set_physics_process(true)
	await frames()
	boss.set_physics_process(false)
	check(boss.action == "charge_recover","charge deadline recovers")
	boss.position = Vector2(boss.arena.position.x+boss.body_size.x/2+T.BOSS_CLEARANCE,boss.arena.end.y-boss.body_size.y/2-T.BOSS_CLEARANCE)
	boss.charge_target = boss.position-Vector2(200,0)
	boss._begin("charging",1.4)
	boss.set_physics_process(true)
	await frames(20)
	boss.set_physics_process(false)
	check(boss.action == "charge_recover","rock collision recovers")
func order_checks():
	for role: String in ["final","secret"]:
		reset_boss(role)
		boss.signature_index = 0
		for index in range(6):
			var pattern: String = T.BOSS_SIGNATURE_ORDER[index%3]
			check(boss.signature_pattern() == pattern,"cyclic signature order "+role)
			boss._choose_attack(0)
			check(boss.action == {"spinner":"windup_spin","summoner":"windup_summon","charger":"windup_charge"}[pattern] and boss.signature_index == index+1,"ordered signature begins "+role)
			boss.cancel_attack()
			boss.signature_clock = 0
		boss.gauge = T.GAUGE_CAPACITY
		boss.switch_clock = 0
		var index_before: int = boss.signature_index
		boss._choose_attack(0)
		check(boss.action == "windup_switch" and boss.signature_index == index_before,"switch priority over full gauge and signature")
		boss.cancel_attack()
		boss.switch_clock = 100
		boss._choose_attack(0)
		check(boss.action == "windup_special" and boss.signature_index == index_before,"full gauge priority over signature")
		boss.cancel_attack()
		boss.gauge = 0
		boss.signature_index = 1
		game.player.position = Vector2(boss.arena.get_center().x,boss.arena.end.y-game.player.body_size.y/2)
		game.player.velocity = Vector2.ZERO
		game._update_camera(0,true)
		var existing := get_nodes_in_group("enemies").filter(func(e): return e.get_parent() == game.world and not e.dead)
		game.summon_minions(boss,20)
		for e in minions(): e.set_physics_process(false)
		check(minions().size() == T.BOSS_SUMMON_MAX_ALIVE[role],"unchanged summon cap "+role)
		check_placement(minions())
		check_screen_placement(minions(),role,existing)
		boss.shot_clock = 0
		boss._choose_attack(0)
		check(boss.action == "windup_shot" and boss.signature_index == 2 and boss.signature_clock == 0,"capped summon advances index only "+role)
		for e in minions(): e.free()
func reload_boss(record: Dictionary):
	check(await Support.ready(self,game,game.boss_cycle.world_record(record).position),"boss sector reloaded")
	boss = get_nodes_in_group("enemies").filter(func(e): return e.get_parent() == game.world and e.kind == "boss" and e.boss_id == record.boss_id)[0]
	boss.set_physics_process(false)
	game.player.position = Vector2(boss.arena.get_center().x,boss.arena.end.y-game.player.body_size.y/2)
	game.player.velocity = Vector2.ZERO
	game._update_camera(0,true)
	game.player.invulnerability = 10000
func persistence_checks():
	reset_boss()
	boss.boss_type = "summoner"
	var record: Dictionary = game.boss_cycle.records[boss.boss_id]
	record.boss_type = "summoner"
	boss._choose_attack(0)
	finish_summon()
	for e in minions().slice(3): e.free()
	boss.signature_clock = 4.25
	boss.signature_index = 7
	boss.spin_direction = -1
	var ids: Array = minions().map(func(e): return e.spawn_id)
	var at: Vector2i = boss.get_meta("sector")
	game.stream._unload(at)
	boss = null
	var saved: Dictionary = game.stream.states[at]
	check(not saved.actors.keys().any(func(id): return str(id).begins_with("summon:")),"unload excludes summons from saved actors")
	check(not get_nodes_in_group("enemies").any(func(e): return e.get_parent() == game.world and e.spawn_id in ids),"unload removes live summons")
	check(record.saved.signature_clock == 4.25 and record.saved.signature_index == 7 and record.saved.spin_direction == -1,"signature fields saved")
	check(record.saved.summon_wave == 1 and record.saved.summons_to_restore == 3,"BossCycle saves completed wave and three survivors")
	check(saved.actors[record.id].summon_wave == 1 and saved.actors[record.id].summons_to_restore == 3,"sector state saves completed wave and three survivors")
	await reload_boss(record)
	check(boss.signature_clock == 4.25 and boss.signature_index == 7 and boss.spin_direction == -1 and boss.boss_type == "summoner","signature fields and assigned type restored")
	check(game.alive_summons(boss) == 0 and boss.summon_wave == 1 and boss.summons_to_restore == 3,"reload defers summons until selection")
	# Re-unloading before restoration must not lose the pending three.
	game.stream._unload(at)
	boss = null
	check(record.saved.summons_to_restore == 3,"unload before restoration retains pending count")
	await reload_boss(record)
	boss.wake_delay = 0
	boss.was_visible = true
	boss.switch_clock = 0
	boss.gauge = T.GAUGE_CAPACITY
	boss._choose_attack(0)
	check(boss.action == "windup_summon","restore warning precedes switch and gauge")
	# Cancellation during restoration likewise retains the obligation.
	game.stream._unload(at)
	boss = null
	check(record.saved.summons_to_restore == 3 and record.saved.summon_wave == 1,"unload during restore warning retains count and wave")
	await reload_boss(record)
	boss.wake_delay = 0
	boss.was_visible = true
	boss._choose_attack(0)
	check(boss.action == "windup_summon" and minions().is_empty(),"next selection warns before restoring")
	finish_summon()
	check(minions().size() == 3 and boss.summon_wave == 1 and boss.summons_to_restore == 0,"restore returns three without advancing wave")
	check_placement(minions())
	check_screen_placement(minions(),"restored three",[boss])
	var survivors := minions()
	boss.hp = boss.max_hp/2
	boss._choose_attack(0)
	check(boss.action == "windup_summon","half HP after reload selects second wave")
	finish_summon()
	check(minions().size() == 8 and boss.summon_wave == 2,"second wave adds five to restored three")
	check_placement(minions().slice(3),survivors)
	game.stream._unload(at)
	boss = null
	await reload_boss(record)
	boss.wake_delay = 0
	boss.was_visible = true
	boss._choose_attack(0)
	finish_summon()
	check(minions().size() == 8 and boss.summon_wave == 2 and boss.summons_to_restore == 0,"second-wave survivors restore without a third wave")
	boss.hp = 1
	no_more_summons()
	var prior_kills: int = game.kills
	game.player.homing_charges = 0
	boss.receive_hit(1-boss.polarity,9999)
	check(minions().is_empty() and game.kills == prior_kills and game.player.homing_charges == T.BOSS_CHARGE_REWARD,"boss defeat removes summons without extra reward")
	boss = null
	await frames(2)
func floor_visibility_checks():
	for seed_value in [1,37,2026,-17]:
		game.start_run(seed_value)
		game.set_physics_process(false)
		game.player.set_physics_process(false)
		for id in range(3):
			var at: Vector2i = S.guardian_sectors(seed_value)[id]
			if not check(await Support.ready(self,game,Vector2(at-game.origin_sector)*T.SECTOR_SIZE+T.SECTOR_START),"floor visibility guardian sector loads %d:%d" % [seed_value,id]): continue
			var actors := get_nodes_in_group("enemies").filter(func(e): return e.get_parent() == game.world and e.kind == "boss" and e.boss_id == id)
			if not check(actors.size() == 1,"floor visibility guardian loaded %d:%d" % [seed_value,id]): continue
			boss = actors[0]
			for enemy in get_nodes_in_group("enemies"): enemy.set_physics_process(false)
			var floor_spawn := Vector2(boss.arena.get_center().x,boss.arena.end.y-game.player.body_size.y/2)
			game.player.position = floor_spawn
			game.player.velocity = Vector2.ZERO
			game.player.invulnerability = 10000
			game.discovered_bosses.erase(id)
			game._update_camera(0,true)
			game._update_exploration()
			check(game.is_on_screen(boss.position,20.0),"guardian visible from arena floor %d:%d" % [seed_value,id])
			check(game.discovered_bosses.has(id),"guardian discovered from arena floor %d:%d" % [seed_value,id])
			var initial_position: Vector2 = boss.position
			var moved := false
			var initial_visible: bool = game.is_on_screen(boss.position,20.0)
			boss.set_physics_process(true)
			for tick in range(300):
				test_progress()
				await physics_frame
				await process_frame
				moved = moved or boss.position.distance_to(initial_position) > 1.0
			check(initial_visible and moved and boss.was_visible,"guardian starts visible from the floor and keeps moving while engaged %d:%d" % [seed_value,id])
			check(game.player.position == floor_spawn and not game.player.dead,"invulnerable player remains at floor centre")
			boss.set_physics_process(false)
	boss = null

func prepare_shot(role: String, shot_pattern: int) -> void:
	reset_boss(role)
	boss.signature_clock = 1000
	boss.switch_clock = 1000
	boss.shot_clock = 1000
	boss.pattern = shot_pattern
	boss.move_clock = 0.0
	boss.action = "windup_shot"
	boss.action_remaining = T.SHOT_WARNING

func barrage_checks():
	for role: String in ["guardian", "final", "secret"]:
		for shot_pattern in [0, 1]:
			prepare_shot(role, shot_pattern)
			boss._complete_action()
			var fan_count: int = T.SECRET_BOSS_FAN_COUNT if role == "secret" else T.BOSS_FAN_COUNT
			var guided_count := 1 if role != "guardian" and (shot_pattern == 1 or role == "secret") else 0
			var first: Array = game.projectiles.get_children()
			check(first.size() == fan_count+guided_count, role + " first volley is never single pattern %d" % shot_pattern)
			check(first.all(func(b): return b.polarity == boss.polarity), role + " first volley keeps boss color pattern %d" % shot_pattern)
			check(first.filter(func(b): return b.homing).size() == guided_count, role + " first volley guided count pattern %d" % shot_pattern)
			var first_fan: Array = first.filter(func(b): return not b.homing)
			var expects_second: bool = role != "guardian" or shot_pattern == 1
			if not expects_second:
				var first_count := first.size()
				boss.set_physics_process(true)
				await frames(ceili(T.BOSS_SECOND_VOLLEY_DELAY*60)+3)
				boss.set_physics_process(false)
				check(game.projectiles.get_child_count() == first_count and boss.action == "idle", "guardian pattern 0 has no second volley")
			else:
				check(boss.action == "second_volley" and is_equal_approx(boss.action_remaining, T.BOSS_SECOND_VOLLEY_DELAY), role + " schedules second volley pattern %d" % shot_pattern)
				boss._complete_action()
				var all_bullets: Array = game.projectiles.get_children()
				var second: Array = all_bullets.slice(first.size())
				check(second.size() == fan_count, role + " second volley count pattern %d" % shot_pattern)
				check(second.all(func(b): return not b.homing and b.polarity == 1-boss.polarity), role + " second volley opposite color without homing pattern %d" % shot_pattern)
				var offset_ok := true
				for i in range(second.size()):
					offset_ok = offset_ok and absf(angle_difference_signed(first_fan[i].direction.angle(), second[i].direction.angle())-T.BOSS_FAN_ANGLE/2.0) < 0.0001
				check(offset_ok, role + " second volley interleaves by half fan angle pattern %d" % shot_pattern)
				check(boss.action == "idle", role + " second volley returns idle pattern %d" % shot_pattern)
			clear_bullets()
	for role: String in ["guardian", "final", "secret"]:
		for shot_pattern in [0, 1]:
			if role == "guardian" and shot_pattern == 0: continue
			prepare_shot(role, shot_pattern)
			boss._complete_action()
			var before: int = game.projectiles.get_child_count()
			boss.cancel_attack()
			boss.set_physics_process(true)
			await frames(ceili(T.BOSS_SECOND_VOLLEY_DELAY*60)+3)
			boss.set_physics_process(false)
			check(game.projectiles.get_child_count() == before and boss.action == "idle", role + " cancelled second volley does not fire pattern %d" % shot_pattern)
			clear_bullets()

func prepare_rage(hp_value: int) -> void:
	reset_boss("final")
	boss.signature_clock = 1000
	boss.switch_clock = 1000
	boss.shot_clock = 1000
	boss.hp = hp_value
	boss.rage_started = false
	boss.rage_spin_angle = 0.0
	boss.rage_spin_clock = 0.0
	boss.action = "idle"
	boss.action_remaining = 0.0
	clear_bullets()

func rage_checks():
	var half_hp: int = int(boss.max_hp*T.FINAL_BOSS_RAGE_RATIO)
	prepare_rage(half_hp)
	boss.set_physics_process(true)
	await frames(60)
	boss.set_physics_process(false)
	check(game.projectiles.get_child_count() == 0, "exact half HP has no final rage spin")
	var low_hp := half_hp-1
	prepare_rage(low_hp)
	boss.set_physics_process(true)
	await frames(60)
	boss.set_physics_process(false)
	var bullets: Array = game.projectiles.get_children()
	var expected := 60.0/(T.FINAL_BOSS_RAGE_SPIN_INTERVAL*60.0)*T.FINAL_BOSS_RAGE_SPIN_ARMS
	var colors := {}
	for bullet in bullets: colors[bullet.polarity] = true
	check(absf(float(bullets.size())-expected) <= T.FINAL_BOSS_RAGE_SPIN_ARMS, "final rage spin volume in idle")
	check(colors.has(0) and colors.has(1), "final rage spin uses both colors")
	prepare_rage(low_hp)
	boss.action = "spinning"
	boss.action_remaining = 100.0
	boss.spin_shot_clock = 1000.0
	boss._physics_process(1.0/60.0)
	check(game.projectiles.get_child_count() == 0, "final rage spin waits while signature spinning")
	boss.action = "idle"
	boss._physics_process(1.0/60.0)
	check(game.projectiles.get_child_count() == T.FINAL_BOSS_RAGE_SPIN_ARMS, "final rage spin resumes after signature spinning")
	for state: String in ["windup_charge", "charging", "windup_shot"]:
		prepare_rage(low_hp)
		boss.action = state
		boss.action_remaining = 100.0
		boss.charge_target = boss.position+Vector2(600, 0)
		var before: int = game.projectiles.get_child_count()
		boss._physics_process(1.0/60.0)
		check(game.projectiles.get_child_count()-before == T.FINAL_BOSS_RAGE_SPIN_ARMS, "final rage spin continues during "+state)
	reset_boss("final")
	clear_minions()
	boss.signature_index = 0
	boss.signature_clock = 0
	boss.switch_clock = 1000
	boss.shot_clock = 1000
	boss.gauge = 0
	boss.hp = low_hp
	boss._choose_attack(0)
	check(boss.signature_index == 1 and boss.action == "idle", "rage skips spinner and advances signature index")
	boss._choose_attack(0)
	check(boss.action == "windup_summon" and boss.signature_index == 2, "rage reaches summoner on the next selection")
	boss.cancel_attack()
	reset_boss("final")
	boss.signature_index = 0
	boss.signature_clock = 0
	boss.switch_clock = 1000
	boss.shot_clock = 1000
	boss.gauge = 0
	boss.hp = boss.max_hp
	boss._choose_attack(0)
	check(boss.action == "windup_spin" and boss.signature_index == 1, "final above half still starts spinner")
	boss.cancel_attack()
	for role: String in ["guardian", "secret"]:
		reset_boss(role)
		boss.signature_clock = 1000
		boss.switch_clock = 1000
		boss.shot_clock = 1000
		boss.hp = low_hp
		clear_bullets()
		boss.set_physics_process(true)
		await frames(60)
		boss.set_physics_process(false)
		check(game.projectiles.get_child_count() == 0, role + " never uses final rage spin")
	prepare_rage(low_hp)
	var camera_position: Vector2 = game.camera.position
	game.player.position = Vector2(boss.arena.get_center().x,boss.arena.end.y-game.player.body_size.y/2)
	game.camera.position = boss.position+Vector2(10000, 0)
	for _tick in range(60): boss._physics_process(1.0/60.0)
	check(game.projectiles.get_child_count() > 0, "final rage spin continues offscreen while player is in arena")
	clear_bullets()
	prepare_rage(low_hp)
	game.player.position = boss.arena.position-Vector2(200,200)
	game.camera.position = boss.position+Vector2(10000, 0)
	for _tick in range(60): boss._physics_process(1.0/60.0)
	check(game.projectiles.get_child_count() == 0, "final rage spin stops when player leaves the arena offscreen")
	game.camera.position = camera_position
	prepare_rage(low_hp)
	game.effects.bursts.clear()
	boss._physics_process(1.0/60.0)
	var switches: int = game.effects.bursts.filter(func(e): return e.kind == "switch").size()
	boss._physics_process(1.0/60.0)
	check(switches == 1 and game.effects.bursts.filter(func(e): return e.kind == "switch").size() == 1, "final rage crossing effect appears once")

func set_boss_role(role: String) -> void:
	boss.boss_role = role
	boss.body_size = Cycle.size_for(role)
	if boss.body_shape != null: boss.body_shape.size = boss.body_size
	boss.max_hp = Cycle.hp_for(role)
	boss.hp = boss.max_hp

func reset_wander(role: String) -> void:
	boss.set_physics_process(false)
	boss.cancel_attack()
	set_boss_role(role)
	boss.position = boss.wander_area().get_center()
	boss.velocity = Vector2.ZERO
	boss.move_clock = 0.0
	boss.move_direction = Vector2(-1, -0.35)
	boss.wander_target = Vector2.INF
	boss.retarget_clock = 0.0
	boss.wander_retargets = 0
	boss.wander_rng_ready = false
	boss.wander_seed_role = ""
	boss.wander_route.clear()
	boss.wander_route_target = Vector2.INF
	boss.wander_route_shift = -1
	boss.wake_delay = 0.0
	boss.was_visible = true
	boss.action = "idle"
	boss.action_remaining = 0.0
	boss.gauge = 0
	boss.pattern = 0
	boss.signature_clock = 10000.0
	boss.signature_index = 0
	boss.shot_clock = 10000.0
	boss.switch_clock = 10000.0
	boss.summon_count = 0
	boss.summon_wave = 0
	boss.summons_to_restore = 0
	boss.summon_restoring = false
	boss.rage_started = false
	game.player.dead = false
	game.player.position = Vector2(boss.arena.get_center().x, boss.arena.end.y-game.player.body_size.y/2)
	game.player.velocity = Vector2.ZERO
	game.player.invulnerability = 10000
	game.camera.position = boss.position
	clear_bullets()

func route_timing_checks() -> Dictionary:
	reset_wander("guardian")
	var area: Rect2 = boss.wander_area()
	# The game refreshes this cache incrementally before combat; complete it here.
	boss._service_wander_sight_warm()
	while boss.wander_warm_index < boss.wander_sight_grid.size():
		boss._service_wander_sight_warm()
	var rng := RandomNumberGenerator.new()
	rng.seed = 37037
	var samples: Array[float] = []
	var first_profile := {}
	for _sample in range(20):
		var target := Vector2(rng.randf_range(area.position.x, area.end.x-0.01), rng.randf_range(area.position.y, area.end.y-0.01))
		boss.wander_profile_route = _sample == 0
		var began := Time.get_ticks_usec()
		boss._wander_route_to(area, target)
		samples.append(float(Time.get_ticks_usec()-began)/1000.0)
		if _sample == 0:
			first_profile = boss.wander_route_profile.duplicate(true)
	boss.wander_profile_route = false
	var total := 0.0
	var maximum := 0.0
	for sample in samples:
		total += sample
		maximum = maxf(maximum, sample)
	var average := total/float(samples.size())
	var ordered := samples.duplicate()
	ordered.sort()
	var middle := ordered.size() >> 1
	var median: float = ordered[middle] if ordered.size() % 2 == 1 else (ordered[middle-1]+ordered[middle])*0.5
	check(median < 3.0, "boss route calculation median finishes under 3ms")
	check(samples[0] < 6.0, "boss route calculation first call finishes under 6ms")
	return {"first_ms":samples[0], "average_ms":average, "median_ms":median, "maximum_ms":maximum, "samples_ms":samples,
		"first_profile":first_profile, "test_sight_player":game.player.global_position-area.position,
		"warm_sight_player":boss.wander_sight_player, "terrain_revision":game.terrain.revision,
		"warm_sight_revision":boss.wander_sight_revision}

func wander_body(point: Vector2, size: Vector2) -> Rect2:
	return Rect2(point-size/2,size).grow(-0.001)

func wander_shelf_overlap(point: Vector2, size: Vector2, data: Dictionary) -> bool:
	var body := wander_body(point,size)
	return data.solids.any(func(r): return r.size.y == 16 and r.intersects(body))

func wander_rock_overlap(point: Vector2, size: Vector2, data: Dictionary) -> bool:
	var body := wander_body(point,size)
	var obstacles: Array = data.solids.filter(func(r): return r.size.y != 16) + data.breakables
	return obstacles.any(func(r): return r.intersects(body))

func wander_line_clear(point: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(point,game.player.global_position,1|T.PLATFORM_LAYER)
	return boss.get_world_2d().direct_space_state.intersect_ray(query).is_empty()

func wander_metrics(role: String) -> Dictionary:
	reset_wander(role)
	boss.set_physics_process(true)
	var data: Dictionary = game.stream.loaded[boss.get_meta("sector")]
	var area: Rect2 = boss.wander_area()
	var size: Vector2 = boss.body_size
	var overlap_frames := 0
	var line_frames := 0
	var inside := true
	var arena_inside := true
	var rocks_clear := true
	var left := false
	var right := false
	var above_center_shelf := false
	for _tick in range(1200):
		await frames()
		inside = inside and area.has_point(boss.position)
		arena_inside = arena_inside and boss.arena.encloses(wander_body(boss.position,size))
		rocks_clear = rocks_clear and not wander_rock_overlap(boss.position,size,data)
		if wander_shelf_overlap(boss.position,size,data): overlap_frames += 1
		if wander_line_clear(boss.position): line_frames += 1
		left = left or boss.position.x < boss.arena.get_center().x
		right = right or boss.position.x > boss.arena.get_center().x
		above_center_shelf = above_center_shelf or boss.position.y < boss.arena.end.y-320.0
	boss.set_physics_process(false)
	var shelf_fraction := float(overlap_frames)/1200.0
	var line_fraction := float(line_frames)/1200.0
	check(inside,"wander target mode stays inside wander area "+role)
	check(arena_inside and rocks_clear,"wander target mode stays in arena and outside rocks "+role)
	check(shelf_fraction < 0.35,"wander body avoids shelves "+role)
	var required_line: float = {"guardian":0.65,"final":0.80,"secret":0.85}[role]
	check(line_fraction >= required_line,"wander keeps a clear line to the player "+role)
	check(left and right and above_center_shelf,"wander visits both halves and above the centre shelf "+role)
	check(boss.wander_retargets >= 5,"wander retargets repeatedly "+role)
	return {"shelf_overlap":shelf_fraction,"sightline_clear":line_fraction,"retargets":boss.wander_retargets,
		"left":left,"right":right,"above_center_shelf":above_center_shelf}

func legacy_wander_metrics(role: String) -> Dictionary:
	var data: Dictionary = game.stream.loaded[boss.get_meta("sector")]
	var zone := G.arena_zone(boss.arena,0)
	var lane := Cycle.roam_rect(data,zone,role,Vector2(zone.get_center().x,boss.arena.end.y-T.ARENA_BOSS_CENTER_HEIGHT),true)
	if not lane.has_area(): lane = boss.roam
	var point := lane.get_center()
	var direction := Vector2(-1,-0.35)
	var clock := 0.0
	var size := Cycle.size_for(role)
	var overlap_frames := 0
	var line_frames := 0
	for _tick in range(1200):
		clock += STEP
		var period: float = T.BOSS_MOVE_PERIOD[role]
		var speed: float = T.BOSS_MOVE_SPEED[role] * (T.BOSS_PACE_MIN + T.BOSS_PACE_VARIATION * sin(clock * TAU / period))
		var slope: float = T.BOSS_MOVE_SLOPE[role]
		var velocity := Vector2(signf(direction.x),signf(direction.y)*slope).normalized()*speed
		var target := point + velocity*STEP
		if target.x <= lane.position.x or target.x >= lane.end.x: direction.x *= -1
		if target.y <= lane.position.y or target.y >= lane.end.y: direction.y *= -1
		point = Vector2(clampf(target.x,lane.position.x,lane.end.x),clampf(target.y,lane.position.y,lane.end.y))
		if wander_shelf_overlap(point,size,data): overlap_frames += 1
		if wander_line_clear(point): line_frames += 1
	return {"shelf_overlap":float(overlap_frames)/1200.0,"sightline_clear":float(line_frames)/1200.0}

func wander_trace(role: String) -> Array:
	reset_wander(role)
	boss.set_physics_process(true)
	var trace: Array = []
	for _tick in range(60):
		await frames()
		trace.append(boss.position)
	boss.set_physics_process(false)
	return trace

func wander_checks():
	for role: String in ["guardian","final","secret"]:
		var current: Dictionary = await wander_metrics(role)
		var legacy := legacy_wander_metrics(role)
		current["legacy_shelf_overlap"] = legacy.shelf_overlap
		current["legacy_sightline_clear"] = legacy.sightline_clear
		wander_results[role] = current
	var first := await wander_trace("guardian")
	var second := await wander_trace("guardian")
	var replay_equal := first.size() == second.size()
	for index in range(mini(first.size(),second.size())):
		replay_equal = replay_equal and first[index] == second[index]
	check(replay_equal,"same seed and boss id replay the wander trace")

func offscreen_checks():
	reset_wander("guardian")
	var camera_position: Vector2 = game.camera.position
	game.camera.position = boss.position+Vector2(10000,0)
	boss.shot_clock = 0.0
	var start: Vector2 = boss.position
	for _tick in range(30): boss._physics_process(STEP)
	check(start.distance_to(boss.position) > 10.0 and boss.was_visible,"arena player keeps offscreen boss moving")
	clear_bullets()
	boss._begin("windup_shot",STEP*2.0)
	boss.action_remaining = STEP*2.0
	boss.shot_clock = 1000.0
	for _tick in range(5): boss._physics_process(STEP)
	check(boss.action == "idle" and game.projectiles.get_child_count() > 0,"offscreen warning completes while player is in arena")
	clear_bullets()
	boss.action = "second_volley"
	boss.action_remaining = STEP*2.0
	boss.pattern = 1
	for _tick in range(4): boss._physics_process(STEP)
	check(boss.action == "idle" and game.projectiles.get_child_count() == T.BOSS_FAN_COUNT,"offscreen second volley completes")
	clear_bullets()
	boss.action = "charging"
	boss.action_remaining = T.BOSS_CHARGE_MAX_TIME
	boss.charge_target = boss.position+Vector2(140,0)
	start = boss.position
	for _tick in range(30): boss._physics_process(STEP)
	check(start.distance_to(boss.position) > 1.0 and boss.action != "charging","offscreen charge completes")
	boss.cancel_attack()
	boss.shot_clock = 0.0
	boss.switch_clock = 1000.0
	boss.signature_clock = 1000.0
	boss.gauge = 0
	clear_bullets()
	for _tick in range(120): boss._physics_process(STEP)
	check(boss.action == "idle" and game.projectiles.get_child_count() == 0,"offscreen idle starts no new attack")
	game.camera.position = boss.position
	boss.shot_clock = 0.0
	boss._physics_process(STEP)
	check(boss.action == "windup_shot","returning onscreen starts a new attack")
	boss.cancel_attack()
	game.player.position = boss.arena.position-Vector2(200,200)
	game.camera.position = boss.position+Vector2(10000,0)
	boss.was_visible = true
	boss._begin("windup_shot",0.5)
	start = boss.position
	for _tick in range(2): boss._physics_process(STEP)
	check(boss.action == "idle" and not boss.was_visible and boss.position.distance_to(start) < 0.1,"outside arena and offscreen stops and cancels the boss")
	game.player.position = Vector2(boss.arena.get_center().x,boss.arena.end.y-game.player.body_size.y/2)
	game.player.dead = true
	game.camera.position = boss.position+Vector2(10000,0)
	boss.was_visible = true
	boss._begin("windup_shot",0.5)
	boss._physics_process(STEP)
	check(boss.action == "idle" and not boss.was_visible,"dead player does not engage the boss")
	game.player.dead = false
	game.player.hp = T.PLAYER_HP
	game.player.invulnerability = 10000
	reset_boss("guardian")
	game.camera.position = camera_position
	clear_bullets()

func run():
	game = Main.new()
	game.controls_path = "res://builds/qa/bosses/pattern_controls.cfg"
	root.add_child(game)
	await floor_visibility_checks()
	game.start_run(37)
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	var at: Vector2i = S.guardian_sectors(37)[0]
	check(await Support.ready(self,game,Vector2(at-game.origin_sector)*T.SECTOR_SIZE+T.SECTOR_START),"initial guardian arena loads")
	boss = get_nodes_in_group("enemies").filter(func(e): return e.get_parent() == game.world and e.kind == "boss" and e.boss_id == 0)[0]
	for enemy in get_nodes_in_group("enemies"): enemy.set_physics_process(false)
	check(boss.collision_mask & T.PLATFORM_LAYER == 0 and boss.collision_mask & 1 != 0,"boss ignores shelves and retains rock collisions")
	check(boss.boss_type == Cycle.guardian_types(37,1)[0],"initial type assigned by seed and ID")
	route_timing_result = route_timing_checks()
	for boss_type: String in T.GUARDIAN_TYPES:
		boss.boss_type = boss_type
		game.boss = boss
		game.camera.position = boss.position
		game.ui.update_hud()
		check(game.ui.boss_label.text.begins_with(Cycle.display_name("guardian",boss_type)),"HUD displays guardian type "+boss_type)
		check(game.boss_cycle.spawn_message({"sector":at,"role":"guardian","boss_type":boss_type,"region":0}).begins_with(Cycle.display_name("guardian",boss_type)),"spawn banner displays guardian type")
	await spin_checks("guardian")
	boss.signature_index = 0
	await spin_checks("secret")
	await summon_checks()
	await charge_checks()
	await barrage_checks()
	await rage_checks()
	await wander_checks()
	offscreen_checks()
	order_checks()
	await persistence_checks()
	var result := {"checks":checks,"failures":failures,"summon_screen":summon_screen_results,"wander":wander_results,"route_timing":route_timing_result}
	DirAccess.make_dir_recursive_absolute("res://builds/qa/bosses")
	FileAccess.open("res://builds/qa/bosses/pattern-results.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("BOSS PATTERNS ",JSON.stringify(result))
	game.free()
	quit(int(not failures.is_empty()))

