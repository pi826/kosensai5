extends SceneTree
const T := preload("res://scripts/tuning.gd")
const Main := preload("res://scripts/main.gd")
const S := preload("res://scripts/sector_generator.gd")
const G := preload("res://scripts/stage_generator.gd")
const Driver := preload("res://tests/stream_driver.gd")
var game: Node2D
var checks := 0
var failures: Array[String] = []
var reports: Array = []
func _initialize(): call_deferred("run")
func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)
	return ok
func run_seed(value: int, damaged: bool = false) -> bool:
	game.start_run(value)
	game.set_physics_process(false)
	var sectors := {Vector2i.ZERO: S.generate(value, Vector2i.ZERO)}
	for target: Vector2i in S.guardian_sectors(value):
		var at := Vector2i.ZERO
		while at != target:
			if at.x != target.x: at.x += signi(target.x - at.x)
			else: at.y += signi(target.y - at.y)
			if not sectors.has(at): sectors[at] = S.generate(value, at)
	var routes := S.guardian_routes(sectors.values(), damaged)
	check(routes.size() == 3, "three executable guardian routes seed %d" % value)
	game.set_physics_process(true)
	var driver := Driver.new()
	driver.tree = self
	driver.game = game
	driver.damaged = damaged
	driver.release()
	var world_id: int = game.world.get_instance_id()
	var player_id: int = game.player.get_instance_id()
	await driver.tick(3)
	var reached := 0
	for route: Dictionary in routes:
		print("ROUTE seed=", value, " guardian=", route.boss_id, " commands=", route.outward.size(), "/", route.returning.size())
		if not check(await driver.follow(route.outward), "seed %d damaged=%s outward guardian %d: %s" % [value, damaged, route.boss_id, driver.error]): return false
		check(game.player.position.distance_to(route.end) < 8, "physically reached guardian sector")
		check(game.discovered_bosses.has(route.boss_id), "actual loaded guardian discovered")
		if not check(await driver.follow(route.returning), "seed %d damaged=%s return guardian %d: %s" % [value, damaged, route.boss_id, driver.error]): return false
		check(game.player.position.distance_to(T.SECTOR_START) < 8, "physically returned to original start")
		check(game.world.get_instance_id() == world_id and game.player.get_instance_id() == player_id, "world and player never replaced")
		reached += 1
	check(game.stream.unload_count > 0, "travel actually unloads distant sectors")
	check(driver.incomplete_views == 0, "every displayed viewport has ready terrain and actors")
	check(driver.incomplete_neighbourhoods == 0,"player always has all eight completed neighbouring sectors")
	check(driver.max_player_step < 25 and driver.max_camera_step < 32, "continuous physics and camera")
	check(game.defeated_bosses.is_empty() and game.player.hp == 100, "route uses movement alone without combat damage")
	check(game.ui.minimap.get_explored_cells().size() == game.explored_cells.size(), "unbounded explored cells retained")
	if damaged: check(not game.terrain.destroyed_cells.is_empty() or not game.stream.states.is_empty(), "excavated state exercised")
	var report := {"seed": value, "damaged": damaged, "frames": driver.frames, "simulated_seconds": game.elapsed, "jumps": driver.jumps,"incomplete_neighbourhoods":driver.incomplete_neighbourhoods, "guardians_returned": reached, "unloads": game.stream.unload_count, "safety_hold_frames_headless": game.stream.hold_frames, "incomplete_views": driver.incomplete_views, "max_player_step": driver.max_player_step, "max_camera_step": driver.max_camera_step, "start": game.last_start_metrics, "main_mean_ms": game.frame_times.reduce(func(a,b): return a+b,0.0) / maxf(1,game.frame_times.size()), "main_max_ms": game.frame_times.max(), "physics_mean_ms": driver.physics_ms.reduce(func(a,b): return a+b,0.0) / maxf(1,driver.physics_ms.size()), "physics_max_ms": driver.physics_ms.max()}
	reports.append(report)
	print("STREAM TRAVERSAL ", JSON.stringify(report))
	driver.release()
	return true
func run():
	DirAccess.make_dir_recursive_absolute("res://builds/qa/streaming")
	game = Main.new()
	game.controls_path = "res://builds/qa/streaming/traversal_controls.cfg"
	root.add_child(game)
	game.key_bindings.reset_defaults()
	var values := [1,37,2026]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="): values = [arg.get_slice("=",1).to_int()]
	if OS.get_cmdline_user_args().has("--damaged-only"): values = []
	for value: int in values:
		if not await run_seed(value): break
	if failures.is_empty() and not OS.get_cmdline_user_args().has("--normal-only"): await run_seed(37,true)
	FileAccess.open("res://builds/qa/streaming/traversal_results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"runs":reports},"\t"))
	game.free()
	print("STREAM PLAYTHROUGH: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
