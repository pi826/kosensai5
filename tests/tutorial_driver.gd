extends RefCounted
## Walk the actual connected course with currently bound physical keyboard keys.
const T := preload("res://scripts/tuning.gd")
var tree: SceneTree
var game: Node2D
var checks := 0
var failures: Array[String] = []
var capture := Callable()
var world_id := 0
var player_id := 0
var previous_position := Vector2.ZERO
var largest_step := 0.0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)

func key(action: String, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = game.key_bindings.get_key(action, 0)
	event.keycode = event.physical_keycode
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func release() -> void:
	for action: String in game.key_bindings.ACTIONS: key(action, false)

func frames(count: int) -> void:
	for i in range(count):
		tree.test_progress()
		await tree.physics_frame
		tree.test_progress()
		await tree.process_frame
		largest_step = maxf(largest_step, previous_position.distance_to(game.player.position))
		previous_position = game.player.position

func tap(action: String) -> void:
	key(action, true)
	await frames(1)
	key(action, false)
	await frames(1)

func walk(x: float) -> void:
	for tick in range(1400):
		var dx: float = x - game.player.position.x
		if absf(dx) <= 3: break
		key("move_left", dx < 0)
		key("move_right", dx > 0)
		await frames(1)
	key("move_left", false)
	key("move_right", false)
	await frames(4)
	check(absf(game.player.position.x - x) < 12, "walk reached %s" % x)

func jump_right(x: float) -> void:
	key("jump", true)
	await walk(x)
	key("jump", false)
	await frames(50)

func shoot() -> void:
	key("shoot", true)
	await frames(55)
	key("shoot", false)

func expect_lesson(index: int) -> void:
	await frames(90)
	check(game.lesson == index, "entered lesson %d, actual %d" % [index, game.lesson])
	if capture.is_valid(): await capture.call("lesson_%02d" % (index + 1))
	await frames(10)
	check(game.lesson == index and game.ok_remaining <= 0, "lesson %d waits for its condition" % index)

func run() -> void:
	world_id = game.world.get_instance_id()
	player_id = game.player.get_instance_id()
	previous_position = game.player.position
	release()
	await expect_lesson(0)
	await walk(320)
	await expect_lesson(1)
	await walk(410)
	await jump_right(608)
	await expect_lesson(2)
	# Walking on the platform does not meet the drop-through condition.
	await walk(800)
	check(game.lesson == 2 and not game.drop_observed, "standing above drop goal does not advance")
	await tap("move_down")
	await expect_lesson(3)
	await walk(984)
	await shoot()
	await expect_lesson(4)
	await walk(1340)
	await jump_right(1540)
	await walk(1620)
	if capture.is_valid(): await capture.call("aim_setup")
	await shoot()
	check(game.lesson == 4 and not game.defeated.has("upper") and not game.defeated.has("lower"), "forward fire cannot complete angled targets")
	await tap("aim_cycle")
	await shoot()
	check(game.defeated.has("upper") and not game.defeated.has("lower") and game.lesson == 4, "upper target alone does not advance")
	await tap("aim_cycle")
	await shoot()
	await expect_lesson(5)
	await walk(2208)
	await frames(90)
	if capture.is_valid(): await capture.call("absorption_setup")
	check(game.player.hp < T.PLAYER_HP and game.lesson == 5 and game.absorptions == 0, "opposite turret bullets damage without advancing")
	await tap("switch_color")
	for tick in range(600):
		if game.ok_remaining > 0 or game.lesson != 5: break
		await frames(1)
	check(game.absorptions >= T.ABSORPTIONS_PER_CHARGE and game.player.homing_charges > 0, "real turret shots absorbed into a stock")
	await expect_lesson(6)
	await tap("aim_cycle") # down -> forward
	await walk(2608)
	await shoot()
	check(game.lesson == 6 and game.targets.color.hp == T.ENEMY_HP and game.targets.color.gauge > 0, "same-color fire absorbed by colored enemy")
	var before_stock: int = game.player.homing_charges
	await tap("switch_color")
	await shoot()
	check(game.player.homing_charges == before_stock + T.ENEMY_CHARGE_REWARD, "colored enemy kill grants a stock")
	await expect_lesson(7)
	await walk(3328)
	if capture.is_valid(): await capture.call("homing_setup")
	await tap("special")
	check(game.volleys == 1 and game.player.homing_charges == before_stock, "special input consumes exactly one stock")
	for tick in range(450):
		if game.lesson != 7 or game.ok_remaining > 0: break
		await frames(1)
	await expect_lesson(8)
	check(game.player.hp == T.TUTORIAL_RECOVERY_HP, "recovery begins with reduced HP")
	await walk(3824)
	await shoot()
	await expect_lesson(9)
	check(game.player.hp == T.TUTORIAL_RECOVERY_HP + T.BLOCK_HEAL, "box healed by normal player fire")
	await walk(T.TUTORIAL_HEART.x)
	await expect_lesson(10)
	check(game.player.hp == T.TUTORIAL_RECOVERY_HP + T.BLOCK_HEAL + T.HEART_HEAL, "heart contact heals")
	await tap("interact")
	await frames(55)
	check(game.state == "tutorial_complete" and game.lesson == 11, "interact confirms contact explanation and completes")
	check(game.world.get_instance_id() == world_id and game.player.get_instance_id() == player_id, "one world and one player throughout")
	check(largest_step < T.MAX_FALL_SPEED / 60 + 1, "no teleport throughout actual input traversal: max %.2f" % largest_step)
	if capture.is_valid(): await capture.call("complete")
	release()
