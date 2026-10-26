extends Node2D
## One collision world. Rendering is split into spatial batches for canvas culling.

const T := preload("res://scripts/tuning.gd")
const Generator := preload("res://scripts/stage_generator.gd")
const TILE_SIZE := 32
const DRAW_CHUNK_SIZE := 512
const NORTH := 1
const NORTH_EAST := 2
const EAST := 4
const SOUTH_EAST := 8
const SOUTH := 16
const SOUTH_WEST := 32
const WEST := 64
const NORTH_WEST := 128
const THEMES := [
	{"back": Color("101e22"), "body": Color("263b3d"), "inner": Color("30484a"), "edge": Color("83a99b"), "shadow": Color("142a2e"), "accent": Color("668f7e")},
	{"back": Color("1c192a"), "body": Color("383247"), "inner": Color("463e55"), "edge": Color("a89abc"), "shadow": Color("282236"), "accent": Color("857694")},
	{"back": Color("241c22"), "body": Color("44363c"), "inner": Color("524249"), "edge": Color("b39a9e"), "shadow": Color("30252c"), "accent": Color("92767c")},
]

class DrawChunk extends Node2D:
	var terrain: Node2D
	var cells: Array[Vector2i] = []
	var shelves: Array[Rect2] = []
	var walls: Array[Vector2i] = []
	func _draw() -> void:
		for cell in cells:
			if terrain.tile_masks.has(cell):
				terrain.draw_tile(self, cell, terrain.tile_masks[cell])
		for shelf in shelves:
			terrain.draw_shelf(self, shelf)
		for cell in walls:
			terrain.draw_wall(self, cell)

var stage: Dictionary = {}
var tile_masks: Dictionary = {}
var occupied: Dictionary = {}
var collision_root: Node2D
var render_root: Node2D
var draw_chunks: Dictionary = {}
var surface_cells: Dictionary = {}
var destroyed_cells: Dictionary = {}
var breakables: Dictionary = {}
var block_cells: Dictionary = {}
var walls: Dictionary = {}
var wall_cells: Dictionary = {}
var row_cells: Dictionary = {}
var row_bodies: Dictionary = {}
var revision := 0
var next_wall_id := 0

func _ready() -> void:
	z_index = -2
	rebuild()

func rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	occupied.clear()
	tile_masks.clear()
	draw_chunks.clear()
	surface_cells.clear()
	destroyed_cells.clear()
	breakables.clear()
	block_cells.clear()
	walls.clear()
	wall_cells.clear()
	row_cells.clear()
	row_bodies.clear()
	next_wall_id = 0
	revision += 1
	collision_root = Node2D.new()
	collision_root.name = "Collision"
	add_child(collision_root)
	render_root = Node2D.new()
	render_root.name = "TileBatches"
	add_child(render_root)
	var shelves: Array[Rect2] = []
	# Excavation rectangles are explicit and can occur on any cave floor.
	for bounds: Rect2 in Generator.subtract_rects(stage.get("solids", []), stage.get("erodible_surfaces", [])):
		_add_collision(bounds)
	for bounds: Rect2 in stage.get("solids", []):
		if bounds.size.y == 16:
			shelves.append(bounds)
			continue
		for cell: Vector2i in _cells_in(bounds): occupied[cell] = true
	for bounds: Rect2 in stage.get("erodible_surfaces", []):
		for cell: Vector2i in _cells_in(bounds):
			if occupied.has(cell) and not _protected(Rect2(Vector2(cell) * TILE_SIZE, Vector2.ONE * TILE_SIZE)):
				surface_cells[cell] = true
				_set_row_cell(cell, 1, true)
	for bounds: Rect2 in stage.get("breakables", []):
		var id := breakables.size()
		var cells := _cells_in(bounds)
		breakables[id] = {"bounds": bounds, "cells": cells, "hp": T.TERRAIN_HP}
		for cell: Vector2i in cells:
			occupied[cell] = true
			block_cells[cell] = id
			_set_row_cell(cell, 1, true)
	for key: Vector2i in row_cells:
		_rebuild_row(key)
	for cell: Vector2i in occupied:
		tile_masks[cell] = mask_for_cell(cell)
		var key := Vector2i(floori(cell.x * TILE_SIZE / float(DRAW_CHUNK_SIZE)), floori(cell.y * TILE_SIZE / float(DRAW_CHUNK_SIZE)))
		_chunk(key).cells.append(cell)
	for shelf in shelves:
		for y in range(floori(shelf.position.y / DRAW_CHUNK_SIZE), ceili(shelf.end.y / DRAW_CHUNK_SIZE)):
			for x in range(floori(shelf.position.x / DRAW_CHUNK_SIZE), ceili(shelf.end.x / DRAW_CHUNK_SIZE)):
				var key := Vector2i(x, y)
				var clip := Rect2(Vector2(key) * DRAW_CHUNK_SIZE, Vector2.ONE * DRAW_CHUNK_SIZE)
				_chunk(key).shelves.append(shelf.intersection(clip))
	for chunk: Node2D in draw_chunks.values():
		chunk.queue_redraw()
	queue_redraw()

func _protected(bounds: Rect2) -> bool:
	return stage.get("protected_rects", []).any(func(rect): return rect.intersects(bounds))
func _cells_in(bounds: Rect2) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in range(floori(bounds.position.y / TILE_SIZE), ceili(bounds.end.y / TILE_SIZE)):
		for x in range(floori(bounds.position.x / TILE_SIZE), ceili(bounds.end.x / TILE_SIZE)):
			result.append(Vector2i(x, y))
	return result

func _chunk_key(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(cell.x * TILE_SIZE / float(DRAW_CHUNK_SIZE)), floori(cell.y * TILE_SIZE / float(DRAW_CHUNK_SIZE)))

func _set_row_cell(cell: Vector2i, layer: int, present: bool) -> void:
	var key := Vector2i(layer, cell.y)
	if not row_cells.has(key):
		row_cells[key] = {}
	if present:
		row_cells[key][cell.x] = true
	else:
		row_cells[key].erase(cell.x)

func _rebuild_row(key: Vector2i) -> void:
	if row_bodies.has(key):
		for body: StaticBody2D in row_bodies[key]:
			body.collision_layer = 0
			collision_root.remove_child(body)
			body.queue_free()
	row_bodies[key] = []
	var columns: Array = row_cells.get(key, {}).keys()
	columns.sort()
	var index := 0
	while index < columns.size():
		var first: int = columns[index]
		var last := first
		index += 1
		while index < columns.size() and columns[index] == last + 1:
			last = columns[index]
			index += 1
		row_bodies[key].append(_add_collision(Rect2(first * TILE_SIZE, key.y * TILE_SIZE, (last - first + 1) * TILE_SIZE, TILE_SIZE), key.x))

func _changed(cells: Array[Vector2i], layer: int) -> void:
	if cells.is_empty():
		return
	var rows := {}
	var neighbours := {}
	for cell: Vector2i in cells:
		rows[Vector2i(layer, cell.y)] = true
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				neighbours[cell + Vector2i(dx, dy)] = true
	for key: Vector2i in rows:
		_rebuild_row(key)
	for cell: Vector2i in neighbours:
		if occupied.has(cell):
			tile_masks[cell] = mask_for_cell(cell)
		else:
			tile_masks.erase(cell)
		_chunk(_chunk_key(cell)).queue_redraw()
	if layer == 1:
		revision += 1

func explode(center: Vector2, radius: float = T.BOMB_RADIUS) -> Array[Vector2i]:
	var removed: Array[Vector2i] = []
	# Only examine the small blast bounding box, independent of world size.
	for cell: Vector2i in _cells_in(Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2)):
		if (Vector2(cell) * TILE_SIZE + Vector2.ONE * TILE_SIZE / 2).distance_squared_to(center) > radius * radius:
			continue
		if surface_cells.has(cell) and occupied.has(cell):
			occupied.erase(cell)
			destroyed_cells[cell] = true
			_set_row_cell(cell, 1, false)
			removed.append(cell)
	var block_ids := breakables.keys()
	for id: int in block_ids:
		if breakables[id].bounds.get_center().distance_squared_to(center) <= radius * radius:
			_remove_block(id, removed)
	_changed(removed, 1)
	var removed_walls: Array[Vector2i] = []
	for cell: Vector2i in _cells_in(Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2)):
		if wall_cells.has(cell) and (Vector2(cell) * TILE_SIZE + Vector2.ONE * TILE_SIZE / 2).distance_squared_to(center) <= radius * radius:
			var id: int = wall_cells[cell]
			walls[id].cells.erase(cell)
			_erase_wall_cell(cell)
			removed_walls.append(cell)
	for id: int in walls.keys():
		if walls[id].cells.is_empty():
			walls.erase(id)
	_changed(removed_walls, T.WALL_LAYER)
	return removed

func _remove_block(id: int, removed: Array[Vector2i]) -> void:
	for cell: Vector2i in breakables[id].cells:
		occupied.erase(cell)
		block_cells.erase(cell)
		_set_row_cell(cell, 1, false)
		removed.append(cell)
	breakables.erase(id)

func damage_at(point: Vector2, damage: int) -> bool:
	var cell := Vector2i(floori(point.x / TILE_SIZE), floori(point.y / TILE_SIZE))
	if block_cells.has(cell):
		var id: int = block_cells[cell]
		breakables[id].hp -= damage
		if breakables[id].hp <= 0:
			var removed: Array[Vector2i] = []
			_remove_block(id, removed)
			_changed(removed, 1)
		return true
	if wall_cells.has(cell):
		var id: int = wall_cells[cell]
		walls[id].hp -= damage
		if walls[id].hp <= 0:
			remove_wall(id)
		return true
	return false

func is_cell_solid(cell: Vector2i, include_walls: bool = true) -> bool:
	if occupied.has(cell) or include_walls and wall_cells.has(cell):
		return true
	var area := Rect2(Vector2(cell) * TILE_SIZE, Vector2.ONE * TILE_SIZE)
	for solid: Rect2 in stage.get("solids", []):
		if solid.size.y <= 20 and area.intersects(solid):
			return true
	return false

func wall_count(owner_id: int) -> int:
	return walls.values().filter(func(wall): return wall.owner == owner_id).size()

func _actors_clear(bounds: Rect2) -> bool:
	for actor in get_tree().get_nodes_in_group("combatants"):
		if actor.dead or actor.is_queued_for_deletion() or actor.get_parent() != get_parent():
			continue
		var body: Rect2 = Rect2(actor.global_position - actor.body_size / 2, actor.body_size)
		if actor.faction == 0:
			body = body.grow(T.WALL_PLAYER_MARGIN)
		if bounds.intersects(body):
			return false
	return true

func can_place_wall(bounds: Rect2, owner_id: int) -> bool:
	if wall_count(owner_id) >= T.WALL_MAX_PER_OWNER or bounds.size.x != TILE_SIZE or bounds.size.y < T.WALL_MIN_HEIGHT or bounds.size.y > T.WALL_MAX_HEIGHT:
		return false
	for value in [bounds.position.x, bounds.position.y, bounds.size.y]:
		if fmod(value, TILE_SIZE) != 0:
			return false
	if not stage.bounds.encloses(bounds) or _protected(bounds) or not _actors_clear(bounds):
		return false
	for cell: Vector2i in _cells_in(bounds):
		if is_cell_solid(cell):
			return false
	var support := Vector2i(floori(bounds.position.x / TILE_SIZE), floori(bounds.end.y / TILE_SIZE))
	# Shelves and temporary walls cannot support another wall.
	if not occupied.has(support):
		return false
	return true

func find_wall_plan(builder: CharacterBody2D, player: CharacterBody2D) -> Rect2:
	var direction := signf(player.position.x - builder.position.x)
	var floor_y: float = builder.position.y + builder.body_size.y / 2
	var player_body := Rect2(player.position - player.body_size / 2, player.body_size)
	for distance in range(T.BUILD_MIN_CELLS, T.BUILD_MAX_CELLS + 1):
		var column := floori(builder.position.x / TILE_SIZE) + int(direction) * distance
		var left := float(column * TILE_SIZE)
		if direction > 0 and (left <= builder.position.x or left + TILE_SIZE > player_body.position.x - T.WALL_MIN_DISTANCE):
			continue
		if direction < 0 and (left + TILE_SIZE >= builder.position.x or left < player_body.end.x + T.WALL_MIN_DISTANCE):
			continue
		for row in range(floori((floor_y - T.BUILD_SUPPORT_RANGE) / TILE_SIZE), floori((floor_y + T.BUILD_SUPPORT_RANGE) / TILE_SIZE) + 1):
			if not occupied.has(Vector2i(column, row)):
				continue
			for height in [T.WALL_MAX_HEIGHT, T.WALL_MIN_HEIGHT]:
				var bounds := Rect2(left, row * TILE_SIZE - height, TILE_SIZE, height)
				if can_place_wall(bounds, builder.get_instance_id()):
					return bounds
			# Only the first solid upper face in the allowed height range is eligible.
			break
	return Rect2()

func confirm_wall_plan(bounds: Rect2, builder: CharacterBody2D, player: CharacterBody2D) -> bool:
	if not can_place_wall(bounds, builder.get_instance_id()):
		return false
	var floor_y: float = builder.position.y + builder.body_size.y / 2
	if absf(bounds.end.y - floor_y) > T.BUILD_SUPPORT_RANGE:
		return false
	var body := Rect2(player.position - player.body_size / 2, player.body_size)
	if builder.position.x < player.position.x:
		return bounds.position.x > builder.position.x and bounds.end.x <= body.position.x - T.WALL_MIN_DISTANCE
	return bounds.end.x < builder.position.x and bounds.position.x >= body.end.x + T.WALL_MIN_DISTANCE

func place_wall(bounds: Rect2, owner_id: int) -> int:
	if not can_place_wall(bounds, owner_id):
		return -1
	var id := next_wall_id
	next_wall_id += 1
	var cells := _cells_in(bounds)
	walls[id] = {"cells": cells, "owner": owner_id, "remaining": T.WALL_LIFETIME, "hp": T.TERRAIN_HP}
	for cell: Vector2i in cells:
		wall_cells[cell] = id
		_set_row_cell(cell, T.WALL_LAYER, true)
		_chunk(_chunk_key(cell)).walls.append(cell)
	_changed(cells, T.WALL_LAYER)
	return id

func _erase_wall_cell(cell: Vector2i) -> void:
	wall_cells.erase(cell)
	_set_row_cell(cell, T.WALL_LAYER, false)
	_chunk(_chunk_key(cell)).walls.erase(cell)

func remove_wall(id: int) -> void:
	if not walls.has(id):
		return
	var cells: Array[Vector2i] = walls[id].cells.duplicate()
	for cell: Vector2i in cells:
		_erase_wall_cell(cell)
	walls.erase(id)
	_changed(cells, T.WALL_LAYER)

func _physics_process(delta: float) -> void:
	for id: int in walls.keys():
		walls[id].remaining -= delta
		if walls[id].remaining <= 0:
			remove_wall(id)
		elif walls[id].remaining <= T.WALL_BLINK_TIME:
			for cell: Vector2i in walls[id].cells:
				_chunk(_chunk_key(cell)).queue_redraw()

func map_geometry(area: Rect2) -> Array[Rect2]:
	var fragments: Array[Rect2] = []
	for cell: Vector2i in _cells_in(area):
		if occupied.has(cell):
			fragments.append(area.intersection(Rect2(Vector2(cell) * TILE_SIZE, Vector2.ONE * TILE_SIZE)))
	for solid: Rect2 in stage.get("solids", []):
		if solid.size.y <= 20 and area.intersects(solid):
			fragments.append(area.intersection(solid))
	return fragments

func draw_wall(canvas: Node2D, cell: Vector2i) -> void:
	if not wall_cells.has(cell):
		return
	var wall: Dictionary = walls[wall_cells[cell]]
	var tint := Color("dbbd84")
	if wall.remaining <= T.WALL_BLINK_TIME and int(wall.remaining * 10) % 2 == 0:
		tint.a = 0.35
	var rect := Rect2(Vector2(cell) * TILE_SIZE - canvas.position + Vector2.ONE, Vector2.ONE * (TILE_SIZE - 2))
	canvas.draw_rect(rect, Color(tint, tint.a * 0.25))
	canvas.draw_rect(rect, tint, false, 2)
	canvas.draw_line(rect.position, rect.end, tint, 2)

func _chunk(key: Vector2i) -> DrawChunk:
	if not draw_chunks.has(key):
		var chunk := DrawChunk.new()
		chunk.terrain = self
		chunk.position = Vector2(key) * DRAW_CHUNK_SIZE
		render_root.add_child(chunk)
		draw_chunks[key] = chunk
	return draw_chunks[key]

func _add_collision(bounds: Rect2, layer: int = 1) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = T.PLATFORM_LAYER if bounds.size.y <= 20.0 else layer
	body.collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = bounds.size
	var collider := CollisionShape2D.new()
	collider.shape = shape
	collider.position = bounds.get_center()
	collider.one_way_collision = bounds.size.y <= 20.0
	collider.one_way_collision_margin = 4.0
	body.add_child(collider)
	collision_root.add_child(body)
	return body

func mask_for_cell(cell: Vector2i) -> int:
	if not occupied.has(cell):
		return 0
	var mask := 0
	var n: bool = occupied.has(cell + Vector2i.UP)
	var e: bool = occupied.has(cell + Vector2i.RIGHT)
	var s: bool = occupied.has(cell + Vector2i.DOWN)
	var w: bool = occupied.has(cell + Vector2i.LEFT)
	if n: mask |= NORTH
	if e: mask |= EAST
	if s: mask |= SOUTH
	if w: mask |= WEST
	# Diagonals join only when both bordering cardinal neighbours exist.
	if n and e and occupied.has(cell + Vector2i(1, -1)): mask |= NORTH_EAST
	if e and s and occupied.has(cell + Vector2i(1, 1)): mask |= SOUTH_EAST
	if s and w and occupied.has(cell + Vector2i(-1, 1)): mask |= SOUTH_WEST
	if w and n and occupied.has(cell + Vector2i(-1, -1)): mask |= NORTH_WEST
	return mask

static func regional_theme(point: Vector2, seed_value: int) -> Dictionary:
	var coord := Vector2i((point / T.SECTOR_SIZE).floor())
	var local := point - Vector2(coord) * T.SECTOR_SIZE
	var lo := coord
	var hi := coord
	var blend := Vector2.ZERO
	for axis in range(2):
		if local[axis] < T.REGION_BLEND_WIDTH:
			lo[axis] -= 1
			blend[axis] = smoothstep(-T.REGION_BLEND_WIDTH, T.REGION_BLEND_WIDTH, local[axis])
		elif local[axis] > T.SECTOR_SIZE[axis] - T.REGION_BLEND_WIDTH:
			hi[axis] += 1
			blend[axis] = smoothstep(T.SECTOR_SIZE[axis] - T.REGION_BLEND_WIDTH, T.SECTOR_SIZE[axis] + T.REGION_BLEND_WIDTH, local[axis])
	var sectors := preload("res://scripts/sector_generator.gd")
	if lo == hi: return THEMES[sectors.region_at(seed_value, lo)]
	var a: Dictionary = THEMES[sectors.region_at(seed_value, lo)]
	var b: Dictionary = THEMES[sectors.region_at(seed_value, Vector2i(hi.x, lo.y))]
	var c: Dictionary = THEMES[sectors.region_at(seed_value, Vector2i(lo.x, hi.y))]
	var d: Dictionary = THEMES[sectors.region_at(seed_value, hi)]
	var result := {}
	for key: String in a: result[key] = a[key].lerp(b[key], blend.x).lerp(c[key].lerp(d[key], blend.x), blend.y)
	return result

func theme_at(point: Vector2) -> Dictionary:
	if stage.has("seed"): return regional_theme(point, stage.seed)
	return theme_at_x(point.x)

func theme_at_x(x: float) -> Dictionary:
	return regional_theme(Vector2(x, 0), int(stage.get("seed", 0)))

func draw_tile(canvas: Node2D, cell: Vector2i, mask: int) -> void:
	var world_at := Vector2(cell) * TILE_SIZE
	var at := world_at - canvas.position
	var theme := theme_at(world_at + Vector2.ONE * TILE_SIZE / 2.0)
	canvas.draw_rect(Rect2(at, Vector2.ONE * TILE_SIZE), theme.body)
	if mask == 255 and not block_cells.has(cell): return
	canvas.draw_line(at + Vector2(0, 31), at + Vector2(32, 31), theme.shadow, 1.0)
	if (cell.x + cell.y) % 3 == 0:
		canvas.draw_line(at + Vector2(13, 12), at + Vector2(20, 12), theme.inner, 1.0)
	if not mask & NORTH:
		canvas.draw_rect(Rect2(at, Vector2(32, 7)), theme.inner)
		canvas.draw_line(at + Vector2(0, 1), at + Vector2(32, 1), theme.edge, 2.0)
	if not mask & EAST:
		canvas.draw_line(at + Vector2(31, 0), at + Vector2(31, 32), theme.accent, 2.0)
	if not mask & SOUTH:
		canvas.draw_line(at + Vector2(0, 31), at + Vector2(32, 31), theme.shadow, 3.0)
	if not mask & WEST:
		canvas.draw_line(at + Vector2(1, 0), at + Vector2(1, 32), theme.accent, 2.0)
	_draw_corner(canvas, at + Vector2(32, 0), Vector2(-1, 1), mask, NORTH, EAST, NORTH_EAST, theme)
	_draw_corner(canvas, at + Vector2(32, 32), Vector2(-1, -1), mask, EAST, SOUTH, SOUTH_EAST, theme)
	_draw_corner(canvas, at + Vector2(0, 32), Vector2(1, -1), mask, SOUTH, WEST, SOUTH_WEST, theme)
	_draw_corner(canvas, at, Vector2(1, 1), mask, WEST, NORTH, NORTH_WEST, theme)
	if block_cells.has(cell):
		canvas.draw_rect(Rect2(at + Vector2(3, 3), Vector2(26, 26)), Color("aa9474"), false, 2)
		canvas.draw_line(at + Vector2(8, 8), at + Vector2(24, 24), Color("aa9474"), 2)

func _draw_corner(canvas: Node2D, corner: Vector2, inward: Vector2, mask: int, a: int, b: int, diagonal: int, theme: Dictionary) -> void:
	if mask & a and mask & b and not mask & diagonal:
		var inset := corner + inward
		canvas.draw_line(inset, inset + Vector2(inward.x * 5, 0), theme.accent, 2.0)
		canvas.draw_line(inset, inset + Vector2(0, inward.y * 5), theme.accent, 2.0)
	elif not mask & a and not mask & b:
		canvas.draw_line(corner + Vector2(inward.x * 4, inward.y), corner + Vector2(inward.x, inward.y * 4), theme.edge, 2.0)

func draw_shelf(canvas: Node2D, world_shelf: Rect2) -> void:
	var shelf := Rect2(world_shelf.position - canvas.position, world_shelf.size)
	var theme := theme_at(world_shelf.get_center())
	canvas.draw_rect(shelf, theme.shadow)
	canvas.draw_rect(Rect2(shelf.position, Vector2(shelf.size.x, 5)), theme.inner)
	canvas.draw_line(shelf.position + Vector2(0, 1), Vector2(shelf.end.x, shelf.position.y + 1), theme.edge, 3.0)
	for x in range(int(shelf.position.x), int(shelf.end.x) - 24, TILE_SIZE):
		canvas.draw_line(Vector2(x + 16, shelf.position.y + 8), Vector2(x + 24, shelf.end.y - 2), theme.accent, 1.0)
