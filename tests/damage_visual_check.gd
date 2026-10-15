extends SceneTree
const Main := preload("res://scripts/main.gd")
const T := preload("res://scripts/tuning.gd")
const OUTPUT := "res://builds/qa/phase2/damage/"
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

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	game = Main.new()
	game.controls_path = OUTPUT + "controls.cfg"
	root.add_child(game)
	game.start_run(37)
	await frames(3)
	var normals: Array = get_nodes_in_group("enemies").filter(func(actor): return actor.kind != "boss")
	for actor in get_nodes_in_group("enemies"):
		actor.set_physics_process(false)
	for i in range(3):
		normals[i].room_id = game.current_room_id
		normals[i].position = Vector2(416 + i * 224, T.ROOM_FLOOR_Y - T.ENEMY_SIZE.y / 2)
		normals[i].polarity = i % 2
	await frames(2)
	normals[0].receive_hit(1, 1)
	normals[1].receive_hit(0, 4)
	normals[2].receive_hit(1, 1)
	for i in range(3):
		normals[i].tick_visuals(0.2)
	await frames(10)
	await capture("enemy_hp_and_damage")
	var boss_actor = get_nodes_in_group("enemies").filter(func(actor): return actor.kind == "boss")[0]
	game._set_current_room(boss_actor.room_id)
	game.player.position = game.current_room().origin + Vector2(288, 618)
	for actor in get_nodes_in_group("enemies"):
		actor.set_physics_process(false)
	await frames(3)
	game.boss.receive_hit(1 - game.boss.polarity, 4)
	game.boss.tick_visuals(0.2)
	await frames(10)
	await capture("boss_hp_and_damage")
	game.queue_free()
	await frames(2)
	print("DAMAGE DISPLAY CAPTURES: builds/qa/phase2/damage/")
	quit()
