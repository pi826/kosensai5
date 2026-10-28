extends CanvasLayer
const T := preload("res://scripts/tuning.gd")
const KeySettingsPanel := preload("res://scripts/key_settings_panel.gd")
const Minimap := preload("res://scripts/minimap.gd")
const ShopPanel := preload("res://scripts/shop_panel.gd")
const BossArrow := preload("res://scripts/boss_arrow.gd")
const LargeMap := preload("res://scripts/large_map.gd")
var game: Node2D
var menu: Control
var health_label: Label
var health_bar: ProgressBar
var color_label: Label
var score_label: Label
var progress_label: Label
var gauge_label: Label
var gauge_bar: ProgressBar
var progress_bar: ProgressBar
var boss_hp_label: Label
var boss_label: Label
var hint_label: Label
var menu_title: Label
var menu_subtitle: Label
var menu_detail: Label
var primary_button: Button
var new_button: Button
var seed_field: LineEdit
var seed_label: Label
var controls_label: Label
var settings_button: Button
var settings_overlay: Control
var settings_panel: PanelContainer
var minimap: Control
var location_label: Label
var objective_label: Label
var angle_label: Label
var announcement_label: Label
var tutorial_button: Button
var title_button: Button
var tutorial_panel: Panel
var tutorial_label: Label
var loot_label: Label
var loot_notice: Label
var shop_panel: Control
var equipment_button: Button
var boss_arrow: Control
var boss_arrow_label: Label
var large_map: Control
var equipment_labels: Dictionary = {}
var equipment_hint: Label
var menu_card: Panel
var eyebrow: Label

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Yu Gothic UI", "Meiryo", "Noto Sans CJK JP"])
	theme.default_font = font
	theme.default_font_size = 18
	root.theme = theme
	add_child(root)
	var hud := Control.new()
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud)
	boss_arrow = BossArrow.new()
	boss_arrow.game = game
	boss_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(boss_arrow)
	var top := Panel.new()
	top.add_theme_stylebox_override("panel", panel_style(Color("0d1b2be8")))
	place(top, Vector2(24, 18), Vector2(1232, 88))
	hud.add_child(top)
	health_label = label("", 21)
	place(health_label, Vector2(44, 27), Vector2(310, 32))
	hud.add_child(health_label)
	health_bar = ProgressBar.new()
	health_bar.show_percentage = false
	var health_background := panel_style(Color("25394a"))
	health_background.set_border_width_all(0)
	var health_fill := panel_style(Color("82dbac"))
	health_fill.set_border_width_all(0)
	health_bar.add_theme_stylebox_override("background", health_background)
	health_bar.add_theme_stylebox_override("fill", health_fill)
	place(health_bar, Vector2(44, 62), Vector2(275, 7))
	hud.add_child(health_bar)
	color_label = label("", 22)
	place(color_label, Vector2(362, 27), Vector2(135, 32))
	hud.add_child(color_label)
	angle_label = label("", 16)
	place(angle_label, Vector2(362, 61), Vector2(155, 24))
	hud.add_child(angle_label)
	gauge_label = label("", 17)
	place(gauge_label, Vector2(522, 26), Vector2(320, 28))
	hud.add_child(gauge_label)
	gauge_bar = ProgressBar.new()
	gauge_bar.max_value = T.ABSORPTIONS_PER_CHARGE
	gauge_bar.show_percentage = false
	gauge_bar.add_theme_stylebox_override("background", panel_style(Color("1c3547")))
	gauge_bar.add_theme_stylebox_override("fill", panel_style(Color.WHITE))
	place(gauge_bar, Vector2(524, 62), Vector2(220, 12))
	hud.add_child(gauge_bar)
	score_label = label("", 21)
	place(score_label, Vector2(862, 27), Vector2(375, 30))
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud.add_child(score_label)
	loot_label = label("", 16, T.CRYSTAL_COLOR)
	place(loot_label, Vector2(840, 80), Vector2(394, 24))
	loot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud.add_child(loot_label)
	loot_notice = label("", 20, T.CRYSTAL_COLOR)
	place(loot_notice, Vector2(80, 570), Vector2(1120, 64))
	loot_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loot_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud.add_child(loot_notice)
	progress_label = label("", 14, Color("91acbd"))
	place(progress_label, Vector2(44, 78), Vector2(445, 22))
	hud.add_child(progress_label)
	progress_bar = ProgressBar.new()
	progress_bar.show_percentage = false
	progress_bar.add_theme_stylebox_override("background", panel_style(Color("1c3547")))
	progress_bar.add_theme_stylebox_override("fill", panel_style(Color("4b7189")))
	place(progress_bar, Vector2(866, 73), Vector2(366, 5))
	hud.add_child(progress_bar)
	location_label = label("", 20, Color("c8decf"))
	place(location_label, Vector2(44, 118), Vector2(365, 30))
	hud.add_child(location_label)
	objective_label = label("", 15, Color("a3b4bd"))
	place(objective_label, Vector2(44, 151), Vector2(365, 28))
	hud.add_child(objective_label)
	boss_arrow_label = label("", 14, Color("a3b4bd"))
	place(boss_arrow_label, Vector2(44, 182), Vector2(365, 24))
	hud.add_child(boss_arrow_label)
	minimap = Minimap.new()
	minimap.game = game
	place(minimap, Vector2(936, 122), Vector2(320, 104))
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(minimap)
	for i in range(3):
		var slot: String = T.EQUIPMENT_SLOTS.keys()[i]
		var entry := label("", 14)
		place(entry, Vector2(902, 236 + i * 26), Vector2(354, 26))
		entry.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hud.add_child(entry)
		equipment_labels[slot] = entry
	equipment_hint = label("", 13, Color("ffdf80"))
	place(equipment_hint, Vector2(902, 318), Vector2(354, 25))
	equipment_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud.add_child(equipment_hint)
	boss_label = label("", 16)
	place(boss_label, Vector2(420, 120), Vector2(440, 28))
	boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(boss_label)
	boss_hp_label = label("", 28)
	place(boss_hp_label, Vector2(420, 148), Vector2(440, 40))
	boss_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(boss_hp_label)
	hint_label = label("", 22)
	place(hint_label, Vector2(190, 280), Vector2(700, 120))
	hint_label.add_theme_font_size_override("font_size", 20)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(hint_label)
	announcement_label = label("", 24, Color("fff0bb"))
	place(announcement_label, Vector2(80, 235), Vector2(780, 64))
	announcement_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	announcement_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	announcement_label.add_theme_color_override("font_shadow_color", Color("07111d"))
	announcement_label.add_theme_constant_override("shadow_outline_size", 6)
	hud.add_child(announcement_label)
	controls_label = label("", 14, Color("97b3c5"))
	place(controls_label, Vector2(24, 670), Vector2(1232, 45))
	controls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(controls_label)
	menu = Control.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(menu)
	var shade := ColorRect.new()
	shade.color = Color("040c16d9")
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(shade)
	var card := Panel.new()
	menu_card = card
	card.add_theme_stylebox_override("panel", panel_style(Color("102235f5"), Color("3e5d72")))
	place(card, Vector2(260, 134), Vector2(760, 520))
	menu.add_child(card)
	eyebrow = label("2色のアクション   /   洞窟を探索", 14, Color("81a6be"))
	place(eyebrow, Vector2(300, 160), Vector2(680, 24))
	menu.add_child(eyebrow)
	menu_title = label("", 48)
	place(menu_title, Vector2(300, 191), Vector2(680, 72))
	menu.add_child(menu_title)
	menu_subtitle = label("", 21, T.COLORS[0])
	place(menu_subtitle, Vector2(302, 271), Vector2(680, 40))
	menu.add_child(menu_subtitle)
	menu_detail = label("", 18, Color("afc2cf"))
	place(menu_detail, Vector2(302, 327), Vector2(680, 110))
	menu.add_child(menu_detail)
	seed_label = label("シード / 同じ数値なら同じマップ", 13, Color("81a6be"))
	place(seed_label, Vector2(302, 406), Vector2(676, 22))
	menu.add_child(seed_label)
	seed_field = LineEdit.new()
	seed_field.placeholder_text = "シード値（整数）"
	seed_field.max_length = 10
	place(seed_field, Vector2(302, 431), Vector2(676, 38))
	seed_field.text_submitted.connect(func(_text): game.primary_action())
	menu.add_child(seed_field)
	primary_button = Button.new()
	primary_button.add_theme_stylebox_override("normal", panel_style(Color("23546a"), Color("57d8ff")))
	primary_button.add_theme_stylebox_override("hover", panel_style(Color("2d6b83"), Color("a1eaff")))
	primary_button.add_theme_stylebox_override("focus", panel_style(Color("00000000"), Color("e9fbff")))
	place(primary_button, Vector2(302, 483), Vector2(676, 45))
	primary_button.pressed.connect(game.primary_action)
	menu.add_child(primary_button)
	new_button = Button.new()
	new_button.add_theme_stylebox_override("normal", panel_style(Color("1a3044")))
	place(new_button, Vector2(302, 541), Vector2(676, 40))
	new_button.pressed.connect(game.new_action)
	menu.add_child(new_button)
	equipment_button = Button.new()
	equipment_button.text = "装備"
	equipment_button.add_theme_stylebox_override("normal", panel_style(Color("1a3044")))
	place(equipment_button, Vector2(650, 541), Vector2(328, 40))
	equipment_button.pressed.connect(game.open_equipment)
	menu.add_child(equipment_button)
	settings_button = Button.new()
	settings_button.text = "キー設定"
	settings_button.add_theme_stylebox_override("normal", panel_style(Color("1a3044")))
	place(settings_button, Vector2(302, 594), Vector2(676, 36))
	settings_button.pressed.connect(game.open_key_settings)
	menu.add_child(settings_button)
	tutorial_button = Button.new()
	tutorial_button.text = "チュートリアル"
	tutorial_button.add_theme_stylebox_override("normal", panel_style(Color("1a3044")))
	place(tutorial_button, Vector2(650, 541), Vector2(328, 40))
	tutorial_button.pressed.connect(game.start_tutorial)
	menu.add_child(tutorial_button)
	title_button = Button.new()
	title_button.text = "タイトルへ戻る"
	title_button.add_theme_stylebox_override("normal", panel_style(Color("1a3044")))
	place(title_button, Vector2(650, 594), Vector2(328, 36))
	title_button.pressed.connect(game.return_to_title)
	menu.add_child(title_button)
	tutorial_panel = Panel.new()
	tutorial_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tutorial_panel.add_theme_stylebox_override("panel", panel_style(Color("0d1b2bf5"), Color("57d8ff")))
	place(tutorial_panel, Vector2(32, 540), Vector2(1216, 122))
	root.add_child(tutorial_panel)
	tutorial_label = label("", 20)
	place(tutorial_label, Vector2(20, 10), Vector2(1176, 102))
	tutorial_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tutorial_panel.add_child(tutorial_label)
	tutorial_panel.hide()
	settings_overlay = Control.new()
	settings_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(settings_overlay)
	var settings_shade := ColorRect.new()
	settings_shade.color = Color("040c16e8")
	settings_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_overlay.add_child(settings_shade)
	settings_panel = KeySettingsPanel.new()
	settings_panel.bindings = game.key_bindings
	settings_panel.settings_path = game.controls_path
	settings_panel.closed.connect(game.close_key_settings)
	settings_overlay.add_child(settings_panel)
	settings_overlay.hide()
	shop_panel = ShopPanel.new()
	shop_panel.game = game
	root.add_child(shop_panel)
	large_map = LargeMap.new()
	large_map.game = game
	root.add_child(large_map)
	large_map.hide()
	refresh_bindings()

func refresh_bindings() -> void:
	var keys: RefCounted = game.key_bindings
	controls_label.text = "左 %s   右 %s   %s ジャンプ   %s 薄い足場を降りる\n%s 射撃   %s 色切替   %s 射撃方向（前→上→下）   %s 誘導弾（1回消費）   %s 調べる   %s 一時停止" % [
		keys.get_binding_text("move_left"), keys.get_binding_text("move_right"), keys.get_binding_text("jump"),
		keys.get_binding_text("move_down"), keys.get_binding_text("shoot"), keys.get_binding_text("switch_color"),
		keys.get_binding_text("aim_cycle"), keys.get_binding_text("special"), keys.get_binding_text("interact"), keys.get_binding_text("pause_game")]
	if not game.is_tutorial():
		controls_label.text = controls_label.text.replace("ジャンプ", "ジャンプ / %s 空中ダッシュ（解禁後）" % keys.get_binding_text("dash"))
		controls_label.text += " / %s 回復薬" % keys.get_binding_text("use_item")
		controls_label.text += " / %s 地図" % keys.get_binding_text("world_map")
	hint_label.text = "撃破で誘導弾+1。吸収%d回で+1、最大%d回。ハートと箱で回復。\n%s 射撃 / %s 色切替 / %s 射撃方向（前→上→下）\n%s 薄い足場を降りる / %s 1回分で複数の敵へ誘導弾" % [T.ABSORPTIONS_PER_CHARGE, T.HOMING_CHARGE_CAPACITY,
		keys.get_binding_text("shoot"), keys.get_binding_text("switch_color"), keys.get_binding_text("aim_cycle"),
		keys.get_binding_text("move_down"), keys.get_binding_text("special")]
	if game.state == "title": menu_detail.text = title_instructions()

func title_instructions() -> String:
	return "あなたの色は青か橙です。%s でいつでも切り替えられます。\n自分と同じ色の攻撃は吸収し、ダメージを受けません。\n違う色の攻撃を受けるとHP（体力）が減ります。\n同じ色の攻撃を%d回吸収するか、敵を1体倒すと誘導弾が1回分たまります。\n%s で、敵を自動で追いかける「誘導弾」を撃てます。\nピンクのハートに触れるか、箱を撃って壊すとHPが回復します。\nHPが0になると結晶・鍵・装備などを全て失い、最初からやり直します。" % [game.key_bindings.get_binding_text("switch_color"), T.ABSORPTIONS_PER_CHARGE, game.key_bindings.get_binding_text("special")]

func update_equipment() -> void:
	var pending := false
	for slot: String in equipment_labels:
		var entry: Label = equipment_labels[slot]
		entry.visible = not game.is_tutorial() and game.state == "playing"
		if game.is_tutorial() or not is_instance_valid(game.player): continue
		var id: String = game.player.equipment[slot]
		var candidates: Array = game.owned_equipment.keys().filter(func(k): return T.EQUIPMENT[k].slot == slot)
		var available := id.is_empty() and not candidates.is_empty()
		pending = pending or available
		entry.text = "%s  %s" % [T.EQUIPMENT_SLOTS[slot], "なし" if id.is_empty() else T.EQUIPMENT[id].name]
		if available: entry.text += " ← %sを付けられます" % T.EQUIPMENT[candidates[0]].name
		entry.modulate = Color("ffdf80") if available else Color("dce9ef")
	equipment_hint.visible = pending and game.state == "playing"
	equipment_hint.text = "%s → 装備 で付け替え" % game.key_bindings.get_binding_text("pause_game")
	equipment_button.text = "装備 ●" if pending else "装備"

func update_hud() -> void:
	update_equipment()
	boss_arrow_label.text = game.boss_arrow_progress()
	boss_arrow_label.visible = not game.is_tutorial() and game.state == "playing" and not boss_arrow_label.text.is_empty()
	var live: bool = is_instance_valid(game.player) and not game.player.dead
	var health: int = game.player.hp if live else 0
	var maximum: int = game.player.max_hp if live else T.PLAYER_HP
	health_label.text = "HP  %d / %d" % [health, maximum]
	health_bar.max_value = maximum
	health_bar.value = health
	health_bar.modulate = Color("ffac82") if health <= maximum * 0.3 else Color.WHITE
	var color_index: int = game.player.polarity if live else 0
	color_label.text = T.COLOR_NAMES[color_index]
	color_label.modulate = T.COLORS[color_index]
	angle_label.text = "射撃方向 " + (game.player.aim_name() if live else T.AIM_NAMES[0])
	var charge: int = game.player.gauge if live else 0
	var required: int = game.player.absorptions_per_charge() if live else T.ABSORPTIONS_PER_CHARGE
	gauge_bar.max_value = required
	gauge_bar.value = charge
	gauge_bar.modulate = T.COLORS[color_index]
	var stocks: int = game.player.homing_charges if live else 0
	var capacity: int = game.player.charge_capacity() if live else T.HOMING_CHARGE_CAPACITY
	gauge_label.text = "誘導弾 %s%s  吸収%d/%d" % ["■".repeat(stocks), "□".repeat(capacity - stocks), charge, required]
	score_label.text = "スコア  %06d    時間 %s" % [game.score, game.clock_text()]
	loot_label.text = "結晶 %d    鍵 %d    回復薬 %d/%d" % [game.crystals, game.keys, game.potions, T.POTION_CAPACITY]
	loot_label.visible = not game.is_tutorial()
	loot_notice.visible = not game.is_tutorial() and game.state == "playing"
	loot_notice.text = game.loot_message if game.loot_message_remaining > 0 else game.interaction_hint()
	if game.loot_message_remaining > 0 and game.loot_ability != 0: loot_notice.text = game.ability_help(game.loot_ability)
	if game.is_tutorial():
		score_label.text = "チュートリアル  %d / 11" % mini(game.lesson + 1, 11)
		progress_label.text = "練習中はHPが1未満になりません"
		progress_bar.max_value = 11
		progress_bar.value = game.lesson
		location_label.text = "操作の練習"
		objective_label.text = game.direction_hint()
		for control in [minimap, boss_hp_label, boss_label, hint_label, announcement_label]: control.hide()
		tutorial_panel.visible = game.state == "playing"
		tutorial_label.text = game.lesson_text()
		return
	if game.stage.is_empty():
		return
	progress_label.text = "探索  %d区画   ·   シード %d" % [explored_sector_count(), game.current_seed]
	progress_bar.max_value = 3
	progress_bar.value = game.boss_cycle.final_clears if game.boss_cycle != null else 0
	var at: Vector2 = game.player.position if live else game.stage.start_position
	location_label.text = T.BIOME_NAMES[game.biome_at(at)]
	objective_label.text = game.boss_cycle.objective()
	announcement_label.text = game.announcement
	announcement_label.visible = game.announcement_remaining > 0 and game.state == "playing"
	minimap.update_map()
	var boss_visible: bool = is_instance_valid(game.boss) and not game.boss.dead and game.is_on_screen(game.boss.position)
	boss_hp_label.visible = boss_visible
	boss_label.visible = boss_visible
	if boss_visible:
		boss_hp_label.text = str(game.boss.hp)
		boss_label.text = "%s  /  %s" % [preload("res://scripts/boss_cycle.gd").name_for(game.boss.boss_role), T.COLOR_NAMES[game.boss.polarity]]
	hint_label.visible = game.state == "playing" and game.elapsed < 8.0 and live and game.player.position.distance_to(game.stage.start_position) < 400.0

func explored_sector_count() -> int:
	return game.visited_sectors.size()

func show_menu(next_state: String) -> void:
	menu.show()
	var title := next_state == "title"
	place(menu_card, Vector2(260, 44 if title else 134), Vector2(760, 610 if title else 520))
	place(eyebrow, Vector2(300, 56 if title else 160), Vector2(680, 24))
	place(menu_title, Vector2(300, 80 if title else 191), Vector2(680, 72))
	menu_subtitle.visible = not title
	place(menu_detail, Vector2(302, 162 if title else 327), Vector2(676, 238 if title else 110))
	menu_detail.add_theme_font_size_override("font_size", 16 if title else 18)
	menu_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	seed_field.text = str(game.current_seed)
	seed_field.visible = next_state == "title"
	seed_label.visible = next_state == "title"
	tutorial_panel.hide()
	tutorial_button.visible = next_state == "title" and not game.is_tutorial()
	title_button.visible = next_state == "paused" or next_state == "tutorial_complete"
	equipment_button.visible = next_state == "paused" and not game.is_tutorial()
	new_button.visible = next_state != "tutorial_complete"
	place(new_button, Vector2(302, 541), Vector2(328 if next_state == "title" or equipment_button.visible else 676, 40))
	place(settings_button, Vector2(302, 594), Vector2(328 if title_button.visible else 676, 36))
	match next_state:
		"title":
			menu_title.text = "CHROMA / SHIFT"
			menu_subtitle.text = ""
			menu_detail.text = title_instructions()
			primary_button.text = "このマップで開始  /  Enter"
			new_button.text = "別のマップを生成"
		"paused":
			menu_title.text = "一時停止"
			menu_subtitle.text = "ひと休み。準備ができたら再開。"
			menu_detail.text = "練習を再開できます。" if game.is_tutorial() else "スコア  %06d     /     シード  %d\n%s    ·    探索 %d区画" % [game.score, game.current_seed, game.boss_cycle.objective(), explored_sector_count()]
			primary_button.text = "再開  /  " + game.key_bindings.get_binding_text("pause_game")
			new_button.text = "同じマップを最初から"
		"lost", "won":
			menu_title.text = "クリア" if next_state == "won" else "失敗"
			menu_subtitle.text = "裏ボスを撃破。探索を完遂。" if next_state == "won" else "再挑戦は同じ地形で最初から。ボスの進行もリセット。"
			menu_detail.text = "スコア  %06d     /     時間  %s\nガーディアン %d体 · ラスボス %d回 · 裏ボス %d体\n通常敵 %d撃破 · 探索 %d区画 · シード %d" % [game.score, game.clock_text(), game.boss_cycle.guardian_kills, game.boss_cycle.final_clears, game.boss_cycle.secret_kills, game.kills, explored_sector_count(), game.current_seed]
			primary_button.text = "同じマップで再挑戦  /  Enter"
			menu_detail.text += "\n獲得した結晶 %d" % game.crystals_earned
			new_button.text = "新しいマップで開始"
		"tutorial_complete":
			menu_title.text = "練習完了"
			menu_subtitle.text = "基本の操作をひと通り練習しました。"
			menu_detail.text = "同じ色は吸収、違う色はダメージ。\n本編では洞窟を探索し、ガーディアンを探します。\nキー設定は本編でも引き継ぎます。"
			primary_button.text = "本編を始める"
	if game.is_tutorial() and next_state == "paused":
		menu_detail.text = "練習 %d / 11\n再開すると同じ課題から続けます。" % mini(game.lesson + 1, 11)
		new_button.text = "チュートリアルを最初から"
	update_hud()
	primary_button.grab_focus()

func label(text: String, size: int, tint: Color = Color("dce9ef")) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", size)
	result.add_theme_color_override("font_color", tint)
	return result

func place(control: Control, at: Vector2, size: Vector2) -> void:
	control.position = at
	control.size = size

func panel_style(tint: Color, border: Color = Color("294759")) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = tint
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	return style
