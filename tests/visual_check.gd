extends SceneTree
const Main := preload("res://scripts/main.gd")
const T := preload("res://scripts/tuning.gd")
const OUTPUT := "res://builds/qa/seamless/"
var game: Node2D

func _initialize() -> void:
	call_deferred("run")

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT + name + ".png")

func floor_position(x: float) -> Vector2:
	var ground_y := T.WORLD_SIZE.y
	for solid: Rect2 in game.stage.solids:
		if solid.size.y > 20 and solid.position.x <= x and solid.end.x > x and solid.position.y > 32:
			ground_y = minf(ground_y, solid.position.y)
	return Vector2(x, ground_y - T.PLAYER_SIZE.y / 2)

func show_position(point: Vector2) -> void:
	game.player.position = point
	game.player.velocity = Vector2.ZERO
	game.player.set_physics_process(false)
	for actor in get_nodes_in_group("enemies"):
		actor.set_physics_process(false)
	game._update_camera(0.0, true)
	game._update_exploration()
	game.ui.update_hud()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	game = Main.new()
	game.controls_path = OUTPUT + "visual_controls.cfg"
	root.add_child(game)
	game.key_bindings.reset_defaults()
	game.start_run(37)
	game.show_menu("title")
	await frames(6)
	await capture("title")
	game.open_key_settings()
	await frames(5)
	game.ui.settings_panel._buttons["pause_game"][0].grab_focus()
	await frames(4)
	await capture("key_settings")
	game.close_key_settings()
	game.start_run(37)
	await frames(6)
	await capture("start")
	show_position(Vector2(5888, 768 - T.PLAYER_SIZE.y / 2))
	await frames(3)
	await capture("upper_path")
	for biome in range(3):
		var point := floor_position(2304 + biome * 3840)
		show_position(point)
		game.player.gauge = 5
		game.player.hp = 88
		var normals: Array = get_nodes_in_group("enemies").filter(func(enemy): return enemy.kind != "boss" and not enemy.dead)
		var actor = normals[biome]
		actor.position = point + Vector2(220, 0)
		actor.receive_hit(1 - actor.polarity, T.NORMAL_DAMAGE)
		actor.tick_visuals(0.2)
		await frames(8)
		await capture("biome_%d" % (biome + 1))
	for boundary in [4096.0, 8192.0]:
		show_position(floor_position(boundary))
		await frames(3)
		await capture("boundary_%d" % int(boundary))
	var bosses: Array = get_nodes_in_group("enemies").filter(func(actor): return actor.kind == "boss")
	show_position(floor_position(bosses[0].position.x + 220))
	bosses[0].receive_hit(1 - bosses[0].polarity, 4)
	bosses[0].tick_visuals(0.2)
	await frames(8)
	await capture("boss")
	game.show_menu("paused")
	await frames(3)
	await capture("paused")
	game.resume_run()
	for actor in bosses:
		game.discovered_bosses[actor.boss_id] = actor.position
		actor.receive_hit(1 - actor.polarity, 1000)
	await frames(3)
	await capture("clear")
	game.start_run(37)
	await frames(3)
	game.player.receive_hit(1 - game.player.polarity, T.PLAYER_HP)
	await frames(3)
	await capture("retry")
	print("VISUAL CAPTURES: builds/qa/seamless/")
	game.queue_free()
	await frames(2)
	quit()
