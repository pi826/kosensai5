extends Control
## The map records explored world cells, rather than room nodes or door links.

const Terrain := preload("res://scripts/world_terrain.gd")
const CELL_SIZE := 128
const T := preload("res://scripts/tuning.gd")
var game
var _cached_seed := -9223372036854775807
var _cell_geometry: Dictionary = {}
var _terrain_version: Array[int] = [-1, -1]

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func update_map() -> void:
	if game != null and "terrain" in game and is_instance_valid(game.terrain):
		var version: Array[int] = [game.terrain.get_instance_id(), game.terrain.revision]
		if version != _terrain_version:
			_terrain_version = version
			_cell_geometry.clear()
	if game != null and int(game.stage.get("seed", 0)) != _cached_seed:
		_cached_seed = int(game.stage.get("seed", 0))
		_cell_geometry.clear()
	queue_redraw()

func get_explored_cells() -> Array:
	var result: Array = []
	if game == null:
		return result
	for cell in game.explored_cells:
		if game.explored_cells[cell]:
			result.append(cell)
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or a.y == b.y and a.x < b.x)
	return result

func get_visible_bosses() -> Array:
	var result: Array = []
	if game == null:
		return result
	for boss_id in game.discovered_bosses:
		result.append({"id": int(boss_id), "position": game.discovered_bosses[boss_id], "defeated": game.defeated_bosses.has(boss_id)})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.id) < int(b.id))
	return result

func _geometry_for_cell(cell: Vector2i) -> Array:
	if _cell_geometry.has(cell):
		return _cell_geometry[cell]
	var fragments: Array[Rect2] = []
	var area := Rect2(Vector2(cell) * CELL_SIZE, Vector2.ONE * CELL_SIZE)
	if "terrain" in game and is_instance_valid(game.terrain):
		fragments.assign(game.map_geometry(area))
		_cell_geometry[cell] = fragments
		return fragments
	for solid: Rect2 in game.stage.get("solids", []):
		if area.intersects(solid):
			fragments.append(area.intersection(solid))
	_cell_geometry[cell] = fragments
	return fragments

func map_area() -> Rect2:
	return Rect2(Vector2(12, 12), Vector2(maxf(32, size.x - 24), maxf(32, size.y - 24)))

func world_area() -> Rect2:
	var width := T.SECTOR_SIZE.x * T.MAP_SECTOR_WIDTH
	var extent := Vector2(width, width * map_area().size.y / map_area().size.x)
	var center: Vector2 = game.player.position if is_instance_valid(game.player) else game.stage.start_position
	return Rect2(center - extent / 2, extent)

func displayed_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var area := world_area()
	for y in range(floori(area.position.y / CELL_SIZE), ceili(area.end.y / CELL_SIZE)):
		for x in range(floori(area.position.x / CELL_SIZE), ceili(area.end.x / CELL_SIZE)):
			var cell := Vector2i(x, y)
			if game.explored_cells.get(cell, false): out.append(cell)
	return out

func guardian_marks() -> Array:
	var area := map_area().grow(-5)
	var world := world_area()
	var scale_factor := map_area().size.x / world.size.x
	var origin := map_area().position - world.position * scale_factor
	var out: Array = []
	for boss: Dictionary in get_visible_bosses():
		var at: Vector2 = origin + boss.position * scale_factor
		var offscreen := not area.has_point(at)
		if offscreen:
			var vector := at - area.get_center()
			var factor := minf(area.size.x / 2 / maxf(absf(vector.x), 0.001), area.size.y / 2 / maxf(absf(vector.y), 0.001))
			at = area.get_center() + vector * factor
		out.append({"id": boss.id, "position": at, "direction": (boss.position - world.get_center()).normalized(), "offscreen": offscreen, "defeated": boss.defeated})
	return out

func _draw() -> void:
	draw_style_box(_panel_style(), Rect2(Vector2.ZERO, size))
	if game == null or not game.stage.has("bounds"):
		return
	var bounds := world_area()
	var map_area := map_area()
	var scale_factor := minf(map_area.size.x / bounds.size.x, map_area.size.y / bounds.size.y)
	var origin := map_area.get_center() - bounds.get_center() * scale_factor
	var world_box := Rect2(origin + bounds.position * scale_factor, bounds.size * scale_factor)
	draw_rect(world_box, Color("080e15"))
	draw_rect(world_box, Color("344552"), false, 1)
	for cell: Vector2i in displayed_cells():
		var cell_box := Rect2(Vector2(cell) * CELL_SIZE, Vector2.ONE * CELL_SIZE).intersection(bounds)
		if not cell_box.has_area():
			continue
		var biome: int = game.biome_at(cell_box.get_center())
		var theme: Dictionary = Terrain.THEMES[clampi(biome, 0, 2)]
		var explored: Color = theme.back
		explored.a = 0.85
		draw_rect(Rect2(origin + cell_box.position * scale_factor, cell_box.size * scale_factor), explored)
		for raw_fragment: Rect2 in _geometry_for_cell(cell):
			var fragment := raw_fragment.intersection(bounds)
			if not fragment.has_area(): continue
			var mini := Rect2(origin + fragment.position * scale_factor, fragment.size * scale_factor)
			mini.size.y = maxf(0.8, mini.size.y)
			draw_rect(mini, theme.edge)
	var view: Rect2 = game.view_rect().intersection(bounds)
	draw_rect(Rect2(origin + view.position * scale_factor, view.size * scale_factor), Color("afc9d780"), false, 1)
	for boss: Dictionary in guardian_marks():
		var at: Vector2 = boss.position
		if boss.defeated:
			draw_polyline(PackedVector2Array([at + Vector2(-3, 0), at + Vector2(-0.5, 2), at + Vector2(4, -3)]), Color("d9f4d9"), 1.5)
		elif boss.offscreen:
			var direction: Vector2 = boss.direction
			draw_colored_polygon(PackedVector2Array([at + direction * 4, at - direction * 3 + direction.orthogonal() * 3, at - direction * 3 - direction.orthogonal() * 3]), Color("f0d8b2"))
		else:
			draw_colored_polygon(PackedVector2Array([at + Vector2(0, -3.5), at + Vector2(3.5, 0), at + Vector2(0, 3.5), at + Vector2(-3.5, 0)]), Color("f0d8b2"))
	if is_instance_valid(game.player):
		var at: Vector2 = origin + game.player.position * scale_factor
		draw_circle(at, 3.0, Color("0d1721"))
		draw_circle(at, 2.0, Color.WHITE)

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.055, 0.075, 0.92)
	style.border_color = Color("405460")
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	return style
