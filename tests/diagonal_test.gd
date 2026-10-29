extends "res://tests/test_tree.gd"
const S := preload("res://scripts/sector_generator.gd")
const Metrics := preload("res://tests/diagonal_metrics.gd")
var count := 200
var label := "diagonal-metrics"
var checks := 0
var failures: Array[String] = []
var specimens := {}
func check(ok: bool, message: String):
	checks += 1
	if not ok: failures.append(message); printerr("FAIL: ",message)
func _initialize():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--samples="): count = arg.get_slice("=",1).to_int()
		if arg.begins_with("--label="): label = arg.get_slice("=",1)
	call_deferred("run")
func run():
	var times: Array = []
	var kinds := {}
	var shapes := {}
	var flat_lengths: Array = []
	var elevated := 0
	var diagonals := 0
	var stepped := 0
	var shaft_count := 0
	var gate_shafts := 0
	var fallback := 0
	var invalid := 0
	var angles := {}
	var fixtures: Array = []
	for seed_value in range(count):
		for at: Vector2i in [Vector2i.ZERO, Vector2i(1,0), Vector2i(-1,1), Vector2i(0,-1), Vector2i(2,2)]:
			test_progress()
			var start := Time.get_ticks_usec()
			var s := S.generate(seed_value, at)
			times.append((Time.get_ticks_usec()-start)/1000.0)
			fallback += int(s.fallback)
			var errors := S.validate(s)
			if not errors.is_empty():
				invalid += 1
				printerr("INVALID ",seed_value," ",at," ",errors)
			check(errors.is_empty(),"diagonal sector validates seed=%d coord=%s" % [seed_value,at])
			for edge: Dictionary in s.connections:
				if edge.type=="elbow" and edge.get("gentle_leg",false) and not specimens.has("elbow"): specimens.elbow={"sector":s,"index":s.connections.find(edge)}
				kinds[edge.type] = kinds.get(edge.type,0) + 1
				var shape := Metrics.shape(edge)
				shapes[shape] = shapes.get(shape,0)+1
				if shape in ["diagonal_steps","gentle_tunnel"]: stepped += 1
				if edge.type == "tunnel" and shape == "gentle_tunnel" and not specimens.has("tunnel"): specimens.tunnel = {"sector":s,"index":s.connections.find(edge)}
				if s.connection_nodes[edge.a].rect.end.y != s.connection_nodes[edge.b].rect.end.y: elevated += 1
				if shape.begins_with("diagonal"):
					if edge.type.begins_with("diagonal") and not specimens.has(edge.type): specimens[edge.type] = {"sector":s,"index":s.connections.find(edge)}
					diagonals += 1
					var angle := Metrics.angle(edge)
					var bucket := floori(angle / 5) * 5
					angles[bucket] = angles.get(bucket,0) + 1
					if fixtures.size() < 16: fixtures.append({"seed":seed_value,"x":at.x,"y":at.y,"edge":s.connections.find(edge),"angle":angle})
			for shaft: Dictionary in s.shafts:
				shaft_count += 1
				gate_shafts += int(shaft.gate)
			for tunnel: Dictionary in s.tunnels:
				var flat := 0.0
				var floor_y := INF
				for p: Rect2 in tunnel.pieces:
					if p.end.y == floor_y: flat += p.size.x
					else:
						if flat > 0: flat_lengths.append(flat)
						flat = p.size.x
					floor_y = p.end.y
				if flat > 0: flat_lengths.append(flat)
		if seed_value % 20 == 0: print("METRICS PROGRESS ",seed_value)
	flat_lengths.sort()
	var bins := {"<256":0,"256..511":0,"512..767":0,"768..1023":0,">=1024":0}
	for n: float in flat_lengths:
		bins["<256" if n<256 else ("256..511" if n<512 else ("512..767" if n<768 else ("768..1023" if n<1024 else ">=1024")))] += 1
	var total: int = kinds.values().reduce(func(a,b): return a+b,0)
	var report := {"seeds":count,"sectors":times.size(),"types":kinds,"shape_types":shapes,"diagonal_count":diagonals,"connections":total,"elevated":elevated,"diagonal_elevated_ratio":float(diagonals)/maxi(elevated,1),"shafts":shaft_count,"gate_shafts":gate_shafts,"flat_runs":flat_lengths.size(),"flat_length_bins":bins,"flat_p50":flat_lengths[flat_lengths.size()/2],"flat_p90":flat_lengths[int(flat_lengths.size()*.9)],"flat_max":flat_lengths.max(),"mean_ms":times.reduce(func(a,b): return a+b,0.0)/times.size(),"max_ms":times.max(),"fallbacks":fallback,"invalid":invalid,"angles":angles,"fixtures":fixtures}
	check(fallback==0,"no ordinary fallback")
	check(stepped*2>=elevated,"at least half of elevated connections have stepped floors")
	check(kinds.get("diagonal",0)>0 and kinds.get("diagonal_platforms",0)==0,"diagonal floors remain and platform chains are absent")
	check(angles.size()>=4,"varied angles")
	if FileAccess.file_exists("res://builds/qa/diagonal/before-metrics.json"):
		var before: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://builds/qa/diagonal/before-metrics.json"))
		if before.sectors==times.size():
			check(shaft_count<before.shafts*0.8,"at least 20 percent fewer shafts with identical inputs")
			check(bins["768..1023"]+bins[">=1024"]<(before.flat_length_bins["768..1023"]+before.flat_length_bins[">=1024"])*0.7,"at least 30 percent fewer long flat runs")
	for kind: String in specimens:
		for mutation: String in (["angle","step","width","ceiling","landing","mouth","protection","cross_room","cross_link"] if kind=="diagonal" else ["angle","step","width","ceiling","mouth","protection","cross_room","cross_link","rock_gap"]):
			var bad: Dictionary = specimens[kind].sector.duplicate(true)
			var edge: Dictionary = bad.connections[specimens[kind].index]
			match mutation:
				"angle":
					edge.pieces[-1].position.y+=1024
				"step":
						edge.pieces[1].position.y+=256 if kind=="diagonal" else 64
				"width": edge.pieces[1].size.x=16
				"ceiling": edge.pieces[1].size.y=32
				"landing":
					for i in range(1,edge.pieces.size()): edge.pieces[i].position.y=edge.pieces[0].position.y
				"mouth": edge.a=edge.b
				"protection": bad.protected_rects=[]
				"cross_room": bad.connection_nodes.append({"id":bad.connection_nodes.size(),"rect":edge.pieces[1]})
				"cross_link": bad.connections.append({"a":-1,"b":-2,"type":"shaft","rect":edge.pieces[1]})
				"rock_gap":
					var p: Rect2 = edge.pieces[-1] if edge.pieces[-1].end.y>=edge.pieces[0].end.y else edge.pieces[0]
					bad.connection_nodes.append({"id":bad.connection_nodes.size(),"rect":Rect2(p.position.x,p.end.y+32,p.size.x,32)})
			check(not S.diagonal_errors(bad).is_empty(),"reject %s %s" % [kind,mutation])
	report.checks=checks
	report.failures=failures
	DirAccess.make_dir_recursive_absolute("res://builds/qa/shafts")
	FileAccess.open("res://builds/qa/shafts/%s.json" % label,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("ROUTE METRICS ",JSON.stringify(report))
	print("DIAGONAL GENERATION: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if invalid==0 and failures.is_empty() else 1)
