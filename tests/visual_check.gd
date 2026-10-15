extends SceneTree
const Main := preload("res://scripts/main.gd")
const T := preload("res://scripts/tuning.gd")
const OUTPUT := "res://builds/qa/phase2/"
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

func show_room(room: Dictionary, local: Vector2 = Vector2(288, 618)) -> void:
	game._set_current_room(room.id)
	game.player.position = room.origin + local
	game.player.velocity = Vector2.ZERO
	game.player.set_physics_process(false)
	for actor in get_nodes_in_group("enemies"):
		actor.set_physics_process(false)
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
	show_room(game.current_room(), Vector2(640, 234))
	await frames(3)
	await capture("upper_passage")
	for biome in range(3):
		var rooms: Array = game.stage.rooms.filter(func(room): return room.biome == biome and room.id != 0 and room.boss_id < 0)
		show_room(rooms[0])
		game.player.gauge = 5
		game.player.hp = 88
		var actor = get_nodes_in_group("enemies").filter(func(enemy): return enemy.room_id == game.current_room_id)[0]
		actor.receive_hit(1 - actor.polarity, T.NORMAL_DAMAGE)
		actor.tick_visuals(0.2)
		await frames(8)
		await capture("biome_%d" % (biome + 1))
	var bosses: Array = get_nodes_in_group("enemies").filter(func(actor): return actor.kind == "boss")
	show_room(game.stage.rooms[bosses[0].room_id])
	bosses[0].receive_hit(1 - bosses[0].polarity, 4)
	bosses[0].tick_visuals(0.2)
	await frames(8)
	await capture("boss")
	game.show_menu("paused")
	await frames(3)
	await capture("paused")
	game.resume_run()
	for room: Dictionary in game.stage.rooms:
		game.visited_rooms[room.id] = true
	for actor in bosses:
		actor.receive_hit(1 - actor.polarity, 1000)
	await frames(3)
	await capture("clear")
	game.start_run(37)
	await frames(3)
	game.player.receive_hit(1 - game.player.polarity, T.PLAYER_HP)
	await frames(3)
	await capture("retry")
	print("VISUAL CAPTURES: builds/qa/phase2/")
	game.queue_free()
	await frames(2)
	quit()
