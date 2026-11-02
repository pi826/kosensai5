extends Node2D
## Continuous regional scenery behind carved cave air. Draw batches create no gameplay boundaries.

const Terrain := preload("res://scripts/world_terrain.gd")
const T := preload("res://scripts/tuning.gd")
const Art := preload("res://scripts/sprite_art.gd")
const CHUNK_SIZE := 512
var stage: Dictionary = {}
var chunks: Dictionary = {} # Stable world chunk keys survive origin shifts.
var art_materials: Array[ShaderMaterial] = []
var art_serial := -1
var was_enabled := false

func _process(_delta: float) -> void:
	if was_enabled != Art.enabled():
		was_enabled=Art.enabled()
		if not was_enabled: art_materials.clear()
		else: art_serial=-1
		for chunk in chunks.values(): chunk.queue_redraw()
	if not Art.enabled(): return
	if art_serial != Art.upload_serial:
		art_serial = Art.upload_serial
		art_materials.clear()
		for layer in range(2):
			var material := ShaderMaterial.new()
			material.shader = preload("res://assets/art/backdrop.gdshader")
			var available := Vector3.ZERO
			for region in range(3):
				var path := "res://assets/art/backdrops/%d-%d.png" % [region,layer]
				var texture := Art.texture(path,path)
				available[region]=1.0 if texture!=null else 0.0
				material.set_shader_parameter(["water","crystal","ash"][region],texture)
				if layer==1: art_materials[0].set_shader_parameter(["mid_water","mid_crystal","mid_ash"][region],texture)
			if layer==0: material.set_shader_parameter("far_enabled",available)
			else: art_materials[0].set_shader_parameter("mid_enabled",available)
			art_materials.append(material)
		for chunk in chunks.values(): chunk.queue_redraw()
	var camera := get_viewport().get_camera_2d()
	if camera == null or art_materials.size()!=2: return
	var origin: Vector2i = stage.get("origin_sector",Vector2i.ZERO)
	var stable_x: float = float(camera.global_position.x)+float(origin.x)*T.SECTOR_SIZE.x
	var stable_y: float = float(camera.global_position.y)+float(origin.y)*T.SECTOR_SIZE.y
	for layer in range(2):
		var factor := 0.84 if layer==0 else 0.64
		var phase := Vector2(fposmod(stable_x*factor,512)/512,fposmod(stable_y*factor,1024)/1024)
		art_materials[layer].set_shader_parameter("camera_offset",phase)
		if layer==1: art_materials[0].set_shader_parameter("mid_offset",phase)

func region_weights(point: Vector2) -> Color:
	# Same region selection and spatial blend as WorldTerrain.regional_theme.
	var coord := Vector2i((point/T.SECTOR_SIZE).floor())
	var local := point-Vector2(coord)*T.SECTOR_SIZE
	coord += stage.get("origin_sector",Vector2i.ZERO)
	var lo := coord
	var hi := coord
	var blend := Vector2.ZERO
	for axis in range(2):
		if local[axis]<T.REGION_BLEND_WIDTH:
			lo[axis]-=1
			blend[axis]=smoothstep(-T.REGION_BLEND_WIDTH,T.REGION_BLEND_WIDTH,local[axis])
		elif local[axis]>T.SECTOR_SIZE[axis]-T.REGION_BLEND_WIDTH:
			hi[axis]+=1
			blend[axis]=smoothstep(T.SECTOR_SIZE[axis]-T.REGION_BLEND_WIDTH,T.SECTOR_SIZE[axis]+T.REGION_BLEND_WIDTH,local[axis])
	var sectors := preload("res://scripts/sector_generator.gd")
	var weights := [Color(1,0,0),Color(0,1,0),Color(0,0,1)]
	var seed_value := int(stage.get("seed",0))
	return weights[sectors.region_at(seed_value,lo)].lerp(weights[sectors.region_at(seed_value,Vector2i(hi.x,lo.y))],blend.x).lerp(weights[sectors.region_at(seed_value,Vector2i(lo.x,hi.y))].lerp(weights[sectors.region_at(seed_value,hi)],blend.x),blend.y)

func draw_art(canvas: Node2D, bounds: Rect2) -> bool:
	if not Art.enabled() or art_materials.size()!=2: return false
	var points := PackedVector2Array([bounds.position,Vector2(bounds.end.x,bounds.position.y),bounds.end,Vector2(bounds.position.x,bounds.end.y)])
	var local := PackedVector2Array()
	var uvs := PackedVector2Array()
	var weights := PackedColorArray()
	var origin: Vector2i = stage.get("origin_sector",Vector2i.ZERO)
	var phase := Vector2(fposmod(float(bounds.position.x)+float(origin.x)*T.SECTOR_SIZE.x,512),fposmod(float(bounds.position.y)+float(origin.y)*T.SECTOR_SIZE.y,1024))
	for p in points:
		local.append(p-canvas.position)
		uvs.append((p-bounds.position+phase)/Vector2(512,1024))
		weights.append(region_weights(p))
	# One draw command for two layers, independent of world length. Preserve
	# origin-shift's chunk-only child contract and streaming readiness checks.
	canvas.material = art_materials[0]
	canvas.draw_polygon(local,weights,uvs)
	return true

class BackdropChunk extends Node2D:
	var backdrop: Node2D
	var bounds: Rect2
	var drawn := false
	func _draw() -> void:
		backdrop.draw_chunk(self, bounds)
		drawn = true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = -20
	var bounds: Rect2 = stage.get("bounds", Rect2(Vector2.ZERO, T.SECTOR_SIZE))
	for y in range(floori(bounds.position.y / CHUNK_SIZE), ceili(bounds.end.y / CHUNK_SIZE)):
		for x in range(floori(bounds.position.x / CHUNK_SIZE), ceili(bounds.end.x / CHUNK_SIZE)):
			var chunk := BackdropChunk.new()
			chunk.backdrop = self
			chunk.position = Vector2(x, y) * CHUNK_SIZE
			chunk.bounds = Rect2(chunk.position, Vector2.ONE * CHUNK_SIZE).intersection(bounds)
			# Streamed sectors install all background data now, but do not build
			# 48 offscreen drawing lists on the sector's completion frame.
			if stage.get("streaming", false): chunk.hide()
			var origin: Vector2i = stage.get("origin_sector", Vector2i.ZERO)
			chunks[Vector2i(x, y) + origin * Vector2i(T.SECTOR_SIZE / CHUNK_SIZE)] = chunk
			add_child(chunk)

func view_chunks(area: Rect2) -> Array[Node2D]:
	var result: Array[Node2D] = []
	var origin: Vector2i = stage.get("origin_sector", Vector2i.ZERO) * Vector2i(T.SECTOR_SIZE / CHUNK_SIZE)
	var first := Vector2i((area.position / CHUNK_SIZE).floor()) + origin
	var last := Vector2i((area.end / CHUNK_SIZE).ceil()) + origin
	for y in range(first.y, last.y):
		for x in range(first.x, last.x):
			if chunks.has(Vector2i(x, y)): result.append(chunks[Vector2i(x, y)])
	return result

func prepare_view(area: Rect2) -> void:
	for chunk: Node2D in view_chunks(area): chunk.show()

func color_at(x: float, key: String = "back") -> Color:
	return Terrain.regional_theme(Vector2(x,0),int(stage.get("seed",0)), stage.get("origin_sector", Vector2i.ZERO))[key]

func draw_chunk(canvas: Node2D, bounds: Rect2) -> void:
	if draw_art(canvas,bounds): return
	canvas.material = null
	var local := Rect2(bounds.position-canvas.position,bounds.size)
	var points := PackedVector2Array([bounds.position,Vector2(bounds.end.x,bounds.position.y),bounds.end,Vector2(bounds.position.x,bounds.end.y)])
	var colors := PackedColorArray()
	for point: Vector2 in points: colors.append(Terrain.regional_theme(point,int(stage.get("seed",0)), stage.get("origin_sector", Vector2i.ZERO)).back)
	canvas.draw_polygon(PackedVector2Array([local.position,Vector2(local.end.x,local.position.y),local.end,Vector2(local.position.x,local.end.y)]),colors)
	# Repeated motifs are anchored to world coordinates in both axes.
	for wx in range(ceili(bounds.position.x/128.0)*128,int(bounds.end.x),128):
		var x := wx-canvas.position.x
		for wy in range(floori(bounds.position.y/1024.0)*1024,int(bounds.end.y),1024):
			var phase := posmod(wx/128 + int(stage.get("origin_sector", Vector2i.ZERO).x) * int(T.SECTOR_SIZE.x / 128),5)
			var shape := Rect2(wx+32,wy+phase*128,22,1024-phase*128)
			var clip := shape.intersection(bounds)
			if clip.has_area():
				var tint: Color=Terrain.regional_theme(clip.get_center(),int(stage.get("seed",0)), stage.get("origin_sector", Vector2i.ZERO)).accent
				tint.a=0.075
				canvas.draw_rect(Rect2(clip.position-canvas.position,clip.size),tint)
		for wy in range(ceili(bounds.position.y/256.0)*256,int(bounds.end.y),256):
			var tint: Color=Terrain.regional_theme(Vector2(wx,wy),int(stage.get("seed",0)), stage.get("origin_sector", Vector2i.ZERO)).accent
			tint.a=0.055
			var y := wy-canvas.position.y
			canvas.draw_line(Vector2(x+58,y+16),Vector2(minf(x+116,local.end.x),y+16),tint,1)
