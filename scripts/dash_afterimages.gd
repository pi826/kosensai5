extends Node2D
## Fading copies of the player along an air dash. Drawing only: no collision
## and no game state. A child of the effects layer, so origin shifts move it.
const T := preload("res://scripts/tuning.gd")
const Art := preload("res://scripts/sprite_art.gd")
var images: Array = []

func _ready() -> void:
	z_as_relative = false
	z_index = -1 # Above terrain, behind enemies and the player.
	# Additive: a normal blend left a dark shadow on the dark cave backgrounds.
	var glow := CanvasItemMaterial.new()
	glow.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = glow

func record(actor: CharacterBody2D) -> void:
	var state := Art.actor_state(actor)
	var shooting: bool = actor.art_fire_remaining > 0 and state not in ["death", "hurt"]
	images.append({"at": to_local(actor.global_position), "age": 0.0, "facing": actor.facing,
		"gravity": actor.gravity_sign, "polarity": actor.polarity, "size": actor.body_size,
		"scale": actor.visual_scale, "state": state, "time": actor.art_time,
		"arm": ["shoot_front", "shoot_up", "shoot_down"][actor.aim_index] if shooting else state,
		"arm_time": 0.125 - actor.art_fire_remaining if shooting else actor.art_time})
	if images.size() > T.DASH_AFTERIMAGE_MAX: images.pop_front()
	queue_redraw()

func clear() -> void:
	images.clear()
	queue_redraw()

func alpha(image: Dictionary) -> float:
	return T.DASH_AFTERIMAGE_ALPHA * clampf(1.0 - image.age / T.DASH_AFTERIMAGE_TIME, 0.0, 1.0)

func _process(delta: float) -> void:
	if images.is_empty(): return
	for image: Dictionary in images: image.age += delta
	images = images.filter(func(image): return image.age < T.DASH_AFTERIMAGE_TIME)
	queue_redraw()

func _draw() -> void:
	for image: Dictionary in images:
		var tint := Color(T.COLORS[image.polarity], alpha(image))
		var foot := Vector2(0, image.size.y / 2)
		# Same placement as Art.draw_actor, including the gravity mirror.
		draw_set_transform(image.at + Vector2(0, image.gravity * foot.y * (1.0 - image.scale.y)), 0, image.scale * Vector2(1, image.gravity))
		if Art.draw_frame(self, "player", image.state, image.polarity, image.time, foot, image.facing, tint):
			Art.draw_frame(self, "player_arm", image.arm, image.polarity, image.arm_time, foot, image.facing, tint)
		else:
			draw_set_transform(image.at)
			draw_rect(Rect2(-image.size / 2, image.size), tint, false, 2.0)
	draw_set_transform(Vector2.ZERO)
