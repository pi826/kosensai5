extends "res://tests/test_tree.gd"
const V := preload("res://scripts/vertical_runs.gd")
const Metrics := preload("res://tests/diagonal_metrics.gd")
var S = preload("res://scripts/sector_generator.gd")
var before := false
var count := 200
var checks := 0
var failures: Array[String] = []
func check(ok: bool, message: String):
	checks += 1
	if not ok: failures.append(message); printerr("FAIL: ", message)
func _initialize():
	DirAccess.make_dir_recursive_absolute("res://builds/qa/shafts")
	for arg in OS.get_cmdline_user_args():
		if arg in ["--before", "--baseline"]: before = true
		if arg.begins_with("--samples="): count = arg.get_slice("=",1).to_int()
	if OS.get_cmdline_user_args().has("--before"): S = load("res://builds/qa/shafts/source-before/scripts/sector_generator.gd")
	call_deferred("run")
func distribution(values: Array) -> Dictionary:
	values.sort()
	if values.is_empty(): return {}
	return {"count":values.size(),"max":values[-1],"p50":values[values.size()/2],"p90":values[int(values.size()*.9)],"p95":values[int(values.size()*.95)],"p99":values[int(values.size()*.99)],"over_1024":values.filter(func(n): return n>1024).size(),"over_512":values.filter(func(n): return n>512).size()}
func gentle_distribution() -> Dictionary:
	return {"count":0,"rise_bins":[0,0,0,0],"angle_bins":[0,0,0],"angle_over_27":0}
func record_gentle(report: Dictionary, pieces: Array) -> void:
	if pieces.is_empty(): return
	var first: Rect2 = pieces[0]
	var last: Rect2 = pieces[-1]
	var rise := absf(last.end.y-first.end.y)
	var angle := rad_to_deg(atan2(rise,last.end.x-first.position.x))
	report.count += 1
	report.rise_bins[0 if rise<96 else (1 if rise<192 else (2 if rise<384 else 3))] += 1
	if angle>27: report.angle_over_27 += 1
	else: report.angle_bins[0 if angle<10 else (1 if angle<18 else 2)] += 1
func run():
	var times: Array = []
	var runs: Array = []
	var seam_runs: Array = []
	var gate_runs: Array = []
	var examples: Array = []
	var shapes := {}
	var kinds := {}
	var flats: Array = []
	var shafts := 0
	var gate_shafts := 0
	var elevated := 0
	var fallback := 0
	var invalid := 0
	var specimen := {}
	var slowest := {"ms":0.0}
	var column_height := 0.0
	var climbing_connections := 0
	var gentle := gentle_distribution()
	var elbow_gentle := gentle_distribution()
	for seed_value in range(count):
		var measurements := {}
		for at: Vector2i in [Vector2i.ZERO,Vector2i(1,0),Vector2i(-1,1),Vector2i(0,-1),Vector2i(2,2),Vector2i(1,1)]:
			test_progress()
			var start := Time.get_ticks_usec()
			var s: Dictionary = S.generate(seed_value, at)
			if specimen.is_empty(): specimen = s
			if at != Vector2i(1,1):
				var ms := (Time.get_ticks_usec()-start)/1000.0
				times.append(ms)
				if ms>slowest.ms: slowest={"ms":ms,"seed":seed_value,"coord":str(at)}
			var m := V.measure(s)
			measurements[at] = m
			if not before: check(V.errors(s,1024).is_empty(),"vertical limits seed=%d at=%s" % [seed_value,at])
			if at == Vector2i(1,1): continue
			fallback += int(s.fallback)
			if s.fallback: print("FALLBACK seed=",seed_value," coord=",at)
			var errors: Array = S.validate(s)
			invalid += int(not errors.is_empty())
			check(errors.is_empty(),"sector validates seed=%d at=%s %s" % [seed_value,at,errors])
			runs.append_array(m.runs)
			for side: Vector2i in m.gates:
				for g: Dictionary in m.gates[side]: gate_runs.append(g.length)
			for c: Dictionary in m.columns:
				column_height += c.column.size.y
				for r: Vector2 in c.runs:
					if r.y-r.x>1024 and examples.size()<20: examples.append({"seed":seed_value,"coord":str(at),"column":str(c.column),"run":str(r),"length":r.y-r.x})
			for edge: Dictionary in s.connections:
				kinds[edge.type] = kinds.get(edge.type,0)+1
				var shape := Metrics.shape(edge)
				shapes[shape] = shapes.get(shape,0)+1
				if edge.type in ["shaft","elbow"]: climbing_connections += 1
				if shape=="gentle_tunnel": record_gentle(gentle,edge.pieces)
				if edge.type=="elbow":
					# Exclude the flat landing inside the shaft from the horizontal leg.
					var leg: Array = []
					for p: Rect2 in edge.pieces:
						var shaft: Rect2 = edge.shaft
						if p.position.x<shaft.position.x: leg.append(Rect2(p.position,Vector2(minf(p.end.x,shaft.position.x)-p.position.x,p.size.y)))
						if p.end.x>shaft.end.x: leg.append(Rect2(maxf(p.position.x,shaft.end.x),p.position.y,p.end.x-maxf(p.position.x,shaft.end.x),p.size.y))
					record_gentle(elbow_gentle,leg)
				if s.connection_nodes[edge.a].rect.end.y != s.connection_nodes[edge.b].rect.end.y: elevated += 1
			shafts += s.shafts.size()
			gate_shafts += s.shafts.filter(func(q): return q.gate).size()
			for tunnel: Dictionary in s.tunnels:
				var flat := 0.0
				var previous := INF
				for p: Rect2 in tunnel.pieces:
					if p.end.y != previous:
						if flat>0: flats.append(flat)
						flat = 0
					flat += p.size.x
					previous = p.end.y
				if flat>0: flats.append(flat)
		for upper: Vector2i in [Vector2i(0,-1),Vector2i(1,0)]:
			for a: Dictionary in measurements[upper].gates[Vector2i.DOWN]:
				var matches: Array = measurements[upper+Vector2i.DOWN].gates[Vector2i.UP].filter(func(b): return b.x==a.x)
				check(matches.size()==1,"matching measured gate %d %s x=%d" % [seed_value,upper,a.x])
				if matches.size()==1:
					var length: float = a.length+matches[0].length
					seam_runs.append(length)
					if not before: check(length<=1024,"combined gate run seed=%d coord=%s length=%d" % [seed_value,upper,length])
		if seed_value%20==0: print("SHAFT PROGRESS ",seed_value)
	var stepped: int = shapes.get("diagonal_steps",0)+shapes.get("gentle_tunnel",0)
	var report := {"seeds":count,"sectors":times.size(),"invalid":invalid,"fallbacks":fallback,"types":kinds,"shapes":shapes,"elevated":elevated,"stepped_ratio":float(stepped)/maxi(elevated,1),"diagonal_ratio":float(shapes.get("diagonal_steps",0))/maxi(elevated,1),"shafts":shafts,"gate_shafts":gate_shafts,"vertical":distribution(runs),"gate_vertical":distribution(gate_runs),"seam_vertical":distribution(seam_runs),"long_examples":examples,"flat":distribution(flats),"flat_768":flats.filter(func(n): return n>=768).size(),"mean_ms":times.reduce(func(a,b): return a+b,0.0)/times.size(),"max_ms":times.max()}
	if not before:
		check(fallback==0,"no ordinary fallback")
		check(kinds.get("diagonal_platforms",0)==0,"no diagonal platform chains")
		check(stepped*2>=elevated,"half of elevated links have stepped floors")
		if count==200:
			check(kinds.get("shaft",0)<=2734,"straight shaft connections do not increase")
			check(report.flat_768<995*.7,"pre-7C long flat reduction preserved")
		var bad := {"bounds":Rect2(0,0,4096,3072),"shafts":[{"rect":Rect2(512,0,256,3072)}],"chambers":[],"tunnels":[],"entrances":[],"solids":[],"gates":{}}
		check(not V.errors(bad,1024).is_empty(),"reject synthetic uninterrupted shaft")
		bad.entrances=[{"rect":Rect2(512,800,768,192)}]
		bad.solids=[Rect2(768,992,512,2080)]
		check(V.measure(bad).columns[0].mouths.is_empty(),"a floored blind vestibule does not reset vertical run")
		bad.shafts=[{"rect":Rect2(512,0,256,800)}]
		bad.entrances=[]
		bad.gates={Vector2i.UP:[{"x":512,"width":256}]}
		check(V.errors(bad,1024).any(func(e): return e.begins_with("Vertical gate")),"half-limit enforced at vertical boundary")
		bad=specimen.duplicate(true)
		bad.shafts=[{"rect":Rect2(512,0,256,3072),"platforms":[],"gate":false}]
		bad.chambers=[]
		bad.tunnels=[]
		bad.entrances=[]
		check(S.validate(bad).any(func(e): return e.begins_with("Vertical")),"final validate rejects injected long column")
		var floor_fixture := {"tunnels":[{"pieces":[Rect2(0,32,64,160)]}],"solids":[Rect2(0,192,32,32),Rect2(0,224,64,64)]}
		S._bridge_floors(floor_fixture)
		var cell := Rect2(0,192,32,32)
		var area: float = floor_fixture.solids.reduce(func(sum,r): return sum+r.intersection(cell).get_area(),0.0)
		check(area==cell.get_area(),"floor repair never duplicates rock in an already supported boundary cell")
		var regression: Dictionary = S.generate(9,Vector2i(-2,-2))
		check(not regression.fallback and S.validate(regression).is_empty(),"seed 9 (-2,-2) keeps canonical boundary without ordinary fallback")
		regression = S.generate(78,Vector2i(1000,-1000))
		check(not regression.fallback and S.validate(regression).is_empty(),"seed 78 (1000,-1000) repairs undercut top gate without ordinary fallback")
	report.generation_ms=distribution(times)
	report.column_height_total=column_height
	report.climbing_connections=climbing_connections
	report.gentle_tunnel=gentle
	report.elbow_horizontal=elbow_gentle
	report.checks=checks
	report.slowest=slowest
	report.failures=failures
	FileAccess.open("res://builds/qa/shafts/%s-metrics.json" % ("before" if before else "after"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("SHAFT METRICS ",JSON.stringify(report))
	print("SHAFT TEST: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
