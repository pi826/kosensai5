extends "res://tests/test_tree.gd"
const Main := preload("res://scripts/main.gd")
const T := preload("res://scripts/tuning.gd")
const Keys := preload("res://scripts/key_bindings.gd")
const Support := preload("res://tests/stream_test_support.gd")
var game: Node2D
var checks := 0
var failures: Array[String] = []
var metrics := {}
var origin_marker_error_px := 0.0
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
func key(code: int, pressed: bool = true) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func tap(code: int) -> void:
	key(code)
	key(code, false)
func mouse_button(at: Vector2, code: int, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.button_index = code
	event.pressed = pressed
	root.push_input(event, true)
func motion(at: Vector2, relative: Vector2 = Vector2.ZERO) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.relative = relative
	root.push_input(event, true)
func click(button: Button) -> void:
	var at := button.get_global_rect().get_center()
	motion(at)
	mouse_button(at, MOUSE_BUTTON_LEFT, true)
	mouse_button(at, MOUSE_BUTTON_LEFT, false)
	await frames(2)
func decision() -> void:
	OS.delay_msec(ceili(T.SHOP_ACTION_INTERVAL * 1000) + 5)
	await frames()

func layout(panel: Control, label: String) -> void:
	var cards: Array = panel.rows.get_children()
	for i in range(cards.size()):
		var rect: Rect2 = cards[i].get_global_rect()
		check(Rect2(Vector2.ZERO, T.VIEW_SIZE).encloses(rect) and panel.rows.get_global_rect().encloses(rect), label + " card fits: " + str(i))
		for j in range(i): check(not rect.intersects(cards[j].get_global_rect()), label + " no overlap: %d/%d" % [i,j])
	# Find and execute arrow-key paths to every card, starting from the first.
	var first: Button = cards[0]
	var paths := {first: []}
	var pending: Array = [first]
	var directions := {KEY_UP: Vector2.UP, KEY_DOWN: Vector2.DOWN, KEY_LEFT: Vector2.LEFT, KEY_RIGHT: Vector2.RIGHT}
	while not pending.is_empty():
		var from: Button = pending.pop_front()
		for code: int in directions:
			var to: Button = panel.neighbor(from, directions[code])
			if paths.has(to): continue
			paths[to] = paths[from] + [code]
			pending.append(to)
	for card: Button in cards:
		check(paths.has(card), label + " reachable by arrows: " + card.text)
		if not paths.has(card): continue
		first.grab_focus()
		for code: int in paths[card]: tap(code)
		check(card.has_focus(), label + " actual arrow navigation reaches card")

func shop_and_hud() -> void:
	var npc = get_nodes_in_group("merchants").filter(func(m): return m.get_parent() == game.world and m.spawn.sector == Vector2i.ZERO)[0]
	game.player.position = npc.position + Vector2(-40, 0)
	game._update_camera(0, true)
	game._update_exploration()
	npc.spawn.stock = ["potion", "key", "rapid", "shell", "homing", "triple", "cushion"]
	game.crystals = 130
	game.owned_equipment.rapid = true
	game.merchant_sold[npc.spawn.id] = true
	game.open_shop(npc)
	await frames(2)
	var panel = game.ui.shop_panel
	check(panel.item_buttons.size() == 7, "maximum seven purchase cards")
	layout(panel, "buy")
	var full_stock: Array = game.active_merchant.stock.duplicate()
	for equipment_count in [3, 4]:
		game.active_merchant.stock = ["potion", "key"] + full_stock.slice(2, 2 + equipment_count)
		panel._rebuild()
		await frames(2)
		layout(panel, "buy %d equipment" % equipment_count)
	game.active_merchant.stock = full_stock
	panel._rebuild()
	await frames(2)
	for id: String in panel.item_buttons:
		check(panel.item_buttons[id].text.contains("結晶 %d" % game.item_price(id)), "price visible " + id)
	check(panel.item_buttons.potion.text.contains("購入可") and panel.item_buttons.triple.text.contains("結晶不足") and panel.item_buttons.rapid.text.contains("所持") and panel.item_buttons.key.text.contains("売り切れ"), "mixed purchase states visible")
	tap(KEY_TAB)
	check(panel.current_cards.armor.text.contains("まだ持っていません") and panel.current_cards.charm.text.contains("まだ持っていません"), "empty inventory slots explain no equipment owned")
	tap(KEY_TAB)
	await click(panel.item_buttons.potion)
	check(game.potions == 1 and game.crystals == 100, "mouse buys from bento card")
	panel.item_buttons.potion.grab_focus()
	tap(KEY_ENTER)
	await click(panel.item_buttons.potion)
	check(game.potions == 1 and game.crystals == 100, "rapid mouse and keyboard blocked by cooldown")
	await decision()
	key(KEY_ENTER)
	key(KEY_SPACE)
	check(game.potions == 2, "simultaneous accept sources buy once")
	key(KEY_ENTER, false)
	key(KEY_SPACE, false)
	game.potions = T.POTION_CAPACITY
	panel.refresh()
	check(panel.item_buttons.potion.text.contains("上限"), "potion cap visible")
	for id: String in T.EQUIPMENT: game.owned_equipment[id] = true
	tap(KEY_TAB)
	await frames(2)
	check(not panel.buying, "Tab selects equipment")
	layout(panel, "equipment empty/full inventory")
	check(panel.equipment_buttons.size() == 12 and panel.current_cards.size() == 3, "all nine owned items and three remove cards")
	for slot: String in T.EQUIPMENT_SLOTS:
		await decision()
		var id: String = T.STARTER_EQUIPMENT[T.EQUIPMENT_SLOTS.keys().find(slot)]
		await click(panel.equipment_buttons[slot + ":" + id])
		check(game.player.equipment[slot] == id, "mouse equips " + slot)
	await frames(2)
	layout(panel, "equipment all equipped")
	game.close_shop()
	game.ui.update_hud()
	for slot: String in T.EQUIPMENT_SLOTS:
		var entry: Label = game.ui.equipment_labels[slot]
		check(entry.visible and entry.text.contains(T.EQUIPMENT[game.player.equipment[slot]].name), "HUD names equipped " + slot)
		check(not entry.get_global_rect().intersects(game.ui.minimap.get_global_rect()) and not entry.get_global_rect().intersects(game.ui.announcement_label.get_global_rect()), "HUD avoids map and announcement " + slot)
	check(not game.ui.equipment_hint.visible and game.ui.equipment_button.text == "装備", "equipped slots clear reminder")
	game.equip("armor", "")
	check(game.ui.equipment_labels.armor.text.contains("付けられます") and game.ui.equipment_hint.visible, "empty owned slot prompts equipment")
	check(game.ui.equipment_button.text == "装備 ●", "pause button marks available equipment")
	check(game.key_bindings.try_bind("pause_game", 0, KEY_P).is_empty(), "pause key rebinds")
	game.ui.update_hud()
	check(game.ui.equipment_hint.text.contains("P → 装備"), "equipment hint follows keys")
	game.show_menu("paused")
	check(game.ui.equipment_button.visible and game.ui.equipment_button.text.contains("●"), "pause menu mark visible")
	game.open_equipment()
	check(not panel.can_buy and not panel.buy_tab.visible and not panel.buying, "pause is equipment only")
	game.close_shop()
	game.equip("armor", "shell")
	check(not game.ui.equipment_button.text.contains("●"), "equipping clears pause mark")
	game.key_bindings.reset_defaults()
	game.resume_run()

func title_and_bindings() -> void:
	game.show_menu("title")
	var text: String = game.ui.menu_detail.text + game.ui.menu_subtitle.text
	for removed in ["ガーディアンとラスボスを巡り", "3体撃破でラスボス", "ラスボス3回撃破で裏ボス", "倒れたら全リセット"]:
		check(not text.contains(removed), "old title text removed " + removed)
	for required in ["青か橙", "ダメージを受けません", "HP（体力）", "%d回吸収" % T.ABSORPTIONS_PER_CHARGE, "自動で追いかける", "ピンクのハート", "最初からやり直"]:
		check(text.contains(required), "title explains " + required)
	game.key_bindings.try_bind("switch_color", 0, KEY_V)
	game.key_bindings.try_bind("special", 0, KEY_B)
	game.ui.refresh_bindings()
	check(game.ui.menu_detail.text.contains("V でいつでも") and game.ui.menu_detail.text.contains("B で、敵"), "title follows rebound keys")
	var label: Label = game.ui.menu_detail
	check(label.position.y + label.get_line_count() * label.get_theme_font("font").get_height(label.get_theme_font_size("font_size")) < game.ui.seed_label.position.y, "title prose fits above seed")
	game.key_bindings.reset_defaults()
	var path := "user://task7a_controls.cfg"
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "version", 3)
	cfg.set_value("bindings", "shoot", [KEY_F, KEY_NONE])
	cfg.save(path)
	game.key_bindings.load_settings(path)
	check(game.key_bindings.get_key("world_map", 0) == KEY_M and game.key_bindings.get_key("shoot", 0) == KEY_F, "old controls default M preserving custom keys")
	cfg.set_value("bindings", "shoot", [KEY_M, KEY_NONE])
	cfg.save(path)
	game.key_bindings.load_settings(path)
	check(game.key_bindings.get_key("world_map", 0) == KEY_R and game.key_bindings.get_key("shoot", 0) == KEY_M, "legacy collision preserves shoot M and fills map with spare R")
	check(not game.key_bindings.try_bind("shoot", 0, KEY_R).is_empty(), "duplicate migrated map key refused")
	check(game.key_bindings.try_bind("world_map", 0, KEY_N).is_empty(), "map can rebind")
	game.key_bindings.save_settings(path)
	var copy := Keys.new()
	copy.load_settings(path)
	check(copy.get_key("world_map", 0) == KEY_N, "map rebind saves and reloads")
	check(game.ui.settings_panel._buttons.has("world_map"), "settings include map action")
	DirAccess.remove_absolute(path)
	game.resume_run()
	tap(KEY_M)
	check(game.state == "playing", "old map key no longer opens")
	tap(KEY_N)
	check(game.state == "map", "new map key opens")
	tap(KEY_N)
	check(game.state == "playing", "new map key closes")
	game.key_bindings.reset_defaults()

func map_checks() -> void:
	game.set_physics_process(true)
	game.player.set_physics_process(true)
	game.player.invulnerability = 10000
	game.ending = true
	tap(KEY_M)
	check(game.state == "playing" and not game.ui.large_map.visible, "end-of-run transition does not open map")
	game.ending = false
	game.player.dead = true
	tap(KEY_M)
	check(game.state == "playing" and not game.ui.large_map.visible, "dead player does not open map before result menu")
	game.player.dead = false
	tap(KEY_M)
	var map = game.ui.large_map
	check(game.state == "map" and map.visible, "M opens large map")
	var elapsed: float = game.elapsed
	var position: Vector2 = game.player.position
	var enemy = get_nodes_in_group("enemies")[0]
	var clock: float = enemy.shot_clock
	var bullet = game.spawn_bullet(game.player, Vector2.RIGHT)
	var bullet_at: Vector2 = bullet.position
	await frames(12)
	check(game.world.process_mode == Node.PROCESS_MODE_DISABLED and game.elapsed == elapsed and game.player.position == position, "map freezes world and elapsed time")
	check(enemy.shot_clock == clock and bullet.position == bullet_at, "map freezes enemies and projectiles")
	check(map.world_area().get_center().is_equal_approx(position) and map.zoom == T.LARGE_MAP_SCALE, "map opens centered at default zoom")
	key(KEY_RIGHT)
	await frames(4)
	key(KEY_RIGHT, false)
	check(map.world_area().get_center().x > position.x, "arrow key pans map")
	tap(KEY_SPACE)
	check(map.world_area().get_center().is_equal_approx(position), "Space centers player")
	key(KEY_W)
	await frames(4)
	key(KEY_W, false)
	check(map.world_area().get_center().y < position.y, "WASD pans map")
	var before: float = map.zoom
	tap(KEY_PLUS)
	check(map.zoom > before, "plus zooms in")
	tap(KEY_MINUS)
	check(is_equal_approx(map.zoom, before), "minus zooms out")
	var at := Vector2(700, 400)
	var anchor_before: Vector2 = map.world_area().position + (at - map.map_area().position) / map.zoom
	mouse_button(at, MOUSE_BUTTON_WHEEL_UP, true)
	var anchor_after: Vector2 = map.world_area().position + (at - map.map_area().position) / map.zoom
	check(map.zoom > before and anchor_after.is_equal_approx(anchor_before), "wheel zooms around cursor")
	mouse_button(at, MOUSE_BUTTON_LEFT, true)
	var center: Vector2 = map.world_area().get_center()
	motion(at + Vector2(40, 20), Vector2(40, 20))
	mouse_button(at + Vector2(40, 20), MOUSE_BUTTON_LEFT, false)
	check(map.world_area().get_center().is_equal_approx(center - Vector2(40, 20) / map.zoom), "mouse drag pans")
	map.change_zoom(100000)
	check(map.zoom == T.LARGE_MAP_MAX_SCALE, "zoom upper limit")
	map.change_zoom(0.0000001)
	check(map.zoom == T.LARGE_MAP_MIN_SCALE, "zoom lower limit")
	map.zoom = T.LARGE_MAP_SCALE
	map.center_on_player()
	var cell: Vector2i = Vector2i((position / T.MAP_CELL_SIZE).floor()) + game.map_origin()
	check(map.displayed_cells().has(cell - game.map_origin()) and game.explored_geometry.has(cell), "visible cells have persistent geometry")
	var saved: Array = game.explored_geometry[cell].duplicate()
	var center_point: Dictionary = map.center_point.duplicate()
	for i in range(3):
		game.discovered_bosses[900+i] = game.stable_point(position + Vector2(400+i*200,0))
		game.boss_cycle.records[900+i] = {"role":["guardian","final","secret"][i]}
	game.defeated_bosses[901] = true
	var marks: Array = map.guardian_marks()
	check(marks.any(func(m): return m.id == 901 and m.defeated) and marks.any(func(m): return m.id == 902 and m.role == "secret"), "map marks discovered boss roles and defeat")
	check(not map.merchant_marks().is_empty() and map.loot_marks().all(func(m): return m.kind in ["key","chest"]), "map retains merchant and item marker meanings")
	var relative_before: Vector2 = position - map.world_area().get_center()
	game.shift_origin(Vector2i(2, -2))
	check(map.center_point == center_point and game.explored_geometry[cell] == saved, "origin shift preserves map records")
	check((game.player.position - map.world_area().get_center()).is_equal_approx(relative_before), "origin shift preserves screen position")
	var shifted_marks: Array = map.guardian_marks()
	var same_marks := shifted_marks.size() == marks.size()
	for i in range(mini(shifted_marks.size(), marks.size())):
		var before_mark: Dictionary = marks[i]
		var after_mark: Dictionary = shifted_marks[i]
		origin_marker_error_px = maxf(origin_marker_error_px, before_mark.position.distance_to(after_mark.position))
		same_marks = same_marks and before_mark.id == after_mark.id and before_mark.role == after_mark.role and before_mark.defeated == after_mark.defeated and before_mark.offscreen == after_mark.offscreen and before_mark.direction.distance_to(after_mark.direction) < 0.0001
	check(same_marks and origin_marker_error_px < 0.01, "origin shift preserves all boss screen markers within 0.01px: " + str(origin_marker_error_px))
	game.shift_origin(Vector2i(-2, 2))
	for i in range(3):
		game.discovered_bosses.erase(900+i)
		game.boss_cycle.records.erase(900+i)
	game.defeated_bosses.erase(901)
	tap(KEY_ESCAPE)
	check(game.state == "playing" and not map.visible, "Esc closes and resumes")
	tap(KEY_M)
	tap(KEY_M)
	check(game.state == "playing", "M closes and resumes")
	tap(KEY_M)
	await click(map.close_button)
	check(game.state == "playing" and not map.visible, "mouse close button resumes play")
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	bullet.queue_free()
	var sector := Vector2i.ZERO
	check(await Support.ready(self, game, Vector2(6, 0) * T.SECTOR_SIZE + T.SECTOR_START), "prepare distant map sector")
	if game.stream.loaded.has(sector): game.stream._unload(sector)
	check(not game.stream.loaded.has(sector) and game.explored_geometry.has(cell) and game.explored_images.has(sector), "unloaded terrain retains geometry and raster")
	game.open_map()
	map.center_point = game.stable_point(position)
	check(map.displayed_cells().has(cell) and map._geometry_for_cell(cell) == game.map_geometry(Rect2(Vector2(cell) * T.MAP_CELL_SIZE, Vector2.ONE * T.MAP_CELL_SIZE)), "unloaded cells remain at same map coordinates")
	game.close_map()
	check(await Support.ready(self, game, position), "reload explored map sector")
	game._update_exploration()
	check(game.explored_geometry[cell] == saved, "reload retains same unchanged contour")
	# Change actual occupied terrain in a seen cell, then observe again.
	var occupied: Dictionary = game.terrain.occupied
	var tile: Vector2i = Vector2i((position / T.TILE_SIZE).floor())
	var had: bool = occupied.has(tile)
	if had: occupied.erase(tile)
	else: occupied[tile] = true
	game.terrain.revision += 1
	game._update_exploration()
	check(game.explored_geometry[cell] != saved, "visible terrain changes refresh recorded contour")
	if had: occupied[tile] = true
	else: occupied.erase(tile)
	game.terrain.revision += 1
	game._update_exploration()

func map_performance() -> void:
	# 300 fully explored sectors, 230400 cells. Synthetic raster/records isolate drawing cost.
	game.open_map()
	var map = game.ui.large_map
	var base := Vector2i(20, 20)
	var count := 0
	var began := Time.get_ticks_usec()
	for y in range(15):
		for x in range(20):
			var sector := base + Vector2i(x, y)
			var cells := {}
			for cy in range(24):
				for cx in range(32): cells[sector * Vector2i(32,24) + Vector2i(cx,cy)] = true
			game.explored_by_sector[sector] = cells
			var image := Image.create_empty(128, 96, false, Image.FORMAT_RGBA8)
			image.fill(Color("293f43"))
			image.fill_rect(Rect2i(20, 30, 88, 36), Color("0c1922"))
			game.explored_images[sector] = image
			game.map_sector_revisions[sector] = 1
			count += cells.size()
	map.center_point = {"sector":base+Vector2i(10,7), "local":T.SECTOR_SIZE/2}
	map.zoom = T.LARGE_MAP_MIN_SCALE
	map.clear_cache()
	map.queue_redraw()
	await frames(3)
	var cold: float = map.last_draw_ms
	var samples: Array[float] = []
	for i in range(12):
		map.pan(Vector2(1, 0))
		await frames(2)
		samples.append(map.last_draw_ms)
	var mean: float = samples.reduce(func(a,b): return a+b, 0.0) / samples.size()
	metrics = {"sectors":300, "cells":count, "cold_draw_ms":cold, "warm_draw_mean_ms":mean, "warm_draw_max_ms":samples.max(), "raster_bytes":300*128*96*4, "fixture_and_measurement_ms":(Time.get_ticks_usec()-began)/1000.0, "renderer":RenderingServer.get_video_adapter_name(), "origin_marker_error_px":origin_marker_error_px}
	check(map._textures.size() >= 300, "performance draws all 300 explored sectors")
	check(cold < 1000 and mean < 100, "bounded map CPU submission time; see metrics")
	game.close_map()
	game.start_run(37)
	check(not game.explored_by_sector.has(base) and not game.explored_geometry.keys().any(func(c): return c.x >= 640) and not game.explored_images.has(base) and map._textures.is_empty(), "retry clears all map records and textures")
	var tutorial := preload("res://scripts/tutorial.gd").new()
	tutorial.key_bindings = game.key_bindings
	tutorial.controls_path = game.controls_path
	# The embedded tutorial disables the host's unhandled input in the same way.
	game.set_process_unhandled_input(false)
	root.add_child(tutorial)
	check(not tutorial.ui.equipment_labels.weapon.visible and not tutorial.ui.equipment_hint.visible, "tutorial hides equipment HUD")
	tap(KEY_M)
	check(tutorial.state != "map" and not tutorial.ui.large_map.visible, "tutorial does not open world map")
	tutorial.free()

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://builds/qa/ui_map")
	game = Main.new()
	game.controls_path = "res://builds/qa/ui_map/test_controls.cfg"
	root.add_child(game)
	preload("res://tests/polish_art_checks.gd").hud(check,game.ui)
	game.key_bindings.reset_defaults()
	game.start_run(37)
	game.set_physics_process(false)
	await shop_and_hud()
	title_and_bindings()
	await map_checks()
	await map_performance()
	game.free()
	FileAccess.open("res://builds/qa/ui_map/test_results.json", FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"metrics":metrics}, "\t"))
	print("UI MAP: %d checks, %d failures; metrics %s" % [checks,failures.size(),JSON.stringify(metrics)])
	quit(0 if failures.is_empty() else 1)
