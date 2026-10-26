extends "res://scripts/combatant.gd"
var target_id := ""
var neutral := false

func _ready() -> void:
	faction = 1
	kind = "turret"
	body_size = T.ENEMY_SIZE
	max_hp = T.ENEMY_HP
	hp = max_hp
	super._ready()

func _physics_process(delta: float) -> void:
	tick_visuals(delta)
	facing = 1 if game.player.position.x > position.x else -1

func receive_hit(attack_color: int, damage: int) -> String:
	# White practice targets accept both colors. Colored enemies share combat rules.
	if neutral: attack_color = 1 - polarity
	return super.receive_hit(attack_color, damage)

func _draw() -> void:
	if not neutral:
		super._draw()
		return
	draw_rect(Rect2(-body_size / 2, body_size), Color("203b48"))
	draw_circle(Vector2.ZERO, 18, Color("eefaff"))
	draw_circle(Vector2.ZERO, 11, Color("355d6e"))
	draw_circle(Vector2.ZERO, 4, Color("eefaff"))
