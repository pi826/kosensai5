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
	for action in ["jump", "dash", "move_left", "move_right"]: input(action, false)
	if is_instance_valid(game): game.free()
	game = Fixture.new()
	root.add_child(game)
	game.player.abilities = abilities
	if on_floor: fixture(Rect2(-500, 1000, 4000, 96))
	game.player.position = Vector2(0, 978 if on_floor else 300)
	await frames(3)

func flight(mask: int, steer: bool = true) -> Dictionary:
	await reset(mask)
	var start: Vector2 = game.player.position
	var minimum := start.y
	var profile: Dictionary = G.flight_profiles(mask)[-1]
	input("jump", true)
	if steer: input("move_right", true)
	var count := 0
	for i in range(T.ABILITY_FLIGHT_FRAMES):
		if i == profile.second:
			input("jump", false)
			input("jump", true)
		if i == profile.dash: input("dash", true)
		if i == profile.dash + 1: input("dash", false)
		await frames()
		minimum = minf(minimum, game.player.position.y)
		count = i + 1
		if i > 2 and game.player.is_on_floor(): break
	return {"height": start.y - minimum, "reach": game.player.position.x - start.x, "frames": count}

func run() -> void:
	await reset()
	input("jump", true)
	await frames(22)
	var before: float = game.player.velocity.y
	input("jump", false)
	input("jump", true)
	input("dash", true)
	await frames()
	check(game.player.velocity.y > before and not game.player.air_jump_used and not game.player.air_dash_used, "locked abilities do not act")
	for mask in [1, 2, 4, 3, 5, 6, 7]:
		measurements[str(mask)] = await flight(mask)
		check(measurements[str(mask)].frames < T.ABILITY_FLIGHT_FRAMES, "measured flight lands mask=%d" % mask)
		var expected: Array = T.ABILITY_HOP_PROFILES[mask]
		check(absf(measurements[str(mask)].height-expected[0])<0.2 and absf(measurements[str(mask)].reach-expected[1])<0.2 and measurements[str(mask)].frames==expected[2], "planner profile matches actual player physics mask=%d" % mask)
	print("ABILITY MEASUREMENTS ", measurements)
	check(measurements["1"].height > 280 and measurements["1"].height < 320, "double jump measured combined height")
	check(measurements["2"].reach > 330, "dash increases measured horizontal reach")
	check(measurements["4"].frames > measurements["2"].frames, "glide prolongs flight")
	await reset(1)
	input("jump", true)
	await frames(22)
	input("jump", false)
	input("jump", true)
	await frames()
	check(game.player.air_jump_used and game.player.velocity.y < -750, "one second jump uses 85 percent impulse")
	await frames(8)
	var rising: float = game.player.velocity.y
	input("jump", false)
	input("jump", true)
	await frames()
	check(game.player.velocity.y > rising, "third jump rejected")
	input("jump", false)
	await frames()
	check(game.player.velocity.y >= -T.JUMP_CUT_SPEED, "release cuts second jump")
	await frames(75)
	check(game.player.is_on_floor() and not game.player.air_jump_used, "landing restores second jump")
	# Walking off a real ledge: coyote input spends the ordinary jump.
	await reset(1, false)
	fixture(Rect2(-100, 500, 100, 16), true)
	game.player.position = Vector2(-30, 478)
	await frames(4)
	input("move_right", true)
	check(await wait_until(func(): return not game.player.is_on_floor(), 3), "walked off coyote ledge")
	await frames(1)
	input("jump", true)
	await frames()
	check(not game.player.air_jump_used and game.player.velocity.y < -850, "coyote press remains ordinary jump")
	await reset(2)
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
	await reset(2,false)
	game.player.facing = -1
	var left_start: Vector2 = game.player.position
	input("dash",true)
	await frames(8)
	check(absf(game.player.position.x-left_start.x+128)<0.2 and absf(game.player.position.y-left_start.y)<0.2, "dash follows left-facing direction without falling")
	await reset(2, false)
	fixture(Rect2(70, -500, 32, 2000))
	input("dash", true)
	await frames(6)
	check(game.player.position.x < 56 and game.player.dash_remaining == 0, "wall stops dash")
	await reset(4, false)
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
	await reset(5, false)
	input("jump", true)
	await frames()
	check(game.player.air_jump_used and game.player.velocity.y < 0 and not game.player.gliding, "second jump takes priority over glide")
	await frames(45)
	check(game.player.gliding and game.player.velocity.y <= T.GLIDE_FALL_SPEED, "continued hold glides after second jump")
	for action in ["jump", "dash", "move_right"]: input(action, false)
	game.free()
	DirAccess.make_dir_recursive_absolute("res://builds/qa/abilities")
	FileAccess.open("res://builds/qa/abilities/physics_results.json", FileAccess.WRITE).store_string(JSON.stringify({"checks": checks,"failures": failures,"measurements": measurements}, "\t"))
	print("ABILITY PHYSICS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
