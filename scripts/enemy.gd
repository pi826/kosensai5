extends "res://scripts/combatant.gd"

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
var loop_level := 0
var ground_actor := true

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
	if kind == "boss": collision_mask &= ~T.PLATFORM_LAYER

func _physics_process(delta: float) -> void:
	if dead or not is_instance_valid(game.player):
		return
	var on_screen: bool = game.is_on_screen(global_position, 20.0)
	# The cached field drawing extends beyond the body. Clear it on exit even
	# though ordinary offscreen actors normally skip redraws.
	if kind == "enhancer" and was_visible and not on_screen: queue_redraw()
	tick_visuals(delta, on_screen and (Engine.get_physics_frames() + get_instance_id()) % T.ENEMY_REDRAW_INTERVAL == 0)
	if not on_screen:
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
	build_clock -= delta * rate
	if action != "idle":
		_tick_action(delta)
		action_remaining -= delta
		if action_remaining <= 0:
			_complete_action()
		return
	_choose_attack(delta, rate)

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
	var nearest := position.clamp(roam.position, roam.end)
	if position.distance_to(nearest) > 0.5:
		velocity = (nearest-position).normalized()*T.BOSS_RETURN_SPEED
		move_and_collide(position.move_toward(nearest, T.BOSS_RETURN_SPEED*delta)-position)
		game.boss_cycle.update_position(self)
		return
	move_clock += delta
	var period: float = T.BOSS_MOVE_PERIOD[boss_role]
	var speed: float = T.BOSS_MOVE_SPEED[boss_role] * (T.BOSS_PACE_MIN + T.BOSS_PACE_VARIATION * sin(move_clock * TAU / period))
	var slope: float = T.BOSS_MOVE_SLOPE[boss_role]
	velocity = Vector2(signf(move_direction.x), signf(move_direction.y) * slope).normalized() * speed
	var target := position + velocity * delta
	if target.x <= roam.position.x or target.x >= roam.end.x: move_direction.x *= -1
	if target.y <= roam.position.y or target.y >= roam.end.y: move_direction.y *= -1
	target = Vector2(clampf(target.x, roam.position.x, roam.end.x), clampf(target.y, roam.position.y, roam.end.y))
	var collision := move_and_collide(target - position)
	if collision:
		move_direction = move_direction.bounce(collision.get_normal())
		if absf(collision.get_normal().x) > 0.5: move_direction.y *= -1
	game.boss_cycle.update_position(self)

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
