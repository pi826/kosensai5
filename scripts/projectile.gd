extends Node2D
const T := preload("res://scripts/tuning.gd")

var game: Node2D
var faction := 0
var polarity := 0
var damage := T.NORMAL_DAMAGE
var direction := Vector2.RIGHT
var speed := T.PLAYER_BULLET_SPEED
var homing := false
var target: Node2D
var life := T.BULLET_LIFETIME
var trail := PackedVector2Array()

func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0:
		queue_free()
		return
	if homing:
		if not is_instance_valid(target) or target.dead or target.is_queued_for_deletion():
			target = game.choose_homing_target(faction, polarity, global_position, self)
		if is_instance_valid(target):
			var desired := (target.global_position - global_position).angle()
			var turn := clampf(angle_difference(direction.angle(), desired), -T.HOMING_TURN_RATE * delta, T.HOMING_TURN_RATE * delta)
			direction = direction.rotated(turn).normalized()
	var next_position := global_position + direction * speed * delta
	if not game.loaded_contains(next_position):
		queue_free()
		return
	# Swept collision prevents fast shots tunnelling through a thin body or shelf.
	var mask := 1 | T.PLATFORM_LAYER | (4 | T.WALL_LAYER if faction == 0 else 2)
	var ray := PhysicsRayQueryParameters2D.create(global_position, next_position, mask)
	ray.hit_from_inside = true
	var hit := get_world_2d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		if hit.collider.has_method("receive_hit"):
			hit.collider.receive_hit(polarity, damage)
		else:
			if faction == 0 and is_instance_valid(game.terrain):
				game.terrain.damage_at(hit.position + direction * 0.5, damage, true)
			game.effect(hit.position, T.COLORS[polarity].darkened(0.3), "hit")
		queue_free()
		return
	global_position = next_position
	trail.append(global_position)
	if trail.size() > (10 if homing else 3):
		trail.remove_at(0)
	queue_redraw()

func _draw() -> void:
	var tint: Color = T.COLORS[polarity]
	if trail.size() > 1:
		var local_trail := PackedVector2Array()
		for point in trail:
			local_trail.append(to_local(point))
		draw_polyline(local_trail, Color(tint, 0.4), 4 if homing else 2, true)
	draw_circle(Vector2.ZERO, 10 if homing else 6, Color(tint, 0.15))
	draw_circle(Vector2.ZERO, 5 if homing else 3.5, tint)
	if homing:
		draw_circle(Vector2.ZERO, 2, Color.WHITE)
