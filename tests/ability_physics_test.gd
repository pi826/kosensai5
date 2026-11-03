extends "res://tests/test_tree.gd"
const Main := preload("res://scripts/main.gd")
const Terrain := preload("res://scripts/terrain.gd")
const T := preload("res://scripts/tuning.gd")
const G := preload("res://scripts/stage_generator.gd")
var game: Node2D
var checks := 0
var failures: Array[String] = []
var measurements := {}

class Fixture extends Main:
	func _ready() -> void:
		key_bindings = KeyBindings.new()
		key_bindings.apply()
		world = Node2D.new()
		add_child(world)
		effects = Effects.new()
		world.add_child(effects)
		player = Player.new()
		player.game = self
		world.add_child(player)
		state = "playing"
	func _physics_process(_delta: float) -> void: pass
	func _update_exploration() -> void: pass

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)
func frames(count: int = 1) -> void:
	for i in range(count):
		test_progress()
		await physics_frame
		await process_frame
func input(action: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func fixture(rect: Rect2, thin: bool = false) -> void:
	add_fixture(game.world, rect, thin)

static func add_fixture(world: Node2D, rect: Rect2, thin: bool = false) -> void:
	if thin:
		var body := StaticBody2D.new()
		body.collision_layer = T.PLATFORM_LAYER
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = rect.size
		shape.shape = box
		shape.one_way_collision = true
		body.position = rect.get_center()
		body.add_child(shape)
		world.add_child(body)
	else:
		var floor := Terrain.new()
		floor.bounds = rect
		world.add_child(floor)
func reset(abilities: int = 0, on_floor: bool = true) -> void:
	for action in ["jump", "dash", "move_up", "move_down", "move_left", "move_right", "gravity_flip"]: input(action, false)
	if is_instance_valid(game): game.free()
	game = Fixture.new()
	root.add_child(game)
	game.player.abilities = abilities
	if on_floor: fixture(Rect2(-500, 1000, 4000, 96))
	game.player.position = Vector2(0, 978 if on_floor else 300)
	await frames(3)

func flight(profile: Dictionary, steer: bool = true) -> Dictionary:
	await reset(profile.required)
	var start: Vector2 = game.player.position
	var minimum := start.y
	input("jump", true)
	if steer: input("move_right", true)
	var count := 0
	for i in range(T.ABILITY_FLIGHT_FRAMES):
		if not profile.glide and i == ceili(T.JUMP_SPEED / T.GRAVITY * 60): input("jump", false)
		if i == profile.dash:
			if profile.dash_up: input("move_up", true)
			input("dash", true)
		if i == profile.dash + 1:
			input("dash", false)
			input("move_up", false)
		if steer: input("move_right", not G.ability_steer_paused(profile, i))
		await frames()
		minimum = minf(minimum, game.player.position.y)
		count = i + 1
		if i > 2 and game.player.is_on_floor(): break
	return {"height": start.y - minimum, "reach": game.player.position.x - start.x, "frames": count}

func run() -> void:
	var all_profiles := G.flight_profiles(T.ABILITY_DASH | T.ABILITY_GLIDE)
	check(all_profiles.map(func(p): return p.id)==T.ABILITY_FLIGHT_SCHEDULES.map(func(p): return p.id),"all schedules retain declared order")
	check(G.flight_profiles(T.ABILITY_DASH).map(func(p): return p.id)==["dash_side","dash_up"] and G.flight_profiles(T.ABILITY_GLIDE).size()==1,"unlocked masks filter schedules")
	all_profiles[0].dash_up=true
	check(not T.ABILITY_FLIGHT_SCHEDULES[0].dash_up,"returned profiles are independent dictionary copies")
	check(G.flight_profiles(1).is_empty(),"removed double-jump bit unlocks no flight schedules")
	await reset()
	input("jump", true)
	await frames(22)
	var before: float = game.player.velocity.y
	input("jump", false)
	input("jump", true)
	input("dash", true)
	await frames()
	check(game.player.velocity.y > before and not game.player.air_dash_used, "locked dash and airborne jump do not act")
	for profile: Dictionary in T.ABILITY_FLIGHT_SCHEDULES:
		measurements[profile.id] = await flight(profile)
		check(measurements[profile.id].frames < T.ABILITY_FLIGHT_FRAMES, "measured flight lands id=" + profile.id)
		var expected: Array = T.ABILITY_HOP_PROFILES[profile.id]
		var actual: Dictionary = measurements[profile.id]
		check(absf(actual.height-expected[0])<0.2 and absf(actual.reach-expected[1])<0.2 and actual.frames==expected[2], "planner table matches actual player physics id=" + profile.id)
		var arc := G.ability_arc(Vector2(0,978),Rect2(0,1000,4000,96),[Rect2(-500,1000,4500,96)],profile)
		print("ARC ", profile.id, " ", arc.get("frames"), " ", arc.get("height"), " ", arc.get("position"))
		check(not arc.is_empty() and absf(arc.height-actual.height)<0.2 and absf(arc.position.x-actual.reach)<0.2 and arc.frames==actual.frames,"simulated arc matches actual physics id=" + profile.id)
	var ordinary := await flight({"required":0,"dash":-1,"dash_up":false,"glide":false})
	print("ABILITY MEASUREMENTS ", measurements, " ordinary=", ordinary)
	check(measurements.dash_up.height > ordinary.height + 150, "up dash rises at least 150 pixels above ordinary jump")
	check(measurements.dash_side.reach > 330, "side dash increases horizontal reach beyond 330")
	check(measurements.glide.frames > measurements.dash_side.frames and measurements.glide.reach > measurements.dash_side.reach, "glide flies longer and farther than side dash")
	check(measurements.dash_up_glide.reach > measurements.dash_up.reach and measurements.dash_side_glide.reach > measurements.dash_side.reach,"glide extends both dash schedules")
	# Ordinary coyote jump retains its original impulse.
	await reset(T.ABILITY_DASH, false)
	fixture(Rect2(-100, 500, 100, 16), true)
	game.player.position = Vector2(-30, 478)
	await frames(4)
	input("move_right", true)
	check(await wait_until(func(): return not game.player.is_on_floor(), 3), "walked off coyote ledge")
	await frames()
	input("jump", true)
	await frames()
	check(game.player.velocity.y < -850, "coyote press remains ordinary jump")
	await reset(T.ABILITY_DASH)
	input("dash", true)
	await frames()
	check(not game.player.air_dash_used and game.player.dash_remaining == 0, "ground dash rejected")
	input("dash", false)
	input("jump", true)
	await frames(12)
	var start: Vector2 = game.player.position
	input("dash", true)
	await frames(11)
	measurements.dash_distance = game.player.position.x - start.x
	check(absf(game.player.position.y - start.y) < 0.2, "dash suppresses falling throughout 11 frames")
	check(absf(measurements.dash_distance - 176) < 1, "dash measured distance 176 pixels")
	input("dash", false)
	input("dash", true)
	await frames()
	check(game.player.dash_remaining == 0 and game.player.air_dash_used, "second air dash rejected")
	input("jump", false)
	await frames(75)
	check(not game.player.air_dash_used, "landing restores dash")
	await reset(T.ABILITY_DASH, false)
	game.player.facing = -1
	var left_start: Vector2 = game.player.position
	input("dash",true)
	await frames(8)
	check(absf(game.player.position.x-left_start.x+128)<0.2 and absf(game.player.position.y-left_start.y)<0.2, "dash follows left-facing direction without falling")
	await reset(T.ABILITY_DASH, false)
	fixture(Rect2(70, -500, 32, 2000))
	input("dash", true)
	await frames(6)
	check(game.player.position.x < 56 and game.player.dash_remaining == 0, "wall stops dash")
	await reset(T.ABILITY_GLIDE, false)
	input("jump", true)
	await frames(30)
	check(game.player.gliding and game.player.velocity.y <= T.GLIDE_FALL_SPEED, "held jump caps falling at 120")
	input("move_right",true)
	await frames(6)
	check(is_equal_approx(game.player.velocity.x,T.MOVE_SPEED), "glide retains ordinary horizontal movement")
	input("move_right",false)
	input("jump", false)
	await frames(3)
	check(not game.player.gliding and game.player.velocity.y > T.GLIDE_FALL_SPEED, "release immediately ends glide")
	for action in ["jump", "dash", "move_up", "move_right"]: input(action, false)
	game.free()
	FileAccess.open("res://.userdata/codex-delegation/task-20261103-64-physics.json", FileAccess.WRITE).store_string(JSON.stringify({"checks": checks,"failures": failures,"measurements": measurements}, "\t"))
	print("ABILITY PHYSICS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
