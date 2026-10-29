extends "res://scripts/world_terrain.gd"
## One world-facing API; sector geometry is installed incrementally, never rebuilt on travel.
const Job := preload("res://scripts/sector_job.gd")
const O := preload("res://scripts/origin_shift.gd")
var sectors: Dictionary = {}
var building: Dictionary = {}
var next_block_id := 0
var pending_redraw: Dictionary = {} # Stable integer chunk keys, including across origin shifts.
var redraw_buckets: Dictionary = {} # bucket -> dictionary of pending integer chunk keys.
var draw_cost_ms := T.STREAM_DRAW_INITIAL_COST_MS
var redraw_service_ms := 0.0
var redraw_estimated_ms := 0.0
var reserved_draw_ms := 0.0
var idle_draw_deferred := false
var origin_sector := Vector2i.ZERO
var collision_sectors: Dictionary = {}

func collision_body_count() -> int:
	var count := 0
	for parent: Node2D in collision_sectors.values(): count += parent.get_child_count()
	return count

func _add_collision(bounds: Rect2, layer: int = 1) -> StaticBody2D:
	var at := origin_sector + Vector2i((bounds.position / T.SECTOR_SIZE).floor())
	if not collision_sectors.has(at):
		var parent := Node2D.new()
		parent.position = sector_offset(at)
		collision_root.add_child(parent)
		collision_sectors[at] = parent
	var parent: Node2D = collision_sectors[at]
	var body := super._add_collision(Rect2(bounds.position-parent.position,bounds.size), layer)
	body.reparent(parent, false)
	return body

func sector_offset(at: Vector2i) -> Vector2:
	return O.offset(at, origin_sector)

func shift_origin(delta: Vector2, new_origin: Vector2i) -> void:
	origin_sector = new_origin
	for block: Dictionary in breakables.values():
		block.bounds.position += delta
	# Move the existing bodies. Rebuilding would discard contacts and one-way state.
	for parent: Node2D in collision_sectors.values():
		parent.position += delta
		parent.force_update_transform()
		parent.reset_physics_interpolation()
		for body: StaticBody2D in parent.get_children():
			body.force_update_transform()
			body.reset_physics_interpolation()
	for chunk: Node2D in draw_chunks.values():
		chunk.position += delta
		chunk.shelves.assign(O.geometry(chunk.shelves, delta))
		# Its drawing commands are chunk-local and remain identical. Redrawing
		# every retained tile here would undo the stream's per-frame draw budget.
	revision += 1

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
						_chunk(Vector2i(x, y)+chunk_origin()).shelves.append(shelf.intersection(Rect2(Vector2(x, y) * DRAW_CHUNK_SIZE, Vector2.ONE * DRAW_CHUNK_SIZE)))
			else: _next_phase()
		4:
			for j in range(i, mini(i + 64, p.occupied.size())):
				var cell: Vector2i = p.occupied[j]
				tile_masks[cell] = mask_for_cell(cell)
			building.index += 63
			if i + 64 >= p.occupied.size():
				_refresh_border(p.data.coord)
				_next_phase()
		5:
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
	var origin := at * Vector2i(T.SECTOR_SIZE / TILE_SIZE)
	var size := Vector2i(T.SECTOR_SIZE / TILE_SIZE)
	for y in range(origin.y - 1, origin.y + size.y + 1):
		for x in [origin.x - 1, origin.x, origin.x + size.x - 1, origin.x + size.x]: _refresh_cell(Vector2i(x, y))
	for x in range(origin.x - 1, origin.x + size.x + 1):
		for y in [origin.y - 1, origin.y, origin.y + size.y - 1, origin.y + size.y]: _refresh_cell(Vector2i(x, y))
	for key: Vector2i in draw_chunks:
		if Rect2(sector_offset(at), T.SECTOR_SIZE).grow(DRAW_CHUNK_SIZE).intersects(Rect2(pixel_of_chunk(key), Vector2.ONE * DRAW_CHUNK_SIZE)):
			keys.append(key)
			if redraw: request_chunk_redraw(key)
	return keys

func _refresh_cell(cell: Vector2i) -> void:
	if occupied.has(cell): tile_masks[cell] = mask_for_cell(cell)

func snapshot(at: Vector2i) -> Dictionary:
	var sector: Dictionary = sectors[at]
	var saved := {"destroyed": {}, "blocks": {}}
	for cell: Vector2i in sector.surfaces:
		if destroyed_cells.has(cell): saved.destroyed[cell-cell_origin()] = true
	for rect: Rect2 in sector.data.breakables: saved.blocks[rect.position] = 0
	for id: int in sector.blocks:
		if breakables.has(id): saved.blocks[breakables[id].bounds.position] = breakables[id].hp
	return saved

func restore_block(at: Vector2i, rect: Rect2) -> void:
	var id := next_block_id
	next_block_id += 1
	var cells := _cells_in(rect)
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
		if walls[id].cells.any(func(cell): return Rect2(sector_offset(at), T.SECTOR_SIZE).has_point(pixel_of_cell(cell))): remove_wall(id)
	for body: Node2D in sector.bodies:
		body.collision_layer = 0
		body.free()
	for key: Vector2i in rows:
		_rebuild_row(key)
		if row_cells[key].is_empty():
			row_cells.erase(key)
			row_bodies.erase(key)
	for key: Vector2i in collision_sectors.keys():
		if collision_sectors[key].get_child_count() == 0:
			collision_sectors[key].free()
			collision_sectors.erase(key)
	var bounds := Rect2(sector_offset(at), T.SECTOR_SIZE)
	for key: Vector2i in draw_chunks.keys():
		if bounds.has_point(pixel_of_chunk(key)):
			draw_chunks[key].free()
			draw_chunks.erase(key)
			_erase_pending(key)
	sectors.erase(at)
	_refresh_border(at)
	revision += 1

func configure_chunk(chunk: DrawChunk) -> void:
	# CanvasItem schedules a first draw on tree entry, even outside the camera.
	# Hide BEFORE adding it; show only when the redraw scheduler selects it.
	chunk.hide()
	_queue_pending(chunk.key)

func request_chunk_redraw(key: Vector2i) -> void:
	var chunk := _chunk(key)
	chunk.change_version += 1
	_queue_pending(key)

func _redraw_bucket(key: Vector2i) -> Vector2i:
	return Vector2i(floori(float(key.x) / T.STREAM_DRAW_BUCKET_SIZE.x), floori(float(key.y) / T.STREAM_DRAW_BUCKET_SIZE.y))

func _queue_pending(key: Vector2i) -> void:
	if pending_redraw.has(key): return
	pending_redraw[key] = true
	var bucket := _redraw_bucket(key)
	if not redraw_buckets.has(bucket): redraw_buckets[bucket] = {}
	redraw_buckets[bucket][key] = true

func _erase_pending(key: Vector2i) -> void:
	pending_redraw.erase(key)
	var bucket := _redraw_bucket(key)
	if not redraw_buckets.has(bucket): return
	redraw_buckets[bucket].erase(key)
	if redraw_buckets[bucket].is_empty(): redraw_buckets.erase(bucket)

func _nearest_pending(priority: Vector2) -> Vector2i:
	# Approximate order: nearest nonempty bucket center, then nearest chunk.
	# At 25 loaded sectors inspect <=25 buckets + <=48 keys, never all 1,200.
	var point := priority / DRAW_CHUNK_SIZE + Vector2(chunk_origin())
	var nearest_bucket := Vector2i.ZERO
	var distance := INF
	for bucket: Vector2i in redraw_buckets:
		var score := (Vector2(bucket * T.STREAM_DRAW_BUCKET_SIZE) + Vector2(T.STREAM_DRAW_BUCKET_SIZE) / 2).distance_squared_to(point)
		if score < distance:
			distance = score
			nearest_bucket = bucket
	var nearest := Vector2i.ZERO
	distance = INF
	for key: Vector2i in redraw_buckets[nearest_bucket]:
		var score := (Vector2(key) + Vector2.ONE / 2).distance_squared_to(point)
		if score < distance:
			distance = score
			nearest = key
	return nearest

func chunk_draw_finished(milliseconds: float) -> void:
	draw_cost_ms = lerpf(draw_cost_ms, milliseconds, T.STREAM_DRAW_COST_SMOOTHING)

func _submit_chunk(key: Vector2i) -> void:
	var chunk: DrawChunk = draw_chunks[key]
	chunk.show()
	chunk.queue_redraw()
	chunk.submitted_version = chunk.change_version
	_erase_pending(key)
	reserved_draw_ms += maxf(T.STREAM_DRAW_MIN_COST_MS, draw_cost_ms)

func _view_keys(area: Rect2) -> Array[Vector2i]:
	var keys: Array[Vector2i] = []
	var first := Vector2i((area.position / DRAW_CHUNK_SIZE).floor()) + chunk_origin()
	var last := Vector2i((area.end / DRAW_CHUNK_SIZE).ceil()) + chunk_origin()
	for y in range(first.y, last.y):
		for x in range(first.x, last.x): keys.append(Vector2i(x, y))
	return keys

func prepare_view(area: Rect2) -> void:
	# Mandatory work is never charged against the optional offscreen limit.
	for key: Vector2i in _view_keys(area):
		if pending_redraw.has(key): _submit_chunk(key)

func view_is_current(area: Rect2, rendered: bool = false) -> bool:
	for key: Vector2i in _view_keys(area):
		if not draw_chunks.has(key): continue # A wholly empty chunk needs no commands.
		var chunk: DrawChunk = draw_chunks[key]
		if pending_redraw.has(key) or not chunk.visible: return false
		if (chunk.drawn_version if rendered else chunk.submitted_version) != chunk.change_version: return false
	return true

func service_redraw(area: Rect2, priority: Vector2, budget_ms: float = T.STREAM_DRAW_BUDGET_MS, service_did_work: bool = false) -> void:
	var began := Time.get_ticks_usec()
	prepare_view(area)
	var estimated_ms := reserved_draw_ms
	var count := 0
	# Polling service() costs time even with no work. Use the explicit work
	# flag, never budget equality, to grant an indivisible idle draw.
	var idle_allowance := not service_did_work and estimated_ms == 0.0
	while not pending_redraw.is_empty() and count < T.STREAM_DRAW_CHUNKS_PER_FRAME:
		var cost := maxf(T.STREAM_DRAW_MIN_COST_MS, draw_cost_ms)
		if not (idle_allowance and count == 0) and estimated_ms + cost > budget_ms: break
		_submit_chunk(_nearest_pending(priority))
		estimated_ms += cost
		count += 1
	# Queue management is measured, but cannot veto an admitted draw.
	redraw_service_ms = (Time.get_ticks_usec() - began) / 1000.0
	redraw_estimated_ms = estimated_ms
	reserved_draw_ms = 0.0
	idle_draw_deferred = false

func is_cell_solid(cell: Vector2i, include_walls: bool = true) -> bool:
	if occupied.has(cell) or include_walls and wall_cells.has(cell): return true
	var at := Vector2i(floori(cell.x * TILE_SIZE / T.SECTOR_SIZE.x), floori(cell.y * TILE_SIZE / T.SECTOR_SIZE.y))
	if not sectors.has(at): return false
	var area := Rect2(pixel_of_cell(cell), Vector2.ONE * TILE_SIZE)
	return sectors[at].data.solids.any(func(r): return r.size.y == 16 and area.intersects(r))

func map_geometry(area: Rect2) -> Array[Rect2]:
	var fragments: Array[Rect2] = []
	for cell: Vector2i in _cells_in(area):
		if occupied.has(cell): fragments.append(area.intersection(Rect2(pixel_of_cell(cell), Vector2.ONE * TILE_SIZE)))
	var at := origin_sector + Vector2i(floori(area.get_center().x / T.SECTOR_SIZE.x), floori(area.get_center().y / T.SECTOR_SIZE.y))
	if sectors.has(at):
		for solid: Rect2 in sectors[at].data.solids:
			if solid.size.y == 16 and area.intersects(solid): fragments.append(area.intersection(solid))
	return fragments
