extends "res://tests/test_tree.gd"
const Main := preload("res://scripts/main.gd")
const T := preload("res://scripts/tuning.gd")
const G := preload("res://scripts/stage_generator.gd")
const S := preload("res://scripts/sector_generator.gd")
const L := preload("res://scripts/loot_generator.gd")
const Support := preload("res://tests/stream_test_support.gd")
const Driver := preload("res://tests/ability_driver.gd")
var game: Node2D
var checks := 0
var failures: Array[String] = []
var travel := {}

func _initialize() -> void: call_deferred("run")
func frames(n: int = 1) -> void:
	for i in range(n):
		test_progress()
		await physics_frame
		await process_frame
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)
func items(kind: String = "") -> Array:
	return get_nodes_in_group("loot").filter(func(n): return n.get_parent() == game.world and not n.is_queued_for_deletion() and (kind.is_empty() or n.spawn.kind == kind))
func input(action: String, pressed: bool) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()
func freeze() -> void:
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	for e in get_nodes_in_group("enemies"): e.set_physics_process(false)
	for item in items(): item.set_physics_process(false)
func at_item(id: String) -> Node2D:
	for item in items():
		if item.spawn.id == id: return item
	return null

func crystal_chest() -> Node2D:
	for item in items("chest"):
		if item.spawn.contents[0].kind == "crystal": return item
	# Terrain changes can change whether an optional normal chest fits in the
	# initial neighbourhood. Select real generated loot with a bounded search.
	for y in range(-2, 3):
		for x in range(-2, 3):
			test_progress()
			var at := Vector2i(x,y)
			var data := S.generate(game.current_seed, at)
			for item: Dictionary in data.loot:
				if item.kind != "chest" or item.contents[0].kind != "crystal": continue
				var point: Vector2 = game.stream.sector_offset(at) + item.position
				if not await Support.ready(self,game,point): return null
				freeze()
				return at_item("%d,%d:%s" % [at.x,at.y,item.id])
	return null

func route_to(driver: RefCounted, target: Vector2, abilities: int = 0) -> bool:
	for attempt in range(8):
		var graph := S.navigation_graph([S.generate(game.current_seed, Vector2i.ZERO)], false, abilities)
		var from := G.node_at(graph, driver.point())
		var to := G.node_at(graph, target)
		var commands := G.path_steps(graph, from, to, target)
		if commands.is_empty(): return false
		if await driver.follow(commands): return true
		print("ABILITY ROUTE REPLAN ", driver.error)
	return false

func play_route() -> void:
	game.start_run(37)
	var driver := Driver.new()
	driver.tree = self
	driver.game = game
	var local := S.generate(37, Vector2i.ZERO)
	var key: Dictionary = local.loot.filter(func(item): return item.kind == "key")[0]
	var chest: Dictionary = local.loot.filter(func(item): return item.kind == "chest" and item.contents[0].kind == "ability")[0]
	check(await driver.floor_wait(), "run begins on physical floor")
	check(await route_to(driver, key.position), "actual inputs reach first key: " + driver.error)
	check(game.keys == 1, "first key collected by touching during traversal")
	check(await route_to(driver, chest.position), "actual inputs reach four-direction dash chest: " + driver.error)
	input("interact", true)
	input("interact", false)
	await driver.tick(2)
	check(game.keys == 0 and game.player.abilities == T.ABILITY_DASH, "interaction key consumes first key and unlocks four-direction dash")
	check(not local.detours.is_empty(), "seed 37 has four-direction dash detour")
	if not local.detours.is_empty():
		var branch: Dictionary = local.detours[0]
		check(await route_to(driver, branch.position, T.ABILITY_DASH), "actual inputs reach ability-only detour: " + driver.error)
		check(game.crystals >= T.DETOUR_REWARD, "detour crystal collected by actual inputs")
		check(await route_to(driver, local.start_position, T.ABILITY_DASH), "actual inputs return from detour to start: " + driver.error)
	driver.release()
	travel = {"seed": 37, "frames": driver.frames, "jumps": driver.jumps, "maximum_step": driver.max_player_step, "error": driver.error}
	check(driver.max_player_step <= T.MAX_FALL_SPEED / 60 + 1, "traversal contains no position correction or teleport")

func run() -> void:
	game = Main.new()
	game.controls_path = "user://task9b_abilities_controls.cfg"
	root.add_child(game)
	game.key_bindings.reset_defaults()
	await play_route()
	game.start_run(37)
	freeze()
	var first_chest = items("chest").filter(func(i): return i.spawn.sector == Vector2i.ZERO and i.spawn.contents[0].kind == "ability")[0]
	game.player.position = first_chest.position
	game.camera.position = first_chest.position + Vector2(T.VIEW_SIZE.x/2+8,0)
	game._update_exploration()
	check(game.discovered_loot.has(first_chest.spawn.id), "partially visible loot is discovered before its center enters screen")
	game._update_camera(0,true)
	game._update_exploration()
	check(game.discovered_loot.has(first_chest.spawn.id) and game.discovered_loot[first_chest.spawn.id].ability, "visible ability chest discovered with distinct map type")
	check(not first_chest.try_open() and game.keys == 0 and not first_chest.opened and game.loot_message == "鍵が必要", "keyless chest stays closed with short notice")
	var key = items("key").filter(func(i): return i.spawn.sector == Vector2i.ZERO)[0]
	game.player.position = key.position
	var key_id: String = key.spawn.id
	game._update_camera(0,true)
	game._update_exploration()
	check(game.discovered_loot.has(key_id) and game.discovered_loot[key_id].kind=="key" and game.ui.minimap.loot_marks().any(func(mark): return mark.kind=="key" and mark.position.distance_to(key.position)<0.001),"visible generated key has its own key map mark")
	check(key.try_collect() and game.keys == 1 and not key.try_collect(), "key increments once")
	game.key_bindings.try_bind("dash", 0, KEY_U)
	game.player.position = first_chest.position
	check(first_chest.try_open() and game.keys == 0 and game.player.abilities == T.ABILITY_DASH, "chest consumes key and grants ability")
	check(game.loot_message.contains("U") and game.loot_message_remaining == T.LOOT_MESSAGE_TIME, "ability notice uses current binding for several seconds")
	game.key_bindings.try_bind("dash",0,KEY_R)
	game.ui.update_hud()
	check(game.ui.loot_notice.text.contains("R") and not game.ui.loot_notice.text.contains("U"), "active notice follows binding changes on resume")
	check(not first_chest.try_open() and game.keys == 0, "opened chest cannot consume twice")
	var chest_id: String = first_chest.spawn.id
	game._update_camera(0, true)
	game._update_exploration()
	check(not game.discovered_loot.has(key_id) and not game.discovered_loot.has(chest_id), "picked key and opened chest removed from map")
	game.stream._unload(Vector2i.ZERO)
	check(not game.stream.loaded.has(Vector2i.ZERO), "collected sector unloaded")
	check(await Support.ready(self, game, T.SECTOR_START), "collected sector reloaded")
	freeze()
	check(at_item(key_id) == null and at_item(chest_id) != null and at_item(chest_id).opened, "picked key absent and chest remains open after reload")
	var mark_before: Dictionary = game.loot_taken.duplicate()
	var chest_position: Vector2 = at_item(chest_id).position
	var delta: Vector2 = game.shift_origin(Vector2i(2, -2))
	check(game.loot_taken == mark_before and at_item(chest_id).opened and at_item(chest_id).position == chest_position + delta, "origin shift preserves open state and moves chest")
	game.shift_origin(Vector2i(-2, 2))
	game.key_bindings.reset_defaults()
	# Normal chest reward and extension-friendly tagged contents.
	var ordinary = await crystal_chest()
	check(is_instance_valid(ordinary), "a real generated crystal chest is available within the bounded search")
	if not is_instance_valid(ordinary): game.free(); quit(1); return
	game.keys = 1
	game.player.position = ordinary.position
	game._update_camera(0,true)
	game._update_exploration()
	check(game.discovered_loot.has(ordinary.spawn.id) and not game.discovered_loot[ordinary.spawn.id].ability and game.ui.minimap.loot_marks().any(func(mark): return mark.kind=="chest" and not mark.ability and mark.position.distance_to(ordinary.position)<0.001),"visible generated ordinary chest has a distinct non-ability chest map mark")
	var before: int = game.crystals
	check(ordinary.try_open() and game.crystals - before == ordinary.spawn.contents[0].amount, "normal chest awards its deterministic crystals")
	check(ordinary.spawn.contents[0].amount in range(T.CHEST_CRYSTAL_MIN, T.CHEST_CRYSTAL_MAX+1), "normal chest reward within tuning range")
	# Exercise each tagged ability payload through the actual chest interaction;
	# generation/arrival for their real sectors is checked separately.
	for ability: int in [T.ABILITY_DASH,T.ABILITY_GLIDE]:
		var payload := {"id":"test_ability_%d" % ability,"kind":"chest","position":game.player.position+Vector2(56,0),"sector":game.stream.sector_at(game.player.position),"contents":[{"kind":"ability","ability":ability}]}
		game.stream._spawn_loot(payload)
		var box := at_item(payload.id)
		game.keys = 1
		check(box.try_open() and game.keys==0 and game.player.has_ability(ability),"chest unlocks ability and spends one key: %d" % ability)
		game.ui.update_hud()
		check(game.ui.loot_notice.text==game.ability_help(ability),"dash/glide unlock notice uses current keys: %d" % ability)
	var enemy = get_nodes_in_group("enemies").filter(func(e): return e.get_parent() == game.world and e.kind != "boss")[0]
	before = game.crystals
	enemy.receive_hit(1-enemy.polarity, T.ENEMY_HP)
	check(game.crystals == before + T.CRYSTAL_REWARDS.normal, "normal enemy crystal reward")
	game.actor_defeated(enemy)
	check(game.crystals == before + T.CRYSTAL_REWARDS.normal, "duplicate defeat notification gives no extra crystals")
	var record: Dictionary = game.stream.missing[enemy.spawn_id].duplicate(true)
	game.stream.missing.erase(enemy.spawn_id)
	game.stream._restore(record)
	var restored = get_nodes_in_group("enemies").filter(func(e): return e.get_parent() == game.world and e != enemy and e.spawn_id == record.id)[0]
	before = game.crystals
	game.actor_defeated(enemy)
	check(game.crystals == before, "late duplicate from old body cannot reward after respawn clears stable ID")
	restored.receive_hit(1-restored.polarity, T.ENEMY_HP)
	check(game.crystals == before + T.CRYSTAL_REWARDS.normal, "respawned instance rewards again")
	before = game.crystals
	game.player.receive_hit(game.player.polarity, 12)
	check(game.crystals == before, "same-color absorption awards no crystals")
	for role: String in ["guardian", "final", "secret"]:
		var actor := preload("res://scripts/enemy.gd").new()
		actor.game = game
		actor.kind = "boss"
		actor.boss_role = role
		actor.boss_id = 100 + checks
		actor.spawn_id = "test_" + role
		actor.position = game.player.position
		actor.arena = Rect2(actor.position - Vector2(300,300), Vector2(600,600))
		actor.roam = Rect2(actor.position-Vector2(32,32), Vector2(64,64))
		game.world.add_child(actor)
		actor.set_physics_process(false)
		# Isolate reward handling from the independently tested boss-cycle state machine.
		game.boss_cycle.records[actor.boss_id] = {"alive": true, "role": role}
		before = game.crystals
		game.actor_defeated(actor)
		game.actor_defeated(actor)
		check(game.crystals == before + T.CRYSTAL_REWARDS[role], "boss crystal reward once: " + role)
		if role == "guardian":
			var drops := items("key").filter(func(i): return i.spawn.id == "guardian_key:%d" % actor.boss_id)
			check(drops.size() == 1 and game.loot_drops.size() == 1, "guardian drops exactly one key")
			var held: int = game.keys
			check(drops[0].try_collect() and not drops[0].try_collect() and game.keys == held+1, "guardian drop is collectible exactly once")
	game.ui.update_hud()
	check(game.ui.loot_label.text == "結晶 %d    鍵 %d    回復薬 %d/%d" % [game.crystals,game.keys,game.potions,T.POTION_CAPACITY], "HUD displays crystals, keys and potions")
	check(not game.effects.crystal_numbers.is_empty() and game.effects.crystal_numbers[-1].text.begins_with("+"), "crystals have a separate floating number")
	game.player.invulnerability = 0
	game.player.receive_hit(1-game.player.polarity,999)
	await frames(2)
	check(game.state == "lost", "actual death opens retry result")
	check(game.ui.menu_detail.text.contains("獲得した結晶 %d" % game.crystals_earned), "result screen displays total earned crystals")
	game.primary_action()
	freeze()
	check(game.crystals == 0 and game.crystals_earned == 0 and game.keys == 0 and game.player.abilities == 0 and game.loot_taken.is_empty() and game.loot_drops.is_empty(), "retry resets currency keys abilities opened/picked records and drops")
	check(at_item(key_id) != null and at_item(chest_id) != null and not at_item(chest_id).opened, "retry restores original key and closed chest")
	# Version 3 migration preserves unrelated custom rows and fills dash default.
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "version", 3)
	cfg.set_value("bindings", "shoot", [KEY_U, KEY_NONE])
	var path := "user://abilities_legacy_controls_%d.cfg" % OS.get_process_id()
	check(cfg.save(path) == OK, "legacy controls fixture saved")
	game.key_bindings.load_settings(path)
	check(game.key_bindings.get_key("dash",0) == KEY_SHIFT and game.key_bindings.get_key("shoot",0) == KEY_U, "old v3 save defaults missing dash and retains custom binding")
	check(not game.key_bindings.try_bind("shoot",0,KEY_SHIFT).is_empty(), "dash key duplicate rejected")
	game.key_bindings.try_bind("dash",0,KEY_CTRL)
	check(game.key_bindings.save_settings(path) == OK, "dash binding saves")
	game.key_bindings.reset_defaults()
	game.key_bindings.load_settings(path)
	check(game.key_bindings.get_key("dash",0) == KEY_CTRL, "dash binding reloads")
	DirAccess.remove_absolute(path)
	game.key_bindings.reset_defaults()
	game.free()
	DirAccess.make_dir_recursive_absolute("res://builds/qa/abilities")
	FileAccess.open("res://.userdata/codex-delegation/task-20261103-64-abilities.json", FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"travel":travel},"\t"))
	print("ABILITIES: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
