extends "res://tests/ability_physics_test.gd"
const Tutorial := preload("res://scripts/tutorial.gd")
const Enemy := preload("res://scripts/enemy.gd")

func tap(action: String) -> void:
	input(action, true)
	input(action, false)

func room(thin: bool = false) -> void:
	await reset(0, false)
	fixture(Rect2(-500,1000,4000,96))
	fixture(Rect2(-500,304,4000,96))
	if thin: fixture(Rect2(400,700,300,16),true)
	game.player.position = Vector2(0,978)
	game.player.velocity = Vector2.ZERO
	await frames(4)

func jump_height() -> float:
	var start: float = game.player.position.y
	var maximum := 0.0
	input("jump",true)
	for i in range(90):
		await frames()
		maximum = maxf(maximum, absf(game.player.position.y-start))
		if i>2 and game.player.is_on_floor(): break
	input("jump",false)
	return maximum

func flip_tests() -> void:
	await room()
	var normal := await jump_height()
	await frames(2)
	# Include buffers and active drop state to verify flip cancellation.
	game.player.jump_buffer = T.JUMP_BUFFER
	game.player.coyote = T.COYOTE_TIME
	game.player.drop_remaining = 0.2
	game.player.drop_clear_y = 2000
	tap("gravity_flip")
	await frames()
	check(game.player.gravity_sign==-1 and game.player.up_direction==Vector2.DOWN and game.player.velocity.y<0,"short flip tap reverses gravity and starts falling up")
	check(not game.player.flip_ready and game.player.coyote==0 and game.player.jump_buffer==0 and game.player.drop_remaining==0 and not game.player.gliding,"flip clears coyote, buffer, drop and glide")
	check(not game.player.collision_mask & T.PLATFORM_LAYER,"inversion removes only thin platform collision")
	check(game.player.collision_mask & 1 and game.player.collision_mask & T.WALL_LAYER,"inversion retains solid and wall collision")
	await frames(5)
	tap("gravity_flip")
	await frames()
	check(game.player.gravity_sign==-1 and not game.player.flip_ready,"second airborne flip is rejected")
	await frames(90)
	check(game.player.is_on_floor() and game.player.up_direction==Vector2.DOWN and absf(game.player.position.y-422)<0.2,"upward fall lands beneath solid ceiling at underside plus 22")
	check(game.player.flip_ready,"ceiling landing recharges flip")
	var reverse := await jump_height()
	check(absf(reverse-normal)<0.5,"ceiling jump has symmetric maximum displacement within 0.5 px")
	game.player.aim_index=1
	check(game.player.shot_direction().y>0,"inverted up aim points screen-down")
	tap("gravity_flip")
	await frames()
	check(game.player.gravity_sign==1 and game.player.up_direction==Vector2.UP and game.player.shot_direction().y<0,"landing permits another flip and restores normal aim")
	await frames(90)
	check(game.player.is_on_floor() and absf(game.player.position.y-978)<0.2,"normal gravity returns to floor")
	# Flip while dashing cancels the dash and does not refund it in midair.
	await reset(T.ABILITY_DASH,false)
	input("dash",true)
	await frames(2)
	tap("gravity_flip")
	await frames()
	check(game.player.gravity_sign==-1 and game.player.dash_remaining==0 and game.player.air_dash_used,"airborne flip cancels dash without refund")
	await reset(T.ABILITY_GLIDE,false)
	input("jump",true)
	await frames(3)
	check(game.player.gliding,"glide fixture is active before flip")
	tap("gravity_flip")
	await frames()
	check(not game.player.gliding and game.player.gravity_sign==-1,"flip cancels active glide")
	input("jump",false)
	await reset(T.ABILITY_GLIDE,false)
	game.player.velocity=Vector2(0,-400)
	input("jump",true)
	tap("gravity_flip")
	await frames()
	check(not game.player.gliding and game.player.velocity.y < -T.GLIDE_FALL_SPEED,"flip frame clears glide even when held jump and new local velocity allow falling")
	await frames()
	check(game.player.gliding and game.player.velocity.y == -T.GLIDE_FALL_SPEED,"held jump can resume inverted glide on following frame")
	input("jump",false)

func platform_tests() -> void:
	await room(true)
	game.player.position=Vector2(500,620)
	game.player.velocity=Vector2.ZERO
	await frames(30)
	check(game.player.is_on_floor() and absf(game.player.position.y-678)<0.2,"normal gravity lands on thin platform from above")
	tap("gravity_flip")
	await frames()
	input("move_down",true)
	await frames(6)
	check(game.player.drop_remaining==0 and game.player.gravity_sign==-1,"down key does not initiate drop during inversion")
	input("move_down",false)
	# Place below the platform and follow a continuous upward crossing.
	game.player.position=Vector2(500,820)
	game.player.velocity=Vector2.ZERO
	await frames(65)
	check(game.player.is_on_floor() and absf(game.player.position.y-422)<0.2,"inverted upward fall passes through thin platform")
	# A downward impulse crosses the same platform while gravity is still up.
	game.player.position=Vector2(500,600)
	game.player.velocity=Vector2(0,900)
	await frames(15)
	check(game.player.position.y>738 and game.player.gravity_sign==-1 and not game.player.is_on_floor(),"inverted downward movement also passes through thin platform")
	await frames(100)
	check(game.player.is_on_floor() and absf(game.player.position.y-422)<0.2,"inverted body returns through platform to ceiling")
	tap("gravity_flip")
	await frames(90)
	check(game.player.is_on_floor() and absf(game.player.position.y-678)<0.2 and game.player.collision_mask & T.PLATFORM_LAYER,"normal gravity restores thin platform landing")

func dash_tests() -> void:
	var cases := [
		{"actions":["move_up"],"vector":Vector2.UP},
		{"actions":["move_down"],"vector":Vector2.DOWN},
		{"actions":["move_left"],"vector":Vector2.LEFT},
		{"actions":["move_right"],"vector":Vector2.RIGHT},
		{"actions":[],"vector":Vector2.LEFT},
		# Task 9D: diagonals replace the old vertical priority.
		{"actions":["move_up","move_right"],"vector":Vector2(1,-1).normalized()},
		{"actions":["move_down","move_left"],"vector":Vector2(-1,1).normalized()},
	]
	for sample: Dictionary in cases:
		await reset(T.ABILITY_DASH | T.ABILITY_GLIDE,false)
		game.player.velocity=Vector2.ZERO
		game.player.facing=-1
		for action: String in sample.actions: input(action,true)
		input("jump",true)
		var start: Vector2=game.player.position
		tap("dash")
		await frames()
		check(game.player.dash_vector.is_equal_approx(sample.vector) and game.player.velocity.is_equal_approx(sample.vector*T.AIR_DASH_SPEED),"eight screen directions: %s" % [sample.actions])
		check(not game.player.gliding and game.player.air_dash_used,"dash suppresses glide and consumes aerial use: %s" % [sample.actions])
		var count:=1
		while game.player.dash_remaining>0 and count<20:
			await frames()
			count+=1
		check(count==ceili(T.AIR_DASH_TIME*60) and (game.player.position-start).distance_to(sample.vector*176)<0.2,"dash time and displacement: %s" % [sample.actions])
		var expected_y: float=T.MAX_FALL_SPEED*sample.vector.y if sample.vector.y>0 else 0.0
		check(is_equal_approx(game.player.velocity.y,expected_y),"dash exit screen-y velocity: %s" % [sample.actions])
		var expected_x: float=Input.get_axis("move_left","move_right")*game.player.move_speed()
		check(is_equal_approx(game.player.velocity.x,expected_x),"dash exit horizontal input speed: %s" % [sample.actions])
		tap("dash")
		await frames()
		check(game.player.dash_remaining==0 and game.player.air_dash_used,"second dash rejected before landing: %s" % [sample.actions])
	await reset(0,false)
	game.player.velocity=Vector2.ZERO
	tap("dash")
	tap("jump")
	await frames()
	check(not game.player.air_dash_used and game.player.dash_remaining==0 and game.player.velocity.y>0,"without abilities dash and airborne jump have no impulse")
	await reset(T.ABILITY_DASH,false)
	game.player.velocity=Vector2(0,100)
	input("jump",true)
	await frames()
	check(game.player.velocity.y>100,"airborne jump stays inert even with dash unlocked")
	await reset(T.ABILITY_DASH,false)
	fixture(Rect2(-100,208,200,32))
	input("move_up",true)
	tap("dash")
	await frames()
	for i in range(6):
		if game.player.dash_remaining<=0: break
		await frames()
	check(game.player.is_on_ceiling() and game.player.dash_remaining==0 and game.player.velocity.y==0,"ceiling impact ends upward dash")
	await reset(T.ABILITY_DASH,false)
	fixture(Rect2(70,-100,32,1000))
	input("move_right",true)
	tap("dash")
	await frames(6)
	check(game.player.is_on_wall() and game.player.dash_remaining==0,"wall impact ends side dash")
	await reset(T.ABILITY_DASH,false)
	fixture(Rect2(-100,400,200,32))
	input("move_down",true)
	tap("dash")
	await frames(6)
	check(game.player.is_on_floor() and game.player.dash_remaining==0,"floor impact ends downward dash")
	await reset(T.ABILITY_DASH,false)
	tap("gravity_flip")
	await frames()
	game.player.velocity=Vector2.ZERO
	var inverted_start: Vector2=game.player.position
	input("move_up",true)
	tap("dash")
	await frames(11)
	check(game.player.gravity_sign==-1 and game.player.dash_vector==Vector2.UP and absf(game.player.position.y-inverted_start.y+176)<0.2,"inverted up dash still moves toward screen-up")
	check(game.player.velocity.y==-T.MAX_FALL_SPEED,"inverted up dash exits at gravity-direction maximum fall speed")
	await reset(T.ABILITY_DASH)
	input("jump",true)
	await frames(8)
	tap("dash")
	await frames(90)
	check(game.player.is_on_floor() and not game.player.air_dash_used,"landing restores dash use")
	input("jump",false)

func real_main_tests() -> void:
	for action in ["jump","dash","move_up","move_down","move_left","move_right"]: input(action,false)
	if is_instance_valid(game): game.free()
	game=Main.new()
	game.controls_path="user://task9b_gravity_controls.cfg"
	root.add_child(game)
	game.key_bindings.reset_defaults()
	game.start_run(37)
	game.streaming_enabled=false
	# Isolate enemy gravity from combat without changing their physics processing.
	game.player.polarity=0
	var walkers: Array=get_nodes_in_group("enemies").filter(func(e): return e.get_parent()==game.world and e.kind=="walker")
	check(not walkers.is_empty(),"real Main spawns ground walkers")
	var actors: Array=[]
	for actor in walkers.slice(0,2):
		actor.polarity=0
		actor.gauge=0
		actors.append(actor)
	await frames(20)
	var supported=get_nodes_in_group("enemies").filter(func(e): return e.get_parent()==game.world and e.kind=="walker" and e.is_on_floor())
	check(not supported.is_empty(),"real Main has a walker standing on the floor")
	# Independent open patch in the same real Main world, away from generated rock.
	fixture(Rect2(-500,10000,1000,96))
	var grounded_enemy:=Enemy.new()
	grounded_enemy.game=game
	grounded_enemy.kind="walker"
	grounded_enemy.polarity=0
	grounded_enemy.position=Vector2(0,9978)
	grounded_enemy.patrol=Vector2(-200,200)
	game.world.add_child(grounded_enemy)
	var falling_enemy:=Enemy.new()
	falling_enemy.game=game
	falling_enemy.kind="walker"
	falling_enemy.polarity=0
	falling_enemy.position=Vector2(100,9500)
	falling_enemy.patrol=Vector2(-200,200)
	game.world.add_child(falling_enemy)
	# Keep both inside their normal activation range.
	game.player.position=Vector2(0,9700)
	game.player.velocity=Vector2.ZERO
	game.player.invulnerability=100
	game._update_camera(0,true)
	await frames(3)
	var ground_y: float=grounded_enemy.position.y
	var air_y: float=falling_enemy.position.y
	tap("gravity_flip")
	await frames()
	game.ui.update_hud()
	check(game.player.gravity_sign==-1 and game.ui.gravity_label.visible and game.ui.gravity_label.text=="重力反転中","HUD displays inversion only while inverted")
	var focus: Vector2 = game.camera_target(0,true)
	game.player.velocity.y=-T.MAX_FALL_SPEED
	focus=game.camera_target(0,true)
	check(absf(focus.y-(game.player.position.y-T.CAMERA_VERTICAL_OFFSET-T.CAMERA_FALL_LOOK_AHEAD))<0.01,"camera looks screen-up during inverted gravity fall")
	game.player.velocity.y=T.MAX_FALL_SPEED
	focus=game.camera_target(0,true)
	check(absf(focus.y-(game.player.position.y-T.CAMERA_VERTICAL_OFFSET))<0.01,"camera ignores velocity against inverted gravity")
	game.player.velocity.y=0
	var actual_player: CharacterBody2D=game.player
	var dummy:=CharacterBody2D.new()
	game.world.add_child(dummy)
	game.player=dummy
	dummy.velocity.y=T.MAX_FALL_SPEED
	focus=game.camera_target(0,true)
	check(absf(focus.y-(dummy.position.y-T.CAMERA_VERTICAL_OFFSET+T.CAMERA_FALL_LOOK_AHEAD))<0.01,"camera defaults to normal gravity for player without gravity_sign")
	game.player=actual_player
	dummy.free()
	check(game.ui.controls_label.text.contains("方向＋") and game.ui.controls_label.text.contains("重力反転") and game.ui.controls_label.get_minimum_size().y<=game.ui.controls_label.size.y,"updated controls fit footer height")
	check(not game.ui.gravity_label.get_rect().intersects(game.ui.boss_arrow_label.get_rect()) and not game.ui.gravity_label.get_rect().intersects(game.ui.minimap.get_rect()),"inverted HUD avoids existing objective and minimap")
	var floor_kept:=true
	for i in range(180):
		await frames()
		floor_kept=floor_kept and absf(grounded_enemy.position.y-ground_y)<0.2
		# Keep enemy wake checks in range while player falls toward distant sky.
		game.camera.position=Vector2(0,9600)
	check(floor_kept and grounded_enemy.is_on_floor() and grounded_enemy.up_direction==Vector2.UP,"ground enemy stays on floor for three seconds after player flip")
	check(falling_enemy.position.y>air_y+100 and falling_enemy.up_direction==Vector2.UP,"unsupported walker falls screen-down after player flip")
	game.player.invulnerability=0
	game.player.receive_hit(1-game.player.polarity,999)
	await frames(2)
	check(game.state=="lost","real Main death reaches retry state")
	game.primary_action()
	game.ui.update_hud()
	check(game.player.gravity_sign==1 and game.player.flip_ready and not game.ui.gravity_label.visible,"retry creates normal-gravity player and hides inversion HUD")
	game.start_run(38)
	check(game.player.gravity_sign==1 and game.player.up_direction==Vector2.UP,"new run starts with normal gravity")
	game.start_tutorial()
	var practice: Node2D = game.tutorial_session
	tap("gravity_flip")
	await frames(4)
	game.ui.update_hud()
	check(practice.player.gravity_sign==1 and not practice.player.pending_flip and not practice.ui.gravity_label.visible,"tutorial ignores gravity key and starts normal")
	check(not practice.ui.controls_label.text.contains("重力反転"),"tutorial controls omit disabled flip")

func run() -> void:
	await flip_tests()
	await platform_tests()
	await dash_tests()
	await real_main_tests()
	for action in ["jump","dash","move_up","move_down","move_left","move_right","gravity_flip"]: input(action,false)
	game.free()
	print("GRAVITY: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
