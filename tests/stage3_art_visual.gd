extends RefCounted
## Normal-renderer branch of the authorized impact_effect_test only.
const Main := preload("res://scripts/main.gd")
const Art := preload("res://scripts/sprite_art.gd")
const T := preload("res://scripts/tuning.gd")
const S := preload("res://scripts/sector_generator.gd")
const Support := preload("res://tests/stream_test_support.gd")
const OUT := "res://builds/qa/art/stage3/"
var tree: SceneTree
var game: Node2D
var checks := 0
var captures := 0
var failures: Array[String] = []
var metrics: Dictionary = {}

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); printerr("FAIL: "+message)

func frames(count: int) -> void:
	for i in range(count):
		tree.test_progress()
		await tree.process_frame

func loaded() -> void:
	var deadline := Time.get_ticks_msec()+30000
	while not Art._pending.is_empty() and Time.get_ticks_msec()<deadline: await frames(1)
	check(Art._pending.is_empty(),"all asynchronous sheets loaded")

func refresh() -> void:
	for actor in tree.get_nodes_in_group("combatants"): actor.queue_redraw()
	for chunk in game.terrain.draw_chunks.values(): chunk.queue_redraw()
	for background in game.stream.backdrops.values():
		for chunk in background.chunks.values(): chunk.queue_redraw()
	game.ui.update_hud()

func capture(name: String) -> void:
	refresh(); await frames(5)
	await RenderingServer.frame_post_draw
	check(tree.root.get_texture().get_image().save_png(OUT+name+".png")==OK,"capture "+name)
	captures += 1

func measure(id: String) -> void:
	var result := {}
	var focus_before := tree.root.gui_get_focus_owner()
	for selected in ["shapes","sprites"]:
		Art.mode_override=selected; refresh(); await frames(25)
		var elapsed: Array[float]=[]
		var draws: Array[float]=[]
		for i in range(120):
			var began := Time.get_ticks_usec()
			await RenderingServer.frame_post_draw
			elapsed.append((Time.get_ticks_usec()-began)/1000.0)
			draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			tree.test_progress()
		elapsed.sort(); draws.sort()
		result[selected]={"samples":120,"mean_ms":elapsed.reduce(func(a,b): return a+b,0.0)/120,"p95_ms":elapsed[113],"max_ms":elapsed[-1],"draw_calls_median":draws[60]}
	Art.mode_override="sprites"; refresh(); await frames(5)
	check(tree.root.gui_get_focus_owner()==focus_before,"art set preserves focus: "+id)
	metrics[id]=result

func fixture() -> void:
	var origin: Vector2 = game.player.position
	for e in tree.get_nodes_in_group("enemies"): e.hide()
	for index in range(3):
		var enemy := preload("res://scripts/enemy.gd").new()
		enemy.game=game; enemy.kind=["turret","walker","flyer"][index]
		enemy.position=origin+Vector2(200+index*100,-60-index*24); enemy.polarity=index%2
		game.world.add_child(enemy); enemy.set_physics_process(false)
	for i in range(10):
		game.player.polarity=i%2
		var bullet: Node2D = game.spawn_bullet(game.player,Vector2.RIGHT,i>=6)
		bullet.position=origin+Vector2(100+i*35,-40-i%3*35)
	for i in range(3):
		var loot := preload("res://scripts/loot.gd").new()
		loot.game=game; loot.spawn={"id":"art-qa-"+str(i),"kind":["key","crystal","chest"][i],"contents":[]}
		loot.position=origin+Vector2(-120+i*60,-20); game.world.add_child(loot)
	var heart := preload("res://scripts/heart.gd").new()
	heart.game=game; heart.position=origin+Vector2(80,-30); game.world.add_child(heart)
	game.player.polarity=0; game.player.homing_charges=3; game.player.gauge=2
	game.camera.position=origin+Vector2(120,-140); game.camera.force_update_scroll()
	game._update_exploration()
	game.terrain.prepare_view(game.view_rect()); game.stream.prepare_backdrop_view(game.view_rect())

func run(host: SceneTree) -> void:
	tree=host
	check(DisplayServer.get_name()!="headless","normal renderer required")
	if not failures.is_empty(): tree.quit(1); return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED); Engine.max_fps=0
	game=Main.new(); game.controls_path=OUT+"qa-controls.cfg"; game.audio_settings_path=OUT+"qa-audio.cfg"; game.audio_synthesis_override=0
	tree.root.add_child(game); game.set_physics_process(false); game.world.process_mode=Node.PROCESS_MODE_DISABLED
	await loaded(); await frames(6)
	check(Art._warnings.is_empty(),"all IDs loaded without warnings")
	check(game.ui.menu_card.get_theme_stylebox("panel") is StyleBoxTexture,"shared textured menu frame")
	for state in ["normal","hover","pressed","focus"]:
		check(game.ui.primary_button.get_theme_stylebox(state) is StyleBoxTexture,"image button state "+state)
	var startup := {"budget_ms":1.5,"frame_max_ms":Art.load_frame_max_usec/1000.0,"operation_max_ms":Art.load_operation_max_usec/1000.0,"imported":Art.imported_loads,"raw":Art.raw_loads}
	await capture("ui-title"); await measure("title")
	Art.mode_override="shapes"; refresh(); await frames(4)
	check(game.ui.menu_card.get_theme_stylebox("panel") is StyleBoxFlat,"shapes restores original menu frame")
	Art.mode_override="sprites"; refresh(); await frames(4)
	game.open_key_settings(); await capture("ui-settings"); await capture("ui-keys"); game.close_key_settings()
	game.open_audio_settings(); await capture("ui-audio"); game.close_audio_settings()
	var last_seed := 1
	for region in range(3):
		var seed_value := 1
		while S.region_at(seed_value,Vector2i.ZERO)!=region: seed_value+=1
		last_seed=seed_value
		game.start_run(seed_value); game.set_physics_process(false); game.world.process_mode=Node.PROCESS_MODE_DISABLED
		fixture(); await frames(10)
		check(game.biome_at(game.player.position)==region,"actual game region "+str(region))
		await capture("game-biome-"+str(region)); await measure("biome-"+str(region))
	# Existing streaming/gates, one persistent world, no boundary regeneration.
	var adjacent := Vector2i.RIGHT
	for at in [Vector2i.RIGHT,Vector2i.LEFT,Vector2i.UP,Vector2i.DOWN]:
		if S.region_at(last_seed,at)!=S.region_at(last_seed,Vector2i.ZERO): adjacent=at; break
	var boundary := Vector2(adjacent)*T.SECTOR_SIZE
	# Select an existing border connection from generated data, preserving terrain.
	boundary=Vector2(T.SECTOR_SIZE.x if adjacent.x>0 else 0, T.SECTOR_SIZE.y/2) if adjacent.x!=0 else Vector2(T.SECTOR_SIZE.x/2,T.SECTOR_SIZE.y if adjacent.y>0 else 0)
	var gates: Array = S.boundary_gates(last_seed,Vector2i.ZERO,adjacent)
	if not gates.is_empty(): boundary=gates[0].rect.get_center()
	check(await Support.ready(tree,game,boundary),"streamed real boundary")
	game.world.process_mode=Node.PROCESS_MODE_DISABLED
	game.camera.position=boundary; game.camera.force_update_scroll()
	game.terrain.prepare_view(game.view_rect()); game.stream.prepare_backdrop_view(game.view_rect())
	await capture("game-boundary")
	game.show_menu("paused"); await capture("ui-pause")
	game.show_menu("won"); await capture("ui-result-win")
	game.show_menu("lost"); await capture("ui-result-lose")
	game.show_menu("paused")
	game.owned_equipment=T.EQUIPMENT.duplicate(true); game.crystals=999; game.keys=2; game.potions=2
	game.open_equipment(); await capture("ui-equipment"); game.close_shop()
	game.active_merchant={"id":"stage3-merchant","stock":["potion","key","rapid","triple","shell","absorb","boots"]}
	game.state="shop"; game.ui.menu.hide(); game.ui.shop_panel.open(true)
	await capture("ui-shop"); await measure("shop")
	game.ui.shop_panel.hide(); game.state="playing"; game.open_map(); await capture("ui-map"); await measure("map"); game.close_map()
	# Per-ID fallback: a broken key does not hide heart, panel or merchant.
	var key_path := Art.description("key","idle").path as String
	Art.path_overrides[key_path]=OUT+"missing-key.png"; Art.texture(key_path,key_path); await loaded()
	check(Art.texture(key_path,key_path)==null,"missing item ID falls back")
	check(Art.texture(Art.description("heart","idle").path,Art.description("heart","idle").path)!=null,"healthy item retained")
	Art.path_overrides.clear()
	var report := {"checks":checks,"captures":captures,"failures":failures,"startup":startup,"renderer":RenderingServer.get_video_adapter_name(),"scenes":metrics,"note":"Normal renderer, actual generated terrain, controlled actor/item placements, physics disabled, 120 frames after warmup. CPU/GPU scheduling included; no human playtest."}
	FileAccess.open(OUT+"frame-time.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	game.free(); print("STAGE3 ART QA: %d checks, %d captures, %d failures" % [checks,captures,failures.size()]); tree.quit(0 if failures.is_empty() else 1)
