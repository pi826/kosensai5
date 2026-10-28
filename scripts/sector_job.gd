extends RefCounted
## Worker owns every object here until its task has completed. No SceneTree access.
const S := preload("res://scripts/sector_generator.gd")
const G := preload("res://scripts/stage_generator.gd")
const T := preload("res://scripts/tuning.gd")
const O := preload("res://scripts/origin_shift.gd")
var origin := Vector2i.ZERO
var seed_value: int
var coord: Vector2i
var saved: Dictionary = {}
var result: Dictionary = {}
var task_id := -1
var generation_ms := 0.0

static func world_data(local: Dictionary, origin_at: Vector2i = Vector2i.ZERO) -> Dictionary:
	var offset := O.offset(local.coord, origin_at)
	var data: Dictionary = _translate(local, offset)
	data.coord = local.coord
	data.gates = {}
	for side: Vector2i in S.SIDES: data.gates[side] = S.boundary_gates(local.seed, local.coord, side, origin_at)
	for i in range(data.spawns.size()):
		data.spawns[i].id = "%d,%d:%s" % [local.coord.x, local.coord.y, local.spawns[i].id]
		data.spawns[i].patrol = local.spawns[i].patrol + Vector2.ONE * offset.x
		data.spawns[i].sector = local.coord
	data.navigation_bounds = [data.bounds]
	for h: Dictionary in data.hearts:
		h.id = "%d,%d:%s" % [local.coord.x, local.coord.y, h.id]
		h.sector = local.coord
	for item: Dictionary in data.get("loot", []):
		item.id = "%d,%d:%s" % [local.coord.x, local.coord.y, item.id]
		item.sector = local.coord
	for item: Dictionary in data.get("merchants", []):
		item.id = "%d,%d:%s" % [local.coord.x, local.coord.y, item.id]
		item.sector = local.coord
	return data

static func _translate(value, offset: Vector2):
	if value is Rect2: return Rect2(value.position + offset, value.size)
	if value is Vector2: return value + offset
	if value is Array:
		var out: Array = []
		for item in value: out.append(_translate(item, offset))
		return out
	if value is Dictionary:
		var out := {}
		for key in value: out[key] = _translate(value[key], offset)
		return out
	return value

func run() -> void:
	var begin := Time.get_ticks_usec()
	var local := S.generate(seed_value, coord)
	generation_ms = (Time.get_ticks_usec() - begin) / 1000.0
	var data := world_data(local, origin)
	saved = O.snapshot(saved, O.offset(coord, origin))
	var occupied := {}
	var surfaces := {}
	var shelves: Array = []
	for rect: Rect2 in data.solids:
		if rect.size.y == 16:
			shelves.append(rect)
		else:
			for cell: Vector2i in cells(rect): occupied[cell] = true
	for rect: Rect2 in data.erodible_surfaces:
		for cell: Vector2i in cells(rect):
			if occupied.has(cell) and not data.protected_rects.any(func(r): return r.intersects(Rect2(Vector2(cell) * T.TILE_SIZE, Vector2.ONE * T.TILE_SIZE))):
				surfaces[cell] = true
	var destroyed: Dictionary = saved.get("destroyed", {})
	for cell: Vector2i in destroyed: occupied.erase(cell)
	var blocks: Array = []
	var block_hp: Dictionary = saved.get("blocks", {})
	for rect: Rect2 in data.breakables:
		var hp: int = block_hp.get(rect.position, T.TERRAIN_HP)
		if hp <= 0: continue
		var block_cells := cells(rect)
		blocks.append({"bounds": rect, "cells": block_cells, "hp": hp})
		for cell: Vector2i in block_cells: occupied[cell] = true
	# Cell identities stay integer world keys. Only pixels sent to the scene
	# are relative to this job's origin.
	var grid_origin := origin * Vector2i(T.SECTOR_SIZE / T.TILE_SIZE)
	for block: Dictionary in blocks: block.cells = O.cells(block.cells, grid_origin)
	result = {"data": data, "occupied": O.cells(occupied.keys(), grid_origin), "surfaces": O.keyed(surfaces, grid_origin), "destroyed": O.keyed(destroyed, grid_origin),
		"blocks": blocks, "shelves": shelves, "collisions": G.subtract_rects(data.solids, data.erodible_surfaces), "population_data":local}

static func cells(rect: Rect2) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(floori(rect.position.y / T.TILE_SIZE), ceili(rect.end.y / T.TILE_SIZE)):
		for x in range(floori(rect.position.x / T.TILE_SIZE), ceili(rect.end.x / T.TILE_SIZE)): out.append(Vector2i(x, y))
	return out
