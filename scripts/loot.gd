extends Node2D
## Keys/crystals are touch pickups; chests require an explicit interaction.
const T := preload("res://scripts/tuning.gd")
var game: Node2D
var spawn: Dictionary
var opened := false
var collected := false

func _ready() -> void:
	opened = spawn.kind == "chest" and game.loot_taken.has(spawn.id)
	add_to_group("loot")

func _physics_process(_delta: float) -> void:
	if spawn.kind != "chest": try_collect()

func try_collect() -> bool:
	if collected or is_queued_for_deletion() or not is_instance_valid(game.player) or game.player.dead: return false
	if not Rect2(game.player.position - game.player.body_size / 2, game.player.body_size).intersects(Rect2(position - T.LOOT_SIZE / 2, T.LOOT_SIZE)): return false
	if game.loot_taken.has(spawn.id): return false
	game.loot_taken[spawn.id] = true
	game.discovered_loot.erase(spawn.id)
	collected = true
	if spawn.kind == "key": game.keys += 1
	elif spawn.kind == "crystal": game.add_crystals(spawn.amount)
	queue_free()
	return true

func try_open() -> bool:
	if opened or spawn.kind != "chest" or game.loot_taken.has(spawn.id): return false
	if not is_instance_valid(game.player) or game.player.dead or game.player.position.distance_to(position) > T.INTERACT_DISTANCE: return false
	if game.keys <= 0:
		game.loot_ability = 0
		game.loot_message = "鍵が必要"
		game.loot_message_remaining = T.KEY_NEEDED_TIME
		return false
	game.keys -= 1
	game.loot_taken[spawn.id] = true
	game.discovered_loot.erase(spawn.id)
	opened = true
	# Tagged contents leave room for equipment/potions in 6B.
	for content: Dictionary in spawn.contents: game.grant_loot(content)
	queue_redraw()
	return true

func _draw() -> void:
	if spawn.kind == "key":
		draw_circle(Vector2(-6, -4), 7, Color("ffdf80"), false, 3, true)
		draw_line(Vector2(-1, 1), Vector2(12, 14), Color("ffdf80"), 3, true)
		draw_line(Vector2(7, 9), Vector2(12, 4), Color("ffdf80"), 3, true)
	elif spawn.kind == "crystal":
		draw_colored_polygon(PackedVector2Array([Vector2(0,-15),Vector2(10,0),Vector2(0,15),Vector2(-10,0)]), T.CRYSTAL_COLOR)
	else:
		var ability: bool = spawn.contents.any(func(c): return c.kind == "ability")
		var tint := T.CRYSTAL_COLOR if ability else Color("ffdf80")
		draw_rect(Rect2(-20, -8, 40, 24), Color("394552") if opened else Color("78644b"))
		draw_rect(Rect2(-20, -8, 40, 24), tint, false, 2)
		draw_rect(Rect2(-20, -22 if opened else -16, 40, 10), tint)
		if not opened:
			draw_rect(Rect2(-3, -7, 6, 10), Color("102235"))
			if ability: draw_circle(Vector2(0, -28), 4, tint)
