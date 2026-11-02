extends "res://tests/test_tree.gd"
## Real-machine return benchmark; run with bench.cmd and paste the final table.
const Main := preload("res://scripts/main.gd")
const T := preload("res://scripts/tuning.gd")
const Art := preload("res://scripts/sprite_art.gd")
var prof = null
var game: Node
var clock_sink := 0.0
var bench_started_msec := 0

func _initialize(): call_deferred("run")

func tick() -> void:
	test_progress()
	await physics_frame
	test_progress()
	await process_frame
	test_progress()
	await RenderingServer.frame_post_draw

func monitors() -> Dictionary:
	var enemies := 0
	var awake := 0
	for actor in get_nodes_in_group("enemies"):
		enemies += 1
		if actor.was_visible: awake += 1
	return {
		"loaded":game.stream.loaded.size(),"enemies":enemies,"visible_enemies":awake,
		"hearts":get_nodes_in_group("hearts").size(),"loot":get_nodes_in_group("loot").size(),
		"nodes":int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"objects":int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"static_mb":snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
		"video_mb":snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"draw_calls":int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"primitives":int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"render_objects":int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"chunks":game.terrain.draw_chunks.size(),"pending":game.terrain.pending_redraw.size(),
		"bodies":game.terrain.collision_body_count(),
		"active_physics":int(Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS)),
		"pairs":int(Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)),
		"explored":game.explored_cells.size(),"missing":game.stream.missing.size(),
		"audio_players":get_nodes_in_group("audio").size(),
	}

func gather_enemies(count: int) -> Array:
	# Brings the nearest ordinary enemies into view and keeps them alive for a steady fight.
	var candidates: Array = []
	for actor in get_nodes_in_group("enemies"):
		if actor.get_parent() == game.world and actor.kind != "boss" and not actor.dead: candidates.append(actor)
	candidates.sort_custom(func(a, b): return a.position.distance_squared_to(game.player.position) < b.position.distance_squared_to(game.player.position))
	var saved: Array = []
	var used := mini(count, candidates.size())
	for index in range(used):
		var actor = candidates[index]
		saved.append({"actor":actor,"position":actor.position,"hp":actor.hp,"max_hp":actor.max_hp,
			"flight_center_y":actor.flight_center_y,"patrol":actor.patrol})
		actor.hp = 100000
		actor.max_hp = 100000
		actor.position = game.player.position + Vector2(-540 + (index % 12) * 95, -180 - (index % 3) * 60)
		actor.flight_center_y = actor.position.y
		actor.patrol = Vector2(actor.position.x - 160, actor.position.x + 160)
	return saved

func fight_frame(frame: int) -> void:
	game.player.invulnerability = 100000
	if frame % 60 == 0:
		Input.action_release("move_left")
		Input.action_release("move_right")
		Input.action_press("move_right" if (frame / 60) % 2 == 0 else "move_left")
	if frame % 45 == 0:
		Input.action_press("jump")
	elif frame % 45 == 12:
		Input.action_release("jump")

func combat(label: String, count: int, report: Dictionary) -> void:
	game.player.set_physics_process(true)
	game.player.velocity = Vector2.ZERO
	game._update_camera(0, true)
	var saved := gather_enemies(count)
	Input.action_press("shoot")
	for i in range(60): await tick()
	await measure(label, 600, report, fight_frame)
	Input.action_release("shoot")
	Input.action_release("move_left")
	Input.action_release("move_right")
	Input.action_release("jump")
	for state: Dictionary in saved:
		var actor = state.actor
		if is_instance_valid(actor) and not actor.dead:
			actor.position = state.position
			actor.hp = state.hp
			actor.max_hp = state.max_hp
			actor.flight_center_y = state.flight_center_y
			actor.patrol = state.patrol
			actor.velocity = Vector2.ZERO
	report[label].fighters = saved.size()
	report[label].bullets = game.projectiles.get_child_count()

func clock_probe() -> float:
	var best := INF
	for repeat in range(5):
		var began := Time.get_ticks_usec()
		var x := 0.0
		for i in range(100000): x += sin(float(i) * 0.001)
		clock_sink += x
		best = minf(best, (Time.get_ticks_usec() - began) / 1000.0)
	return best

func measure(label: String, frames: int, report: Dictionary, each_frame: Callable = Callable()) -> void:
	if prof != null: prof.clear()
	var samples: Array[float] = []
	var process_ms := 0.0
	var physics_ms := 0.0
	var render_cpu := 0.0
	var render_gpu := 0.0
	var vp := root.get_viewport_rid()
	for frame in range(frames):
		if each_frame.is_valid(): each_frame.call(frame)
		var began := Time.get_ticks_usec()
		await tick()
		samples.append((Time.get_ticks_usec() - began) / 1000.0)
		process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		physics_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		render_cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
		render_gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0.0
	for value: float in samples: total += value
	var entry := {"mean":total / frames,"p50":sorted[frames / 2],"p95":sorted[int(frames * 0.95)],"max":sorted[-1],
		"process":process_ms / frames,"physics":physics_ms / frames,"render_cpu":render_cpu / frames,"render_gpu":render_gpu / frames}
	entry.merge(monitors())
	entry.clock = clock_probe()
	entry.elapsed_s = (Time.get_ticks_msec() - bench_started_msec) / 1000.0
	report[label] = entry
	print("PHASE ", label, " ", JSON.stringify(entry))
	if prof != null: prof.report(frames)

func travel(offset: Vector2, speed: float) -> void:
	var left := offset.length()
	var step := offset.normalized() * speed / 60.0
	game.player.set_physics_process(false)
	game.player.invulnerability = 100000
	while left > 0.0:
		if not game.streaming_wait:
			game.player.position += step
			game.player.velocity = step * 60.0
			left -= step.length()
		await tick()
	game.player.velocity = Vector2.ZERO

func run():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://builds/qa/perf"))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	print("BENCH_ENV cpu=%s gpu=%s driver=%s window=%s refresh=%.1f screen=%s threads=%d" % [OS.get_processor_name(), RenderingServer.get_video_adapter_name(), RenderingServer.get_current_rendering_driver_name(), str(DisplayServer.window_get_size()), DisplayServer.screen_get_refresh_rate(), str(DisplayServer.screen_get_size()), OS.get_processor_count()])
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	if FileAccess.file_exists("res://scripts/prof.gd"): prof = load("res://scripts/prof.gd")
	game = Main.new()
	game.controls_path = "res://builds/qa/perf/controls.cfg"
	root.add_child(game)
	var wait_until := Time.get_ticks_msec() + 15000
	while not Art._pending.is_empty() and Time.get_ticks_msec() < wait_until:
		await tick()
	var report := {}
	bench_started_msec = Time.get_ticks_msec()
	game.start_run(37)
	game.player.invulnerability = 100000
	var home: Vector2 = game.player.position
	for i in range(10): await tick()
	await measure("A_just_started", 60, report)
	await measure("B_start_sector_settling", 300, report)
	await measure("C_start_sector_settled", 300, report)
	await combat("C2_fight_12_at_start", 12, report)
	game.player.position = home
	game._update_camera(0, true)
	for i in range(30): await tick()
	await measure("C3_start_after_fight", 300, report)
	await travel(Vector2(T.SECTOR_SIZE.x * 2.5, 0), 640.0)
	await measure("D_two_sectors_away", 300, report)
	await travel(Vector2(0, T.SECTOR_SIZE.y * 1.5), 640.0)
	await measure("E_further_away", 300, report)
	await travel(Vector2(-T.SECTOR_SIZE.x * 2.5, -T.SECTOR_SIZE.y * 1.5), 640.0)
	await measure("F_back_at_start", 300, report)
	for i in range(600): await tick()
	await measure("G_back_after_10s", 300, report)
	await combat("H_fight_12_after_travel", 12, report)
	await combat("I_fight_24_after_travel", 24, report)
	game.player.position = home
	game._update_camera(0, true)
	for i in range(30): await tick()
	await measure("J_start_idle_end", 300, report)
	var tag: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "return"
	FileAccess.open("res://builds/qa/perf/%s.json" % tag, FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("PHASE\tMEAN_MS\tP95_MS\tMAX_MS\tGPU_MS\tCLOCK_MS\tELAPSED_S\tDRAW_CALLS\tTRIANGLES\tSECTORS\tENEMIES\tVISIBLE")
	for label: String in report:
		var entry: Dictionary = report[label]
		print("%s\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%.0f\t%d\t%d\t%d\t%d\t%d" % [label, entry.mean, entry.p95, entry.max, entry.render_gpu, entry.clock, entry.elapsed_s, entry.draw_calls, entry.primitives, entry.loaded, entry.enemies, entry.visible_enemies])
	game.free()
	quit(0)
