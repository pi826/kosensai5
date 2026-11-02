extends "res://tests/stage3_art_visual.gd"
## Same seeds, fixture, camera and real gate as stage 3; no performance/full suite.
const POLISH := "res://builds/qa/art/polish/"
const Checks := preload("res://tests/polish_art_checks.gd")
const Backdrop := preload("res://scripts/world_backdrop.gd")

class ShelfTerrain extends Node2D:
	var stage := {"seed":4}
	var fallbacks: Array[Rect2] = []
	func cell_at(point: Vector2) -> Vector2i: return Vector2i((point/32).floor())
	func draw_shelf_shape(_canvas: Node2D, part: Rect2) -> void: fallbacks.append(part)

class ShelfProbe extends Node2D:
	var fixture: Node2D
	var result := false
	func _draw() -> void: result=Art.draw_shelf(self,fixture,Rect2(4000,600,192,16))

func capture(name: String) -> void:
	refresh(); await frames(5)
	await RenderingServer.frame_post_draw
	check(tree.root.get_texture().get_image().save_png(POLISH+name+".png")==OK,"capture "+name)
	captures+=1

func backdrop_metrics(region: int) -> void:
	var hidden: Array[CanvasItem] = []
	for child in game.world.get_children():
		if child is CanvasItem and child.visible and not child is Backdrop:
			hidden.append(child); child.hide()
	game.ui.hide()
	await capture("background-"+str(region))
	var stats := Checks.image_stats(tree.root.get_texture().get_image())
	metrics["background_"+str(region)]=stats
	var rgb: Array = stats.mean_rgb
	check(stats.mean_luma<=30,"rendered background luminance <=30")
	check((rgb[1]-rgb[0]>=6 if region==0 else rgb[2]-rgb[1]>=8 if region==1 else rgb[0]-rgb[2]>=8),"rendered regional background color")
	for child in hidden: child.show()
	game.ui.show()

func interior_metrics() -> void:
	var best := Vector2(2048,2048)
	var best_count := -1
	for y in range(768,2560,384):
		for x in range(768,3456,384):
			var count := 0
			for sy in range(-320,321,128):
				for sx in range(-608,609,128):
					if game.terrain.tile_masks.get(game.terrain.cell_at(Vector2(x+sx,y+sy)),0)==255: count+=1
			if count>best_count: best=Vector2(x,y); best_count=count
	game.camera.position=best; game.camera.force_update_scroll()
	game.terrain.prepare_view(game.view_rect()); game.stream.prepare_backdrop_view(game.view_rect())
	var hidden: Array[CanvasItem] = []
	for child in game.world.get_children():
		if child is CanvasItem and child.visible and child!=game.terrain and not child is Backdrop:
			hidden.append(child); child.hide()
	game.ui.hide()
	await capture("game-interior-0")
	var image := tree.root.get_texture().get_image()
	var mask := Image.create(1280,720,false,Image.FORMAT_RGB8)
	var top_left: Vector2 = game.camera.get_screen_center_position()-Vector2(640,360)
	for y in range(720):
		for x in range(1280):
			var cell: Vector2i = game.terrain.cell_at(top_left+Vector2(x+.5,y+.5))
			if game.terrain.tile_masks.get(cell,0)==255 and game.terrain.tile_masks.get(cell+Vector2i.UP,0)==255 and not game.terrain.block_cells.has(cell):
				mask.set_pixel(x,y,Color.WHITE)
	mask.save_png(POLISH+"interior-mask-0.png")
	var stats := Checks.image_stats(image,mask)
	stats["camera"]=[best.x,best.y]
	metrics["waterway_interior"]=stats
	metrics["waterway_four_cell_periods"]=Checks.image_periods(image,mask,check)
	check(image.get_size()==Vector2i(1280,720),"deep interior measured in a 1280x720 game frame")
	check(stats.pixels>=200000,"deep interior mask contains >=200000 real rock pixels")
	check(stats.std_luma>=18,"deep interior rendered luminance deviation >=18")
	for child in hidden: child.show()
	game.ui.show()

func run(host: SceneTree) -> void:
	tree=host
	check(DisplayServer.get_name()!="headless","normal renderer required")
	if not failures.is_empty(): tree.quit(1); return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED); Engine.max_fps=0
	Checks.sheets(check)
	game=Main.new(); game.controls_path=POLISH+"qa-controls.cfg"; game.audio_settings_path=POLISH+"qa-audio.cfg"; game.audio_synthesis_override=0
	tree.root.add_child(game); game.set_physics_process(false); game.world.process_mode=Node.PROCESS_MODE_DISABLED
	await loaded(); await frames(6)
	Checks.hud(check,game.ui)
	# Ensure screenshots use the rebuilt pixels, rather than stale imported caches.
	for path in [Art.terrain_path(0),"res://assets/art/backdrops/0-0.png","res://assets/art/backdrops/1-0.png","res://assets/art/backdrops/2-0.png"]:
		var source := Image.load_from_file(path)
		var shown := Art.texture(path,path).get_image()
		source.convert(Image.FORMAT_RGBA8); shown.convert(Image.FORMAT_RGBA8)
		check(source.get_data()==shown.get_data(),"GPU sheet matches current PNG: "+path)
	var last_seed := 1
	for region in range(3):
		var seed_value := 1
		while S.region_at(seed_value,Vector2i.ZERO)!=region: seed_value+=1
		last_seed=seed_value
		game.start_run(seed_value); game.set_physics_process(false); game.world.process_mode=Node.PROCESS_MODE_DISABLED
		fixture(); await frames(10)
		check(game.biome_at(game.player.position)==region,"actual region "+str(region))
		await capture("game-biome-"+str(region))
		await backdrop_metrics(region)
		if region==0: await interior_metrics()
	var adjacent := Vector2i.RIGHT
	for at in [Vector2i.RIGHT,Vector2i.LEFT,Vector2i.UP,Vector2i.DOWN]:
		if S.region_at(last_seed,at)!=S.region_at(last_seed,Vector2i.ZERO): adjacent=at; break
	var boundary := Vector2(T.SECTOR_SIZE.x if adjacent.x>0 else 0,T.SECTOR_SIZE.y/2) if adjacent.x!=0 else Vector2(T.SECTOR_SIZE.x/2,T.SECTOR_SIZE.y if adjacent.y>0 else 0)
	var gates: Array = S.boundary_gates(last_seed,Vector2i.ZERO,adjacent)
	if not gates.is_empty(): boundary=gates[0].rect.get_center()
	check(await Support.ready(tree,game,boundary),"streamed actual boundary")
	game.world.process_mode=Node.PROCESS_MODE_DISABLED
	game.camera.position=boundary; game.camera.force_update_scroll()
	game.terrain.prepare_view(game.view_rect()); game.stream.prepare_backdrop_view(game.view_rect())
	await capture("game-boundary")
	Art.mode_override="shapes"; refresh(); await frames(3)
	check(game.ui.menu_card.get_theme_stylebox("panel") is StyleBoxFlat,"shapes retains original UI fallback")
	Art.mode_override="sprites"; refresh(); await frames(3)
	var path := Art.terrain_path(0)
	Art.path_overrides[path]=POLISH+"missing-waterway.png"; Art.texture(path,path); await loaded()
	check(Art.texture(path,path)==null,"missing waterway ID falls back")
	check(Art.texture(Art.terrain_path(1),Art.terrain_path(1))!=null,"healthy regional tile retained")
	var special := Art.terrain_path(0,true)
	Art.path_overrides[special]=POLISH+"missing-special.png"; Art.texture(special,special); await loaded()
	var shelf_fixture := ShelfTerrain.new()
	var probe := ShelfProbe.new(); probe.fixture=shelf_fixture
	tree.root.add_child(probe); await frames(2)
	check(probe.result,"mixed shelf completes rendering despite missing regional sheet")
	var expected_missing := 0
	for x in range(4000,4192,32):
		if Art.tile_visual_region(Vector2i(x/32,600/32),4)==0: expected_missing+=1
	check(expected_missing>0 and expected_missing<6,"mixed shelf probe includes both regional IDs")
	check(shelf_fixture.fallbacks.size()==expected_missing,"only missing regional shelf cells fall back")
	for part in shelf_fixture.fallbacks:
		check(Art.tile_visual_region(shelf_fixture.cell_at(part.position),4)==0,"healthy shelf region never replaced by fallback")
	probe.free(); shelf_fixture.free()
	Art.path_overrides.clear()
	metrics["luminance_definition"]="0.2126 R + 0.7152 G + 0.0722 B, sRGB bytes 0..255"
	metrics["method"]="Same stage3 seeds/fixtures/camera and gate. Background rendered alone at the same camera; interior uses actual generated mask=255, above=255, no breakable cells, HUD/actors hidden. Physics frozen."
	FileAccess.open(POLISH+"metrics.json",FileAccess.WRITE).store_string(JSON.stringify(metrics,"\t"))
	FileAccess.open(POLISH+"visual-results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"captures":captures,"failures":failures},"\t"))
	game.free(); print("POLISH ART QA: %d checks, %d captures, %d failures; %s" % [checks,captures,failures.size(),JSON.stringify(metrics)])
	tree.quit(0 if failures.is_empty() else 1)
