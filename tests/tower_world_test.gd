extends "res://tests/playthrough.gd"
## Each fixture starts on a real generated surface; all subsequent travel uses input.
const G := preload("res://scripts/stage_generator.gd")
var minimum_bridge_clearance := 0.0
func place(point: Vector2) -> void:
	release_inputs()
	game.player.position = point
	game.player.velocity = Vector2.ZERO
	game._update_camera(0.0, true)
	for tick in range(5): await frame()

func cross_bridge(bridge: Dictionary, reverse: bool, jumping: bool) -> void:
	var rect: Rect2 = bridge.rect
	var from_x := rect.position.x - T.TOWER_WALL - 64 if not reverse else rect.end.x + T.TOWER_WALL + 64
	var to_x := rect.end.x + T.TOWER_WALL + 64 if not reverse else rect.position.x - T.TOWER_WALL - 64
	await place(Vector2(from_x, rect.position.y - T.PLAYER_SIZE.y / 2))
	var sign_x := -1 if reverse else 1
	Input.action_press("move_left" if reverse else "move_right")
	var jumped := false
	var obstacle_jump := 0
	var safe := true
	var steps := int((absf(to_x - from_x) / T.MOVE_SPEED + 3) * 60)
	for tick in range(steps):
		if obstacle_jump > 0:
			obstacle_jump -= 1
			if obstacle_jump == 0: action_event("jump",false)
		if game.player.is_on_floor() and game.player.is_on_wall() and obstacle_jump == 0:
			action_event("jump",true)
			obstacle_jump = 40
		if jumping and not jumped and absf(game.player.position.x - rect.get_center().x) < 48:
			action_event("jump", true)
			jumped = true
		await frame()
		safe = safe and game.player.position.y + T.PLAYER_SIZE.y / 2 <= rect.position.y + 1
		if (game.player.position.x - to_x) * sign_x >= 0: break
	release_inputs()
	check((game.player.position.x - to_x) * sign_x >= 0, "Bridge %d crosses both doorway sills, reverse=%s jump=%s actual=%s target=%s" % [bridge.id,reverse,jumping,game.player.position,to_x])
	check(safe, "Bridge %d never permits a fall beneath its deck" % bridge.id)

func verify_roofs() -> void:
	for tower: Dictionary in game.stage.towers:
		var roof: Rect2 = tower.roof
		var graph := G.navigation_graph(game.stage)
		var bottom := Vector2(tower.platforms[0].get_center().x,T.GROUND_Y - T.PLAYER_SIZE.y / 2)
		var top := Vector2(roof.get_center().x,tower.roof_y - T.PLAYER_SIZE.y / 2)
		await place(bottom)
		var ascent := G.path_steps(graph,G.node_at(graph,bottom),G.node_at(graph,top),top)
		check(not ascent.is_empty(), "Vertical-wall tower has a bottom-to-roof route")
		if not ascent.is_empty(): check(await follow_steps(ascent), "Tower %d climbs from bottom around real solid inner walls using input" % tower.id)
		# Descend immediately after the ascent, without resetting position or world.
		var origin := G.node_at(graph,game.player.position + Vector2(0,0.075))
		var descent := G.path_steps(graph,origin,G.node_at(graph,bottom),bottom)
		check(not descent.is_empty(), "Roof hatch has a descent route")
		if not descent.is_empty(): check(await follow_steps(descent), "Tower %d roof hatch returns to the floor continuously after climbing" % tower.id)
		for direction in [-1,1]:
			await place(Vector2(roof.get_center().x,tower.roof_y - T.PLAYER_SIZE.y / 2))
			action_event("jump",true)
			Input.action_press("move_left" if direction < 0 else "move_right")
			var contained := true
			for tick in range(100):
				await frame()
				# Falling through a hatch may later leave through a legitimate bridge.
				# Check escape over the parapet while the body is still at roof height.
				if game.player.position.y + T.PLAYER_SIZE.y / 2 <= tower.roof_y + 1:
					contained = contained and game.player.position.x - T.PLAYER_SIZE.x / 2 >= tower.interior.position.x - 1 and game.player.position.x + T.PLAYER_SIZE.x / 2 <= tower.interior.end.x + 1
			release_inputs()
			check(contained, "Tower %d parapet prevents escape in direction %d" % [tower.id,direction])

func verify_excavated_escape() -> void:
	var tower: Dictionary = game.stage.towers.filter(func(t): return not t.start and not t.boss)[0]
	for x in range(int(tower.interior.position.x),int(tower.interior.end.x),32):
		game.terrain.explode(Vector2(x + 16,T.GROUND_Y + 32),64)
	var fully_removed := true
	for x in range(int(tower.interior.position.x / 32),int(tower.interior.end.x / 32)):
		for y in [int(T.GROUND_Y / 32),int(T.GROUND_Y / 32) + 1]:
			fully_removed = fully_removed and not game.terrain.occupied.has(Vector2i(x,y))
	check(fully_removed,"Excavated fixture removes every unprotected bottom tile to maximum depth")
	var door: Dictionary = tower.entrances[0]
	var bridge: Rect2 = game.stage.bridges[door.bridge_id].rect
	var outside := Vector2(bridge.get_center().x,bridge.position.y - T.PLAYER_SIZE.y / 2)
	await place(outside)
	var graph := G.navigation_graph(game.stage,true)
	var bottom := Vector2(tower.platforms[0].get_center().x,T.GROUND_Y + T.SURFACE_DEPTH - T.PLAYER_SIZE.y / 2)
	var descent := G.path_steps(graph,G.node_at(graph,outside),G.node_at(graph,bottom),bottom)
	check(not descent.is_empty() and await follow_steps(descent),"Enter an excavated tower from its bridge and descend using real input")
	check(absf(game.player.position.y - bottom.y) < 2 and game.player.is_on_floor(),"Player actually stands on the bottom 64 pixels below the original floor")
	var first: Rect2 = tower.platforms[0]
	var target := Vector2(first.get_center().x,first.position.y - T.PLAYER_SIZE.y / 2)
	var ascent := G.path_steps(graph,G.node_at(graph,bottom),G.node_at(graph,target),target)
	var before_jumps := jumps
	check(not ascent.is_empty() and await follow_steps(ascent),"Ordinary held jump climbs from the excavated bottom to the first platform")
	check(jumps > before_jumps and absf(game.player.position.y - target.y) < 2,"Excavated-floor escape includes a real 160-pixel jump and landing")
	var exit_steps := G.path_steps(graph,G.node_at(graph,target),G.node_at(graph,outside),outside)
	check(not exit_steps.is_empty() and await follow_steps(exit_steps),"Climb out through the doorway and return to the external bridge using input")
	check(bridge.position.x < game.player.position.x and game.player.position.x < bridge.end.x,"Excavated escape ends outside the tower on its bridge")

func verify_obstacles() -> void:
	var bridge: Rect2 = game.stage.bridges[0].rect
	var x := floorf(bridge.get_center().x / 32) * 32
	await place(Vector2(x + 200,bridge.position.y - T.PLAYER_SIZE.y / 2))
	var builder = get_nodes_in_group("enemies").filter(func(e): return e.kind == "builder")[0]
	var previous_position: Vector2 = builder.position
	builder.position = Vector2(x - 160,bridge.position.y - T.ENEMY_SIZE.y / 2)
	var bridge_plan: Rect2 = game.terrain.find_wall_plan(builder,game.player)
	check(bridge_plan.has_area() and game.terrain.confirm_wall_plan(bridge_plan,builder,game.player), "Builder planning and warning revalidation accept a thin bridge support")
	builder.position = previous_position
	await place(Vector2(x - 160,bridge.position.y - T.PLAYER_SIZE.y / 2))
	var plan := Rect2(x,bridge.position.y - 96,32,96)
	var wall: int = game.terrain.place_wall(plan,9901)
	check(wall >= 0, "Builder wall can stand on a permanent thin bridge")
	if wall >= 0:
		check(await walk_to(x + 128), "Actual held jump input passes installed bridge wall")
		check(game.player.position.y + T.PLAYER_SIZE.y / 2 <= bridge.position.y + 1, "Wall crossing cannot drop beneath bridge")
		game.terrain.remove_wall(wall)
	# Add a legal block to this generated bridge, then rebuild its real collisions.
	var block := Rect2(x,bridge.position.y - 64,32,64)
	check(G.doorway_clearance(game.stage,block), "Bridge block is clear of entrance protection")
	var obstacle_fixture: Dictionary = game.stage.duplicate(true)
	# This deliberately tests an obstacle on the reserved walking corridor.
	# Generation keeps that corridor free, so clear only fixture reservations.
	obstacle_fixture.routes = []
	obstacle_fixture.spawns = []
	obstacle_fixture.breakables = []
	check(G.block_is_valid(block,obstacle_fixture), "Thin bridge supports a legal block outside navigation reservations")
	game.terrain.stage = game.stage.duplicate(true)
	game.terrain.stage.breakables.append(block)
	game.terrain.rebuild()
	await place(Vector2(x - 160,bridge.position.y - T.PLAYER_SIZE.y / 2))
	check(await walk_to(x + 128), "Actual jump input crosses a bridge block")
	check(game.player.position.y + T.PLAYER_SIZE.y / 2 <= bridge.position.y + 1, "Block crossing cannot drop beneath bridge")
	# Confirm the block can also be removed through the player projectile path.
	await place(Vector2(x - 128,bridge.position.y - T.PLAYER_SIZE.y / 2))
	game.player.facing = 1
	for shot in range(3):
		game.spawn_bullet(game.player,Vector2.RIGHT)
		for tick in range(15): await frame()
	check(not game.terrain.block_cells.has(Vector2i(int(x / 32), int((bridge.position.y - 32) / 32))), "Player bullets destroy a bridge block")
	for tower: Dictionary in game.stage.towers:
		for door: Dictionary in tower.entrances:
			var forbidden := Rect2(door.rect.position.x - 32,door.y - 64,32,64)
			check(not game.terrain.can_place_wall(forbidden,999), "Builder cannot block doorway or its approach")
	var before: Dictionary = game.terrain.occupied.duplicate()
	# Breakable objects remain destructible even when their supporting floor is
	# protected. Compare only the permanent tiles here.
	for cell: Vector2i in game.terrain.block_cells: before.erase(cell)
	for wall_rect: Rect2 in game.stage.inner_walls: game.terrain.explode(wall_rect.get_center(),64)
	for link: Dictionary in game.stage.bridges: game.terrain.explode(link.rect.get_center(),64)
	for tower: Dictionary in game.stage.towers:
		game.terrain.explode(Vector2(tower.outer.position.x + 32,tower.roof_y),96)
		game.terrain.explode(tower.roof.get_center(),96)
		if tower.start or tower.boss:
			game.terrain.explode(Vector2(tower.floor.get_center().x,T.GROUND_Y + 32),160)
	var after: Dictionary = game.terrain.occupied.duplicate()
	for cell: Vector2i in game.terrain.block_cells: after.erase(cell)
	check(after == before, "Breaker cannot destroy bridge, exterior/interior walls, roof or protected tower floor")

func run() -> void:
	game = Main.new()
	game.controls_path = "res://builds/qa/towers/tower_controls.cfg"
	root.add_child(game)
	game.key_bindings.reset_defaults()
	for seed_value in [1,37,2026]:
		game.start_run(seed_value)
		for bridge: Dictionary in game.stage.bridges:
			for reverse in [false,true]:
				await cross_bridge(bridge,reverse,false)
				await cross_bridge(bridge,reverse,true)
	game.start_run(37)
	# Isolate permanent geometry here; intact generated blocks are covered by
	# playthrough, and input-based bridge obstacle crossing is tested below.
	for block: Rect2 in game.stage.breakables: game.terrain.damage_at(block.get_center(),T.TERRAIN_HP)
	await verify_excavated_escape()
	game.start_run(37)
	for block: Rect2 in game.stage.breakables: game.terrain.damage_at(block.get_center(),T.TERRAIN_HP)
	await verify_roofs()
	await verify_obstacles()
	release_inputs()
	game.queue_free()
	await physics_frame
	print("TOWER WORLD TEST: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
