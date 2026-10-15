extends SceneTree

const Terrain := preload("res://scripts/room_terrain.gd")
const Backdrop := preload("res://scripts/room_backdrop.gd")
const Minimap := preload("res://scripts/minimap.gd")

class MapFixture extends RefCounted:
	var stage: Dictionary = {}
	var visited_rooms: Dictionary = {}
	var current_room_id := 0
	var defeated_bosses: Dictionary = {}

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
	terrain.room = {"solids": [Rect2(0, 0, 96, 96), Rect2(160, 128, 96, 16)], "biome": 1}
	root.add_child(terrain)
	check(terrain.tile_masks.size() == 9, "Thin shelves do not fill a 32 px solid collision tile")
	check(terrain.mask_for_cell(Vector2i(1, 1)) == 255, "Filled centre connects in all eight directions")
	check(terrain.mask_for_cell(Vector2i(0, 0)) == Terrain.EAST | Terrain.SOUTH_EAST | Terrain.SOUTH, "Outer corner connects only inward")
	check(terrain.mask_for_cell(Vector2i(8, 8)) == 0, "Empty cells have no neighbours")
	check(terrain.get_child_count() == 2, "Merged solids and one-way shelf retain their separate collisions")
	var full_shape: CollisionShape2D = terrain.get_child(0).get_child(0)
	var shelf_shape: CollisionShape2D = terrain.get_child(1).get_child(0)
	check(not full_shape.one_way_collision, "Solid tiles block from all sides")
	check(shelf_shape.one_way_collision, "A thin shelf can be jumped through from below")
	terrain.room = {"solids": [Rect2(32, 32, 32, 32), Rect2(64, 0, 32, 32)]}
	terrain.rebuild()
	check(terrain.mask_for_cell(Vector2i(1, 1)) == 0, "A touching diagonal does not join across absent cardinal edges")
	terrain.room = {"solids": [Rect2(0, 32, 96, 32), Rect2(32, 0, 32, 32)]}
	terrain.rebuild()
	check(terrain.mask_for_cell(Vector2i(1, 1)) == Terrain.NORTH | Terrain.EAST | Terrain.WEST, "An inside corner keeps missing diagonal information")
	for cell: Vector2i in terrain.tile_masks:
		var mask: int = terrain.tile_masks[cell]
		check(not mask & Terrain.NORTH_EAST or mask & Terrain.NORTH and mask & Terrain.EAST, "NE only joins two bordering edges")
		check(not mask & Terrain.SOUTH_EAST or mask & Terrain.SOUTH and mask & Terrain.EAST, "SE only joins two bordering edges")
		check(not mask & Terrain.SOUTH_WEST or mask & Terrain.SOUTH and mask & Terrain.WEST, "SW only joins two bordering edges")
		check(not mask & Terrain.NORTH_WEST or mask & Terrain.NORTH and mask & Terrain.WEST, "NW only joins two bordering edges")
	var fixture := MapFixture.new()
	fixture.stage = {"rooms": [
		{"id": 0, "grid": Vector2i.ZERO, "doors": [{"target": 1}], "biome": 0},
		{"id": 1, "grid": Vector2i.RIGHT, "doors": [{"target": 0}], "biome": 1, "boss_id": 0},
		{"id": 2, "grid": Vector2i.UP, "doors": [], "biome": 2, "boss_id": 1},
	]}
	var minimap := Minimap.new()
	minimap.game = fixture
	check(minimap.get_visible_rooms().is_empty(), "The map reveals no rooms before exploration")
	fixture.visited_rooms = {0: true}
	check(minimap.get_visible_rooms().size() == 1, "Only the current visited room is revealed")
	fixture.visited_rooms[1] = true
	fixture.current_room_id = 1
	fixture.defeated_bosses[0] = true
	check(minimap.get_visible_rooms().size() == 2, "A boss defeat does not reveal an unexplored room")
	check(int(minimap.get_visible_rooms()[1].boss_id) == 0, "Visited boss room retains its unique guardian identity")
	minimap.size = Vector2(240, 170)
	root.add_child(minimap)
	for biome in range(3):
		var backdrop := Backdrop.new()
		backdrop.room = {"id": biome, "biome": biome}
		root.add_child(backdrop)
		check(backdrop.z_index < terrain.z_index, "Biome scenery stays behind collision tiles")
		backdrop.queue_free()
	await process_frame
	minimap.queue_free()
	terrain.free()
	print("Tile and minimap checks: %d, failures: %d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
