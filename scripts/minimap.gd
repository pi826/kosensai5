extends Control
## The map records explored world cells, rather than room nodes or door links.

const Terrain := preload("res://scripts/world_terrain.gd")
const CELL_SIZE := 128
const T := preload("res://scripts/tuning.gd")
const Art := preload("res://scripts/sprite_art.gd")
var game
var _cached_seed := -9223372036854775807
var _cell_geometry: Dictionary = {}
var _terrain_version: Array[int] = [-1, -1]
var _map_key: Array = []
var _last_redraw_frame := -1000000
var _redraws := 0

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
	var key := _map_state_key()
	var frame := Engine.get_process_frames()
	if key != _map_key or frame - _last_redraw_frame >= T.MINIMAP_MAX_STALE_FRAMES:
		_map_key = key
		_last_redraw_frame = frame
		_redraws += 1
		queue_redraw()

func _map_state_key() -> Array:
	var key: Array = []
	var map := map_area()
	var scale_factor := map.size.x / (T.SECTOR_SIZE.x * T.MAP_SECTOR_WIDTH)
	var player_node = game.get("player") if game != null else null
	var at: Vector2 = player_node.position if is_instance_valid(player_node) else Vector2.ZERO
	var view := Rect2()
	if game != null and game.has_method("view_rect"): view = game.view_rect()
	key.append(Vector2i(roundi(at.x * scale_factor), roundi(at.y * scale_factor)))
	key.append(Vector2i(roundi(view.position.x * scale_factor), roundi(view.position.y * scale_factor)))
	var terrain_node = game.get("terrain") if game != null else null
	key.append(terrain_node.revision if is_instance_valid(terrain_node) else -1)
	key.append(_count("explored_cells"))
	key.append(_count("discovered_bosses"))
	key.append(_count("defeated_bosses"))
	key.append(_count("discovered_loot"))
	key.append(_count("loot_taken"))
	key.append(_count("discovered_merchants"))
	key.append(game.get("origin_sector") if game != null and game.get("origin_sector") != null else Vector2i.ZERO)
	key.append(size)
	key.append(Art.upload_serial)
	return key

func _count(field: String) -> int:
	var value = game.get(field) if game != null else null
	return value.size() if value is Dictionary or value is Array else 0

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
		var role := "guardian"
		if "boss_cycle" in game and game.boss_cycle != null: role = game.boss_cycle.records.get(boss_id, {}).get("role", "guardian")
		var position: Vector2 = game.boss_mark(boss_id) if game.has_method("boss_mark") else game.discovered_bosses[boss_id]
		result.append({"id": int(boss_id), "position": position, "defeated": game.defeated_bosses.has(boss_id), "role": role})
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
			var stable_cell: Vector2i = cell + (game.map_origin() if game.has_method("map_origin") else Vector2i.ZERO)
			if game.explored_cells.get(stable_cell, false): out.append(cell)
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
		out.append({"id": boss.id, "role": boss.role, "position": at, "direction": (boss.position - world.get_center()).normalized(), "offscreen": offscreen, "defeated": boss.defeated})
	return out

func _draw() -> void:
	draw_style_box(preload("res://scripts/art_skin.gd").style("panel",_panel_style()), Rect2(Vector2.ZERO, size))
	if game == null or not game.stage.has("bounds"):
		return
	var bounds := world_area()
	var map_area := map_area()
	var scale_factor := minf(map_area.size.x / bounds.size.x, map_area.size.y / bounds.size.y)
	var origin := map_area.get_center() - bounds.get_center() * scale_factor
	var world_box := Rect2(origin + bounds.position * scale_factor, bounds.size * scale_factor)
	draw_rect(world_box, Color("080e15"))
	draw_rect(world_box, Color("344552"), false, 1)
	_draw_explored(bounds, origin, scale_factor)
	var view: Rect2 = game.view_rect().intersection(bounds)
	draw_rect(Rect2(origin + view.position * scale_factor, view.size * scale_factor), Color("afc9d780"), false, 1)
	for boss: Dictionary in guardian_marks():
		var at: Vector2 = boss.position
		var tint := Color("f0d8b2") if boss.role == "guardian" else (Color("ffdc79") if boss.role == "final" else Color("e4a8ff"))
		if not boss.defeated and not boss.offscreen and draw_mark("map_boss",at,12,tint): continue
		if boss.defeated:
			draw_polyline(PackedVector2Array([at + Vector2(-3, 0), at + Vector2(-0.5, 2), at + Vector2(4, -3)]), Color("d9f4d9"), 1.5)
		elif boss.offscreen:
			var direction: Vector2 = boss.direction
			draw_set_transform(at,direction.angle())
			var arrow_drawn := draw_mark("cursor",Vector2.ZERO,12,tint)
			draw_set_transform(Vector2.ZERO)
			if arrow_drawn: continue
			draw_colored_polygon(PackedVector2Array([at + direction * 4, at - direction * 3 + direction.orthogonal() * 3, at - direction * 3 - direction.orthogonal() * 3]), tint)
		else:
			draw_colored_polygon(PackedVector2Array([at + Vector2(0, -3.5), at + Vector2(3.5, 0), at + Vector2(0, 3.5), at + Vector2(-3.5, 0)]), tint)
			if boss.role != "guardian": draw_arc(at, 5, 0, TAU, 16, tint, 1, true)
	for mark: Dictionary in loot_marks():
		var at: Vector2 = origin + mark.position * scale_factor
		if not map_area.has_point(at): continue
		var tint := T.CRYSTAL_COLOR if mark.ability else Color("ffdf80")
		if draw_mark("map_key" if mark.kind=="key" else "map_chest",at,12,tint): continue
		if mark.kind == "key":
			draw_circle(at, 2.5, tint, false, 1.5, true)
			draw_line(at + Vector2(2, 2), at + Vector2(5, 5), tint, 1.5)
		elif mark.ability:
			draw_colored_polygon(PackedVector2Array([at+Vector2(0,-4),at+Vector2(4,0),at+Vector2(0,4),at+Vector2(-4,0)]), tint)
		else: draw_rect(Rect2(at - Vector2(3,2), Vector2(6,4)), tint, false, 1.5)
	for mark: Dictionary in merchant_marks():
		var at: Vector2 = origin + mark.position * scale_factor
		if not map_area.grow(-5).has_point(at): continue
		if draw_mark("map_merchant",at,14): continue
		draw_rect(Rect2(at - Vector2(4, 1), Vector2(8, 6)), T.MERCHANT_COLOR, false, 1.5)
		draw_colored_polygon(PackedVector2Array([at+Vector2(-5,-1),at+Vector2(0,-5),at+Vector2(5,-1)]), T.MERCHANT_COLOR)
	if is_instance_valid(game.player):
		var at: Vector2 = origin + game.player.position * scale_factor
		if not draw_mark("map_player",at,12):
			draw_circle(at, 3.0, Color("0d1721"))
			draw_circle(at, 2.0, Color.WHITE)

func draw_mark(id: String, at: Vector2, extent: float, tint: Color = Color.WHITE) -> bool:
	var desc := Art.description(id,"idle")
	if desc.is_empty(): return false
	var texture := Art.texture(desc.path,desc.path)
	if texture==null: return false
	var cell := Vector2(desc.cell[0],desc.cell[1])
	draw_texture_rect_region(texture,Rect2(at-Vector2.ONE*extent/2,Vector2.ONE*extent),Rect2(0,desc.row*cell.y,cell.x,cell.y),tint)
	return true

func loot_marks() -> Array:
	var out: Array = []
	if game == null or game.get("discovered_loot") == null: return out
	for id: String in game.discovered_loot:
		if game.loot_taken.has(id): continue
		var mark: Dictionary = game.discovered_loot[id].duplicate()
		mark.position = game.local_point(mark)
		out.append(mark)
	return out

func merchant_marks() -> Array:
	var out: Array = []
	if game == null or game.get("discovered_merchants") == null: return out
	for id: String in game.discovered_merchants:
		var mark: Dictionary = game.discovered_merchants[id].duplicate()
		mark.position = game.local_point(mark)
		mark.id = id
		out.append(mark)
	return out

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.055, 0.075, 0.92)
	style.border_color = Color("405460")
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	return style

func _draw_explored(bounds: Rect2, origin: Vector2, scale_factor: float) -> void:
	var biomes := {}
	for cell: Vector2i in displayed_cells():
		var cell_box := Rect2(Vector2(cell) * CELL_SIZE, Vector2.ONE * CELL_SIZE).intersection(bounds)
		if not cell_box.has_area():
			continue
		var center := cell_box.get_center()
		var sector := Vector2i(floori(center.x / T.SECTOR_SIZE.x), floori(center.y / T.SECTOR_SIZE.y))
		if not biomes.has(sector): biomes[sector] = game.biome_at(center)
		var biome: int = biomes[sector]
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
