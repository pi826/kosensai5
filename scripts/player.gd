extends "res://scripts/combatant.gd"

var shot_cooldown := 0.0
var coyote := 0.0
var jump_buffer := 0.0
var pending_special := false
var jump_cut_requested := false
var aim_index := 0
var drop_remaining := 0.0
var drop_clear_y := 0.0
var contact_query := PhysicsShapeQueryParameters2D.new()

func _ready() -> void:
	super._ready()
	contact_query.shape = body_shape
	contact_query.collision_mask = 4 # Enemy bodies; the movement mask stays terrain-only.

func aim_name() -> String:
	return T.AIM_NAMES[aim_index]

func heal(amount: int) -> int:
	if dead or amount <= 0:
		return 0
	var before := hp
	hp = mini(max_hp, hp + amount)
	if hp > before:
		_hp_changed(before)
	return hp - before

func _hp_changed(previous_hp: int) -> void:
	if is_instance_valid(game) and is_instance_valid(game.effects):
		game.effects.show_player_health(self, previous_hp, hp)

func _check_enemy_contact() -> void:
	if invulnerability > 0.0:
		return
	contact_query.transform = global_transform
	for hit: Dictionary in get_world_2d().direct_space_state.intersect_shape(contact_query, 64):
		var enemy = hit.collider
		if not enemy is CharacterBody2D or enemy.get_parent() != game.world or enemy.dead or enemy.is_queued_for_deletion():
			continue
		# A color-change warning still uses polarity, never next_polarity.
		if enemy.polarity != polarity:
			receive_hit(enemy.polarity, T.CONTACT_DAMAGE)
			return

func aim_angle() -> float:
	return T.AIM_ANGLES[aim_index]

func shot_direction() -> Vector2:
	var angle := deg_to_rad(aim_angle())
	return Vector2(facing * cos(angle), -sin(angle))

func _unhandled_input(event: InputEvent) -> void:
	if dead or event.is_echo() or game.state != "playing":
		return
	# A short tap can occur entirely between physics ticks. Keep discrete actions.
	if event.is_action_pressed("switch_color"):
		polarity = 1 - polarity
		game.effect(global_position, T.COLORS[polarity], "switch")
	elif event.is_action_pressed("aim_cycle"):
		aim_index = (aim_index + 1) % T.AIM_ANGLES.size()
		queue_redraw()
	elif event.is_action_pressed("jump"):
		jump_buffer = T.JUMP_BUFFER
		jump_cut_requested = false
	elif event.is_action_released("jump"):
		if not Input.is_action_pressed("jump"):
			jump_cut_requested = true
	elif event.is_action_pressed("special"):
		pending_special = true

func _physics_process(delta: float) -> void:
	if dead:
		return
	tick_visuals(delta)
	shot_cooldown = maxf(0.0, shot_cooldown - delta)
	var horizontal := Input.get_axis("move_left", "move_right")
	var dropping := drop_remaining > 0.0
	if dropping:
		drop_remaining = maxf(0.0, drop_remaining - delta)
		if global_position.y - body_size.y / 2 > drop_clear_y or drop_remaining <= 0.0:
			drop_remaining = 0.0
			collision_mask |= T.PLATFORM_LAYER
	elif Input.is_action_pressed("move_down") and is_on_floor():
		dropping = _try_drop_through()
	var grounded := is_on_floor() and not dropping
	var acceleration: float = T.GROUND_ACCELERATION if grounded else T.AIR_ACCELERATION
	if is_zero_approx(horizontal):
		acceleration = T.GROUND_DECELERATION if grounded else T.AIR_DECELERATION
	velocity.x = move_toward(velocity.x, horizontal * T.MOVE_SPEED, acceleration * delta)
	if not is_zero_approx(horizontal):
		facing = 1 if horizontal > 0 else -1
	coyote = 0.0 if dropping else (T.COYOTE_TIME if grounded else maxf(0.0, coyote - delta))
	jump_buffer = maxf(0.0, jump_buffer - delta)
	if jump_buffer > 0 and coyote > 0:
		velocity.y = -T.JUMP_SPEED
		coyote = 0.0
		jump_buffer = 0.0
		visual_scale = Vector2(0.82, 1.16)
		game.effect(global_position + Vector2(0, 22), Color("537083"), "jump")
	if jump_cut_requested:
		if velocity.y < 0:
			velocity.y = maxf(velocity.y, -T.JUMP_CUT_SPEED)
			jump_cut_requested = false
		elif jump_buffer <= 0:
			jump_cut_requested = false
	var gravity: float = T.GRAVITY if velocity.y < 0 else T.FALL_GRAVITY
	velocity.y = minf(velocity.y + gravity * delta, T.MAX_FALL_SPEED)
	var before_slide_y := velocity.y
	move_and_slide()
	_check_enemy_contact()
	if dead:
		return
	if is_on_ceiling() and before_slide_y < 0:
		_try_correct_ceiling(before_slide_y)
	if not grounded and is_on_floor() and before_slide_y > 180:
		visual_scale = Vector2(1.18, 0.84)
		game.effect(global_position + Vector2(0, 22), Color("8aa4ac"), "land")
	visual_scale = visual_scale.lerp(Vector2.ONE, 1.0 - exp(-18.0 * delta))
	var world_bounds: Rect2 = game.stage.bounds
	position.x = clampf(position.x, world_bounds.position.x + 24, world_bounds.end.x - 24)
	if Input.is_action_pressed("shoot") and shot_cooldown <= 0:
		game.spawn_bullet(self, shot_direction())
		shot_cooldown = T.SHOT_INTERVAL
	if pending_special and gauge > 0:
		game.fire_special(self, take_gauge())
	pending_special = false

func _try_drop_through() -> bool:
	var platform_bottom := -INF
	for index in range(get_slide_collision_count()):
		var contact := get_slide_collision(index)
		if contact.get_normal().dot(up_direction) < cos(floor_max_angle):
			continue
		var body := contact.get_collider() as CollisionObject2D
		# A simultaneous solid support (e.g. the edge of a block) must stay solid.
		if body == null or not body.collision_layer & T.PLATFORM_LAYER:
			return false
		var shape := contact.get_collider_shape() as CollisionShape2D
		if shape != null and shape.shape is RectangleShape2D:
			platform_bottom = maxf(platform_bottom, shape.global_position.y + shape.shape.size.y / 2)
	if platform_bottom == -INF:
		return false
	drop_clear_y = platform_bottom + T.DROP_THROUGH_CLEARANCE
	drop_remaining = T.DROP_THROUGH_MAX_TIME
	collision_mask &= ~T.PLATFORM_LAYER
	coyote = 0.0
	jump_buffer = 0.0
	return true

func _try_correct_ceiling(upward_velocity: float) -> bool:
	# Nudge only a grazing corner. A real ceiling still stops the jump.
	var preferred := 1 if velocity.x >= 0 else -1
	for distance in range(2, T.CEILING_CORRECTION + 1, 2):
		for direction in [preferred, -preferred]:
			var offset := Vector2((distance + safe_margin * 2.0) * direction, 0)
			if test_move(global_transform, offset):
				continue
			if not test_move(global_transform.translated(offset), Vector2(0, -8)):
				position += offset + Vector2(0, -2)
				velocity.y = upward_velocity
				return true
	return false
