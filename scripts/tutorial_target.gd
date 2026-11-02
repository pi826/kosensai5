extends "res://scripts/combatant.gd"
var target_id := ""
var neutral := false
var required_aim := -1 # Only the two direction-practice targets restrict shots.

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

func receive_projectile_hit(bullet: Node2D) -> String:
	if required_aim >= 0 and (bullet.faction != 0 or bullet.homing or bullet.get_meta("tutorial_aim_index", -1) != required_aim):
		hit_flash = 0.25
		queue_redraw()
		game.show_aim_hint(target_id)
		return "protected"
	return receive_hit(bullet.polarity, bullet.damage)

func _draw() -> void:
	if not neutral:
		super._draw()
		return
	if preload("res://scripts/sprite_art.gd").draw_frame(self,"target","idle",0,art_time,Vector2(0,body_size.y/2),1):
		if required_aim >= 0 and hit_flash > 0: draw_arc(Vector2.ZERO,26,0,TAU,32,Color("b9f4ff"),3,true)
		return
	draw_rect(Rect2(-body_size / 2, body_size), Color("203b48"))
	draw_circle(Vector2.ZERO, 18, Color("eefaff"))
	draw_circle(Vector2.ZERO, 11, Color("355d6e"))
	draw_circle(Vector2.ZERO, 4, Color("eefaff"))
	if required_aim >= 0 and hit_flash > 0:
		draw_circle(Vector2.ZERO, 23, Color(1, 1, 1, hit_flash * 2))
		draw_arc(Vector2.ZERO, 26, 0, TAU, 32, Color("b9f4ff"), 3, true)
