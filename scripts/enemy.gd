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

func _ready() -> void:
	faction = 1
	body_size = T.BOSS_SIZE if kind == "boss" else T.ENEMY_SIZE
	max_hp = T.BOSS_HP if kind == "boss" else T.ENEMY_HP
	hp = max_hp
	facing = -1
	flight_center_y = position.y
	if kind == "laser":
		shot_clock = T.LASER_INTERVAL
	elif kind == "breaker":
		shot_clock = T.BOMB_INTERVAL
	super._ready()

func _physics_process(delta: float) -> void:
	if dead or not is_instance_valid(game.player):
		return
	var on_screen: bool = game.is_on_screen(global_position, 20.0)
	tick_visuals(delta, on_screen)
	if not on_screen:
		was_visible = false
		if action != "idle" or is_instance_valid(laser_beam) or is_instance_valid(bomb): cancel_attack()
		velocity.x = 0
		if kind != "flyer":
			var revision: int = game.terrain.revision if is_instance_valid(game.terrain) else -1
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
	wake_delay = maxf(0.0, wake_delay - delta)
	if wake_delay > 0:
		return
	build_clock -= delta
	if action != "idle":
		action_remaining -= delta
		if action_remaining <= 0:
			_complete_action()
		return
	_choose_attack(delta)

func _move_kind(delta: float) -> void:
	if kind == "flyer":
		_move_flyer(delta)
		return
	velocity.y += T.ENEMY_GRAVITY * delta
	if kind == "walker" and action == "idle" and wake_delay <= 0:
		var direction := -1
		if position.x <= patrol.x:
			set_meta("patrol_direction", 1)
		elif position.x >= patrol.y:
			set_meta("patrol_direction", -1)
		direction = int(get_meta("patrol_direction", direction))
		velocity.x = direction * T.PATROL_SPEED
	else:
		velocity.x = 0
	move_and_slide()
	if kind == "walker" and is_on_wall():
		set_meta("patrol_direction", -int(get_meta("patrol_direction", -1)))

func _move_flyer(delta: float) -> void:
	velocity = Vector2.ZERO
	flight_clock += delta
	var direction := int(get_meta("patrol_direction", -1))
	var next_x := position.x + direction * T.FLYER_SPEED * delta
	# Reflect overshoot, including large physics steps, without ever leaving the lane.
	var width := patrol.y - patrol.x
	if width > 0:
		var phase := fposmod(next_x - patrol.x, width * 2)
		position.x = patrol.x + (phase if phase <= width else width * 2 - phase)
		if next_x < patrol.x or next_x > patrol.y:
			set_meta("patrol_direction", -direction)
	position.y = flight_center_y + sin(flight_clock * TAU / T.FLYER_BOB_PERIOD) * T.FLYER_BOB_AMPLITUDE

func _choose_attack(delta: float) -> void:
	shot_clock -= delta
	switch_clock -= delta
	if (kind == "shifter" or kind == "boss") and switch_clock <= 0:
		next_polarity = 1 - polarity
		_begin("windup_switch", T.SWITCH_WARNING)
	elif gauge >= T.GAUGE_CAPACITY:
		_begin("windup_special", T.SPECIAL_WARNING)
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
	if kind == "laser":
		return T.LASER_INTERVAL
	if kind == "breaker":
		return T.BOMB_INTERVAL
	return T.BOSS_SHOT_INTERVAL if kind == "boss" else T.ENEMY_SHOT_INTERVAL

func _begin(next_action: String, duration: float) -> void:
	action = next_action
	action_remaining = duration

func _complete_action() -> void:
	match action:
		"windup_bomb":
			if is_instance_valid(bomb):
				bomb.fire()
			bomb = null
			shot_clock = T.BOMB_INTERVAL
		"windup_build":
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
			polarity = next_polarity
			switch_clock = T.SWITCH_INTERVAL
			pattern = 1 - pattern
			game.effect(global_position, T.COLORS[polarity], "switch")
		"windup_special":
			game.fire_special(self, take_gauge())
			shot_clock = T.BOMB_INTERVAL if kind == "breaker" else (T.LASER_INTERVAL if kind == "laser" else T.ENEMY_SHOT_INTERVAL)
		"windup_shot":
			var direction: Vector2 = (game.player.global_position - global_position).normalized()
			if kind == "boss" and pattern == 1:
				for angle in [-0.34, -0.17, 0.0, 0.17, 0.34]:
					game.spawn_bullet(self, direction.rotated(angle))
			else:
				game.spawn_bullet(self, direction)
			shot_clock = _shot_interval()
	action = "idle"

func _draw() -> void:
	super._draw()
	if action == "windup_build" and wall_plan.has_area():
		var local := Rect2(to_local(wall_plan.position), wall_plan.size)
		draw_rect(local, Color("dbbd8430"))
		draw_rect(local, Color("dbbd84"), false, 2)
