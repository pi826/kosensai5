extends Control
## Its bounds, nodes and edges depend only on visited rooms.

const Terrain := preload("res://scripts/room_terrain.gd")
var game

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func update_map() -> void:
	queue_redraw()

func get_visible_rooms() -> Array:
	var result: Array = []
	if game == null:
		return result
	for room_data: Dictionary in game.stage.get("rooms", []):
		if game.visited_rooms.get(int(room_data.id), false):
			result.append(room_data)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.id) < int(b.id))
	return result

func _draw() -> void:
	var panel := Rect2(Vector2.ZERO, size)
	draw_style_box(_panel_style(), panel)
	var font := get_theme_default_font()
	draw_string(font, Vector2(12, 19), "MAP", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("d0dce2"))
	var rooms := get_visible_rooms()
	if rooms.is_empty():
		return
	var min_grid: Vector2i = rooms[0].grid
	var max_grid: Vector2i = min_grid
	var known: Dictionary = {}
	for room_data: Dictionary in rooms:
		var grid: Vector2i = room_data.grid
		min_grid = Vector2i(mini(min_grid.x, grid.x), mini(min_grid.y, grid.y))
		max_grid = Vector2i(maxi(max_grid.x, grid.x), maxi(max_grid.y, grid.y))
		known[int(room_data.id)] = room_data
	var map_area := Rect2(Vector2(16, 32), Vector2(maxf(32, size.x - 32), maxf(32, size.y - 65)))
	var span := Vector2(max_grid - min_grid) + Vector2.ONE
	var pitch := minf(28, minf(map_area.size.x / span.x, map_area.size.y / span.y))
	var center_grid := (Vector2(min_grid) + Vector2(max_grid)) / 2
	var map_origin := map_area.get_center() - center_grid * pitch
	for room_data: Dictionary in rooms:
		var start := map_origin + Vector2(room_data.grid) * pitch
		for door: Dictionary in room_data.get("doors", []):
			var target_id := int(door.target)
			if target_id <= int(room_data.id) or not known.has(target_id):
				continue
			var target_room: Dictionary = known[target_id]
			var finish := map_origin + Vector2(target_room.grid) * pitch
			draw_line(start, finish, Color("61717a"), maxf(1, pitch * 0.09))
	for room_data: Dictionary in rooms:
		var at := map_origin + Vector2(room_data.grid) * pitch
		var width := maxf(7, pitch * 0.62)
		var box := Rect2(at - Vector2(width, width * 0.70) / 2, Vector2(width, width * 0.70))
		var theme: Dictionary = Terrain.THEMES[clampi(int(room_data.get("biome", 0)), 0, 2)]
		draw_rect(box, theme.accent)
		if int(room_data.id) == int(game.current_room_id):
			draw_rect(box.grow(2), Color("f4f8fa"), false, 2)
		var boss_id := int(room_data.get("boss_id", -1))
		if boss_id >= 0:
			var radius := maxf(3, width * 0.24)
			if game.defeated_bosses.has(boss_id):
				draw_polyline(PackedVector2Array([at + Vector2(-radius, 0), at + Vector2(-radius * 0.15, radius * 0.7), at + Vector2(radius, -radius * 0.7)]), Color("eff7ed"), 2)
			else:
				draw_colored_polygon(PackedVector2Array([at + Vector2(0, -radius), at + Vector2(radius, 0), at + Vector2(0, radius), at + Vector2(-radius, 0)]), Color("f0d8b2"))
	var cleared := 0
	if game != null:
		cleared = game.defeated_bosses.size()
	draw_string(font, Vector2(12, size.y - 12), "ROOMS %d   GUARDIANS %d / 3" % [rooms.size(), cleared], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("aebdc5"))

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.055, 0.075, 0.92)
	style.border_color = Color("405460")
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	return style
