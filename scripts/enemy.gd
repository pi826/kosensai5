extends "res://scripts/combatant.gd"

var patrol := Vector2.ZERO
var shot_clock := 0.7
var switch_clock := T.SWITCH_INTERVAL
var wake_delay := T.ENEMY_WAKE_DELAY
var was_visible := false
var pattern := 0
var boss_id := -1
var spawn_id := ""

func _ready() -> void:
	faction = 1
	body_size = T.BOSS_SIZE if kind == "boss" else T.ENEMY_SIZE
	max_hp = T.BOSS_HP if kind == "boss" else T.ENEMY_HP
	hp = max_hp
	facing = -1
	super._ready()

func _physics_process(delta: float) -> void:
	if dead or not is_instance_valid(game.player):
		return
	tick_visuals(delta)
	velocity.y += T.GRAVITY * delta
	var on_screen: bool = game.is_on_screen(global_position, 20.0)
	if not on_screen:
		was_visible = false
		action = "idle"
		velocity.x = 0
		move_and_slide()
		return
	if not was_visible:
		wake_delay = T.ENEMY_WAKE_DELAY
		was_visible = true
	facing = 1 if game.player.position.x > position.x else -1
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
	wake_delay = maxf(0.0, wake_delay - delta)
	if wake_delay > 0:
		return
	if action != "idle":
		action_remaining -= delta
		if action_remaining <= 0:
			_complete_action()
		return
	shot_clock -= delta
	switch_clock -= delta
	if (kind == "shifter" or kind == "boss") and switch_clock <= 0:
		next_polarity = 1 - polarity
		_begin("windup_switch", T.SWITCH_WARNING)
	elif gauge >= T.GAUGE_CAPACITY:
		_begin("windup_special", T.SPECIAL_WARNING)
	elif shot_clock <= 0:
		_begin("windup_shot", T.SHOT_WARNING)

func _begin(next_action: String, duration: float) -> void:
	action = next_action
	action_remaining = duration

func _complete_action() -> void:
	match action:
		"windup_switch":
			polarity = next_polarity
			switch_clock = T.SWITCH_INTERVAL
			pattern = 1 - pattern
			game.effect(global_position, T.COLORS[polarity], "switch")
		"windup_special":
			game.fire_special(self, take_gauge())
			shot_clock = T.ENEMY_SHOT_INTERVAL
		"windup_shot":
			var direction: Vector2 = (game.player.global_position - global_position).normalized()
			if kind == "boss" and pattern == 1:
				for angle in [-0.34, -0.17, 0.0, 0.17, 0.34]:
					game.spawn_bullet(self, direction.rotated(angle))
			else:
				game.spawn_bullet(self, direction)
			shot_clock = T.BOSS_SHOT_INTERVAL if kind == "boss" else T.ENEMY_SHOT_INTERVAL
	action = "idle"
