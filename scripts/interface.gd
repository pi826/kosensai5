extends CanvasLayer
const T := preload("res://scripts/tuning.gd")
const KeySettingsPanel := preload("res://scripts/key_settings_panel.gd")
const Minimap := preload("res://scripts/minimap.gd")
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
	gauge_bar.max_value = T.GAUGE_CAPACITY
	gauge_bar.show_percentage = false
	gauge_bar.add_theme_stylebox_override("background", panel_style(Color("1c3547")))
	gauge_bar.add_theme_stylebox_override("fill", panel_style(Color.WHITE))
	place(gauge_bar, Vector2(524, 62), Vector2(220, 12))
	hud.add_child(gauge_bar)
	score_label = label("", 21)
	place(score_label, Vector2(862, 27), Vector2(375, 30))
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud.add_child(score_label)
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
	minimap = Minimap.new()
	minimap.game = game
	place(minimap, Vector2(1016, 122), Vector2(240, 170))
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(minimap)
	boss_label = label("", 16)
	place(boss_label, Vector2(420, 120), Vector2(440, 28))
	boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(boss_label)
	boss_hp_label = label("", 28)
	place(boss_hp_label, Vector2(420, 148), Vector2(440, 40))
	boss_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(boss_hp_label)
	hint_label = label("", 22)
	place(hint_label, Vector2(190, 280), Vector2(800, 120))
	hint_label.add_theme_font_size_override("font_size", 20)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(hint_label)
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
	card.add_theme_stylebox_override("panel", panel_style(Color("102235f5"), Color("3e5d72")))
	place(card, Vector2(260, 134), Vector2(760, 520))
	menu.add_child(card)
	var eyebrow := label("02 COLORS   /   03 WARDENS   /   EXPLORE", 14, Color("81a6be"))
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
	seed_label = label("SEED / 同じ数値なら同じマップ", 13, Color("81a6be"))
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
	settings_button = Button.new()
	settings_button.text = "キー設定"
	settings_button.add_theme_stylebox_override("normal", panel_style(Color("1a3044")))
	place(settings_button, Vector2(302, 594), Vector2(676, 36))
	settings_button.pressed.connect(game.open_key_settings)
	menu.add_child(settings_button)
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
	refresh_bindings()

func refresh_bindings() -> void:
	var keys: RefCounted = game.key_bindings
	controls_label.text = "左 %s   右 %s   %s ジャンプ   %s 薄い足場を降りる\n%s 射撃   %s 色切替   %s 角度切替   %s 誘導弾   %s 調べる   %s 一時停止" % [
		keys.get_binding_text("move_left"), keys.get_binding_text("move_right"), keys.get_binding_text("jump"),
		keys.get_binding_text("move_down"), keys.get_binding_text("shoot"), keys.get_binding_text("switch_color"),
		keys.get_binding_text("aim_cycle"), keys.get_binding_text("special"), keys.get_binding_text("interact"), keys.get_binding_text("pause_game")]
	hint_label.text = "敵と違う色で攻撃。同色の弾は吸収して誘導弾に。\n%s 射撃 / %s 色切替 / %s 角度 0° → 60° → -60°\n%s 薄い足場を降りる / %s 複数の敵へ誘導弾" % [
		keys.get_binding_text("shoot"), keys.get_binding_text("switch_color"), keys.get_binding_text("aim_cycle"),
		keys.get_binding_text("move_down"), keys.get_binding_text("special")]

func update_hud() -> void:
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
	angle_label.text = "角度 %d°" % (game.player.aim_angle() if live else 0.0)
	var charge: int = game.player.gauge if live else 0
	gauge_bar.value = charge
	gauge_bar.modulate = T.COLORS[color_index]
	gauge_label.text = "%s  誘導弾  %d / %d" % [game.key_bindings.get_binding_text("special"), charge, T.GAUGE_CAPACITY]
	score_label.text = "SCORE  %06d    %s" % [game.score, game.clock_text()]
	if game.stage.is_empty():
		return
	progress_label.text = "探索  %d%%   ·   SEED %d" % [exploration_percent(), game.current_seed]
	progress_bar.max_value = 3
	progress_bar.value = game.defeated_bosses.size()
	var at: Vector2 = game.player.position if live else game.stage.start_position
	location_label.text = T.BIOME_NAMES[game.biome_at(at)]
	var marks: Array[String] = []
	for boss_id in range(3):
		marks.append("◆" if game.defeated_bosses.has(boss_id) else "◇")
	objective_label.text = "中ボス  %s  %d / 3 撃破" % ["  ".join(marks), game.defeated_bosses.size()]
	minimap.update_map()
	var boss_visible: bool = is_instance_valid(game.boss) and not game.boss.dead and game.is_on_screen(game.boss.position)
	boss_hp_label.visible = boss_visible
	boss_label.visible = boss_visible
	if boss_visible:
		boss_hp_label.text = str(game.boss.hp)
		boss_label.text = "WARDEN %d  /  %s" % [game.boss.boss_id + 1, T.COLOR_NAMES[game.boss.polarity]]
	hint_label.visible = game.state == "playing" and game.elapsed < 8.0 and live and game.player.position.distance_to(game.stage.start_position) < 400.0

func exploration_percent() -> int:
	if game.stage.is_empty():
		return 0
	var bounds: Rect2 = game.stage.bounds
	var cells := ceili(bounds.size.x / 128.0) * ceili(bounds.size.y / 128.0)
	return clampi(roundi(game.explored_cells.size() * 100.0 / maxi(cells, 1)), 0, 100)

func show_menu(next_state: String) -> void:
	menu.show()
	seed_field.text = str(game.current_seed)
	seed_field.visible = next_state == "title"
	seed_label.visible = next_state == "title"
	match next_state:
		"title":
			menu_title.text = "CHROMA / SHIFT"
			menu_subtitle.text = "3地域を探索し、3体の中ボスを倒す。"
			menu_detail.text = "敵と違う色で攻撃。同色の弾は吸収して誘導弾に。\n開けた洞窟を通路と縦穴で探索。\n倒れたら全リセット。目標プレイ時間 5〜10分。"
			primary_button.text = "このマップで開始  /  Enter"
			new_button.text = "別のマップを生成"
		"paused":
			menu_title.text = "PAUSED"
			menu_subtitle.text = "ひと休み。準備ができたら再開。"
			menu_detail.text = "SCORE  %06d     /     SEED  %d\n中ボス %d / 3 撃破    ·    探索 %d%%" % [game.score, game.current_seed, game.defeated_bosses.size(), exploration_percent()]
			primary_button.text = "再開  /  " + game.key_bindings.get_binding_text("pause_game")
			new_button.text = "同じマップを最初から"
		"lost", "won":
			menu_title.text = "STAGE CLEAR" if next_state == "won" else "TRY AGAIN"
			menu_subtitle.text = "3体の中ボスをすべて撃破。" if next_state == "won" else "再挑戦は同じ地形で最初から。中ボスも復活。"
			menu_detail.text = "SCORE  %06d     /     TIME  %s\n中ボス %d / 3    ·    通常敵 %d / %d\n探索 %d%%    ·    SEED %d" % [game.score, game.clock_text(), game.defeated_bosses.size(), game.kills, game.total_enemies, exploration_percent(), game.current_seed]
			primary_button.text = "同じマップで再挑戦  /  Enter"
			new_button.text = "新しいマップで開始"
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
