extends "res://tests/test_tree.gd"
const Main := preload("res://scripts/main.gd")
const T := preload("res://scripts/tuning.gd")
const Combatant := preload("res://scripts/combatant.gd")
const Physics := preload("res://tests/ability_physics_test.gd")
var game: Node2D
var checks := 0
var failures: Array[String] = []

class QuietUI extends CanvasLayer:
	func update_hud() -> void: pass

class EffectFixture extends "res://scripts/main.gd":
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

class BossActor extends CharacterBody2D:
	var game: Node2D
	var faction := 1
	var kind := "boss"
	var boss_role := "final"
	var boss_id := 0
	var spawn_id := ""
	var polarity := 1
	var hp := 100
	var max_hp := 100
	var dead := false

class StubCycle extends RefCounted:
	var game: Node2D
	var final_clears := 0
	var guardian_kills := 0
	var secret_kills := 0
	var phase := "guardians"
	var records: Dictionary = {}
	var live_actors: Dictionary = {}
	func defeated(actor) -> void:
		if actor.boss_role == "final":
			final_clears += 1
			game.update_loop_scaling()
	func objective() -> String: return ""
	func service() -> void: pass
	func shutdown() -> void: pass

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

func next_decision() -> void:
	OS.delay_msec(ceili(T.SHOP_ACTION_INTERVAL * 1000) + 5)
	await frames()

func key(code: int, pressed: bool = true, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func tap(code: int) -> void:
	key(code)
	key(code, false)

func clear_shots() -> void:
	for bullet in game.projectiles.get_children():
		bullet.free()

func freeze() -> void:
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	for group in ["enemies", "hearts", "loot"]:
		for actor in get_nodes_in_group(group):
			actor.set_physics_process(false)

func effect_checks() -> void:
	game = EffectFixture.new()
	root.add_child(game)
	Physics.add_fixture(game.world, Rect2(-500, 1000, 3000, 96))
	for id: String in T.EQUIPMENT:
		game.owned_equipment[id] = true
	await frames(4)
	var p = game.player
	check(p.is_on_floor() and p.hp == 100 and p.max_hp == 100, "effect fixture starts on the floor at base HP")
	check(T.RAPID_INTERVAL_RATIOS[0] == T.RAPID_INTERVAL_RATIO and T.TRIPLE_COUNTS[0] == 3 and T.PIERCE_COUNTS[0] == T.BULLET_PENETRATIONS, "level arrays keep the original Lv1 rapid, triple and pierce values")
	check(T.SHELL_HP_BONUSES[0] == T.SHELL_HP_BONUS and T.ARMOR_DAMAGE_RATIOS[0] == T.ARMOR_DAMAGE_RATIO and T.LONG_INVULNERABILITY_BONUSES[0] == T.LONG_INVULNERABILITY_BONUS, "level arrays keep the original Lv1 armor values")
	check(T.HOMING_CAPACITY_BONUSES[0] == T.HOMING_CAPACITY_BONUS and T.HOMING_VOLLEY_BONUSES[0] == T.HOMING_VOLLEY_BONUS and T.EFFICIENT_ABSORPTION_COUNTS[0] == T.EFFICIENT_ABSORPTIONS and T.BOOTS_SPEED_RATIOS[0] == T.BOOTS_SPEED_RATIO, "level arrays keep the original Lv1 charm values")

	for level in range(1, 4):
		game.equipment_levels["rapid"] = level
		game.equip("weapon", "rapid")
		check(is_equal_approx(p.shot_interval(), T.SHOT_INTERVAL * T.RAPID_INTERVAL_RATIOS[level - 1]), "rapid Lv%d interval" % level)
		game.equipment_levels["boots"] = level
		game.equip("charm", "boots")
		check(is_equal_approx(p.move_speed(), T.MOVE_SPEED * T.BOOTS_SPEED_RATIOS[level - 1]), "boots Lv%d speed" % level)
		game.equipment_levels["cushion"] = level
		game.equip("armor", "cushion")
		check(p.hit_damage(12) == ceili(12 * T.ARMOR_DAMAGE_RATIOS[level - 1]) and p.hit_damage(1) == 1, "cushion Lv%d damage" % level)
		game.equipment_levels["invincible"] = level
		game.equip("armor", "invincible")
		check(is_equal_approx(p.hurt_invulnerability(), T.INVULNERABILITY + T.LONG_INVULNERABILITY_BONUSES[level - 1]), "invincible Lv%d duration" % level)
		game.equipment_levels["homing"] = level
		game.equip("charm", "homing")
		check(p.charge_capacity() == T.HOMING_CHARGE_CAPACITY + T.HOMING_CAPACITY_BONUSES[level - 1] and p.volley_size() == T.HOMING_VOLLEY_SIZE + T.HOMING_VOLLEY_BONUSES[level - 1], "homing Lv%d stock and volley" % level)
		game.equipment_levels["absorb"] = level
		game.equip("charm", "absorb")
		check(p.absorptions_per_charge() == T.EFFICIENT_ABSORPTION_COUNTS[level - 1], "absorb Lv%d requirement" % level)
		p.hp = 100
		p.max_hp = 100
		game.equipment_levels["shell"] = level
		game.equip("armor", "shell")
		check(p.max_hp == T.PLAYER_HP + T.SHELL_HP_BONUSES[level - 1] and p.hp == p.max_hp, "shell Lv%d maximum and current HP" % level)
		game.equip("armor", "")
		p.hp = 100
		p.max_hp = 100

	p.facing = 1
	p.aim_index = 0
	for level in range(1, 4):
		game.equipment_levels["triple"] = level
		game.equip("weapon", "triple")
		clear_shots()
		p.fire_normal()
		var shots: Array = game.projectiles.get_children()
		var expected: int = T.TRIPLE_COUNTS[level - 1]
		check(shots.size() == expected, "triple Lv%d fires %d projectiles" % [level, expected])
		var spread_ok := true
		for i in range(shots.size()):
			var angle: float = (i - (expected - 1) / 2.0) * T.TRIPLE_SPREAD
			if not is_equal_approx(shots[i].direction.angle(), angle): spread_ok = false
		check(spread_ok, "triple Lv%d projectile spread" % level)

	for level in range(1, 4):
		game.equipment_levels["pierce"] = level
		game.equip("weapon", "pierce")
		clear_shots()
		var targets: Array = []
		for i in range(4):
			var target := Combatant.new()
			target.game = game
			target.faction = 1
			target.polarity = 1
			target.hp = 100
			target.max_hp = 100
			target.position = p.position + Vector2(90 + i * 80, 0)
			game.world.add_child(target)
			targets.append(target)
		await frames(2)
		p.fire_normal()
		await frames(25)
		var hits := 0
		for target in targets:
			if target.hp == 99: hits += 1
		check(hits == level + 1, "pierce Lv%d hits %d enemies" % [level, level + 1])
		check(game.projectiles.get_child_count() == 0, "pierce Lv%d projectile is consumed" % level)
		for target in targets:
			target.free()
		clear_shots()
	game.free()
	game = null

func equipment_text_checks() -> void:
	var expected := {
		"rapid": ["射撃の間隔 −25%", "射撃の間隔 −38%", "射撃の間隔 −50%"],
		"triple": ["3発に広がる", "4発に広がる", "5発に広がる"],
		"pierce": ["敵を1体貫通", "敵を2体貫通", "敵を3体貫通"],
		"shell": ["最大HP+30", "最大HP+50", "最大HP+70"],
		"cushion": ["受けるダメージ −25%", "受けるダメージ −35%", "受けるダメージ −45%"],
		"invincible": ["無敵時間+0.7秒", "無敵時間+1.0秒", "無敵時間+1.3秒"],
		"homing": ["ストック上限+1、発射数+1", "ストック上限+2、発射数+2", "ストック上限+3、発射数+3"],
		"absorb": ["吸収3回で1ストック", "吸収2回で1ストック", "吸収1回で1ストック"],
		"boots": ["移動速度+12%", "移動速度+20%", "移動速度+28%"],
	}
	for id: String in expected:
		for level in range(1, 4):
			check(game.equipment_effect_text(id, level) == expected[id][level - 1], "%s Lv%d effect text" % [id, level])

func token_checks() -> void:
	check(game.upgrade_tokens == 0, "new run starts with no upgrade token")
	for id: String in T.EQUIPMENT:
		check(game.equipment_level(id) == 1, "new run starts %s at Lv1" % id)
	game.equipment_levels["rapid"] = 99
	check(game.equipment_level("rapid") == T.EQUIPMENT_MAX_LEVEL, "equipment level clamps to the maximum")
	game.equipment_levels.clear()

	var guardian := BossActor.new()
	guardian.game = game
	guardian.boss_role = "guardian"
	guardian.boss_id = 9001
	guardian.spawn_id = "test:guardian"
	guardian.position = game.player.position + Vector2(600, 0)
	game.world.add_child(guardian)
	game.actor_defeated(guardian)
	check(game.upgrade_tokens == 0, "guardian defeat does not grant a token")

	var secret := BossActor.new()
	secret.game = game
	secret.boss_role = "secret"
	secret.boss_id = 9002
	secret.spawn_id = "test:secret"
	secret.position = game.player.position + Vector2(700, 0)
	game.world.add_child(secret)
	game.actor_defeated(secret)
	check(game.upgrade_tokens == 0, "secret defeat does not grant a token")

	var walker := BossActor.new()
	walker.game = game
	walker.faction = 1
	walker.kind = "walker"
	walker.boss_role = "normal"
	walker.spawn_id = "test:normal"
	walker.hp = 1
	walker.max_hp = 1
	walker.position = game.player.position + Vector2(800, 0)
	game.world.add_child(walker)
	game.actor_defeated(walker)
	check(game.upgrade_tokens == 0, "normal enemy defeat does not grant a token")
	walker.free()

	var final := BossActor.new()
	final.game = game
	final.boss_role = "final"
	final.boss_id = 9003
	final.spawn_id = "test:final"
	final.position = game.player.position + Vector2(900, 0)
	game.world.add_child(final)
	game.actor_defeated(final)
	check(game.upgrade_tokens == 1, "first final boss defeat grants one token")
	check(game.loot_message.contains(T.LOOP_COUNT_NOTICE) and game.loot_message.contains("装備を1つ強化できる（商人の「強化」）"), "loop and upgrade notices share the loot message")
	check(game.ui.loot_notice.text.contains("装備を1つ強化できる（商人の「強化」）"), "HUD shows the upgrade notice")
	var notice_size: Vector2 = game.ui.loot_notice.get_theme_font("font").get_multiline_string_size(game.ui.loot_notice.text, HORIZONTAL_ALIGNMENT_CENTER, game.ui.loot_notice.size.x, 20)
	check(notice_size.y <= game.ui.loot_notice.size.y, "upgrade notice fits the HUD notice area")
	game.actor_defeated(final)
	check(game.upgrade_tokens == 1, "duplicate final boss defeat does not grant another token")
	guardian.free()
	secret.free()
	final.free()

	var prices := {"rapid": [45, 90], "triple": [100, 200], "pierce": [90, 180], "shell": [50, 100], "cushion": [75, 150], "invincible": [60, 120], "homing": [65, 130], "absorb": [80, 160], "boots": [40, 80]}
	for id: String in prices:
		game.equipment_levels[id] = 1
		check(game.upgrade_price(id) == prices[id][0], "%s Lv1 to Lv2 price" % id)
		game.equipment_levels[id] = 2
		check(game.upgrade_price(id) == prices[id][1], "%s Lv2 to Lv3 price" % id)
	game.equipment_levels.clear()

func merchant() -> Node2D:
	for npc in get_nodes_in_group("merchants"):
		if npc.get_parent() == game.world: return npc
	return null

func at_merchant() -> Node2D:
	var npc := merchant()
	game.player.position = npc.position + Vector2(-40, 0)
	game._update_camera(0, true)
	game._update_exploration()
	game.ui.update_hud()
	return npc

func shop_checks() -> void:
	for id: String in T.EQUIPMENT:
		game.owned_equipment[id] = true
	game.crystals = 0
	game.upgrade_tokens = 0
	var npc := at_merchant()
	check(npc != null, "a merchant exists in the starting sector")
	game.open_shop(npc)
	await frames(3)
	var panel = game.ui.shop_panel
	check(game.state == "shop" and panel.visible, "merchant shop opens")
	check(panel.upgrade_tab.visible and panel.buy_tab.visible, "merchant shop shows buy and upgrade tabs")
	tap(KEY_TAB)
	check(not panel.buying and not panel.upgrading, "Tab selects equipment")
	tap(KEY_TAB)
	check(panel.upgrading and not panel.buying, "Tab selects upgrade")
	tap(KEY_TAB)
	check(panel.buying and not panel.upgrading, "Tab returns to buy")
	tap(KEY_TAB)
	tap(KEY_TAB)
	await frames(2)
	check(panel.upgrading and panel.upgrade_buttons.size() == 9, "upgrade page lists all owned equipment")
	check(panel.status_label.text.contains("強化できる回数 0"), "upgrade page shows the remaining token count")

	var bounds := Rect2(Vector2.ZERO, panel.rows.size)
	var rects: Array[Rect2] = []
	for id: String in panel.upgrade_buttons:
		var button: Button = panel.upgrade_buttons[id]
		var rect := Rect2(button.position, button.size)
		check(bounds.encloses(rect), "%s upgrade card stays inside rows" % id)
		for other: Rect2 in rects:
			check(not rect.intersects(other), "%s upgrade card does not overlap" % id)
		rects.append(rect)
		var font := button.get_theme_font("font")
		var font_size := button.get_theme_font_size("font_size")
		var text_size := font.get_multiline_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, button.size.x - 58, font_size)
		check(text_size.y <= button.size.y - 16, "%s upgrade card text fits" % id)
		check(button.text.contains("Lv1 → Lv2") and button.text.contains("結晶 %d" % game.upgrade_price(id)), "%s upgrade card shows level change and price" % id)

	for id: String in T.EQUIPMENT:
		game.equipment_levels[id] = T.EQUIPMENT_MAX_LEVEL
	panel.refresh()
	for id: String in panel.upgrade_buttons:
		var button: Button = panel.upgrade_buttons[id]
		var font := button.get_theme_font("font")
		var font_size := button.get_theme_font_size("font_size")
		var text_size := font.get_multiline_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, button.size.x - 58, font_size)
		check(button.text.contains("Lv3（最大）") and text_size.y <= button.size.y - 16, "%s maximum upgrade card fits and says max" % id)
	for id: String in T.EQUIPMENT:
		game.equipment_levels[id] = 1
	panel.refresh()

	check(game.upgrade_reason("rapid") == "ラスボスを倒すと強化できます", "no-token upgrade reason")
	game.upgrade_tokens = 1
	game.crystals = 0
	check(game.upgrade_reason("rapid") == "結晶不足", "insufficient crystal upgrade reason")
	game.crystals = 1000
	game.equipment_levels["triple"] = T.EQUIPMENT_MAX_LEVEL
	check(game.upgrade_reason("triple") == "最大", "maximum-level upgrade reason")
	game.owned_equipment.erase("boots")
	check(game.upgrade_reason("boots") == "未所持", "unowned upgrade reason")
	game.owned_equipment["boots"] = true

	game.close_shop()
	check(game.upgrade_reason("rapid") == "商人の画面で強化できます", "upgrade reason outside the merchant screen")
	game.open_shop(npc)
	await frames(2)
	check(game.state == "shop", "merchant shop reopens")

	game.equipment_levels["rapid"] = 1
	game.upgrade_tokens = 1
	game.crystals = 1000
	panel.refresh()
	tap(KEY_TAB)
	tap(KEY_TAB)
	await frames(2)
	panel.upgrade_buttons["rapid"].grab_focus()
	tap(KEY_DOWN)
	check(panel.upgrade_buttons["triple"].has_focus(), "down arrow moves between upgrade cards")
	panel.upgrade_buttons["rapid"].grab_focus()
	tap(KEY_ENTER)
	await frames(2)
	check(game.equipment_level("rapid") == 2, "Enter upgrades the focused card")
	check(game.upgrade_tokens == 0 and game.crystals == 955, "keyboard upgrade consumes one token and the Lv1 price")
	check(panel.status_label.text.contains("速射の銃身を Lv2 に強化しました"), "upgrade success message appears")

	game.equipment_levels["triple"] = 1
	game.upgrade_tokens = 2
	game.crystals = 1000
	await next_decision()
	check(game.upgrade_item("triple"), "first of two upgrades succeeds")
	check(not game.upgrade_item("triple"), "immediate second upgrade is blocked by the shop interval")
	check(game.equipment_level("triple") == 2 and game.upgrade_tokens == 1, "blocked second upgrade keeps the level")
	await next_decision()
	check(game.upgrade_item("triple") and game.equipment_level("triple") == 3 and game.upgrade_tokens == 0, "two tokens raise the same item to Lv3")

	game.equipment_levels["pierce"] = 1
	game.upgrade_tokens = 1
	game.crystals = 1000
	await next_decision()
	check(game.upgrade_item("pierce"), "one-token upgrade succeeds")
	await next_decision()
	check(not game.upgrade_item("pierce") and game.equipment_level("pierce") == 2 and game.upgrade_tokens == 0, "one token cannot upgrade twice")

	game.equipment_levels["shell"] = 1
	check(game.equip("armor", "shell"), "shell equips for the upgrade test")
	game.player.hp = game.player.max_hp
	game.upgrade_tokens = 1
	game.crystals = 1000
	await next_decision()
	check(game.upgrade_item("shell"), "equipped shell upgrade succeeds")
	check(game.player.max_hp == 150 and game.player.hp == 150, "equipped shell upgrade adds 20 to maximum and current HP")

	game.equipment_levels["rapid"] = 2
	check(game.equip("weapon", "rapid"), "rapid equips for the HUD test")
	game.close_shop()
	game.ui.update_hud()
	check(game.ui.equipment_labels["weapon"].text.contains("速射の銃身 Lv2"), "HUD shows equipment level")
	game.open_shop(npc)
	await frames(2)
	tap(KEY_TAB)
	await frames(2)
	check(panel.current_cards["weapon"].text.contains("速射の銃身 Lv2"), "equipment tab current card shows level")
	check(panel.equipment_buttons["weapon:rapid"].text.contains("速射の銃身 Lv2"), "equipment tab choice shows level")

	tap(KEY_TAB)
	await frames(2)
	for id: String in T.EQUIPMENT:
		if T.EQUIPMENT[id].slot == "armor": game.owned_equipment.erase(id)
	panel._rebuild()
	var empty_labels := 0
	for child in panel.rows.get_children():
		if child is Label and child.text == "まだ持っていません": empty_labels += 1
	check(empty_labels == 1, "an empty equipment column shows the empty message")
	for id: String in T.EQUIPMENT:
		game.owned_equipment[id] = true
	panel._rebuild()

	game.close_shop()
	game.show_menu("paused")
	game.open_equipment()
	check(not panel.can_buy and not panel.upgrade_tab.visible and not panel.buying and not panel.upgrading, "pause equipment has no upgrade tab")
	game.close_shop()
	game.resume_run()
	game.player.invulnerability = 0
	game.player.receive_hit(1 - game.player.polarity, 9999)
	await frames(3)
	check(game.state == "lost", "lethal hit reaches the retry menu")
	game.primary_action()
	check(game.upgrade_tokens == 0 and game.equipment_levels.is_empty(), "retry resets upgrade tokens and levels")
	for id: String in T.EQUIPMENT:
		check(game.equipment_level(id) == 1, "retry restores %s to Lv1" % id)

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://builds/qa/merchant")
	await effect_checks()
	game = Main.new()
	game.controls_path = "res://builds/qa/merchant/test_controls.cfg"
	root.add_child(game)
	game.key_bindings.reset_defaults()
	game.start_run(37)
	await frames(4)
	freeze()
	game.boss_cycle = StubCycle.new()
	game.boss_cycle.game = game
	equipment_text_checks()
	token_checks()
	await shop_checks()
	game.free()
	FileAccess.open("res://builds/qa/merchant/equipment_upgrade_results.json", FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures}, "\t"))
	print("EQUIPMENT UPGRADE: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
