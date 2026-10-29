extends "res://tests/test_tree.gd"
const Bank := preload("res://scripts/sound_bank.gd")
const Main := preload("res://scripts/main.gd")
const Settings := preload("res://scripts/audio_settings.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Loot := preload("res://scripts/loot.gd")
const Terrain := preload("res://scripts/world_terrain.gd")
const T := preload("res://scripts/tuning.gd")
const OUT := "res://builds/qa/sound/"
var checks := 0
var failures: Array[String] = []
var groups: Dictionary = {}
var group := "synthesis"
var bank: RefCounted
var streams: Dictionary
var wave_metrics: Dictionary = {}
var game: Node2D
var event_ids: Dictionary = {}
var benchmark: Dictionary = {}

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	groups[group] = groups.get(group,0)+1
	if not ok:
		failures.append(message)
		printerr("FAIL: ",message)
func frames(count: int = 1) -> void:
	for i in range(count):
		test_progress()
		await physics_frame
		await process_frame
func raw_key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func tap(code: int) -> void:
	raw_key(code,true)
	raw_key(code,false)
func action(id: String) -> void:
	var event := InputEventAction.new()
	event.action = id
	event.pressed = true
	game.player._unhandled_input(event)

func synthesize() -> void:
	bank = Bank.new()
	bank.start()
	while not bank.snapshot().complete:
		test_progress()
		OS.delay_msec(2)
		await process_frame
	streams = bank.collect()
	benchmark.synthesis = bank.snapshot()
	bank.shutdown()
	check(streams.size()==Bank.SOUNDS.size()+5,"all sound IDs synthesized")
	var reference := Bank.new()
	reference.start()
	while not reference.snapshot().complete:
		test_progress()
		OS.delay_msec(2)
		await process_frame
	var twice: Dictionary = reference.collect()
	reference.shutdown()
	var bytes := 0
	for id: String in streams:
		test_progress()
		var stream: AudioStreamWAV = streams[id]
		var pcm := stream.data
		check(pcm == twice[id].data,id+": byte-identical fixed-seed synthesis")
		check(stream.format==AudioStreamWAV.FORMAT_16_BITS and not stream.stereo,id+": mono 16bit PCM")
		var music := Bank.MUSIC_IDS.has(id)
		check(stream.mix_rate >= (22050 if music else 32000),id+": sample rate")
		var seconds := stream.get_length()
		check(seconds >= 24 and seconds <= 48 if music else absf(seconds-float(Bank.SOUNDS[id][0]))<0.001,id+": duration")
		bytes += pcm.size()
		var n := pcm.size()/2
		var peak := 0.0
		var total := 0.0
		var sq := 0.0
		for i in range(n):
			var value := pcm.decode_s16(i*2)/32768.0
			peak = maxf(peak,absf(value))
			total += value
			sq += value*value
		var rms := sqrt(sq/n)
		wave_metrics[id] = {"peak_dbfs":linear_to_db(peak),"rms_dbfs":linear_to_db(rms),"dc":total/n,"bytes":pcm.size(),"seconds":seconds}
		check(peak <= db_to_linear(-3 if music else -1) and peak>0.01,id+": peak and non-silence")
		check(rms > 0.002 and absf(total/n)<0.0002,id+": RMS and DC")
		if music:
			check(stream.loop_begin==0 and stream.loop_end==n and stream.loop_mode==AudioStreamWAV.LOOP_FORWARD,id+": exact loop sample count")
			var jump := absf(pcm.decode_s16(0)-pcm.decode_s16((n-1)*2))/32768.0
			var window := int(stream.mix_rate*0.05)
			var before := 0.0
			var after := 0.0
			for i in range(window):
				before += pow(pcm.decode_s16((n-1-i)*2)/32768.0,2)
				after += pow(pcm.decode_s16(i*2)/32768.0,2)
			var difference := absf(linear_to_db(sqrt(before/window))-linear_to_db(sqrt(after/window)))
			wave_metrics[id].seam_jump = jump
			wave_metrics[id].seam_rms_db = difference
			check(jump<0.025,id+": loop boundary step <0.025")
			check(difference<6,id+": adjacent 50ms RMS difference <6dB")
		else:
			check(pcm.decode_s16(0)==0 and pcm.decode_s16(pcm.size()-2)==0,id+": zero endpoints")
	benchmark.pcm_bytes = bytes
	check(bytes<=32*1024*1024,"PCM <=32 MiB")
	var metrics: Dictionary = benchmark.synthesis.ids
	check(metrics.title.ready_ms<4000,"title ready before 4s")
	check(metrics.amb2_metal.ready_ms<2000,"all effects ready before 2s")
	check(metrics.boss.ready_ms<20000,"total synthesis before 20s")
	for id: String in Bank.MUSIC_IDS: check(metrics[id].ms<4000,id+": synthesis <4s")
	var cancel := Bank.new()
	cancel.start()
	cancel.shutdown()
	check(cancel.thread==null,"cancel joins dedicated synthesis thread")

func startup_test() -> void:
	group="startup"
	var began:=Time.get_ticks_usec()
	var initial:=Main.new()
	initial.controls_path=OUT+"startup-controls.cfg"
	initial.audio_settings_path=OUT+"startup-audio.cfg"
	initial.audio_synthesis_override=1
	root.add_child(initial)
	initial.set_physics_process(false)
	var effects_ready:=0.0
	var title_ready:=0.0
	while not initial.audio.bank.snapshot().complete or initial.audio.streams.size()<Bank.SOUNDS.size()+5:
		test_progress()
		OS.delay_msec(2)
		await process_frame
		if effects_ready==0 and initial.audio.streams.has("amb2_metal"): effects_ready=(Time.get_ticks_usec()-began)/1000.0
		if title_ready==0 and initial.audio.streams.has("title"): title_ready=(Time.get_ticks_usec()-began)/1000.0
	benchmark.startup={"effects_from_scene_ms":effects_ready,"title_from_scene_ms":title_ready,"engine_before_scene_ms":began/1000.0,"effects_from_engine_ms":began/1000.0+effects_ready,"title_from_engine_ms":began/1000.0+title_ready,"setup_ms":initial.audio.setup_ms,"synthesis":initial.audio.bank.snapshot()}
	check(effects_ready>0 and effects_ready<2000,"real main receives all effects within 2s of scene creation")
	check(title_ready>0 and title_ready<4000,"real main receives title within 4s of scene creation")
	check(initial.audio.setup_ms<10,"setup including thread start <10ms")
	initial.free()

func settings_test() -> void:
	group = "settings"
	var settings := Settings.new()
	var path := OUT+"audio-test.cfg"
	settings.load_settings(OUT+"missing.cfg")
	check(settings.values==Settings.DEFAULTS,"missing config defaults")
	settings.values={"master":0,"bgm":100,"se":30}
	check(settings.save_settings(path)==OK,"save test-only config")
	settings.load_settings(path)
	check(settings.values=={"master":0,"bgm":100,"se":30},"roundtrip")
	FileAccess.open(path,FileAccess.WRITE).store_string("[audio]\nversion=1\nmaster=150\nbgm=-12\nse=\"broken\"\n")
	settings.load_settings(path)
	check(settings.values=={"master":100,"bgm":0,"se":80},"clamp and per-field fallback")
	FileAccess.open(path,FileAccess.WRITE).store_string("[audio]\nversion=99\nmaster=20\n")
	settings.load_settings(path)
	check(settings.values==Settings.DEFAULTS,"unknown version resets everything")
	FileAccess.open(path,FileAccess.WRITE).store_string("invalid configuration [")
	settings.load_settings(path)
	check(settings.values==Settings.DEFAULTS,"corrupt file defaults")
	for value in [0,10,50,80,100]:
		for key in ["master","bgm","se"]: settings.values[key]=value
		settings.apply()
		for name in ["Master","BGM","SE"]:
			var bus := AudioServer.get_bus_index(name)
			check(AudioServer.is_bus_mute(bus)==(value==0),name+": mute at zero")
			check(absf(AudioServer.get_bus_volume_db(bus)-Settings.db_for(value))<0.001,name+": perceived volume curve")
	game.audio.settings.values = Settings.DEFAULTS.duplicate()
	game.audio.settings.apply()
	game.show_menu("title")
	var count: int = game.audio.request_cursor
	game.ui.show_menu("title")
	check(game.audio.request_cursor==count,"programmatic focus is silent")
	tap(KEY_TAB)
	await frames()
	check(game.audio.history().any(func(e):return e.id=="ui_move"),"menu navigation requests ui_move")
	event_ids.ui_move=true
	game.open_audio_settings()
	var saved_before:=FileAccess.get_file_as_bytes(game.audio_settings_path) if FileAccess.file_exists(game.audio_settings_path) else PackedByteArray()
	await frames()
	check(game.state=="audio_settings" and game.ui.audio_panel.is_visible_in_tree(),"audio panel opens")
	var panel: Control = game.ui.audio_panel
	tap(KEY_LEFT)
	check(game.audio.settings.values.master==70,"left decreases by 10")
	tap(KEY_DOWN)
	tap(KEY_RIGHT)
	check(game.audio.settings.values.bgm==70,"down selects BGM; right increases")
	var old_polarity: int = game.player.polarity
	tap(KEY_K)
	tap(KEY_ENTER)
	check(game.state=="audio_settings" and game.player.polarity==old_polarity,"Enter/gameplay keys cannot leak")
	# Use the real GUI mouse path, not a direct value assignment.
	var slider: HSlider = panel.sliders[2]
	for pressed in [true,false]:
		var mouse := InputEventMouseButton.new()
		mouse.position=slider.get_global_rect().position+Vector2(slider.size.x*0.2,slider.size.y/2)
		mouse.button_index=MOUSE_BUTTON_LEFT
		mouse.pressed=pressed
		root.push_input(mouse,true)
		await frames()
	check(game.audio.settings.values.se<=30,"mouse slider click updates SE")
	var drag_start:=slider.get_global_rect().position+Vector2(slider.size.x*0.2,slider.size.y/2)
	var mouse_down:=InputEventMouseButton.new()
	mouse_down.position=drag_start
	mouse_down.button_index=MOUSE_BUTTON_LEFT
	mouse_down.pressed=true
	root.push_input(mouse_down,true)
	var motion:=InputEventMouseMotion.new()
	motion.position=slider.get_global_rect().position+Vector2(slider.size.x*0.8,slider.size.y/2)
	motion.relative=motion.position-drag_start
	motion.button_mask=MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion,true)
	var mouse_up:=InputEventMouseButton.new()
	mouse_up.position=motion.position
	mouse_up.button_index=MOUSE_BUTTON_LEFT
	mouse_up.pressed=false
	root.push_input(mouse_up,true)
	await frames()
	check(game.audio.settings.values.se>=70,"mouse drag updates SE")
	var saved_during:=FileAccess.get_file_as_bytes(game.audio_settings_path) if FileAccess.file_exists(game.audio_settings_path) else PackedByteArray()
	check(saved_before==saved_during,"volume changes do not write config while panel remains open")
	tap(KEY_ESCAPE)
	check(game.state=="title" and not panel.is_visible_in_tree(),"Esc closes panel without starting game")
	check(root.gui_get_focus_owner()==game.ui.audio_button,"focus returns to audio button")
	var saved := Settings.new()
	saved.load_settings(game.audio_settings_path)
	check(saved.values==game.audio.settings.values,"panel saves only the test settings path")
	game.start_tutorial()
	await frames()
	var practice: Node = game.tutorial_session
	practice.show_menu("paused")
	practice.open_audio_settings()
	check(practice.audio==game.audio and practice.ui.audio_panel.is_visible_in_tree(),"tutorial pause shares host director")
	practice.ui.audio_panel._reset()
	practice.ui.audio_panel._close()
	check(practice.state=="paused" and practice.get_viewport().gui_get_focus_owner()==practice.ui.audio_button,"tutorial closes to pause and restores focus")
	game.finish_tutorial()
	await frames()

func expect(id: String, callback: Callable, point: Variant = null) -> void:
	var cursor: int = game.audio.request_cursor
	var frame := Engine.get_physics_frames()
	callback.call()
	var history: Array = game.audio.history()
	var count: int = game.audio.request_cursor-cursor
	var matching: Array = history.slice(maxi(0,history.size()-count)).filter(func(e):return e.id==id)
	check(not matching.is_empty(),id+": actual event calls audio")
	if matching.is_empty(): return
	event_ids[id] = true
	check(matching.all(func(e):return e.frame==frame),id+": same physics frame")
	if point is Vector2: check(matching[0].position==point,id+": event position")

func make_enemy(kind: String, point: Vector2) -> Node:
	var actor := Enemy.new()
	actor.game=game
	actor.kind=kind
	actor.spawn_id="audio:%d" % game.world.get_child_count()
	actor.position=point
	if kind=="boss": actor.boss_id=9999
	game.world.add_child(actor)
	actor.set_physics_process(false)
	return actor

func event_test() -> void:
	group="events"
	game.start_run(37)
	game.set_physics_process(false)
	game.world.process_mode=Node.PROCESS_MODE_DISABLED
	var player: Node = game.player
	var point: Vector2 = player.position
	game.audio.streams=streams.duplicate()
	expect("shot",func(): player.fire_normal(),point)
	player.equipment.weapon="triple"
	var cursor: int=game.audio.request_cursor
	var bullets: int=game.projectiles.get_child_count()
	player.fire_normal()
	check(game.projectiles.get_child_count()-bullets==3 and game.audio.request_cursor-cursor==1,"triple shot is one sound request")
	expect("switch",func():action("switch_color"),point)
	expect("aim",func():action("aim_cycle"),point)
	expect("empty",func():player.launch_homing(),point)
	expect("charge",func():player.add_homing_charges(2),point)
	cursor=game.audio.request_cursor
	bullets=game.projectiles.get_child_count()
	expect("homing",func():player.launch_homing(),point)
	check(game.projectiles.get_child_count()-bullets==4 and game.audio.request_cursor-cursor==1,"homing volley is one sound request")
	expect("absorb",func():player.receive_hit(player.polarity,12),point)
	expect("hurt",func():player.receive_hit(1-player.polarity,12),point)
	expect("heal",func():player.heal(5),point)
	game.potions=1
	expect("potion",func():game.use_potion(),point)
	var enemy:=make_enemy("turret",point+Vector2(180,0))
	expect("enemy_hit",func():enemy.receive_hit(1-enemy.polarity,1),enemy.position)
	expect("enemy_absorb",func():enemy.receive_hit(enemy.polarity,1),enemy.position)
	expect("enemy_warn",func():enemy._begin("windup_shot",0.3),enemy.position)
	expect("enemy_warn_special",func():enemy._begin("windup_special",0.4),enemy.position)
	expect("enemy_shot",func():game.spawn_bullet(enemy,Vector2.LEFT),enemy.position)
	expect("enemy_homing",func():game.fire_special(enemy,4),enemy.position)
	enemy.next_polarity=1
	enemy.action="windup_switch"
	expect("enemy_switch",func():enemy._complete_action(),enemy.position)
	expect("enemy_defeat",func():enemy.receive_hit(1-enemy.polarity,999),enemy.position)
	var enhancer:=make_enemy("enhancer",point+Vector2(200,0))
	expect("enhancer_defeat",func():enhancer.receive_hit(1-enhancer.polarity,999),enhancer.position)
	check(game.audio.history().any(func(e):return e.id=="arrow_unlock"),"enhancer defeat unlock announcement sound")
	event_ids.arrow_unlock=true
	var boss:=make_enemy("boss",point+Vector2(240,0))
	boss.boss_role="secret"
	boss.action="windup_shot"
	bullets=game.projectiles.get_child_count()
	cursor=game.audio.request_cursor
	expect("boss_shot",func():boss._complete_action(),boss.position)
	check(game.projectiles.get_child_count()-bullets==8 and game.audio.request_cursor-cursor==1,"seven-way boss shot plus homing is one sound")
	expect("boss_hit",func():boss.receive_hit(1-boss.polarity,1),boss.position)
	# Avoid starting a boss placement job: valid defeat hook, complete phase stays inert.
	game.boss_cycle.phase="complete"
	expect("boss_defeat",func():boss.receive_hit(1-boss.polarity,9999),boss.position)
	expect("loop_up",func():game.update_loop_scaling())
	var laser:=make_enemy("laser",point+Vector2(210,0))
	var beam: Node
	cursor=game.audio.request_cursor
	beam=game.spawn_laser(laser)
	check(game.audio.history().back().id=="laser_charge" and game.audio.history().back().frame==Engine.get_physics_frames(),"laser warning start in same frame")
	event_ids.laser_charge=true
	expect("laser_fire",func():beam.fire(),laser.position)
	beam.cancel()
	var bomb: Node=game.spawn_bomb_warning(laser)
	check(game.audio.history().back().id=="bomb_warn","bomb warning sound")
	event_ids.bomb_warn=true
	bomb.position=point+Vector2(350,0)
	expect("bomb_explode",func():bomb.detonate(),bomb.position)
	expect("block_break",func():game._block_removed(Rect2(point-Vector2.ONE*16,Vector2.ONE*32),false),point)
	expect("crystal",func():game.add_crystals(30),point)
	var key:=Loot.new()
	key.game=game
	key.position=point
	key.spawn={"id":"audio-key","kind":"key"}
	game.world.add_child(key)
	expect("key",func():key.try_collect(),point)
	var chest:=Loot.new()
	chest.game=game
	chest.position=point
	chest.spawn={"id":"audio-chest","kind":"chest","contents":[{"kind":"potion"}]}
	game.world.add_child(chest)
	game.keys=0
	expect("chest_locked",func():chest.try_open(),point)
	game.keys=1
	expect("chest_open",func():chest.try_open(),point)
	check(game.audio.history().any(func(e):return e.id=="item_get"),"chest item acquisition")
	event_ids.item_get=true
	expect("ability_get",func():game.grant_loot({"kind":"ability","ability":T.ABILITY_DOUBLE}),point)
	var merchant: Node=game.nearest_merchant()
	if merchant==null:
		for candidate in get_nodes_in_group("merchants"):
			if candidate.get_parent()==game.world: merchant=candidate; break
	player.position=merchant.position
	expect("shop_open",func():game.open_shop(merchant))
	game.crystals=9999
	expect("buy",func():game.buy_item("rapid"))
	game.last_shop_action_ms=-1000
	expect("deny",func():game.buy_item("rapid"))
	expect("equip",func():game.equip("weapon","rapid"))
	expect("ui_back",func():game.close_shop())
	game.ending=false
	expect("map_open",func():game.open_map())
	expect("map_close",func():game.close_map())
	expect("pause",func():game.show_menu("paused"))
	expect("ui_confirm",func():game.open_key_settings())
	game.close_key_settings()
	game.resume_run()
	player.invulnerability=0
	expect("death",func():player.receive_hit(1-player.polarity,9999))
	await frames()
	check(game.state=="lost","actual death reaches lost screen")
	# Physics-triggered movement uses the existing movement driver fixture below.
	await movement_events()

func movement_events() -> void:
	game.start_run(37)
	game.set_physics_process(false)
	game.streaming_enabled=false
	game.world.process_mode=Node.PROCESS_MODE_INHERIT
	for child in game.world.get_children(): child.set_physics_process(false)
	var floor_body:=StaticBody2D.new()
	var shape:=CollisionShape2D.new()
	var rect:=RectangleShape2D.new()
	rect.size=Vector2(1000,100)
	shape.shape=rect
	floor_body.position=Vector2(1000,-1000)
	floor_body.add_child(shape)
	game.world.add_child(floor_body)
	var p: Node=game.player
	p.position=Vector2(1000,-1072)
	p.velocity=Vector2.ZERO
	await frames(2)
	p._physics_process(1.0/60)
	await frames()
	p.jump_buffer=0.1
	expect("jump",func():p._physics_process(1.0/60),p.position)
	p.abilities=T.ABILITY_DOUBLE|T.ABILITY_DASH|T.ABILITY_GLIDE
	p.jump_buffer=0.1
	expect("air_jump",func():p._physics_process(1.0/60),p.position)
	p.pending_dash=true
	expect("dash",func():p._physics_process(1.0/60),p.position)
	p.dash_remaining=0
	p.velocity=Vector2(0,80)
	Input.action_press("jump")
	expect("glide",func():p._physics_process(1.0/60))
	Input.action_release("jump")
	var cursor: int=game.audio.request_cursor
	for i in range(150):
		p._physics_process(1.0/60)
		await frames()
	check(game.audio.history().any(func(e):return e.id=="land"),"real falling collision requests land")
	if game.audio.request_cursor>cursor: event_ids.land=true
	var fixture:=Terrain.new()
	fixture.stage={"bounds":Rect2(0,-1400,4096,1500),"solids":[Rect2(0,-1024,4096,128)],"breakables":[],"protected_rects":[]}
	game.world.add_child(fixture)
	var plan:=Rect2(1504,-1120,32,96)
	var wall_id: int=fixture.next_wall_id
	expect("wall_place",func():fixture.place_wall(plan,987654),plan.get_center())
	expect("wall_vanish",func():fixture.remove_wall(wall_id),plan.get_center())
	fixture.free()
	game.boss_cycle.phase="final"
	var roles: Array[String]=["final"]
	game.boss_cycle.request(roles)
	check(await wait_until(func():return WorkerThreadPool.is_task_completed(game.boss_cycle.selection.task_id),30),"boss placement job finishes")
	expect("boss_appear",func():game.boss_cycle.service())

func overlap_test() -> void:
	group="overlap"
	game.audio.enabled=true
	game.audio.streams=streams.duplicate()
	game.state="playing"
	var audio: Node=game.audio
	audio.stop_world()
	audio.clock_ms+=1000
	var at: Vector2=game.view_rect().get_center()
	var handle: int=game.play_sound("shot",at,0,1,0)
	check(handle>=0,"synthesized sound plays")
	game.play_sound("shot",at,0,1,0)
	check(audio.history().back().reason=="same_frame","same frame merges same ID")
	await frames()
	game.play_sound("shot",at,0,1,0)
	check(audio.history().back().reason=="interval","minimum interval")
	audio.clock_ms+=1000
	game.play_sound("enemy_hit",at+Vector2(2000,0))
	check(audio.history().back().reason=="offscreen","half-screen beyond view is silent")
	var count :=0
	for id: String in Bank.SOUNDS:
		if id.begins_with("amb") or id.ends_with("_a") or id.ends_with("_b") or audio.PRIORITY.has(id) or id.begins_with("ui_"): continue
		audio.last_frame.clear()
		audio.last_id.clear()
		game.play_sound(id,at)
		count+=1
	for id in ["hurt","absorb","ui_confirm"]:
		audio.last_frame.erase(id)
		audio.last_id.erase(id)
		game.play_sound(id,null,0,1,0)
		check(audio.history().back().played,id+": priority survives enemy saturation")
	var active :=0
	for voice: Dictionary in audio.voices:
		if voice.until>audio.clock_ms: active+=1
	check(active<=32,"global polyphony <=32")
	# Fill every reserved/general slot with long priority voices, then verify
	# that a new ordinary sound is actually refused by the global capacity.
	for id: String in audio.PRIORITY+["ui_move","ui_confirm","ui_back"]:
		for repeat in range(2):
			audio.last_frame.erase(id)
			audio.last_id.erase(id)
			game.play_sound(id,null,0,0.25,0)
	active=0
	for voice: Dictionary in audio.voices:
		if voice.until>audio.clock_ms: active+=1
	check(active==32,"test really saturates all32 voices")
	audio.last_frame.erase("enemy_shot")
	audio.last_id.erase("enemy_shot")
	game.play_sound("enemy_shot",at)
	check(audio.history().back().reason=="voice_limit","global capacity rejects an extra ordinary sound")
	for voice: Dictionary in audio.voices: audio.stop_handle(voice.handle)
	audio.stop_world()
	audio.last_id.clear()
	for i in range(5):
		audio.clock_ms+=41
		audio.last_frame.erase("shot")
		game.play_sound("shot",at,0,0.25,0)
	check(audio.history().back().reason=="id_limit","shot polyphony <=4")
	audio.clock_ms+=1000
	audio.last_frame.clear()
	handle=game.play_sound("laser_charge",at)
	game.show_menu("paused")
	await frames(2)
	check(audio.voices[handle%32].player.stream_paused,"pause suspends world SE")
	game.resume_run()
	game.streaming_wait=true
	await frames(2)
	check(not audio.voices[handle%32].player.stream_paused,"streaming wait does not chop audio")
	game.streaming_wait=false
	var before: Vector2=audio.voices[handle%32].point
	audio.shift_origin(game,Vector2(-4096,0))
	check(audio.voices[handle%32].point==before+Vector2(-4096,0),"active source shifts with origin")
	audio.stop_handle(handle)
	check(audio.voices[handle%32].until==0,"cancel laser stops its voice")
	game.return_to_title()
	check(audio.voices.all(func(v):return not v.world or v.until==0),"return title clears world voices")
	game.play_sound("jump",at)
	check(audio.history().back().reason=="state","background title run stays silent")
	for i in range(600): game.play_sound("ui_move")
	check(audio.history().size()==512,"request ring bounded at512")

func music_test() -> void:
	group="music"
	var audio: Node=game.audio
	game.show_menu("title")
	audio._process(0.1)
	check(audio.requested_music=="title","title music")
	game.start_run(37)
	game.set_physics_process(false)
	game.world.process_mode=Node.PROCESS_MODE_DISABLED
	audio._process(0.1)
	check(audio.requested_music=="region%d"%game.biome_at(game.camera.position),"start selects starting region")
	audio._process(3.1)
	var original_slot: int=audio.music_slot
	var original_id: String=audio.current_music
	audio.music[original_slot].seek(4.0)
	OS.delay_msec(50)
	audio.set_music("region%d"%((game.biome_at(game.camera.position)+1)%3),3.0)
	audio.music_gain[original_slot]=0.8
	audio.music_gain[1-original_slot]=0.2
	audio.set_music(original_id,3.0)
	OS.delay_msec(50)
	check(audio.music_slot==original_slot and audio.music[original_slot].get_playback_position()>3.9,"reversing region fade preserves actual playback position")
	audio._process(3.1)
	var old_region: int=audio.region
	# Find a real adjacent-sector boundary with different region classification.
	var s: GDScript=preload("res://scripts/sector_generator.gd")
	var found :=false
	var boundary_seed:=0
	var left:=Vector2i.ZERO
	for value in range(100):
		if found: break
		for x in range(-8,9):
			if s.region_at(value,Vector2i(x,0))!=s.region_at(value,Vector2i(x+1,0)):
				boundary_seed=value
				left=Vector2i(x,0)
				found=true
				break
	check(found,"find deterministic adjacent biomes")
	game.current_seed=boundary_seed
	game.camera.position=(Vector2(left)+Vector2(0.5,0.5))*T.SECTOR_SIZE
	audio.region=game.biome_at(game.camera.position)
	old_region=audio.region
	audio.candidate_region=old_region
	var right_point: Vector2=(Vector2(left+Vector2i.RIGHT)+Vector2(0.5,0.5))*T.SECTOR_SIZE
	for i in range(8):
		game.camera.position=right_point if i%2==0 else right_point-T.SECTOR_SIZE*Vector2.RIGHT
		audio._process(0.3)
	check(audio.region==old_region,"boundary oscillation does not switch music")
	game.camera.position=right_point
	for i in range(18): audio._process(0.1)
	check(audio.region==game.biome_at(right_point) and audio.fade_seconds==3,"1.5s stable biome starts 3s crossfade")
	var boss:=make_enemy("boss",right_point)
	audio._process(0.1)
	check(not audio.boss_music,"boss must remain visible 0.3s")
	audio._process(0.21)
	check(audio.boss_music and audio.requested_music=="boss" and audio.fade_seconds==1,"boss entry music")
	boss.position+=Vector2(3000,0)
	audio._process(3.9)
	check(audio.boss_music,"boss exit hysteresis")
	audio._process(0.2)
	check(not audio.boss_music and audio.fade_seconds==2.5,"4s outside returns to biome")
	boss.position=right_point
	audio._process(0.31)
	boss.dead=true
	audio.boss_defeated()
	audio._process(0.01)
	check(not audio.boss_music and audio.requested_music.begins_with("region"),"boss defeat returns immediately")
	for state in ["paused","map","shop","equipment","settings","audio_settings"]:
		game.state=state
		audio._process(0.25)
		check(is_equal_approx(audio.duck_db,-10),state+": -10dB duck")
		game.state="playing"
		audio._process(0.25)
		check(is_zero_approx(audio.duck_db),state+": restore BGM")
	for state in ["lost","won"]:
		game.show_menu(state)
		audio._process(0.01)
		check(audio.music_target==[0.0,0.0] and audio.fade_seconds==0.5,state+": BGM fade")
		game.open_audio_settings()
		audio._process(0.1)
		check(audio.music_target==[0.0,0.0],state+": modal settings do not resurrect ended BGM")
		game.ui.audio_panel._close()
		audio._process(0.01)
		check(audio.ending_id==("lose" if state=="lost" else "win") and audio.ending_timer<1.5,state+": settings preserve jingle phase")
		audio._process(1.6)
		check(audio.history().back().id==("lose" if state=="lost" else "win"),state+": delayed jingle")
		event_ids["lose" if state=="lost" else "win"]=true
		audio._process(4)
		check(audio.requested_music=="title" and audio.ending_started,state+": quieter title after jingle")
	game.show_menu("lost")
	audio._process(0.01)
	game.open_audio_settings()
	audio._process(1.0)
	audio._process(3.0)
	check(audio.requested_music=="title" and audio.ending_started,"result sequence continues to title inside audio settings")
	game.ui.audio_panel._close()
	game.state="playing"
	for region_id in range(3):
		var selected:=false
		for x in range(-20,21):
			var p:=Vector2(x,0)*T.SECTOR_SIZE+T.SECTOR_SIZE/2
			if game.biome_at(p)==region_id: game.camera.position=p; selected=true; break
		check(selected,"find ambient region %d"%region_id)
		audio.ambient_in=0
		audio._process(0.1)
		check(audio.history().back().id.begins_with("amb%d_"%region_id),"ambient only in current biome")
		check(audio.ambient_in>=3 and audio.ambient_in<=9,"irregular ambient interval 3..9s")
	game.start_tutorial()
	await frames()
	audio._process(0.1)
	check(audio.requested_music=="title","tutorial uses title music")
	var p: Node=game.tutorial_session
	await frames(12)
	var jump_cursor: int=audio.request_cursor
	tap(KEY_SPACE)
	await frames(2)
	var jump_events: Array=audio.history().slice(-int(audio.request_cursor-jump_cursor))
	check(jump_events.any(func(e):return e.id=="jump" and e.position is Vector2),"tutorial physical jump routes to host")
	var cursor: int=audio.request_cursor
	p.player.fire_normal()
	p.player.receive_hit(p.player.polarity,12)
	p.complete_lesson()
	var recent: Array=audio.history().slice(-int(audio.request_cursor-cursor))
	check(recent.any(func(e):return e.id=="shot") and recent.any(func(e):return e.id=="absorb"),"tutorial shot and absorb route to host")
	check(recent.any(func(e):return e.id=="tutorial_step"),"tutorial task achievement")
	check(recent.any(func(e):return e.id=="shot" and e.pan<0),"tutorial uses its own view for left panning")
	event_ids.tutorial_step=true
	game.finish_tutorial()
	await frames()

func state_bytes() -> PackedByteArray:
	var p: Node=game.player
	var enemies: Array=[]
	for child in game.world.get_children():
		if child is Enemy and not child.is_queued_for_deletion(): enemies.append([child.spawn_id,child.position,child.velocity,child.hp,child.gauge,child.polarity,child.dead,child.action,child.action_remaining,child.shot_clock])
	enemies.sort_custom(func(a,b):return a[0]<b[0])
	var bullets: Array=[]
	for shot in game.projectiles.get_children():
		if not shot.is_queued_for_deletion(): bullets.append([shot.position,shot.get("direction"),shot.get("polarity"),shot.get("faction")])
	return var_to_bytes([p.position,p.velocity,p.hp,p.gauge,p.homing_charges,p.polarity,p.aim_index,p.abilities,p.equipment,enemies,bullets,game.score,game.crystals,game.keys,game.loot_taken,game.kills,game.elapsed])

func replay(with_audio: bool) -> Array[PackedByteArray]:
	seed(821731)
	game.start_run(37)
	game.set_physics_process(false)
	game.streaming_enabled=false
	game.world.process_mode=Node.PROCESS_MODE_INHERIT
	for child in game.world.get_children(): child.set_physics_process(false)
	game.audio.enabled=with_audio
	game.audio.streams=streams.duplicate() if with_audio else {}
	# Confine the script to already loaded sectors; no asynchronous completion enters state.
	var output: Array[PackedByteArray]=[]
	var p: Node=game.player
	for frame in range(1800):
		test_progress()
		p.invulnerability=10000 # Only scripted damage participates in this repeatable route.
		if frame%120==0:
			Input.action_release("move_left")
			Input.action_release("move_right")
			Input.action_press("move_right" if frame%240==0 else "move_left")
		if frame%60==0: p.jump_buffer=0.1
		if frame%90==0: action("switch_color")
		if frame%130==0: p.receive_hit(p.polarity,12)
		if frame%180==1:
			p.invulnerability=0
			p.receive_hit(1-p.polarity,1)
		if frame%100==0: p.heal(2)
		if frame==20:
			var enemy:=make_enemy("turret",p.position+Vector2(180,0))
			enemy.receive_hit(1-enemy.polarity,999)
		if frame==30:
			game.keys=1
			var chest:=Loot.new()
			chest.game=game
			chest.position=p.position
			chest.spawn={"id":"replay-chest","kind":"chest","contents":[{"kind":"crystal","amount":40}]}
			game.world.add_child(chest)
			chest.try_open()
		Input.action_press("shoot") if frame%40<20 else Input.action_release("shoot")
		# Drive real handlers at fixed physics delta; tree callbacks remain disabled.
		game._physics_process(1.0/60)
		p._physics_process(1.0/60)
		for enemy in game.world.get_children():
			if enemy is Enemy and not enemy.dead and not enemy.is_queued_for_deletion(): enemy._physics_process(1.0/60)
		for shot in game.projectiles.get_children():
			shot.set_physics_process(false)
			if not shot.is_queued_for_deletion(): shot._physics_process(1.0/60)
		output.append(state_bytes())
		await frames()
	Input.action_release("shoot")
	Input.action_release("move_left")
	Input.action_release("move_right")
	return output

func replay_test() -> void:
	group="invariance"
	game.audio.process_usec_total=0
	game.audio.process_usec_max=0
	game.audio.process_samples=0
	game.audio.play_usec_total=0
	game.audio.play_usec_max=0
	game.audio.play_samples=0
	game.audio.pending_play_usec=0
	game.audio.frame_work_usec_total=0
	game.audio.frame_work_usec_max=0
	var a: Array=await replay(false)
	var b: Array=await replay(false)
	for i in range(1800): check(a[i]==b[i],"disabled/disabled exact state frame %d"%i)
	var c: Array=await replay(true)
	for i in range(1800): check(a[i]==c[i],"disabled/synthesized exact state frame %d"%i)
	game.audio.enabled=true
	benchmark.director=game.audio.measurements()

func stress_test() -> void:
	group="stress"
	game.start_run(37)
	game.set_physics_process(false)
	game.world.process_mode=Node.PROCESS_MODE_DISABLED
	game.audio.streams=streams.duplicate()
	game.audio.enabled=true
	var audio: Node=game.audio
	var at: Vector2=game.camera.position
	var enemies: Array[Node]=[]
	for i in range(96): enemies.append(make_enemy("turret",at+Vector2((i%12-6)*55,(i/12-4)*40)))
	audio.process_usec_total=0
	audio.process_usec_max=0
	audio.process_samples=0
	audio.play_usec_total=0
	audio.play_usec_max=0
	audio.play_samples=0
	audio.pending_play_usec=0
	audio.frame_work_usec_total=0
	audio.frame_work_usec_max=0
	var max_voices:=0
	for frame in range(180):
		for i in range(enemies.size()):
			var enemy: Node=enemies[i]
			if frame%30==i%30: game.spawn_bullet(enemy,Vector2.LEFT)
			if frame%40==i%40: enemy.receive_hit(enemy.polarity,1)
			if frame%90==i%90: game.add_crystals(1)
		if frame%30==0: game.play_sound("hurt",at)
		if frame%20==0: game.play_sound("absorb",at,0,1,0)
		if frame%12==0: game.play_sound("ui_move")
		var active:=0
		for voice: Dictionary in audio.voices:
			if voice.until>audio.clock_ms: active+=1
		max_voices=maxi(max_voices,active)
		await frames()
	check(max_voices<=32,"96-enemy stress obeys global limit")
	check(audio.history().any(func(e):return e.id=="hurt" and e.played),"stress hurt audible")
	check(audio.history().any(func(e):return e.id=="absorb" and e.played),"stress absorption audible")
	check(audio.history().any(func(e):return e.id=="ui_move" and e.played),"stress UI audible")
	benchmark.stress=audio.measurements()
	benchmark.stress.enemies=96
	benchmark.stress.frames=180
	benchmark.stress.max_voices=max_voices

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var real_cfg:=FileAccess.get_file_as_bytes("user://audio.cfg") if FileAccess.file_exists("user://audio.cfg") else PackedByteArray()
	await startup_test()
	group="synthesis"
	await synthesize()
	game=Main.new()
	game.controls_path=OUT+"test-controls.cfg"
	game.audio_settings_path=OUT+"test-audio.cfg"
	game.audio_synthesis_override=0
	root.add_child(game)
	game.set_physics_process(false)
	game.audio.streams=streams.duplicate()
	await settings_test()
	await event_test()
	await overlap_test()
	await music_test()
	await replay_test()
	await stress_test()
	group="coverage"
	for id: String in Bank.SOUNDS:
		if id.begins_with("amb"): continue
		var logical:=id.trim_suffix("_a").trim_suffix("_b")
		check(event_ids.has(logical),logical+": event coverage")
	group="isolation"
	var after_cfg:=FileAccess.get_file_as_bytes("user://audio.cfg") if FileAccess.file_exists("user://audio.cfg") else PackedByteArray()
	check(real_cfg==after_cfg,"real user audio.cfg unchanged")
	check(game.audio.setup_ms<10,"main-thread audio setup <10ms")
	var buses:=AudioServer.bus_count
	game.free()
	game=Main.new()
	game.controls_path=OUT+"test-controls.cfg"
	game.audio_settings_path=OUT+"second-audio.cfg"
	game.audio_synthesis_override=0
	root.add_child(game)
	check(AudioServer.bus_count==buses,"repeated main does not duplicate buses")
	check(game.audio.bank.thread==null,"headless skips synthesis")
	game.free()
	game=null
	FileAccess.open(OUT+"audio-results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"groups":groups,"events":event_ids.keys(),"waveforms":wave_metrics,"benchmark":benchmark},"\t"))
	print("AUDIO RESULT: ",checks," checks, ",failures.size()," failures; groups=",groups)
	quit(0 if failures.is_empty() else 1)

func _finalize() -> void:
	if bank!=null: bank.shutdown()
	if is_instance_valid(game): game.free()
