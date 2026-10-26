extends SceneTree
const Main := preload("res://scripts/main.gd")
const T := preload("res://scripts/tuning.gd")
const S := preload("res://scripts/sector_generator.gd")
const Driver := preload("res://tests/stream_driver.gd")
const Support := preload("res://tests/stream_test_support.gd")
const Enemy := preload("res://scripts/enemy.gd")
const G := preload("res://scripts/stage_generator.gd")
var game: Node2D
var driver: RefCounted
var checks := 0
var failures: Array[String] = []
var heights := {}
var gate_counts := {}
var crossings := 0
var samples: Array = []
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)
func setup(point: Vector2):
	driver.release()
	check(await Support.ready(self,game,point),"crossing viewport prepared before input")
	Support.release(self,game)
	await driver.tick(3)
func continuity_fixture(gate: Dictionary) -> Dictionary:
	var floor_y: float=gate.rect.end.y
	var x: float=gate.rect.position.x
	var surface: Rect2=game.stage.erodible_surfaces[0]
	game.terrain.explode(surface.get_center(),45)
	var wall: int=-1
	for area: Rect2 in game.stage.erodible_surfaces:
		for wx in range(int(area.position.x),int(area.end.x),32):
			wall=game.terrain.place_wall(Rect2(wx,area.position.y-96,32,96),123)
			if wall>=0: break
		if wall>=0: break
	check(wall>=0 and not game.terrain.destroyed_cells.is_empty(),"continuity fixture has a destroyed floor and installed wall")
	if wall<0: return {}
	var source:=Enemy.new()
	source.game=game
	source.kind="laser"
	source.position=Vector2(x+280,floor_y-22)
	source.patrol=Vector2(source.position.x,source.position.x)
	source.spawn_id="seam_laser_fixture"
	game.world.add_child(source)
	var warning=game.spawn_laser(source)
	var active=game.spawn_laser(source)
	for beam in [warning,active]:
		beam.build_curve(Vector2(x+300,floor_y-64),Vector2(x+380,floor_y-64),1)
		beam.clip_path()
	active.fire()
	var flyer:=Enemy.new()
	flyer.game=game
	flyer.kind="flyer"
	flyer.position=Vector2(x+180,floor_y-112)
	flyer.patrol=Vector2(x+96,x+256)
	flyer.spawn_id="seam_flyer_fixture"
	game.world.add_child(flyer)
	flyer.hp=1
	flyer.gauge=3
	flyer.shot_clock=100
	driver.live_enemies=[flyer]
	var room: Rect2=game.stage.chambers.filter(func(r):return r.kind=="start")[0].rect
	var bomb_x:=room.get_center().x
	for candidate in range(int(room.position.x)+64,int(room.end.x)-64,32):
		if not G._any_intersects(game.stage.solids+game.stage.breakables,Rect2(candidate-2,room.end.y-128,4,128).grow(-0.1)):
			bomb_x=candidate
			break
	var bomb=game.spawn_bomb_warning(source)
	bomb.fire()
	bomb.position=Vector2(bomb_x,room.end.y-64)
	bomb.velocity=Vector2(0,-250)
	game.show_damage(game.player.position,1)
	return {"destroyed":game.terrain.destroyed_cells.duplicate(),"wall":wall,"wall_remaining":game.terrain.walls[wall].remaining,"warning":warning,"active":active,"curve":warning.curve.duplicate(),"flyer":flyer,"flyer_position":flyer.position,"bomb":bomb,"bomb_position":bomb.position,"damage_sequence":game.effects.damage_sequence}
func horizontal(gate: Dictionary):
	var x: float = gate.rect.position.x
	var floor_y: float = gate.rect.end.y
	heights[gate.height]=true
	for direction in [1,-1]:
		await setup(Vector2(x-direction*96,floor_y-22))
		game.player.hp=88
		game.player.gauge=3
		game.player.homing_charges=T.HOMING_CHARGE_CAPACITY
		game.score=200
		var world_id: int=game.world.get_instance_id()
		var player_id: int=game.player.get_instance_id()
		var terrain_id: int=game.terrain.get_instance_id()
		var witness=get_nodes_in_group("enemies").filter(func(e):return not e.dead and e.get_parent()==game.world)[0]
		witness.hp=1
		witness.gauge=3
		var witness_id: int=witness.get_instance_id()
		var bullet=game.spawn_bullet(game.player,Vector2(direction,0))
		bullet.position=Vector2(x-direction*48,floor_y-64)
		var bullet_id: int=bullet.get_instance_id()
		var continuity: Dictionary=continuity_fixture(gate) if crossings==0 else {}
		Input.action_press("move_right" if direction>0 else "move_left")
		var max_height_error:=0.0
		var seam_speed:=0.0
		for i in range(40):
			var before: Vector2=game.player.position
			await driver.tick()
			max_height_error=maxf(max_height_error,absf(game.player.position.y-(floor_y-22)))
			if (before.x-x)*direction<=0 and (game.player.position.x-x)*direction>0: seam_speed=absf(game.player.velocity.x)
			if i==7: check(is_instance_valid(bullet) and bullet.get_instance_id()==bullet_id and (bullet.position.x-x)*direction>0,"actual projectile crosses horizontal seam with launch color")
			if i==7 and not continuity.is_empty():
				check(is_instance_valid(continuity.warning) and continuity.warning.phase=="warning" and continuity.warning.elapsed>0 and continuity.warning.curve==continuity.curve,"laser warning preserves its fixed curve and elapsed time across seam")
				check(is_instance_valid(continuity.active) and continuity.active.phase=="beam" and continuity.active.remaining<T.LASER_DURATION,"active irradiation continues across seam")
		driver.release()
		check((game.player.position.x-x)*direction>64,"real walking crosses gate in both directions")
		check(max_height_error<0.2 and absf(seam_speed-T.MOVE_SPEED)<0.1,"no floor gap height step or horizontal velocity loss at seam")
		check(game.world.get_instance_id()==world_id and game.player.get_instance_id()==player_id and game.terrain.get_instance_id()==terrain_id,"seam never replaces world player or terrain")
		check(is_instance_id_valid(witness_id) and witness.hp==1 and witness.gauge==3 and game.player.hp==88 and game.player.gauge==3 and game.player.homing_charges==T.HOMING_CHARGE_CAPACITY and game.score==200,"crossing preserves HP absorption meter homing stocks and enemy combat state")
		if not continuity.is_empty():
			check(game.terrain.destroyed_cells==continuity.destroyed,"seam preserves destroyed floor cells")
			check(game.terrain.walls.has(continuity.wall) and game.terrain.walls[continuity.wall].remaining<continuity.wall_remaining,"seam preserves installed wall and its lifetime")
			check(is_instance_valid(continuity.bomb) and continuity.bomb.phase=="flight" and continuity.bomb.position!=continuity.bomb_position,"offscreen bomb keeps flying through seam traversal")
			check(is_instance_valid(continuity.flyer) and continuity.flyer.hp==1 and continuity.flyer.gauge==3 and continuity.flyer.flight_clock>0 and continuity.flyer.position!=continuity.flyer_position,"live flyer retains HP gauge and flight phase across seam")
			check(game.effects.damage_sequence==continuity.damage_sequence and not game.effects.damage_numbers.is_empty(),"seam preserves damage effects")
			driver.live_enemies.clear()
			var before: Vector2=game.player.position
			driver.input("interact",true)
			driver.input("interact",false)
			await driver.tick()
			check(game.player.position.distance_to(before)<24 and game.world.get_instance_id()==world_id,"interaction cannot warp or regenerate the world")
		samples.append({"axis":"x","at":gate.rect.position,"direction":direction,"height_error":max_height_error,"speed":seam_speed})
		crossings+=1
func vertical(gate: Dictionary):
	var x: float=gate.rect.position.x+128
	var y: float=gate.rect.position.y
	await setup(Vector2(x,y-32-22))
	Input.action_press("move_down")
	var crossed:=false
	for i in range(80):
		await driver.tick()
		if game.player.position.y>y+24:
			Input.action_release("move_down")
			crossed=true
		if crossed and game.player.is_on_floor(): break
	check(crossed and absf(game.player.position.y-(y+96-22))<0.5,"held down crosses vertical seam and lands on canonical lower shelf")
	check(absf(game.player.position.x-x)<0.1,"vertical crossing never changes x")
	var bullet=game.spawn_bullet(game.player,Vector2.UP)
	bullet.position=Vector2(x,y+16)
	await driver.tick(2)
	check(is_instance_valid(bullet) and bullet.position.y<y,"actual upward projectile crosses vertical seam")
	driver.input("jump",true)
	var highest: float=game.player.position.y
	for i in range(45):
		await driver.tick()
		highest=minf(highest,game.player.position.y)
	driver.input("jump",false)
	await driver.tick(8)
	check(highest<y-22 and game.player.is_on_floor() and absf(game.player.position.y-(y-32-22))<0.5,"held normal jump crosses upward and lands on upper shelf")
	check(absf(game.player.position.x-x)<0.1,"upward seam has no sideways correction or warp")
	crossings+=2
	samples.append({"axis":"y","at":gate.rect.position,"highest":highest,"landed":game.player.position})
func run():
	DirAccess.make_dir_recursive_absolute("res://builds/qa/streaming")
	game=Main.new()
	game.controls_path="res://builds/qa/streaming/seam_controls.cfg"
	root.add_child(game)
	game.start_run(37)
	driver=Driver.new()
	driver.tree=self
	driver.game=game
	for at in [Vector2i(-1,-1),Vector2i.ZERO,Vector2i(1,1),Vector2i(-1,1),Vector2i(1,-1)]:
		for side in [Vector2i.RIGHT,Vector2i.DOWN]:
			var gates:=S.boundary_gates(37,at,side)
			gate_counts[gates.size()]=true
			for gate: Dictionary in gates:
				if side.x!=0: await horizontal(gate)
				else: await vertical(gate)
	check(heights.size()==4,"all horizontal gate heights 160 192 224 256 physically exercised")
	check(gate_counts.has(1) and gate_counts.has(2),"single and double openings exercised")
	check(driver.incomplete_views==0,"every crossing frame displays only completely ready sectors")
	check(driver.max_player_step<25 and driver.max_camera_step<32,"all seam movement and camera steps continuous")
	game.show_menu("paused")
	var before: Vector2=game.player.position
	var elapsed: float=game.elapsed
	Input.action_press("move_right")
	for i in range(20):
		await physics_frame
		await process_frame
	Input.action_release("move_right")
	check(game.player.position==before and game.elapsed==elapsed,"pause freezes world and clock")
	game.open_key_settings()
	for i in range(5):
		await physics_frame
		await process_frame
	check(game.player.position==before and game.elapsed==elapsed,"settings freezes world without regeneration")
	FileAccess.open("res://builds/qa/streaming/seam_results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"crossings":crossings,"samples":samples,"max_player_step":driver.max_player_step,"max_camera_step":driver.max_camera_step},"\t"))
	game.free()
	print("STREAM SEAMS: %d checks, %d failures, %d physical crossings" % [checks,failures.size(),crossings])
	quit(0 if failures.is_empty() else 1)
