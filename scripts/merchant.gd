extends Node2D
## A peaceful NPC. No combatant group, attack, or physics collision layer.
const T := preload("res://scripts/tuning.gd")
var game: Node2D
var spawn: Dictionary
var art_age := 0.0

func _process(delta: float) -> void:
	art_age += delta
	queue_redraw()

func _ready() -> void:
	add_to_group("merchants")

func _draw() -> void:
	if preload("res://scripts/sprite_art.gd").draw_frame(self,"merchant","idle",0,art_age,Vector2(0,24),1): return
	draw_rect(Rect2(-19, 19, 38, 5), Color(0, 0, 0, 0.25))
	draw_colored_polygon(PackedVector2Array([Vector2(-15,22),Vector2(-12,-6),Vector2(12,-6),Vector2(15,22)]), Color("325d58"))
	draw_polyline(PackedVector2Array([Vector2(-15,22),Vector2(-12,-6),Vector2(12,-6),Vector2(15,22)]), T.MERCHANT_COLOR, 2, true)
	draw_circle(Vector2(0,-12), 9, Color("e9d3ae"))
	draw_line(Vector2(-17,-17), Vector2(17,-17), T.MERCHANT_COLOR, 5)
	draw_rect(Rect2(-10,-24,20,8), T.MERCHANT_COLOR)
	draw_rect(Rect2(12,1,13,16), Color("b49b62"))
	draw_line(Vector2(-4,5), Vector2(4,5), T.MERCHANT_COLOR, 3)
