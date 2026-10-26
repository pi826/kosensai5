extends SceneTree
const Main := preload("res://scripts/main.gd")
const G := preload("res://scripts/stage_generator.gd")
const T := preload("res://scripts/tuning.gd")
const Driver := preload("res://tests/cave_driver.gd")
var game: Node2D
var checks := 0
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	checks+=1
	if not ok:
		failures.append(message)
		printerr("FAIL: ",message)
func frames(n: int = 1):
	for i in range(n):
		await physics_frame
		await process_frame
func quiet():
	for enemy in get_nodes_in_group("enemies"): enemy.set_physics_process(false)
func run():
	game=Main.new()
	game.controls_path="res://builds/qa/caves/world_controls.cfg"
	root.add_child(game)
	game.key_bindings.reset_defaults()
	game.start_run(37)
	quiet()
	var driver := Driver.new()
	driver.tree=self
	driver.game=game
	var world_id: int = game.world.get_instance_id()
	var fixture := Driver.shaft_fixture(game.stage)
	var shaft: Dictionary = fixture.shaft
	var x: float = fixture.x
	game.player.position=Vector2(x,shaft.rect.end.y-22)
	game.player.velocity=Vector2.ZERO
	game._update_camera(0,true)
	await driver.tick(4)
	for i in range(shaft.platforms.size()-1,-1,-1):
		var shelf: Rect2 = shaft.platforms[i]
		var command := {"action":"jump","position":Vector2(x,game.player.position.y),"target":Vector2(x,shelf.position.y-22)}
		check(await driver.step(command),"climb shaft to mouth: "+driver.error)
	check(absf(game.player.position.y+22-shaft.rect.position.y)<1,"stands on mouth lid from below")
	check(await driver.walk(shaft.rect.end.x+16) and await driver.walk(shaft.rect.position.x-16) and await driver.walk(x),"walks across mouth without falling")
	driver.input("move_down",true)
	var passed_shelves := 0
	var last_y: float = game.player.position.y
	# Allow the slower fall and a fresh drop through each overlapping shelf.
	var descent_frames := ceili(60 * (shaft.rect.size.y / T.MAX_FALL_SPEED + (shaft.platforms.size() + 1) * (T.MAX_FALL_SPEED / T.FALL_GRAVITY + T.DROP_THROUGH_MAX_TIME)))
	for i in range(descent_frames):
		await driver.tick()
		for shelf: Rect2 in shaft.platforms:
			if last_y+22<=shelf.position.y+1 and game.player.position.y+22>shelf.position.y+1: passed_shelves+=1
		last_y=game.player.position.y
		if game.player.is_on_floor() and game.player.position.y+22>shaft.rect.end.y-1: break
	driver.input("move_down",false)
	check(absf(game.player.position.y+22-shaft.rect.end.y)<1 and passed_shelves>=shaft.platforms.size(),"held down passes mouth and all overlapping shelves to bottom")
	var tunnel: Dictionary = game.stage.tunnels.filter(func(e):return game.stage.chambers[e.a].rect.end.y!=game.stage.chambers[e.b].rect.end.y)[0]
	var ar: Rect2 = game.stage.chambers[tunnel.a].rect
	var br: Rect2 = game.stage.chambers[tunnel.b].rect
	var a := Vector2(ar.end.x-32,ar.end.y-22)
	var b := Vector2(br.position.x+32,br.end.y-22)
	game.player.position=a
	game.player.velocity=Vector2.ZERO
	game._update_camera(0,true)
	await driver.tick(4)
	var graph := G.navigation_graph(game.stage)
	check(await driver.follow(G.path_steps(graph,G.node_at(graph,a),G.node_at(graph,b),b)),"different-height tunnel forward: "+driver.error)
	check(await driver.follow(G.path_steps(graph,G.node_at(graph,b),G.node_at(graph,a),a)),"different-height tunnel return: "+driver.error)
	check(game.world.get_instance_id()==world_id,"shaft and tunnel use original world")
	check(game.stage.spawns.all(func(s): return s.kind=="boss" or game.stage.chambers[s.chamber_id].kind=="normal"),"no ordinary enemies in start or boss chamber")
	driver.release()
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	quiet()
	var candidates: Array = game.stage.spawns.filter(func(s): return s.kind in ["turret","walker","shifter","builder"])
	check(candidates.size()>=10,"ten direct-shooting enemies available")
	for i in range(mini(10,candidates.size())):
		quiet()
		for bullet in game.projectiles.get_children(): bullet.free()
		var spawn: Dictionary = candidates[i]
		var witness := G.sight_witness(spawn,game.stage)
		var enemy = get_nodes_in_group("enemies").filter(func(e): return e.spawn_id==spawn.id)[0]
		enemy.position=witness.position
		enemy.velocity=Vector2.ZERO
		game.player.position=witness.target
		game.player.polarity=enemy.polarity
		game.player.hp=100
		game.player.gauge=0
		game.player.invulnerability=0
		game.camera.position=(game.player.position+enemy.position)/2-Vector2(0,160)
		enemy.was_visible=false
		enemy.wake_delay=T.ENEMY_WAKE_DELAY
		enemy.shot_clock=0
		enemy.set_physics_process(true)
		for tick in range(360):
			await frames()
			if game.player.gauge>0 or game.player.hp<100: break
		check(game.player.gauge>0 or game.player.hp<100,"actual enemy bullet reaches approach "+spawn.id+" "+spawn.kind)
		print("SIGHT PHYSICS ",spawn.id," ",spawn.kind," gauge=",game.player.gauge," hp=",game.player.hp)
	game.free()
	print("CAVE WORLD: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
