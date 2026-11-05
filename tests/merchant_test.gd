extends "res://tests/test_tree.gd"
const Main := preload("res://scripts/main.gd")
const T := preload("res://scripts/tuning.gd")
const S := preload("res://scripts/sector_generator.gd")
const G := preload("res://scripts/stage_generator.gd")
const Driver := preload("res://tests/ability_driver.gd")
const Support := preload("res://tests/stream_test_support.gd")
var game: Node2D
var checks := 0
var failures: Array[String] = []
var traversal := {}

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
func key(code: int, pressed: bool = true, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func tap(code: int) -> void:
	key(code)
	key(code,false)
func click(button: Button) -> void:
	await frames(3)
	var at := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	root.push_input(motion, true)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
		Input.flush_buffered_events()
	await frames(2)
func next_decision() -> void:
	OS.delay_msec(ceili(T.SHOP_ACTION_INTERVAL*1000)+5)
	await frames()
func merchant(id: String = "") -> Node2D:
	for npc in get_nodes_in_group("merchants"):
		if npc.get_parent()==game.world and (npc.spawn.id==id or id.is_empty()): return npc
	return null
func freeze() -> void:
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	for group in ["enemies","hearts","loot"]:
		for actor in get_nodes_in_group(group): actor.set_physics_process(false)
func at_merchant() -> Node2D:
	var npc := merchant()
	game.player.position = npc.position+Vector2(-40,0)
	game._update_camera(0,true)
	game._update_exploration()
	game.ui.update_hud()
	return npc
func route(driver: RefCounted, point: Vector2) -> bool:
	for attempt in range(8):
		var graph := S.navigation_graph([S.generate(game.current_seed,Vector2i.ZERO)])
		var steps := G.path_steps(graph,G.node_at(graph,driver.point()),G.node_at(graph,point),point)
		if steps.is_empty(): return false
		if await driver.follow(steps): return true
	return false

func physical_round_trip() -> void:
	var driver := Driver.new()
	driver.tree = self
	driver.game = game
	var npc := merchant()
	check(await driver.floor_wait(), "start on physical floor")
	check(await route(driver,npc.position), "initial inputs reach merchant: " + driver.error)
	check(game.player.abilities==0, "merchant route uses no unlocked abilities")
	game.loot_message_remaining = 0
	game.ui.update_hud()
	check(game.ui.loot_notice.text.contains("E で話す"), "nearby merchant shows current interaction key")
	var elapsed: float = game.elapsed
	var position: Vector2 = game.player.position
	tap(KEY_E)
	await frames(3)
	check(game.state=="shop" and game.ui.shop_panel.visible, "E opens merchant shop")
	var bullet: Node2D = game.spawn_bullet(game.player,Vector2.RIGHT)
	var bullet_position: Vector2 = bullet.position
	var enemy = get_nodes_in_group("enemies")[0]
	var enemy_clock: float = enemy.shot_clock
	await frames(30)
	check(game.world.process_mode==Node.PROCESS_MODE_DISABLED and game.elapsed==elapsed and game.player.position==position, "shop freezes simulation and player")
	check(bullet.position==bullet_position and enemy.shot_clock==enemy_clock, "shop freezes projectiles and enemy clocks")
	tap(KEY_E)
	await frames(2)
	check(game.state=="playing" and not game.ui.shop_panel.visible, "E closes shop and resumes")
	bullet.queue_free()
	check(await route(driver,T.SECTOR_START), "initial inputs return from merchant: " + driver.error)
	check(driver.max_player_step<=T.MAX_FALL_SPEED/60+1, "round trip contains no teleport or correction")
	traversal = {"seed":37,"frames":driver.frames,"jumps":driver.jumps,"maximum_step":driver.max_player_step,"error":driver.error}
	driver.release()

func shop_checks() -> void:
	freeze()
	var npc := at_merchant()
	check(not npc.is_in_group("combatants") and not npc.is_in_group("enemies"), "merchant is a peaceful NPC")
	check(game.discovered_merchants.has(npc.spawn.id) and game.ui.minimap.merchant_marks().any(func(m): return m.id==npc.spawn.id), "visible merchant discovered and marked on map")
	tap(KEY_E)
	await frames(3)
	var panel = game.ui.shop_panel
	check(panel.balance_label.text.contains("結晶 0"), "shop displays current crystals")
	check(panel.item_buttons.potion.text.contains("結晶不足"), "insufficient funds reason appears on row")
	panel.item_buttons.potion.grab_focus()
	tap(KEY_DOWN)
	check(panel.item_buttons.key.has_focus(), "down selects next purchase row")
	tap(KEY_UP)
	check(panel.item_buttons.potion.has_focus(), "up returns to previous purchase row")
	tap(KEY_TAB)
	check(not panel.buying and not panel.upgrading, "Tab switches to equipment page")
	tap(KEY_TAB)
	check(panel.upgrading and not panel.buying, "Tab switches to upgrade page")
	tap(KEY_TAB)
	check(panel.buying and not panel.upgrading, "Tab returns to purchase page")
	panel.item_buttons.potion.grab_focus()
	tap(KEY_ENTER)
	check(game.potions==0 and game.crystals==0 and panel.status_label.text=="結晶不足", "insufficient purchase rejected with reason")
	game.add_crystals(2000)
	panel.refresh()
	check(panel.balance_label.text.contains("結晶 2000"), "balance display refreshes")
	await next_decision()
	key(KEY_ENTER)
	key(KEY_ENTER,true,true)
	key(KEY_SPACE)
	await click(panel.item_buttons.potion)
	check(game.potions==1 and game.crystals==1970, "held, repeated and simultaneous mouse/key confirmation buys once")
	await next_decision()
	key(KEY_ENTER,true,true)
	check(game.potions==1, "held-key echo remains blocked after purchase interval")
	key(KEY_ENTER,false)
	key(KEY_SPACE,false)
	tap(KEY_ENTER)
	tap(KEY_ENTER)
	check(game.potions==2 and game.crystals==1940, "rapid separate confirmations cannot purchase twice")
	await next_decision()
	await click(panel.item_buttons.potion)
	check(game.potions==3 and game.crystals==1910, "actual mouse click buys one potion")
	await next_decision()
	check(not game.buy_item("potion") and game.potions==3 and game.purchase_reason("potion")=="所持数の上限", "potion cap enforced")
	await click(panel.item_buttons.rapid)
	check(game.owned_equipment.has("rapid") and game.crystals==1820, "equipment purchase consumes catalog price")
	check(panel.item_buttons.rapid.text.contains("所持") and not game.buy_item("rapid"), "owned equipment cannot be bought again")
	check(game.player.equipment.weapon.is_empty(), "purchase does not automatically equip")
	await next_decision()
	check(game.buy_item("key") and game.keys>=1, "key purchase succeeds")
	var keys: int = game.keys
	await next_decision()
	check(not game.buy_item("key") and game.keys==keys and game.purchase_reason("key")=="売り切れ", "key sold out per merchant")
	check(not game.buy_item("triple"), "cannot purchase equipment outside merchant stock")
	check(game.crystals_earned>=2000, "purchases preserve total earned crystal statistic")
	panel.refresh()
	tap(KEY_TAB)
	await frames(3)
	check(not panel.buying and not panel.upgrading and panel.equipment_buttons.has("weapon:rapid"), "keyboard switches to equipment page")
	panel.equipment_buttons["weapon:rapid"].grab_focus()
	tap(KEY_ENTER)
	check(game.player.equipment.weapon=="rapid", "keyboard equips owned weapon")
	await next_decision()
	await click(panel.equipment_buttons["weapon:"])
	check(game.player.equipment.weapon.is_empty(), "mouse removes equipment")
	tap(KEY_ESCAPE)
	check(game.state=="playing", "Esc closes shop")
	game.show_menu("paused")
	check(game.ui.equipment_button.visible, "pause menu offers equipment")
	await click(game.ui.equipment_button)
	check(game.state=="equipment" and not panel.can_buy and not panel.buy_tab.visible and not panel.upgrade_tab.visible, "pause opens equipment without merchant purchasing or upgrading")
	await next_decision()
	await click(panel.equipment_buttons["weapon:rapid"])
	check(game.player.equipment.weapon=="rapid", "pause equipment selection takes effect")
	tap(KEY_ESCAPE)
	check(game.state=="paused" and game.world.process_mode==Node.PROCESS_MODE_DISABLED, "closing pause equipment returns to pause")
	game.resume_run()
	freeze()
	game.key_bindings.try_bind("interact",0,KEY_R)
	game.ui.update_hud()
	check(game.ui.loot_notice.text.contains("R で話す"), "merchant hint follows rebinding")
	tap(KEY_R)
	check(game.state=="shop", "rebound interaction opens merchant")
	tap(KEY_R)
	check(game.state=="playing", "rebound interaction closes merchant")
	game.key_bindings.try_bind("interact",0,KEY_ENTER)
	tap(KEY_ENTER)
	check(game.state=="shop", "interaction bound to Enter opens shop")
	tap(KEY_ENTER)
	check(game.state=="playing", "custom interaction has priority over UI accept when closing")
	game.key_bindings.reset_defaults()

func potion_checks() -> void:
	game.potions = 2
	game.player.hp = 20
	tap(KEY_Q)
	check(game.player.hp==60 and game.potions==1, "default Q consumes one potion and heals forty")
	check(not game.effects.player_hp_numbers.is_empty() and game.effects.player_hp_numbers.back().text=="+40", "potion uses existing recovery display")
	game.player.hp = 90
	tap(KEY_Q)
	check(game.player.hp==100 and game.potions==0, "potion healing clamps to maximum HP")
	game.potions = 1
	tap(KEY_Q)
	check(game.potions==1, "full HP does not consume potion")
	game.potions = 0
	game.player.hp = 20
	tap(KEY_Q)
	check(game.player.hp==20, "no potion does nothing")
	check(game.key_bindings.get_key("use_item",0)==KEY_Q and not game.key_bindings.try_bind("shoot",0,KEY_Q).is_empty(), "Q default exists and duplicate is refused")
	check(game.key_bindings.try_bind("use_item",0,KEY_H).is_empty(), "potion action can be rebound")
	game.potions = 2
	tap(KEY_Q)
	check(game.player.hp==20, "old potion key no longer activates")
	tap(KEY_H)
	check(game.player.hp==60 and game.potions==1, "new potion key activates")
	var path := "user://merchant_controls_%d.cfg" % OS.get_process_id()
	check(game.key_bindings.save_settings(path)==OK, "new action saves")
	game.key_bindings.reset_defaults()
	game.key_bindings.load_settings(path)
	check(game.key_bindings.get_key("use_item",0)==KEY_H, "new action reloads")
	var config := ConfigFile.new()
	config.set_value("controls","version",3)
	config.set_value("bindings","shoot",[KEY_F,KEY_NONE])
	config.save(path)
	game.key_bindings.load_settings(path)
	check(game.key_bindings.get_key("use_item",0)==KEY_Q and game.key_bindings.get_key("shoot",0)==KEY_F, "missing item row defaults without losing custom controls")
	DirAccess.remove_absolute(path)
	game.key_bindings.reset_defaults()
	game.ui.update_hud()
	check(game.ui.loot_label.text.contains("回復薬 1/3"), "HUD displays potion count")
	game.open_shop(at_merchant())
	tap(KEY_Q)
	check(game.potions==1 and game.player.hp==60, "shop does not consume items through gameplay key")
	game.close_shop()

func chest_checks() -> void:
	for slot: String in T.EQUIPMENT_SLOTS: game.equip(slot,"")
	game.owned_equipment.clear()
	game.potions = 0
	var point: Vector2 = game.player.position
	var payloads: Array = [{"kind":"potion"}]
	for i in range(10): payloads.append({"kind":"equipment","roll":i*37})
	for index in range(payloads.size()):
		var spawn := {"id":"merchant_test_chest_%d" % index,"kind":"chest","position":point,"sector":Vector2i.ZERO,"contents":[payloads[index]]}
		game.stream._spawn_loot(spawn)
		var chest = get_nodes_in_group("loot").filter(func(i): return i.spawn.id==spawn.id)[0]
		game.keys = 1
		var owned: int = game.owned_equipment.size()
		var crystals: int = game.crystals
		check(chest.try_open() and game.keys==0 and not chest.try_open(), "tagged chest opens once and consumes one key")
		if index==0: check(game.potions==1, "chest grants potion")
		elif index<=9: check(game.owned_equipment.size()==owned+1, "equipment chest always chooses an unowned item")
		else: check(game.owned_equipment.size()==9 and game.crystals==crystals+T.DETOUR_REWARD, "all equipment owned falls back to crystals")
	game.potions = T.POTION_CAPACITY
	var crystals: int = game.crystals
	game.grant_loot({"kind":"potion"})
	check(game.potions==T.POTION_CAPACITY and game.crystals==crystals+T.DETOUR_REWARD, "full potion inventory converts chest reward to crystals")

func persistence_checks() -> void:
	var npc := at_merchant()
	var id: String = npc.spawn.id
	var stable: Dictionary = game.stable_point(npc.position)
	var stock: Array = npc.spawn.stock.duplicate()
	game.merchant_sold[id] = true
	game.equip("armor","shell")
	game.equip("weapon","triple")
	game.equip("charm","homing")
	game.player.abilities = T.ABILITY_DASH | T.ABILITY_GLIDE
	game.player.hp = 89
	game.potions = 2
	var saved := {"owned":game.owned_equipment.duplicate(),"equipped":game.player.equipment.duplicate(),"sold":game.merchant_sold.duplicate(),"marks":game.discovered_merchants.duplicate(true),"crystals":game.crystals,"keys":game.keys}
	var delta: Vector2 = game.shift_origin(Vector2i(2,-2))
	check(npc.position==game.local_point(stable) and npc.spawn.position==npc.position, "origin shift moves merchant geometry")
	check(game.discovered_merchants==saved.marks and game.merchant_sold==saved.sold, "origin shift keeps stable discovery and sold-out records")
	check(game.ui.minimap.merchant_marks().any(func(m): return m.id==id and m.position==npc.position), "map merchant follows origin shift")
	game.shift_origin(Vector2i(-2,2))
	check(delta!=Vector2.ZERO and game.owned_equipment==saved.owned and game.player.equipment==saved.equipped and game.potions==2 and game.player.hp==89, "origin round trip preserves inventory, equipment and HP")
	# Real unload/reload, using streaming preparation with a finite deadline.
	check(await Support.ready(self,game,Vector2(6,0)*T.SECTOR_SIZE+T.SECTOR_START), "prepare distant sector")
	freeze()
	game.stream._unload(Vector2i.ZERO) if game.stream.loaded.has(Vector2i.ZERO) else null
	check(merchant(id)==null and game.merchant_sold.has(id), "unload removes NPC but preserves sold-out record")
	check(await Support.ready(self,game,game.local_point(stable)), "reload merchant sector")
	freeze()
	npc = merchant(id)
	check(npc!=null and npc.position==game.local_point(stable) and npc.spawn.stock==stock, "reload restores merchant identity, placement and stock")
	check(game.owned_equipment==saved.owned and game.player.equipment==saved.equipped and game.crystals==saved.crystals and game.keys==saved.keys and game.potions==2 and game.player.abilities==(T.ABILITY_DASH | T.ABILITY_GLIDE), "streaming preserves entire run inventory")
	game.player.position = npc.position+Vector2(-40,0)
	game.open_shop(npc)
	check(game.purchase_reason("key")=="売り切れ", "reloaded merchant retains sold-out key")
	game.close_shop()
	game.player.invulnerability = 0
	game.player.receive_hit(1-game.player.polarity,9999)
	await frames(3)
	check(game.state=="lost", "actual lethal hit reaches retry menu")
	game.primary_action()
	freeze()
	check(game.crystals==0 and game.crystals_earned==0 and game.keys==0 and game.player.abilities==0, "retry resets crystals, keys and all abilities")
	check(game.owned_equipment.is_empty() and game.player.equipment.values().all(func(v): return v.is_empty()) and game.potions==0, "retry resets owned and equipped items and potions")
	check(game.merchant_sold.is_empty() and game.active_merchant.is_empty() and game.loot_taken.is_empty(), "retry clears merchant sold-out and chest states")
	check(game.player.max_hp==100 and game.player.hp==100 and game.origin_sector==Vector2i.ZERO and merchant(id)!=null, "retry restores base health, origin and merchant")

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://builds/qa/merchant")
	game = Main.new()
	game.controls_path = "res://builds/qa/merchant/test_controls.cfg"
	root.add_child(game)
	game.key_bindings.reset_defaults()
	game.start_run(37)
	await physical_round_trip()
	await shop_checks()
	potion_checks()
	chest_checks()
	await persistence_checks()
	game.free()
	FileAccess.open("res://builds/qa/merchant/merchant_results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"traversal":traversal},"\t"))
	print("MERCHANT: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
