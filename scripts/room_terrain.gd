extends Node2D
## Collision uses merged rectangles; the placeholder artwork connects on a 32 px grid.

const TILE_SIZE := 32
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

var room: Dictionary = {}
var tile_masks: Dictionary = {}
var _occupied: Dictionary = {}
var _shelves: Array[Rect2] = []

func _ready() -> void:
	z_index = -2
	rebuild()

func rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_occupied.clear()
	tile_masks.clear()
	_shelves.clear()
	for bounds: Rect2 in room.get("solids", []):
		if bounds.size.x <= 0 or bounds.size.y <= 0:
			continue
		_add_collision(bounds)
		if bounds.size.y <= 20.0:
			_shelves.append(bounds)
			continue
		for y in range(floori(bounds.position.y / TILE_SIZE), ceili(bounds.end.y / TILE_SIZE)):
			for x in range(floori(bounds.position.x / TILE_SIZE), ceili(bounds.end.x / TILE_SIZE)):
				_occupied[Vector2i(x, y)] = true
	for cell: Vector2i in _occupied:
		tile_masks[cell] = mask_for_cell(cell)
	queue_redraw()

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
	add_child(body)

func mask_for_cell(cell: Vector2i) -> int:
	if not _occupied.has(cell):
		return 0
	var mask := 0
	var n: bool = _occupied.has(cell + Vector2i.UP)
	var e: bool = _occupied.has(cell + Vector2i.RIGHT)
	var s: bool = _occupied.has(cell + Vector2i.DOWN)
	var w: bool = _occupied.has(cell + Vector2i.LEFT)
	if n:
		mask |= NORTH
	if e:
		mask |= EAST
	if s:
		mask |= SOUTH
	if w:
		mask |= WEST
	# A diagonal only joins when both bordering cardinal neighbours also exist.
	if n and e and _occupied.has(cell + Vector2i(1, -1)):
		mask |= NORTH_EAST
	if e and s and _occupied.has(cell + Vector2i(1, 1)):
		mask |= SOUTH_EAST
	if s and w and _occupied.has(cell + Vector2i(-1, 1)):
		mask |= SOUTH_WEST
	if w and n and _occupied.has(cell + Vector2i(-1, -1)):
		mask |= NORTH_WEST
	return mask

func _draw() -> void:
	var theme: Dictionary = THEMES[clampi(int(room.get("biome", 0)), 0, 2)]
	for cell: Vector2i in tile_masks:
		_draw_tile(cell, int(tile_masks[cell]), theme)
	for shelf: Rect2 in _shelves:
		_draw_shelf(shelf, theme)

func _draw_tile(cell: Vector2i, mask: int, theme: Dictionary) -> void:
	var at := Vector2(cell) * TILE_SIZE
	var box := Rect2(at, Vector2.ONE * TILE_SIZE)
	draw_rect(box, theme.body)
	# Subtle masonry remains visible in filled areas without competing with bullets.
	draw_line(at + Vector2(0, 31), at + Vector2(32, 31), theme.shadow, 1.0)
	if (cell.x + cell.y) % 3 == 0:
		draw_line(at + Vector2(13, 12), at + Vector2(20, 12), theme.inner, 1.0)
	if not mask & NORTH:
		draw_rect(Rect2(at, Vector2(32, 7)), theme.inner)
		draw_line(at + Vector2(0, 1), at + Vector2(32, 1), theme.edge, 2.0)
	if not mask & EAST:
		draw_line(at + Vector2(31, 0), at + Vector2(31, 32), theme.accent, 2.0)
	if not mask & SOUTH:
		draw_line(at + Vector2(0, 31), at + Vector2(32, 31), theme.shadow, 3.0)
	if not mask & WEST:
		draw_line(at + Vector2(1, 0), at + Vector2(1, 32), theme.accent, 2.0)
	# Missing diagonal neighbours expose a concave corner, even when both edges join.
	_draw_corner(at + Vector2(32, 0), Vector2(-1, 1), mask, NORTH, EAST, NORTH_EAST, theme)
	_draw_corner(at + Vector2(32, 32), Vector2(-1, -1), mask, EAST, SOUTH, SOUTH_EAST, theme)
	_draw_corner(at + Vector2(0, 32), Vector2(1, -1), mask, SOUTH, WEST, SOUTH_WEST, theme)
	_draw_corner(at, Vector2(1, 1), mask, WEST, NORTH, NORTH_WEST, theme)

func _draw_corner(corner: Vector2, inward: Vector2, mask: int, a: int, b: int, diagonal: int, theme: Dictionary) -> void:
	if mask & a and mask & b and not mask & diagonal:
		var inset := corner + inward
		draw_line(inset, inset + Vector2(inward.x * 5, 0), theme.accent, 2.0)
		draw_line(inset, inset + Vector2(0, inward.y * 5), theme.accent, 2.0)
	elif not mask & a and not mask & b:
		# A small bevel marks the exposed outer corner on the grid.
		draw_line(corner + Vector2(inward.x * 4, inward.y), corner + Vector2(inward.x, inward.y * 4), theme.edge, 2.0)

func _draw_shelf(shelf: Rect2, theme: Dictionary) -> void:
	draw_rect(shelf, theme.shadow)
	draw_rect(Rect2(shelf.position, Vector2(shelf.size.x, 5)), theme.inner)
	draw_line(shelf.position + Vector2(0, 1), Vector2(shelf.end.x, shelf.position.y + 1), theme.edge, 3.0)
	for x in range(int(shelf.position.x), int(shelf.end.x), TILE_SIZE):
		draw_line(Vector2(x + 16, shelf.position.y + 8), Vector2(x + 24, shelf.end.y - 2), theme.accent, 1.0)
	draw_line(shelf.position, Vector2(shelf.position.x, shelf.end.y), theme.accent, 2.0)
	draw_line(Vector2(shelf.end.x, shelf.position.y), shelf.end, theme.accent, 2.0)
