extends Node2D
## One warning owns the fixed target/color; flight survives source death and region changes.
const T := preload("res://scripts/tuning.gd")
var game: Node2D
var source: CharacterBody2D
var polarity := 0
var target := Vector2.ZERO
var velocity := Vector2.ZERO
var phase := "warning"
var elapsed := 0.0
var exploded := false
var damage := T.BOMB_DAMAGE

func fire() -> void:
	phase = "flight"
	global_position = source.global_position + Vector2(0, -source.body_size.y / 2 - 8)
	velocity = (target - global_position) / T.BOMB_FLIGHT_TIME - Vector2(0, T.BOMB_GRAVITY * T.BOMB_FLIGHT_TIME / 2)

func cancel() -> void:
	if phase == "warning":
		hide()
		queue_free()

func _physics_process(delta: float) -> void:
	elapsed += delta
	if phase == "warning":
		if not is_instance_valid(source) or source.dead or not game.is_on_screen(source.global_position, 20):
			cancel()
	elif phase == "flight" and not exploded:
		var next := global_position + velocity * delta + Vector2(0, T.BOMB_GRAVITY * delta * delta / 2)
		velocity.y += T.BOMB_GRAVITY * delta
		var ray := PhysicsRayQueryParameters2D.create(global_position, next, 1 | 2 | T.PLATFORM_LAYER)
		ray.hit_from_inside = true
		var hit := get_world_2d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty():
			global_position = hit.position
			detonate()
		elif not game.loaded_contains(next):
			queue_free()
		else:
			global_position = next
	queue_redraw()

func detonate() -> void:
	if exploded:
		return
	exploded = true
	if is_instance_valid(game.terrain):
		game.terrain.explode(global_position, T.BOMB_RADIUS)
	if is_instance_valid(game.player) and not game.player.dead:
		var body := Rect2(game.player.global_position - game.player.body_size / 2, game.player.body_size)
		if global_position.distance_squared_to(global_position.clamp(body.position, body.end)) <= T.BOMB_RADIUS * T.BOMB_RADIUS:
			game.player.receive_hit(polarity, damage)
	game.effect(global_position, T.COLORS[polarity], "bomb")
	queue_free()

func _draw() -> void:
	var tint: Color = T.COLORS[polarity]
	var mark := to_local(target)
	draw_arc(mark, T.BOMB_RADIUS, 0, TAU, 32, Color(tint, 0.5), 2, true)
	draw_line(mark - Vector2(12, 0), mark + Vector2(12, 0), tint, 2)
	draw_line(mark - Vector2(0, 12), mark + Vector2(0, 12), tint, 2)
	if phase == "flight":
		draw_circle(Vector2.ZERO, 9, tint.darkened(0.6))
		draw_arc(Vector2.ZERO, 9, 0, TAU, 20, tint, 2, true)
		draw_line(Vector2.ZERO, -velocity.normalized() * 18, tint, 3)
