extends CharacterBody2D
## Screen-space gravity, independent of the player's gravity sign and color.
const T := preload("res://scripts/tuning.gd")
const Art := preload("res://scripts/sprite_art.gd")
var game: Node2D
var elapsed := 0.0
var exploded := false
var blast_age := 0.0

func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 | T.WALL_LAYER | T.PLATFORM_LAYER
	floor_snap_length = 2.0
	var shape := RectangleShape2D.new()
	shape.size = Vector2(12, 8)
	var collider := CollisionShape2D.new()
	collider.shape = shape
	add_child(collider)

func _physics_process(delta: float) -> void:
	if exploded:
		blast_age += delta
		if blast_age >= 0.45: queue_free()
		queue_redraw()
		return
	if not game.loaded_contains(global_position):
		queue_free()
		return
	elapsed += delta
	velocity.y += T.DYNAMITE_GRAVITY * delta
	if not game.loaded_contains(global_position+velocity*delta):
		queue_free()
		return
	move_and_slide()
	if is_on_wall():
		velocity.x = 0
		velocity.y = maxf(0, velocity.y)
	if is_on_floor(): velocity = Vector2.ZERO
	if not game.loaded_contains(global_position):
		queue_free()
		return
	if elapsed + 0.000001 >= T.DYNAMITE_FUSE: detonate()
	queue_redraw()

func detonate() -> void:
	if exploded or is_queued_for_deletion(): return
	if not game.loaded_contains(global_position):
		queue_free()
		return
	exploded = true
	collision_mask = 0
	game.play_sound("bomb_explode", global_position)
	if is_instance_valid(game.terrain):
		var removed: Array[Vector2i] = game.terrain.dynamite_explode(global_position)
		game.refresh_dynamite_map(removed)
	# Damage enemies first: player death must not suppress the normal kill rewards.
	var actors: Array = game.get_tree().get_nodes_in_group("enemies")
	if is_instance_valid(game.player): actors.append(game.player)
	for actor in actors:
		if actor.get_parent() != game.world or actor.dead or actor.is_queued_for_deletion(): continue
		var body := Rect2(actor.global_position-actor.body_size/2, actor.body_size)
		var nearest := global_position.clamp(body.position, body.end)
		if global_position.distance_squared_to(nearest) <= T.DYNAMITE_RADIUS*T.DYNAMITE_RADIUS:
			actor.receive_neutral_hit(T.DYNAMITE_SELF_DAMAGE if actor.faction == 0 else T.DYNAMITE_DAMAGE)
	queue_redraw()

func _draw() -> void:
	var tint := Color("f5bd68")
	if exploded:
		var fade := 1.0-blast_age/0.45
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE*T.DYNAMITE_RADIUS/T.BOMB_RADIUS)
		Art.draw_frame(self, "burst", "bomb", 1, blast_age, Vector2.ZERO, 1)
		draw_set_transform(Vector2.ZERO)
		draw_circle(Vector2.ZERO, T.DYNAMITE_RADIUS*fade, Color(tint,fade*0.15))
		draw_arc(Vector2.ZERO, T.DYNAMITE_RADIUS, 0, TAU, 48, Color(tint,fade), 3, true)
		return
	draw_arc(Vector2.ZERO, T.DYNAMITE_RADIUS, 0, TAU, 48, Color(tint,0.28+0.15*sin(elapsed*16)), 1.5, true)
	draw_rect(Rect2(-9,-5,18,10), Color("ba5148"))
	draw_line(Vector2(-4,-5),Vector2(-4,5),tint,2)
	draw_line(Vector2(4,-5),Vector2(4,5),tint,2)
	var spark := Vector2(7,-10)
	draw_line(Vector2(6,-5),spark,Color("dfd3ac"),1.5)
	draw_circle(spark,2+sin(elapsed*39),Color("fff1a8"))
	for i in range(3):
		var angle := elapsed*29+i*TAU/3
		draw_line(spark+Vector2.from_angle(angle)*3,spark+Vector2.from_angle(angle)*7,tint,1)
