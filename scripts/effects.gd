extends Node2D
const T := preload("res://scripts/tuning.gd")
const Art := preload("res://scripts/sprite_art.gd")
const PlayerHealthDisplay := preload("res://scripts/player_health_display.gd")

var bursts: Array = []
var damage_numbers: Array = []
var damage_sequence := 0
var health_display: Node2D
var player_hp_numbers: Array = []
var charge_numbers: Array = []
var crystal_numbers: Array = []
var player: CharacterBody2D
const DAMAGE_LIFETIME := 0.8

func show_crystals(at: Vector2, amount: int) -> void:
	crystal_numbers.append({"at": at + Vector2(-56, -88), "text": "+%d" % amount, "age": 0.0})
	if crystal_numbers.size() > 32: crystal_numbers.pop_front()

func show_charge(at: Vector2, amount: int) -> void:
	charge_numbers.append({"at": at + Vector2(24, -68), "text": "誘導弾 +%d" % amount, "age": 0.0})
	if charge_numbers.size() > 32: charge_numbers.pop_front()

func emit(at: Vector2, tint: Color, kind: String) -> void:
	bursts.append({"at": at, "color": tint, "kind": kind, "age": 0.0})
	if bursts.size() > 100:
		bursts.pop_front()

func show_damage(at: Vector2, amount: int) -> void:
	if amount <= 0:
		return
	var lane := damage_sequence % 3 - 1
	damage_sequence += 1
	damage_numbers.append({"at": at, "amount": amount, "age": 0.0, "lane": lane})
	if damage_numbers.size() > 64:
		damage_numbers.pop_front()

func show_player_health(actor: CharacterBody2D, before: int, after: int) -> void:
	if before == after:
		if is_instance_valid(health_display): health_display.change(actor, before, after)
		return
	if not is_instance_valid(health_display):
		health_display = PlayerHealthDisplay.new()
		add_child(health_display)
	health_display.change(actor, before, after)
	var amount := after - before
	player_hp_numbers.append({"at": actor.global_position + Vector2(0, -actor.body_size.y / 2) + T.PLAYER_HP_NUMBER_OFFSET,
		"text": ("+" if amount > 0 else "") + str(amount), "age": 0.0,
		"color": T.PLAYER_HP_COLORS.healing if amount > 0 else T.PLAYER_HP_COLORS.red})
	if player_hp_numbers.size() > 32:
		player_hp_numbers.pop_front()

func aim_indicator_visible() -> bool:
	return is_instance_valid(player) and not player.dead and player.aim_indicator_remaining > 0

func aim_indicator_point() -> Vector2:
	return player.global_position + player.shot_direction() * T.AIM_INDICATOR_DISTANCE

func _draw_aim_indicator() -> void:
	# A chevron in the player's color, unlike the sprite of the boss arrow that
	# also circles the player.
	if not aim_indicator_visible(): return
	var direction: Vector2 = player.shot_direction()
	var side := direction.orthogonal()
	var at := aim_indicator_point()
	var alpha: float = player.aim_indicator_alpha()
	var fill := Color(T.COLORS[player.polarity].lightened(0.3), alpha)
	var outline := Color(0.03, 0.07, 0.11, alpha)
	var head := PackedVector2Array([at + direction * 20, at + direction * 4 + side * 12, at + direction * 4 - side * 12])
	draw_line(at - direction * 16, at + direction * 6, outline, 10)
	draw_line(at - direction * 14, at + direction * 6, fill, 5)
	var ring := head.duplicate()
	ring.append(head[0])
	draw_colored_polygon(head, fill)
	draw_polyline(ring, outline, 2.5, true)

func _process(delta: float) -> void:
	for number: Dictionary in crystal_numbers: number.age += delta
	crystal_numbers = crystal_numbers.filter(func(n): return n.age < T.PLAYER_HP_NUMBER_TIME)
	for number: Dictionary in charge_numbers: number.age += delta
	charge_numbers = charge_numbers.filter(func(n): return n.age < T.PLAYER_HP_NUMBER_TIME)
	for burst: Dictionary in bursts:
		burst.age += delta
	bursts = bursts.filter(func(b): return b.age < 0.45)
	for number: Dictionary in damage_numbers:
		number.age += delta
	damage_numbers = damage_numbers.filter(func(number): return number.age < DAMAGE_LIFETIME)
	for number: Dictionary in player_hp_numbers:
		number.age += delta
	player_hp_numbers = player_hp_numbers.filter(func(number): return number.age < T.PLAYER_HP_NUMBER_TIME)
	queue_redraw()

func _draw() -> void:
	for burst: Dictionary in bursts:
		var polarity := 0 if burst.color.b > burst.color.r else 1
		if Art.draw_frame(self,"burst",burst.kind,polarity,burst.age,burst.at,1): continue
		var fraction: float = burst.age / 0.45
		var tint: Color = burst.color
		tint.a = 1.0 - fraction
		var radius := 8.0 + fraction * (54.0 if burst.kind == "defeat" else 26.0)
		if burst.kind == "bomb":
			draw_circle(burst.at, T.BOMB_RADIUS * (1 - fraction), Color(tint, tint.a * 0.15))
			draw_arc(burst.at, T.BOMB_RADIUS, 0, TAU, 32, tint, 3, false)
		if burst.kind == "land" or burst.kind == "jump":
			for i in range(6):
				var side := -1.0 if i < 3 else 1.0
				var offset := Vector2(side * (8 + fraction * (30 + i * 4)), -sin(fraction * PI) * (5 + i * 2))
				draw_circle(burst.at + offset, (2.0 + fraction * 4) * (1 - fraction), tint)
		elif burst.kind == "absorb" or burst.kind == "switch":
			draw_arc(burst.at, radius, 0, TAU, 24, tint, 2, false)
		else:
			for i in range(8):
				var direction := Vector2.from_angle(i * TAU / 8)
				draw_line(burst.at + direction * radius * 0.55, burst.at + direction * radius, tint, 3, false)
	_draw_aim_indicator()
	var font := ThemeDB.fallback_font
	for number: Dictionary in crystal_numbers:
		var at: Vector2 = number.at + Vector2(0, -number.age * 36)
		var tint := Color(T.CRYSTAL_COLOR, clampf((1.0 - number.age) / 0.35, 0, 1))
		draw_string_outline(font, at, number.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 4, Color("07111d"))
		draw_string(font, at, number.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, tint)
	for number: Dictionary in charge_numbers:
		var at: Vector2 = number.at + Vector2(0, -number.age * 36)
		var tint := Color(1, 1, 1, clampf((1.0 - number.age) / 0.35, 0, 1))
		draw_string_outline(font, at, number.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 4, Color("07111d"))
		draw_string(font, at, number.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, tint)
	for number: Dictionary in player_hp_numbers:
		var at: Vector2 = number.at + Vector2(0, -number.age * T.PLAYER_HP_NUMBER_RISE)
		var alpha := clampf((T.PLAYER_HP_NUMBER_TIME - float(number.age)) / T.PLAYER_HP_FADE_TIME, 0.0, 1.0)
		var tint: Color = number.color
		tint.a = alpha
		draw_string_outline(font, at, number.text, HORIZONTAL_ALIGNMENT_CENTER, -1, 24, 5, Color(0.02, 0.04, 0.07, alpha))
		draw_string(font, at, number.text, HORIZONTAL_ALIGNMENT_CENTER, -1, 24, tint)
	for number: Dictionary in damage_numbers:
		var text := str(number.amount)
		var font_size := 26 if number.amount >= 4 else 22
		var alpha := clampf((DAMAGE_LIFETIME - float(number.age)) / 0.3, 0.0, 1.0)
		var at: Vector2 = number.at + Vector2(number.lane * (12 + number.age * 8), -number.age * 64)
		at.x -= font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x / 2
		draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 5, Color(0.02, 0.04, 0.07, alpha))
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1.0, 0.86, 0.42, alpha))
