extends "res://tests/test_tree.gd"
const Main := preload("res://scripts/main.gd")
const Combatant := preload("res://scripts/combatant.gd")
const T := preload("res://scripts/tuning.gd")
const Physics := preload("res://tests/ability_physics_test.gd")
var game: Node2D
var checks := 0
var failures: Array[String] = []

class QuietUI extends CanvasLayer:
	func update_hud() -> void: pass
class Fixture extends Main:
	func _ready() -> void:
		key_bindings = KeyBindings.new()
		key_bindings.apply()
		streaming_enabled = false
		stage = {"bounds":Rect2(-500,-500,3000,2500),"start_position":Vector2(0,978)}
		world = Node2D.new()
		add_child(world)
		projectiles = Node2D.new()
		world.add_child(projectiles)
		effects = Effects.new()
		world.add_child(effects)
		camera = Camera2D.new()
		camera.position = Vector2(500,800)
		add_child(camera)
		ui = QuietUI.new()
		add_child(ui)
		player = Player.new()
		player.game = self
		player.position = Vector2(0,978)
		world.add_child(player)
		state = "playing"
	func _physics_process(_delta: float) -> void: pass

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)
func frames(n: int = 1) -> void:
	for i in range(n):
		test_progress()
		await physics_frame
		await process_frame
func action(name: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = name
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func target(at: Vector2, color: int = 1) -> CharacterBody2D:
	var actor := Combatant.new()
	actor.game = game
	actor.faction = 1
	actor.polarity = color
	actor.hp = 100
	actor.max_hp = 100
	actor.position = at
	game.world.add_child(actor)
	return actor
func clear_shots() -> void:
	for b in game.projectiles.get_children(): b.free()
func equip(id: String) -> void:
	check(game.equip(T.EQUIPMENT[id].slot,id), "equip owned " + id)
func remove(slot: String) -> void:
	check(game.equip(slot,""), "remove " + slot)

func run() -> void:
	game = Fixture.new()
	root.add_child(game)
	Physics.add_fixture(game.world,Rect2(-500,1000,3000,96))
	for id: String in T.EQUIPMENT: game.owned_equipment[id] = true
	await frames(4)
	var p = game.player
	check(p.is_on_floor() and p.hp==100 and p.max_hp==100, "unequipped base body and HP")
	check(p.shot_interval()==0.25 and p.move_speed()==320 and p.hurt_invulnerability()==1.5 and p.hit_damage(12)==12, "unequipped base combat values")
	check(p.charge_capacity()==5 and p.volley_size()==4 and p.absorptions_per_charge()==4, "unequipped base stock and absorption")
	action("shoot",true)
	await frames()
	check(game.projectiles.get_child_count()==1, "base normal fire creates one projectile")
	check(is_equal_approx(p.shot_cooldown,0.25), "base actual shot cooldown")
	action("shoot",false)
	clear_shots()
	p.shot_cooldown = 0
	equip("rapid")
	action("shoot",true)
	await frames()
	check(is_equal_approx(p.shot_cooldown,0.1875), "rapid fire actual cooldown is 25 percent shorter")
	action("shoot",false)
	remove("weapon")
	check(p.shot_interval()==T.SHOT_INTERVAL, "rapid removal restores interval")
	clear_shots()
	equip("triple")
	for facing in [-1,1]:
		p.facing = facing
		for aim in range(3):
			clear_shots()
			p.aim_index = aim
			p.fire_normal()
			check(game.projectiles.get_child_count()==3, "three actual projectiles in each facing and aim")
			var shots: Array = game.projectiles.get_children()
			check(is_equal_approx(shots[0].direction.angle_to(shots[1].direction),T.TRIPLE_SPREAD) and shots.all(func(b): return b.polarity==p.polarity and not b.homing), "triple spread and fired color")
	remove("weapon")
	clear_shots()
	p.fire_normal()
	check(game.projectiles.get_child_count()==1, "removing triple returns single shot")
	clear_shots()
	p.facing = 1
	p.aim_index = 0
	var a := target(p.position+Vector2(90,0))
	var b := target(p.position+Vector2(170,0))
	var c := target(p.position+Vector2(250,0))
	await frames(2)
	equip("pierce")
	p.fire_normal()
	p.polarity = 1 # In-flight bullet retains blue.
	await frames(25)
	check(a.hp==99 and b.hp==99 and c.hp==100, "piercing bullet hits exactly two enemies, once each, retaining color")
	check(game.projectiles.get_child_count()==0, "piercing projectile consumed by second body")
	remove("weapon")
	p.polarity = 0
	p.fire_normal()
	await frames(25)
	check(a.hp==98 and b.hp==99, "unequipped bullet stops on first enemy")
	a.free()
	b.free()
	c.free()
	var same := target(p.position+Vector2(90,0),0)
	Physics.add_fixture(game.world,Rect2(130,900,32,100))
	await frames(2)
	equip("pierce")
	p.fire_normal()
	await frames(20)
	check(same.hp==100 and same.gauge==1 and game.projectiles.get_child_count()==0, "same-color absorption once; piercing still stops at terrain")
	same.free()
	remove("weapon")
	p.hp = 50
	game.world.process_mode = Node.PROCESS_MODE_DISABLED
	equip("shell")
	check(p.max_hp==130 and p.hp==80, "shell adds 30 current and maximum HP")
	check(game.effects.health_display.maximum==130 and game.effects.player_hp_numbers.back().text=="+30", "shell addition updates HP display and healing number")
	var number_count: int = game.effects.player_hp_numbers.size()
	equip("shell")
	check(p.hp==80 and game.effects.player_hp_numbers.size()==number_count, "reselecting shell does not heal or display a change")
	remove("armor")
	check(p.max_hp==100 and p.hp==50, "shell removal subtracts 30 current and maximum HP: 80/130 to 50/100")
	check(game.effects.health_display.maximum==100 and game.effects.health_display.health==50 and game.effects.player_hp_numbers.back().text=="-30", "shell removal updates HP display and loss number")
	for i in range(5):
		equip("shell")
		check(p.max_hp==130 and p.hp==80 and p.max_hp-p.hp==50, "repeated shell addition preserves fifty missing HP")
		remove("armor")
		check(p.max_hp==100 and p.hp==50 and p.max_hp-p.hp==50, "repeated shell removal cannot heal during pause")
	equip("shell")
	p.hp = 130
	remove("armor")
	check(p.max_hp==100 and p.hp==100, "full shell HP 130/130 becomes 100/100 on removal")
	for replacement in ["", "cushion", "invincible"]:
		for health in [1, 15, 30, 31, 80]:
			equip("shell")
			p.hp = health
			p.invulnerability = 0
			p.hit_flash = 0
			var burst_count: int = game.effects.bursts.size()
			check(game.equip("armor",replacement), "replace shell with armor: " + replacement)
			check(p.max_hp==100 and p.hp==maxi(1,health-30), "shell replacement subtracts thirty with minimum one: %s at %d HP" % [replacement,health])
			check(not p.dead and game.state=="playing" and p.invulnerability==0 and p.hit_flash==0 and game.effects.bursts.size()==burst_count, "shell HP loss causes no death, invulnerability or hit effects")
			check(game.effects.health_display.maximum==100 and game.effects.health_display.health==p.hp, "shell replacement refreshes HP display even at one HP")
			if health > 1:
				check(game.effects.player_hp_numbers.back().text==str(p.hp-health), "shell replacement displays actual HP loss after minimum-one clamp")
	# Equipment changes must also preserve an existing invulnerability timer.
	equip("shell")
	p.invulnerability = 0.5
	remove("armor")
	check(p.invulnerability==0.5, "shell removal does not restart existing invulnerability")
	p.invulnerability = 0
	game.world.process_mode = Node.PROCESS_MODE_INHERIT
	p.hp = 100
	equip("cushion")
	p.invulnerability = 0
	p.receive_hit(1,12)
	check(p.hp==91, "armor reduces actual damage 12 to 9")
	p.invulnerability = 0
	p.receive_hit(1,1)
	check(p.hp==90, "armor minimum damage remains 1")
	remove("armor")
	p.invulnerability = 0
	p.receive_hit(1,12)
	check(p.hp==78, "removal restores actual damage")
	equip("invincible")
	p.invulnerability = 0
	p.receive_hit(1,1)
	check(is_equal_approx(p.invulnerability,2.2), "actual hit grants 2.2 seconds of invulnerability")
	p.receive_hit(0,99)
	check(p.gauge==1, "same-color absorption remains active during invulnerability")
	remove("armor")
	p.invulnerability = 0
	p.receive_hit(1,1)
	check(is_equal_approx(p.invulnerability,1.5), "removal restores default invulnerability on next hit")
	equip("homing")
	p.add_homing_charges(100)
	check(p.homing_charges==6, "homing equipment raises stock cap to six")
	clear_shots()
	p.launch_homing()
	check(p.homing_charges==5 and game.projectiles.get_child_count()==5, "homing volley actually fires five projectiles for one stock")
	p.add_homing_charges(1)
	remove("charm")
	check(p.homing_charges==5 and p.volley_size()==4, "removal clamps stock and restores volley")
	clear_shots()
	p.launch_homing()
	check(game.projectiles.get_child_count()==4, "base actual volley restored")
	clear_shots()
	equip("absorb")
	p.gauge = 0
	p.homing_charges = 0
	for i in range(3): p.receive_hit(0,99)
	check(p.homing_charges==1 and p.gauge==0, "three actual absorptions make one charge")
	remove("charm")
	for i in range(3): p.receive_hit(0,99)
	check(p.homing_charges==1 and p.gauge==3, "base requires fourth absorption again")
	p.receive_hit(0,99)
	check(p.homing_charges==2 and p.gauge==0, "base fourth absorption grants charge")
	# Remove the wall fixture before the movement test.
	for child in game.world.get_children():
		if child is StaticBody2D and child.position.x==146: child.free()
	equip("boots")
	p.position = Vector2(0,978)
	action("move_left",true)
	await frames(10)
	check(is_equal_approx(p.velocity.x,-358.4), "boots alter actual movement speed by 12 percent")
	remove("charm")
	await frames(5)
	check(is_equal_approx(p.velocity.x,-320.0), "removing boots restores actual movement speed")
	action("move_left",false)
	check(not game.equip("weapon","boots") and not game.equip("other","rapid"), "wrong slot and invalid slot rejected")
	game.owned_equipment.erase("rapid")
	check(not game.equip("weapon","rapid"), "unowned equipment rejected")
	game.free()
	print("EQUIPMENT PHYSICS: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
