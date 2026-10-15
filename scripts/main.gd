extends Node2D
const T := preload("res://scripts/tuning.gd")
const Generator := preload("res://scripts/stage_generator.gd")
const Player := preload("res://scripts/player.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Bullet := preload("res://scripts/projectile.gd")
const RoomTerrain := preload("res://scripts/room_terrain.gd")
const RoomBackdrop := preload("res://scripts/room_backdrop.gd")
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
var projectiles: Node2D
var effects: Node2D
var camera: Camera2D
var ui: CanvasLayer
var ending := false
var key_bindings: RefCounted
var controls_path := "user://controls.cfg"
var settings_return_state := "title"
var current_room_id := -1
var visited_rooms: Dictionary = {}
var defeated_bosses: Dictionary = {}
var defeated_enemies: Dictionary = {}
var travel_cooldown := 0.0
var travel_pending := false
var door_font: SystemFont

func _ready() -> void:
	_register_inputs()
	door_font = SystemFont.new()
	door_font.font_names = PackedStringArray(["Yu Gothic UI", "Meiryo", "Noto Sans CJK JP"])
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
	current_room_id = -1
	visited_rooms.clear()
	defeated_bosses.clear()
	defeated_enemies.clear()
	travel_pending = false
	travel_cooldown = 0.0
	world = Node2D.new()
	world.name = "Stage"
	add_child(world)
	for room: Dictionary in stage.rooms:
		var background := RoomBackdrop.new()
		background.room = room
		background.position = room.origin
		background.z_index = -2
		world.add_child(background)
		var terrain := RoomTerrain.new()
		terrain.room = room
		terrain.position = room.origin
		world.add_child(terrain)
		for spawn: Dictionary in room.spawns:
			var enemy := Enemy.new()
			enemy.game = self
			enemy.kind = spawn.kind
			enemy.polarity = spawn.polarity
			enemy.patrol = spawn.patrol + Vector2(room.origin.x, room.origin.x)
			enemy.position = room.origin + spawn.position
			enemy.room_id = room.id
			enemy.boss_id = spawn.boss_id
			enemy.spawn_id = spawn.id
			world.add_child(enemy)
			enemy.set_physics_process(false)
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
	player.position = stage.rooms[stage.start_room].origin + Vector2(256, T.ROOM_FLOOR_Y - T.PLAYER_SIZE.y / 2)
	player.z_index = 2
	world.add_child(player)
	state = "playing"
	ui.menu.hide()
	ui.settings_overlay.hide()
	world.process_mode = Node.PROCESS_MODE_INHERIT
	_set_current_room(stage.start_room)
	get_viewport().gui_release_focus()
	ui.update_hud()
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if state == "playing" and event.is_action_pressed("interact") and not event.is_echo():
		try_travel()
		get_viewport().set_input_as_handled()
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
		travel_cooldown = maxf(0.0, travel_cooldown - delta)
		ui.update_hud()
	queue_redraw()

func current_room() -> Dictionary:
	if current_room_id < 0 or stage.is_empty():
		return {}
	return stage.rooms[current_room_id]

func nearby_door() -> Dictionary:
	if not is_instance_valid(player) or player.dead:
		return {}
	var nearest: Dictionary = {}
	var distance := T.DOOR_INTERACT_RADIUS
	for door: Dictionary in current_room().get("doors", []):
		var separation: float = player.position.distance_to(current_room().origin + door.position)
		if separation < distance:
			distance = separation
			nearest = door
	return nearest

func try_travel() -> bool:
	if state != "playing" or travel_pending or travel_cooldown > 0:
		return false
	var door := nearby_door()
	if door.is_empty():
		return false
	travel_pending = true
	call_deferred("_travel", door.target)
	return true

func _travel(target_id: int) -> void:
	travel_pending = false
	if state != "playing" or not is_instance_valid(player) or player.dead:
		return
	var linked := false
	for door: Dictionary in current_room().doors:
		if door.target == target_id:
			linked = true
	if not linked:
		return
	var destination: Dictionary = stage.rooms[target_id]
	for door: Dictionary in destination.doors:
		if door.target != current_room_id:
			continue
		# No projectile or queued jump follows a player through a passage.
		for bullet in projectiles.get_children():
			bullet.free()
		effects.bursts.clear()
		effects.damage_numbers.clear()
		player.position = destination.origin + door.arrival
		player.velocity = Vector2.ZERO
		player.jump_buffer = 0.0
		player.coyote = 0.0
		player.pending_special = false
		player.jump_cut_requested = false
		player.facing = -1 if door.direction == "east" else 1
		_set_current_room(target_id)
		travel_cooldown = T.ROOM_TRAVEL_COOLDOWN
		ui.update_hud()
		return

func _set_current_room(room_id: int) -> void:
	current_room_id = room_id
	visited_rooms[room_id] = true
	camera.position = current_room().rect.get_center()
	camera.reset_smoothing()
	boss = null
	for actor in get_tree().get_nodes_in_group("enemies"):
		if actor.get_parent() != world or actor.is_queued_for_deletion():
			continue
		var active: bool = actor.room_id == room_id and not actor.dead
		actor.set_physics_process(active)
		actor.was_visible = false
		actor.wake_delay = T.ENEMY_WAKE_DELAY
		actor.action = "idle"
		actor.velocity = Vector2.ZERO
		if active and actor.kind == "boss":
			boss = actor
	queue_redraw()

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

func _draw() -> void:
	if not is_instance_valid(camera):
		return
	if current_room().is_empty():
		return
	var near := nearby_door()
	for door: Dictionary in current_room().doors:
		var at: Vector2 = current_room().origin + door.position
		var selected: bool = not near.is_empty() and near.target == door.target
		var tint := Color("d8e7c6") if selected else Color("7b958a")
		draw_rect(Rect2(at - Vector2(28, 44), Vector2(56, 88)), Color("102127"))
		draw_rect(Rect2(at - Vector2(28, 44), Vector2(56, 88)), tint, false, 3 if selected else 1)
		var symbol: String = {"west": "←", "east": "→", "north": "↑", "south": "↓"}[door.direction]
		draw_string(door_font, at + Vector2(-16, 8), symbol, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, tint)
		if selected:
			var caption: String = "%s 移動" % key_bindings.get_binding_text("interact")
			var width := door_font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			draw_string(door_font, at + Vector2(-width / 2, -56), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
