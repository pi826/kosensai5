extends "res://scripts/world_terrain.gd"
## One world-facing API; sector geometry is installed incrementally, never rebuilt on travel.
const Job := preload("res://scripts/sector_job.gd")
var sectors: Dictionary = {}
var building: Dictionary = {}
var next_block_id := 0
var pending_redraw: Array[Vector2i] = []

func _ready() -> void:
	z_index = -2
	collision_root = Node2D.new()
	collision_root.name = "Collision"
	add_child(collision_root)
	render_root = Node2D.new()
	render_root.name = "TileBatches"
	add_child(render_root)

func begin_sector(payload: Dictionary) -> void:
	assert(building.is_empty())
	building = {"payload": payload, "phase": 0, "index": 0, "bodies": [], "rows": {}, "blocks": []}
	for block: Dictionary in payload.blocks:
		var id := next_block_id
		next_block_id += 1
		breakables[id] = block
		building.blocks.append(id)
		for cell: Vector2i in block.cells:
			block_cells[cell] = id
			_set_row_cell(cell, 1, true)
			building.rows[Vector2i(1, cell.y)] = true
	for cell: Vector2i in payload.surfaces:
		surface_cells[cell] = true
		if payload.destroyed.has(cell): destroyed_cells[cell] = true
		else: _set_row_cell(cell, 1, true)
		building.rows[Vector2i(1, cell.y)] = true
	building.row_keys = building.rows.keys()

# Each unit is small (one collider, one row or 64 cells). Caller enforces a wall-time budget.
func build_step() -> bool:
	var p: Dictionary = building.payload
	var i: int = building.index
	match int(building.phase):
		0:
			if i < p.collisions.size(): building.bodies.append(_add_collision(p.collisions[i]))
			else: _next_phase()
		1:
			for j in range(i, mini(i + 64, p.occupied.size())):
				var cell: Vector2i = p.occupied[j]
				occupied[cell] = true
				_chunk(_chunk_key(cell)).cells.append(cell)
			building.index += 63
			if i + 64 >= p.occupied.size(): _next_phase()
		2:
			if i < building.row_keys.size(): _rebuild_row(building.row_keys[i])
			else: _next_phase()
		3:
			if i < p.shelves.size():
				var shelf: Rect2 = p.shelves[i]
				for y in range(floori(shelf.position.y / DRAW_CHUNK_SIZE), ceili(shelf.end.y / DRAW_CHUNK_SIZE)):
					for x in range(floori(shelf.position.x / DRAW_CHUNK_SIZE), ceili(shelf.end.x / DRAW_CHUNK_SIZE)):
						_chunk(Vector2i(x, y)).shelves.append(shelf.intersection(Rect2(Vector2(x, y) * DRAW_CHUNK_SIZE, Vector2.ONE * DRAW_CHUNK_SIZE)))
			else: _next_phase()
		4:
			for j in range(i, mini(i + 64, p.occupied.size())):
				var cell: Vector2i = p.occupied[j]
				tile_masks[cell] = mask_for_cell(cell)
			building.index += 63
			if i + 64 >= p.occupied.size():
				building.draw_keys = _refresh_border(p.data.coord,false)
				_next_phase()
		5:
			if i < building.draw_keys.size():
				var key: Vector2i = building.draw_keys[i]
				if draw_chunks.has(key): draw_chunks[key].queue_redraw()
			else:
				var at: Vector2i = p.data.coord
				sectors[at] = {"data": p.data, "cells": p.occupied, "bodies": building.bodies, "blocks": building.blocks, "surfaces": p.surfaces}
				building = {}
				revision += 1
				return true
	building.index += 1
	return false

func _next_phase() -> void:
	building.phase += 1
	building.index = -1

func _refresh_border(at: Vector2i, redraw: bool = true) -> Array[Vector2i]:
	var keys: Array[Vector2i] = []
	var origin := Vector2i(Vector2(at) * T.SECTOR_SIZE / TILE_SIZE)
	var size := Vector2i(T.SECTOR_SIZE / TILE_SIZE)
	for y in range(origin.y - 1, origin.y + size.y + 1):
		for x in [origin.x - 1, origin.x, origin.x + size.x - 1, origin.x + size.x]: _refresh_cell(Vector2i(x, y))
	for x in range(origin.x - 1, origin.x + size.x + 1):
		for y in [origin.y - 1, origin.y, origin.y + size.y - 1, origin.y + size.y]: _refresh_cell(Vector2i(x, y))
	for key: Vector2i in draw_chunks:
		if Rect2(Vector2(at) * T.SECTOR_SIZE, T.SECTOR_SIZE).grow(DRAW_CHUNK_SIZE).intersects(Rect2(Vector2(key) * DRAW_CHUNK_SIZE, Vector2.ONE * DRAW_CHUNK_SIZE)):
			keys.append(key)
			if redraw: draw_chunks[key].queue_redraw()
	return keys

func _refresh_cell(cell: Vector2i) -> void:
	if occupied.has(cell): tile_masks[cell] = mask_for_cell(cell)

func snapshot(at: Vector2i) -> Dictionary:
	var sector: Dictionary = sectors[at]
	var saved := {"destroyed": {}, "blocks": {}}
	for cell: Vector2i in sector.surfaces:
		if destroyed_cells.has(cell): saved.destroyed[cell] = true
	for rect: Rect2 in sector.data.breakables: saved.blocks[rect.position] = 0
	for id: int in sector.blocks:
		if breakables.has(id): saved.blocks[breakables[id].bounds.position] = breakables[id].hp
	return saved

func restore_block(at: Vector2i, rect: Rect2) -> void:
	var id := next_block_id
	next_block_id += 1
	var cells := Job.cells(rect)
	breakables[id] = {"bounds": rect, "cells": cells, "hp": T.TERRAIN_HP}
	sectors[at].blocks.append(id)
	for cell: Vector2i in cells:
		occupied[cell] = true
		if not sectors[at].cells.has(cell): sectors[at].cells.append(cell)
		block_cells[cell] = id
		_set_row_cell(cell, 1, true)
		var chunk := _chunk(_chunk_key(cell))
		if not chunk.cells.has(cell): chunk.cells.append(cell)
	_changed(cells, 1)

func unload(at: Vector2i) -> void:
	var sector: Dictionary = sectors[at]
	var rows := {}
	for cell: Vector2i in sector.cells:
		occupied.erase(cell)
		tile_masks.erase(cell)
		block_cells.erase(cell)
	for id: int in sector.blocks:
		if not breakables.has(id): continue
		for cell: Vector2i in breakables[id].cells:
			_set_row_cell(cell,1,false)
			rows[Vector2i(1,cell.y)] = true
	for cell: Vector2i in sector.surfaces:
		_set_row_cell(cell, 1, false)
		surface_cells.erase(cell)
		destroyed_cells.erase(cell)
		rows[Vector2i(1, cell.y)] = true
	for id: int in sector.blocks: breakables.erase(id)
	for id: int in walls.keys():
		if walls[id].cells.any(func(cell): return Rect2(Vector2(at) * T.SECTOR_SIZE, T.SECTOR_SIZE).has_point(Vector2(cell) * TILE_SIZE)): remove_wall(id)
	for body: Node2D in sector.bodies:
		body.collision_layer = 0
		body.free()
	for key: Vector2i in rows:
		_rebuild_row(key)
		if row_cells[key].is_empty():
			row_cells.erase(key)
			row_bodies.erase(key)
	var bounds := Rect2(Vector2(at) * T.SECTOR_SIZE, T.SECTOR_SIZE)
	for key: Vector2i in draw_chunks.keys():
		if bounds.has_point(Vector2(key) * DRAW_CHUNK_SIZE):
			draw_chunks[key].free()
			draw_chunks.erase(key)
	sectors.erase(at)
	for key: Vector2i in _refresh_border(at,false):
		if not pending_redraw.has(key): pending_redraw.append(key)
	revision += 1

func is_cell_solid(cell: Vector2i, include_walls: bool = true) -> bool:
	if occupied.has(cell) or include_walls and wall_cells.has(cell): return true
	var at := Vector2i(floori(cell.x * TILE_SIZE / T.SECTOR_SIZE.x), floori(cell.y * TILE_SIZE / T.SECTOR_SIZE.y))
	if not sectors.has(at): return false
	var area := Rect2(Vector2(cell) * TILE_SIZE, Vector2.ONE * TILE_SIZE)
	return sectors[at].data.solids.any(func(r): return r.size.y == 16 and area.intersects(r))

func map_geometry(area: Rect2) -> Array[Rect2]:
	var fragments: Array[Rect2] = []
	for cell: Vector2i in _cells_in(area):
		if occupied.has(cell): fragments.append(area.intersection(Rect2(Vector2(cell) * TILE_SIZE, Vector2.ONE * TILE_SIZE)))
	var at := Vector2i(floori(area.get_center().x / T.SECTOR_SIZE.x), floori(area.get_center().y / T.SECTOR_SIZE.y))
	if sectors.has(at):
		for solid: Rect2 in sectors[at].data.solids:
			if solid.size.y == 16 and area.intersects(solid): fragments.append(area.intersection(solid))
	return fragments
