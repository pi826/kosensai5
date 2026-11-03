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
				if edge.type not in ["diagonal", "tunnel"] or Metrics.shape(edge)=="flat_tunnel": continue
				var points: Array = edge.pieces.map(func(p): return Vector2(p.get_center().x,p.end.y-22))
				var angle := Metrics.angle(edge)
				var bucket := (0 if angle < 29 else (1 if angle < 33 else 2)) if edge.type=="diagonal" else (0 if angle < 10 else (1 if angle < 18 else 2))
				var key: String = "%s_%d" % [edge.type,bucket]
				if not fixtures.has(key): fixtures[key] = {"sector":s,"points":points,"type":edge.type,"angle":angle}
			if fixtures.size()==6: break
		if fixtures.size()==6: break
	check(fixtures.size()==6,"diagonal and gentle floors, three angle bands each")
	# Traverse the new gate side exits themselves with the same real-input driver.
	for seed_value in [0,1,37]:
		var s := S.generate(seed_value,Vector2i.ZERO)
		for n: Dictionary in s.connection_nodes:
			if n.get("vertical_gate_x",[]).is_empty(): continue
			var side := "top_exit" if n.rect.position.y < 512 else "bottom_exit"
			if fixtures.has(side): continue
			for edge: Dictionary in s.connections:
				if n.id not in [edge.a,edge.b] or edge.type not in ["shaft","elbow"]: continue
				var column: Rect2 = edge.rect if edge.type=="shaft" else edge.shaft
				var x: float = n.vertical_gate_x[0]+128
				var points: Array = [Vector2(x,(96 if side=="top_exit" else 3040)-22)]
				if edge.type=="elbow":
					var treads: Array = edge.pieces.map(func(p): return Vector2(p.get_center().x,p.end.y-22))
					if points[0].distance_to(treads[-1])<points[0].distance_to(treads[0]): treads.reverse()
					points.append_array(treads)
				else:
					points.append(Vector2(column.get_center().x,n.rect.end.y-22))
				fixtures[side]={"sector":s,"points":points,"type":side,"angle":0.0}
				break
	check(fixtures.has("top_exit") and fixtures.has("bottom_exit"),"both vertical gate side exits represented")
	for seed_value in [0,1,37,2026,12,71]:
		for at: Vector2i in [Vector2i.ZERO,Vector2i(1,0),Vector2i(-1,1)]:
			var s := S.generate(seed_value,at)
			for edge: Dictionary in s.connections:
				var kind := "elbow_leg" if edge.get("gentle_leg",false) else ""
				if kind.is_empty() or fixtures.has(kind): continue
				fixtures[kind]={"sector":s,"points":edge.pieces.map(func(p): return Vector2(p.get_center().x,p.end.y-22)),"type":kind,"angle":0.0}
			if fixtures.has("elbow_leg"): break
		if fixtures.has("elbow_leg"): break
	check(fixtures.has("elbow_leg"),"stepped elbow branches represented")
	var corner := S.generate(24,Vector2i(2,2))
	fixtures.corner_step={"sector":corner,"points":[Vector2(64,2506),Vector2(224,2538)],"type":"corner_step","angle":0.0}
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
				check(game.player.abilities==0 and not game.player.air_dash_used,"initial abilities only")
				reports.append({"type":fixture.type,"seed":s.seed,"coord":str(s.coord),"angle":fixture.angle,"damaged":damaged,"returning":returning,"passed":ok,"frames":driver.frames,"jumps":driver.jumps})
				if not ok: break
			driver.release()
	if is_instance_valid(game): game.free()
	DirAccess.make_dir_recursive_absolute("res://builds/qa/shafts")
	FileAccess.open("res://builds/qa/shafts/physics-results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"runs":reports},"\t"))
	print("DIAGONAL PHYSICS: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
