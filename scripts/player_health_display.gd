extends Node2D
## Follows the player; its timer belongs to the pausable effects tree.
const T := preload("res://scripts/tuning.gd")
var actor_ref: WeakRef
var health := 0
var maximum := 1
var trail_hp := 0.0
var healing_from := 0
var age := 0.0
var remaining := 0.0

func change(actor: CharacterBody2D, before: int, after: int) -> void:
	actor_ref = weakref(actor)
	health = after
	maximum = actor.max_hp
	trail_hp = float(before if before > after else after)
	healing_from = before if after > before else after
	age = 0.0
	remaining = T.PLAYER_HP_DISPLAY_TIME
	modulate.a = 1.0
	visible = true
	_follow()
	queue_redraw()

func _follow() -> void:
	var actor = actor_ref.get_ref() if actor_ref != null else null
	if is_instance_valid(actor):
		global_position = actor.global_position + Vector2(0, -actor.body_size.y / 2 - T.PLAYER_HP_BAR_OFFSET)

func _process(delta: float) -> void:
	if remaining <= 0.0:
		return
	_follow()
	age += delta
	remaining = maxf(0.0, remaining - delta)
	# Only the part of this tick after the hold period advances the red trail.
	var decay_delta := minf(delta, maxf(0.0, age - T.PLAYER_HP_TRAIL_DELAY))
	trail_hp = move_toward(trail_hp, health, T.PLAYER_HP_TRAIL_SPEED * decay_delta)
	visible = remaining > 0.0
	modulate.a = clampf(remaining / T.PLAYER_HP_FADE_TIME, 0.0, 1.0)
	queue_redraw()

func bar_segments() -> Dictionary:
	var heal_start := healing_from if age < T.PLAYER_HP_HEAL_TIME else health
	var scale := T.PLAYER_HP_BAR_SIZE.x / float(maxi(maximum, 1))
	return {"green": heal_start * scale, "healing": (health - heal_start) * scale,
		"red": maxf(0.0, trail_hp - health) * scale,
		"gray": maxf(0.0, maximum - maxf(health, trail_hp)) * scale}

func _draw() -> void:
	var segments := bar_segments()
	var start := -T.PLAYER_HP_BAR_SIZE / 2
	draw_rect(Rect2(start - Vector2.ONE * 2, T.PLAYER_HP_BAR_SIZE + Vector2.ONE * 4), Color("07111d"))
	var x := start.x
	for key in ["green", "healing", "red", "gray"]:
		var width: float = segments[key]
		if width > 0:
			draw_rect(Rect2(Vector2(x, start.y), Vector2(width, T.PLAYER_HP_BAR_SIZE.y)), T.PLAYER_HP_COLORS[key])
		x += width
