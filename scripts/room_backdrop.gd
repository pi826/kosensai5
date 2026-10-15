extends Node2D
## Quiet geometric placeholders; generated art is reserved for the later art phase.

const Terrain := preload("res://scripts/room_terrain.gd")
const ROOM_SIZE := Vector2(1280, 736)
var room: Dictionary = {}

func _ready() -> void:
	z_index = -20
	queue_redraw()

func _draw() -> void:
	var biome := clampi(int(room.get("biome", 0)), 0, 2)
	var theme: Dictionary = Terrain.THEMES[biome]
	draw_rect(Rect2(Vector2.ZERO, ROOM_SIZE), theme.back)
	var glow: Color = theme.accent
	glow.a = 0.035
	draw_circle(Vector2(640, 336), 320, glow)
	var faint: Color = theme.accent
	faint.a = 0.10
	var dark: Color = theme.body
	dark.a = 0.36
	var detail: Color = theme.accent
	detail.a = 0.15
	var offset := posmod(int(room.get("id", 0)) * 43, 96)
	match biome:
		0:
			# Stone galleries, with deep arches beyond the playable platforms.
			for x in range(128 - offset, 1280, 224):
				draw_rect(Rect2(x, 240, 34, 400), dark)
				draw_rect(Rect2(x + 136, 240, 34, 400), dark)
				draw_arc(Vector2(x + 85, 270), 68, PI, TAU, 20, faint, 18)
				draw_line(Vector2(x + 43, 352), Vector2(x + 127, 352), detail, 1)
		1:
			# A layered, angular underground chamber.
			for x in range(64 - offset, 1280, 192):
				var points := PackedVector2Array([Vector2(x, 640), Vector2(x + 18, 344), Vector2(x + 62, 224), Vector2(x + 108, 400), Vector2(x + 126, 640)])
				draw_colored_polygon(points, dark)
				draw_line(Vector2(x + 62, 240), Vector2(x + 62, 588), detail, 1)
		2:
			# Tall sealed machinery, drawn with low contrast behind the action.
			for x in range(96 - offset, 1280, 256):
				draw_rect(Rect2(x, 206, 96, 434), dark)
				draw_rect(Rect2(x + 12, 222, 72, 394), faint, false, 2)
				for y in range(264, 600, 64):
					draw_line(Vector2(x + 24, y), Vector2(x + 72, y), detail, 2)
	# Horizontal scale lines are decoration only; collision tiles are drawn separately.
	for y in [192, 608]:
		draw_line(Vector2(32, y), Vector2(1248, y), faint, 1)
