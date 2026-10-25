extends SceneTree
const Main := preload("res://scripts/main.gd")
const T := preload("res://scripts/tuning.gd")
const OUTPUT := "res://builds/qa/towers/"
var game: Node2D
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func frames(count: int) -> void:
	for tick in range(count):
		await physics_frame
		await process_frame
func capture(name: String) -> void:
	await frames(3)
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(OUTPUT + name + ".png")
	if result != OK: failures += 1
	print("CAPTURE ", name, " result=", result)
func show_position(point: Vector2) -> void:
	game.player.position = point
	game.player.velocity = Vector2.ZERO
	game.player.set_physics_process(false)
	for actor in get_nodes_in_group("enemies"): actor.set_physics_process(false)
	game.camera.zoom = Vector2.ONE
	game._update_camera(0.0,true)
	game._update_exploration()
	game.ui.update_hud()
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	game = Main.new()
	game.controls_path = OUTPUT + "visual_controls.cfg"
	root.add_child(game)
	game.start_run(37)
	game.set_physics_process(false)
	show_position(game.stage.start_position)
	await capture("tower_start_interior")
	var start_tower: Dictionary = game.stage.towers[T.TOWER_START_ID]
	var verticals: Array = game.stage.inner_walls.filter(func(w): return w.size.y >= T.INNER_WALL_MIN_HEIGHT)
	verticals.sort_custom(func(a,b): return a.size.y > b.size.y)
	var inner_wall: Rect2 = verticals[0]
	var wall_tower: Dictionary = game.stage.towers.filter(func(t): return t.interior.encloses(inner_wall))[0]
	var below: Rect2 = wall_tower.platforms.filter(func(p): return p.position.y > inner_wall.position.y)[-1]
	show_position(Vector2(below.get_center().x,below.position.y - T.PLAYER_SIZE.y / 2))
	await capture("varied_platforms_inner_wall")
	var door: Dictionary = start_tower.entrances[0]
	show_position(Vector2(door.landing.get_center().x,door.y - T.PLAYER_SIZE.y / 2))
	game.camera.position.x = door.rect.get_center().x
	await capture("tower_door_landing")
	var crowded: Array = game.stage.bridges.filter(func(b): return game.stage.spawns.filter(func(s): return s.kind != "boss" and s.support == b.rect).size() >= 2)
	crowded.sort_custom(func(a,b): return a.rect.size.x > b.rect.size.x)
	var bridge: Rect2 = crowded[0].rect
	show_position(Vector2(bridge.get_center().x - 160,bridge.position.y - T.PLAYER_SIZE.y / 2))
	game.camera.position.x = bridge.get_center().x
	await capture("suspension_bridge_enemy")
	var overview_tower: Dictionary = game.stage.towers[3]
	show_position(Vector2(overview_tower.roof.get_center().x - 96,overview_tower.roof_y - T.PLAYER_SIZE.y / 2))
	game.camera.zoom = Vector2(0.45,0.45)
	game.camera.position = Vector2(4096,1300)
	await capture("tower_exteriors")
	var boss: Dictionary = game.stage.spawns.filter(func(s): return s.kind == "boss")[0]
	var tower: Dictionary = game.stage.towers[boss.tower_id]
	show_position(Vector2(tower.roof.get_center().x - 128,tower.roof_y - T.PLAYER_SIZE.y / 2))
	await capture("guardian_roof")
	game.elapsed = 20
	for route: Dictionary in game.stage.routes:
		for step: Dictionary in route.outward + route["return"]:
			if step.has("position"): show_position(step.position)
	for landmark: Dictionary in game.stage.landmarks:
		show_position(landmark.position)
	show_position(game.stage.start_position)
	await capture("explored_minimap")
	game.show_menu("paused")
	await capture("paused")
	game.open_key_settings()
	await capture("key_settings")
	game.close_key_settings()
	game.show_menu("title")
	await capture("title")
	game.queue_free()
	await frames(2)
	print("TOWER VISUAL CAPTURES: 10 captures, ",failures," failures")
	quit(0 if failures == 0 else 1)
