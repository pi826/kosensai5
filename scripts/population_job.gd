extends RefCounted
## Immutable sector-local input; the main thread reads output only after joining.
const Population := preload("res://scripts/enemy_population.gd")
var data: Dictionary = {}
var result: Array = []
var task_id := -1
var generation_ms := 0.0
func run() -> void:
	var begin := Time.get_ticks_usec()
	result = Population.reserve(data)
	generation_ms = (Time.get_ticks_usec()-begin)/1000.0
