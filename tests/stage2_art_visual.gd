extends RefCounted
## Invoked only by impact_effect_test --stage2-art-qa, normal renderer.
const Main := preload("res://scripts/main.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Art := preload("res://scripts/sprite_art.gd")
const S := preload("res://scripts/sector_generator.gd")
const OUT := "res://builds/qa/art/stage2/"
var tree: SceneTree
var game: Node2D
var failures: Array[String] = []
var checks := 0
var captures := 0
var fixtures: Array = []

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
	check(Art._pending.is_empty(),"all asynchronous requests completed")

func refresh() -> void:
	for e in tree.get_nodes_in_group("combatants"): e.queue_redraw()
	for chunk in game.terrain.draw_chunks.values(): chunk.queue_redraw()
	game.effects.queue_redraw()
	game.ui.update_hud()

func capture(name: String) -> void:
	refresh(); await frames(3)
	await RenderingServer.frame_post_draw
	check(tree.root.get_texture().get_image().save_png(OUT+name+".png")==OK,"capture "+name)
	captures += 1

func enemy(kind: String, at: Vector2, color: int, role: String="guardian") -> Node2D:
	var e := Enemy.new()
	e.game=game; e.kind=kind; e.boss_role=role; e.boss_id=900+fixtures.size()
	e.position=at; e.spawn_id="stage2-"+str(fixtures.size())
	game.world.add_child(e)
	e.polarity=color; e.facing=-1; e.set_physics_process(false)
	fixtures.append(e)
	return e

func run(host: SceneTree) -> void:
	tree=host
	check(DisplayServer.get_name()!="headless","normal renderer required")
	if not failures.is_empty(): tree.quit(1); return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps=0
	game=Main.new()
	game.controls_path=OUT+"visual-controls.cfg"
	game.audio_settings_path=OUT+"visual-audio.cfg"
	game.audio_synthesis_override=0
	tree.root.add_child(game)
	await loaded()
	check(Art._warnings.is_empty(),"startup sheets have no missing IDs")
	var startup={"frame_max_ms":Art.load_frame_max_usec/1000.0,"operation_max_ms":Art.load_operation_max_usec/1000.0,"budget_ms":1.5,"imported":Art.imported_loads,"raw":Art.raw_loads,"uploads":Art.upload_serial}
	check(Art.load_frame_max_usec<8000,"startup art service never blocks a frame for 8ms")
	# The same production decoder handles a PNG without an import sidecar.
	var raw_copy:=OUT+"fresh-source.png"
	FileAccess.open(raw_copy,FileAccess.WRITE).store_buffer(FileAccess.get_file_as_bytes("res://assets/art/player/blue.png"))
	var before_raw:=Art.raw_loads
	Art.texture("fresh-source",raw_copy)
	await loaded()
	check(Art.texture("fresh-source",raw_copy)!=null and Art.raw_loads==before_raw+1,"PNG bytes fallback without import cache")
	var seed_value:=1
	while S.region_at(seed_value,Vector2i.ZERO)!=0: seed_value+=1
	game.start_run(seed_value)
	game.set_physics_process(false)
	game.world.process_mode=Node.PROCESS_MODE_DISABLED
	game.state="playing"; game.ui.menu.hide()
	game.camera.position=game.player.position+Vector2(120,-140)
	game.camera.force_update_scroll()
	game._update_exploration()
	game.terrain.prepare_view(game.view_rect())
	game.stream.prepare_backdrop_view(game.view_rect())
	await frames(8)
	await capture("game-terrain")
	for e in tree.get_nodes_in_group("enemies"): e.hide()
	var origin: Vector2=game.player.position
	for kind in ["walker","flyer","laser","breaker","builder","shifter","enhancer"]:
		for e in fixtures: e.hide()
		var e:=enemy(kind,origin+Vector2(300,-40),0)
		e.action="windup_switch" if kind=="shifter" else ("idle" if kind=="enhancer" else "windup_shot")
		e.next_polarity=1; e.art_time=0.12
		if kind=="enhancer": enemy("walker",origin+Vector2(400,-40),1)
		await capture("game-enemy-"+kind)
		check(e.art_sprite_drawn,kind+" uses sprite")
	for e in fixtures: e.hide()
	for role in ["guardian","final","secret"]:
		for color in [0,1]:
			var boss:=enemy("boss",origin+Vector2(330,-100),color,role)
			boss.action="windup_switch"; boss.next_polarity=1-color; boss.art_time=0.18
			game.boss=boss
			await capture("game-boss-"+role+("-blue" if color==0 else "-orange"))
			check(boss.art_sprite_drawn,role+" uses distinct boss sheet")
			boss.hide()
	game.boss=null
	# Many actors + both colors and owners + ordinary/guided shots.
	for i in range(20): enemy(["laser","breaker","builder","shifter","walker","flyer","enhancer"][i%7],origin+Vector2(-240+(i%10)*95,-80-(i/10)*150),i%2)
	var bullets: Array=[]
	for i in range(64):
		var source: Node=game.player if i%4<2 else fixtures[-1]
		source.polarity=i%2
		var bullet: Node=game.spawn_bullet(source,Vector2.RIGHT.rotated((i%5-2)*0.2),i%8>=4)
		bullet.position=origin+Vector2(-250+(i%16)*53,-100-(i/16)*90)
		bullet.art_age=i*.017
		for t in range(6): bullet.trail.append(bullet.position-bullet.direction*(6-t)*7)
		bullets.append(bullet)
	var laser: Node=game.spawn_laser(fixtures[-2])
	laser.path=PackedVector2Array([origin+Vector2(-220,-190),origin+Vector2(80,-235),origin+Vector2(470,-190)])
	laser.phase="beam"
	var bomb: Node=game.spawn_bomb_warning(fixtures[-3])
	bomb.target=origin+Vector2(270,-10)
	await capture("game-projectiles")
	check(bullets.filter(func(b):return b.polarity==0).size()>=10 and bullets.filter(func(b):return b.polarity==1).size()>=10,"at least ten shots of each color")
	var samples:={}
	for i in range(100):
		game.effects.emit(origin+Vector2(-230+(i%20)*53,-30-(i/20)*75),preload("res://scripts/tuning.gd").COLORS[i%2],["absorb","hit","switch","defeat"][i%4])
	for selected in ["shapes","sprites"]:
		Art.mode_override=selected; refresh(); await frames(20)
		var wall: Array[float]=[]; var draws: Array[float]=[]
		for i in range(120):
			var began:=Time.get_ticks_usec()
			for actor in fixtures: actor.tick_visuals(1.0/60.0)
			for bullet in bullets: bullet.art_age+=1.0/60.0; bullet.queue_redraw()
			laser.elapsed+=1.0/60.0; laser.queue_redraw()
			for j in range(game.effects.bursts.size()): game.effects.bursts[j].age=fmod(i/60.0+j*.01,0.44)
			game.effects.queue_redraw()
			await RenderingServer.frame_post_draw
			wall.append((Time.get_ticks_usec()-began)/1000.0)
			draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			tree.test_progress()
		wall.sort(); draws.sort()
		samples[selected]={"samples":120,"wall_frame_mean_ms":wall.reduce(func(a,b):return a+b,0.0)/120,"wall_frame_p95_ms":wall[113],"wall_frame_max_ms":wall[-1],"draw_calls_median":draws[60]}
		await capture("game-busy-"+selected)
	Art.mode_override="sprites"
	# Missing/corrupt IDs resolve independently; a valid sibling keeps rendering.
	var broken:="res://assets/art/enemies/laser-blue.png"
	Art.path_overrides[broken]=OUT+"missing-file.png"
	Art.texture(broken,broken)
	await loaded()
	for i in range(3): check(Art.texture(broken,broken)==null,"missing ID returns null")
	check(Art._warnings.size()==1,"missing ID warns once")
	check(Art.texture("res://assets/art/enemies/breaker-blue.png","res://assets/art/enemies/breaker-blue.png")!=null,"healthy sibling retained")
	var missing_actor:=enemy("laser",origin+Vector2(-100,-65),0)
	var healthy_actor:=enemy("breaker",origin+Vector2(150,-65),0)
	await capture("game-fallback")
	check(not missing_actor.art_sprite_drawn and healthy_actor.art_sprite_drawn,"only missing ID draws shapes in the actual game")
	Art.path_overrides.clear()
	var corrupt:=OUT+"corrupt.png"
	FileAccess.open(corrupt,FileAccess.WRITE).store_string("invalid PNG")
	Art.texture("corrupt-qa",corrupt)
	await loaded()
	check(Art.texture("corrupt-qa",corrupt)==null and Art._warnings.size()==2,"corrupt PNG falls back independently with one warning")
	# Actual damage/delete -> noncolliding death visual, slow and distortion survive fire.
	var boss:=enemy("boss",origin+Vector2(320,-90),0,"secret")
	boss.receive_hit(1,99999)
	game.boss_impact.set_process(false)
	game.player.fire_normal()
	game.boss_impact.advance(0.12)
	await frames(1)
	check(not tree.get_nodes_in_group("sprite_remnants").is_empty(),"boss remnant exists after body removal")
	for ghost in tree.get_nodes_in_group("sprite_remnants"): ghost.age=0.32; ghost.queue_redraw()
	for i in range(12): game.effects.emit(origin+Vector2(300,-80),preload("res://scripts/tuning.gd").COLORS[i%2],"defeat")
	for burst in game.effects.bursts: burst.age=0.15
	await capture("game-defeat")
	check(game.boss_impact.active and game.boss_impact.ring_age>=0.12,"boss distortion continues after shooting")
	game.boss_impact.cancel()
	game.effects.bursts.clear()
	for i in range(120): game.effects.emit(origin,Color("57d8ff"),"absorb")
	check(game.effects.bursts.size()==100,"burst cap stays at 100")
	var report={"checks":checks,"captures":captures,"failures":failures,"renderer":RenderingServer.get_video_adapter_name(),"startup":startup,"sets":samples,"actors":20,"bullets":64,"bursts":100,"seed":seed_value,"note":"normal renderer; actual generated waterway, controlled placements and visual clocks, world physics disabled, 120 frames after warmup, no vsync/cap; CPU/GPU scheduling included"}
	FileAccess.open(OUT+"frame-time.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	game.free()
	print("STAGE2 ART QA: %d checks, %d captures, %d failures" % [checks,captures,failures.size()])
	tree.quit(0 if failures.is_empty() else 1)
