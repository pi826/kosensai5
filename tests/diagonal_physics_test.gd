extends "res://tests/test_tree.gd"
const S := preload("res://scripts/sector_generator.gd")
const G := preload("res://scripts/stage_generator.gd")
const T := preload("res://scripts/tuning.gd")
const Physics := preload("res://tests/ability_physics_test.gd")
const Driver := preload("res://tests/cave_driver.gd")
const Metrics := preload("res://tests/diagonal_metrics.gd")
var checks := 0
var failures: Array[String] = []
var reports: Array = []
var game: Node2D
func _initialize(): call_deferred("run")
func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok: failures.append(message); printerr("FAIL: ",message)
	return ok
func run():
	var fixtures := {}
	for seed_value in [0,1,37,2026,12,71]:
		for at: Vector2i in [Vector2i.ZERO,Vector2i(1,0),Vector2i(-1,1)]:
			test_progress()
			var s := S.generate(seed_value,at)
			for edge: Dictionary in s.connections:
				if not edge.type.begins_with("diagonal"): continue
				var points: Array = edge.landings.map(func(p): return Vector2(p.get_center().x,p.position.y-22)) if edge.type=="diagonal_platforms" else edge.pieces.map(func(p): return Vector2(p.get_center().x,p.end.y-22))
				var angle := Metrics.angle(edge)
				var bucket := (0 if angle < 29 else (1 if angle < 33 else 2)) if edge.type=="diagonal" else (0 if angle < 40 else (1 if angle < 45 else 2))
				var key: String = "%s_%d" % [edge.type,bucket]
				if not fixtures.has(key): fixtures[key] = {"sector":s,"points":points,"type":edge.type,"angle":angle}
			if fixtures.size()==6: break
		if fixtures.size()==6: break
	check(fixtures.size()==6,"two route types, three angle bands each")
	for key: String in fixtures:
		var fixture: Dictionary = fixtures[key]
		var s: Dictionary = fixture.sector
		for damaged: bool in [false,true]:
			var terrain := s.duplicate(false)
			terrain.solids = (G.damaged_solids(s) if damaged else s.solids) + s.breakables
			var graph := G.navigation_graph(terrain)
			if is_instance_valid(game): game.free()
			game = Physics.Fixture.new()
			root.add_child(game)
			game.camera = Camera2D.new()
			game.add_child(game.camera)
			game.player.abilities = 0
			for rect: Rect2 in terrain.solids: Physics.add_fixture(game.world,rect,rect.size.y==16)
			var driver := Driver.new()
			driver.tree = self
			driver.game = game
			var points: Array = fixture.points.duplicate()
			game.player.position = points[0]
			game.player.velocity = Vector2.ZERO
			await driver.tick(4)
			for returning: bool in [false,true]:
				if returning: points.reverse()
				var ok := true
				for target: Vector2 in points.slice(1):
					var commands := G.path_steps(graph,G.node_at(graph,driver.point()),G.node_at(graph,target),target)
					if not check(not commands.is_empty(),"planned adjacent tread %s damaged=%s reverse=%s" % [key,damaged,returning]): ok=false; break
					if not await driver.follow(commands): ok=false; break
				check(ok,"actual input %s seed=%d coord=%s angle=%.1f damaged=%s reverse=%s: %s" % [key,s.seed,s.coord,fixture.angle,damaged,returning,driver.error])
				check(game.player.abilities==0 and not game.player.air_jump_used and not game.player.air_dash_used,"initial abilities only")
				reports.append({"type":fixture.type,"seed":s.seed,"coord":str(s.coord),"angle":fixture.angle,"damaged":damaged,"returning":returning,"passed":ok,"frames":driver.frames,"jumps":driver.jumps})
				if not ok: break
			driver.release()
	if is_instance_valid(game): game.free()
	DirAccess.make_dir_recursive_absolute("res://builds/qa/diagonal")
	FileAccess.open("res://builds/qa/diagonal/physics-results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"runs":reports},"\t"))
	print("DIAGONAL PHYSICS: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
