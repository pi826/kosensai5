extends SceneTree
const Main := preload("res://scripts/main.gd")
const T := preload("res://scripts/tuning.gd")
const OUTPUT := "res://builds/qa/caves/"
var game: Node2D
var capture_failures := 0

func _initialize() -> void:
	call_deferred("run")

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(OUTPUT + name + ".png")
	if result != OK:
		capture_failures += 1
		printerr("CAPTURE FAILED: ", name, " ", error_string(result))

func floor_position(x: float) -> Vector2:
	var rooms: Array = game.stage.chambers.filter(func(r):return r.kind!='normal')
	rooms.sort_custom(func(a,b):return absf(a.rect.get_center().x-x)<absf(b.rect.get_center().x-x))
	var r: Rect2 = rooms[0].rect
	return Vector2(clampf(x,r.position.x+64,r.end.x-64),r.end.y-22)
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
	await capture("key_settings_top")
	game.ui.settings_panel._buttons["aim_cycle"][0].grab_focus()
	await frames(4)
	await capture("key_settings_aim")
	game.ui.settings_panel._buttons["pause_game"][0].grab_focus()
	await frames(4)
	await capture("key_settings")
	game.close_key_settings()
	game.start_run(37)
	await frames(6)
	await capture("start")
	await capture_caves()
	show_position(game.stage.chambers.filter(func(r):return r.band==0)[0].approaches[0])
	await frames(3)
	await capture("upper_path")
	for biome in range(3):
		var room: Dictionary = game.stage.chambers.filter(func(r):return r.region==biome and r.kind=='boss')[0]
		var point := Vector2(room.rect.get_center().x,room.rect.end.y-22)
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
	show_position(bosses[0].position+Vector2(160,T.BOSS_SIZE.y/2-22))
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
	await capture_phase3_enemies()
	await capture_changing_terrain()
	await capture_controls()
	print("VISUAL CAPTURES: builds/qa/caves/")
	game.queue_free()
	await frames(2)
	quit(0 if capture_failures == 0 else 1)

func capture_controls() -> void:
	game.start_run(37)
	await frames(3)
	await capture("controls_help")
	# Clear air west of the central shelves keeps all three shots in flight.
	var room: Dictionary = game.stage.chambers.filter(func(r):return r.kind=='boss')[0]
	var shot_position := Vector2.ZERO
	for x in range(int(room.rect.position.x)+160,int(room.rect.end.x)-160,32):
		var point := Vector2(x,room.rect.end.y-256)
		if T.AIM_ANGLES.all(func(a):return preload('res://scripts/stage_generator.gd')._segment_clear(point,point+Vector2.RIGHT.rotated(-deg_to_rad(a))*96,game.stage.solids)):
			shot_position=point
			break
	show_position(shot_position)
	game.elapsed = 10
	for actor in get_nodes_in_group("enemies"):
		actor.hide()
	for index in range(T.AIM_ANGLES.size()):
		game.player.aim_index = index
		game.player.queue_redraw()
		game.ui.update_hud()
		var bullet = game.spawn_bullet(game.player, game.player.shot_direction())
		await frames(5)
		if not is_instance_valid(bullet):
			capture_failures += 1
			printerr("CAPTURE FAILED: angle projectile hit terrain before capture")
			continue
		bullet.set_physics_process(false)
		await capture("angle_%d" % int(T.AIM_ANGLES[index]))
		bullet.free()
	var enemies: Array = get_nodes_in_group("enemies").filter(func(actor): return actor.kind != "boss")
	for index in range(3):
		var enemy = enemies[index]
		enemy.show()
		enemy.position = game.player.position + [Vector2(150, -140), Vector2(280, -50), Vector2(410, -140)][index]
		enemy.polarity = 1
		enemy.queue_redraw()
	game.player.aim_index = 0
	game.player.gauge = 5
	game.player.queue_redraw()
	await frames(3)
	await capture("lock_on_preview")
	game.fire_special(game.player, game.player.take_gauge())
	await frames(6)
	for missile in game.projectiles.get_children():
		missile.set_physics_process(false)
	await capture("lock_on_flight")

func capture_phase3_enemies() -> void:
	game.start_run(37)
	await frames(3)
	var flyer = get_nodes_in_group("enemies").filter(func(actor): return actor.kind == "flyer")[0]
	var spawn: Dictionary = game.stage.spawns.filter(func(e):return e.id==flyer.spawn_id)[0]
	var points: Array = game.stage.chambers[spawn.chamber_id].approaches.duplicate()
	points.sort_custom(func(a,b):return a.distance_to(flyer.position+Vector2(-160,176))<b.distance_to(flyer.position+Vector2(-160,176)))
	show_position(points[0])
	await frames(3)
	await capture("phase3_flyer")
	# A clear floor section keeps both the complete arc and the lens in view.
	var laser_floor := floor_position(9600)
	show_position(laser_floor)
	var laser = get_nodes_in_group("enemies").filter(func(actor): return actor.kind == "laser")[0]
	laser.position = laser_floor+Vector2(300,0)
	laser.polarity = 1
	laser.facing = -1
	laser.action = "windup_laser"
	laser.action_remaining = T.LASER_WARNING
	laser.queue_redraw()
	var beam = game.spawn_laser(laser)
	beam.set_physics_process(false)
	await frames(3)
	await capture("phase3_laser_warning")
	laser.action = "firing_laser"
	laser.queue_redraw()
	beam.fire()
	await frames(3)
	await capture("phase3_laser_beam")

func capture_changing_terrain() -> void:
	game.start_run(37)
	await frames(3)
	var block: Rect2 = game.stage.breakables[0]
	show_position(block.get_center()+Vector2(-160,-48))
	for actor in get_nodes_in_group("enemies"):
		actor.hide()
	await frames(3)
	await capture("phase3_breakable")
	# Keep a natural floor section and relocate actors for a readable QA fixture.
	var battle := floor_position(4224)
	show_position(battle)
	var breaker = get_nodes_in_group("enemies").filter(func(actor): return actor.kind == "breaker")[0]
	var builder = get_nodes_in_group("enemies").filter(func(actor): return actor.kind == "builder")[0]
	breaker.show()
	builder.show()
	breaker.position = battle+Vector2(-240,0)
	breaker.polarity = 1
	breaker.action = "windup_bomb"
	breaker.queue_redraw()
	builder.position = battle+Vector2(240,0)
	builder.action = "windup_build"
	builder.wall_plan = game.terrain.find_wall_plan(builder, game.player)
	builder.queue_redraw()
	var warning = game.spawn_bomb_warning(breaker)
	warning.set_physics_process(false)
	await frames(3)
	await capture("phase3_terrain_warning")
	var planned: Rect2 = builder.wall_plan
	if planned.has_area():
		game.terrain.place_wall(planned, builder.get_instance_id())
	builder.action = "idle"
	builder.queue_redraw()
	breaker.action = "idle"
	breaker.queue_redraw()
	warning.fire()
	warning.set_physics_process(true)
	await frames(22)
	if is_instance_valid(warning): warning.set_physics_process(false)
	# A separate, nearby crater shows both surface rows and refreshed tile edges.
	var surface: Rect2 = game.stage.erodible_surfaces[0]
	var ground := surface.position.y
	game.terrain.explode(Vector2(surface.get_center().x, ground + 32), 64)
	await frames(3)
	await capture("phase3_terrain_changed")

func capture_caves() -> void:
	game.start_run(37)
	show_position(game.stage.start_position)
	await frames(3)
	await capture("cave_start")
	var room: Dictionary = game.stage.chambers.filter(func(r): return r.kind=="normal" and game.stage.spawns.filter(func(e): return e.get("chamber_id",-1)==r.id).size()>=2)[0]
	var clear_points: Array = room.approaches.filter(func(p):return game.stage.spawns.all(func(e):return e.position.distance_to(p)>80) and not preload("res://scripts/stage_generator.gd")._embedded(p,T.PLAYER_SIZE,game.stage.solids+game.stage.breakables))
	clear_points.sort_custom(func(a,b):return a.distance_to(room.rect.get_center())<b.distance_to(room.rect.get_center()))
	show_position(clear_points[0])
	game.camera.position=Vector2(room.rect.get_center().x,room.rect.end.y-224)
	await frames(3)
	await capture("cave_enemies_and_shelves")
	var shaft: Dictionary = game.stage.shafts[0]
	show_position(Vector2(shaft.rect.get_center().x,shaft.rect.position.y-22))
	game.camera.position=Vector2(shaft.rect.get_center().x,shaft.rect.position.y+180)
	await frames(3)
	await capture("cave_shaft_and_mouth")
	var tunnel: Dictionary = game.stage.tunnels.filter(func(e):return game.stage.chambers[e.a].rect.end.y!=game.stage.chambers[e.b].rect.end.y)[0]
	var piece: Rect2 = tunnel.pieces[tunnel.pieces.size()/2]
	show_position(Vector2(piece.get_center().x,piece.end.y-22))
	game.camera.position=tunnel.rect.get_center()
	await frames(3)
	await capture('cave_tunnel')
	await capture('cave_stepped_tunnel')
	var detailed: Dictionary = game.stage.chambers.filter(func(r):return r.kind=='normal' and not r.floor_steps.is_empty() and r.rocks.any(func(rock):return rock.end.y==r.rect.end.y))[0]
	var detail_points: Array = detailed.approaches.filter(func(p):return game.stage.spawns.all(func(e):return e.position.distance_to(p)>80) and not preload("res://scripts/stage_generator.gd")._embedded(p,T.PLAYER_SIZE,game.stage.solids+game.stage.breakables))
	detail_points.sort_custom(func(a,b):return a.y>b.y)
	show_position(detail_points[0])
	game.camera.position=Vector2(detailed.rect.get_center().x,detailed.rect.end.y-224)
	await frames(3)
	await capture('cave_steps_and_rocks')
	for boss: Dictionary in game.stage.spawns.filter(func(e): return e.kind=="boss"):
		show_position(boss.position+Vector2(-160,T.BOSS_SIZE.y/2-22))
		await frames(3)
		await capture("cave_boss_%d" % boss.boss_id)
	# Reveal by visiting chambers and tunnel/shaft mouths through the normal exploration recorder.
	for chamber: Dictionary in game.stage.chambers:
		for point: Vector2 in chamber.approaches: show_position(point)
	for edge: Dictionary in game.stage.tunnels+game.stage.shafts: show_position(edge.rect.get_center())
	show_position(game.stage.start_position)
	await frames(3)
	await capture("cave_explored_minimap")
