extends CharacterBody2D
## Screen-space gravity, independent of the player's gravity sign and color.
## Sticks where it first touches terrain. The blast digs a straight shaft that
## points away from the player at the moment of detonation.
const T := preload("res://scripts/tuning.gd")
const Art := preload("res://scripts/sprite_art.gd")
var game: Node2D
var elapsed := 0.0
var exploded := false
var blast_age := 0.0
var throw_facing := 1
var stuck := false
var stick_normal := Vector2.ZERO
var blast := Rect2() # Local to the stick, so origin shifts carry it.
var blast_direction := Vector2i.RIGHT
var blast_origin := Vector2.ZERO # Center of the stick's cell, local.

func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 | T.WALL_LAYER | T.PLATFORM_LAYER
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
	if stuck and not test_move(global_transform, -stick_normal * 2.0):
		stuck = false # The support was destroyed: fall again.
	if not stuck:
		velocity.y += T.DYNAMITE_GRAVITY * delta
		if not game.loaded_contains(global_position+velocity*delta):
			queue_free()
			return
		move_and_slide()
		var contacts := get_slide_collision_count()
		if contacts > 0:
			stuck = true
			stick_normal = get_slide_collision(contacts - 1).get_normal()
			velocity = Vector2.ZERO
		if not game.loaded_contains(global_position):
			queue_free()
			return
	if elapsed + 0.000001 >= T.DYNAMITE_FUSE: detonate()
	queue_redraw()

func fuse_remaining() -> float:
	return clampf(1.0 - elapsed / T.DYNAMITE_FUSE, 0.0, 1.0)

func aim_direction() -> Vector2i:
	# Away from the player along the dominant axis; ties dig sideways.
	var player = game.player
	if not is_instance_valid(player) or player.dead: return Vector2i(throw_facing, 0)
	var away: Vector2 = global_position - player.global_position
	if absf(away.x) >= absf(away.y):
		return Vector2i(int(signf(away.x)) if away.x != 0 else throw_facing, 0)
	return Vector2i(0, int(signf(away.y)))

func shaft_cells(direction: Vector2i) -> Rect2i:
	return game.terrain.dynamite_shaft(global_position, direction)

func detonate() -> void:
	if exploded or is_queued_for_deletion(): return
	if not game.loaded_contains(global_position):
		queue_free()
		return
	exploded = true
	collision_mask = 0
	game.play_sound("bomb_explode", global_position)
	blast_direction = aim_direction()
	var cut := shaft_cells(blast_direction)
	var reach: Rect2 = game.terrain.cell_rect_pixels(cut)
	blast = Rect2(reach.position - global_position, reach.size)
	blast_origin = game.terrain.cell_rect_pixels(Rect2i(game.terrain.cell_at(global_position), Vector2i.ONE)).get_center() - global_position
	var removed: Array[Vector2i] = game.terrain.dynamite_dig(cut)
	game.refresh_dynamite_map(removed)
	# Damage enemies first: player death must not suppress the normal kill rewards.
	var actors: Array = game.get_tree().get_nodes_in_group("enemies")
	if is_instance_valid(game.player): actors.append(game.player)
	for actor in actors:
		if actor.get_parent() != game.world or actor.dead or actor.is_queued_for_deletion(): continue
		if hits(actor):
			actor.receive_neutral_hit(T.DYNAMITE_SELF_DAMAGE if actor.faction == 0 else T.DYNAMITE_DAMAGE)
	queue_redraw()

func hits(actor: Node2D) -> bool:
	# The shaft plus a small core around the stick.
	var body := Rect2(actor.global_position-actor.body_size/2, actor.body_size)
	var nearest := global_position.clamp(body.position, body.end)
	return body.intersects(Rect2(blast.position + global_position, blast.size)) \
		or global_position.distance_squared_to(nearest) <= T.DYNAMITE_CORE_RADIUS*T.DYNAMITE_CORE_RADIUS

func _draw() -> void:
	var tint := Color("f5bd68")
	if exploded:
		var fade := 1.0-blast_age/0.45
		draw_rect(blast, Color(tint, fade*0.25))
		var burst_scale := T.TILE_SIZE*T.DYNAMITE_SHAFT_WIDTH*0.5/T.BOMB_RADIUS
		for i in range(0, T.DYNAMITE_SHAFT_LENGTH, 2):
			var age := blast_age - i*0.015 # A short ripple outward.
			if age < 0: continue
			var at := blast_origin + Vector2(blast_direction)*i*T.TILE_SIZE
			draw_set_transform(at, 0, Vector2.ONE*burst_scale)
			Art.draw_frame(self, "burst", "bomb", 1, age, Vector2.ZERO, 1)
		draw_set_transform(Vector2.ZERO)
		draw_rect(blast, Color(tint, fade), false, 3)
		return
	if is_instance_valid(game.terrain):
		var preview: Rect2 = game.terrain.cell_rect_pixels(shaft_cells(aim_direction()))
		var pulse := 0.28+0.15*sin(elapsed*16)
		draw_rect(Rect2(preview.position - global_position, preview.size), Color(tint, pulse), false, 1.5)
	var remaining := fuse_remaining()
	draw_arc(Vector2.ZERO, T.DYNAMITE_GAUGE_RADIUS, 0, TAU, 48, Color(0,0,0,0.45), 5, true)
	if remaining > 0.0:
		var gauge_color := Color("f5bd68").lerp(Color("ff5a4a"), 1.0 - remaining)
		draw_arc(Vector2.ZERO, T.DYNAMITE_GAUGE_RADIUS, -PI/2, -PI/2 + TAU*remaining, 48, gauge_color, T.DYNAMITE_GAUGE_WIDTH, true)
	draw_rect(Rect2(-9,-5,18,10), Color("ba5148"))
	draw_line(Vector2(-4,-5),Vector2(-4,5),tint,2)
	draw_line(Vector2(4,-5),Vector2(4,5),tint,2)
	var spark := Vector2(7,-10)
	draw_line(Vector2(6,-5),spark,Color("dfd3ac"),1.5)
	draw_circle(spark,2+sin(elapsed*39),Color("fff1a8"))
	for i in range(3):
		var angle := elapsed*29+i*TAU/3
		draw_line(spark+Vector2.from_angle(angle)*3,spark+Vector2.from_angle(angle)*7,tint,1)
