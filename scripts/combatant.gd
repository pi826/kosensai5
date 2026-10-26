extends CharacterBody2D
const T := preload("res://scripts/tuning.gd")

var game: Node2D
var faction := 0 # 0: player, 1: enemy. Bodies collide with terrain only.
var kind := "player"
var polarity := 0
var hp := T.PLAYER_HP
var max_hp := T.PLAYER_HP
var gauge := 0
var facing := 1
var invulnerability := 0.0
var hit_flash := 0.0
var absorb_flash := 0.0
var dead := false
var body_size := T.PLAYER_SIZE
var action := "idle"
var action_remaining := 0.0
var next_polarity := 0
var visual_scale := Vector2.ONE
var lock_marked := false
var body_shape: RectangleShape2D

func _ready() -> void:
	collision_layer = 2 if faction == 0 else 4
	collision_mask = 1 | T.WALL_LAYER | T.PLATFORM_LAYER
	var shape := RectangleShape2D.new()
	shape.size = body_size
	body_shape = shape
	var collider := CollisionShape2D.new()
	collider.shape = shape
	add_child(collider)
	add_to_group("combatants")
	add_to_group("players" if faction == 0 else "enemies")
	floor_snap_length = 12.0

func tick_visuals(delta: float, redraw: bool = true) -> void:
	invulnerability = maxf(0.0, invulnerability - delta)
	hit_flash = maxf(0.0, hit_flash - delta)
	absorb_flash = maxf(0.0, absorb_flash - delta)
	if redraw: queue_redraw()

func receive_hit(attack_color: int, damage: int) -> String:
	if dead:
		return "dead"
	if attack_color == polarity:
		_absorb_attack()
		absorb_flash = 0.28
		if is_instance_valid(game):
			game.effect(global_position, T.COLORS[polarity], "absorb")
		queue_redraw()
		return "absorbed"
	if invulnerability > 0.0:
		return "protected"
	var previous_hp := hp
	hp = maxi(0, hp - damage)
	if hp != previous_hp:
		_hp_changed(previous_hp)
	hit_flash = 0.15
	queue_redraw()
	if faction == 0:
		invulnerability = T.INVULNERABILITY
	if is_instance_valid(game):
		game.effect(global_position, Color("f8f8ef"), "hit")
		if faction == 1 and previous_hp > hp:
			game.show_damage(global_position + Vector2(body_size.x / 2 + 22, -body_size.y / 2 - 12), previous_hp - hp)
	if hp == 0:
		dead = true
		if is_instance_valid(game):
			game.actor_defeated(self)
		queue_free()
	return "damaged"

func _hp_changed(_previous_hp: int) -> void:
	pass

func _absorb_attack() -> void:
	gauge = mini(T.GAUGE_CAPACITY, gauge + 1)

func take_gauge() -> int:
	var amount := gauge
	gauge = 0
	return amount

func shot_direction() -> Vector2:
	return Vector2(facing, 0)

func muzzle_offset(direction: Vector2) -> Vector2:
	# Intersection of the firing ray with the rectangular body, plus clearance.
	var half := body_size / 2
	var extent := minf(half.x / maxf(absf(direction.x), 0.0001), half.y / maxf(absf(direction.y), 0.0001))
	return direction * (extent + T.MUZZLE_CLEARANCE)

func _draw() -> void:
	var tint: Color = T.COLORS[polarity]
	# Fade the entire body, including its dark fill and markings, for a clear blink.
	if faction == 0 and invulnerability > 0 and hit_flash <= 0 and fmod(invulnerability, T.INVULNERABILITY_BLINK_PERIOD) < T.INVULNERABILITY_BLINK_PERIOD / 2:
		modulate.a = T.INVULNERABILITY_BLINK_ALPHA
	else:
		modulate.a = 1.0
	if hit_flash > 0:
		tint = Color.WHITE
	var rect := Rect2(-body_size * 0.5, body_size)
	if kind == "player":
		draw_set_transform(Vector2(0, body_size.y * 0.5 * (1.0 - visual_scale.y)), 0, visual_scale)
		draw_rect(Rect2(-18, 19, 36, 5), Color(0, 0, 0, 0.25))
		draw_style_box(_body_style(tint), rect)
		draw_rect(Rect2(-11, -13, 22, 9), Color("102533"))
		var direction := shot_direction()
		draw_line(direction * 10, muzzle_offset(direction), tint, 8)
		draw_line(Vector2(-8, 15), Vector2(-8, 24), tint, 5)
		draw_line(Vector2(8, 15), Vector2(8, 24), tint, 5)
	elif kind == "boss":
		var points := PackedVector2Array([Vector2(-53, -32), Vector2(-30, -58), Vector2(30, -58), Vector2(53, -32), Vector2(53, 36), Vector2(28, 58), Vector2(-28, 58), Vector2(-53, 36)])
		draw_colored_polygon(points, Color("152d40"))
		points.append(points[0])
		draw_polyline(points, tint, 4, true)
		draw_circle(Vector2.ZERO, 27, tint.darkened(0.65))
		draw_arc(Vector2.ZERO, 29, 0, TAU, 36, tint, 3, true)
		draw_line(Vector2(-58, -12), Vector2(-30, -12), tint, 10)
		draw_line(Vector2(-58, 22), Vector2(-30, 22), tint, 10)
	elif kind == "flyer":
		draw_colored_polygon(PackedVector2Array([Vector2(-19, 6), Vector2(-34, -18), Vector2(-10, -9), Vector2(0, -20), Vector2(10, -9), Vector2(34, -18), Vector2(19, 6), Vector2(0, 22)]), tint.darkened(0.65))
		draw_polyline(PackedVector2Array([Vector2(-34, -18), Vector2(-19, 6), Vector2(0, 22), Vector2(19, 6), Vector2(34, -18)]), tint, 3, true)
		draw_arc(Vector2(0, 25), 11, 0.2, PI - 0.2, 16, tint, 2, true)
	elif kind == "laser":
		draw_style_box(_body_style(tint.darkened(0.7)), rect)
		draw_line(Vector2(-24, 22), Vector2(24, 22), tint, 5)
		draw_arc(Vector2(facing * 14, -4), 13, 0, TAU, 24, tint, 4, true)
		draw_circle(Vector2(facing * 22, -4), 5, Color.WHITE)
	elif kind == "breaker":
		draw_colored_polygon(PackedVector2Array([Vector2(-19, 20), Vector2(-19, 0), Vector2(-10, -20), Vector2(10, -20), Vector2(19, 0), Vector2(19, 20)]), tint.darkened(0.65))
		draw_arc(Vector2(0, -10), 14, PI, TAU, 20, tint, 5)
		draw_line(Vector2(-24, 21), Vector2(24, 21), tint, 5)
	elif kind == "builder":
		draw_rect(rect, tint.darkened(0.7))
		for y in [-18, -4, 10]:
			draw_rect(Rect2(-19, y, 38, 12), tint, false, 2)
		draw_line(Vector2(0, -25), Vector2(0, 20), tint, 3)
	elif kind == "shifter":
		var diamond := PackedVector2Array([Vector2(0, -25), Vector2(23, 0), Vector2(0, 23), Vector2(-23, 0)])
		draw_colored_polygon(diamond, tint.darkened(0.7))
		diamond.append(diamond[0])
		draw_polyline(diamond, tint, 3, true)
	else:
		draw_style_box(_body_style(tint.darkened(0.6)), rect)
		draw_rect(rect, tint, false, 2)
		draw_line(Vector2(facing * 12, -4), Vector2(facing * 28, -4), tint, 7)
		if kind == "walker":
			draw_circle(Vector2(-11, 22), 5, tint)
			draw_circle(Vector2(11, 22), 5, tint)
	var mark := "A" if polarity == 0 else "B"
	draw_string(ThemeDB.fallback_font, Vector2(-6, 9), mark, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, tint if faction == 1 else Color("102533"))
	draw_set_transform(Vector2.ZERO)
	if lock_marked:
		# White corner brackets with dark outlines differ from both bullet colors.
		var center := Vector2(0, -body_size.y / 2 - 56)
		for x in [-1, 1]:
			for y in [-1, 1]:
				var corner := center + Vector2(x, y) * T.LOCK_MARK_SIZE
				var points := PackedVector2Array([corner - Vector2(x * 6, 0), corner, corner - Vector2(0, y * 6)])
				draw_polyline(points, Color("07111d"), 5, true)
				draw_polyline(points, Color.WHITE, 2, true)
	if absorb_flash > 0:
		draw_arc(Vector2.ZERO, body_size.x * 0.65 + (0.28 - absorb_flash) * 55, 0, TAU, 32, Color(tint, absorb_flash * 3), 3, true)
	if faction == 1:
		var width := body_size.x + 12
		var hp_text := str(hp)
		var font := ThemeDB.fallback_font
		var hp_width := font.get_string_size(hp_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		var hp_position := Vector2(-hp_width / 2, -body_size.y / 2 - 12)
		draw_string_outline(font, hp_position, hp_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 4, Color("07111d"))
		draw_string(font, hp_position, hp_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("f3f7fb"))
		for i in range(gauge):
			draw_rect(Rect2(-width / 2 + i * width / T.GAUGE_CAPACITY, -body_size.y / 2 - 40, width / T.GAUGE_CAPACITY - 1, 3), tint)
	if action.begins_with("windup"):
		var warning_color: Color = T.COLORS[next_polarity] if action == "windup_switch" else tint
		var radius := body_size.x * 0.7 + 5 + sin(Time.get_ticks_msec() * 0.025) * 3
		draw_arc(Vector2.ZERO, radius, 0, TAU, 40, warning_color, 2, true)
		var message := "切替 → " + ("A" if next_polarity == 0 else "B") if action == "windup_switch" else ("誘導弾 !" if action == "windup_special" else "!")
		draw_string(ThemeDB.fallback_font, Vector2(-30, -body_size.y / 2 - 54), message, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, warning_color)

func _body_style(tint: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = tint
	style.set_corner_radius_all(5)
	return style
