extends Node2D
const T := preload("res://scripts/tuning.gd")
const Art := preload("res://scripts/sprite_art.gd")
const Bullet := preload("res://scripts/projectile.gd")
var game: Node2D
var _had := false

func _process(_delta: float) -> void:
	if game == null or not is_instance_valid(game.projectiles): return
	var any: bool = game.projectiles.get_child_count() > 0
	if any or _had: queue_redraw()
	_had = any

func _draw() -> void:
	if game == null or not is_instance_valid(game.projectiles): return
	var bullets: Array = []
	for child in game.projectiles.get_children():
		if child is Bullet and not child.is_queued_for_deletion() and child.trail.size() > 1: bullets.append(child)
	if Art.enabled():
		for bullet: Node2D in bullets: _draw_trail(bullet, Color("091326"), 7 if bullet.homing else 5)
	for bullet: Node2D in bullets: _draw_trail(bullet, Color(T.COLORS[bullet.polarity], 0.4), 4 if bullet.homing else 2)

func _draw_trail(bullet: Node2D, tint: Color, width: float) -> void:
	for index in range(1, bullet.trail.size()):
		draw_line(bullet.trail[index - 1], bullet.trail[index], tint, width)
