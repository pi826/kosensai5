extends Node2D
## One collision world. Rendering is split into spatial batches for canvas culling.

const T := preload("res://scripts/tuning.gd")
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
	func _draw() -> void:
		for cell in cells:
			terrain.draw_tile(self, cell, terrain.tile_masks[cell])
		for shelf in shelves:
			terrain.draw_shelf(self, shelf)

var stage: Dictionary = {}
var tile_masks: Dictionary = {}
var occupied: Dictionary = {}
var collision_root: Node2D
var render_root: Node2D
var draw_chunks: Dictionary = {}

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
	collision_root = Node2D.new()
	collision_root.name = "Collision"
	add_child(collision_root)
	render_root = Node2D.new()
	render_root.name = "TileBatches"
	add_child(render_root)
	var shelves: Array[Rect2] = []
	for bounds: Rect2 in stage.get("solids", []):
		if bounds.size.x <= 0 or bounds.size.y <= 0:
			continue
		_add_collision(bounds)
		if bounds.size.y <= 20.0:
			shelves.append(bounds)
			continue
		for y in range(floori(bounds.position.y / TILE_SIZE), ceili(bounds.end.y / TILE_SIZE)):
			for x in range(floori(bounds.position.x / TILE_SIZE), ceili(bounds.end.x / TILE_SIZE)):
				occupied[Vector2i(x, y)] = true
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

func _chunk(key: Vector2i) -> DrawChunk:
	if not draw_chunks.has(key):
		var chunk := DrawChunk.new()
		chunk.terrain = self
		chunk.position = Vector2(key) * DRAW_CHUNK_SIZE
		render_root.add_child(chunk)
		draw_chunks[key] = chunk
	return draw_chunks[key]

func _add_collision(bounds: Rect2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
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

func theme_at_x(x: float) -> Dictionary:
	var bounds: Rect2 = stage.get("bounds", Rect2(0, 0, 12288, 3072))
	var width := bounds.size.x / 3.0
	var region := clampi(floori((x - bounds.position.x) / width), 0, 2)
	var theme: Dictionary = THEMES[region].duplicate()
	# The terrain palette follows the same soft boundary as the backdrop.
	for boundary in [1, 2]:
		var at: float = bounds.position.x + width * int(boundary)
		if absf(x - at) < 256.0:
			var mix := smoothstep(at - 256.0, at + 256.0, x)
			for key: String in theme:
				theme[key] = THEMES[boundary - 1][key].lerp(THEMES[boundary][key], mix)
	return theme

func draw_tile(canvas: Node2D, cell: Vector2i, mask: int) -> void:
	var world_at := Vector2(cell) * TILE_SIZE
	var at := world_at - canvas.position
	var theme := theme_at_x(world_at.x + TILE_SIZE / 2.0)
	canvas.draw_rect(Rect2(at, Vector2.ONE * TILE_SIZE), theme.body)
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

func _draw_corner(canvas: Node2D, corner: Vector2, inward: Vector2, mask: int, a: int, b: int, diagonal: int, theme: Dictionary) -> void:
	if mask & a and mask & b and not mask & diagonal:
		var inset := corner + inward
		canvas.draw_line(inset, inset + Vector2(inward.x * 5, 0), theme.accent, 2.0)
		canvas.draw_line(inset, inset + Vector2(0, inward.y * 5), theme.accent, 2.0)
	elif not mask & a and not mask & b:
		canvas.draw_line(corner + Vector2(inward.x * 4, inward.y), corner + Vector2(inward.x, inward.y * 4), theme.edge, 2.0)

func draw_shelf(canvas: Node2D, world_shelf: Rect2) -> void:
	var shelf := Rect2(world_shelf.position - canvas.position, world_shelf.size)
	var theme := theme_at_x(world_shelf.get_center().x)
	canvas.draw_rect(shelf, theme.shadow)
	canvas.draw_rect(Rect2(shelf.position, Vector2(shelf.size.x, 5)), theme.inner)
	canvas.draw_line(shelf.position + Vector2(0, 1), Vector2(shelf.end.x, shelf.position.y + 1), theme.edge, 3.0)
	for x in range(int(shelf.position.x), int(shelf.end.x) - 24, TILE_SIZE):
		canvas.draw_line(Vector2(x + 16, shelf.position.y + 8), Vector2(x + 24, shelf.end.y - 2), theme.accent, 1.0)
