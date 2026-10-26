extends SceneTree
const Main := preload("res://scripts/main.gd")
const T := preload("res://scripts/tuning.gd")
const S := preload("res://scripts/sector_generator.gd")
const Support := preload("res://tests/stream_test_support.gd")
const OUTPUT := "res://builds/qa/streaming/"
var game: Node2D
var failures := 0
func _initialize(): call_deferred("run")
func frames(n: int):
	for i in range(n):
		await physics_frame
		await process_frame
func capture(name: String):
	await RenderingServer.frame_post_draw
	var code := root.get_texture().get_image().save_png(OUTPUT + name + ".png")
	if code != OK:
		failures += 1
		printerr("CAPTURE FAILED ",name)
	else: print("CAPTURE ", name)
func show(point: Vector2):
	if not await Support.ready(self,game,point):
		failures += 1
		return
	game.player.position = point
	game.player.velocity = Vector2.ZERO
	game._update_camera(0,true)
	game._update_exploration()
	game.ui.update_hud()
	await frames(4)
func run():
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	game = Main.new()
	game.controls_path = OUTPUT + "visual_controls.cfg"
	root.add_child(game)
	game.start_run(37)
	await show(T.SECTOR_START)
	await capture("start")
	var gate: Dictionary = S.boundary_gates(37,Vector2i.ZERO,Vector2i.RIGHT)[0]
	await show(Vector2(gate.rect.position.x,gate.rect.end.y-22))
	await capture("seam_horizontal")
	gate = S.boundary_gates(37,Vector2i.ZERO,Vector2i.DOWN)[0]
	await show(Vector2(gate.rect.position.x+128,gate.rect.position.y-54))
	await capture("seam_vertical")
	var at: Vector2i = S.guardian_sectors(37)[0]
	await show(Vector2(at)*T.SECTOR_SIZE+T.SECTOR_START)
	var guardian = get_nodes_in_group("enemies").filter(func(e): return e.kind=="boss" and e.get_meta("sector",Vector2i.ZERO)==at)[0]
	await show(guardian.position+Vector2(160,T.BOSS_SIZE.y/2-22))
	guardian.receive_hit(1-guardian.polarity,4)
	game.ui.update_hud()
	await frames(2)
	await capture("guardian")
	await show(T.SECTOR_START)
	for y in range(-8,20):
		for x in range(-12,32):
			var cell := Vector2i(x,y)
			if (Vector2(cell)*T.MAP_CELL_SIZE-game.player.position).length()<1800: game.explored_cells[cell]=true
	game.ui.minimap.update_map()
	await frames(3)
	await capture("map_offscreen_guardian")
	await show(Vector2(50,-20)*T.SECTOR_SIZE+T.SECTOR_START)
	var far: Dictionary = game.stream.loaded[Vector2i(50,-20)]
	await show(far.start_position)
	var bullet=game.spawn_bullet(game.player,Vector2.RIGHT)
	bullet.set_physics_process(false)
	bullet.position=game.player.position+Vector2(90,-4)
	await frames(2)
	await capture("far_sector")
	game.show_menu("paused")
	await frames(3)
	await capture("paused")
	game.kills=12
	for id in range(3): game.defeated_bosses[id]=true
	game.show_menu("won")
	await frames(3)
	await capture("result")
	FileAccess.open(OUTPUT+"visual_results.json",FileAccess.WRITE).store_string(JSON.stringify({"captures":8,"failures":failures,"renderer":RenderingServer.get_video_adapter_name()},"\t"))
	game.free()
	print("VISUAL CHECK: 8 captures, ", failures, " failures")
	quit(0 if failures==0 else 1)
