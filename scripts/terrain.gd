extends StaticBody2D
const T := preload("res://scripts/tuning.gd")

var bounds := Rect2()

func _ready() -> void:
	collision_layer = T.PLATFORM_LAYER if bounds.size.y <= 20.0 else 1
	collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = bounds.size
	var collider := CollisionShape2D.new()
	collider.shape = shape
	collider.position = bounds.get_center()
	# Raised thin shelves can be jumped through from below, then landed on.
	collider.one_way_collision = bounds.size.y <= 20.0
	collider.one_way_collision_margin = 4.0
	add_child(collider)

func _draw() -> void:
	var art := preload("res://scripts/sprite_art.gd")
	var path := art.terrain_path(0,bounds.size.y<=20)
	var texture := art.texture(path,path)
	if texture != null:
		for y in range(int(bounds.position.y),ceili(bounds.end.y),32):
			for x in range(int(bounds.position.x),ceili(bounds.end.x),32):
				var extent := Vector2(minf(32,bounds.end.x-x),minf(32,bounds.end.y-y))
				var source := Vector2.ZERO if bounds.size.y<=20 else Vector2((124 if y==bounds.position.y else 255)*32,0)
				draw_texture_rect_region(texture,Rect2(Vector2(x,y),extent),Rect2(source,extent))
		return
	draw_rect(bounds, Color("142d40"))
	draw_rect(Rect2(bounds.position, Vector2(bounds.size.x, minf(7.0, bounds.size.y))), Color("45677a"))
	draw_line(bounds.position, bounds.position + Vector2(bounds.size.x, 0), Color("8eabb9"), 2)
	if bounds.size.y > 20:
		for x in range(int(bounds.position.x) + 20, int(bounds.end.x), 48):
			draw_line(Vector2(x, bounds.position.y + 20), Vector2(x + 12, bounds.position.y + 32), Color("244254"), 2)
