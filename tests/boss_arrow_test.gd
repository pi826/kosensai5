extends "res://tests/test_tree.gd"
const Main := preload("res://scripts/main.gd")
const Tutorial := preload("res://scripts/tutorial.gd")
const Enemy := preload("res://scripts/enemy.gd")
const T := preload("res://scripts/tuning.gd")
const S := preload("res://scripts/sector_generator.gd")
const Support := preload("res://tests/stream_test_support.gd")
const OUTPUT := "res://builds/qa/boss_arrow/"
var game: Node2D
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)
func frames(n: int = 1) -> void:
	for i in range(n):
		test_progress()
		await physics_frame
		await process_frame
func freeze() -> void:
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	for e in get_nodes_in_group("enemies"): e.set_physics_process(false)
func reset() -> void:
	game.start_run(37)
	freeze()
func record(id: int, position: Vector2, role: String = "guardian") -> Dictionary:
	var point: Dictionary = game.stable_point(position)
	var value := {"boss_id": id, "sector": point.sector, "position": point.local,
		"sector_local": true, "role": role, "alive": true, "hp": 80, "revealed": false,
		"arena": Rect2(), "roam": Rect2(), "saved": {}, "patrol": Vector2.ZERO, "chamber_id": -1}
	game.boss_cycle.records[id] = value
	return value
func fixture_boss(id: int, position: Vector2, role: String = "guardian") -> Node2D:
	record(id, position, role)
	var e := Enemy.new()
	e.game = game
	e.kind = "boss"
	e.boss_role = role
	e.boss_id = id
	e.spawn_id = "arrow_boss:%d" % id
	e.position = position
	game.world.add_child(e)
	e.set_physics_process(false)
	return e
func clear_bosses() -> void:
	for e in get_nodes_in_group("enemies"):
		if e.get_parent() == game.world and e.kind == "boss": e.free()
	game.boss_cycle.records.clear()
	game.boss_cycle.live_actors.clear()
	game.defeated_bosses.clear()
func aim(id: int, offset: Vector2, message: String) -> void:
	var target: Dictionary = game.boss_arrow_state()
	check(not target.is_empty(), message + " visible")
	if target.is_empty(): return
	check(target.boss_id == id, message + " target")
	check(absf(target.direction.angle_to(offset.normalized())) < 0.00001, message + " angle < 1e-5 rad")
	check(is_equal_approx(target.distance, offset.length()), message + " straight distance")

func unlocking() -> void:
	reset()
	check(game.kills == 0 and game.boss_arrow_state().is_empty(), "fresh run locked")
	game.ui.update_hud()
	check(game.ui.boss_arrow_label.visible and game.ui.boss_arrow_label.text == T.ENHANCER_NAME + "を倒すとボスの方角が分かる", "initial lantern hint HUD")
	var normals := get_nodes_in_group("enemies").filter(func(e): return e.get_parent() == game.world and e.kind not in ["boss", "enhancer"])
	for i in range(20): normals[i].receive_hit(1 - normals[i].polarity, 999)
	await frames(2)
	check(game.kills == 20 and game.boss_arrow_state().is_empty(), "twenty real ordinary defeats remain locked")
	game.ui.update_hud()
	check(game.ui.boss_arrow_label.text == T.ENHANCER_NAME + "を倒すとボスの方角が分かる", "hint unchanged by ordinary defeats")
	var boss := fixture_boss(0, game.player.position + Vector2(2000, 0))
	boss.receive_hit(1 - boss.polarity, 999)
	await frames(2)
	check(game.kills == 20 and game.boss_arrow_state().is_empty(), "boss defeat does not unlock")
	check(game.announcement_remaining == 0, "boss defeat does not announce arrow unlock")
	var lanterns := get_nodes_in_group("enhancers").filter(func(e):return e.get_parent()==game.world)
	check(not lanterns.is_empty(), "generated lantern exists")
	if lanterns.is_empty(): return
	var lantern = lanterns[0]
	var id: String = lantern.spawn_id
	lantern.receive_hit(1-lantern.polarity,999)
	check(game.boss_arrow_unlocked and not game.boss_arrow_state().is_empty(), "first lantern defeat unlocks")
	check(game.announcement == "ボスの方角が分かるようになった" and game.announcement_remaining > 0, "unlock notification")
	game.ui.update_hud()
	check(not game.ui.boss_arrow_label.visible and game.ui.announcement_label.visible, "unlock HUD replaces hint with notice")
	check(game.stream.missing.has(id), "lantern defeat registered for 5C respawn")
	game.announcement = "unchanged"
	game.announcement_remaining = 0
	game.actor_defeated(lantern)
	check(game.announcement=="unchanged" and game.kills==21,"duplicate defeat ignored")
	await frames(2)
	game.stream._restore(game.stream.missing[id])
	game.stream.missing.erase(id)
	var returned := get_nodes_in_group("enhancers").filter(func(e):return e.get_parent()==game.world and e.spawn_id==id and not e.dead)
	check(returned.size()==1,"5C restores lantern with same persistent ID")
	if not returned.is_empty():
		returned[0].set_physics_process(false)
		returned[0].receive_hit(1-returned[0].polarity,999)
		check(game.kills==22 and game.announcement=="unchanged" and game.announcement_remaining==0,"restored lantern rewards without repeating unlock notice")
	await frames(2)
	check(not game.boss_arrow_state().is_empty(), "arrow stays unlocked after further defeats")
	reset()
	check(game.kills == 0 and not game.boss_arrow_unlocked and game.boss_arrow_state().is_empty() and game.announcement_remaining == 0, "retry resets arrow and notification")
	var tutorial := Tutorial.new()
	tutorial.key_bindings = game.key_bindings
	root.add_child(tutorial)
	tutorial.set_physics_process(false)
	tutorial.boss_arrow_unlocked = true
	tutorial.ui.update_hud()
	check(tutorial.boss_arrow_state().is_empty() and tutorial.boss_arrow_progress().is_empty() and not tutorial.ui.boss_arrow_label.visible, "tutorial hides arrow and hint even if flag is set")
	tutorial.free()
	game.camera.make_current()
func targets() -> void:
	reset()
	clear_bosses()
	game.boss_arrow_unlocked = true
	game.player.position = Vector2(500, 500)
	game.camera.position = game.player.position
	game.boss_cycle.round_number = 2
	game.boss_cycle.guardian_ids.assign([10, 11, 12])
	var a := fixture_boss(10, Vector2(2500, 800))
	var b := fixture_boss(11, Vector2(-3500, -200))
	record(12, Vector2(500, 6500))
	aim(10, a.position - game.player.position, "nearest guardian")
	# No update_position call: the indicator must consult the actual moving actor.
	a.position += Vector2(4000, 1000)
	aim(11, b.position - game.player.position, "movement uses live position over record")
	a.position -= Vector2(4000, 1000)
	game.player.position = Vector2(-1800, 500)
	game.camera.position = game.player.position
	aim(11, b.position - game.player.position, "player movement switches nearest")
	b.receive_hit(1 - b.polarity, 999)
	aim(10, a.position - game.player.position, "dead nearest switches target")
	await frames(2)
	# Different phases exclude even a closer living guardian and old rounds.
	record(20, game.player.position + Vector2(2100, -1200), "final")
	record(21, game.player.position + Vector2(1400, 2200), "secret")
	record(22, game.player.position + Vector2(900, 0))
	aim(10, a.position - game.player.position, "current guardian IDs exclude closer old guardian")
	game.boss_cycle.phase = "final"
	aim(20, Vector2(2100, -1200), "final phase")
	game.boss_cycle.phase = "secret"
	aim(21, Vector2(1400, 2200), "secret phase")
	# A dummy selection exercises the pending guard without starting a worker.
	game.boss_cycle.selection = RefCounted.new()
	check(game.boss_arrow_state().is_empty(), "selection in progress hides target")
	game.boss_cycle.selection = null
	game.boss_cycle.phase = "complete"
	check(game.boss_arrow_state().is_empty(), "complete phase hides target")
	game.boss_cycle.phase = "final"
	game.boss_cycle.records[20].alive = false
	check(game.boss_arrow_state().is_empty(), "no living target hides arrow")
	game.boss_cycle.phase = "guardians"
	game.boss_cycle.guardian_ids.assign([99])
	check(game.boss_arrow_state().is_empty(), "later round without record has no first-round fallback")
	game.boss_cycle.phase = "final"
	game.boss_cycle.records[20].alive = true
	for state in ["paused", "shop", "equipment", "lost", "won", "title", "settings"]:
		game.state = state
		check(game.boss_arrow_state().is_empty(), state + " hides arrow")
	game.state = "playing"
	game.player.dead = true
	check(game.boss_arrow_state().is_empty(), "dead player hides arrow")
	game.player.dead = false

func unloaded_and_origin() -> void:
	reset()
	game.boss_arrow_unlocked = true
	var sectors := S.guardian_sectors(37)
	var id := 0
	for i in range(3):
		if not game.boss_cycle.records.has(i): id = i; break
	for i in range(3):
		if i != id: game.defeated_bosses[i] = true
	check(not game.stream.loaded.has(sectors[id]) and not game.boss_cycle.records.has(id), "first-round target sector starts unloaded without record")
	var expected: Vector2 = game.stream.sector_offset(sectors[id]) + T.SECTOR_SIZE / 2 - game.player.position
	var loaded_before: Array = game.stream.loaded.keys()
	var jobs_before: int = game.stream.jobs.size()
	for i in range(30): game.boss_arrow_state()
	check(game.stream.loaded.keys() == loaded_before and game.stream.jobs.size() == jobs_before and not game.boss_cycle.records.has(id), "arrow query never generates or streams a sector")
	aim(id, expected, "unloaded initial guardian sector-center fallback")
	check(await Support.ready(self, game, game.stream.sector_offset(sectors[id]) + T.SECTOR_SIZE / 2), "guardian sector loads via existing streaming")
	freeze()
	var actor = game.boss_cycle.live_actors[id].get_ref() if game.boss_cycle.live_actors.has(id) else null
	check(is_instance_valid(actor) and game.boss_cycle.records.has(id), "initial_spawn creates record and live actor on load")
	if not is_instance_valid(actor): return
	game.player.position = actor.position + Vector2(-1000, -700)
	game.camera.position = game.player.position
	aim(id, actor.position - game.player.position, "loaded initial guardian exact actor position")
	game.camera.position = actor.position
	check(game.boss_arrow_state().is_empty(), "target inside viewport suppresses arrow")
	game.camera.position = actor.position - Vector2(T.VIEW_SIZE.x / 2 + actor.body_size.x / 2 - 1, 0)
	check(game.boss_arrow_state().is_empty(), "partially visible boss also suppresses arrow")
	game.camera.position = game.player.position
	var before: Dictionary = game.boss_arrow_state()
	game.shift_origin(Vector2i(2, -3))
	var after: Dictionary = game.boss_arrow_state()
	check(before.direction.distance_to(after.direction) < 0.00001 and is_equal_approx(before.distance, after.distance) and not after.has("distance_text"), "loaded actor origin shift preserves direction distance and label")
	game.stream._unload(sectors[id])
	check(not is_instance_valid(actor) and game.boss_cycle.live_actors[id].get_ref() == null, "unloading frees boss despite weak actor registry")
	after = game.boss_arrow_state()
	check(before.direction.distance_to(after.direction) < 0.00001 and is_equal_approx(before.distance, after.distance) and not after.has("distance_text"), "unloaded guardian uses remembered position after origin shift")
	# Establish a distant origin without making an absolute pixel Vector2.
	reset()
	clear_bosses()
	game.origin_sector = Vector2i(100000, -50000)
	game.stage.origin_sector = game.origin_sector
	game.player.position = Vector2(300, 700)
	game.camera.position = game.player.position
	game.boss_arrow_unlocked = true
	game.boss_cycle.round_number = 2
	game.boss_cycle.guardian_ids.assign([30])
	record(30, Vector2(9000, -6700))
	aim(30, Vector2(8700, -7400), "far sector stable record")
	before = game.boss_arrow_state()
	game.shift_origin(Vector2i(3, -2))
	after = game.boss_arrow_state()
	check(before.direction.distance_to(after.direction) < 0.00001 and is_equal_approx(before.distance, after.distance) and not after.has("distance_text"), "far (100000,-50000) shift preserves direction distance and label")
	record(30, game.player.position + Vector2(3000, 0))
	check(not game.boss_arrow_state().has("distance_text"), "no label below one sector")
	record(30, game.player.position + Vector2(8192, 0))
	check(not game.boss_arrow_state().has("distance_text"), "no label at two horizontal sectors")
	record(30, game.player.position + Vector2(0, -6144))
	check(not game.boss_arrow_state().has("distance_text"), "no label at two vertical sectors")
	var live := fixture_boss(30, game.player.position + Vector2(-3100, 2700))
	before = game.boss_arrow_state()
	game.shift_origin(Vector2i(-4, 5))
	after = game.boss_arrow_state()
	check(before.direction.distance_to(after.direction) < 0.00001 and is_equal_approx(before.distance, after.distance) and not after.has("distance_text"), "far loaded actor also preserves direction distance and label")
	aim(30, live.position - game.player.position, "far actual actor")

func hud_layout() -> void:
	reset()
	game.ui.update_hud()
	var hint: Control = game.ui.boss_arrow_label
	check(not hint.get_rect().intersects(game.ui.objective_label.get_rect()) and not hint.get_rect().intersects(game.ui.location_label.get_rect()) and not hint.get_rect().intersects(game.ui.minimap.get_rect()), "progress HUD avoids existing objective location and map")
	var font: Font = hint.get_theme_font("font")
	check(font.get_string_size(hint.text, HORIZONTAL_ALIGNMENT_LEFT, -1, hint.get_theme_font_size("font_size")).x <= hint.size.x, "progress text fits allocated width")
	# A circumscribed HP rectangle and player body are entirely inside the arrow's
	# smallest radius, including its outline, so all angles keep them clear.
	var hp_center := T.PLAYER_SIZE.y / 2 + T.PLAYER_HP_BAR_OFFSET
	var hp_corner := Vector2(T.PLAYER_HP_BAR_SIZE.x / 2 + 2, hp_center + T.PLAYER_HP_BAR_SIZE.y / 2 + 2)
	var inner_radius := T.BOSS_ARROW_RADIUS - T.BOSS_ARROW_LENGTH / 2 - T.BOSS_ARROW_OUTLINE_WIDTH / 2
	check(inner_radius > hp_corner.length() and inner_radius > (T.PLAYER_SIZE / 2).length(), "arrow clears player and HP bar for every angle")
	check(T.BOSS_ARROW_COLOR != T.CRYSTAL_COLOR and T.BOSS_ARROW_COLOR != T.MERCHANT_COLOR and not T.COLORS.has(T.BOSS_ARROW_COLOR), "arrow color differs from combat crystals and merchant")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	game = Main.new()
	game.controls_path = OUTPUT + "test_controls.cfg"
	root.add_child(game)
	await unlocking()
	await targets()
	await unloaded_and_origin()
	hud_layout()
	game.free()
	FileAccess.open(OUTPUT + "boss_arrow_results.json", FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures.size(), "failure_messages": failures}, "\t"))
	print("BOSS ARROW TEST: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
