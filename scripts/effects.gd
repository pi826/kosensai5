extends Node2D
const T := preload("res://scripts/tuning.gd")
const PlayerHealthDisplay := preload("res://scripts/player_health_display.gd")

var bursts: Array = []
var damage_numbers: Array = []
var damage_sequence := 0
var health_display: Node2D
var player_hp_numbers: Array = []
const DAMAGE_LIFETIME := 0.8

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

func _process(delta: float) -> void:
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
		var fraction: float = burst.age / 0.45
		var tint: Color = burst.color
		tint.a = 1.0 - fraction
		var radius := 8.0 + fraction * (54.0 if burst.kind == "defeat" else 26.0)
		if burst.kind == "bomb":
			draw_circle(burst.at, T.BOMB_RADIUS * (1 - fraction), Color(tint, tint.a * 0.15))
			draw_arc(burst.at, T.BOMB_RADIUS, 0, TAU, 32, tint, 3, true)
		if burst.kind == "land" or burst.kind == "jump":
			for i in range(6):
				var side := -1.0 if i < 3 else 1.0
				var offset := Vector2(side * (8 + fraction * (30 + i * 4)), -sin(fraction * PI) * (5 + i * 2))
				draw_circle(burst.at + offset, (2.0 + fraction * 4) * (1 - fraction), tint)
		elif burst.kind == "absorb" or burst.kind == "switch":
			draw_arc(burst.at, radius, 0, TAU, 24, tint, 2, true)
		else:
			for i in range(8):
				var direction := Vector2.from_angle(i * TAU / 8)
				draw_line(burst.at + direction * radius * 0.55, burst.at + direction * radius, tint, 3, true)
	var font := ThemeDB.fallback_font
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
