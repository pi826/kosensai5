extends "res://scripts/combatant.gd"

var shot_cooldown := 0.0
var coyote := 0.0
var jump_buffer := 0.0
var pending_special := false
var jump_cut_requested := false

func _unhandled_input(event: InputEvent) -> void:
	if dead or event.is_echo():
		return
	# A short tap can occur entirely between physics ticks. Keep discrete actions.
	if event.is_action_pressed("switch_color"):
		polarity = 1 - polarity
		game.effect(global_position, T.COLORS[polarity], "switch")
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
	var grounded := is_on_floor()
	var acceleration: float = T.GROUND_ACCELERATION if grounded else T.AIR_ACCELERATION
	if is_zero_approx(horizontal):
		acceleration = T.GROUND_DECELERATION if grounded else T.AIR_DECELERATION
	velocity.x = move_toward(velocity.x, horizontal * T.MOVE_SPEED, acceleration * delta)
	if not is_zero_approx(horizontal):
		facing = 1 if horizontal > 0 else -1
	coyote = T.COYOTE_TIME if is_on_floor() else maxf(0.0, coyote - delta)
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
	if is_on_ceiling() and before_slide_y < 0:
		_try_correct_ceiling(before_slide_y)
	if not grounded and is_on_floor() and before_slide_y > 180:
		visual_scale = Vector2(1.18, 0.84)
		game.effect(global_position + Vector2(0, 22), Color("8aa4ac"), "land")
	visual_scale = visual_scale.lerp(Vector2.ONE, 1.0 - exp(-18.0 * delta))
	var room_rect: Rect2 = game.current_room().rect
	position.x = clampf(position.x, room_rect.position.x + 24, room_rect.end.x - 24)
	if Input.is_action_pressed("shoot") and shot_cooldown <= 0:
		game.spawn_bullet(self, Vector2(facing, 0))
		shot_cooldown = T.SHOT_INTERVAL
	if pending_special and gauge > 0:
		game.fire_special(self, take_gauge())
	pending_special = false

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
