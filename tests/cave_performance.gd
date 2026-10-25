extends SceneTree
const Main = preload("res://scripts/main.gd")
func _initialize(): call_deferred("run")
func run():
	var game=Main.new()
	game.controls_path="res://builds/qa/caves/performance_controls.cfg"
	root.add_child(game)
	var reports=[]
	for value in [1,37,2026]:
		game.start_run(value)
		reports.append(game.last_start_metrics.duplicate())
		print("START RUN PERFORMANCE ",JSON.stringify(game.last_start_metrics))
		await process_frame
	FileAccess.open("res://builds/qa/caves/start_run_results.json",FileAccess.WRITE).store_string(JSON.stringify(reports,"\t"))
	game.free()
	quit()
