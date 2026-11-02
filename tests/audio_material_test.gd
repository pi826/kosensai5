extends "res://tests/test_tree.gd"
var checks := 0
var failures := []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: ",message)
func run() -> void:
	var metrics := preload("res://tests/audio_assets_checks.gd").run(self)
	FileAccess.open("res://builds/qa/sound/task8d/material-results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"metrics":metrics},"\t"))
	print("MATERIAL RESULT: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
