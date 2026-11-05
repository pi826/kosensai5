extends SceneTree
## Captures a scripted final-boss fight for the title-screen demo.
## Normal rendering: run with --fixed-fps 60 and no --headless. Dry runs work headless.

const Main := preload("res://scripts/main.gd")
const T := preload("res://scripts/tuning.gd")
const S := preload("res://scripts/sector_generator.gd")
const Support := preload("res://tests/stream_test_support.gd")

const CAPTURE_STEPS := 1800
const SAVE_EVERY := 2
const FRAME_DIR := "res://builds/qa/demo/frames"
const RESULT_PATH := "res://builds/qa/demo/capture.json"

var game: Node2D
var boss: Node2D
var dry_run := false
var dry_frames := CAPTURE_STEPS
var prep_ok := false
var prep_detail := ""
var failed := false
var steps_run := 0
var saved_frames := 0
var boss_start_hp := 0
var boss_end_hp := 0
var half_time := -1.0
var rage_time := -1.0
var max_projectiles := 0
var max_enemy_projectiles := 0
var player_hits := 0
var last_player_hp := 0
var floor_y := 0.0
var player_start_y := 0.0
var capture_arena := Rect2()
var max_player_rise := 0.0
var max_player_above_boss := 0.0
var hp_hit_frames := 0
var special_shots := 0
var hp_by_second: Array[int] = []
var distance_by_second: Array[float] = []
var last_boss_hp := 0
var side := 1.0
var move_state := 0
var jump_hold := 0
var switch_cooldown := 0.0
var aim_cooldown := 0.0
var special_clock := 0.0
var dash_cooldown := 0.0
var absorb_remaining := 0.0
var boss_half_locked := false

func _initialize() -> void: call_deferred("run")

# Support.ready expects a test tree; keep the helper API without a deadline.
func test_progress() -> void: pass

func frames(count: int = 1) -> void:
	for i in range(count):
		for b in game.projectiles.get_children(): b.set_physics_process(false)
		await physics_frame
		await process_frame

func freeze() -> void:
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	for enemy in get_nodes_in_group("enemies"): enemy.set_physics_process(false)

func clear_bullets() -> void:
	for b in game.projectiles.get_children(): b.free()

func actor(id: int) -> Node2D:
	for enemy in get_nodes_in_group("enemies"):
		if enemy.get_parent() == game.world and enemy.kind == "boss" and enemy.boss_id == id \
			and not enemy.dead and not enemy.is_queued_for_deletion(): return enemy
	return null

func settle() -> bool:
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		game.boss_cycle.service()
		if game.boss_cycle.selection == null: return true
		await frames()
		OS.delay_msec(1)
	return false

func load_boss(record: Dictionary) -> Node2D:
	var ok: bool = await Support.ready(self, game, game.boss_cycle.world_record(record).position)
	if not ok: return null
	freeze()
	await frames(2)
	return actor(record.boss_id)

func defeat(enemy: Node2D) -> bool:
	if not is_instance_valid(enemy): return false
	enemy.receive_hit(1 - enemy.polarity, 9999)
	game.actor_defeated(enemy)
	await frames(2)
	return await settle()

func current(role: String) -> Array:
	return game.boss_cycle.records.values().filter(func(r): return r.role == role and r.alive)

func prepare() -> bool:
	DirAccess.make_dir_recursive_absolute("res://builds/qa/demo")
	game = Main.new()
	game.controls_path = "res://builds/qa/demo/test_controls.cfg"
	root.add_child(game)
	await frames(3)
	game.key_bindings.reset_defaults()
	game.start_run(37)
	freeze()
	var sectors: Array = S.guardian_sectors(37)
	for index in range(sectors.size()):
		var at: Vector2i = sectors[index]
		var point: Vector2 = Vector2(at - game.origin_sector) * T.SECTOR_SIZE + T.SECTOR_START
		if not await Support.ready(self, game, point):
			prep_detail = "guardian %d sector failed to stream" % index
			return false
		freeze()
		if not await defeat(actor(index)):
			prep_detail = "guardian %d could not be defeated" % index
			return false
	if game.boss_cycle.phase != "final":
		prep_detail = "boss cycle did not reach final (phase %s)" % game.boss_cycle.phase
		return false
	if not await settle():
		prep_detail = "final boss selection timed out"
		return false
	var finals: Array = current("final")
	if finals.is_empty():
		prep_detail = "no live final boss record"
		return false
	boss = await load_boss(finals[0])
	if not is_instance_valid(boss):
		prep_detail = "final boss actor was not installed"
		return false
	var arena: Rect2 = boss.arena
	if not arena.has_area():
		prep_detail = "final boss arena is empty"
		return false
	capture_arena = arena
	side = 1.0 if boss.position.x <= capture_arena.get_center().x else -1.0
	var shelf_center := capture_arena.get_center().x
	var target_x := clampf(boss.position.x + side * 280.0, shelf_center - 350.0, shelf_center + 350.0)
	floor_y = capture_arena.end.y - T.PLAYER_SIZE.y / 2.0
	# The middle shelf keeps the player near the final boss's roaming height.
	game.player.position = Vector2(target_x, floor_y - 320.0)
	game.player.velocity = Vector2.ZERO
	game.player.gravity_sign = 1
	game.player.up_direction = Vector2(0, -1)
	game.player.facing = -1 if target_x < boss.position.x else 1
	game.player.hp = game.player.max_hp
	game.player.abilities |= T.ABILITY_DASH
	game.player.homing_charges = game.player.charge_capacity()
	boss.hp = roundi(boss.max_hp * 0.6)
	boss_start_hp = boss.hp
	game.announcement = ""
	game.announcement_remaining = 0.0
	game.ui.update_hud()
	clear_bullets()
	Support.release(self, game)
	# Keep the boss and player framed together; the normal player-centred camera
	# can put the large final boss just outside the attack visibility inset.
	game.set_physics_process(false)
	boss.set_physics_process(true)
	boss.was_visible = true
	boss.wake_delay = 0.0
	boss.shot_clock = 0.7
	boss.signature_clock = 2.5
	_fit_camera()
	await frames(30)
	clear_bullets()
	boss.was_visible = true
	boss.wake_delay = 0.0
	boss.shot_clock = 0.7
	boss.signature_clock = 2.5
	game.player.hp = game.player.max_hp
	game.elapsed = 9.0 * 60.0 + 24.0
	game.dynamite_stock = 6
	game.dynamite_kill_progress = 1
	game.ui.update_hud()
	_fit_camera()
	var distance := absf(game.player.position.x - boss.position.x)
	prep_detail = "guardians=%d phase=%s boss=%s distance=%.1f floor=%.1f on_floor=%s arena=%s" % [
		sectors.size(), game.boss_cycle.phase, boss.name if boss.name != "" else "final", distance,
		floor_y, str(game.player.is_on_floor()), str(capture_arena)]
	print("DEMO PREP ", prep_detail)
	return true

func _clear_frames() -> void:
	DirAccess.make_dir_recursive_absolute(FRAME_DIR)
	var dir := DirAccess.open(FRAME_DIR)
	if dir == null: return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".png"):
			dir.remove(entry)
		entry = dir.get_next()
	dir.list_dir_end()

func _fit_camera() -> void:
	if not is_instance_valid(boss) or not is_instance_valid(game.player): return
	game.camera.position = (game.player.position + boss.position) * 0.5
	game.camera.reset_smoothing()

func _action(action_name: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action_name
	event.pressed = pressed
	event.strength = 1.0
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _set_move(direction: int) -> void:
	if move_state == direction: return
	if move_state < 0: Input.action_release("move_left")
	if move_state > 0: Input.action_release("move_right")
	move_state = direction
	if direction < 0: Input.action_press("move_left")
	elif direction > 0: Input.action_press("move_right")

func _incoming_bullet_near() -> bool:
	var player: Node2D = game.player
	for b in game.projectiles.get_children():
		if b.get("faction") != 1: continue
		if b.get("polarity") == player.polarity: continue
		var offset: Vector2 = player.position - b.position
		if offset.length() > 120.0: continue
		if offset.normalized().dot(b.direction) > 0.2: return true
	return false

func _nearest_bullet_color() -> int:
	var player: Node2D = game.player
	var best := -1
	var best_distance := 130.0
	for b in game.projectiles.get_children():
		if b.get("faction") != 1: continue
		var color: int = b.get("polarity")
		if color == player.polarity: continue
		var offset: Vector2 = player.position - b.position
		if offset.length() >= best_distance: continue
		if offset.normalized().dot(b.direction) <= 0.2: continue
		best_distance = offset.length()
		best = color
	return best

func _apply_controls(step: int) -> void:
	var player: Node2D = game.player
	var shelf_center := capture_arena.get_center().x
	var flight_time := player.position.distance_to(boss.position) / T.PLAYER_BULLET_SPEED
	var aim_point: Vector2 = boss.position + boss.velocity * flight_time * 0.8
	var aim_vertical := absf(aim_point.y - player.position.y)
	var target_offset := 260.0
	if aim_vertical > 70.0:
		# Aim through the near edge of the boss body instead of overshooting it.
		target_offset = maxf(8.0, (aim_vertical - 68.0) / tan(deg_to_rad(60.0)))
	var preferred_side := signf(player.position.x - boss.position.x)
	if is_zero_approx(preferred_side): preferred_side = side
	var target_x := aim_point.x + preferred_side * target_offset
	if target_x < shelf_center - 350.0 or target_x > shelf_center + 350.0:
		preferred_side = -preferred_side
		target_x = aim_point.x + preferred_side * target_offset
	target_x = clampf(target_x, shelf_center - 350.0, shelf_center + 350.0)
	side = preferred_side
	var error := target_x - player.position.x
	_set_move(0 if absf(error) <= 16.0 else (1 if error > 0.0 else -1))

	if jump_hold > 0:
		jump_hold -= 1
		if jump_hold == 0: _action("jump", false)
	elif player.is_on_floor() and player.position.y > floor_y - 40.0 and _incoming_bullet_near():
		# Do not climb more than 120 px above the boss while evading.
		var jump_margin: float = player.position.y - (boss.position.y - 120.0)
		if jump_margin > 60.0:
			_action("jump", true)
			jump_hold = 18 if jump_margin > 220.0 else (8 if jump_margin > 120.0 else 3)

	switch_cooldown = maxf(0.0, switch_cooldown - 1.0 / 60.0)
	absorb_remaining = maxf(0.0, absorb_remaining - 1.0 / 60.0)
	var desired := 1 - int(boss.polarity)
	var nearby := _nearest_bullet_color()
	if nearby >= 0 and absorb_remaining <= 0.0:
		desired = nearby
		absorb_remaining = 0.4
	if switch_cooldown <= 0.0 and int(player.polarity) != desired:
		_action("switch_color", true)
		_action("switch_color", false)
		switch_cooldown = 0.18

	aim_cooldown = maxf(0.0, aim_cooldown - 1.0 / 60.0)
	var want_aim := 0
	var vertical := boss.position.y - player.position.y
	if vertical < -70.0: want_aim = 1
	elif vertical > 70.0: want_aim = 2
	if aim_cooldown <= 0.0 and int(player.aim_index) != want_aim:
		_action("aim_cycle", true)
		_action("aim_cycle", false)
		aim_cooldown = 0.12

	special_clock += 1.0 / 60.0
	var pace_hp := lerpf(float(boss_start_hp), 30.0, clampf(float(step + 1) / CAPTURE_STEPS, 0.0, 1.0))
	if special_clock >= 3.5:
		special_clock = 0.0
		if player.homing_charges <= 0: player.homing_charges = 1
		if int(player.polarity) != int(boss.polarity) and (special_shots == 0 or boss.hp > roundi(pace_hp) + 8):
			_action("special", true)
			_action("special", false)
			special_shots += 1

	dash_cooldown = maxf(0.0, dash_cooldown - 1.0 / 60.0)
	if dash_cooldown <= 0.0 and not player.is_on_floor() and not player.air_dash_used \
		and player.dash_remaining <= 0.0 and player.has_ability(T.ABILITY_DASH):
		_action("dash", true)
		_action("dash", false)
		dash_cooldown = 5.0

func _after_step(step: int) -> void:
	var elapsed := float(step + 1) / 60.0
	var player: Node2D = game.player
	if not is_instance_valid(boss) or boss.dead or boss.is_queued_for_deletion():
		failed = true
		return
	if player.hp < last_player_hp: player_hits += 1
	player.hp = player.max_hp
	last_player_hp = player.hp
	if boss.hp <= 1: boss.hp = 1
	if boss.hp < last_boss_hp: hp_hit_frames += 1
	last_boss_hp = boss.hp
	max_player_rise = maxf(max_player_rise, player_start_y - player.position.y)
	max_player_above_boss = maxf(max_player_above_boss, boss.position.y - player.position.y)
	var half: float = boss.max_hp * 0.5
	var fallback := 18.0
	if not boss_half_locked and boss.hp < half:
		boss_half_locked = true
		half_time = elapsed
		print("DEMO HALF at %.2fs hp=%d" % [elapsed, boss.hp])
	elif not boss_half_locked and elapsed >= fallback:
		boss.hp = maxi(1, boss.max_hp / 2 - 1)
		boss_half_locked = true
		half_time = elapsed
		print("DEMO HALF forced at %.2fs hp=%d" % [elapsed, boss.hp])
	if boss.rage_started and rage_time < 0.0:
		rage_time = elapsed
		print("DEMO RAGE SPIN at %.2fs" % elapsed)
	var enemy_bullets := 0
	for b in game.projectiles.get_children():
		if b.get("faction") == 1: enemy_bullets += 1
	max_enemy_projectiles = maxi(max_enemy_projectiles, enemy_bullets)
	max_projectiles = maxi(max_projectiles, game.projectiles.get_child_count())
	if (step + 1) % 60 == 0:
		var second := (step + 1) / 60
		var distance := player.position.distance_to(boss.position)
		hp_by_second.append(boss.hp)
		distance_by_second.append(snappedf(distance, 0.1))
		print("DEMO t=%ds hp=%d/%d distance=%.0f rage=%s bullets=%d enemy=%d hits=%d rise=%.0f above=%.0f on_floor=%s" % [
			second, boss.hp, boss.max_hp, distance, str(boss.rage_started), game.projectiles.get_child_count(),
			enemy_bullets, player_hits, max_player_rise, max_player_above_boss, str(player.is_on_floor())])

func _run_steps(steps: int) -> void:
	Input.action_press("shoot")
	for step in range(steps):
		game.elapsed += 1.0 / 60.0
		_apply_controls(step)
		game.player.hp = game.player.max_hp
		_fit_camera()
		await physics_frame
		await process_frame
		_fit_camera()
		_after_step(step)
		if step % 10 == 0: game.ui.update_hud()
		steps_run = step + 1
		if failed: break
		if not dry_run and step % SAVE_EVERY == 1:
			await RenderingServer.frame_post_draw
			var image: Image = root.get_texture().get_image()
			if image != null:
				saved_frames += 1
				image.save_png("%s/frame_%05d.png" % [FRAME_DIR, saved_frames])
	_release_inputs()

func _release_inputs() -> void:
	_set_move(0)
	Input.action_release("shoot")
	if jump_hold > 0:
		_action("jump", false)
		jump_hold = 0

func _finish() -> void:
	boss_end_hp = boss.hp if is_instance_valid(boss) else -1
	var summary := {
		"dry_run": dry_run,
		"prep_ok": prep_ok,
		"prep": prep_detail,
		"steps": steps_run,
		"frames": saved_frames,
		"boss_max_hp": boss.max_hp if is_instance_valid(boss) else 0,
		"boss_start_hp": boss_start_hp,
		"boss_half_time": half_time,
		"boss_end_hp": boss_end_hp,
		"rage_time": rage_time,
		"max_projectiles": max_projectiles,
		"max_enemy_projectiles": max_enemy_projectiles,
		"player_hits": player_hits,
		"player_boss_hit_frames": hp_hit_frames,
		"special_shots": special_shots,
		"max_player_rise": max_player_rise,
		"max_player_above_boss": max_player_above_boss,
		"hp_by_second": hp_by_second,
		"distance_by_second": distance_by_second,
		"failed": failed,
	}
	DirAccess.make_dir_recursive_absolute("res://builds/qa/demo")
	FileAccess.open(RESULT_PATH, FileAccess.WRITE).store_string(JSON.stringify(summary, "\t"))
	var hp10: int = hp_by_second[9] if hp_by_second.size() >= 10 else -1
	var hp20: int = hp_by_second[19] if hp_by_second.size() >= 20 else -1
	var hp30: int = hp_by_second[29] if hp_by_second.size() >= 30 else -1
	print("DEMO CAPTURE frames=%d steps=%d boss_hp=%d->%d half=%.2f rage=%.2f max_bullets=%d enemy_max=%d hits=%d hit_frames=%d specials=%d rise=%.0f above=%.0f hp10=%d hp20=%d hp30=%d failed=%s" % [
		saved_frames, steps_run, boss_start_hp, boss_end_hp, half_time, rage_time, max_projectiles,
		max_enemy_projectiles, player_hits, hp_hit_frames, special_shots, max_player_rise, max_player_above_boss,
		hp10, hp20, hp30, str(failed)])
	quit(0 if prep_ok and not failed else 1)

func run() -> void:
	var args := OS.get_cmdline_user_args()
	for index in range(args.size()):
		if args[index] == "--dry-run": dry_run = true
		if args[index] == "--frames" and index + 1 < args.size():
			dry_frames = maxi(1, int(args[index + 1]))
	prep_ok = await prepare()
	if not prep_ok:
		print("DEMO CAPTURE preparation failed: ", prep_detail)
		quit(1)
		return
	if not dry_run: _clear_frames()
	last_player_hp = game.player.max_hp
	last_boss_hp = boss.hp
	player_start_y = game.player.position.y
	await _run_steps(dry_frames if dry_run else CAPTURE_STEPS)
	_finish()
