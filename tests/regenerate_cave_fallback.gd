extends SceneTree
## Rebuilds scripts/cave_fallback.gd from one ordinary generated world.
## Run after changing the cave rules, then run tests/generation_test.gd:
## tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script tests/regenerate_cave_fallback.gd
const G := preload("res://scripts/stage_generator.gd")
const SOURCE_SEED := 4242
const OUTPUT := "res://scripts/cave_fallback.gd"
const HEADER := "extends RefCounted\n## Fixed, editable emergency blueprint. No random sampling at runtime.\n## Rebuild it with tests/regenerate_cave_fallback.gd after changing the cave rules.\nstatic func data() -> Dictionary:\n\treturn "

func _initialize() -> void:
	var stage: Dictionary = G.generate(SOURCE_SEED)
	if stage.fallback:
		printerr("Seed %d already needs the fallback; choose another SOURCE_SEED." % SOURCE_SEED)
		quit(1)
		return
	stage.fallback = true
	var errors := G.validate(stage)
	if not errors.is_empty():
		printerr("Fallback candidate is invalid: ", errors)
		quit(1)
		return
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	file.store_string(HEADER + var_to_str(stage).replace("\n", "\n\t") + "\n")
	file.close()
	# Read the written script back without the cached copy and confirm it reproduces the world.
	# var_to_str sorts dictionary keys, so it compares content regardless of key order.
	var written: GDScript = ResourceLoader.load(OUTPUT, "", ResourceLoader.CACHE_MODE_IGNORE)
	var loaded: Dictionary = written.data()
	if var_to_str(loaded) != var_to_str(stage) or not G.validate(loaded).is_empty():
		printerr("Written fallback does not reproduce the validated world.")
		quit(1)
		return
	print("Wrote %s from seed %d: %d chambers, %d enemies." % [OUTPUT, SOURCE_SEED, stage.chambers.size(), stage.spawns.size()])
	quit(0)
