extends SceneTree
## Every executable test has a wall-clock deadline, including a coroutine that
## stopped on a script error. Synchronous engine stalls also need a runner limit.
var _test_deadline_ms := 0
var _test_progress_ms := 0
var _test_idle_ms := 120000

func _init() -> void:
	call_deferred("_arm_test_deadline")

func _arm_test_deadline() -> void:
	var seconds := 900.0
	if get_script().resource_path.get_file() in ["sector_test.gd", "generation_test.gd", "playthrough.gd", "boss_cycle_test.gd"]:
		seconds = 3600.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--test-timeout="):
			seconds = maxf(0.01, arg.get_slice("=", 1).to_float())
		if arg.begins_with("--test-idle-timeout="):
			_test_idle_ms = maxi(10, int(arg.get_slice("=", 1).to_float() * 1000))
	_test_deadline_ms = Time.get_ticks_msec() + int(seconds * 1000)
	test_progress()

func test_progress() -> void:
	_test_progress_ms = Time.get_ticks_msec()

func _process(_delta: float) -> bool:
	if _test_deadline_ms > 0 and Time.get_ticks_msec() >= _test_deadline_ms:
		printerr("FAIL: test wall-clock deadline exceeded: ", get_script().resource_path)
		quit(1)
	elif _test_progress_ms > 0 and Time.get_ticks_msec() - _test_progress_ms >= _test_idle_ms:
		printerr("FAIL: test coroutine made no progress within deadline: ", get_script().resource_path)
		quit(1)
	return false

func wait_until(condition: Callable, timeout_seconds: float = 20.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000)
	while not condition.call():
		if Time.get_ticks_msec() >= deadline: return false
		test_progress()
		await physics_frame
		await process_frame
		# Fixed-fps headless frames otherwise outrun worker preparation.
		OS.delay_msec(1)
	return true
