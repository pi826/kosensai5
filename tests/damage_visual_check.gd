extends "res://tests/test_tree.gd"
const Main := preload("res://scripts/main.gd")
const T := preload("res://scripts/tuning.gd")
const Support := preload("res://tests/stream_test_support.gd")
const S := preload("res://scripts/sector_generator.gd")
const OUTPUT := "res://builds/qa/seamless/damage/"
var game: Node2D

func _initialize() -> void:
	call_deferred("run")

func frames(count: int) -> void:
	for i in range(count):
		test_progress()
		await physics_frame
		test_progress()
		await process_frame

func capture(name: String) -> void:
	test_progress()
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
	var sector: Vector2i = S.guardian_sectors(37)[0]
	if not await Support.ready(self, game, game.stream.sector_offset(sector) + T.SECTOR_START):
		printerr("FAIL: damage capture boss sector preparation timed out")
		quit(1)
		return
	var bosses := get_nodes_in_group("enemies").filter(func(actor): return actor.kind == "boss" and not actor.is_queued_for_deletion())
	if bosses.is_empty():
		printerr("FAIL: damage capture guardian missing after preparation")
		quit(1)
		return
	var boss_actor = bosses[0]
	game.player.position = Vector2(boss_actor.position.x + 256, boss_actor.position.y + T.BOSS_SIZE.y / 2 - T.PLAYER_SIZE.y / 2)
	game._update_camera(0.0, true)
	game._update_exploration()
	game.ui.update_hud()
	if not await wait_until(func(): return is_instance_valid(game.boss) and game.boss == boss_actor):
		printerr("FAIL: damage capture visible boss detection timed out")
		quit(1)
		return
	boss_actor.receive_hit(1 - boss_actor.polarity, 4)
	boss_actor.tick_visuals(0.2)
	await frames(10)
	await capture("boss_hp_and_damage")
	game.queue_free()
	await frames(2)
	print("DAMAGE DISPLAY CAPTURES: builds/qa/seamless/damage/")
	quit()
