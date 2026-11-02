extends Node2D
## Visual remnant only: actor collision, reward and deletion are unchanged.
var kind := "player"
var polarity := 0
var facing := 1
var age := 0.0
const Art := preload("res://scripts/sprite_art.gd")

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if kind == "player": process_mode = Node.PROCESS_MODE_ALWAYS
	# World-origin shifts move non-actor children through this existing group.
	add_to_group("sprite_remnants")

func _process(delta: float) -> void:
	age += delta
	var desc := Art.description(kind,"death")
	var duration := float(desc.frames)/float(desc.fps) if not desc.is_empty() else 0.5
	if age >= duration: queue_free()
	queue_redraw()

func _draw() -> void:
	Art.draw_frame(self,kind,"death",polarity,age,Vector2.ZERO,facing)
	if kind == "player": Art.draw_frame(self,"player_arm","death",polarity,age,Vector2.ZERO,facing)
