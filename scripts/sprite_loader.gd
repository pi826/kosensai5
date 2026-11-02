extends Node
## Process even on title/pause; rendering caches are refreshed once after upload.
const Art := preload("res://scripts/sprite_art.gd")
var game: Node
var seen_serial := -1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -900
	Art.prewarm()
	set_process(Art.enabled())

func _process(_delta: float) -> void:
	Art.service_loading()
	if Art._pending.is_empty() and seen_serial != Art.upload_serial:
		seen_serial = Art.upload_serial
		if is_instance_valid(game.terrain):
			for key: Vector2i in game.terrain.draw_chunks: game.terrain.request_chunk_redraw(key)

func _exit_tree() -> void:
	Art.shutdown_loading()
