extends Node2D
const T := preload("res://scripts/tuning.gd")
var game: Node2D
var spawn: Dictionary
var age := 0.0

func _physics_process(delta: float) -> void:
	age += delta
	try_collect()
	queue_redraw()

func try_collect() -> bool:
	if is_queued_for_deletion() or not is_instance_valid(game.player) or game.player.dead: return false
	var player_rect := Rect2(game.player.position - game.player.body_size / 2, game.player.body_size)
	if not player_rect.intersects(Rect2(position - T.HEART_SIZE / 2, T.HEART_SIZE)): return false
	if game.player.heal(T.HEART_HEAL) <= 0: return false
	if game.stream != null: game.stream.remember_heart(spawn)
	queue_free()
	return true

func _draw() -> void:
	draw_set_transform(Vector2(0, sin(age * TAU / T.HEART_BOB_PERIOD) * T.HEART_BOB_HEIGHT))
	draw_circle(Vector2.ZERO, 23, Color(T.HEART_COLOR, 0.12))
	var points := PackedVector2Array([Vector2(0, 12), Vector2(-13, -1), Vector2(-13, -7), Vector2(-8, -12), Vector2(-3, -12), Vector2(0, -8), Vector2(3, -12), Vector2(8, -12), Vector2(13, -7), Vector2(13, -1)])
	draw_colored_polygon(points, T.HEART_COLOR)
	points.append(points[0])
	draw_polyline(points, Color("ffe5f1"), 2, true)
	draw_line(Vector2(-8, -7), Vector2(-5, -8), Color.WHITE, 2, true)
