extends Node2D
const T := preload("res://scripts/tuning.gd")
const SectorStream := preload("res://scripts/sector_stream.gd")
const Player := preload("res://scripts/player.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Bullet := preload("res://scripts/projectile.gd")
const LaserBeam := preload("res://scripts/laser_beam.gd")
const Bomb := preload("res://scripts/bomb.gd")
const WorldTerrain := preload("res://scripts/streamed_terrain.gd")
const WorldBackdrop := preload("res://scripts/world_backdrop.gd")
const Effects := preload("res://scripts/effects.gd")
const Interface := preload("res://scripts/interface.gd")
const KeyBindings := preload("res://scripts/key_bindings.gd")
const BossCycle := preload("res://scripts/boss_cycle.gd")

class PhysicsProbe extends Node:
	var game: Node
	func _physics_process(_delta: float) -> void:
		game._finish_physics_sample()

var stage: Dictionary = {}
var last_start_metrics: Dictionary = {}
var current_seed := 1
var state := "title"
var score := 0
var elapsed := 0.0
var kills := 0
var total_enemies := 0
var player: CharacterBody2D
var boss: CharacterBody2D
var world: Node2D
var terrain: Node2D
var projectiles: Node2D
var effects: Node2D
var camera: Camera2D
var ui: CanvasLayer
var ending := false
var key_bindings: RefCounted
var controls_path := "user://controls.cfg"
var settings_return_state := "title"
var explored_cells: Dictionary = {}
var discovered_bosses: Dictionary = {}
var defeated_bosses: Dictionary = {}
var defeated_enemies: Dictionary = {}
var visited_sectors: Dictionary = {}
var explored_by_sector: Dictionary = {}
var explored_geometry: Dictionary = {}
var stream: RefCounted
var streaming_enabled := true
var streaming_wait := false
var frame_times: Array[float] = []
var physics_frame_times: Array[float] = []
var physics_frame_started := 0
var boss_cycle: RefCounted
var announcement := ""
var announcement_remaining := 0.0
var tutorial_session: Node2D
var tutorial_layer: CanvasLayer
var tutorial_seed_text := ""

func is_tutorial() -> bool:
	return false

func start_tutorial() -> void:
	if is_instance_valid(tutorial_session): return
	tutorial_seed_text = ui.seed_field.text
	# Keep the entire main run suspended, including its seed and all progress.
	world.process_mode = Node.PROCESS_MODE_DISABLED
	world.hide()
	ui.hide()
	set_physics_process(false)
	set_process_unhandled_input(false)
	tutorial_layer = CanvasLayer.new()
	tutorial_layer.layer = 10
	add_child(tutorial_layer)
	var container := SubViewportContainer.new()
	container.size = T.VIEW_SIZE
	container.stretch = true
	tutorial_layer.add_child(container)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(T.VIEW_SIZE)
	viewport.world_2d = World2D.new()
	viewport.disable_3d = true
	container.add_child(viewport)
	tutorial_session = load("res://scripts/tutorial.gd").new()
	tutorial_session.host = self
	tutorial_session.key_bindings = key_bindings
	tutorial_session.controls_path = controls_path
	viewport.add_child(tutorial_session)

func finish_tutorial(begin_main: bool = false) -> void:
	if is_instance_valid(tutorial_layer):
		tutorial_layer.hide()
		tutorial_layer.process_mode = Node.PROCESS_MODE_DISABLED
		tutorial_layer.queue_free()
	tutorial_layer = null
	tutorial_session = null
	camera.make_current()
	world.show()
	ui.show()
	set_physics_process(true)
	set_process_unhandled_input(true)
	ui.refresh_bindings()
	show_menu("title")
	ui.seed_field.text = tutorial_seed_text
	if begin_main: primary_action()

func return_to_title() -> void:
	show_menu("title")

func _ready() -> void:
	_register_inputs()
	camera = Camera2D.new()
	camera.position = T.VIEW_SIZE / 2
	camera.limit_enabled = false
	add_child(camera)
	ui = Interface.new()
	ui.game = self
	add_child(ui)
	var probe := PhysicsProbe.new()
	probe.game = self
	probe.process_physics_priority = 1000
	add_child(probe)
	start_run(_random_seed())
	show_menu("title")

func _register_inputs() -> void:
	key_bindings = KeyBindings.new()
	key_bindings.load_settings(controls_path)

func _random_seed() -> int:
	return int(Time.get_ticks_usec() % 2147483647)

func start_run(stage_seed: int) -> void:
	var started := Time.get_ticks_usec()
	if boss_cycle != null: boss_cycle.shutdown()
	if stream != null: stream.shutdown()
	if is_instance_valid(world):
		remove_child(world)
		world.free()
	current_seed = stage_seed
	stage = {"seed": stage_seed, "streaming": true, "bounds": Rect2(), "start_position": T.SECTOR_START}
	score = 0
	elapsed = 0.0
	kills = 0
	total_enemies = 0
	ending = false
	boss = null
	player = null
	streaming_enabled = true
	streaming_wait = false
	frame_times.clear()
	physics_frame_times.clear()
	physics_frame_started = 0
	explored_cells.clear()
	explored_by_sector.clear()
	explored_geometry.clear()
	visited_sectors.clear()
	discovered_bosses.clear()
	defeated_bosses.clear()
	defeated_enemies.clear()
	announcement = ""
	announcement_remaining = 0.0
	boss_cycle = BossCycle.new()
	boss_cycle.game = self
	boss_cycle.initialize()
	world = Node2D.new()
	world.name = "Stage"
	add_child(world)
	terrain = WorldTerrain.new()
	terrain.stage = stage
	world.add_child(terrain)
	terrain.block_removed.connect(_block_removed)
	projectiles = Node2D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)
	effects = Effects.new()
	effects.z_index = 5
	world.add_child(effects)
	stream = SectorStream.new()
	stream.game = self
	stream.initialize()
	player = Player.new()
	player.game = self
	player.position = stage.start_position
	player.z_index = 2
	world.add_child(player)
	state = "playing"
	ui.menu.hide()
	ui.settings_overlay.hide()
	world.process_mode = Node.PROCESS_MODE_INHERIT
	_update_camera(0.0, true)
	_update_exploration()
	get_viewport().gui_release_focus()
	ui.update_hud()
	last_start_metrics = {"seed": stage_seed, "generation_ms": stream.generation_times.reduce(func(a, b): return a + b, 0.0), "start_run_ms": (Time.get_ticks_usec() - started) / 1000.0, "terrain_bodies": terrain.collision_root.get_child_count(), "actors": stage.spawns.size() + 1}

func _exit_tree() -> void:
	if boss_cycle != null: boss_cycle.shutdown()
	if stream != null: stream.shutdown()

func loaded_contains(point: Vector2) -> bool:
	if not streaming_enabled or stream == null: return stage.bounds.has_point(point)
	return stream.contains(point)

func map_geometry(area: Rect2) -> Array:
	if is_instance_valid(terrain) and (not streaming_enabled or stream.contains(area.get_center())): return terrain.map_geometry(area)
	return explored_geometry.get(Vector2i((area.position / T.MAP_CELL_SIZE).floor()), [])

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_game") and not event.is_echo():
		if state == "playing":
			show_menu("paused")
		elif state == "paused":
			resume_run()
		get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ENTER and state in ["title", "paused", "lost", "won"] and not ui.seed_field.has_focus() and get_viewport().gui_get_focus_owner() == null:
		primary_action()
		get_viewport().set_input_as_handled()

func _physics_process(delta: float) -> void:
	physics_frame_started = 0
	if state == "playing" and is_instance_valid(player):
		boss_cycle.service()
		var begin := Time.get_ticks_usec()
		physics_frame_started = begin
		if streaming_enabled:
			stream.request_around(player.position,player.velocity)
			stream.service()
			var next_view := view_rect().grow(T.TILE_SIZE).merge(Rect2(player.position - T.VIEW_SIZE / 2 + player.velocity * delta, T.VIEW_SIZE))
			streaming_wait = not stream.contains_rect(next_view) or not stream.neighbourhood_ready(player.position,delta)
			world.process_mode = Node.PROCESS_MODE_DISABLED if streaming_wait else Node.PROCESS_MODE_INHERIT
			if streaming_wait:
				stream.hold_frames += 1
				_record_frame(begin)
				return
		elapsed += delta
		announcement_remaining = maxf(0, announcement_remaining - delta)
		_update_camera(delta)
		if streaming_enabled: stream.update_rewards()
		_update_exploration()
		_update_lock_marks()
		ui.update_hud()
		_record_frame(begin)

func _record_frame(begin: int) -> void:
	frame_times.append((Time.get_ticks_usec() - begin) / 1000.0)
	if frame_times.size() > T.STREAM_METRIC_SAMPLES: frame_times.pop_front()

func _finish_physics_sample() -> void:
	if physics_frame_started == 0: return
	physics_frame_times.append((Time.get_ticks_usec()-physics_frame_started)/1000.0)
	physics_frame_started = 0
	if physics_frame_times.size() > T.STREAM_METRIC_SAMPLES: physics_frame_times.pop_front()

func _update_camera(delta: float, snap: bool = false) -> void:
	if not is_instance_valid(player):
		return
	var look := clampf(player.velocity.x / T.MOVE_SPEED, -1.0, 1.0) * T.CAMERA_LOOK_AHEAD
	var fall_look := clampf(player.velocity.y / T.MAX_FALL_SPEED, 0.0, 1.0) * T.CAMERA_FALL_LOOK_AHEAD
	var focus := player.position + Vector2(look, -T.CAMERA_VERTICAL_OFFSET + fall_look)
	var target := camera.position
	if snap:
		target = focus
	else:
		var difference := focus - camera.position
		if absf(difference.x) > T.CAMERA_DEAD_ZONE.x:
			target.x = focus.x - signf(difference.x) * T.CAMERA_DEAD_ZONE.x
		if absf(difference.y) > T.CAMERA_DEAD_ZONE.y:
			target.y = focus.y - signf(difference.y) * T.CAMERA_DEAD_ZONE.y
	camera.position = target if snap else camera.position.lerp(target, 1.0 - exp(-T.CAMERA_FOLLOW_SPEED * delta))
	if snap:
		camera.reset_smoothing()

func biome_at(point: Vector2) -> int:
	return preload("res://scripts/sector_generator.gd").region_at(current_seed, SectorStream.coord_at(point))

func _update_exploration() -> void:
	if not is_instance_valid(player) or player.dead:
		return
	var radius := T.EXPLORATION_RADIUS
	var from_cell := Vector2i(((player.position - Vector2.ONE * radius) / T.MAP_CELL_SIZE).floor())
	var to_cell := Vector2i(((player.position + Vector2.ONE * radius) / T.MAP_CELL_SIZE).floor())
	for y in range(from_cell.y, to_cell.y + 1):
		for x in range(from_cell.x, to_cell.x + 1):
			var cell := Vector2i(x, y)
			var center := (Vector2(cell) + Vector2.ONE * 0.5) * T.MAP_CELL_SIZE
			if center.distance_to(player.position) <= radius:
				explored_cells[cell] = true
				var at := SectorStream.coord_at(center)
				if not explored_by_sector.has(at): explored_by_sector[at] = {}
				explored_by_sector[at][cell] = true
	visited_sectors[SectorStream.coord_at(player.position)] = true
	boss = null
	var distance := INF
	for actor in get_tree().get_nodes_in_group("enemies"):
		if actor.get_parent() != world or actor.kind != "boss" or actor.dead or actor.is_queued_for_deletion():
			continue
		if is_on_screen(actor.position, 20):
			discovered_bosses[actor.boss_id] = actor.position
			var separation := player.position.distance_squared_to(actor.position)
			if separation < distance:
				distance = separation
				boss = actor

func view_rect() -> Rect2:
	return Rect2(camera.position - T.VIEW_SIZE / 2, T.VIEW_SIZE)

func is_on_screen(point: Vector2, inset: float = 0.0) -> bool:
	return view_rect().grow(-inset).has_point(point)

func targets_for(side: int, color: int, origin: Vector2) -> Array:
	var candidates: Array = []
	var group := "enemies" if side == 0 else "players"
	for actor in get_tree().get_nodes_in_group(group):
		if not actor.dead and not actor.is_queued_for_deletion() and actor.get_parent() == world and is_on_screen(actor.global_position, 12):
			candidates.append(actor)
	candidates.sort_custom(func(a, b):
		if (a.polarity != color) != (b.polarity != color):
			return a.polarity != color
		return origin.distance_squared_to(a.global_position) < origin.distance_squared_to(b.global_position))
	if side == 0:
		var opposite := candidates.filter(func(actor): return actor.polarity != color)
		if not opposite.is_empty():
			return opposite
	return candidates

func choose_homing_target(side: int, color: int, origin: Vector2, seeking: Node2D = null) -> Node2D:
	var candidates := targets_for(side, color, origin)
	if candidates.is_empty():
		return null
	if side != 0:
		return candidates[0] # Enemy missiles still target only the player.
	var selected: Node2D = null
	var least := 2147483647
	for candidate in candidates:
		var count := 0
		for missile in projectiles.get_children():
			if missile == seeking or not missile is Bullet or not missile.homing or missile.faction != 0 or missile.is_queued_for_deletion():
				continue
			if missile.target == candidate:
				count += 1
		if count < least:
			selected = candidate
			least = count
	return selected

func lock_on_targets() -> Array:
	var marked: Array = []
	if not is_instance_valid(player) or player.dead:
		return marked
	var candidates := targets_for(0, player.polarity, player.global_position)
	for index in range(mini(T.HOMING_VOLLEY_SIZE if player.homing_charges > 0 else 0, candidates.size())):
		marked.append(candidates[index])
	for missile in projectiles.get_children():
		if not missile is Bullet or not missile.homing or missile.faction != 0 or missile.is_queued_for_deletion(): continue
		var target = missile.target
		if is_instance_valid(target) and not target.dead and not target.is_queued_for_deletion() and target.get_parent() == world and is_on_screen(target.position, 12) and not marked.has(target):
			marked.append(target)
	return marked

func _update_lock_marks() -> void:
	var marked := lock_on_targets()
	for actor in get_tree().get_nodes_in_group("enemies"):
		if actor.get_parent() == world:
			var next_mark := marked.has(actor)
			if actor.lock_marked != next_mark:
				actor.lock_marked = next_mark
				actor.queue_redraw()

func spawn_bullet(actor: CharacterBody2D, direction: Vector2, guided: bool = false, target: Node2D = null) -> Node2D:
	var bullet := Bullet.new()
	bullet.game = self
	bullet.faction = actor.faction
	bullet.polarity = actor.polarity
	bullet.direction = direction.normalized()
	bullet.homing = guided
	bullet.target = target
	if actor.faction == 0:
		bullet.damage = T.HOMING_DAMAGE if guided else T.NORMAL_DAMAGE
	else:
		bullet.damage = T.ENEMY_HOMING_DAMAGE if guided else T.ENEMY_NORMAL_DAMAGE
	if guided:
		bullet.speed = T.PLAYER_HOMING_SPEED if actor.faction == 0 else T.ENEMY_HOMING_SPEED
	else:
		bullet.speed = T.PLAYER_BULLET_SPEED if actor.faction == 0 else T.ENEMY_BULLET_SPEED
	if actor.faction == 0 and not guided:
		bullet.position = actor.position + actor.muzzle_offset(bullet.direction)
	else:
		var launch_side: float = signf(direction.x) if guided else float(actor.facing)
		bullet.position = actor.position + Vector2(launch_side * (actor.body_size.x / 2 + 9), -4)
	projectiles.add_child(bullet)
	return bullet

func spawn_laser(actor: CharacterBody2D) -> Node2D:
	var beam := LaserBeam.new()
	beam.game = self
	beam.source = actor
	beam.set_meta("source_sector", SectorStream.coord_at(actor.position))
	beam.polarity = actor.polarity
	beam.build_curve(actor.global_position + Vector2(actor.facing * (actor.body_size.x / 2 + 9), -4), player.global_position, actor.facing)
	projectiles.add_child(beam)
	beam.clip_path()
	return beam

func spawn_bomb_warning(actor: CharacterBody2D) -> Node2D:
	var bomb := Bomb.new()
	bomb.game = self
	bomb.source = actor
	bomb.set_meta("source_sector", SectorStream.coord_at(actor.position))
	bomb.polarity = actor.polarity
	bomb.target = player.global_position + Vector2(0, player.body_size.y / 2)
	projectiles.add_child(bomb)
	return bomb

func fire_special(actor: CharacterBody2D, amount: int) -> void:
	if amount <= 0:
		return
	var candidates := targets_for(actor.faction, actor.polarity, actor.global_position)
	var opposite: Array = candidates.filter(func(target): return target.polarity != actor.polarity)
	if not opposite.is_empty():
		candidates = opposite
	for index in range(amount):
		var target: Node2D = candidates[index % candidates.size()] if not candidates.is_empty() else null
		var spread := (float(index) - float(amount - 1) / 2) * 0.13
		var direction: Vector2 = (target.global_position - actor.global_position).normalized() if is_instance_valid(target) else Vector2(actor.facing, 0)
		direction = direction.rotated(spread)
		spawn_bullet(actor, direction, true, target)
	effect(actor.global_position, T.COLORS[actor.polarity], "switch")

func effect(at: Vector2, tint: Color, effect_kind: String) -> void:
	if is_instance_valid(effects):
		effects.emit(at, tint, effect_kind)

func show_damage(at: Vector2, amount: int) -> void:
	if is_instance_valid(effects) and amount > 0:
		var view := view_rect()
		at.x = clampf(at.x, view.position.x + 32, view.end.x - 32)
		effects.show_damage(at, amount)

func _block_removed(bounds: Rect2, player_attack: bool) -> void:
	if stream != null: stream.remember_block(bounds)
	if player_attack and is_instance_valid(player): player.heal(T.BLOCK_HEAL)

func actor_defeated(actor: CharacterBody2D) -> void:
	if actor.has_method("cancel_attack"):
		actor.cancel_attack()
	if actor.get_parent() != world:
		return
	if actor.faction == 0:
		if not ending:
			ending = true
			call_deferred("_finish_run")
		return
	if defeated_enemies.has(actor.spawn_id):
		return
	defeated_enemies[actor.spawn_id] = true
	if is_instance_valid(player) and not player.dead:
		var reward := T.ENEMY_CHARGE_REWARD
		if actor.kind == "boss":
			reward = {"guardian": T.BOSS_CHARGE_REWARD, "final": T.FINAL_BOSS_CHARGE_REWARD, "secret": T.SECRET_BOSS_CHARGE_REWARD}[actor.boss_role]
		player.add_homing_charges(reward)
	if stream != null and actor.kind != "boss": stream.remember_enemy(actor)
	effect(actor.position, T.COLORS[actor.polarity], "defeat")
	if actor.kind == "boss":
		if defeated_bosses.has(actor.boss_id):
			return
		defeated_bosses[actor.boss_id] = true
		score += {"guardian": T.BOSS_SCORE, "final": T.FINAL_BOSS_SCORE, "secret": T.SECRET_BOSS_SCORE}[actor.boss_role]
		boss_cycle.defeated(actor)
	else:
		score += T.ENEMY_SCORE
		kills += 1

func _finish_run() -> void:
	if not is_instance_valid(player) or player.dead:
		show_menu("lost")
	elif boss_cycle.phase == "complete":
		show_menu("won")
	else:
		ending = false

func resume_run() -> void:
	state = "playing"
	ui.menu.hide()
	world.process_mode = Node.PROCESS_MODE_INHERIT
	get_viewport().gui_release_focus()

func open_key_settings() -> void:
	settings_return_state = "paused" if state == "playing" else state
	state = "settings"
	world.process_mode = Node.PROCESS_MODE_DISABLED
	ui.menu.hide()
	ui.settings_overlay.show()
	ui.settings_panel.open()

func close_key_settings() -> void:
	ui.settings_panel.hide()
	ui.settings_panel.set_process_input(false)
	ui.settings_overlay.hide()
	ui.refresh_bindings()
	show_menu(settings_return_state)

func show_menu(next_state: String) -> void:
	state = next_state
	world.process_mode = Node.PROCESS_MODE_DISABLED
	ui.show_menu(next_state)

func primary_action() -> void:
	if state == "paused":
		resume_run()
	elif state == "title":
		var text: String = ui.seed_field.text.strip_edges()
		if not text.is_valid_int():
			ui.seed_field.text = str(current_seed)
			return
		start_run(int(text))
	else:
		start_run(current_seed)

func new_action() -> void:
	if state == "paused":
		start_run(current_seed)
	elif state == "title":
		start_run(_random_seed())
		show_menu("title")
	else:
		start_run(_random_seed())

func clock_text() -> String:
	return "%02d:%02d" % [int(elapsed) / 60, int(elapsed) % 60]

func announce(message: String) -> void:
	announcement = message
	announcement_remaining = T.BOSS_ANNOUNCEMENT_TIME
