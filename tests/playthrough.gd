extends SceneTree
const T := preload("res://scripts/tuning.gd")
const Main := preload("res://scripts/main.gd")
const G := preload("res://scripts/stage_generator.gd")
const Driver := preload("res://tests/cave_driver.gd")
var game: Node2D
var checks := 0
var failures: Array[String] = []
var reports: Array = []
func _initialize(): call_deferred("run")
func check(ok: bool, message: String) -> bool:
	checks+=1
	if not ok:
		failures.append(message)
		printerr("FAIL: ",message)
	return ok
func run_seed(value: int, damaged: bool = false) -> bool:
	var driver := Driver.new()
	driver.tree=self
	driver.game=game
	driver.release()
	game.start_run(value)
	var world_id: int = game.world.get_instance_id()
	var actor_ids: Array = get_nodes_in_group("enemies").map(func(e): return e.get_instance_id())
	var initial_blocks: Dictionary = game.terrain.breakables.duplicate(true)
	if damaged:
		for surface: Rect2 in game.stage.erodible_surfaces:
			for x in range(int(surface.position.x)+16,int(surface.end.x),32):
				for dy in [16,48]: game.terrain.explode(Vector2(x,surface.position.y+dy),17)
		check(game.terrain.destroyed_cells.size()>100,"actual excavation removes route floors")
	await driver.tick(3)
	var graph := G.navigation_graph(game.stage,damaged)
	var reached := 0
	var lowered_waypoints := 0
	for route: Dictionary in game.stage.routes:
		var end: Vector2 = route.points[-1]
		var outward: Array = route.outward
		var returning: Array = route.returning
		if damaged:
			outward=G.path_steps(graph,G.node_at(graph,game.stage.start_position),G.node_at(graph,end),end)
			returning=G.path_steps(graph,G.node_at(graph,end),G.node_at(graph,game.stage.start_position),game.stage.start_position)
			for command: Dictionary in outward+returning:
				if command.action=="walk" and game.stage.erodible_surfaces.any(func(s): return command.position.x>=s.position.x and command.position.x<=s.end.x and absf(command.position.y+22-s.position.y-64)<1): lowered_waypoints+=1
		if not check(await driver.follow(outward),"seed %d outward %d: %s" % [value,route.boss_id,driver.error]): return false
		check(game.player.position.distance_to(end)<8,"physically reached boss")
		check(game.discovered_bosses.has(route.boss_id),"boss marker discovered")
		if not check(await driver.follow(returning),"seed %d return %d: %s" % [value,route.boss_id,driver.error]): return false
		check(game.player.position.distance_to(game.stage.start_position)<8,"physically returned to start")
		check(game.world.get_instance_id()==world_id,"no regeneration")
		reached+=1
	if damaged:
		# Boss routes may only cross protected floors, so visit an excavated floor explicitly.
		var visit := eroded_visit(graph)
		check(not visit.is_empty(),"an excavated floor is reachable and returnable")
		if not visit.is_empty():
			if not check(await driver.follow(visit.outward),"excavated floor outward: %s" % driver.error): return false
			check(game.player.is_on_floor() and absf(game.player.position.y-visit.point.y)<2,"excavated route actually changes standing height by 64px")
			lowered_waypoints+=1
			if not check(await driver.follow(visit.returning),"excavated floor return: %s" % driver.error): return false
			check(game.player.position.distance_to(game.stage.start_position)<8,"returned from the excavated floor")
	for id in actor_ids: check(is_instance_id_valid(id),"original actor persists")
	check(game.terrain.breakables==initial_blocks,"blocks intact, no shooting required")
	check(game.defeated_bosses.is_empty() and game.defeated_enemies.is_empty() and game.player.hp==100,"navigation causes no damage or kills")
	check(driver.max_player_step<25 and driver.max_camera_step<32,"continuous physics and camera")
	check(game.ui.minimap.get_explored_cells().size()==game.explored_cells.size(),"only explored map cells")
	var report := {"seed":value,"damaged":damaged,"simulated_seconds":game.elapsed,"jumps":driver.jumps,"frames":driver.frames,"reached_and_returned":reached,"lowered_waypoints":lowered_waypoints,"max_player_step":driver.max_player_step,"max_camera_step":driver.max_camera_step}
	reports.append(report)
	print("CAVE TRAVERSAL: ",JSON.stringify(report))
	driver.release()
	return true
# The widest excavated floor reachable from the start and back, with walk/jump/drop steps both ways.
func eroded_visit(graph: Dictionary) -> Dictionary:
	var origin := G.node_at(graph,game.stage.start_position)
	var surfaces: Array = game.stage.erodible_surfaces.duplicate()
	surfaces.sort_custom(func(a,b): return a.size.x>b.size.x)
	for surface: Rect2 in surfaces:
		var point := Vector2(surface.get_center().x,surface.position.y+T.SURFACE_DEPTH-T.PLAYER_SIZE.y/2)
		var node := G.node_at(graph,point)
		if node<0: continue
		var outward := G.path_steps(graph,origin,node,point)
		var returning := G.path_steps(graph,node,origin,game.stage.start_position)
		if not outward.is_empty() and not returning.is_empty(): return {"point":point,"outward":outward,"returning":returning}
	return {}
func run():
	game=Main.new()
	game.controls_path="res://builds/qa/caves/traversal_controls.cfg"
	root.add_child(game)
	game.key_bindings.reset_defaults()
	for value in ([] if OS.get_cmdline_user_args().has("--damaged-only") else [1,37,2026]):
		if not await run_seed(value): break
	if failures.is_empty(): await run_seed(37,true)
	FileAccess.open("res://builds/qa/caves/traversal_results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"runs":reports},"\t"))
	game.free()
	print("CAVE PLAYTHROUGH: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
