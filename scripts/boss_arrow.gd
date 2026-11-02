extends Control
## Draw in the HUD canvas, above terrain/actors/shots, below menus and other HUD.
const T := preload("res://scripts/tuning.gd")
const Art := preload("res://scripts/sprite_art.gd")
var game: Node2D

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var target: Dictionary = game.boss_arrow_state()
	if target.is_empty(): return
	var direction: Vector2 = target.direction
	var center: Vector2 = game.player.get_global_transform_with_canvas().origin + direction * T.BOSS_ARROW_RADIUS
	draw_set_transform(center,direction.angle())
	var drawn := Art.draw_frame(self,"boss_arrow","idle",0,0,Vector2.ZERO,1)
	draw_set_transform(Vector2.ZERO)
	if drawn: return
	var side := direction.orthogonal()
	var half := T.BOSS_ARROW_LENGTH / 2
	var width := T.BOSS_ARROW_WIDTH / 2
	var points := PackedVector2Array([center + direction * half, center - direction * half + side * width,
		center - direction * half * 0.5, center - direction * half - side * width])
	draw_colored_polygon(points, T.BOSS_ARROW_COLOR)
	points.append(points[0])
	draw_polyline(points, T.BOSS_ARROW_OUTLINE, T.BOSS_ARROW_OUTLINE_WIDTH, true)
