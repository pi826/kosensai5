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
		var p: Vector2 = game.player.position
		var c: Vector2 = game.camera.position
		while true:
			for enemy in tree.get_nodes_in_group("enemies"): enemy.set_physics_process(live_enemies.has(enemy))
			game.player.invulnerability = 10000
			if damaged:
				for at: Vector2i in game.stream.loaded:
					if excavated.has(at): continue
					# Exercise the real destruction/collision update path. Radius17 removes
					# one cell, keeping blocks on the standing surfaces intact.
					for cell: Vector2i in game.terrain.sectors[at].surfaces:
						game.terrain.explode((Vector2(cell) + Vector2.ONE * 0.5) * T.TILE_SIZE, 17)
					excavated[at] = true
			await tree.physics_frame
			await tree.process_frame
			if not game.stream.contains_rect(game.view_rect()): incomplete_views += 1
			var at := preload("res://scripts/sector_stream.gd").coord_at(game.player.position)
			if not game.stream.contains_rect(Rect2(Vector2(at-Vector2i.ONE)*T.SECTOR_SIZE,T.SECTOR_SIZE*3)): incomplete_neighbourhoods += 1
			if not game.streaming_wait: break
			held += 1
			if held % 1000 == 0: print("STREAM WAIT ", game.player.position, " camera=", game.camera.position, " loaded=", game.stream.loaded.keys(), " jobs=", game.stream.jobs.keys())
			# Headless fixed-fps runs faster than real time. Give worker CPU time
			# during the production safety hold instead of exhausting route timeouts.
			OS.delay_msec(1)
		if not game.physics_frame_times.is_empty(): physics_ms.append(game.physics_frame_times.back())
		max_player_step = maxf(max_player_step, p.distance_to(game.player.position))
		max_camera_step = maxf(max_camera_step, c.distance_to(game.camera.position))
		frames += 1
		if frames % 1200 == 0: print("TRAVEL ", frames, " position=", game.player.position, " loaded=", game.stream.loaded.size())
