extends Node2D
## Continuous regional scenery behind carved cave air. Draw batches create no gameplay boundaries.

const Terrain := preload("res://scripts/world_terrain.gd")
const T := preload("res://scripts/tuning.gd")
const CHUNK_SIZE := 512
var stage: Dictionary = {}

class BackdropChunk extends Node2D:
	var backdrop: Node2D
	var bounds: Rect2
	func _draw() -> void:
		backdrop.draw_chunk(self, bounds)

func _ready() -> void:
	z_index = -20
	var bounds: Rect2 = stage.get("bounds", Rect2(Vector2.ZERO, T.SECTOR_SIZE))
	for y in range(floori(bounds.position.y / CHUNK_SIZE), ceili(bounds.end.y / CHUNK_SIZE)):
		for x in range(floori(bounds.position.x / CHUNK_SIZE), ceili(bounds.end.x / CHUNK_SIZE)):
			var chunk := BackdropChunk.new()
			chunk.backdrop = self
			chunk.position = Vector2(x, y) * CHUNK_SIZE
			chunk.bounds = Rect2(chunk.position, Vector2.ONE * CHUNK_SIZE).intersection(bounds)
			add_child(chunk)

func color_at(x: float, key: String = "back") -> Color:
	return Terrain.regional_theme(Vector2(x,0),int(stage.get("seed",0)))[key]

func draw_chunk(canvas: Node2D, bounds: Rect2) -> void:
	var local := Rect2(bounds.position-canvas.position,bounds.size)
	var points := PackedVector2Array([bounds.position,Vector2(bounds.end.x,bounds.position.y),bounds.end,Vector2(bounds.position.x,bounds.end.y)])
	var colors := PackedColorArray()
	for point: Vector2 in points: colors.append(Terrain.regional_theme(point,int(stage.get("seed",0))).back)
	canvas.draw_polygon(PackedVector2Array([local.position,Vector2(local.end.x,local.position.y),local.end,Vector2(local.position.x,local.end.y)]),colors)
	# Repeated motifs are anchored to world coordinates in both axes.
	for wx in range(ceili(bounds.position.x/128.0)*128,int(bounds.end.x),128):
		var x := wx-canvas.position.x
		for wy in range(floori(bounds.position.y/1024.0)*1024,int(bounds.end.y),1024):
			var phase := posmod(wx/128,5)
			var shape := Rect2(wx+32,wy+phase*128,22,1024-phase*128)
			var clip := shape.intersection(bounds)
			if clip.has_area():
				var tint: Color=Terrain.regional_theme(clip.get_center(),int(stage.get("seed",0))).accent
				tint.a=0.075
				canvas.draw_rect(Rect2(clip.position-canvas.position,clip.size),tint)
		for wy in range(ceili(bounds.position.y/256.0)*256,int(bounds.end.y),256):
			var tint: Color=Terrain.regional_theme(Vector2(wx,wy),int(stage.get("seed",0))).accent
			tint.a=0.055
			var y := wy-canvas.position.y
			canvas.draw_line(Vector2(x+58,y+16),Vector2(minf(x+116,local.end.x),y+16),tint,1)