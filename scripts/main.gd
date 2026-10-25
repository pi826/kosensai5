extends Node2D
const T := preload("res://scripts/tuning.gd")
const Generator := preload("res://scripts/stage_generator.gd")
const Player := preload("res://scripts/player.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Bullet := preload("res://scripts/projectile.gd")
const LaserBeam := preload("res://scripts/laser_beam.gd")
const Bomb := preload("res://scripts/bomb.gd")
const WorldTerrain := preload("res://scripts/world_terrain.gd")
const WorldBackdrop := preload("res://scripts/world_backdrop.gd")
const Effects := preload("res://scripts/effects.gd")
const Interface := preload("res://scripts/interface.gd")
const KeyBindings := preload("res://scripts/key_bindings.gd")

var stage: Dictionary = {}
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

func _ready() -> void:
	_register_inputs()
	camera = Camera2D.new()
	camera.position = T.VIEW_SIZE / 2
	add_child(camera)
	ui = Interface.new()
	ui.game = self
	add_child(ui)
	start_run(_random_seed())
	show_menu("title")

func _register_inputs() -> void:
	key_bindings = KeyBindings.new()
	key_bindings.load_settings(controls_path)

func _random_seed() -> int:
	return int(Time.get_ticks_usec() % 2147483647)

func start_run(stage_seed: int) -> void:
	if is_instance_valid(world):
		remove_child(world)
		world.queue_free()
	stage = Generator.generate(stage_seed)
	current_seed = stage_seed
	score = 0
	elapsed = 0.0
	kills = 0
	total_enemies = 0
	ending = false
	boss = null
	explored_cells.clear()
	discovered_bosses.clear()
	defeated_bosses.clear()
	defeated_enemies.clear()
	world = Node2D.new()
	world.name = "Stage"
	add_child(world)
	var background := WorldBackdrop.new()
	background.stage = stage
	world.add_child(background)
	terrain = WorldTerrain.new()
	terrain.stage = stage
	world.add_child(terrain)
	for spawn: Dictionary in stage.spawns:
		var enemy := Enemy.new()
		enemy.game = self
		enemy.kind = spawn.kind
		enemy.polarity = spawn.polarity
		enemy.patrol = spawn.patrol
		enemy.position = spawn.position
		enemy.boss_id = spawn.boss_id
		enemy.spawn_id = spawn.id
		world.add_child(enemy)
		if enemy.kind != "boss":
			total_enemies += 1
	projectiles = Node2D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)
	effects = Effects.new()
	effects.z_index = 5
	world.add_child(effects)
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

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_game") and not event.is_echo():
		if state == "playing":
			show_menu("paused")
		elif state == "paused":
			resume_run()
		get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ENTER and state in ["title", "paused", "lost", "won"] and not ui.seed_field.has_focus():
		primary_action()
		get_viewport().set_input_as_handled()

func _physics_process(delta: float) -> void:
	if state == "playing" and is_instance_valid(player):
		elapsed += delta
		_update_camera(delta)
		_update_exploration()
		ui.update_hud()

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
	var half := T.VIEW_SIZE / 2
	var bounds: Rect2 = stage.bounds
	target.x = clampf(target.x, bounds.position.x + half.x, bounds.end.x - half.x)
	target.y = clampf(target.y, bounds.position.y + half.y, bounds.end.y - half.y)
	camera.position = target if snap else camera.position.lerp(target, 1.0 - exp(-T.CAMERA_FOLLOW_SPEED * delta))
	if snap:
		camera.reset_smoothing()

func biome_at(point: Vector2) -> int:
	for biome: Dictionary in stage.get("biomes", []):
		if biome.rect.has_point(point):
			return biome.id
	return 0

func _update_exploration() -> void:
	if not is_instance_valid(player) or player.dead:
		return
	var bounds: Rect2 = stage.bounds
	var radius := T.EXPLORATION_RADIUS
	var from_cell := Vector2i((player.position - Vector2.ONE * radius) / T.MAP_CELL_SIZE)
	var to_cell := Vector2i((player.position + Vector2.ONE * radius) / T.MAP_CELL_SIZE)
	for y in range(from_cell.y, to_cell.y + 1):
		for x in range(from_cell.x, to_cell.x + 1):
			var cell := Vector2i(x, y)
			var center := (Vector2(cell) + Vector2.ONE * 0.5) * T.MAP_CELL_SIZE
			if bounds.has_point(center) and center.distance_to(player.position) <= radius:
				explored_cells[cell] = true
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
	return candidates

func choose_homing_target(side: int, color: int, origin: Vector2) -> Node2D:
	var candidates := targets_for(side, color, origin)
	return candidates[0] if not candidates.is_empty() else null

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
	var launch_side: float = signf(direction.x) if guided else float(actor.facing)
	bullet.position = actor.position + Vector2(launch_side * (actor.body_size.x / 2 + 9), -4)
	projectiles.add_child(bullet)
	return bullet

func spawn_laser(actor: CharacterBody2D) -> Node2D:
	var beam := LaserBeam.new()
	beam.game = self
	beam.source = actor
	beam.polarity = actor.polarity
	beam.build_curve(actor.global_position + Vector2(actor.facing * (actor.body_size.x / 2 + 9), -4), player.global_position, actor.facing)
	projectiles.add_child(beam)
	beam.clip_path()
	return beam

func spawn_bomb_warning(actor: CharacterBody2D) -> Node2D:
	var bomb := Bomb.new()
	bomb.game = self
	bomb.source = actor
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
	effect(actor.position, T.COLORS[actor.polarity], "defeat")
	if actor.kind == "boss":
		if defeated_bosses.has(actor.boss_id):
			return
		defeated_bosses[actor.boss_id] = true
		score += T.BOSS_SCORE
		if defeated_bosses.size() == 3 and not ending:
			ending = true
			call_deferred("_finish_run")
	else:
		score += T.ENEMY_SCORE
		kills += 1

func _finish_run() -> void:
	if not is_instance_valid(player) or player.dead:
		show_menu("lost")
	elif defeated_bosses.size() == 3:
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
