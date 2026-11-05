extends "res://scripts/combatant.gd"
const G := preload("res://scripts/stage_generator.gd")
const WANDER_STEPS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN,
	Vector2i(-1,-1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(1,1)]
const WANDER_WARM_CELLS_PER_FRAME := 16

var patrol := Vector2.ZERO
var shot_clock := 0.7
var switch_clock := T.SWITCH_INTERVAL
var wake_delay := T.ENEMY_WAKE_DELAY
var was_visible := false
var pattern := 0
var boss_id := -1
var spawn_id := ""
var flight_center_y := 0.0
var flight_clock := 0.0
var laser_beam: Node2D
var bomb: Node2D
var build_clock := T.BUILD_INTERVAL
var wall_plan := Rect2()
var resting_revision := -1
var resting_position := Vector2.INF
var support_seen := -1
var boss_role := "guardian"
var boss_type := ""
var signature_clock := T.BOSS_SIGNATURE_DELAY
var signature_index := 0
var spin_angle := 0.0
var spin_direction := 1
var spin_shot_clock := 0.0
var rage_spin_angle := 0.0
var rage_spin_clock := 0.0
var rage_started := false
var charge_target := Vector2.ZERO
var summon_count := 0
var summon_wave := 0
var summons_to_restore := 0
var summon_restoring := false
var arena := Rect2()
var roam := Rect2()
var move_clock := 0.0
var move_direction := Vector2(-1, -0.35)
var wander_target := Vector2.INF
var retarget_clock := 0.0
var wander_retargets := 0
var wander_rng := RandomNumberGenerator.new()
var wander_rng_ready := false
var wander_seed_role := ""
var wander_route: Array[Vector2] = []
var wander_route_target := Vector2.INF
var wander_route_shift := -1
var wander_body_cache := PackedByteArray()
var wander_body_cache_area_size := Vector2.INF
var wander_body_cache_body_size := Vector2.ZERO
var wander_body_cache_role := ""
var wander_body_cache_columns := 0
var wander_body_cache_rows := 0
var wander_body_cache_revision := -1
var wander_neighbor_columns := 0
var wander_neighbor_rows := 0
var wander_neighbor_indices := PackedInt32Array()
var wander_neighbor_side_a := PackedInt32Array()
var wander_neighbor_side_b := PackedInt32Array()
var wander_step_costs := PackedFloat64Array()
var wander_route_columns := 0
var wander_route_rows := 0
var wander_cell_area_size := Vector2.INF
var wander_cell_columns := 0
var wander_cell_rows := 0
var wander_cell_points := PackedVector2Array()
var wander_sight_grid := PackedByteArray()
var wander_sight_generations := PackedInt32Array()
var wander_sight_generation := 1
var wander_sight_player := Vector2.INF
var wander_sight_area_size := Vector2.INF
var wander_sight_revision := -1
var wander_sight_query_count := 0
var wander_route_profile := {}
var wander_profile_route := false
var wander_warm_index := -1
var wander_closed := PackedByteArray()
var wander_came_from := PackedInt32Array()
var wander_costs := PackedFloat64Array()
var wander_heuristics := PackedFloat64Array()
var wander_open_heap
var wander_body_shape := RectangleShape2D.new()
var wander_body_query := PhysicsShapeQueryParameters2D.new()
var wander_line_query := PhysicsRayQueryParameters2D.create(Vector2.ZERO, Vector2.ZERO, 1 | T.PLATFORM_LAYER)
var loop_level := 0
var ground_actor := true

class WanderOpen:
	var nodes: Array[int] = []
	var positions := PackedInt32Array()
	var scores := PackedFloat64Array()
	var orders := PackedInt32Array()
	var node_count := 0
	var next_order := 0

	func _init(cell_count: int) -> void:
		nodes.resize(cell_count)
		nodes.fill(-1)
		positions.resize(cell_count)
		positions.fill(-1)
		scores.resize(cell_count)
		scores.fill(INF)
		orders.resize(cell_count)
		orders.fill(-1)

	func reset() -> void:
		positions.fill(-1)
		scores.fill(INF)
		orders.fill(-1)
		node_count = 0
		next_order = 0

	func is_empty() -> bool:
		return node_count == 0

	func has_node(node: int) -> bool:
		return positions[node] >= 0

	func upsert(node: int, score: float) -> void:
		var position := positions[node]
		if position < 0:
			scores[node] = score
			orders[node] = next_order
			next_order += 1
			position = node_count
			node_count += 1
			nodes[position] = node
			while position > 0:
				var parent := (position-1) >> 1
				var parent_node: int = nodes[parent]
				if score > scores[parent_node] or (score == scores[parent_node] and orders[node] > orders[parent_node]): break
				nodes[position] = parent_node
				positions[parent_node] = position
				position = parent
			nodes[position] = node
			positions[node] = position
		else:
			var previous: float = scores[node]
			scores[node] = score
			if score < previous:
				while position > 0:
					var parent := (position-1) >> 1
					var parent_node: int = nodes[parent]
					if score > scores[parent_node] or (score == scores[parent_node] and orders[node] > orders[parent_node]): break
					nodes[position] = parent_node
					positions[parent_node] = position
					position = parent
				nodes[position] = node
				positions[node] = position
			else:
				while true:
					var left := position*2+1
					if left >= node_count: break
					var right := left+1
					var best := left
					if right < node_count and (scores[nodes[right]] < scores[nodes[left]] or (scores[nodes[right]] == scores[nodes[left]] and orders[nodes[right]] < orders[nodes[left]])): best = right
					var best_node: int = nodes[best]
					if score < scores[best_node] or (score == scores[best_node] and orders[node] < orders[best_node]): break
					nodes[position] = best_node
					positions[best_node] = position
					position = best
				nodes[position] = node
				positions[node] = position

	func pop() -> int:
		var result: int = nodes[0]
		positions[result] = -1
		node_count -= 1
		var last: int = nodes[node_count]
		if node_count == 0:
			return result
		var position := 0
		while true:
			var left := position*2+1
			if left >= node_count: break
			var right := left+1
			var best := left
			if right < node_count and (scores[nodes[right]] < scores[nodes[left]] or (scores[nodes[right]] == scores[nodes[left]] and orders[nodes[right]] < orders[nodes[left]])): best = right
			var best_node: int = nodes[best]
			if scores[last] < scores[best_node] or (scores[last] == scores[best_node] and orders[last] < orders[best_node]): break
			nodes[position] = best_node
			positions[best_node] = position
			position = best
		nodes[position] = last
		positions[last] = position
		return result
func apply_loop(level: int) -> void:
	if kind == "boss" or game.is_tutorial(): return
	var base: int = T.ENHANCER_HP if kind == "enhancer" else T.ENEMY_HP
	var next_hp: int = base * (1 + T.LOOP_HP_RATIO_PER_CLEAR * level)
	hp += next_hp - max_hp
	max_hp = next_hp
	loop_level = level
	queue_redraw()

func outgoing_damage(base: int) -> int:
	return roundi(base * (1.0 + T.LOOP_DAMAGE_PER_CLEAR * loop_level)) if kind != "boss" else base

func movement_ratio() -> float:
	return 1.0 + T.LOOP_SPEED_PER_CLEAR * loop_level if kind != "boss" else 1.0

func field_active() -> bool:
	return kind == "enhancer" and not dead and not is_queued_for_deletion() and game.is_on_screen(global_position, 20.0)

func _player_in_arena() -> bool:
	return kind == "boss" and arena.has_area() and is_instance_valid(game.player) and not game.player.dead and arena.has_point(game.player.global_position)

func enhanced() -> bool:
	if kind == "boss" or kind == "enhancer" or game.is_tutorial(): return false
	for source in get_tree().get_nodes_in_group("enhancers"):
		if global_position.distance_squared_to(source.global_position) <= T.ENHANCER_RADIUS * T.ENHANCER_RADIUS and source.get_parent() == game.world and source.field_active(): return true
	return false

func hit_damage(amount: int) -> int:
	return maxi(1, ceili(amount * T.ENHANCER_DAMAGE_RATIO)) if enhanced() else amount

func attack_rate() -> float:
	var rate: float = 1.0 + T.LOOP_ATTACK_PER_CLEAR * loop_level if kind != "boss" else 1.0
	return rate / T.ENHANCER_INTERVAL_RATIO if enhanced() else rate

func _hp_changed(_previous_hp: int) -> void:
	if kind == "boss" and game.boss_cycle.records.has(boss_id): game.boss_cycle.records[boss_id].hp = hp

func _ready() -> void:
	faction = 1
	body_size = T.BOSS_SIZE if kind == "boss" else T.ENEMY_SIZE
	max_hp = T.BOSS_HP if kind == "boss" else (T.ENHANCER_HP if kind == "enhancer" else T.ENEMY_HP)
	if kind == "boss":
		game.boss_cycle.live_actors[boss_id] = weakref(self)
		body_size = preload("res://scripts/boss_cycle.gd").size_for(boss_role)
		max_hp = preload("res://scripts/boss_cycle.gd").hp_for(boss_role)
	hp = max_hp
	if kind == "enhancer": add_to_group("enhancers")
	if kind == "boss": add_to_group("bosses")
	ground_actor = kind not in ["flyer", "enhancer"]
	apply_loop(game.enemy_loop_level())
	facing = -1
	flight_center_y = position.y
	if kind == "laser":
		shot_clock = T.LASER_INTERVAL
	elif kind == "breaker":
		shot_clock = T.BOMB_INTERVAL
	super._ready()
	if kind == "boss":
		collision_mask &= ~T.PLATFORM_LAYER
		if arena.has_area():
			var area := wander_area()
			if area.has_area():
				_prepare_wander_geometry(area, ceili(area.size.x/48.0)+1, ceili(area.size.y/48.0)+1)
				call_deferred("_warm_wander_route")

func _physics_process(delta: float) -> void:
	if dead or not is_instance_valid(game.player):
		return
	var on_screen: bool = game.is_on_screen(global_position, 20.0)
	var engaged := on_screen or _player_in_arena()
	if kind == "boss" and not engaged:
		_service_wander_sight_warm()
	# The cached field drawing extends beyond the body. Clear it on exit even
	# though ordinary offscreen actors normally skip redraws.
	if kind == "enhancer" and was_visible and not on_screen: queue_redraw()
	tick_visuals(delta, on_screen and (Engine.get_physics_frames() + get_instance_id()) % T.ENEMY_REDRAW_INTERVAL == 0)
	if not engaged:
		was_visible = false
		if action != "idle" or is_instance_valid(laser_beam) or is_instance_valid(bomb): cancel_attack()
		velocity.x = 0
		if ground_actor and not (kind == "boss" and roam.has_area()):
			var revision: int = resting_revision
			if is_instance_valid(game.terrain):
				var serial: int = game.terrain.support_serial
				if serial != support_seen:
					revision = game.terrain.support_revision_at(position)
					support_seen = serial
			else:
				revision = -1
			# A resting body only needs another physics query after terrain changes
			# or external movement. Unsupported enemies still fall off screen.
			if not is_on_floor() or revision != resting_revision or position != resting_position:
				velocity.y += T.ENEMY_GRAVITY * delta
				move_and_slide()
				resting_position = position
				resting_revision = revision
		return
	if not was_visible:
		wake_delay = T.ENEMY_WAKE_DELAY
		was_visible = true
	facing = 1 if game.player.position.x > position.x else -1
	_move_kind(delta)
	if kind == "enhancer": return
	wake_delay = maxf(0.0, wake_delay - delta)
	if wake_delay > 0:
		return
	if _rage_spin_active():
		_tick_rage_spin(delta)
	var rate := attack_rate()
	if on_screen: build_clock -= delta * rate
	if action != "idle":
		_tick_action(delta)
		action_remaining -= delta
		if action_remaining <= 0:
			_complete_action()
		return
	if on_screen: _choose_attack(delta, rate)

func _move_kind(delta: float) -> void:
	if kind == "boss" and roam.has_area():
		if action in ["windup_charge", "charging", "charge_recover"]:
			velocity = Vector2.ZERO
			return
		_move_boss(delta)
		return
	if kind == "flyer":
		_move_flyer(delta)
		return
	if kind == "enhancer":
		_move_enhancer(delta)
		return
	velocity.y += T.ENEMY_GRAVITY * delta
	if kind == "walker" and action == "idle" and wake_delay <= 0:
		var direction := -1
		if position.x <= patrol.x:
			set_meta("patrol_direction", 1)
		elif position.x >= patrol.y:
			set_meta("patrol_direction", -1)
		direction = int(get_meta("patrol_direction", direction))
		velocity.x = direction * T.PATROL_SPEED * movement_ratio()
	else:
		velocity.x = 0
	move_and_slide()
	if kind == "walker" and is_on_wall():
		set_meta("patrol_direction", -int(get_meta("patrol_direction", -1)))

func _move_boss(delta: float) -> void:
	var area := wander_area()
	if not area.has_area():
		velocity = Vector2.ZERO
		return
	if wander_route_shift != game.origin_shift_count:
		wander_route.clear()
		wander_route_target = Vector2.INF
		wander_route_shift = game.origin_shift_count
	var nearest := _wander_point(position, area)
	if position.distance_to(nearest) > 0.5:
		wander_route.clear()
		wander_route_target = Vector2.INF
		velocity = (nearest-position).normalized()*T.BOSS_RETURN_SPEED
		move_and_collide(position.move_toward(nearest, T.BOSS_RETURN_SPEED*delta)-position)
		game.boss_cycle.update_position(self)
		return
	if wander_seed_role != boss_role:
		wander_target = Vector2.INF
		retarget_clock = 0.0
	move_clock += delta
	retarget_clock -= delta
	var choose_target: bool = wander_target == Vector2.INF or retarget_clock <= 0.0
	if wander_route.is_empty() and wander_target != position and position.distance_to(wander_target) <= 12.0:
		choose_target = true
	if choose_target:
		_choose_wander_target(area)
		wander_route.clear()
		wander_route_target = Vector2.INF
	if wander_route.is_empty():
		wander_route = _wander_route_to(area, wander_target)
		wander_route_target = wander_target
	while not wander_route.is_empty() and position.distance_to(wander_route[0]) <= 12.0:
		wander_route.pop_front()
	if wander_route.is_empty():
		velocity = Vector2.ZERO
		game.boss_cycle.update_position(self)
		return
	var waypoint: Vector2 = wander_route[0]
	var direction := (waypoint-position).normalized()
	var wobble := sin(move_clock*T.BOSS_WANDER_WOBBLE_RATE)*T.BOSS_WANDER_WOBBLE
	var heading := (direction+direction.orthogonal()*wobble).normalized()
	var speed: float = T.BOSS_MOVE_SPEED[boss_role] * T.BOSS_WANDER_SPEED_RATIO
	var remaining := waypoint-position
	var step := heading*minf(speed*delta, remaining.length())
	if step.length_squared() >= remaining.length_squared(): step = remaining
	var next := _wander_point(position+step, area)
	if _wander_body_clear(position) and not _wander_body_clear(next) and absf(wobble) > 0.001:
		heading = direction
		step = heading*minf(speed*delta, remaining.length())
		next = _wander_point(position+step, area)
		step = next-position
	step = next-position
	velocity = step/maxf(delta, 0.00001)
	var collision := move_and_collide(step)
	if collision:
		wander_target = Vector2.INF
		retarget_clock = 0.0
		wander_route.clear()
		wander_route_target = Vector2.INF
		velocity = Vector2.ZERO
	game.boss_cycle.update_position(self)

func wander_area() -> Rect2:
	if not arena.has_area(): return Rect2()
	var zone: Rect2 = G.arena_zone(arena, 0)
	var inset := body_size/2 + Vector2.ONE*T.BOSS_CLEARANCE
	var size := zone.size-inset*2
	if size.x <= 0.0 or size.y <= 0.0: return Rect2()
	return Rect2(zone.position+inset, size)

func _wander_point(point: Vector2, area: Rect2) -> Vector2:
	return point.clamp(area.position, area.end-Vector2(0.01, 0.01))

func _prepare_wander_geometry(area: Rect2, columns: int, rows: int) -> void:
	_wander_prepare_cells(area, columns, rows)
	_wander_neighbor_grid(columns, rows)
	_wander_prepare_route_storage(columns, rows)
	_wander_body_grid(area, columns, rows)

func _choose_wander_target(area: Rect2) -> void:
	if not wander_rng_ready or wander_seed_role != boss_role:
		wander_rng.seed = hash([game.current_seed, boss_id, boss_role])
		wander_rng_ready = true
		wander_seed_role = boss_role
	var best := area.position
	var best_score := -INF
	var hold_position: bool = _wander_body_clear(position) and _wander_line_clear(position)
	var side: float = -1.0 if int(wander_retargets/T.BOSS_WANDER_SIDE_PICKS) % 2 == 0 else 1.0
	var half_start: float = area.position.x if side < 0.0 else area.get_center().x
	var half_end: float = area.get_center().x if side < 0.0 else area.end.x
	for candidate_index in range(T.BOSS_WANDER_CANDIDATES):
		var candidate: Vector2
		if candidate_index == 0 and hold_position and position.x >= half_start and position.x <= half_end:
			# Keeping a clear firing position competes with the random points.
			candidate = position
		else:
			# Hold one side long enough to cross the shelf band before retargeting.
			# The random points are still stratified across the full wander height.
			var slot: int = maxi(candidate_index, 1)
			var band_start: float = lerpf(half_start,half_end,float(slot-1)/float(T.BOSS_WANDER_CANDIDATES-1))
			var band_end: float = lerpf(half_start,half_end,float(slot)/float(T.BOSS_WANDER_CANDIDATES-1))
			candidate = Vector2(wander_rng.randf_range(band_start, minf(band_end, area.end.x)-0.01), wander_rng.randf_range(area.position.y, area.end.y-0.01))
		var score := 0.0
		if _wander_line_clear(candidate): score += 3.0
		if _wander_body_clear(candidate): score += 2.0
		if position.distance_squared_to(candidate) >= 240.0*240.0: score += 1.0
		score += wander_rng.randf()
		if score > best_score:
			best_score = score
			best = candidate
	wander_target = best
	retarget_clock = wander_rng.randf_range(T.BOSS_WANDER_RETARGET_MIN, T.BOSS_WANDER_RETARGET_MAX)
	wander_retargets += 1

func _wander_line_clear(candidate: Vector2) -> bool:
	wander_line_query.from = candidate
	wander_line_query.to = game.player.global_position
	return get_world_2d().direct_space_state.intersect_ray(wander_line_query).is_empty()

func _wander_sight_clear_at(index: int, local_player: Vector2, origin: Vector2, space: PhysicsDirectSpaceState2D) -> bool:
	var cached := 0
	if wander_sight_generations[index] == wander_sight_generation:
		cached = wander_sight_grid[index]
	if cached != 0:
		return cached == 2
	if wander_profile_route:
		wander_sight_query_count += 1
	wander_line_query.from = origin+wander_cell_points[index]
	wander_line_query.to = origin+local_player
	var clear := space.intersect_ray(wander_line_query).is_empty()
	cached = 2 if clear else 1
	wander_sight_generations[index] = wander_sight_generation
	wander_sight_grid[index] = cached
	return clear

func _wander_body_clear(candidate: Vector2) -> bool:
	wander_body_shape.size = body_size
	wander_body_query.shape = wander_body_shape
	wander_body_query.transform = Transform2D(0.0, candidate)
	wander_body_query.collision_mask = T.PLATFORM_LAYER
	wander_body_query.collide_with_areas = false
	return get_world_2d().direct_space_state.intersect_shape(wander_body_query, 1).is_empty()

func _wander_body_grid(area: Rect2, columns: int, rows: int) -> PackedByteArray:
	var terrain_revision: int = game.terrain.revision if is_instance_valid(game.terrain) else -1
	if wander_body_cache_area_size == area.size and wander_body_cache_body_size == body_size and wander_body_cache_role == boss_role and wander_body_cache_columns == columns and wander_body_cache_rows == rows and wander_body_cache_revision == terrain_revision:
		return wander_body_cache
	var shelves: Array[Rect2] = []
	if is_instance_valid(game) and game.stream != null:
		var sector = get_meta("sector") if has_meta("sector") else null
		var data: Dictionary = game.stream.loaded.get(sector, {})
		var arena_bounds: Rect2 = arena if arena.has_area() else area
		for solid: Rect2 in data.get("solids", []):
			if not solid.intersects(arena_bounds): continue
			if solid.size.y <= 20:
				shelves.append(Rect2(solid.position-area.position, solid.size))
	var grid := PackedByteArray()
	grid.resize(columns*rows)
	grid.fill(1)
	for shelf: Rect2 in shelves:
		var reach := Rect2(shelf.position-body_size/2-Vector2.ONE, shelf.size+body_size+Vector2.ONE*2)
		var first_x := maxi(0, floori(reach.position.x/48.0))
		var last_x := mini(columns-1, ceili(reach.end.x/48.0))
		var first_y := maxi(0, floori(reach.position.y/48.0))
		var last_y := mini(rows-1, ceili(reach.end.y/48.0))
		for y in range(first_y, last_y+1):
			var point_y := float(y)*48.0
			if y == rows-1: point_y = area.size.y-0.01
			for x in range(first_x, last_x+1):
				var point_x := float(x)*48.0
				if x == columns-1: point_x = area.size.x-0.01
				var body := Rect2(Vector2(point_x,point_y)-body_size/2, body_size).grow(-0.001)
				if shelf.intersects(body): grid[y*columns+x] = 0
	wander_body_cache = grid
	wander_body_cache_area_size = area.size
	wander_body_cache_body_size = body_size
	wander_body_cache_role = boss_role
	wander_body_cache_columns = columns
	wander_body_cache_rows = rows
	wander_body_cache_revision = terrain_revision
	return wander_body_cache

func _wander_neighbor_grid(columns: int, rows: int) -> void:
	if wander_neighbor_columns == columns and wander_neighbor_rows == rows: return
	var cell_count := columns*rows
	wander_neighbor_indices.resize(cell_count*8)
	wander_neighbor_side_a.resize(cell_count*8)
	wander_neighbor_side_b.resize(cell_count*8)
	wander_step_costs.resize(cell_count*8)
	for y in range(rows):
		for x in range(columns):
			var index := y*columns+x
			for direction in range(8):
				var offset: Vector2i = WANDER_STEPS[direction]
				var slot := index*8+direction
				var neighbor := Vector2i(x,y)+offset
				if neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= columns or neighbor.y >= rows:
					wander_neighbor_indices[slot] = -1
					wander_neighbor_side_a[slot] = -1
					wander_neighbor_side_b[slot] = -1
					continue
				wander_neighbor_indices[slot] = neighbor.y*columns+neighbor.x
				wander_neighbor_side_a[slot] = index+offset.x if offset.x != 0 and offset.y != 0 else -1
				wander_neighbor_side_b[slot] = index+offset.y*columns if offset.x != 0 and offset.y != 0 else -1
				wander_step_costs[slot] = 1.41421356 if offset.x != 0 and offset.y != 0 else 1.0
	wander_neighbor_columns = columns
	wander_neighbor_rows = rows

func _wander_prepare_cells(area: Rect2, columns: int, rows: int) -> void:
	if wander_cell_area_size == area.size and wander_cell_columns == columns and wander_cell_rows == rows:
		return
	wander_cell_area_size = area.size
	wander_cell_columns = columns
	wander_cell_rows = rows
	wander_cell_points.resize(columns*rows)
	for y in range(rows):
		for x in range(columns):
			wander_cell_points[y*columns+x] = _wander_grid_point(area, 48.0, Vector2i(x,y), columns, rows)-area.position

func _wander_prepare_route_storage(columns: int, rows: int) -> void:
	if wander_route_columns == columns and wander_route_rows == rows:
		return
	var cell_count := columns*rows
	wander_route_columns = columns
	wander_route_rows = rows
	wander_closed.resize(cell_count)
	wander_came_from.resize(cell_count)
	wander_costs.resize(cell_count)
	wander_heuristics.resize(cell_count)
	wander_sight_grid.resize(cell_count)
	wander_sight_grid.fill(0)
	wander_sight_generations.resize(cell_count)
	wander_sight_generations.fill(0)
	wander_sight_generation += 1
	wander_sight_player = Vector2.INF
	wander_sight_area_size = Vector2.INF
	wander_sight_revision = -1
	wander_open_heap = WanderOpen.new(cell_count)

func _warm_wander_route() -> void:
	if kind != "boss" or not is_instance_valid(game) or not is_instance_valid(game.player): return
	var area := wander_area()
	if not area.has_area(): return
	# Exercise both a normal route and the unsafe-goal search before combat.
	_wander_route_to(area, _wander_point(area.end, area))
	_wander_route_to(area, area.get_center())
	# Combat starts at the lower centre; seed sight results for that viewpoint last.
	var entry := Vector2(arena.get_center().x, arena.end.y-game.player.body_size.y/2)
	_warm_wander_sight(area, entry-area.position)

func _warm_wander_sight(area: Rect2, local_player: Vector2) -> void:
	var space := get_world_2d().direct_space_state
	_start_wander_sight_warm(area, local_player)
	for index in range(wander_sight_grid.size()):
		_wander_sight_clear_at(index, local_player, area.position, space)
	wander_warm_index = wander_sight_grid.size()

func _start_wander_sight_warm(area: Rect2, local_player: Vector2) -> void:
	var terrain_revision: int = game.terrain.revision if is_instance_valid(game.terrain) else -1
	wander_sight_generation += 1
	wander_sight_player = local_player
	wander_sight_area_size = area.size
	wander_sight_revision = terrain_revision
	wander_warm_index = 0

func _service_wander_sight_warm() -> void:
	# Spread the entry sight cache over frames while the boss is unengaged.
	if not arena.has_area() or not is_instance_valid(game.player): return
	var area := wander_area()
	if not area.has_area(): return
	var terrain_revision: int = game.terrain.revision if is_instance_valid(game.terrain) else -1
	var entry := Vector2(arena.get_center().x, arena.end.y-game.player.body_size.y/2)-area.position
	if wander_warm_index >= 0 and wander_warm_index >= wander_sight_grid.size() \
			and wander_sight_area_size == area.size and wander_sight_player == entry \
			and wander_sight_revision == terrain_revision:
		return
	if wander_warm_index < 0 or wander_sight_area_size != area.size \
			or wander_sight_player != entry or wander_sight_revision != terrain_revision:
		var columns := maxi(1, ceili(area.size.x/48.0)+1)
		var rows := maxi(1, ceili(area.size.y/48.0)+1)
		_prepare_wander_geometry(area, columns, rows)
		_start_wander_sight_warm(area, entry)
	var space := get_world_2d().direct_space_state
	var budget := WANDER_WARM_CELLS_PER_FRAME
	while wander_warm_index < wander_sight_grid.size() and budget > 0:
		_wander_sight_clear_at(wander_warm_index, entry, area.position, space)
		wander_warm_index += 1
		budget -= 1

func _wander_route_to(area: Rect2, target: Vector2) -> Array[Vector2]:
	var profile := wander_profile_route
	var profile_start := Time.get_ticks_usec()
	var profile_total_start := profile_start
	if profile:
		wander_route_profile = {}
		wander_sight_query_count = 0
	var grid := 48.0
	var columns := maxi(1, ceili(area.size.x/grid)+1)
	var rows := maxi(1, ceili(area.size.y/grid)+1)
	_prepare_wander_geometry(area, columns, rows)
	if profile:
		wander_route_profile["geometry_ms"] = float(Time.get_ticks_usec()-profile_start)/1000.0
		profile_start = Time.get_ticks_usec()
	var body_grid := wander_body_cache
	var cell_count := columns*rows
	wander_came_from.fill(-1)
	wander_closed.fill(0)
	wander_costs.fill(INF)
	if profile:
		wander_route_profile["reset_ms"] = float(Time.get_ticks_usec()-profile_start)/1000.0
		profile_start = Time.get_ticks_usec()
	var local_player: Vector2 = game.player.global_position-area.position
	var terrain_revision: int = game.terrain.revision if is_instance_valid(game.terrain) else -1
	var sight_cached: bool = local_player == wander_sight_player and area.size == wander_sight_area_size and terrain_revision == wander_sight_revision
	if local_player != wander_sight_player or area.size != wander_sight_area_size or terrain_revision != wander_sight_revision:
		wander_sight_generation += 1
		wander_sight_player = local_player
		wander_sight_area_size = area.size
		wander_sight_revision = terrain_revision
	var space := get_world_2d().direct_space_state
	var start := Vector2i(clampi(roundi((position.x-area.position.x)/grid), 0, columns-1),
		clampi(roundi((position.y-area.position.y)/grid), 0, rows-1))
	var goal := Vector2i(clampi(roundi((target.x-area.position.x)/grid), 0, columns-1),
		clampi(roundi((target.y-area.position.y)/grid), 0, rows-1))
	var requested_goal := goal
	var goal_index := goal.y*columns+goal.x
	var goal_corrected := false
	if not (body_grid[goal_index] and _wander_sight_clear_at(goal_index, local_player, area.position, space)):
		goal_corrected = true
		var best_goal_index := goal_index
		var best_distance := INF
		var target_local := target-area.position
		var position_local := position-area.position
		var require_away := position.distance_squared_to(target) > grid*grid
		# Search the whole arena when the requested goal is unsafe. Restricting
		# this search changed the chosen goal enough to hide the player too often.
		for index in range(cell_count):
			if not body_grid[index]: continue
			var point := wander_cell_points[index]
			if require_away and point.distance_squared_to(position_local) < grid*grid: continue
			var distance := point.distance_to(target_local)+point.distance_to(position_local)*0.15
			if distance >= best_distance: continue
			if not _wander_sight_clear_at(index, local_player, area.position, space): continue
			best_distance = distance
			best_goal_index = index
		goal = Vector2i(best_goal_index%columns, floori(float(best_goal_index)/float(columns)))
	if profile:
		wander_route_profile["goal_ms"] = float(Time.get_ticks_usec()-profile_start)/1000.0
		wander_route_profile["goal_corrected"] = goal_corrected
		profile_start = Time.get_ticks_usec()
	var start_index := start.y*columns+start.x
	goal_index = goal.y*columns+goal.x
	for y in range(rows):
		var dy := float(y-goal.y)
		for x in range(columns):
			var dx := float(x-goal.x)
			wander_heuristics[y*columns+x] = sqrt(dx*dx+dy*dy)
	if profile:
		wander_route_profile["heuristics_ms"] = float(Time.get_ticks_usec()-profile_start)/1000.0
		profile_start = Time.get_ticks_usec()
	var found := false
	var closed := wander_closed
	var came_from := wander_came_from
	var costs := wander_costs
	var heuristics := wander_heuristics
	var neighbor_indices := wander_neighbor_indices
	var neighbor_side_a := wander_neighbor_side_a
	var neighbor_side_b := wander_neighbor_side_b
	var step_costs := wander_step_costs
	var open: WanderOpen = wander_open_heap
	open.reset()
	costs[start_index] = 0.0
	open.upsert(start_index,heuristics[start_index])
	while not open.is_empty():
		var current_index := open.pop()
		if current_index == goal_index:
			found = true
			break
		closed[current_index] = 1
		var current_cost: float = costs[current_index]
		var slot := current_index*8
		for direction in range(8):
			var neighbor_index: int = neighbor_indices[slot+direction]
			if neighbor_index < 0: continue
			if closed[neighbor_index]: continue
			var side_a: int = neighbor_side_a[slot+direction]
			if side_a >= 0 and (not body_grid[side_a] or not body_grid[neighbor_side_b[slot+direction]]): continue
			var body_clear: bool = body_grid[neighbor_index] != 0
			var line_clear := _wander_sight_clear_at(neighbor_index, local_player, area.position, space)
			var step_cost: float = step_costs[slot+direction]
			step_cost += 0.0 if body_clear else 80.0
			step_cost += 0.0 if line_clear else 60.0
			var next_cost: float = current_cost+step_cost
			if next_cost >= costs[neighbor_index]: continue
			costs[neighbor_index] = next_cost
			came_from[neighbor_index] = current_index
			open.upsert(neighbor_index,next_cost+heuristics[neighbor_index])
	if not found:
		if profile:
			wander_route_profile["astar_ms"] = float(Time.get_ticks_usec()-profile_start)/1000.0
			wander_route_profile["build_ms"] = 0.0
			wander_route_profile["total_ms"] = float(Time.get_ticks_usec()-profile_total_start)/1000.0
			wander_route_profile["sight_queries"] = wander_sight_query_count
			wander_route_profile["sight_cached"] = sight_cached
			wander_route_profile["terrain_revision"] = terrain_revision
		return [target]
	if profile:
		wander_route_profile["astar_ms"] = float(Time.get_ticks_usec()-profile_start)/1000.0
		profile_start = Time.get_ticks_usec()
	var route: Array[Vector2] = []
	var node_index := goal_index
	while node_index != start_index:
		route.append(wander_cell_points[node_index]+area.position)
		node_index = came_from[node_index]
	route.reverse()
	if goal == requested_goal: route.append(target)
	elif route.is_empty(): route.append(wander_cell_points[goal_index]+area.position)
	if profile:
		wander_route_profile["build_ms"] = float(Time.get_ticks_usec()-profile_start)/1000.0
		wander_route_profile["total_ms"] = float(Time.get_ticks_usec()-profile_total_start)/1000.0
		wander_route_profile["sight_queries"] = wander_sight_query_count
		wander_route_profile["sight_cached"] = sight_cached
		wander_route_profile["terrain_revision"] = terrain_revision
	return route

func _wander_grid_point(area: Rect2, grid: float, cell: Vector2i, columns: int, rows: int) -> Vector2:
	var point := area.position+Vector2(cell)*grid
	if cell.x == columns-1: point.x = area.end.x-0.01
	if cell.y == rows-1: point.y = area.end.y-0.01
	return point

func _move_flyer(delta: float) -> void:
	velocity = Vector2.ZERO
	flight_clock += delta * movement_ratio()
	var direction := int(get_meta("patrol_direction", -1))
	var next_x := position.x + direction * T.FLYER_SPEED * movement_ratio() * delta
	# Reflect overshoot, including large physics steps, without ever leaving the lane.
	var width := patrol.y - patrol.x
	if width > 0:
		var phase := fposmod(next_x - patrol.x, width * 2)
		position.x = patrol.x + (phase if phase <= width else width * 2 - phase)
		if next_x < patrol.x or next_x > patrol.y:
			set_meta("patrol_direction", -direction)
	position.y = flight_center_y + sin(flight_clock * TAU / T.FLYER_BOB_PERIOD) * T.FLYER_BOB_AMPLITUDE

func _move_enhancer(delta: float) -> void:
	flight_clock += delta * movement_ratio()
	var center := (patrol.x + patrol.y) / 2
	var target := Vector2(center + sin(flight_clock * T.ENHANCER_SPEED / T.ENHANCER_DRIFT) * T.ENHANCER_DRIFT,
		flight_center_y + sin(flight_clock * TAU / T.ENHANCER_BOB_PERIOD) * T.ENHANCER_BOB_AMPLITUDE)
	velocity = (target - position) / maxf(delta, 0.00001)
	move_and_collide(target - position)

func _choose_attack(delta: float, rate: float = -1.0) -> void:
	if rate < 0.0: rate = attack_rate()
	shot_clock -= delta * rate
	if kind == "boss": signature_clock -= delta * rate
	switch_clock -= delta * rate
	if kind == "boss" and boss_role == "guardian" and boss_type == "summoner":
		# Urgent summons wait for idle/visibility/waking in _physics_process.
		# Keep unfinished warnings pending across cancellation and sector unload.
		var half_hp := hp <= max_hp * T.BOSS_SUMMON_SECOND_WAVE_RATIO
		if summons_to_restore > 0:
			summon_count = summons_to_restore
			summon_restoring = true
			_begin("windup_summon", T.BOSS_SUMMON_WARNING)
			return
		if half_hp and (summon_wave == 1 or (summon_wave == 0 and signature_clock <= 0)):
			_begin_signature()
			return
	if (kind == "shifter" or kind == "boss") and switch_clock <= 0:
		next_polarity = 1 - polarity
		_begin("windup_switch", T.SWITCH_WARNING)
	elif gauge >= T.GAUGE_CAPACITY:
		_begin("windup_special", T.SPECIAL_WARNING)
	elif kind == "boss" and signature_clock <= 0 and _begin_signature():
		pass
	elif kind == "builder" and build_clock <= 0 and _choose_build():
		_begin("windup_build", T.BUILD_WARNING)
	elif shot_clock <= 0:
		if kind == "laser":
			laser_beam = game.spawn_laser(self)
			_begin("windup_laser", T.LASER_WARNING)
		elif kind == "breaker":
			bomb = game.spawn_bomb_warning(self)
			_begin("windup_bomb", T.BOMB_WARNING)
		else:
			_begin("windup_shot", T.SHOT_WARNING)

func signature_pattern() -> String:
	return boss_type if boss_role == "guardian" else T.BOSS_SIGNATURE_ORDER[signature_index % 3]

func _begin_signature() -> bool:
	var selected := signature_pattern()
	if boss_role != "guardian": signature_index += 1
	if selected == "spinner" and _rage_spin_active(): return false
	match selected:
		"spinner":
			spin_angle = (game.player.position-position).angle()
			spin_direction *= -1
			_begin("windup_spin", T.BOSS_SPIN_WARNING)
		"summoner":
			if boss_role == "guardian" and (summon_wave >= 2 or (summon_wave == 1 and hp > max_hp * T.BOSS_SUMMON_SECOND_WAVE_RATIO)): return false
			summon_count = mini(T.BOSS_SUMMON_COUNT[boss_role], T.BOSS_SUMMON_MAX_ALIVE[boss_role]-game.alive_summons(self))
			if summon_count <= 0: return false
			summon_restoring = false
			_begin("windup_summon", T.BOSS_SUMMON_WARNING)
		"charger":
			var clearance := Vector2.ONE*T.BOSS_CLEARANCE
			var bounds := Rect2(arena.position+body_size/2+clearance, arena.size-body_size-clearance*2)
			charge_target = game.player.position.clamp(bounds.position, bounds.end)
			velocity = Vector2.ZERO
			_begin("windup_charge", T.BOSS_CHARGE_WARNING[boss_role])
		_: return false
	signature_clock = T.BOSS_SIGNATURE_INTERVAL[boss_role]
	return true

func _tick_action(delta: float) -> void:
	if action == "spinning":
		spin_angle += spin_direction*T.BOSS_SPIN_SPEED[boss_role]*delta
		spin_shot_clock -= delta
		if spin_shot_clock <= 0:
			spin_shot_clock += T.BOSS_SPIN_SHOT_INTERVAL[boss_role]
			var arms: int = T.BOSS_SPIN_ARMS[boss_role]
			for k in range(arms):
				var direction := Vector2.from_angle(spin_angle+k*TAU/arms)
				game.spawn_bullet(self, direction, false, null, polarity if k%2 == 0 else 1-polarity, position+muzzle_offset(direction))
			game.play_sound("boss_shot", position, -6.0)
	elif action == "charging":
		var distance := position.distance_to(charge_target)
		var travel: float = T.BOSS_CHARGE_SPEED[boss_role]*delta
		velocity = (charge_target-position).normalized()*T.BOSS_CHARGE_SPEED[boss_role]
		var collision := move_and_collide(position.move_toward(charge_target, travel)-position)
		game.boss_cycle.update_position(self)
		if collision or distance <= travel:
			velocity = Vector2.ZERO
			_begin("charge_recover", T.BOSS_CHARGE_RECOVER)

func _rage_spin_active() -> bool:
	return kind == "boss" and boss_role == "final" and hp < max_hp * T.FINAL_BOSS_RAGE_RATIO

func _tick_rage_spin(delta: float) -> void:
	if not _rage_spin_active(): return
	if not rage_started:
		rage_started = true
		rage_spin_angle = (game.player.global_position-global_position).angle()
		rage_spin_clock = 0.0
		game.effect(global_position, T.COLORS[polarity], "switch")
	if action == "spinning": return
	rage_spin_angle += T.FINAL_BOSS_RAGE_SPIN_SPEED * delta
	rage_spin_clock -= delta
	if rage_spin_clock > 0: return
	rage_spin_clock += T.FINAL_BOSS_RAGE_SPIN_INTERVAL
	var arms: int = T.FINAL_BOSS_RAGE_SPIN_ARMS
	for k in range(arms):
		var direction := Vector2.from_angle(rage_spin_angle+k*TAU/arms)
		game.spawn_bullet(self, direction, false, null, polarity if k%2 == 0 else 1-polarity, position+muzzle_offset(direction))
	game.play_sound("boss_shot", position, -10.0)

func cancel_attack() -> void:
	action = "idle"
	if is_instance_valid(laser_beam):
		laser_beam.cancel()
	laser_beam = null
	if is_instance_valid(bomb):
		bomb.cancel()
	bomb = null
	wall_plan = Rect2()
	queue_redraw()

func _choose_build() -> bool:
	if not is_instance_valid(game.terrain):
		return false
	wall_plan = game.terrain.find_wall_plan(self, game.player)
	return wall_plan.has_area()

func _shot_interval() -> float:
	return _base_shot_interval() / attack_rate()

func _base_shot_interval() -> float:
	if kind == "boss" and boss_role == "final": return T.FINAL_BOSS_SHOT_INTERVAL
	if kind == "boss" and boss_role == "secret": return T.SECRET_BOSS_SHOT_INTERVAL
	if kind == "laser":
		return T.LASER_INTERVAL
	if kind == "breaker":
		return T.BOMB_INTERVAL
	return T.BOSS_SHOT_INTERVAL if kind == "boss" else T.ENEMY_SHOT_INTERVAL

func _begin(next_action: String, duration: float) -> void:
	if next_action.begins_with("windup") and next_action not in ["windup_laser", "windup_bomb"]:
		game.play_sound("enemy_warn_special" if next_action == "windup_special" else "enemy_warn", position)
	action = next_action
	action_remaining = duration

func _boss_fan_count() -> int:
	return T.SECRET_BOSS_FAN_COUNT if boss_role == "secret" else T.BOSS_FAN_COUNT

func _fire_fan(direction: Vector2, count: int, color: int, offset: float) -> void:
	for i in range(count):
		var angle := (i - (count - 1) / 2.0) * T.BOSS_FAN_ANGLE + offset
		game.spawn_bullet(self, direction.rotated(angle), false, null, color)

func _complete_action() -> void:
	match action:
		"windup_spin":
			spin_shot_clock = 0.0
			_begin("spinning", T.BOSS_SPIN_DURATION[boss_role])
			return
		"windup_summon":
			game.summon_minions(self, summon_count)
			if boss_role == "guardian" and boss_type == "summoner":
				if summon_restoring: summons_to_restore = 0
				else: summon_wave += 1
				summon_restoring = false
		"windup_charge":
			_begin("charging", T.BOSS_CHARGE_MAX_TIME)
			return
		"charging":
			velocity = Vector2.ZERO
			_begin("charge_recover", T.BOSS_CHARGE_RECOVER)
			return
		"windup_bomb":
			art_fire_remaining = 3.0 / 16.0
			if is_instance_valid(bomb):
				bomb.fire()
			bomb = null
			shot_clock = T.BOMB_INTERVAL
		"windup_build":
			art_fire_remaining = 3.0 / 16.0
			if is_instance_valid(game.terrain) and game.terrain.confirm_wall_plan(wall_plan, self, game.player):
				game.terrain.place_wall(wall_plan, get_instance_id())
			wall_plan = Rect2()
			build_clock = T.BUILD_INTERVAL
		"windup_laser":
			if is_instance_valid(laser_beam):
				laser_beam.fire()
				_begin("firing_laser", T.LASER_DURATION)
				return
		"firing_laser":
			shot_clock = T.LASER_INTERVAL
		"windup_switch":
			art_switch_remaining = 4.0 / 12.0
			polarity = next_polarity
			game.play_sound("enemy_switch", position)
			switch_clock = T.SWITCH_INTERVAL
			pattern = 1 - pattern
			game.effect(global_position, T.COLORS[polarity], "switch")
		"windup_special":
			art_special_fire = true
			art_fire_remaining = (4.0 if kind == "boss" else 3.0) / 16.0
			game.fire_special(self, take_gauge())
			shot_clock = T.BOMB_INTERVAL if kind == "breaker" else (T.LASER_INTERVAL if kind == "laser" else T.ENEMY_SHOT_INTERVAL)
		"windup_shot":
			art_special_fire = false
			art_fire_remaining = 3.0 / 16.0
			var direction: Vector2 = (game.player.global_position - global_position).normalized()
			if kind != "boss":
				game.spawn_bullet(self, direction)
				shot_clock = _base_shot_interval()
			else:
				game.play_sound("boss_shot", position)
				if boss_role == "guardian" and pattern == 0:
					_fire_fan(direction, T.BOSS_FAN_COUNT, polarity, 0.0)
					shot_clock = _base_shot_interval()
				else:
					var count := _boss_fan_count()
					var offset := sin(move_clock) * T.BOSS_FAN_ANGLE if boss_role != "guardian" and pattern == 1 else 0.0
					_fire_fan(direction, count, polarity, offset)
					if boss_role != "guardian" and (pattern == 1 or boss_role == "secret"):
						game.spawn_bullet(self, direction, true, game.player)
					_begin("second_volley", T.BOSS_SECOND_VOLLEY_DELAY)
					return
		"second_volley":
			art_special_fire = false
			art_fire_remaining = 3.0 / 16.0
			game.play_sound("boss_shot", position)
			var direction: Vector2 = (game.player.global_position - global_position).normalized()
			_fire_fan(direction, _boss_fan_count(), 1-polarity, T.BOSS_FAN_ANGLE / 2.0)
			shot_clock = _base_shot_interval()
	action = "idle"

func _draw() -> void:
	if field_active():
		draw_circle(Vector2.ZERO, T.ENHANCER_RADIUS, T.ENHANCER_FIELD_COLOR)
		draw_arc(Vector2.ZERO, T.ENHANCER_RADIUS, 0, TAU, 80, Color(T.ENHANCER_RING_COLOR, 0.35), 2, false)
	super._draw()
	if kind == "boss":
		var tint: Color = T.COLORS[polarity]
		var mark := Vector2(0, -body_size.y/2-16)
		if boss_role == "guardian":
			match boss_type:
				"spinner":
					draw_line(mark-Vector2(8,0), mark+Vector2(8,0), tint, 3)
					draw_line(mark-Vector2(0,8), mark+Vector2(0,8), tint, 3)
				"summoner":
					for x in [-10,0,10]: draw_circle(mark+Vector2(x,0), 3, tint)
				"charger":
					draw_polyline(PackedVector2Array([mark+Vector2(-facing*7,-7), mark+Vector2(facing*5,0), mark+Vector2(-facing*7,7)]), tint, 3)
		if action == "windup_spin":
			for k in range(T.BOSS_SPIN_ARMS[boss_role]):
				draw_line(Vector2.ZERO, Vector2.from_angle(spin_angle+k*TAU/T.BOSS_SPIN_ARMS[boss_role])*160, Color(tint,0.35), 2)
		elif action == "windup_summon":
			draw_arc(Vector2.ZERO, body_size.length()/2+12+8*sin(action_remaining*TAU*3), 0, TAU, 48, Color(tint,0.55), 3)
		elif action == "windup_charge":
			draw_line(Vector2.ZERO, charge_target-position, Color(tint,0.5), 3)
	if kind == "enhancer":
		draw_arc(Vector2.ZERO, 29, 0, TAU, 32, T.ENHANCER_RING_COLOR, 3, false)
	if enhanced(): draw_arc(Vector2.ZERO, body_size.length()/2+6, 0, TAU, 40, T.ENHANCER_RING_COLOR, 3, false)
	if action == "windup_build" and wall_plan.has_area():
		var local := Rect2(to_local(wall_plan.position), wall_plan.size)
		draw_rect(local, Color("dbbd8430"))
		draw_rect(local, Color("dbbd84"), false, 2)
