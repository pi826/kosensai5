extends "res://scripts/main.gd"
## Independent scene reusing the main combat API; never generates or mutates a run.
const PracticePlayer := preload("res://scripts/tutorial_player.gd")
const Target := preload("res://scripts/tutorial_target.gd")
const Dynamite := preload("res://scripts/dynamite.gd")
const Heart := preload("res://scripts/heart.gd")
const GRAVITY_LESSON := 10
const DYNAMITE_LESSON := 11
const CONTACT_LESSON := 12
const LESSON_COUNT := 13
var host: Node2D
var lesson := 0
var ok_remaining := 0.0
var targets: Dictionary = {}
var defeated: Dictionary = {}
var absorptions := 0
var healing_events := 0
var drop_observed := false
var switches := 0
var lesson_switches := 0
var volleys := 0
var aim_hint_target := ""
var aim_hint_remaining := 0.0
var lesson_volleys := 0
var box_healed := false
var heart_healed := false
var turret_clock := 0.0
var heart: Node2D
var marker: Node2D
var gravity_flips := 0
var last_gravity_sign := 1
var dynamite_explosions := 0

class PracticeTerrain extends "res://scripts/world_terrain.gd":
	func _dynamite_cell_allowed(cell: Vector2i) -> bool:
		var center := pixel_of_cell(cell) + Vector2.ONE * TILE_SIZE * 0.5
		return T.TUTORIAL_DYNAMITE_WALL.has_point(center)

class Marker extends Node2D:
	var session: Node2D
	func _draw() -> void:
		var point: Vector2 = session.goal() - Vector2(0, T.TUTORIAL_MARKER_HEIGHT)
		draw_set_transform(point,PI/2)
		var drawn := preload("res://scripts/sprite_art.gd").draw_frame(self,"boss_arrow","idle",0,0,Vector2.ZERO,1)
		draw_set_transform(Vector2.ZERO)
		if not drawn:
			draw_circle(point, 20, Color("57d8ff30"))
			draw_polyline(PackedVector2Array([point + Vector2(-12, -5), point + Vector2(0, 8), point + Vector2(12, -5)]), Color("b9f4ff"), 4, true)
		draw_arc(session.goal(), T.TUTORIAL_GOAL_RADIUS, 0, TAU, 40, Color("8fe9ff"), 2, true)

func is_tutorial() -> bool:
	return true

func gravity_flip_enabled() -> bool:
	return lesson >= GRAVITY_LESSON and is_instance_valid(player) and player.position.x >= T.TUTORIAL_FLIP_MIN_X

func dynamite_enabled() -> bool:
	return lesson >= DYNAMITE_LESSON

func _ready() -> void:
	streaming_enabled = false
	stage = {"bounds": T.TUTORIAL_BOUNDS, "start_position": T.TUTORIAL_START, "solids": T.TUTORIAL_SOLIDS, "breakables": [], "protected_rects": []}
	camera = Camera2D.new()
	camera.limit_enabled = false
	add_child(camera)
	camera.make_current()
	world = Node2D.new()
	add_child(world)
	terrain = PracticeTerrain.new()
	terrain.stage = stage
	world.add_child(terrain)
	terrain.block_removed.connect(_block_removed)
	terrain.sound_requested.connect(play_sound)
	projectiles = Node2D.new()
	world.add_child(projectiles)
	effects = Effects.new()
	world.add_child(effects)
	player = PracticePlayer.new()
	player.game = self
	player.position = T.TUTORIAL_START
	world.add_child(player)
	effects.player = player
	marker = Marker.new()
	marker.session = self
	world.add_child(marker)
	ui = Interface.new()
	ui.game = self
	add_child(ui)
	state = "playing"
	ui.menu.hide()
	_update_camera(0, true)
	ui.update_hud()
	get_viewport().gui_release_focus()

func _unhandled_input(event: InputEvent) -> void:
	if state == "playing" and event.is_action_pressed("switch_color") and not event.is_echo(): switches += 1
	if lesson == CONTACT_LESSON and state == "playing" and event.is_action_pressed("interact") and ok_remaining <= 0:
		complete_lesson()
	if event.is_action_pressed("pause_game") and not event.is_echo():
		if state == "playing": show_menu("paused")
		elif state == "paused":
			play_sound("ui_back")
			resume_run()
		get_viewport().set_input_as_handled()

func _physics_process(delta: float) -> void:
	if state != "playing": return
	if player.gravity_sign != last_gravity_sign:
		if lesson == GRAVITY_LESSON: gravity_flips += 1
		last_gravity_sign = player.gravity_sign
	if lesson == DYNAMITE_LESSON and dynamite_stock <= 0 and not projectiles.get_children().any(func(item): return item.get_script() == Dynamite and not item.exploded and not item.is_queued_for_deletion()):
		dynamite_stock = 1
	aim_hint_remaining = maxf(0, aim_hint_remaining - delta)
	_update_camera(delta)
	if ok_remaining > 0:
		ok_remaining -= delta
		if ok_remaining <= 0: enter_lesson(lesson + 1)
	else:
		if lesson == 2 and player.drop_remaining > 0: drop_observed = true
		if lesson == 7 and player.homing_charges == 0 and not projectiles.get_children().any(func(b): return b.homing and b.faction == 0):
			player.add_homing_charges(1) # Retry a wasted practice volley without restarting.
		if lesson == 5:
			# Restore the teaching turret if it was shot before absorption practice.
			if not is_instance_valid(targets.get("turret")) or targets.turret.dead:
				add_target("turret", T.TUTORIAL_TURRET)
			turret_clock -= delta
			if turret_clock <= 0 and is_on_screen(T.TUTORIAL_TURRET):
				turret_clock = T.TUTORIAL_TURRET_INTERVAL
				spawn_bullet(targets.turret, (player.position - T.TUTORIAL_TURRET).normalized())
		if lesson_satisfied(): complete_lesson()
	_update_lock_marks()
	marker.queue_redraw()
	ui.update_hud()

func _update_camera(_delta: float, _snap: bool = false) -> void:
	if not is_instance_valid(player): return
	camera.position = Vector2(clampf(player.position.x + T.CAMERA_LOOK_AHEAD, T.VIEW_SIZE.x / 2, T.TUTORIAL_BOUNDS.end.x - T.VIEW_SIZE.x / 2), T.TUTORIAL_CAMERA_Y)

func biome_at(_point: Vector2) -> int:
	return 0

func goal() -> Vector2:
	if lesson == 4:
		var edge: Vector2 = T.TUTORIAL_GOALS[4]
		if not player.is_on_floor() or player.position.distance_to(edge) >= T.TUTORIAL_GOAL_RADIUS: return edge
		if not defeated.has("upper"): return T.TUTORIAL_AIM_TARGETS[0]
		if not defeated.has("lower"): return T.TUTORIAL_AIM_TARGETS[1]
		return edge
	return T.TUTORIAL_GOALS[mini(lesson, T.TUTORIAL_GOALS.size() - 1)]

func direction_hint() -> String:
	if lesson == 4 and ok_remaining > 0: return "上下の的を壊しました"
	var dx := goal().x - player.position.x
	return "%s 光る目印まで %dm" % ["→" if dx >= 0 else "←", roundi(absf(dx) / T.TILE_SIZE)]

func lesson_text() -> String:
	if ok_remaining > 0: return "OK！　次の練習へ進みます。"
	var k: Callable = key_bindings.get_binding_text
	if lesson == 4 and aim_hint_remaining > 0:
		var direction := "上" if aim_hint_target == "upper" else "下"
		return "5 / 13　射撃方向：前 → 上 → 下\n%sの的は %s 向きで撃とう（%s で切り替え）。\n足場の端から狙えます。%s でジャンプ、%s で射撃。" % [direction, direction, k.call("aim_cycle"), k.call("jump"), k.call("shoot")]
	var texts := [
		"1 / 13　左右に移動\n%s で左、%s で右。光る目印まで歩こう。\n次へ：床の上の目印に着く。" % [k.call("move_left"), k.call("move_right")],
		"2 / 13　ジャンプ\n%s でジャンプ。%s を2回押してもジャンプ。長く押すほど高く跳べます。\n次へ：足場の上の目印に着地する。" % [k.call("jump"), k.call("move_up")],
		"3 / 13　足場を降りる\n薄い足場の上で %s を押すと、真下へすり抜けます。\n次へ：足場をすり抜けて、下の目印へ着地する。" % k.call("move_down"),
		"4 / 13　射撃\n%s を押し続けて、右の白い的を壊そう。\n次へ：通常射撃で的を壊す。" % k.call("shoot"),
		"5 / 13　射撃方向：前 → 上 → 下\n%s で切り替え、%s で射撃。上の的は上向き、下の的は下向きで壊そう。\n%s で右の足場へジャンプし、端から狙って両方壊すと次へ。" % [k.call("aim_cycle"), k.call("shoot"), k.call("jump")],
		"6 / 13　色を切り替えて吸収\n%s で青／橙を切替。同色の弾は吸収メーターへ、異色の弾はダメージ。\n次へ：橙の砲台の前で色を切り替え、同色の弾を%d発吸収する。" % [k.call("switch_color"), T.ABSORPTIONS_PER_CHARGE],
		"7 / 13　敵の色を見て攻撃\n同色の攻撃は敵に吸収され、異色ならダメージ。%s で色、%s で方向。\n次へ：%s で橙の敵を倒す。撃破すると誘導弾ストック＋1。" % [k.call("switch_color"), k.call("aim_cycle"), k.call("shoot")],
		"8 / 13　誘導弾を一斉発射\n%s でストックを1回分使い、4発を複数の敵へ。練習では空になると1回補充。\n次へ：青に切り替え、誘導弾を発射して右の3体を倒す。" % k.call("special"),
		"9 / 13　箱で回復\nHPが減った状態で練習します。%s で右の箱を壊すとHP＋%d。\n次へ：箱を壊してHPを回復する。" % [k.call("shoot"), T.BLOCK_HEAL],
		"10 / 13　ハートで回復\n右のピンクのハートに触れるとHP＋%d。満タンのときは残ります。\n次へ：ハートに触れてHPを回復する。" % T.HEART_HEAL,
		"11 / 13　重力反転\n%s で重力を反転して天井に立つ。もう一度押すと床へ戻る（着地ごとに1回）。\n次へ：天井を歩いて右の壁を越え、床に戻って目印に着く。" % k.call("gravity_flip"),
		"12 / 13　ダイナマイト\n%s で投げると面に張り付き、リングが一周すると自機と反対の方向へ穴を掘る（自分も被弾）。\n本編は通常敵%d体ごとに1個（最大%d個）。次へ：右の壁を壊して奥の目印へ。" % [k.call("dynamite"), T.DYNAMITE_KILLS_PER_STICK, T.DYNAMITE_CAPACITY],
		"13 / 13　接触と無敵\n異色の敵の体に触れるとHPが減ります。被弾後%.1f秒は点滅し、無敵です。\n同色の弾は無敵中も吸収できます。%s で確認して練習を終える。" % [T.INVULNERABILITY, k.call("interact")]
	]
	return texts[mini(lesson, texts.size() - 1)]

func lesson_satisfied() -> bool:
	var at_goal := player.position.distance_to(goal()) < T.TUTORIAL_GOAL_RADIUS and player.is_on_floor()
	match lesson:
		0, 1: return at_goal
		2: return drop_observed and at_goal
		3: return defeated.has("shot")
		4: return defeated.has("upper") and defeated.has("lower")
		5: return switches > lesson_switches and absorptions >= T.ABSORPTIONS_PER_CHARGE
		6: return defeated.has("color")
		7: return volleys > lesson_volleys and defeated.has("volley0") and defeated.has("volley1") and defeated.has("volley2")
		8: return box_healed
		9: return heart_healed
		GRAVITY_LESSON: return at_goal and player.gravity_sign == 1 and gravity_flips > 0
		DYNAMITE_LESSON: return at_goal and dynamite_explosions > 0
	return false

func complete_lesson() -> void:
	if ok_remaining > 0: return
	play_sound("tutorial_step")
	ok_remaining = T.TUTORIAL_OK_TIME
	if lesson == 4: marker.hide()

func show_aim_hint(id: String) -> void:
	if lesson != 4 or ok_remaining > 0: return
	aim_hint_target = id
	aim_hint_remaining = 2.5

func enter_lesson(next: int) -> void:
	lesson = next
	last_gravity_sign = player.gravity_sign
	ok_remaining = 0
	aim_hint_remaining = 0
	marker.show()
	for bullet in projectiles.get_children(): bullet.queue_free()
	match lesson:
		3: add_target("shot", T.TUTORIAL_GOALS[3], true)
		4:
			add_target("upper", T.TUTORIAL_AIM_TARGETS[0], true)
			add_target("lower", T.TUTORIAL_AIM_TARGETS[1], true)
		5:
			lesson_switches = switches
			absorptions = 0
			add_target("turret", T.TUTORIAL_TURRET)
		6:
			if is_instance_valid(targets.get("turret")): targets.turret.queue_free()
			add_target("color", T.TUTORIAL_GOALS[6])
		7:
			lesson_volleys = volleys
			for i in range(T.TUTORIAL_VOLLEY_TARGETS.size()): add_target("volley%d" % i, T.TUTORIAL_VOLLEY_TARGETS[i])
		8:
			var previous_hp: int = player.hp
			player.hp = mini(player.hp, T.TUTORIAL_RECOVERY_HP)
			player._hp_changed(previous_hp)
			player.invulnerability = 0
			stage.breakables = [T.TUTORIAL_BOX]
			terrain.rebuild()
		9:
			heart = Heart.new()
			heart.game = self
			heart.position = T.TUTORIAL_HEART
			heart.spawn = {"id": 0, "position": T.TUTORIAL_HEART}
			world.add_child(heart)
		GRAVITY_LESSON:
			gravity_flips = 0
		DYNAMITE_LESSON:
			dynamite_stock = 1
			dynamite_explosions = 0
		LESSON_COUNT: show_menu("tutorial_complete")

func refresh_dynamite_map(cells: Array[Vector2i]) -> void:
	if lesson == DYNAMITE_LESSON: dynamite_explosions += 1
	super(cells)

func add_target(id: String, at: Vector2, neutral: bool = false) -> CharacterBody2D:
	var target := Target.new()
	target.game = self
	target.position = at
	target.target_id = id
	target.polarity = 1
	target.neutral = neutral
	if id == "upper": target.required_aim = 1
	elif id == "lower": target.required_aim = 2
	world.add_child(target)
	targets[id] = target
	return target

func spawn_bullet(actor: CharacterBody2D, direction: Vector2, guided: bool = false, target: Node2D = null, color: int = -1, origin: Vector2 = Vector2.INF) -> Node2D:
	var bullet := super.spawn_bullet(actor, direction, guided, target, color, origin)
	if actor == player and not guided: bullet.set_meta("tutorial_aim_index", player.aim_index)
	if actor.faction == 1: bullet.damage = T.TUTORIAL_DAMAGE
	return bullet

func fire_special(actor: CharacterBody2D, amount: int) -> void:
	if actor == player: volleys += 1
	super.fire_special(actor, amount)

func actor_defeated(actor: CharacterBody2D) -> void:
	if actor.faction == 0: return
	defeated[actor.target_id] = true
	if lesson == 4:
		if actor.target_id == aim_hint_target: aim_hint_remaining = 0
		if lesson_satisfied(): complete_lesson()
	if not actor.neutral: player.add_homing_charges(T.ENEMY_CHARGE_REWARD)
	effect(actor.position, T.COLORS[actor.polarity], "defeat")

func _block_removed(_bounds: Rect2, player_attack: bool) -> void:
	if player_attack: box_healed = player.heal(T.BLOCK_HEAL) > 0

func start_tutorial() -> void:
	pass

func primary_action() -> void:
	play_sound("ui_confirm")
	if state == "paused": resume_run()
	elif state == "tutorial_complete": host.call_deferred("finish_tutorial", true)

func new_action() -> void:
	play_sound("ui_confirm")
	host.call_deferred("finish_tutorial")
	host.call_deferred("start_tutorial")

func return_to_title() -> void:
	play_sound("ui_back")
	host.call_deferred("finish_tutorial")
