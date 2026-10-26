extends RefCounted
const T := preload("res://scripts/tuning.gd")
## Executes generated commands using the same action input as the player.
var tree: SceneTree
var game: Node2D
var frames := 0
var jumps := 0
var max_player_step := 0.0
var max_camera_step := 0.0
var error := ""
# These route fixtures span only a few sectors. Their planner uses the original
# frame; production physics and durable records never use this absolute vector.
func world_point(node: Node2D) -> Vector2:
	return node.position + Vector2(game.origin_sector) * T.SECTOR_SIZE
func point() -> Vector2:
	return world_point(game.player)
func local(point: Vector2) -> Vector2:
	return point - Vector2(game.origin_sector) * T.SECTOR_SIZE
func tick(count: int = 1):
	for i in range(count):
		for enemy in tree.get_nodes_in_group("enemies"): enemy.set_physics_process(false)
		game.player.invulnerability = 10000
		var p: Vector2 = point()
		var c: Vector2 = world_point(game.camera)
		tree.test_progress()
		await tree.physics_frame
		tree.test_progress()
		await tree.process_frame
		max_player_step = maxf(max_player_step,p.distance_to(point()))
		max_camera_step = maxf(max_camera_step,c.distance_to(world_point(game.camera)))
		frames += 1
func input(action: String, pressed: bool):
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func release():
	for name in ["move_left","move_right","jump","move_down","shoot","special"]: Input.action_release(name)
func steer(x: float, tolerance: float = 2):
	Input.action_release("move_left")
	Input.action_release("move_right")
	if absf(x-point().x)>tolerance: Input.action_press("move_right" if x>point().x else "move_left")
func stop():
	steer(point().x)
	await tick(4)
func floor_wait() -> bool:
	for i in range(180):
		if game.player.is_on_floor(): return true
		await tick()
	error = "landing timeout at %s" % point()
	return false
func walk(x: float) -> bool:
	var limit := int(absf(x-point().x)/320*60)+240
	var jump_timer := 0
	for i in range(limit):
		if absf(x-point().x)<0.8:
			await stop()
			if absf(x-point().x)>=0.8: continue
			input("jump",false)
			return await floor_wait()
		if absf(x-point().x)<12 and absf(game.player.velocity.x)>1:
			await stop()
			continue
		steer(x, 0.5)
		if jump_timer>0:
			jump_timer-=1
			if jump_timer==0: input("jump",false)
		if game.player.is_on_floor() and game.player.is_on_wall() and jump_timer==0:
			input("jump",true)
			jump_timer=40
			jumps+=1
		await tick()
	error="walking to %.1f timed out at %s" % [x,point()]
	return false
func step(command: Dictionary) -> bool:
	error = ""
	if OS.get_cmdline_user_args().has("--trace"): print("STEP ",command," actual ",point())
	if command.action=="walk":
		if not await walk(command.x): return false
		if absf(point().y-command.position.y)>2:
			error="walk reached wrong floor: %s expected %s" % [point(),command.position]
			return false
		return true
	if command.action=="drop":
		if not await walk(command.x): return false
		if not await floor_wait(): return false
	else:
		if not await walk(command.position.x): return false
		if command.action=="jump":
			input("jump",true)
			jumps+=1
		elif command.action=="drop_through": input("move_down",true)
		var launch_position: Vector2 = point()
		var airborne := false
		for i in range(130):
			if command.action == "jump" and i == command.get("hold_frames", 40): input("jump", false)
			steer(command.target.x)
			await tick()
			if OS.get_cmdline_user_args().has("--trace") and command.action=="drop_through" and i<3: print("DROP ",i," ",point()," down ",Input.is_action_pressed("move_down")," drop ",game.player.drop_remaining," coll ",game.player.get_slide_collision_count())
			if not game.player.is_on_floor():
				airborne=true
				if command.action=="drop_through": input("move_down",false)
			elif airborne: break
		if not airborne: error = "never left %s for %s; contacts=%s drop=%s" % [launch_position, command, game.player.get_slide_collision_count(), game.player.drop_remaining]
		input("jump",false)
		input("move_down",false)
		await stop()
		if command.action == "jump" and not await walk(command.target.x): return false
	if point().distance_to(command.target)>10:
		error+="; %s from %s target %s, actual %s" % [command.action,command.position,command.target,point()]
		return false
	return true
func follow(commands: Array) -> bool:
	for command: Dictionary in commands:
		if not await step(command):
			release()
			return false
	return true

static func shaft_fixture(stage: Dictionary, for_fall: bool = false) -> Dictionary:
	var shafts: Array = stage.shafts.duplicate()
	shafts.sort_custom(func(a,b):return a.rect.size.y>b.rect.size.y)
	for shaft: Dictionary in shafts:
		var left: float = shaft.rect.position.x
		var right: float = shaft.rect.end.x
		for shelf: Rect2 in shaft.platforms:
			left=maxf(left,shelf.position.x)
			right=minf(right,shelf.end.x)
		var xs: Array = [(left+right)/2]
		if for_fall:
			xs=[]
			if shaft.rect.size.y<512: continue
			for x in range(int(shaft.rect.position.x)+24,int(shaft.rect.end.x)-23,32): xs.append(float(x))
		for x: float in xs:
			if for_fall and (x<640 or x>11648): continue
			if not stage.solids.any(func(s):return s.size.y!=16 and s.position.y==shaft.rect.end.y and s.position.x<=x-15 and s.end.x>=x+15): continue
			var gap := 0.0
			var previous: float = shaft.rect.position.y
			for shelf: Rect2 in shaft.platforms:
				if x+15<=shelf.position.x or x-15>=shelf.end.x: continue
				gap=maxf(gap,shelf.position.y-previous)
				previous=shelf.position.y
			gap=maxf(gap,shaft.rect.end.y-previous)
			if for_fall and gap<160: continue
			if not for_fall:
				var geometry := preload("res://scripts/stage_generator.gd")
				if not [shaft.rect.position.x-16, shaft.rect.end.x+16, x].all(func(px): return geometry._supported(Vector2(px,shaft.rect.position.y-22),T.PLAYER_SIZE,stage.solids) and not geometry._embedded(Vector2(px,shaft.rect.position.y-22),T.PLAYER_SIZE,stage.solids)): continue
			return {"shaft":shaft,"x":x}
	return {}
