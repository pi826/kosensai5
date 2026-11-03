extends "res://tests/test_tree.gd"
const Main := preload("res://scripts/main.gd")
const Terrain := preload("res://scripts/streamed_terrain.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Dynamite := preload("res://scripts/dynamite.gd")
const Job := preload("res://scripts/sector_job.gd")
const O := preload("res://scripts/origin_shift.gd")
const T := preload("res://scripts/tuning.gd")
var game: Node2D
var checks := 0
var failures: Array[String] = []
var blast_ms := 0.0
var began := 0

class RecenterProbe extends Node:
	var game: Node2D
	var delta := Vector2.ZERO
	func _physics_process(_dt: float) -> void:
		delta = game.maybe_shift_origin()
		set_physics_process(false)

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)
func frames(count: int = 1) -> void:
	for i in range(count):
		test_progress()
		await physics_frame
		await process_frame
func freeze() -> void:
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	for enemy in get_nodes_in_group("enemies"): enemy.set_physics_process(false)
func enemies(at: Vector2i, chamber: int) -> Array:
	return get_nodes_in_group("enemies").filter(func(e): return e.get_parent() == game.world and not e.dead and not e.is_queued_for_deletion() and e.kind != "boss" and not e.has_meta("summoned_by") and e.get_meta("sector") == at and e.get_meta("chamber_id", -1) == chamber)
func kill(e: Node2D, player_attack: bool = true) -> void:
	e.receive_neutral_hit(99999, player_attack)
func reload_sector(at: Vector2i) -> void:
	game.stream._unload(at)
	var job := Job.new()
	job.seed_value = game.current_seed
	job.coord = at
	job.origin = game.origin_sector
	job.saved = game.stream.states[at].duplicate(true)
	job.run()
	game.terrain.begin_sector(job.result, game.stream.states[at].get("dynamite", {}))
	while not game.terrain.build_step(): pass
	game.stream.loaded[at] = job.result.data
	for spawn: Dictionary in job.result.data.spawns: game.stream._spawn(spawn)
	freeze()
func extra_enemy(id: String, chamber: int, kind: String = "walker", summoned: bool = false) -> Node2D:
	var spawn := {"id":id,"kind":kind,"position":Vector2(800,400),"patrol":Vector2(800,800),"polarity":0,"boss_id":-1,"sector":Vector2i.ZERO,"chamber_id":chamber}
	if not summoned: game.stream.loaded[Vector2i.ZERO].spawns.append(spawn)
	game.stream._spawn(spawn)
	var actor: Node2D
	for e in get_nodes_in_group("enemies"):
		if e.get_parent() == game.world and e.spawn_id == id: actor = e
	actor.set_physics_process(false)
	if summoned: actor.set_meta("summoned_by", 123)
	return actor

func acquisition() -> void:
	check(game.dynamite_stock == 0 and game.dynamite_claimed.is_empty(), "run starts empty")
	var groups: Array = []
	for at: Vector2i in game.stream.loaded:
		for chamber: Dictionary in game.stream.loaded[at].chambers:
			if enemies(at, chamber.id).size() >= 2: groups.append([at,chamber.id])
	check(groups.size() >= 5, "loaded generated rooms supply at least five real groups")
	var first: Array = groups[0]
	var targets := enemies(first[0],first[1])
	var descriptors: Array = []
	for spawn: Dictionary in game.stream.loaded[first[0]].spawns:
		if spawn.chamber_id == first[1] and spawn.kind != "boss": descriptors.append(spawn.duplicate(true))
	for i in range(targets.size()-1):
		kill(targets[i])
		check(game.dynamite_stock == 0, "no reward before last generated normal")
	kill(targets.back())
	check(game.dynamite_stock == 1 and game.announcement.contains("1/3"), "last player kill awards one and announces")
	var acquired_key := Vector3i(first[0].x,first[0].y,first[1])
	check(game.dynamite_claimed.has(acquired_key), "room marked claimed")
	await frames()
	for spawn: Dictionary in descriptors:
		game.stream._restore(game.stream.missing[spawn.id])
		game.stream.missing.erase(spawn.id)
	freeze()
	for e in enemies(first[0],first[1]): kill(e)
	check(game.dynamite_stock == 1, "restored group cannot award again")
	await frames()
	reload_sector(first[0])
	check(game.dynamite_claimed.has(acquired_key) and game.dynamite_stock == 1, "claim and stock survive actual stream unload/reload")
	for i in range(1,4):
		for e in enemies(groups[i][0],groups[i][1]): kill(e)
		check(game.dynamite_stock == mini(i+1,3), "group reward stops at three")
	var full_key := Vector3i(groups[3][0].x,groups[3][0].y,groups[3][1])
	check(game.dynamite_claimed.has(full_key) and game.announcement == "ダイナマイトは満杯です", "full stock consumes room claim and announces")
	game.dynamite_stock = 0
	var solo := extra_enemy("dynamite_solo",900)
	kill(solo)
	check(game.dynamite_stock == 0 and not game.dynamite_claimed.has(Vector3i(0,0,900)), "single normal room excluded")
	var summon := extra_enemy("dynamite_summon",901,"walker",true)
	kill(summon)
	check(game.dynamite_stock == 0, "summoned kill excluded")
	var a := extra_enemy("dynamite_env_a",902)
	var b := extra_enemy("dynamite_env_b",902)
	kill(a)
	kill(b,false)
	check(game.dynamite_stock == 0, "non-player last kill excluded")
	var p := extra_enemy("dynamite_pending_a",903)
	var q := extra_enemy("dynamite_pending_b",903)
	game.stream.pending_population[q.spawn_id] = Vector2i.ZERO
	kill(p)
	kill(q)
	check(game.dynamite_stock == 0, "pending population blocks premature claim")
	game.stream.pending_population.erase(q.spawn_id)
	var r := extra_enemy("dynamite_pending_c",903)
	kill(r)
	check(game.dynamite_stock == 1, "completed population can award on final kill")
	# An unfinished reinforcement worker can still add enemies to any room.
	var at: Vector2i = groups[4][0]
	var data: Dictionary = game.stream.loaded[at]
	var had := data.has("reinforcements")
	var reinforcement: Array = data.get("reinforcements", [])
	data.erase("reinforcements")
	var original_level: int = game.boss_cycle.final_clears
	game.boss_cycle.final_clears = 1
	for e in enemies(at,groups[4][1]): kill(e)
	check(game.dynamite_stock == 1, "unfinished reinforcement data blocks room award")
	game.boss_cycle.final_clears = original_level
	if had: data.reinforcements = reinforcement

func payload(at: Vector2i) -> Dictionary:
	var offset := Vector2(at)*T.SECTOR_SIZE
	var rect := Rect2(offset+Vector2(0,512),Vector2(4096,512))
	var shelf := Rect2(offset+Vector2(1000,256),Vector2(192,16))
	var cells := Job.cells(rect)
	var data := {"coord":at,"solids":[rect,shelf],"breakables":[],"protected_rects":[rect],"seed":37}
	return {"data":data,"occupied":cells,"surfaces":{},"destroyed":{},"blocks":[],"shelves":[shelf],"collisions":[rect,shelf]}
func install(terrain: Node2D, at: Vector2i, saved: Dictionary = {}) -> void:
	terrain.begin_sector(payload(at),saved)
	while not terrain.build_step(): pass
func point_solid(point: Vector2, mask: int = 1) -> bool:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collision_mask = mask
	return not game.get_world_2d().direct_space_state.intersect_point(query).is_empty()

func terrain_tests() -> void:
	# Replace only the fixture's terrain, using the real incremental streaming API.
	game.stream.shutdown()
	game.terrain.free()
	var terrain := Terrain.new()
	terrain.stage = game.stage
	game.world.add_child(terrain)
	game.terrain = terrain
	install(terrain,Vector2i.ZERO)
	install(terrain,Vector2i.RIGHT)
	game.player.position = Vector2(1500,200)
	var center := Vector2(2048,768)
	var before: String = str(terrain.sectors[Vector2i.ZERO].data)
	check(center.y-512 > T.SURFACE_DEPTH and 1024-center.y > T.SURFACE_DEPTH, "blast lies deeper than surface depth from either face")
	await frames(2)
	check(point_solid(center), "deep rock starts physically solid")
	var revision: int = terrain.support_revision_at(center)
	var start := Time.get_ticks_usec()
	var removed: Array[Vector2i] = terrain.dynamite_explode(center)
	blast_ms = (Time.get_ticks_usec()-start)/1000.0
	check(blast_ms <= 8.0, "large-rock blast <= 8ms: %.3f" % blast_ms)
	check(removed.size() > 10, "deep protected rock is removed")
	check(terrain.support_revision_at(center) > revision, "blast invalidates resting enemy support")
	await frames(2)
	for cell: Vector2i in removed:
		var point: Vector2 = terrain.pixel_of_cell(cell)+Vector2(16,16)
		check(not terrain.occupied.has(cell) and not terrain.tile_masks.has(cell) and not point_solid(point), "removed deep cell matches physics and drawing %s" % cell)
	var outside := Vector2(2160,784)
	check(terrain.occupied.has(terrain.cell_at(outside)) and point_solid(outside), "adjacent cell outside circle retains collision")
	# Every cell in and next to the carve square must match physical point queries.
	for y in range(20,28):
		for x in range(60,68):
			var point := Vector2(x*32+16,y*32+16)
			check(point_solid(point) == terrain.occupied.has(Vector2i(x,y)), "split rectangle/row exactness %d,%d" % [x,y])
	var probe := CharacterBody2D.new()
	probe.collision_layer = 0
	probe.collision_mask = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(8,8)
	shape.shape = rect
	probe.add_child(shape)
	game.world.add_child(probe)
	probe.position = center+Vector2(0,-40)
	for i in range(16):
		probe.velocity = Vector2(0,120)
		probe.move_and_slide()
		await frames()
	check(probe.position.y > center.y-12, "small real CharacterBody falls through excavated rock")
	probe.free()
	var boundary := Vector2(4096,768)
	var border_removed: Array[Vector2i] = terrain.dynamite_explode(boundary)
	check(border_removed.any(func(c): return c.x < 128) and border_removed.any(func(c): return c.x >= 128), "blast spans two ready sectors")
	await frames(2)
	for cell: Vector2i in border_removed:
		check(not point_solid(terrain.pixel_of_cell(cell)+Vector2(16,16)), "cross-sector destroyed cell has no collision")
	check(str(terrain.sectors[Vector2i.ZERO].data) == before, "generated data remains unchanged")
	var saved0: Dictionary = terrain.snapshot(Vector2i.ZERO)
	var saved1: Dictionary = terrain.snapshot(Vector2i.RIGHT)
	check(saved1.dynamite.holes.keys().all(func(c): return c.x in range(128) and c.y in range(96)), "holes save in sector-local integer coordinates")
	terrain.unload(Vector2i.ZERO)
	terrain.unload(Vector2i.RIGHT)
	check(terrain.rock_bodies.is_empty() and terrain.dynamic_rock_cells.is_empty(), "unload clears static and row ownership")
	install(terrain,Vector2i.ZERO,saved0.dynamite)
	install(terrain,Vector2i.RIGHT,saved1.dynamite)
	await frames(2)
	for cell: Vector2i in removed+border_removed:
		check(not terrain.occupied.has(cell) and not point_solid(terrain.pixel_of_cell(cell)+Vector2(16,16)), "reload preserves deep hole and physical collision")
	check(point_solid(outside), "reload preserves neighbouring rock collision")
	# Repeated intersecting carves and a full origin move use the same integer keys.
	terrain.dynamite_explode(center+Vector2(64,32))
	terrain.shift_origin(-T.SECTOR_SIZE,Vector2i.ONE)
	game.stage.origin_sector = Vector2i.ONE
	await frames(2)
	check(not point_solid(center-T.SECTOR_SIZE), "origin shift preserves existing physical hole")
	var shifted := Vector2(3008,768)-T.SECTOR_SIZE
	var shifted_removed: Array[Vector2i] = terrain.dynamite_explode(shifted)
	await frames(2)
	check(shifted_removed.size()>10 and not point_solid(shifted), "blast after origin shift uses world cell keys")
	check(point_solid(Vector2(3216,768)-T.SECTOR_SIZE), "remaining shifted rock blocks physics")
	terrain.shift_origin(T.SECTOR_SIZE,Vector2i.ZERO)
	game.stage.origin_sector = Vector2i.ZERO
	terrain.dynamite_explode(Vector2(1104,256))
	await frames(2)
	check(point_solid(Vector2(1104,264),T.PLATFORM_LAYER), "thin shelf survives dynamite")
	var not_ready: Array[Vector2i] = terrain.dynamite_explode(Vector2(-16,768))
	check(not_ready.size()>0 and not_ready.all(func(c): return c.x >= 0), "only the ready side of a loaded boundary is touched")

func throwing_and_damage() -> void:
	var player: Node2D = game.player
	player.position = Vector2(1400,100)
	player.facing = 1
	game.dynamite_stock = 2
	check(player.throw_dynamite(), "normal gravity throws")
	var one: Node2D = game.projectiles.get_child(-1)
	one.set_physics_process(false)
	player.gravity_sign = -1
	check(player.throw_dynamite(), "inverted gravity throws")
	var two: Node2D = game.projectiles.get_child(-1)
	two.set_physics_process(false)
	check(one.velocity == two.velocity and one.velocity == Vector2(300,-260), "initial velocity ignores gravity sign")
	for i in range(24):
		one._physics_process(1.0/60)
		two._physics_process(1.0/60)
		await frames()
	check(one.position.is_equal_approx(two.position), "N-frame real-physics trajectories agree")
	check(game.dynamite_stock == 0 and not player.throw_dynamite(), "empty stock cannot throw")
	one.free()
	two.free()
	game.dynamite_stock = 1
	player.dead = true
	check(not player.throw_dynamite() and game.dynamite_stock == 1, "dead player cannot consume stock")
	player.dead = false
	# Move and rest on a shelf; removing its support is tested on a rock floor.
	var stick := Dynamite.new()
	stick.game = game
	stick.position = Vector2(1150,200)
	game.projectiles.add_child(stick)
	stick.set_physics_process(false)
	for i in range(28):
		stick._physics_process(1.0/60)
		await frames()
	check(stick.is_on_floor() and absf(stick.position.y-252)<1 and stick.velocity == Vector2.ZERO, "dynamite rests on one-way shelf")
	stick.free()
	stick = Dynamite.new()
	stick.game = game
	stick.position = Vector2(2800,450)
	game.projectiles.add_child(stick)
	stick.set_physics_process(false)
	for i in range(28):
		stick._physics_process(1.0/60)
		await frames()
	check(stick.is_on_floor() and stick.velocity == Vector2.ZERO, "dynamite rests on rock")
	var floor_y: float = stick.position.y
	game.terrain.dynamite_explode(stick.position+Vector2(0,32))
	await frames(2)
	for i in range(10):
		stick._physics_process(1.0/60)
		await frames()
	check(stick.position.y > floor_y+5, "dynamite falls again when supporting floor is destroyed")
	stick.free()
	# Blast overlaps the edge of bodies, rather than requiring actor centers.
	var center := Vector2(1800,300)
	player.position = center+Vector2(T.DYNAMITE_RADIUS+T.PLAYER_SIZE.x/2-2,0)
	player.hp = 100
	player.invulnerability = 0
	var gauge: int = player.gauge
	var blue := extra_enemy("dynamite_blue",910)
	var orange := extra_enemy("dynamite_orange",911)
	var distant := extra_enemy("dynamite_outside",912)
	for e in [blue,orange,distant]: e.hp=30; e.max_hp=30
	blue.polarity=0; orange.polarity=1
	blue.position=center+Vector2(0,-40)
	orange.position=center+Vector2(-100,0)
	distant.position=center+Vector2(200,0)
	var blast := Dynamite.new()
	blast.game=game; blast.position=center
	game.projectiles.add_child(blast)
	blast.set_physics_process(false)
	blast.detonate()
	check(player.hp == 100-T.DYNAMITE_SELF_DAMAGE and player.gauge == gauge, "body edge receives colorless self damage without absorption")
	check(blue.hp == 30-T.DYNAMITE_DAMAGE and orange.hp == 30-T.DYNAMITE_DAMAGE and distant.hp == 30, "both colors damaged at body edge; outside enemy unchanged")
	player.receive_neutral_hit(20)
	check(player.hp == 80, "self invulnerability is preserved")
	check(blue.gauge == 0 and orange.gauge == 0, "enemies cannot absorb neutral damage")
	blast.free()
	player.position=Vector2(1600,100)
	var score: int = game.score
	var crystals: int = game.crystals
	blue.hp=1; blue.position=center
	blast=Dynamite.new();blast.game=game;blast.position=center
	game.projectiles.add_child(blast);blast.set_physics_process(false)
	blast.detonate()
	check(blue.dead and game.score == score+T.ENEMY_SCORE and game.crystals == crystals+T.CRYSTAL_REWARDS.normal, "blast kill grants regular player rewards")
	blast.free()
	var outside := Dynamite.new()
	outside.game=game;outside.position=Vector2(1000000,0)
	game.projectiles.add_child(outside);outside.set_physics_process(false)
	outside._physics_process(1.0/60)
	check(outside.is_queued_for_deletion() and not outside.exploded, "unloaded projectile disappears without blast")


func additional_tests() -> void:
	var terrain: Node2D = game.terrain
	var player: Node2D = game.player
	player.position=Vector2(1600,100)
	player.gravity_sign=1
	player.hp=50
	terrain.block_removed.connect(game._block_removed)
	var block := Rect2(2400,320,64,64)
	terrain.restore_block(Vector2i.ZERO, block)
	terrain.dynamite_explode(block.get_center())
	check(player.hp==50+T.BLOCK_HEAL and not terrain.block_cells.has(terrain.cell_at(block.position)), "dynamite breaks blocks as player attack and heals")
	# Builder wall stands on unchanged deep rock away from the generated actors.
	terrain.sectors[Vector2i.ZERO].data.protected_rects=[]
	game.stage.protected_rects=[]
	var wall := Rect2(3520,448,32,64)
	var wall_id: int=terrain.place_wall(wall,98765)
	check(wall_id>=0, "builder wall fixture is legal")
	terrain.dynamite_explode(wall.get_center())
	await frames(2)
	check(not terrain.walls.has(wall_id) and not point_solid(wall.get_center(),T.WALL_LAYER), "dynamite removes wall and collision")
	var intact := Vector2(3408,784)
	var cell: Vector2i=terrain.cell_at(intact)
	terrain.explode(intact,96)
	await frames(2)
	check(terrain.occupied.has(cell) and point_solid(intact), "enemy bomb still cannot destroy deep rock")
	# A side impact stops horizontal travel, and the fuse continues while resting.
	var side := Dynamite.new()
	side.game=game;side.position=Vector2(-20,960);side.velocity=Vector2(300,-260)
	game.projectiles.add_child(side);side.set_physics_process(false)
	for i in range(5):
		side._physics_process(1.0/60)
		await frames()
	check(side.velocity.x==0 and side.velocity.y>=0 and not side.exploded, "side collision stops horizontal speed and falls screen-down")
	side.free()
	var timed := Dynamite.new()
	timed.game=game;timed.position=Vector2(500,400)
	game.projectiles.add_child(timed);timed.set_physics_process(false)
	for i in range(95):
		timed._physics_process(1.0/60)
		await frames()
	check(not timed.exploded, "fuse remains live before 1.6 seconds")
	timed._physics_process(1.0/60)
	check(timed.exploded, "fuse detonates at 1.6 seconds")
	timed.free()
	# Bosses and summoned enemies take the neutral route without a room reward.
	var boss := Enemy.new()
	boss.game=game;boss.kind="boss";boss.boss_id=98765;boss.position=Vector2(1800,300)
	boss.spawn_id="dynamite_boss"
	boss.arena=Rect2(1500,0,1000,512)
	game.world.add_child(boss);boss.set_physics_process(false)
	var summon := extra_enemy("dynamite_blast_summon",-1,"flyer",true)
	summon.position=boss.position+Vector2(0,40)
	summon.hp=30
	var hp: int=boss.hp
	var stock: int=game.dynamite_stock
	var blast := Dynamite.new()
	blast.game=game;blast.position=boss.position
	game.projectiles.add_child(blast);blast.set_physics_process(false)
	blast.detonate()
	check(boss.hp==hp-T.DYNAMITE_DAMAGE and summon.hp==30-T.DYNAMITE_DAMAGE, "neutral blast damages boss and summoned enemy")
	check(game.dynamite_stock==stock, "boss/summon blast does not award room stock")
	boss.dead=true # Avoid altering the real boss-cycle fixture when testing exclusion.
	boss.set_meta("defeated_by_player",true)
	game.claim_dynamite_room(boss)
	check(game.dynamite_stock==stock, "boss defeat is excluded from room claim")
	boss.free();summon.free();blast.free()
	# Exercise the actual normal and guided projectile paths for the last kill.
	for guided in [false,true]:
		game.dynamite_stock=0
		var chamber := 920+(1 if guided else 0)
		var a := extra_enemy("dynamite_shot_a_%s" % guided,chamber)
		var b := extra_enemy("dynamite_shot_b_%s" % guided,chamber)
		kill(a)
		b.position=Vector2(2000,200);b.hp=1;b.polarity=1
		player.position=Vector2(1900,200);player.polarity=0
		await frames(2)
		var bullet: Node2D=game.spawn_bullet(player,Vector2.RIGHT,guided,b)
		for i in range(12): await frames()
		check(b.dead if is_instance_valid(b) else game.defeated_enemies.has("dynamite_shot_b_%s" % guided), "projectile kills last room member")
		check(game.dynamite_stock==1, "last normal/guided projectile awards dynamite")
		if is_instance_valid(bullet): bullet.free()
	# The dynamite itself is also a player kill and can complete a group.
	game.dynamite_stock=0
	var first := extra_enemy("dynamite_chain_a",930)
	var last := extra_enemy("dynamite_chain_b",930)
	first.position=Vector2(1800,200);last.position=Vector2(1820,200)
	blast=Dynamite.new();blast.game=game;blast.position=Vector2(1800,200)
	game.projectiles.add_child(blast);blast.set_physics_process(false)
	blast.detonate()
	check(game.dynamite_stock==1 and game.dynamite_claimed.has(Vector3i(0,0,930)), "dynamite final kill earns group reward")
	blast.free()
	# Clear room at capacity remains consumed even after spending stock.
	game.dynamite_stock=3
	first=extra_enemy("dynamite_full_a",931);last=extra_enemy("dynamite_full_b",931)
	kill(first);kill(last)
	game.dynamite_stock=0
	game.claim_dynamite_room(last)
	check(game.dynamite_stock==0 and game.dynamite_claimed.has(Vector3i(0,0,931)), "capacity claim cannot be collected after stock is spent")
	# Key input is buffered between physics ticks and consumed once.
	player.position=Vector2(1400,100);player.hp=100;player.invulnerability=0
	game.dynamite_stock=1
	var event := InputEventAction.new()
	event.action="dynamite";event.pressed=true
	player._unhandled_input(event)
	check(player.pending_dynamite, "short tool tap is buffered")
	player._physics_process(1.0/60)
	check(not player.pending_dynamite and game.dynamite_stock==0, "buffered throw consumes exactly one stock")
	for child in game.projectiles.get_children(): child.free()
	game.ui.update_hud()
	check(game.ui.dynamite_label.text=="ダイナマイト 0/3" and game.ui.controls_label.text.contains("G ダイナマイト"), "HUD and controls show stock and live key")

func map_tests() -> void:
	# Both map controls draw the same sector image, with independent texture caches.
	game.explored_cells.clear()
	game.explored_by_sector.clear()
	game.explored_geometry.clear()
	game.explored_images.clear()
	game.map_sector_revisions.clear()
	var at := Vector2i.RIGHT
	var unknown := Vector2i(47,6)
	game.explored_by_sector[at] = {}
	for key in [Vector2i(46,5), Vector2i(46,6), Vector2i(47,5)]:
		game.explored_cells[key] = true
		game.explored_by_sector[at][key] = true
		game.record_map_cell(key)
	game.player.position = Vector2(6000,300)
	game._update_camera(0,true)
	var mini: Control = game.ui.minimap
	var large: Control = game.ui.large_map
	mini.clear_cache()
	large.clear_cache()
	mini.update_map()
	large.open()
	await frames(2)
	var image: Image = game.explored_images[at]
	var before: Image = image.duplicate()
	var revision: int = game.map_sector_revisions[at]
	var geometry: String = str(game.explored_geometry)
	for map in [mini,large]:
		check(map._textures.has(at) and map._versions.get(at) == revision, "map draw primes sector texture cache")
	var removed: Array[Vector2i] = game.terrain.dynamite_explode(Vector2(6000,784))
	game.refresh_dynamite_map(removed)
	mini.update_map()
	large.queue_redraw()
	await frames(2)
	check(str(game.explored_geometry) != geometry, "blast changes explored geometry fragments")
	check(game.map_sector_revisions[at] > revision, "blast invalidates explored sector image")
	var known_removed := 0
	var unknown_removed := 0
	for cell: Vector2i in removed:
		var key := Vector2i(floori(float(cell.x)*T.TILE_SIZE/T.MAP_CELL_SIZE), floori(float(cell.y)*T.TILE_SIZE/T.MAP_CELL_SIZE))
		var pixel := cell-at*Vector2i(T.SECTOR_SIZE/T.TILE_SIZE)
		if key == unknown:
			unknown_removed += 1
			check(image.get_pixelv(pixel).a == 0, "unexplored blast pixel stays hidden")
		else:
			known_removed += 1
			check(image.get_pixelv(pixel) != before.get_pixelv(pixel), "explored destroyed rock changes drawn image pixel")
	check(known_removed > 0 and unknown_removed > 0, "map blast covers explored and unexplored cells")
	check(not game.explored_cells.has(unknown) and not game.explored_geometry.has(unknown), "blast never reveals unexplored map cell")
	var outside := Vector2i(190,21)-at*Vector2i(T.SECTOR_SIZE/T.TILE_SIZE)
	check(image.get_pixelv(outside) == before.get_pixelv(outside), "surviving mapped rock keeps its image pixel")
	for map in [mini,large]:
		check(map._textures.has(at) and map._versions.get(at) == game.map_sector_revisions[at], "minimap/large map draw updates cached texture to excavated image")
	large.hide()

func origin_shift_tests() -> void:
	# Use the same game-level, physics-priority recenter path as origin_shift_test.
	game.start_run(37)
	freeze()
	game.stream.shutdown()
	for at: Vector2i in game.stream.loaded.keys(): game.stream._unload(at)
	var at := Vector2i(2,2)
	var base := Vector2(at)*T.SECTOR_SIZE
	var p := payload(at)
	p.data.bounds = Rect2(base,T.SECTOR_SIZE)
	for key in ["spawns","hearts","loot","merchants","detours","optional_surfaces","erodible_surfaces","chambers","tunnels","shafts","landmarks","biomes"]:
		p.data[key] = []
	game.terrain.begin_sector(p)
	while not game.terrain.build_step(): pass
	game.stream.loaded[at] = p.data
	game.stream.center = at
	game.stream._refresh_stage()
	game.player.position = base+Vector2(1500,200)
	game._update_camera(0,true)
	var center := base+Vector2(2048,768)
	await frames(2)
	check(point_solid(center), "origin fixture begins with deep physical rock")
	var removed: Array[Vector2i] = game.terrain.dynamite_explode(center)
	await frames(2)
	var stick := Dynamite.new()
	stick.game = game
	stick.position = base+Vector2(1400,200)
	stick.velocity = Vector2(300,-260)
	game.projectiles.add_child(stick)
	stick.set_physics_process(false)
	stick._physics_process(1.0/60)
	var position: Vector2 = stick.position
	var velocity: Vector2 = stick.velocity
	var elapsed: float = stick.elapsed
	var stable: Dictionary = game.stable_point(position)
	var probe := RecenterProbe.new()
	probe.game = game
	probe.process_physics_priority = -100
	game.add_child(probe)
	await frames()
	check(probe.delta == -base and game.origin_sector == at, "game recenters automatically at two sectors")
	check(stick.position == position-base and game.stable_point(stick.position) == stable, "in-flight dynamite retains stable world position through recenter")
	check(stick.velocity == velocity and stick.elapsed == elapsed and not stick.exploded, "recenter preserves flying dynamite velocity and fuse")
	for cell: Vector2i in removed:
		check(not game.terrain.occupied.has(cell) and not point_solid(game.terrain.pixel_of_cell(cell)+Vector2(16,16)), "game origin shift preserves every excavated cell and collision")
	check(point_solid(Vector2(2160,784)), "game origin shift retains adjacent rock collision")
	stick._physics_process(1.0/60)
	await frames()
	check(stick.position.is_equal_approx(position-base+(velocity+Vector2(0,T.DYNAMITE_GRAVITY/60))*1.0/60), "flying dynamite continues correct trajectory after recenter")
	check(game.loaded_contains(stick.position), "shifted dynamite stays in the same loaded sector")
	stick.free()
	probe.free()
	var again := Vector2(2560,768)
	var shifted_removed: Array[Vector2i] = game.terrain.dynamite_explode(again)
	await frames(2)
	check(shifted_removed.size()>10, "game recentered blast removes deep rock")
	for cell: Vector2i in shifted_removed:
		check(not game.terrain.occupied.has(cell) and not point_solid(game.terrain.pixel_of_cell(cell)+Vector2(16,16)), "post-recenter blast matches removed cells and physical holes")
	for point in [Vector2(2160,784),Vector2(2672,784),Vector2(2400,784)]:
		check(game.terrain.occupied.has(game.terrain.cell_at(point)) and point_solid(point), "post-recenter explosions retain surrounding rock collision")

func run() -> void:
	began=Time.get_ticks_msec()
	_test_deadline_ms=began+120000
	game=Main.new()
	game.controls_path="user://dynamite_test_no_controls.cfg"
	root.add_child(game)
	game.start_run(37)
	freeze()
	await acquisition()
	await terrain_tests()
	await throwing_and_damage()
	await additional_tests()
	await map_tests()
	await origin_shift_tests()
	# Real death and retry create a clean run and stock.
	game.dynamite_stock=3
	game.player.invulnerability=0
	game.player.receive_neutral_hit(99999)
	await frames(2)
	check(game.dynamite_stock==0 and game.dynamite_claimed.is_empty() and game.state=="lost", "death clears stock and claims")
	game.primary_action()
	freeze()
	check(game.dynamite_stock==0 and game.dynamite_claimed.is_empty(), "retry starts empty")
	game.start_tutorial()
	var practice: Node2D=game.tutorial_session
	practice.dynamite_stock=2
	check(not practice.player.throw_dynamite() and practice.dynamite_stock==2, "practice rejects dynamite")
	check(not practice.ui.dynamite_label.visible and not practice.ui.controls_label.text.contains("ダイナマイト"), "practice hides disabled tool")
	game.free()
	var result := {"checks":checks,"failures":failures,"blast_ms":blast_ms,"elapsed_ms":Time.get_ticks_msec()-began}
	DirAccess.make_dir_recursive_absolute("res://builds/qa/dynamite")
	FileAccess.open("res://builds/qa/dynamite/dynamite-results.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("DYNAMITE: %d checks, %d failures; blast %.3f ms; elapsed %d ms" % [checks,failures.size(),blast_ms,result.elapsed_ms])
	quit(0 if failures.is_empty() else 1)
