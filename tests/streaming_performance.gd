extends SceneTree
const Main := preload("res://scripts/main.gd")
const S := preload("res://scripts/sector_generator.gd")
const T := preload("res://scripts/tuning.gd")
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
	for offset in [0.0,204800.0,262144.0,1048576.0,4194304.0,8388608.0,16777216.0]:
		var floor_body:=StaticBody2D.new()
		var floor_shape:=CollisionShape2D.new()
		var rectangle:=RectangleShape2D.new()
		rectangle.size=Vector2(4096,256)
		floor_shape.shape=rectangle
		floor_body.position=Vector2(offset+1024,offset+128)
		floor_body.add_child(floor_shape)
		root.add_child(floor_body)
		var walker:=Walker.new()
		var shape:=CollisionShape2D.new()
		var body:=RectangleShape2D.new()
		body.size=T.PLAYER_SIZE
		shape.shape=body
		walker.add_child(shape)
		walker.position=Vector2(offset+128,offset-22)
		root.add_child(walker)
		var start: Vector2=walker.position
		for i in range(120):
			await physics_frame
			await process_frame
		var dx: float=walker.position.x-start.x
		var delta: float=Vector2(offset+0.1,0).x-offset
		var sample:={"offset_px":offset,"stored_0_1px":delta,"walk_120_frames_px":dx,"expected_px":640.0,"walk_error_percent":absf(dx-640)/640*100,"floor_error_px":absf(walker.position.y-(offset-22)),"grounded":walker.is_on_floor()}
		precision.append(sample)
		if offset<=1048576: check(walker.is_on_floor(),"float precision experiment lands at offset %.0f" % offset)
		if offset<=262144: check(absf(dx-640)<2 and absf(walker.position.y-(offset-22))<0.2,"practical walking accuracy at %.0f" % offset)
		walker.free()
		floor_body.free()
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
	game.set_physics_process(true)
	var gate: Dictionary = S.boundary_gates(37,Vector2i.ZERO,Vector2i.RIGHT)[0]
	game.player.position=Vector2(gate.rect.position.x-320,gate.rect.end.y-22)
	game._update_camera(0,true)
	var render_samples: Array[float] = []
	var first_frame_ms := 0.0
	for frame in range(900):
		var frame_started := Time.get_ticks_usec()
		game.player.invulnerability=10000
		if frame%120==0:
			Input.action_release("move_left")
			Input.action_release("move_right")
			Input.action_press("move_right" if (frame/120)%2==0 else "move_left")
		await physics_frame
		await process_frame
		if render_frames:
			await RenderingServer.frame_post_draw
			if frame==0: first_frame_ms=(Time.get_ticks_usec()-visible_started)/1000.0
			else: render_samples.append((Time.get_ticks_usec()-frame_started)/1000.0)
	Input.action_release("move_left")
	Input.action_release("move_right")
	check(game.stream.loaded.size()>9,"moving benchmark includes incremental loading")
	check(game.physics_frame_times.size()==900,"full physics frames measured after all actor callbacks")
	var frame_report:={"frames":game.physics_frame_times.size(),"main_mean_ms":game.frame_times.reduce(func(a,b):return a+b,0.0)/game.frame_times.size(),"main_max_ms":game.frame_times.max(),"physics_mean_ms":game.physics_frame_times.reduce(func(a,b):return a+b,0.0)/game.physics_frame_times.size(),"physics_max_ms":game.physics_frame_times.max(),"loaded_sectors":game.stream.loaded.size(),"hold_frames":game.stream.hold_frames}
	if render_frames:
		frame_report.start_to_first_render_ms=first_frame_ms
		frame_report.render_frame_mean_ms=render_samples.reduce(func(a,b):return a+b,0.0)/render_samples.size()
		frame_report.render_frame_max_ms=render_samples.max()
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
	FileAccess.open("res://builds/qa/streaming/"+("performance_render_results.json" if render_frames else "performance_results.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	report.erase("timings_ms")
	print("STREAM PERFORMANCE ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
