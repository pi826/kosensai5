extends "res://tests/test_tree.gd"
var condition_ready := false
var checks := 0
var failures: Array[String] = []

func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)

func delayed_ready():
	for i in range(8):
		test_progress()
		await physics_frame
		test_progress()
		await process_frame
	var deadline := Time.get_ticks_msec() + 60
	while Time.get_ticks_msec() < deadline: await process_frame
	condition_ready = true

func run():
	var begun := Time.get_ticks_msec()
	check(not await wait_until(func(): return false, 0.05), "unmet prerequisite returns false")
	check(Time.get_ticks_msec() - begun < 1000, "unmet prerequisite has a bounded real wait")
	delayed_ready()
	check(await wait_until(func(): return condition_ready, 2.0), "delayed prerequisite survives more than three frames")
	check(is_instance_valid(self), "test continues after unmet prerequisite")
	if OS.get_cmdline_user_args().has("--inject-null"):
		# The runner expects exit 1 from the deadline after this coroutine stops.
		var missing: Node = null
		missing.get_child_count()
		return
	print("TEST GUARD: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
