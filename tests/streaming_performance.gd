extends "res://tests/test_tree.gd"
const Main := preload("res://scripts/main.gd")
const S := preload("res://scripts/sector_generator.gd")
const T := preload("res://scripts/tuning.gd")
const O := preload("res://scripts/origin_shift.gd")
var checks := 0
var failures: Array[String] = []
class Walker extends CharacterBody2D:
	func _physics_process(delta: float):
		velocity=Vector2(320,3300*delta)
		move_and_slide()
func _initialize(): call_deferred("run")
func check(ok: bool,message: String):
	checks+=1
	if not ok:
		failures.append(message)
		printerr("FAIL: ",message)
func run():
	DirAccess.make_dir_recursive_absolute("res://builds/qa/streaming")
	var precision: Array=[]
	# The same scene-space experiment at each integer world origin. Recenter
	# halfway through the walk and compensate only for that exact translation.
	for origin in [Vector2i.ZERO,Vector2i(50,-20),Vector2i(100000,-50000),Vector2i(-100000,50000)]:
		var base := T.SECTOR_SIZE * 2
		var floor_body:=StaticBody2D.new()
		var floor_shape:=CollisionShape2D.new()
		var rectangle:=RectangleShape2D.new()
		rectangle.size=Vector2(4096,256)
		floor_shape.shape=rectangle
		floor_body.position=base+Vector2(1024,128)
		floor_body.add_child(floor_shape)
		root.add_child(floor_body)
		var walker:=Walker.new()
		var shape:=CollisionShape2D.new()
		var body:=RectangleShape2D.new()
		body.size=T.PLAYER_SIZE
		shape.shape=body
		walker.add_child(shape)
		walker.position=base+Vector2(128,-22)
		root.add_child(walker)
		var start: Vector2=walker.position
		var reference: Vector2i = origin
		var stable_start := O.point(start, reference)
		for i in range(120):
			if i == 60:
				floor_body.position -= base
				walker.position -= base
				reference += Vector2i(2,2)
				walker.reset_physics_interpolation()
			test_progress()
			await physics_frame
			test_progress()
			await process_frame
		var stable_end := O.point(walker.position, reference)
		var dx: float = float(stable_end.sector.x-stable_start.sector.x)*T.SECTOR_SIZE.x + float(stable_end.local.x)-float(stable_start.local.x)
		var sample:={"origin_sector":[origin.x,origin.y],"walk_120_frames_px":dx,"expected_px":640.0,"walk_error_percent":absf(dx-640)/640*100,"floor_error_px":absf(walker.position.y+22),"grounded":walker.is_on_floor(),"origin_shifts":1}
		precision.append(sample)
		check(walker.is_on_floor(),"recentered precision experiment lands at sector %s" % origin)
		check(absf(dx-640)<0.2 and sample.floor_error_px<0.2,"walking accuracy after recenter at sector %s" % origin)
		check(sample.walk_120_frames_px==precision[0].walk_120_frames_px and sample.floor_error_px==precision[0].floor_error_px,"far precision equals the near-origin reference")
		check(O.unpack(stable_start, reference).distance_to(start-base) < 0.001 and O.unpack(stable_end, reference).distance_to(walker.position) < 0.001,"sector-local positions preserve identities within 0.001px across recenter")
		walker.free()
		floor_body.free()
		test_progress()
		await process_frame
	var game:=Main.new()
	game.controls_path="res://builds/qa/streaming/performance_controls.cfg"
	root.add_child(game)
	var starts: Array=[]
	for value in [1,37,2026]:
		game.start_run(value)
		game.set_physics_process(false)
		game.player.set_physics_process(false)
		starts.append(game.last_start_metrics.duplicate())
		check(game.stream.loaded.size()==9,"benchmark starts with all nine ready sectors")
	var render_frames := OS.get_cmdline_user_args().has("--render-frames")
	if render_frames: DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var visible_started := Time.get_ticks_usec()
	game.start_run(37)
	var loop_three := OS.get_cmdline_user_args().has("--loop-three")
	if loop_three:
		game.set_physics_process(false)
		game.world.process_mode=Node.PROCESS_MODE_DISABLED
		var base_count := 0
		for data: Dictionary in game.stream.loaded.values():
			base_count += data.spawns.filter(func(e): return e.kind != "boss").size()
		# Finish offscreen additions before measuring, rather than waiting for
		# the deadline on candidates intentionally deferred beside the camera.
		game.camera.position=Vector2(-20000,-20000)
		game.boss_cycle.final_clears=T.FINAL_BOSS_CLEARS
		game.update_loop_scaling()
		var deadline := Time.get_ticks_msec()+30000
		while Time.get_ticks_msec()<deadline:
			game.stream._service_population_jobs()
			game.stream._service_population(Time.get_ticks_usec()+3000)
			if game.stream.population_jobs.is_empty() and game.stream.population_waiting.is_empty() and game.stream.population_queue.is_empty(): break
			test_progress()
			OS.delay_msec(1)
		check(game.stream.population_jobs.is_empty() and game.stream.population_waiting.is_empty() and game.stream.population_queue.is_empty(),"initial stage-three population and jobs complete within deadline")
		check(get_nodes_in_group("enemies").filter(func(e):return e.get_parent()==game.world and e.kind!="boss" and not e.dead).size()==base_count*T.LOOP_COUNT_CAP,"benchmark begins with full fourfold normal-enemy population")
		game.world.process_mode=Node.PROCESS_MODE_INHERIT
	game.set_physics_process(true)
	var gate: Dictionary = S.boundary_gates(37,Vector2i.ZERO,Vector2i.RIGHT)[0]
	game.player.position=Vector2(gate.rect.position.x-320,gate.rect.end.y-22)
	game._update_camera(0,true)
	var render_samples: Array[float] = []
	var slow_render_frames: Array = []
	var first_frame_ms := 0.0
	for frame in range(900):
		var frame_started := Time.get_ticks_usec()
		game.player.invulnerability=10000
		if frame%120==0:
			Input.action_release("move_left")
			Input.action_release("move_right")
			Input.action_press("move_right" if (frame/120)%2==0 else "move_left")
		test_progress()
		await physics_frame
		test_progress()
		await process_frame
		if render_frames:
			test_progress()
			await RenderingServer.frame_post_draw
			if frame==0: first_frame_ms=(Time.get_ticks_usec()-visible_started)/1000.0
			else:
				var work_ms := (Time.get_ticks_usec()-frame_started)/1000.0
				render_samples.append(work_ms)
				if work_ms > 16.7:
					slow_render_frames.append({"frame":frame,"work_ms":work_ms,"install_ms":game.stream.service_times[-1],"redraw_cpu_ms":game.terrain.redraw_service_ms,"estimated_draw_ms":game.terrain.redraw_estimated_ms,"physics_ms":game.physics_frame_times[-1]})
	Input.action_release("move_left")
	Input.action_release("move_right")
	check(game.stream.loaded.size()>9,"moving benchmark includes incremental loading")
	check(game.physics_frame_times.size()==900,"full physics frames measured after all actor callbacks")
	var frame_report:={"frames":game.physics_frame_times.size(),"main_mean_ms":game.frame_times.reduce(func(a,b):return a+b,0.0)/game.frame_times.size(),"main_max_ms":game.frame_times.max(),"physics_mean_ms":game.physics_frame_times.reduce(func(a,b):return a+b,0.0)/game.physics_frame_times.size(),"physics_max_ms":game.physics_frame_times.max(),"loaded_sectors":game.stream.loaded.size(),"hold_frames":game.stream.hold_frames}
	frame_report.loop_level=game.enemy_loop_level()
	frame_report.enemy_count=get_nodes_in_group("enemies").filter(func(e):return e.get_parent()==game.world and not e.dead).size()
	frame_report.worker_generation_mean_ms=game.stream.generation_times.reduce(func(a,b):return a+b,0.0)/game.stream.generation_times.size()
	frame_report.worker_generation_max_ms=game.stream.generation_times.max()
	if not game.stream.population_times.is_empty():
		frame_report.population_worker_mean_ms=game.stream.population_times.reduce(func(a,b):return a+b,0.0)/game.stream.population_times.size()
		frame_report.population_worker_max_ms=game.stream.population_times.max()
	if loop_three:
		check(frame_report.main_mean_ms<1000.0/60.0 and frame_report.physics_mean_ms<1000.0/60.0,"stage-three average frame processing stays within 60fps budget")
	if render_frames:
		frame_report.start_to_first_render_ms=first_frame_ms
		frame_report.visible_start_run_ms=game.last_start_metrics.start_run_ms
		frame_report.slow_render_frames=slow_render_frames
		frame_report.render_frame_mean_ms=render_samples.reduce(func(a,b):return a+b,0.0)/render_samples.size()
		frame_report.render_frame_max_ms=render_samples.max()
	var sorted_physics := game.physics_frame_times.duplicate()
	sorted_physics.sort()
	frame_report.physics_p95_ms = sorted_physics[int(sorted_physics.size()*0.95)]
	frame_report.physics_p99_ms = sorted_physics[int(sorted_physics.size()*0.99)]
	if is_instance_valid(game.audio): frame_report.audio = game.audio.measurements()
	game.free()
	var samples: Array[float]=[]
	for seed_value in range(200):
		var begin:=Time.get_ticks_usec()
		S.generate(seed_value,Vector2i(seed_value%5-2,(seed_value/5)%5-2))
		samples.append((Time.get_ticks_usec()-begin)/1000.0)
	for seed_value in [1,37,2026]:
		for y in range(-1,2):
			for x in range(-2,3):
				var begin:=Time.get_ticks_usec()
				S.generate(seed_value,Vector2i(x,y))
				samples.append((Time.get_ticks_usec()-begin)/1000.0)
	var report:={"checks":checks,"failures":failures,"precision":precision,"starts":starts,"frame_processing":frame_report,"generation_samples":samples.size(),"generation_mean_ms":samples.reduce(func(a,b):return a+b,0.0)/samples.size(),"generation_max_ms":samples.max(),"timings_ms":samples}
	FileAccess.open("res://builds/qa/streaming/"+("loop_three_" if loop_three else "")+("performance_render_results.json" if render_frames else "performance_results.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	report.erase("timings_ms")
	print("STREAM PERFORMANCE ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
