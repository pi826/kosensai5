extends SceneTree
const S := preload("res://scripts/sector_generator.gd")
const G := preload("res://scripts/stage_generator.gd")
const T := preload("res://scripts/tuning.gd")
var checks := 0
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: ",message)
func run():
	var geometries := {}
	var enemy_layouts := {}
	var block_layouts := {}
	var samples: Array[float] = []
	var fallbacks := 0
	for value in range(1000):
		var coord := Vector2i(value % 7 - 3, (value / 7) % 7 - 3)
		if value % 5 == 0: coord = Vector2i.ZERO
		var begin := Time.get_ticks_usec()
		var s := S.generate(value,coord)
		samples.append((Time.get_ticks_usec()-begin)/1000.0)
		check(S.validate(s).is_empty(),"independent geometry validation seed %d" % value)
		check(S.signature(s)==S.signature(S.generate(value,coord)),"deterministic seed %d" % value)
		check(not s.has("rooms") and not s.has("doors"),"single continuous geometry")
		geometries[str(s.solids)]=true
		enemy_layouts[str(s.spawns.map(func(e):return e.position))]=true
		block_layouts[str(s.breakables)]=true
		fallbacks += int(s.fallback)
		for damaged in [false,true]:
			var terrain := s.duplicate(false)
			terrain.solids = s.solids + s.breakables
			var graph := G.navigation_graph(terrain,damaged)
			check(G.connectivity_errors(s,damaged,graph).is_empty(),"every standing surface returns after excavation=%s" % damaged)
			check(S.gate_positions(s).all(func(p): return G.node_at(graph,p)>=0),"all gate landing points present")
		for spawn: Dictionary in s.spawns:
			check(spawn.kind=="boss" or G.has_attack_sight(spawn,s),"actual attack trajectory has a visible approach")
		if value%100==0: print("GENERATION PROGRESS ",value)
	check(geometries.size()==1000 and enemy_layouts.size()==1000 and block_layouts.size()==1000,"1000 distinct geometry enemy and block layouts")
	check(fallbacks==0,"zero ordinary fallback")
	var original := S.generate(37,Vector2i.ZERO)
	for mutate in ["unreachable","headroom","sight","safety","rock","protection","identity","patrol","region","kind","block","gate"]:
		var bad := original.duplicate(true)
		match mutate:
			"unreachable": bad.solids.append(Rect2(32,256,512,16))
			"headroom":
				var shelf: Rect2 = bad.solids.filter(func(r):return r.size.y==16)[0]
				bad.solids.append(Rect2(shelf.position-Vector2(0,32),Vector2(shelf.size.x,32)))
			"sight":
				var e: Dictionary = bad.spawns.filter(func(e):return e.kind=="turret")[0]
				bad.chambers[e.chamber_id].approaches=[Vector2(32,32)]
			"safety": bad.spawns[0].position=T.SECTOR_START
			"rock": bad.solids=G.subtract_rects(bad.solids,[Rect2(0,0,32,32)])
			"protection": bad.protected_rects=[]
			"identity": bad.spawns[1].id=bad.spawns[0].id
			"patrol": bad.spawns[0].patrol=Vector2(32,4000)
			"region": bad.biomes=[]
			"kind": bad.spawns=bad.spawns.filter(func(e):return e.kind!="builder")
			"block": bad.breakables.append(Rect2(T.SECTOR_START,Vector2(96,96)))
			"gate": bad.gates[Vector2i.RIGHT][0].floor+=32
		check(not S.validate(bad).is_empty(),"reject corrupted "+mutate)
		check(S.signature(original)!=S.signature(bad),"signature covers "+mutate)
	for kind in ["flyer","walker"]:
		var bad:=original.duplicate(true)
		bad.spawns.filter(func(e):return e.kind==kind)[0].patrol=Vector2(32,4000)
		check(not S.validate(bad).is_empty(),"reject explicit "+kind+" patrol")
	for at in S.guardian_sectors(37):
		var s:=S.generate(37,at)
		var bad:=s.duplicate(true)
		bad.landmarks[0].position.x+=32
		check(not S.validate(bad).is_empty(),"reject mismatched guardian landmark")
		var fallback:=S.generate_fallback(37,at)
		check(S.validate(fallback).is_empty(),"canonical per-sector fallback verified")
	DirAccess.make_dir_recursive_absolute("res://builds/qa/streaming")
	var report:={"checks":checks,"failures":failures,"seeds":1000,"fallbacks":fallbacks,"mean_ms":samples.reduce(func(a,b):return a+b,0.0)/samples.size(),"max_ms":samples.max()}
	FileAccess.open("res://builds/qa/streaming/generation_results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("SECTOR GENERATION ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
