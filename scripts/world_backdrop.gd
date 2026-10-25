extends Node2D
## Continuous regional scenery behind carved cave air. Draw batches create no gameplay boundaries.

const Terrain := preload("res://scripts/world_terrain.gd")
const CHUNK_SIZE := 512
var stage: Dictionary = {}

class BackdropChunk extends Node2D:
	var backdrop: Node2D
	var bounds: Rect2
	func _draw() -> void:
		backdrop.draw_chunk(self, bounds)

func _ready() -> void:
	z_index = -20
	var bounds: Rect2 = stage.get("bounds", Rect2(0, 0, 12288, 3072))
	for y in range(floori(bounds.position.y / CHUNK_SIZE), ceili(bounds.end.y / CHUNK_SIZE)):
		for x in range(floori(bounds.position.x / CHUNK_SIZE), ceili(bounds.end.x / CHUNK_SIZE)):
			var chunk := BackdropChunk.new()
			chunk.backdrop = self
			chunk.position = Vector2(x, y) * CHUNK_SIZE
			chunk.bounds = Rect2(chunk.position, Vector2.ONE * CHUNK_SIZE).intersection(bounds)
			add_child(chunk)

func color_at(x: float, key: String = "back") -> Color:
	var bounds: Rect2 = stage.get("bounds", Rect2(0, 0, 12288, 3072))
	var width := bounds.size.x / 3.0
	var region := clampi(floori((x - bounds.position.x) / width), 0, 2)
	for boundary in [1, 2]:
		var at: float = bounds.position.x + width * int(boundary)
		if absf(x - at) < 384:
			return Terrain.THEMES[boundary - 1][key].lerp(Terrain.THEMES[boundary][key], smoothstep(at - 384, at + 384, x))
	return Terrain.THEMES[region][key]

func draw_chunk(canvas: Node2D, bounds: Rect2) -> void:
	var local := Rect2(bounds.position - canvas.position, bounds.size)
	var left := color_at(bounds.position.x)
	var right := color_at(bounds.end.x)
	canvas.draw_polygon(PackedVector2Array([local.position, Vector2(local.end.x, local.position.y), local.end, Vector2(local.position.x, local.end.y)]), PackedColorArray([left, right, right, left]))
	# Motifs use world coordinates, so they continue through render-batch seams.
	for wx in range(ceili(bounds.position.x / 128.0) * 128, int(bounds.end.x), 128):
		var x := wx - canvas.position.x
		var tint := color_at(wx, "accent")
		tint.a = 0.075
		var phase := posmod(wx / 128, 5)
		var world_top := 384.0 + phase * 160.0
		var top := maxf(bounds.position.y, world_top) - canvas.position.y
		var bottom := bounds.end.y - canvas.position.y
		if top < bottom:
			canvas.draw_rect(Rect2(x + 32, top, 22, bottom - top), tint)
		var edge := color_at(wx, "accent")
		edge.a = 0.055
		for wy in range(ceili(bounds.position.y / 256.0) * 256, int(bounds.end.y), 256):
			var y := wy - canvas.position.y
			canvas.draw_line(Vector2(x + 58, y + 16), Vector2(minf(x + 116, local.end.x), y + 16), edge, 1)
