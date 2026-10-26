extends SceneTree

const Terrain := preload("res://scripts/world_terrain.gd")
const Backdrop := preload("res://scripts/world_backdrop.gd")
const Minimap := preload("res://scripts/minimap.gd")

class MapFixture extends RefCounted:
	var stage: Dictionary = {}
	var explored_cells: Dictionary = {}
	var discovered_bosses: Dictionary = {}
	var defeated_bosses: Dictionary = {}
	var player: Node2D
	func view_rect() -> Rect2:
		return Rect2(0, 0, 1280, 720)
	func biome_at(point: Vector2) -> int:
		return clampi(floori(point.x / (stage.bounds.size.x / 3.0)), 0, 2)

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: ", message)

func run() -> void:
	var terrain := Terrain.new()
	terrain.stage = {"bounds": Rect2(0, 0, 12288, 3072), "solids": [Rect2(0, 0, 96, 96), Rect2(160, 128, 96, 16)]}
	root.add_child(terrain)
	check(terrain.tile_masks.size() == 9, "Thin shelves do not fill a solid tile")
	check(terrain.mask_for_cell(Vector2i(1, 1)) == 255, "Filled centre connects in all eight directions")
	check(terrain.mask_for_cell(Vector2i(0, 0)) == Terrain.EAST | Terrain.SOUTH_EAST | Terrain.SOUTH, "Outer corner connects only inward")
	check(terrain.mask_for_cell(Vector2i(8, 8)) == 0, "Empty cells have no neighbours")
	check(terrain.collision_root.get_child_count() == 2, "Merged solids retain separate shelf collisions")
	var full_shape: CollisionShape2D = terrain.collision_root.get_child(0).get_child(0)
	var shelf_shape: CollisionShape2D = terrain.collision_root.get_child(1).get_child(0)
	check(not full_shape.one_way_collision, "Solid tiles block from all sides")
	check(shelf_shape.one_way_collision, "Thin shelves can be jumped through")
	terrain.stage.solids = [Rect2(32, 32, 32, 32), Rect2(64, 0, 32, 32)]
	terrain.rebuild()
	check(terrain.mask_for_cell(Vector2i(1, 1)) == 0, "Diagonals cannot join across absent cardinal edges")
	terrain.stage.solids = [Rect2(0, 32, 96, 32), Rect2(32, 0, 32, 32)]
	terrain.rebuild()
	check(terrain.mask_for_cell(Vector2i(1, 1)) == Terrain.NORTH | Terrain.EAST | Terrain.WEST, "Inside corners keep missing diagonal information")
	for cell: Vector2i in terrain.tile_masks:
		var mask: int = terrain.tile_masks[cell]
		check(not mask & Terrain.NORTH_EAST or mask & Terrain.NORTH and mask & Terrain.EAST, "NE requires both bordering edges")
		check(not mask & Terrain.SOUTH_EAST or mask & Terrain.SOUTH and mask & Terrain.EAST, "SE requires both bordering edges")
		check(not mask & Terrain.SOUTH_WEST or mask & Terrain.SOUTH and mask & Terrain.WEST, "SW requires both bordering edges")
		check(not mask & Terrain.NORTH_WEST or mask & Terrain.NORTH and mask & Terrain.WEST, "NW requires both bordering edges")
	# A batch seam must never become an edge in the actual terrain adjacency.
	terrain.stage.solids = [Rect2(448, 480, 128, 64), Rect2(448, 640, 128, 16)]
	terrain.rebuild()
	check(terrain.draw_chunks.size() == 4, "Terrain is split spatially for off-screen culling")
	check(terrain.mask_for_cell(Vector2i(15, 15)) & Terrain.EAST, "Horizontal adjacency crosses a draw batch boundary")
	check(terrain.mask_for_cell(Vector2i(15, 15)) & Terrain.SOUTH, "Vertical adjacency crosses a draw batch boundary")
	var tile_count := 0
	var shelf_width := 0.0
	for chunk in terrain.draw_chunks.values():
		tile_count += chunk.cells.size()
		for shelf: Rect2 in chunk.shelves:
			shelf_width += shelf.size.x
			check(shelf.size.x <= Terrain.DRAW_CHUNK_SIZE, "Shelf rendering clips at draw batch boundaries")
	check(tile_count == terrain.tile_masks.size(), "Every solid tile belongs to exactly one draw batch")
	check(is_equal_approx(shelf_width, 128.0), "Splitting a shelf preserves its complete visible width")
	var fixture := MapFixture.new()
	fixture.stage = {"seed": 37, "bounds": Rect2(0, 0, 12288, 3072), "solids": [Rect2(0, 2304, 12288, 768)]}
	var minimap := Minimap.new()
	minimap.game = fixture
	check(minimap.get_explored_cells().is_empty(), "The map initially reveals no world terrain")
	check(minimap.get_visible_bosses().is_empty(), "Boss positions are hidden until discovered")
	fixture.explored_cells[Vector2i(2, 17)] = true
	check(minimap.get_explored_cells() == [Vector2i(2, 17)], "Exploration reveals spatial cells without room nodes")
	fixture.discovered_bosses[1] = Vector2(6400, 1580)
	check(minimap.get_visible_bosses().size() == 1, "Only discovered bosses appear")
	fixture.defeated_bosses[1] = true
	fixture.defeated_bosses[2] = true
	check(minimap.get_visible_bosses().size() == 1, "Defeat state alone never reveals an unknown boss")
	check(minimap.get_visible_bosses()[0].defeated, "A discovered defeated boss keeps its cleared marker")
	fixture.player = Node2D.new()
	fixture.player.position = Vector2(288, 2282)
	root.add_child(fixture.player)
	minimap.size = Vector2(240, 170)
	check(minimap.map_area() == Rect2(12, 12, 216, 146), "map uses the former heading and legend area with twelve-pixel margins")
	var map_source := FileAccess.get_file_as_string("res://scripts/minimap.gd")
	check(not map_source.contains("draw_string") and not map_source.contains("draw_char"), "minimap draws no text headings, legends or counts")
	check(map_source.contains("draw_circle") and map_source.contains("draw_polyline") and map_source.contains("draw_colored_polygon") and map_source.contains("view_rect()"), "map keeps player, cleared and discovered guardian shapes and viewport outline")
	root.add_child(minimap)
	minimap.update_map()
	check(minimap._geometry_for_cell(Vector2i(2, 17)).is_empty(), "Explored air remains air on the map")
	check(minimap._geometry_for_cell(Vector2i(2, 18)).size() == 1, "Ground geometry is clipped to explored cells")
	fixture.stage.seed = 38
	minimap.update_map()
	check(minimap._cell_geometry.is_empty(), "A new seed clears cached minimap geometry")
	var backdrop := Backdrop.new()
	backdrop.stage = fixture.stage
	root.add_child(backdrop)
	check(backdrop.z_index < terrain.z_index, "Biome scenery stays behind collision tiles")
	check(backdrop.get_child_count() == 144, "The world background is divided into cullable spatial batches")
	for boundary in [4096, 8192]:
		var left: Color = backdrop.color_at(boundary - 0.1)
		var right: Color = backdrop.color_at(boundary + 0.1)
		check(absf(left.r - right.r) + absf(left.g - right.g) + absf(left.b - right.b) < 0.0002, "Biome background colors remain continuous at boundaries")
		var before: Color = terrain.theme_at_x(boundary - 0.01).body
		var after: Color = terrain.theme_at_x(boundary + 0.01).body
		check(before.is_equal_approx(after), "Terrain color does not create a hard region seam")
	await process_frame
	minimap.queue_free()
	fixture.player.queue_free()
	terrain.free()
	backdrop.queue_free()
	print("Tile and minimap checks: %d, failures: %d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
