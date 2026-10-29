extends "res://tests/test_tree.gd"
const Main := preload("res://scripts/main.gd")
const S := preload("res://scripts/sector_generator.gd")
const T := preload("res://scripts/tuning.gd")
var checks := 0
var failures: Array[String] = []
var game: Node2D
var windowed := false
var loop_samples: Array[Dictionary] = []
var loop_reports: Array[Dictionary] = []
var sample_loop := false

class EstimateOverride extends Node:
	var suite: SceneTree
	var forced := false
	func _process(_delta: float) -> void:
		if forced: suite.game.terrain.draw_cost_ms = T.STREAM_DRAW_BUDGET_MS * 3.0

# Runs immediately after main's safety gate and after its late redraw callback.
class Audit extends Node:
	var suite: SceneTree
	var held_elapsed := -1.0
	func _physics_process(_delta: float) -> void:
		# Main has already advanced the camera once. Check that actual view
		# plus the full speed/correction margin here, rather than predicting
		# an additional camera step beyond the safety gate's next view.
		var view: Rect2 = suite.game.view_rect().grow(T.STREAM_VIEW_MARGIN + maxf(T.AIR_DASH_SPEED, T.MAX_FALL_SPEED) / 60.0 + T.CEILING_CORRECTION)
		if suite.game.is_physics_processing() and suite.game.state == "playing" and not suite.game.streaming_wait:
			suite.check(suite.game.terrain.view_is_current(view), "advancing physics has a submitted current view")
			suite.check(suite.game.stream.backdrop_view_is_current(view), "advancing physics has a prepared background")
		if suite.game.is_physics_processing() and suite.game.streaming_wait:
			if held_elapsed >= 0: suite.check(suite.game.elapsed == held_elapsed, "hold freezes simulation time while preparation continues")
			held_elapsed = suite.game.elapsed
		else: held_elapsed = -1.0
	func _process(_delta: float) -> void:
		suite.check(suite.game.terrain.view_is_current(suite.game.stream_view_rect()), "late callbacks leave no dirty visible chunks")
		suite.check(suite.game.stream.backdrop_view_is_current(suite.game.stream_view_rect()), "late callbacks prepare background including shifted origins")
		if suite.sample_loop:
			suite.loop_samples.append({"pending": suite.game.terrain.pending_redraw.size(), "scheduler_ms": suite.game.terrain.redraw_service_ms, "service_ms": suite.game.stream.service_times[-1], "idle": suite.game.stream.loaded.size() == 25 and suite.game.stream.active_job == null and suite.game.stream.jobs.is_empty()})

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)
func frame(count: int = 1) -> void:
	for i in range(count):
		test_progress()
		await physics_frame
		await process_frame
		if windowed:
			await RenderingServer.frame_post_draw
			check(game.terrain.view_is_current(game.stream_view_rect(), true), "visible draw commands actually executed with the current version")
			check(game.stream.backdrop_view_is_current(game.stream_view_rect(), true), "visible background commands actually executed")
func focus(point: Vector2) -> void:
	game.player.position = point
	game.player.velocity = Vector2.ZERO
	game._update_camera(0, true)
func queue_valid() -> bool:
	return game.terrain.pending_redraw.keys().all(func(k): return game.terrain.draw_chunks.has(k))

func real_loop_queue(override_cost: Node) -> void:
	# Keep main AND world physics running. Real-time pacing gives the workers
	# enough time without draining the optional queue through thousands of ticks.
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		var began := Time.get_ticks_usec()
		game.player.invulnerability = 10000
		await frame()
		if game.stream.loaded.size() == 25 and game.stream.jobs.is_empty() and game.stream.active_job == null: break
		OS.delay_usec(maxi(0, 16667 - (Time.get_ticks_usec() - began)))
	# process_frame resumes before node _process in headless runs; sample only
	# from Audit after main._process, then inspect on the following iteration.
	for forced in [false, true]:
		override_cost.forced = forced
		check(game.is_physics_processing() and game.world.can_process(), "real-loop queue audit keeps physics enabled")
		check(game.stream.loaded.size() == 25 and game.stream.jobs.is_empty() and game.stream.active_job == null, "real-loop queue audit has all 25 sectors and no jobs/install")
		check(game.terrain.pending_redraw.size() >= 800, "real-loop queue audit starts with at least 800 pending chunks")
		loop_samples.clear()
		sample_loop = true
		await frame(122)
		sample_loop = false
		var idle := 0
		var progress := 0
		var total_ms := 0.0
		for i in range(1, loop_samples.size()):
			if not loop_samples[i].idle or not loop_samples[i - 1].idle: continue
			idle += 1
			progress += loop_samples[i - 1].pending - loop_samples[i].pending
			total_ms += loop_samples[i].scheduler_ms
		var mean := total_ms / maxi(1, idle)
		var report := {"forced_cost": forced, "frames": idle, "progress": progress, "pending_start": loop_samples[0].pending, "pending_end": loop_samples[-1].pending, "scheduler_mean_ms": mean}
		loop_reports.append(report)
		print("REAL LOOP ", JSON.stringify(report))
		check(idle >= 120, "real-loop audit observes at least 120 idle frames")
		check(progress * 2 >= idle, "real-loop offscreen queue drains at least once per two idle frames")
		check(mean < 0.5, "real-loop scheduler mean stays below 0.5ms")
		check(loop_samples.all(func(s): return s.service_ms > 0), "real-loop service polling duration stays nonzero")
	override_cost.forced = false
	# Exercise two physics callbacks before one idle callback. The first
	# performs real queue cleanup; the second only polls. Old snapshots lack
	# these diagnostic properties, but still run the queue-progress regression.
	if game.get("stream_service_did_work") != null:
		var before_ms: float = game.stream_install_ms
		game.stream.pending_population["redraw_work_probe"] = Vector2i(999999, 999999)
		game.stream.population_queue.append("redraw_work_probe")
		game._physics_process(1.0 / 60.0)
		var first_ms: float = game.stream.service_times[-1]
		check(game.stream.service_did_work, "first physics callback performs population queue cleanup")
		game._physics_process(1.0 / 60.0)
		check(not game.stream.service_did_work, "second physics callback only polls")
		check(game.stream_service_did_work, "idle work flag retains first callback's work")
		check(is_equal_approx(game.stream_install_ms, before_ms + first_ms + game.stream.service_times[-1]), "idle budget sums both physics service durations")

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://builds/qa/stream_install")
	windowed = DisplayServer.get_name() != "headless"
	if windowed: DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	game = Main.new()
	game.controls_path = "res://builds/qa/stream_install/redraw_controls.cfg"
	root.add_child(game)
	game.start_run(37)
	check(game.terrain.draw_chunks.values().all(func(c): return not c.visible), "initial chunks hidden before tree entry")
	check(game.terrain.pending_redraw.size() > 350, "initial offscreen chunks remain deferred")
	var audit := Audit.new()
	audit.suite = self
	audit.process_physics_priority = -99
	audit.process_priority = 1001
	game.add_child(audit)
	var override_cost := EstimateOverride.new()
	override_cost.suite = self
	override_cost.process_priority = 999
	game.add_child(override_cost)
	await real_loop_queue(override_cost)
	var gate: Dictionary = S.boundary_gates(37, Vector2i.ZERO, Vector2i.RIGHT)[0]
	focus(Vector2(gate.rect.position.x - 320, gate.rect.end.y - 22))
	var fell := false
	var dashed := false
	for i in range(300):
		game.player.invulnerability = 10000
		if i == 0: Input.action_press("move_right")
		if i == 120: Input.action_release("move_right")
		if i == 140:
			focus(T.SECTOR_START - Vector2(0, 300))
			game.player.velocity.y = T.MAX_FALL_SPEED
		if i == 180:
			game.player.abilities |= T.ABILITY_DASH
			focus(T.SECTOR_START - Vector2(0, 250))
		if i == 182:
			game.player.pending_dash = true
		await frame()
		fell = fell or game.player.velocity.y > T.MAX_FALL_SPEED * 0.9
		dashed = dashed or game.player.dash_remaining > 0
		OS.delay_msec(1)
	Input.action_release("move_right")
	check(fell, "maximum-speed fall actually occurred")
	check(dashed, "air dash actually occurred")
	game.set_physics_process(false)
	game.world.process_mode = Node.PROCESS_MODE_DISABLED
	# A frozen world still services mandatory and optional work in main._process.
	for key: Vector2i in game.terrain.draw_chunks: game.terrain.request_chunk_redraw(key)
	var pending: int = game.terrain.pending_redraw.size()
	await frame(8)
	check(game.terrain.pending_redraw.size() < pending, "redraw queue advances while world is frozen")
	var data: Dictionary = game.stream.loaded[Vector2i.ZERO]
	var surface: Rect2 = data.erodible_surfaces[0]
	focus(surface.get_center())
	check(not game.terrain.explode(surface.get_center(), 45).is_empty(), "floor excavation exercised")
	await frame()
	var id: int = game.terrain.sectors[Vector2i.ZERO].blocks[0]
	var bounds: Rect2 = game.terrain.breakables[id].bounds
	focus(bounds.get_center())
	game.terrain.damage_at(bounds.get_center(), T.TERRAIN_HP)
	check(not game.terrain.breakables.has(id), "block destroyed")
	await frame()
	game.terrain.restore_block(Vector2i.ZERO, bounds)
	await frame()
	check(game.terrain.occupied.has(game.terrain.cell_at(bounds.get_center())), "block restored")
	# Place on a genuine free supported column, away from actor/protected bounds.
	var wall := -1
	for cell: Vector2i in game.terrain.occupied:
		var rect := Rect2(game.terrain.pixel_of_cell(cell) - Vector2(0, T.WALL_MIN_HEIGHT), Vector2(32, T.WALL_MIN_HEIGHT))
		wall = game.terrain.place_wall(rect, -700)
		if wall >= 0:
			focus(rect.get_center() + Vector2(150, 0))
			break
	check(wall >= 0, "placed wall on a real supported free column")
	if wall >= 0:
		await frame()
		game.terrain.walls[wall].remaining = T.WALL_BLINK_TIME
		for i in range(6):
			game.terrain._physics_process(0.1)
			await frame()
		game.terrain.remove_wall(wall)
		await frame()
	var queued_keys: Array = game.terrain.pending_redraw.keys()
	var before: Rect2 = game.stream_view_rect()
	game.shift_origin(Vector2i(2, -2))
	check(queued_keys == game.terrain.pending_redraw.keys(), "origin shift preserves stable dirty keys")
	check(game.stream_view_rect().size.is_equal_approx(before.size), "origin shift preserves view extent")
	await frame()
	# Deliberately withhold redraw: exactly the same oracle must detect it.
	var key: Vector2i = game.terrain._view_keys(game.stream_view_rect()).filter(func(k): return game.terrain.draw_chunks.has(k))[0]
	game.terrain.request_chunk_redraw(key)
	check(not game.terrain.view_is_current(game.stream_view_rect()), "negative control detects deliberately stopped redraw")
	await frame()
	check(game.terrain.view_is_current(game.stream_view_rect()), "scheduler repairs negative control")
	var holds: int = game.stream.hold_frames
	focus(Vector2(7, 0) * T.SECTOR_SIZE + T.SECTOR_START)
	game.set_physics_process(true)
	var prepare_deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < prepare_deadline:
		game.player.invulnerability = 10000
		await frame()
		if game.stream.neighbourhood_ready(game.player.position, 1.0 / 60.0) and not game.streaming_wait: break
		OS.delay_msec(1)
	check(game.stream.hold_frames > holds, "deliberately unprepared move exercises the real hold")
	check(not game.streaming_wait and game.stream.neighbourhood_ready(game.player.position, 1.0 / 60.0), "held world completes installation and resumes")
	game.set_physics_process(false)
	game.world.process_mode = Node.PROCESS_MODE_DISABLED
	for i in range(80):
		game.stream.service()
		await frame()
	check(not game.stream.loaded.has(Vector2i.ZERO), "distant sector actually unloaded")
	check(queue_valid(), "unload removes stale queue keys")
	# Stop producers and drain the bounded offscreen queue, including hidden chunks.
	game.stream.shutdown()
	game.terrain.draw_cost_ms = T.STREAM_DRAW_BUDGET_MS * 3.0
	var deadline := Time.get_ticks_msec() + 30000
	while not game.terrain.pending_redraw.is_empty() and Time.get_ticks_msec() < deadline:
		await frame()
	print("DRAIN pending=", game.terrain.pending_redraw.size(), " draw_cost_ms=", game.terrain.draw_cost_ms, " scheduler_ms=", game.terrain.redraw_service_ms)
	check(game.terrain.pending_redraw.is_empty(), "offscreen queue eventually empty")
	check(game.terrain.draw_chunks.values().all(func(c): return c.visible and c.submitted_version == c.change_version), "no hidden or stale chunk remains after drain")
	if windowed: check(game.terrain.draw_chunks.values().all(func(c): return c.drawn_version == c.change_version), "all deferred commands executed after drain")
	check(queue_valid(), "drained queue contains no freed keys")
	game.free()
	var report := {"checks": checks, "failures": failures, "windowed": windowed, "real_loop": loop_reports}
	FileAccess.open("res://builds/qa/stream_install/redraw_" + ("render" if windowed else "headless") + ".json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("STREAM REDRAW ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
