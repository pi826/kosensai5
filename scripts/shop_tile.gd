extends Button
## Category stripe and geometric icon; no image assets.
var category := "weapon"
var tint := Color("89cfff")

func _draw() -> void:
	draw_rect(Rect2(0, 8, 5, size.y - 16), tint)
	var at := Vector2(22, 25)
	match category:
		"potion":
			draw_rect(Rect2(at - Vector2(7, 5), Vector2(14, 15)), tint, false, 2)
			draw_rect(Rect2(at - Vector2(4, 10), Vector2(8, 5)), tint)
			draw_line(at + Vector2(-3, 2), at + Vector2(3, 2), tint, 2)
		"key":
			draw_circle(at - Vector2(3, 3), 5, tint, false, 2)
			draw_line(at, at + Vector2(8, 9), tint, 2)
			draw_line(at + Vector2(5, 6), at + Vector2(9, 3), tint, 2)
		"armor":
			draw_colored_polygon(PackedVector2Array([at+Vector2(-8,-8), at+Vector2(8,-8), at+Vector2(7,3), at+Vector2(0,11), at+Vector2(-7,3)]), tint)
		"charm":
			draw_colored_polygon(PackedVector2Array([at+Vector2(0,-10), at+Vector2(8,0), at+Vector2(0,10), at+Vector2(-8,0)]), tint)
		_:
			draw_rect(Rect2(at-Vector2(9,5), Vector2(18,7)), tint)
			draw_line(at+Vector2(-4,2), at+Vector2(-4,10), tint, 4)
