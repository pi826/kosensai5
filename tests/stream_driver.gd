extends "res://tests/cave_driver.gd"
var damaged := false
var excavated := {}
var unloaded_seen := 0
var incomplete_views := 0
var incomplete_neighbourhoods := 0
var physics_ms: Array[float] = []
var held := 0
var live_enemies: Array = []

func tick(count: int = 1):
	for i in range(count):
		var p: Vector2 = point()
		var c: Vector2 = world_point(game.camera)
		var deadline := Time.get_ticks_msec() + 30000
		while true:
			if Time.get_ticks_msec() >= deadline:
				error = "stream preparation exceeded 30 seconds at %s" % point()
				return
			for enemy in tree.get_nodes_in_group("enemies"): enemy.set_physics_process(live_enemies.has(enemy))
			game.player.invulnerability = 10000
			if damaged:
				for at: Vector2i in game.stream.loaded:
					if excavated.has(at): continue
					# Exercise the real destruction/collision update path. Radius17 removes
					# one cell, keeping blocks on the standing surfaces intact.
					for cell: Vector2i in game.terrain.sectors[at].surfaces:
						game.terrain.explode(game.terrain.pixel_of_cell(cell) + Vector2.ONE * T.TILE_SIZE * 0.5, 17)
					excavated[at] = true
			tree.test_progress()
			await tree.physics_frame
			tree.test_progress()
			await tree.process_frame
			if not game.stream.contains_rect(game.view_rect()): incomplete_views += 1
			var at: Vector2i = game.stream.sector_at(game.player.position)
			if not game.stream.contains_rect(Rect2(game.stream.sector_offset(at-Vector2i.ONE),T.SECTOR_SIZE*3)): incomplete_neighbourhoods += 1
			if not game.streaming_wait: break
			held += 1
			if held % 1000 == 0: print("STREAM WAIT ", point(), " camera=", world_point(game.camera), " loaded=", game.stream.loaded.keys(), " jobs=", game.stream.jobs.keys())
			# Headless fixed-fps runs faster than real time. Give worker CPU time
			# during the production safety hold instead of exhausting route timeouts.
			OS.delay_msec(1)
		if not game.physics_frame_times.is_empty(): physics_ms.append(game.physics_frame_times.back())
		if p.distance_to(point()) > 25: print("LARGE STEP ", p, " -> ", point(), " origin=", game.origin_sector, " velocity=", game.player.velocity)
		max_player_step = maxf(max_player_step, p.distance_to(point()))
		max_camera_step = maxf(max_camera_step, c.distance_to(world_point(game.camera)))
		frames += 1
		if frames % 1200 == 0: print("TRAVEL ", frames, " position=", point(), " loaded=", game.stream.loaded.size())
