extends "res://scripts/player.gd"
## The sole combat exception in practice: a different-color hit leaves HP >= 1.
func receive_hit(attack_color: int, damage: int) -> String:
	var result := super.receive_hit(attack_color, mini(damage, maxi(0, hp - 1)))
	if result == "absorbed": game.absorptions += 1
	return result

func heal(amount: int) -> int:
	var gained := super.heal(amount)
	if gained > 0:
		game.healing_events += 1
		if game.lesson == 9 and amount == T.HEART_HEAL: game.heart_healed = true
	return gained
