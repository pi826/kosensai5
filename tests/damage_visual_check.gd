extends SceneTree
const Main := preload("res://scripts/main.gd")
const T := preload("res://scripts/tuning.gd")
const OUTPUT := "res://builds/qa/seamless/damage/"
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
	game.player.set_physics_process(false)
	game.elapsed = 10.0
	var normals: Array = get_nodes_in_group("enemies").filter(func(actor): return actor.kind != "boss")
	for actor in get_nodes_in_group("enemies"):
		actor.set_physics_process(false)
	game.player.position.x -= 256
	game._update_camera(0.0, true)
	for i in range(3):
		normals[i].position = game.stage.start_position + Vector2(-160 + i * 224, 0)
		normals[i].polarity = i % 2
	await frames(2)
	for i in range(3):
		normals[i].receive_hit(1 - normals[i].polarity, 1)
		normals[i].tick_visuals(0.2)
	await frames(10)
	await capture("enemy_hp_and_damage")
	var boss_actor = get_nodes_in_group("enemies").filter(func(actor): return actor.kind == "boss")[0]
	game.player.position = Vector2(boss_actor.position.x + 256, boss_actor.position.y + T.BOSS_SIZE.y / 2 - T.PLAYER_SIZE.y / 2)
	game._update_camera(0.0, true)
	game._update_exploration()
	game.ui.update_hud()
	await frames(3)
	game.boss.receive_hit(1 - game.boss.polarity, 4)
	game.boss.tick_visuals(0.2)
	await frames(10)
	await capture("boss_hp_and_damage")
	game.queue_free()
	await frames(2)
	print("DAMAGE DISPLAY CAPTURES: builds/qa/seamless/damage/")
	quit()
