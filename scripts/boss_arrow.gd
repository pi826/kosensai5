extends Control
## Draw in the HUD canvas, above terrain/actors/shots, below menus and other HUD.
const T := preload("res://scripts/tuning.gd")
var game: Node2D
var background: StyleBoxFlat

func _ready() -> void:
	background = StyleBoxFlat.new()
	background.bg_color = T.BOSS_ARROW_OUTLINE
	background.set_corner_radius_all(4)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var target: Dictionary = game.boss_arrow_state()
	if target.is_empty(): return
	var direction: Vector2 = target.direction
	var center: Vector2 = game.player.get_global_transform_with_canvas().origin + direction * T.BOSS_ARROW_RADIUS
	var side := direction.orthogonal()
	var half := T.BOSS_ARROW_LENGTH / 2
	var width := T.BOSS_ARROW_WIDTH / 2
	var points := PackedVector2Array([center + direction * half, center - direction * half + side * width,
		center - direction * half * 0.5, center - direction * half - side * width])
	draw_colored_polygon(points, T.BOSS_ARROW_COLOR)
	points.append(points[0])
	draw_polyline(points, T.BOSS_ARROW_OUTLINE, T.BOSS_ARROW_OUTLINE_WIDTH, true)
	var font := get_theme_default_font()
	var text: String = target.distance_text
	var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, T.BOSS_ARROW_FONT_SIZE)
	# Put the label outward for vertical
	# arrows and below for horizontal arrows so neither label nor arrow covers them.
	var label_center := center + Vector2(0, signf(direction.y) * (half + T.BOSS_ARROW_LABEL_GAP)) if absf(direction.y) > 0.65 else center + Vector2(0, half + T.BOSS_ARROW_LABEL_GAP)
	var baseline := label_center + Vector2(-size.x / 2, T.BOSS_ARROW_FONT_SIZE * 0.35)
	draw_style_box(background, Rect2(label_center - size / 2 - Vector2(5, 2), size + Vector2(10, 4)))
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, T.BOSS_ARROW_FONT_SIZE, T.BOSS_ARROW_COLOR)
