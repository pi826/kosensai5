extends Node2D
const T := preload("res://scripts/tuning.gd")
const SectorStream := preload("res://scripts/sector_stream.gd")
const Player := preload("res://scripts/player.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Bullet := preload("res://scripts/projectile.gd")
const TrailLayer := preload("res://scripts/trail_layer.gd")
const LaserBeam := preload("res://scripts/laser_beam.gd")
const Bomb := preload("res://scripts/bomb.gd")
const WorldTerrain := preload("res://scripts/streamed_terrain.gd")
const WorldBackdrop := preload("res://scripts/world_backdrop.gd")
const Effects := preload("res://scripts/effects.gd")
const Interface := preload("res://scripts/interface.gd")
const KeyBindings := preload("res://scripts/key_bindings.gd")
const BossCycle := preload("res://scripts/boss_cycle.gd")
const O := preload("res://scripts/origin_shift.gd")
const AudioDirector := preload("res://scripts/audio_director.gd")
var audio: Node
var boss_impact: CanvasLayer
var impact_effect_override := -1
var audio_settings_path := "user://audio.cfg"
var audio_synthesis_override := -1
var audio_return_state := "title"

func play_sound(id: String, at: Variant = null, volume_db: float = 0, pitch: float = 1, color: int = -1) -> int:
	if not is_instance_valid(audio): return -1
	return audio.play(id, at, volume_db, pitch, self, color)

func open_audio_settings() -> void:
	audio_return_state = state
	state = "audio_settings"
	world.process_mode = Node.PROCESS_MODE_DISABLED
	ui.menu.hide()
	ui.audio_overlay.show()
	ui.audio_panel.open()
	play_sound("ui_confirm")

func close_audio_settings() -> void:
	ui.audio_overlay.hide()
	show_menu(audio_return_state)
	ui.audio_button.grab_focus()
var origin_sector := Vector2i.ZERO
var origin_shift_count := 0
var origin_shift_times: Array[float] = []

func map_origin() -> Vector2i:
	return origin_sector * Vector2i(T.SECTOR_SIZE / T.MAP_CELL_SIZE)

func stable_point(point: Vector2) -> Dictionary:
	return O.point(point, origin_sector)

func local_point(point: Dictionary) -> Vector2:
	return O.unpack(point, origin_sector)

func boss_mark(id: int) -> Vector2:
	var mark = discovered_bosses[id]
	return local_point(mark) if mark is Dictionary else mark

func maybe_shift_origin() -> Vector2:
	var at := SectorStream.coord_at(player.position)
	if maxi(absi(at.x), absi(at.y)) < T.ORIGIN_SHIFT_SECTORS: return Vector2.ZERO
	return shift_origin(at)

func shift_origin(sectors: Vector2i) -> Vector2:
	if sectors == Vector2i.ZERO: return Vector2.ZERO
	var began := Time.get_ticks_usec()
	var delta := -Vector2(sectors) * T.SECTOR_SIZE
	# Called before world physics, never deferred across actor callbacks.
	origin_sector += sectors
	origin_shift_count += 1
	stage.origin_sector = origin_sector
	terrain.shift_origin(delta, origin_sector)
	if is_instance_valid(audio): audio.shift_origin(self, delta)
	stream.shift_origin(delta)
	for actor: Node in world.get_children():
		if actor.is_in_group("sprite_remnants"): actor.position += delta
		if actor == player or actor is Enemy:
			actor.position += delta
			if actor == player: player.drop_clear_y += delta.y
			if actor is Enemy:
				actor.patrol += Vector2.ONE * delta.x
				actor.flight_center_y += delta.y
				actor.resting_position += delta
				actor.arena.position += delta
				actor.roam.position += delta
				actor.charge_target += delta
				actor.wall_plan.position += delta
			actor.force_update_transform()
			actor.reset_physics_interpolation()
		elif actor.is_in_group("hearts") or actor.is_in_group("loot") or actor.is_in_group("merchants"):
			actor.position += delta
			actor.spawn = O.geometry(actor.spawn, delta)
			actor.reset_physics_interpolation()
	for shot: Node2D in projectiles.get_children():
		shot.position += delta
		if shot is Bullet: shot.trail = O.points(shot.trail, delta)
		elif shot is LaserBeam:
			shot.curve = O.points(shot.curve, delta)
			shot.path = O.points(shot.path, delta)
		elif shot is Bomb: shot.target += delta
		shot.reset_physics_interpolation()
	for field in ["bursts", "damage_numbers", "player_hp_numbers", "charge_numbers", "crystal_numbers"]:
		for entry: Dictionary in effects.get(field): entry.at += delta
	for display: Node2D in effects.get_children(): display.position += delta
	effects.queue_redraw()
	camera.position += delta
	camera.reset_physics_interpolation()
	camera.force_update_scroll()
	origin_shift_times.append((Time.get_ticks_usec()-began)/1000.0)
	if origin_shift_times.size() > T.STREAM_METRIC_SAMPLES: origin_shift_times.pop_front()
	return delta

class PhysicsProbe extends Node:
	var game: Node
	func _physics_process(_delta: float) -> void:
		game._finish_physics_sample()

var stage: Dictionary = {}
var last_start_metrics: Dictionary = {}
var current_seed := 1
var state := "title":
	set(value):
		if value != "playing" and is_instance_valid(boss_impact): boss_impact.cancel()
		state = value
var score := 0
var elapsed := 0.0
var kills := 0
var crystals := 0
var crystals_earned := 0
var keys := 0
var loot_taken: Dictionary = {}
var discovered_loot: Dictionary = {}
var loot_drops: Dictionary = {}
var loot_message := ""
var loot_message_remaining := 0.0
var loot_ability := 0
var potions := 0
var owned_equipment: Dictionary = {}
var merchant_sold: Dictionary = {}
var discovered_merchants: Dictionary = {}
var active_merchant: Dictionary = {}
var shop_return_state := "playing"
var last_shop_action_ms := -1000
var total_enemies := 0
var player: CharacterBody2D
var boss: CharacterBody2D
var world: Node2D
var terrain: Node2D
var projectiles: Node2D
var trail_layer: Node2D
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
var explored_images: Dictionary = {}
var map_sector_revisions: Dictionary = {}
var _map_record_revision := -1
var _lock_marked: Array = []
var stream: RefCounted
var streaming_enabled := true
var streaming_wait := false
var stream_install_ms := 0.0
var stream_service_did_work := false # OR across physics callbacks until the next redraw.
var frame_times: Array[float] = []
var physics_frame_times: Array[float] = []
var physics_frame_started := 0
var boss_cycle: RefCounted
var announcement := ""
var announcement_remaining := 0.0
var boss_arrow_unlocked := false
var tutorial_session: Node2D
var tutorial_layer: CanvasLayer
var tutorial_seed_text := ""

func enemy_loop_level() -> int:
	return clampi(boss_cycle.final_clears, 0, T.FINAL_BOSS_CLEARS) if boss_cycle != null and not is_tutorial() else 0

func update_loop_scaling() -> void:
	if is_tutorial(): return
	play_sound("loop_up")
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.get_parent() == world and not enemy.dead: enemy.apply_loop(enemy_loop_level())
	if stream != null: stream.queue_population()
	loot_message = T.LOOP_NOTICE
	loot_message_remaining = T.LOOT_MESSAGE_TIME
	loot_ability = 0

func is_tutorial() -> bool:
	return false

func start_tutorial() -> void:
	if is_instance_valid(tutorial_session): return
	if is_instance_valid(boss_impact): boss_impact.cancel()
	if is_instance_valid(audio): audio.reset_run()
	play_sound("ui_confirm")
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
	tutorial_session.audio = audio
	tutorial_session.audio_settings_path = audio_settings_path
	viewport.add_child(tutorial_session)

func finish_tutorial(begin_main: bool = false) -> void:
	if is_instance_valid(audio): audio.reset_run()
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
	if is_instance_valid(audio): audio.stop_world()
	play_sound("ui_back")
	show_menu("title")

func _ready() -> void:
	var sprite_loader := preload("res://scripts/sprite_loader.gd").new()
	sprite_loader.game = self
	add_child(sprite_loader)
	process_physics_priority = -100
	process_priority = 1000 # Redraw after world callbacks (excavation, walls, restores).
	_register_inputs()
	audio = AudioDirector.new()
	audio.game = self
	audio.synthesis_override = audio_synthesis_override
	add_child(audio)
	camera = Camera2D.new()
	camera.position = T.VIEW_SIZE / 2
	camera.limit_enabled = false
	add_child(camera)
	ui = Interface.new()
	ui.game = self
	add_child(ui)
	boss_impact = preload("res://scripts/boss_impact.gd").new()
	boss_impact.game = self
	boss_impact.override_enabled = impact_effect_override
	add_child(boss_impact)
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
	if is_instance_valid(boss_impact): boss_impact.cancel()
	var started := Time.get_ticks_usec()
	if is_instance_valid(audio): audio.reset_run()
	stream_install_ms = 0.0
	stream_service_did_work = false
	if boss_cycle != null: boss_cycle.shutdown()
	if stream != null: stream.shutdown()
	if is_instance_valid(world):
		remove_child(world)
		world.free()
	current_seed = stage_seed
	origin_sector = Vector2i.ZERO
	origin_shift_count = 0
	origin_shift_times.clear()
	stage = {"seed": stage_seed, "streaming": true, "bounds": Rect2(), "start_position": T.SECTOR_START, "origin_sector": origin_sector}
	score = 0
	elapsed = 0.0
	kills = 0
	boss_arrow_unlocked = false
	crystals = 0
	crystals_earned = 0
	keys = 0
	loot_taken.clear()
	discovered_loot.clear()
	loot_drops.clear()
	loot_message = ""
	loot_message_remaining = 0.0
	loot_ability = 0
	potions = 0
	owned_equipment.clear()
	merchant_sold.clear()
	discovered_merchants.clear()
	active_merchant.clear()
	last_shop_action_ms = -1000
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
	_lock_marked.clear()
	explored_images.clear()
	map_sector_revisions.clear()
	ui.large_map.clear_cache()
	ui.minimap.clear_cache()
	_map_record_revision = -1
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
	terrain.sound_requested.connect(play_sound)
	trail_layer = TrailLayer.new()
	trail_layer.name = "Trails"
	trail_layer.game = self
	world.add_child(trail_layer)
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
	ui.shop_panel.hide()
	ui.large_map.hide()
	ui.audio_overlay.hide()
	world.process_mode = Node.PROCESS_MODE_INHERIT
	_update_camera(0.0, true)
	_update_exploration()
	get_viewport().gui_release_focus()
	ui.update_hud()
	last_start_metrics = {"seed": stage_seed, "generation_ms": stream.generation_times.reduce(func(a, b): return a + b, 0.0), "start_run_ms": (Time.get_ticks_usec() - started) / 1000.0, "terrain_bodies": terrain.collision_body_count(), "actors": stage.spawns.size() + 1}

func _exit_tree() -> void:
	if is_instance_valid(boss_impact): boss_impact.cancel()
	if boss_cycle != null: boss_cycle.shutdown()
	if stream != null: stream.shutdown()

func loaded_contains(point: Vector2) -> bool:
	if not streaming_enabled or stream == null: return stage.bounds.has_point(point)
	return stream.contains(point)

func map_geometry(area: Rect2) -> Array:
	if is_instance_valid(terrain) and (not streaming_enabled or stream.contains(area.get_center())): return terrain.map_geometry(area)
	var cell := Vector2i((area.position / T.MAP_CELL_SIZE).floor())
	return O.geometry(explored_geometry.get(cell + map_origin(), []), Vector2(cell) * T.MAP_CELL_SIZE)

func record_map_cell(cell: Vector2i) -> void:
	if not is_instance_valid(terrain): return
	var corner := Vector2(cell - map_origin()) * T.MAP_CELL_SIZE
	# Merge adjacent tile rectangles into horizontal runs, then vertical runs.
	# Entries are cell-local; integer cell + sector index never shift with origin.
	var fragments: Array = O.geometry(terrain.map_geometry(Rect2(corner, Vector2.ONE * T.MAP_CELL_SIZE)), -corner)
	fragments.sort_custom(func(a: Rect2, b: Rect2): return a.position.y < b.position.y or (a.position.y == b.position.y and a.position.x < b.position.x))
	var rows: Array[Rect2] = []
	for rect: Rect2 in fragments:
		if not rows.is_empty() and rows[-1].position.y == rect.position.y and rows[-1].size.y == rect.size.y and rows[-1].end.x == rect.position.x:
			rows[-1] = rows[-1].merge(rect)
		else: rows.append(rect)
	var merged: Array[Rect2] = []
	for rect: Rect2 in rows:
		var found := false
		for i in range(merged.size()):
			if merged[i].position.x == rect.position.x and merged[i].size.x == rect.size.x and merged[i].end.y == rect.position.y:
				merged[i] = merged[i].merge(rect)
				found = true
				break
		if not found: merged.append(rect)
	explored_geometry[cell] = merged
	var dimensions := Vector2i(T.SECTOR_SIZE / T.MAP_CELL_SIZE)
	var sector := Vector2i(floori(float(cell.x) / dimensions.x), floori(float(cell.y) / dimensions.y))
	var tile_ratio := T.MAP_CELL_SIZE / T.TILE_SIZE
	if not explored_images.has(sector):
		explored_images[sector] = Image.create_empty(dimensions.x * tile_ratio, dimensions.y * tile_ratio, false, Image.FORMAT_RGBA8)
	var image: Image = explored_images[sector]
	var offset := (cell - sector * dimensions) * tile_ratio
	var biome := preload("res://scripts/sector_generator.gd").region_at(current_seed, sector)
	var theme: Dictionary = preload("res://scripts/world_terrain.gd").THEMES[biome]
	image.fill_rect(Rect2i(offset, Vector2i.ONE * tile_ratio), Color(theme.back, 0.85))
	for rect: Rect2 in merged:
		var pixels := Rect2i(Vector2i((rect.position / T.TILE_SIZE).floor()) + offset, Vector2i((rect.size / T.TILE_SIZE).ceil()).max(Vector2i.ONE))
		image.fill_rect(pixels.intersection(Rect2i(offset, Vector2i.ONE * tile_ratio)), theme.edge)
	map_sector_revisions[sector] = map_sector_revisions.get(sector, 0) + 1

func open_map() -> void:
	if state != "playing" or is_tutorial() or ending or not is_instance_valid(player) or player.dead: return
	state = "map"
	play_sound("map_open")
	world.process_mode = Node.PROCESS_MODE_DISABLED
	player.pending_special = false
	player.pending_dash = false
	ui.large_map.open()
	ui.update_hud()

func close_map() -> void:
	if state != "map": return
	play_sound("map_close")
	ui.large_map.hide()
	resume_run()
	ui.update_hud()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("world_map") and not event.is_echo() and state == "playing":
		open_map()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause_game") and not event.is_echo():
		if state == "playing":
			show_menu("paused")
		elif state == "paused":
			play_sound("ui_back")
			resume_run()
		get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ENTER and state in ["title", "paused", "lost", "won"] and not ui.seed_field.has_focus() and get_viewport().gui_get_focus_owner() == null:
		primary_action()
		get_viewport().set_input_as_handled()

func _physics_process(delta: float) -> void:
	physics_frame_started = 0
	if state == "playing" and is_instance_valid(player):
		var begin := Time.get_ticks_usec()
		physics_frame_started = begin
		if streaming_enabled: maybe_shift_origin()
		boss_cycle.service()
		if streaming_enabled:
			stream.request_around(player.position,player.velocity)
			stream.service()
			stream_install_ms += stream.service_times[-1]
			stream_service_did_work = stream_service_did_work or stream.service_did_work
			var next_view := stream_view_rect(delta)
			terrain.prepare_view(next_view)
			stream.prepare_backdrop_view(next_view)
			streaming_wait = not stream.contains_rect(next_view) or not stream.neighbourhood_ready(player.position,delta) or not terrain.view_is_current(next_view)
			world.process_mode = Node.PROCESS_MODE_DISABLED if streaming_wait else Node.PROCESS_MODE_INHERIT
			if streaming_wait:
				stream.hold_frames += 1
				_record_frame(begin)
				return
		elapsed += delta
		announcement_remaining = maxf(0, announcement_remaining - delta)
		loot_message_remaining = maxf(0, loot_message_remaining - delta)
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

func stream_view_rect(delta: float = 1.0 / 60.0) -> Rect2:
	# Contains the present and next camera view, plus a conservative envelope
	# for a dash/fall and ceiling correction before the next physics check.
	var next := Rect2(camera_target(delta) - T.VIEW_SIZE / 2, T.VIEW_SIZE)
	var movement := maxf(T.AIR_DASH_SPEED, T.MAX_FALL_SPEED) * delta + T.CEILING_CORRECTION
	return view_rect().merge(next).grow(T.STREAM_VIEW_MARGIN + movement)

func _process(_delta: float) -> void:
	if not streaming_enabled or stream == null or not is_instance_valid(terrain) or not is_instance_valid(player) or not world.visible: return
	var area := stream_view_rect()
	stream.prepare_backdrop_view(area)
	terrain.service_redraw(area, stream.priority_point, maxf(0.0, T.STREAM_DRAW_BUDGET_MS - stream_install_ms), stream_service_did_work)
	stream_install_ms = 0.0
	stream_service_did_work = false

func _update_camera(delta: float, snap: bool = false) -> void:
	if not is_instance_valid(player):
		return
	camera.position = camera_target(delta, snap)
	if snap:
		camera.reset_smoothing()

func camera_target(delta: float, snap: bool = false) -> Vector2:
	var look := clampf(player.velocity.x / T.MOVE_SPEED, -1.0, 1.0) * T.CAMERA_LOOK_AHEAD
	var gravity: int = player.get("gravity_sign") if player.get("gravity_sign") != null else 1
	var fall_look := clampf(player.velocity.y * gravity / T.MAX_FALL_SPEED, 0.0, 1.0) * T.CAMERA_FALL_LOOK_AHEAD * gravity
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
	return target if snap else camera.position.lerp(target, 1.0 - exp(-T.CAMERA_FOLLOW_SPEED * delta))

func biome_at(point: Vector2) -> int:
	return preload("res://scripts/sector_generator.gd").region_at(current_seed, origin_sector + SectorStream.coord_at(point))

func _update_exploration() -> void:
	if not is_instance_valid(player) or player.dead:
		return
	var revision: int = terrain.revision if is_instance_valid(terrain) else -1
	var refresh_geometry := revision != _map_record_revision
	_map_record_revision = revision
	var view := view_rect()
	var radius := T.EXPLORATION_RADIUS
	var from_cell := Vector2i(((player.position - Vector2.ONE * radius) / T.MAP_CELL_SIZE).floor())
	var to_cell := Vector2i(((player.position + Vector2.ONE * radius) / T.MAP_CELL_SIZE).floor())
	for y in range(from_cell.y, to_cell.y + 1):
		for x in range(from_cell.x, to_cell.x + 1):
			var cell := Vector2i(x, y)
			var center := (Vector2(cell) + Vector2.ONE * 0.5) * T.MAP_CELL_SIZE
			if center.distance_to(player.position) <= radius:
				var stable_cell := cell + map_origin()
				if not refresh_geometry and explored_cells.has(stable_cell) and explored_geometry.has(stable_cell): continue
				explored_cells[stable_cell] = true
				var at := origin_sector + SectorStream.coord_at(center)
				if not explored_by_sector.has(at): explored_by_sector[at] = {}
				explored_by_sector[at][stable_cell] = true
				if refresh_geometry or not explored_geometry.has(stable_cell): record_map_cell(stable_cell)
	visited_sectors[origin_sector + SectorStream.coord_at(player.position)] = true
	for merchant in get_tree().get_nodes_in_group("merchants"):
		if merchant.get_parent() != world: continue
		if view.intersects(Rect2(merchant.position - T.MERCHANT_SIZE / 2, T.MERCHANT_SIZE)):
			discovered_merchants[merchant.spawn.id] = stable_point(merchant.position)
	for item in get_tree().get_nodes_in_group("loot"):
		if item.get_parent() != world or item.spawn.kind == "crystal" or loot_taken.has(item.spawn.id): continue
		if view.intersects(Rect2(item.position - T.LOOT_SIZE / 2, T.LOOT_SIZE)):
			var mark := stable_point(item.position)
			mark.kind = item.spawn.kind
			mark.ability = item.spawn.get("contents", []).any(func(c): return c.kind == "ability")
			discovered_loot[item.spawn.id] = mark
	boss = null
	var distance := INF
	var boss_view := view.grow(-20)
	for actor in get_tree().get_nodes_in_group("bosses"):
		if actor.get_parent() != world or actor.kind != "boss" or actor.dead or actor.is_queued_for_deletion():
			continue
		if boss_view.has_point(actor.position):
			discovered_bosses[actor.boss_id] = stable_point(actor.position)
			var separation := player.position.distance_squared_to(actor.position)
			if separation < distance:
				distance = separation
				boss = actor

func view_rect() -> Rect2:
	return Rect2(camera.position - T.VIEW_SIZE / 2, T.VIEW_SIZE)

func is_on_screen(point: Vector2, inset: float = 0.0) -> bool:
	var view := view_rect()
	var left := view.position.x + inset
	var top := view.position.y + inset
	return point.x >= left and point.y >= top and point.x < left + (view.size.x - 2.0 * inset) and point.y < top + (view.size.y - 2.0 * inset)

func boss_arrow_progress() -> String:
	if is_tutorial() or boss_arrow_unlocked: return ""
	return T.ENHANCER_NAME + "を倒すとボスの方角が分かる"

func boss_arrow_state() -> Dictionary:
	if is_tutorial() or state != "playing" or not boss_arrow_unlocked or not is_instance_valid(player) or player.dead or boss_cycle == null: return {}
	var target: Dictionary = boss_cycle.nearest_target(player.position)
	if target.is_empty(): return {}
	var bounds := Rect2(target.offset - BossCycle.size_for(target.role) / 2, BossCycle.size_for(target.role))
	var view := view_rect()
	if bounds.intersects(Rect2(view.position - player.position, view.size)): return {}
	target.direction = target.offset.normalized()
	target.distance = target.offset.length()
	return target

func targets_for(side: int, color: int, origin: Vector2) -> Array:
	var candidates: Array = []
	var group := "enemies" if side == 0 else "players"
	var view := view_rect().grow(-12)
	for actor in get_tree().get_nodes_in_group(group):
		if view.has_point(actor.global_position) and not actor.dead and not actor.is_queued_for_deletion() and actor.get_parent() == world:
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
	if player.homing_charges > 0:
		var candidates := targets_for(0, player.polarity, player.global_position)
		for index in range(mini(player.volley_size(), candidates.size())):
			marked.append(candidates[index])
	for missile in projectiles.get_children():
		if not missile is Bullet or not missile.homing or missile.faction != 0 or missile.is_queued_for_deletion(): continue
		var target = missile.target
		if is_instance_valid(target) and not target.dead and not target.is_queued_for_deletion() and target.get_parent() == world and is_on_screen(target.position, 12) and not marked.has(target):
			marked.append(target)
	return marked

func _update_lock_marks() -> void:
	var marked := lock_on_targets()
	for actor in _lock_marked:
		if not is_instance_valid(actor): continue
		if not marked.has(actor) and actor.lock_marked:
			actor.lock_marked = false
			actor.queue_redraw()
	for actor in marked:
		if not actor.lock_marked:
			actor.lock_marked = true
			actor.queue_redraw()
	_lock_marked = marked

func spawn_bullet(actor: CharacterBody2D, direction: Vector2, guided: bool = false, target: Node2D = null, color: int = -1, origin: Vector2 = Vector2.INF) -> Node2D:
	var bullet := Bullet.new()
	bullet.game = self
	bullet.faction = actor.faction
	bullet.polarity = actor.polarity if color < 0 else color
	bullet.direction = direction.normalized()
	bullet.homing = guided
	bullet.target = target
	if actor.faction == 0:
		bullet.damage = T.HOMING_DAMAGE if guided else T.NORMAL_DAMAGE
	else:
		bullet.damage = T.ENEMY_HOMING_DAMAGE if guided else T.ENEMY_NORMAL_DAMAGE
		if actor.has_method("outgoing_damage"): bullet.damage = actor.outgoing_damage(bullet.damage)
	if guided:
		bullet.speed = T.PLAYER_HOMING_SPEED if actor.faction == 0 else T.ENEMY_HOMING_SPEED
	else:
		bullet.speed = T.PLAYER_BULLET_SPEED if actor.faction == 0 else T.ENEMY_BULLET_SPEED
	if actor.faction == 0 and not guided:
		bullet.penetrations = T.BULLET_PENETRATIONS if actor.wears("pierce") else 0
		bullet.position = actor.position + actor.muzzle_offset(bullet.direction)
	else:
		var launch_side: float = signf(direction.x) if guided else float(actor.facing)
		bullet.position = actor.position + Vector2(launch_side * (actor.body_size.x / 2 + 9), -4)
	if origin != Vector2.INF: bullet.position = origin
	projectiles.add_child(bullet)
	if actor.faction == 1 and actor.kind != "boss": play_sound("enemy_homing" if guided else "enemy_shot", actor.position)
	return bullet

func spawn_laser(actor: CharacterBody2D) -> Node2D:
	var beam := LaserBeam.new()
	beam.game = self
	beam.source = actor
	beam.damage = actor.outgoing_damage(T.LASER_DAMAGE)
	beam.set_meta("source_sector", origin_sector + SectorStream.coord_at(actor.position))
	beam.polarity = actor.polarity
	beam.build_curve(actor.global_position + Vector2(actor.facing * (actor.body_size.x / 2 + 9), -4), player.global_position, actor.facing)
	projectiles.add_child(beam)
	beam.clip_path()
	beam.sound_handle = play_sound("laser_charge", actor.position)
	return beam

func spawn_bomb_warning(actor: CharacterBody2D) -> Node2D:
	var bomb := Bomb.new()
	bomb.game = self
	bomb.source = actor
	bomb.damage = actor.outgoing_damage(T.BOMB_DAMAGE)
	bomb.set_meta("source_sector", origin_sector + SectorStream.coord_at(actor.position))
	bomb.polarity = actor.polarity
	bomb.target = player.global_position + Vector2(0, player.body_size.y / 2)
	projectiles.add_child(bomb)
	play_sound("bomb_warn", actor.position)
	return bomb

func fire_special(actor: CharacterBody2D, amount: int) -> void:
	if amount <= 0:
		return
	play_sound("homing" if actor.faction == 0 else "enemy_homing", actor.position)
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
	play_sound("block_break", bounds.get_center())
	if stream != null: stream.remember_block(bounds)
	if player_attack and is_instance_valid(player): player.heal(T.BLOCK_HEAL)

func alive_summons(boss_actor: CharacterBody2D) -> int:
	var count := 0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.get_parent() == world and enemy.get_meta("summoned_by", -1) == boss_actor.boss_id and not enemy.dead and not enemy.is_queued_for_deletion(): count += 1
	return count

func summon_minions(boss_actor: CharacterBody2D, requested: int) -> void:
	var count := mini(requested, T.BOSS_SUMMON_MAX_ALIVE[boss_actor.boss_role]-alive_summons(boss_actor))
	var arena: Rect2 = boss_actor.arena
	# Subtract open forbidden intervals. Endpoints allow bodies to touch terrain
	# and make the 102px spacing exact, without a seed, RNG or grid-rounding bias.
	var subtract := func(intervals: Array, forbidden: Vector2) -> Array:
		var remaining: Array = []
		for lane: Vector2 in intervals:
			if forbidden.y <= lane.x or forbidden.x >= lane.y:
				remaining.append(lane)
			else:
				if forbidden.x >= lane.x: remaining.append(Vector2(lane.x, forbidden.x))
				if forbidden.y <= lane.y: remaining.append(Vector2(forbidden.y, lane.y))
		return remaining
	var terrain_obstacles: Array = stage.get("solids", []).filter(func(r): return r.size.y != 16) + stage.get("breakables", [])
	var screen := view_rect().grow(-16)
	var spawned: Array[Rect2] = []
	for i in range(maxi(0,count)):
		var walker := i%2 == 0
		var y: float = arena.end.y-T.ENEMY_SIZE.y/2 if walker else arena.end.y-T.ARENA_FLYER_HEIGHT
		var margin: float = maxf(64 if walker else 160, T.ENEMY_SIZE.x/2)
		if y-T.ENEMY_SIZE.y/2 < arena.position.y or y+T.ENEMY_SIZE.y/2 > arena.end.y: continue
		var lanes: Array = [Vector2(arena.position.x+margin, arena.end.x-margin)]
		# Terrain and this wave's minimum separation are hard constraints.
		for obstacle: Rect2 in terrain_obstacles + spawned:
			var padding: float = T.ENEMY_SIZE.x/2 if not spawned.has(obstacle) else T.ENEMY_SIZE.x/2+64
			if y+T.ENEMY_SIZE.y/2 <= obstacle.position.y or y-T.ENEMY_SIZE.y/2 >= obstacle.end.y: continue
			lanes = subtract.call(lanes, Vector2(obstacle.position.x-padding, obstacle.end.x+padding))
		var clear_lanes: Array = lanes.duplicate()
		for existing in get_tree().get_nodes_in_group("enemies"):
			if existing.get_parent() != world or existing.dead or existing.is_queued_for_deletion(): continue
			var body := Rect2(existing.position-existing.body_size/2, existing.body_size)
			if y+T.ENEMY_SIZE.y/2 <= body.position.y or y-T.ENEMY_SIZE.y/2 >= body.end.y: continue
			clear_lanes = subtract.call(clear_lanes, Vector2(body.position.x-T.ENEMY_SIZE.x/2, body.end.x+T.ENEMY_SIZE.x/2))
		# Keep the entire body inside the current view before relaxing distance
		# or survivor overlap. Terrain and same-wave spacing never relax.
		var visible_lanes: Array = []
		var visible_clear_lanes: Array = []
		if y-T.ENEMY_SIZE.y/2 >= screen.position.y and y+T.ENEMY_SIZE.y/2 <= screen.end.y:
			for source_index in range(2):
				var clipped: Array = []
				for lane: Vector2 in (lanes if source_index == 0 else clear_lanes):
					var left := maxf(lane.x, screen.position.x+T.ENEMY_SIZE.x/2)
					var right := minf(lane.y, screen.end.x-T.ENEMY_SIZE.x/2)
					if left <= right: clipped.append(Vector2(left,right))
				if source_index == 0: visible_lanes = clipped
				else: visible_clear_lanes = clipped
		var near_player := Vector2(player.position.x-256,player.position.x+256)
		var candidates: Array = subtract.call(visible_clear_lanes, near_player) # a
		if candidates.is_empty(): candidates = subtract.call(visible_lanes, near_player) # b
		if candidates.is_empty(): # c: distance may relax, but not player overlap.
			candidates = visible_lanes.duplicate()
			var player_body := Rect2(player.position-player.body_size/2,player.body_size)
			if y+T.ENEMY_SIZE.y/2 > player_body.position.y and y-T.ENEMY_SIZE.y/2 < player_body.end.y:
				candidates = subtract.call(candidates, Vector2(player_body.position.x-T.ENEMY_SIZE.x/2,player_body.end.x+T.ENEMY_SIZE.x/2))
		if candidates.is_empty(): candidates = clear_lanes if not clear_lanes.is_empty() else lanes # d
		if candidates.is_empty(): continue
		var x: float = candidates[0].x
		for lane: Vector2 in candidates:
			for endpoint: float in [lane.x, lane.y]:
				if absf(endpoint-player.position.x) > absf(x-player.position.x) or (absf(endpoint-player.position.x) == absf(x-player.position.x) and endpoint < x): x = endpoint
		var serial: int = get_meta("summon_serial",0)
		set_meta("summon_serial",serial+1)
		var enemy := Enemy.new()
		enemy.game = self
		enemy.kind = "walker" if i%2 == 0 else "flyer"
		enemy.polarity = (boss_actor.polarity+i)%2
		enemy.position = Vector2(x, y)
		enemy.patrol = Vector2(maxf(arena.position.x+64,x-192),minf(arena.end.x-64,x+192)) if enemy.kind == "walker" else Vector2(arena.position.x+160,arena.end.x-160)
		enemy.spawn_id = "summon:%d:%d" % [boss_actor.boss_id,serial]
		enemy.boss_id = -1
		enemy.set_meta("summoned_by",boss_actor.boss_id)
		enemy.set_meta("sector",boss_actor.get_meta("sector"))
		enemy.set_meta("chamber_id",-1)
		world.add_child(enemy)
		spawned.append(Rect2(enemy.position-T.ENEMY_SIZE/2, T.ENEMY_SIZE))
		enemy.apply_loop(enemy_loop_level())
		effect(enemy.position,T.COLORS[enemy.polarity],"switch")
		play_sound("enemy_switch",enemy.position)

func actor_defeated(actor: CharacterBody2D) -> void:
	if actor.has_method("cancel_attack"):
		actor.cancel_attack()
	if actor.get_parent() != world:
		return
	if actor.faction == 0:
		play_sound("death", actor.position)
		if not ending:
			ending = true
			call_deferred("_finish_run")
		return
	if actor.get_meta("defeat_rewarded", false) or defeated_enemies.has(actor.spawn_id):
		return
	if actor.kind == "boss" and defeated_bosses.has(actor.boss_id): return
	actor.set_meta("defeat_rewarded", true)
	if actor.kind == "boss" and is_instance_valid(boss_impact): boss_impact.start(actor.position, actor.boss_role)
	play_sound("boss_defeat" if actor.kind == "boss" else ("enhancer_defeat" if actor.kind == "enhancer" else "enemy_defeat"), actor.position)
	if actor.kind == "boss" and is_instance_valid(audio): audio.boss_defeated()
	if actor.has_meta("summoned_by"):
		effect(actor.position, T.COLORS[actor.polarity], "defeat")
		if is_instance_valid(player) and not player.dead: player.add_homing_charges(T.ENEMY_CHARGE_REWARD)
		return
	defeated_enemies[actor.spawn_id] = true
	if not is_tutorial():
		add_crystals(T.CRYSTAL_REWARDS[actor.boss_role if actor.kind == "boss" else "normal"])
		if actor.kind == "boss" and actor.boss_role == "guardian":
			var drop := stable_point(actor.position)
			drop.id = "guardian_key:%d" % actor.boss_id
			drop.kind = "key"
			loot_drops[drop.id] = drop
			stream.spawn_loot_drop(drop)
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
		for minion in get_tree().get_nodes_in_group("enemies"):
			if minion.get_parent() != world or minion.get_meta("summoned_by",-1) != actor.boss_id: continue
			minion.cancel_attack()
			minion.dead = true
			effect(minion.position, T.COLORS[minion.polarity], "defeat")
			minion.queue_free()
		defeated_bosses[actor.boss_id] = true
		score += {"guardian": T.BOSS_SCORE, "final": T.FINAL_BOSS_SCORE, "secret": T.SECRET_BOSS_SCORE}[actor.boss_role]
		boss_cycle.defeated(actor)
	else:
		score += T.ENEMY_SCORE
		kills += 1
		if actor.kind == "enhancer" and not boss_arrow_unlocked and not is_tutorial():
			boss_arrow_unlocked = true
			announce("ボスの方角が分かるようになった")
			play_sound("arrow_unlock")

func _finish_run() -> void:
	if not is_instance_valid(player) or player.dead:
		show_menu("lost")
	elif boss_cycle.phase == "complete":
		if is_instance_valid(boss_impact) and boss_impact.active: return
		show_menu("won")
	else:
		ending = false

func add_crystals(amount: int) -> void:
	if amount <= 0: return
	play_sound("crystal", player.position if is_instance_valid(player) else null, 0, 1.0 + minf(amount, 100) * 0.001)
	crystals += amount
	crystals_earned += amount
	if is_instance_valid(player) and is_instance_valid(effects): effects.show_crystals(player.position, amount)

func grant_loot(content: Dictionary) -> void:
	match content.kind:
		"crystal": add_crystals(content.amount)
		"potion":
			if potions < T.POTION_CAPACITY:
				potions += 1
				play_sound("item_get", player.position)
				loot_message = "回復薬を手に入れた（%d / %d）" % [potions, T.POTION_CAPACITY]
			else:
				add_crystals(T.DETOUR_REWARD)
				loot_message = "回復薬が満杯：結晶 +%d" % T.DETOUR_REWARD
			loot_ability = 0
			loot_message_remaining = T.LOOT_MESSAGE_TIME
		"equipment":
			var available := T.EQUIPMENT.keys().filter(func(id): return not owned_equipment.has(id))
			if available.is_empty():
				add_crystals(T.DETOUR_REWARD)
				loot_message = "装備を全て所持：結晶 +%d" % T.DETOUR_REWARD
			else:
				var id: String = available[posmod(int(content.get("roll", 0)), available.size())]
				owned_equipment[id] = true
				play_sound("item_get", player.position)
				loot_message = "%sを手に入れた。店か一時停止の「装備」で付け替え" % T.EQUIPMENT[id].name
			loot_ability = 0
			loot_message_remaining = T.LOOT_MESSAGE_TIME
		"ability":
			play_sound("ability_get", player.position)
			player.abilities |= int(content.ability)
			loot_ability = int(content.ability)
			loot_message = ability_help(content.ability)
			loot_message_remaining = T.LOOT_MESSAGE_TIME

func ability_help(ability: int) -> String:
	var jump: String = key_bindings.get_binding_text("jump")
	match ability:
		T.ABILITY_DASH: return "空中ダッシュを覚えた！ 空中で 方向（上 %s・下 %s・左 %s・右 %s）＋ %s でその方向へ（着地まで1回）" % [key_bindings.get_binding_text("move_up"), key_bindings.get_binding_text("move_down"), key_bindings.get_binding_text("move_left"), key_bindings.get_binding_text("move_right"), key_bindings.get_binding_text("dash")]
		T.ABILITY_GLIDE: return "滑空を覚えた！ 落下中に %s を押し続ける" % jump
	return ""

func nearest_chest() -> Node2D:
	if not is_instance_valid(player) or player.dead: return null
	var best: Node2D
	var distance := T.INTERACT_DISTANCE
	for item in get_tree().get_nodes_in_group("loot"):
		if item.get_parent() != world or item.spawn.kind != "chest" or item.opened: continue
		var next: float = item.position.distance_to(player.position)
		if next < distance or (is_equal_approx(next, distance) and (best == null or item.spawn.id < best.spawn.id)):
			best = item
			distance = next
	return best

func interact() -> void:
	if state != "playing" or is_tutorial(): return
	var chest := nearest_chest()
	var merchant := nearest_merchant()
	if merchant != null and (chest == null or merchant.position.distance_to(player.position) < chest.position.distance_to(player.position)):
		open_shop(merchant)
	elif chest != null: chest.try_open()

func nearest_merchant() -> Node2D:
	if not is_instance_valid(player) or player.dead: return null
	var best: Node2D
	var distance := T.INTERACT_DISTANCE
	for merchant in get_tree().get_nodes_in_group("merchants"):
		if merchant.get_parent() != world or merchant.is_queued_for_deletion(): continue
		var separation: float = player.position.distance_to(merchant.position)
		if separation < distance or (is_equal_approx(separation, distance) and (best == null or merchant.spawn.id < best.spawn.id)):
			best = merchant
			distance = separation
	return best

func interaction_hint() -> String:
	var chest := nearest_chest()
	var merchant := nearest_merchant()
	var key: String = key_bindings.get_binding_text("interact")
	if merchant != null and (chest == null or merchant.position.distance_to(player.position) < chest.position.distance_to(player.position)):
		return "%s で話す" % key
	return "%s 調べる" % key if chest != null else ""

func open_shop(merchant: Node2D) -> void:
	if state != "playing" or not is_instance_valid(merchant) or merchant != nearest_merchant(): return
	active_merchant = merchant.spawn.duplicate(true)
	shop_return_state = "playing"
	state = "shop"
	world.process_mode = Node.PROCESS_MODE_DISABLED
	player.pending_special = false
	player.pending_dash = false
	ui.menu.hide()
	ui.shop_panel.open(true)
	play_sound("shop_open")

func open_equipment() -> void:
	if state != "paused" or is_tutorial(): return
	active_merchant.clear()
	shop_return_state = "paused"
	state = "equipment"
	world.process_mode = Node.PROCESS_MODE_DISABLED
	ui.menu.hide()
	ui.shop_panel.open(false)
	play_sound("ui_confirm")

func close_shop() -> void:
	if state not in ["shop", "equipment"]: return
	play_sound("ui_back")
	ui.shop_panel.hide()
	active_merchant.clear()
	if shop_return_state == "paused": show_menu("paused")
	else: resume_run()

func purchase_reason(id: String) -> String:
	if active_merchant.is_empty() or not active_merchant.stock.has(id): return "販売していません"
	if id == "potion" and potions >= T.POTION_CAPACITY: return "所持数の上限"
	if id == "key" and merchant_sold.has(active_merchant.id): return "売り切れ"
	if T.EQUIPMENT.has(id) and owned_equipment.has(id): return "所持"
	if crystals < item_price(id): return "結晶不足"
	return ""

func item_price(id: String) -> int:
	if id == "potion": return T.POTION_PRICE
	if id == "key": return T.SHOP_KEY_PRICE
	return int(T.EQUIPMENT.get(id, {}).get("price", 0))

func buy_item(id: String) -> bool:
	if state != "shop" or not purchase_reason(id).is_empty():
		if state == "shop" and Time.get_ticks_msec() - last_shop_action_ms >= int(T.SHOP_ACTION_INTERVAL * 1000): play_sound("deny")
		return false
	var now := Time.get_ticks_msec()
	if now - last_shop_action_ms < int(T.SHOP_ACTION_INTERVAL * 1000): return false
	last_shop_action_ms = now
	crystals -= item_price(id)
	if id == "potion": potions += 1
	elif id == "key":
		keys += 1
		merchant_sold[active_merchant.id] = true
	else: owned_equipment[id] = true
	play_sound("buy")
	ui.update_hud()
	return true

func equip(slot: String, id: String) -> bool:
	if not is_instance_valid(player) or player.dead or not T.EQUIPMENT_SLOTS.has(slot): return false
	if not id.is_empty() and (not owned_equipment.has(id) or T.EQUIPMENT[id].slot != slot): return false
	player.apply_equipment(slot, id)
	play_sound("equip")
	ui.update_hud()
	return true

func use_potion() -> bool:
	if state != "playing" or is_tutorial() or potions <= 0 or not is_instance_valid(player) or player.dead:
		if state == "playing" and not is_tutorial() and is_instance_valid(player) and not player.dead: play_sound("deny")
		return false
	if player.heal(T.POTION_HEAL) <= 0:
		play_sound("deny")
		return false
	potions -= 1
	play_sound("potion", player.position)
	ui.update_hud()
	return true

func resume_run() -> void:
	state = "playing"
	if ending and boss_cycle != null and boss_cycle.phase == "complete": call_deferred("_finish_run")
	ui.menu.hide()
	ui.shop_panel.hide()
	world.process_mode = Node.PROCESS_MODE_INHERIT
	get_viewport().gui_release_focus()

func open_key_settings() -> void:
	play_sound("ui_confirm")
	settings_return_state = "paused" if state == "playing" else state
	state = "settings"
	world.process_mode = Node.PROCESS_MODE_DISABLED
	ui.menu.hide()
	ui.settings_overlay.show()
	ui.settings_panel.open()

func close_key_settings() -> void:
	play_sound("ui_back")
	ui.settings_panel.hide()
	ui.settings_panel.set_process_input(false)
	ui.settings_overlay.hide()
	ui.refresh_bindings()
	show_menu(settings_return_state)

func show_menu(next_state: String) -> void:
	if next_state == "paused" and state == "playing": play_sound("pause")
	if next_state == "title" and is_instance_valid(audio): audio.stop_world()
	ui.large_map.hide()
	state = next_state
	world.process_mode = Node.PROCESS_MODE_DISABLED
	ui.show_menu(next_state)

func primary_action() -> void:
	play_sound("ui_confirm")
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
	play_sound("ui_confirm")
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
