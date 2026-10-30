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
var homing_charges := 0
var abilities := 0
var air_jump_used := false
var air_dash_used := false
var dash_remaining := 0.0
var dash_direction := 1
var pending_dash := false
var gliding := false
var equipment := {"weapon": "", "armor": "", "charm": ""}

func wears(id: String) -> bool:
	return equipment.values().has(id)

func shot_interval() -> float:
	return T.SHOT_INTERVAL * (T.RAPID_INTERVAL_RATIO if wears("rapid") else 1.0)

func move_speed() -> float:
	return T.MOVE_SPEED * (T.BOOTS_SPEED_RATIO if wears("boots") else 1.0)

func charge_capacity() -> int:
	return T.HOMING_CHARGE_CAPACITY + (T.HOMING_CAPACITY_BONUS if wears("homing") else 0)

func volley_size() -> int:
	return T.HOMING_VOLLEY_SIZE + (T.HOMING_VOLLEY_BONUS if wears("homing") else 0)

func absorptions_per_charge() -> int:
	return T.EFFICIENT_ABSORPTIONS if wears("absorb") else T.ABSORPTIONS_PER_CHARGE

func hit_damage(amount: int) -> int:
	return maxi(1, ceili(amount * T.ARMOR_DAMAGE_RATIO)) if wears("cushion") else amount

func hurt_invulnerability() -> float:
	return T.INVULNERABILITY + (T.LONG_INVULNERABILITY_BONUS if wears("invincible") else 0.0)

func apply_equipment(slot: String, id: String) -> void:
	var old_max := max_hp
	var previous_hp := hp
	equipment[slot] = id
	max_hp = T.PLAYER_HP + (T.SHELL_HP_BONUS if wears("shell") else 0)
	# Preserve missing HP across equipment changes; removal alone cannot kill.
	if max_hp != old_max: hp = clampi(hp + max_hp - old_max, 1, max_hp)
	if hp != previous_hp or max_hp != old_max: _hp_changed(previous_hp)
	homing_charges = mini(homing_charges, charge_capacity())
	gauge = mini(gauge, absorptions_per_charge())
	invulnerability = minf(invulnerability, hurt_invulnerability())
	shot_cooldown = minf(shot_cooldown, shot_interval())

func has_ability(ability: int) -> bool:
	return not game.is_tutorial() and (abilities & ability) == ability

func _absorb_attack() -> void:
	gauge = mini(absorptions_per_charge(), gauge + 1)
	if gauge == absorptions_per_charge() and homing_charges < charge_capacity():
		gauge = 0
		add_homing_charges(1)

func add_homing_charges(amount: int) -> int:
	if dead or amount <= 0: return 0
	var before := homing_charges
	homing_charges = mini(charge_capacity(), homing_charges + amount)
	var gained := homing_charges - before
	if gained > 0 and is_instance_valid(game): game.play_sound("charge", position)
	if gained > 0 and is_instance_valid(game) and is_instance_valid(game.effects):
		game.effects.show_charge(global_position, gained)
	return gained

func launch_homing() -> bool:
	if dead: return false
	if homing_charges <= 0:
		game.play_sound("empty", position)
		return false
	homing_charges -= 1
	game.fire_special(self, volley_size())
	return true

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
		game.play_sound("heal", position)
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
			receive_hit(enemy.polarity, enemy.outgoing_damage(T.CONTACT_DAMAGE) if enemy.has_method("outgoing_damage") else T.CONTACT_DAMAGE)
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
		game.play_sound("switch", position, 0, 1, polarity)
	elif event.is_action_pressed("aim_cycle"):
		aim_index = (aim_index + 1) % T.AIM_ANGLES.size()
		game.play_sound("aim", position, 0, [1.0, 1.25, 0.8][aim_index])
		queue_redraw()
	elif event.is_action_pressed("jump"):
		jump_buffer = T.JUMP_BUFFER
		jump_cut_requested = false
	elif event.is_action_released("jump"):
		if not Input.is_action_pressed("jump"):
			jump_cut_requested = true
	elif event.is_action_pressed("special"):
		pending_special = true
	elif event.is_action_pressed("dash"):
		pending_dash = true
	elif event.is_action_pressed("interact") and not game.is_tutorial():
		game.interact()
	elif event.is_action_pressed("use_item") and not game.is_tutorial():
		game.use_potion()

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
	if grounded:
		air_jump_used = false
		air_dash_used = false
		dash_remaining = 0.0
	var acceleration: float = T.GROUND_ACCELERATION if grounded else T.AIR_ACCELERATION
	if is_zero_approx(horizontal):
		acceleration = T.GROUND_DECELERATION if grounded else T.AIR_DECELERATION
	velocity.x = move_toward(velocity.x, horizontal * move_speed(), acceleration * delta)
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
		game.play_sound("jump", position)
	elif jump_buffer > 0 and not grounded and dash_remaining <= 0 and not air_jump_used and has_ability(T.ABILITY_DOUBLE):
		air_jump_used = true
		velocity.y = -T.JUMP_SPEED * T.DOUBLE_JUMP_RATIO
		jump_buffer = 0.0
		visual_scale = Vector2(0.82, 1.16)
		game.effect(global_position, T.CRYSTAL_COLOR, "jump")
		game.play_sound("air_jump", position)
	if jump_cut_requested:
		if velocity.y < 0:
			velocity.y = maxf(velocity.y, -T.JUMP_CUT_SPEED)
			jump_cut_requested = false
		elif jump_buffer <= 0:
			jump_cut_requested = false
	var gravity: float = T.GRAVITY if velocity.y < 0 else T.FALL_GRAVITY
	velocity.y = minf(velocity.y + gravity * delta, T.MAX_FALL_SPEED)
	var was_gliding := gliding
	gliding = not grounded and has_ability(T.ABILITY_GLIDE) and velocity.y > 0 and Input.is_action_pressed("jump")
	if gliding: velocity.y = minf(velocity.y, T.GLIDE_FALL_SPEED)
	if pending_dash and not grounded and not air_dash_used and has_ability(T.ABILITY_DASH):
		air_dash_used = true
		dash_remaining = T.AIR_DASH_TIME
		dash_direction = facing
		game.effect(global_position, T.CRYSTAL_COLOR, "dash")
		game.play_sound("dash", position)
	pending_dash = false
	var dashing := dash_remaining > 0.0
	if dashing:
		velocity = Vector2(dash_direction * T.AIR_DASH_SPEED, 0)
		dash_remaining = maxf(0.0, dash_remaining - delta)
		gliding = false
	var before_slide_y := velocity.y
	move_and_slide()
	if is_on_floor(): gliding = false
	if gliding and not was_gliding: game.play_sound("glide", position)
	if dashing:
		if is_on_wall(): dash_remaining = 0.0
		if dash_remaining <= 0: velocity.x = horizontal * move_speed()
	_check_enemy_contact()
	if dead:
		return
	if is_on_ceiling() and before_slide_y < 0:
		_try_correct_ceiling(before_slide_y)
	if not grounded and is_on_floor() and before_slide_y > 180:
		visual_scale = Vector2(1.18, 0.84)
		game.effect(global_position + Vector2(0, 22), Color("8aa4ac"), "land")
		game.play_sound("land", position, linear_to_db(clampf(before_slide_y / 900.0, 0.25, 1.0)))
	visual_scale = visual_scale.lerp(Vector2.ONE, 1.0 - exp(-18.0 * delta))
	if Input.is_action_pressed("shoot") and shot_cooldown <= 0:
		fire_normal()
		shot_cooldown = shot_interval()
	if pending_special:
		launch_homing()
	pending_special = false

func fire_normal() -> void:
	game.play_sound("shot", position, 0, 1, polarity)
	var direction := shot_direction()
	for spread: float in ([-T.TRIPLE_SPREAD, 0.0, T.TRIPLE_SPREAD] if wears("triple") else [0.0]):
		game.spawn_bullet(self, direction.rotated(spread))

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

func _draw() -> void:
	super._draw()
	if gliding:
		draw_polyline(PackedVector2Array([Vector2(-32,-18), Vector2(-18,-30), Vector2(0,-34), Vector2(18,-30), Vector2(32,-18)]), T.CRYSTAL_COLOR, 3, true)
	if dash_remaining > 0:
		for i in range(3):
			draw_line(Vector2(-facing*(22+i*12), -8+i*8), Vector2(-facing*(44+i*12), -8+i*8), Color(T.CRYSTAL_COLOR,0.7-i*0.15), 3, true)

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
