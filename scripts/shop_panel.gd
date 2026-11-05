extends Control
## A fixed bento canvas; every card remains visible and focusable.
const T := preload("res://scripts/tuning.gd")
const Tile := preload("res://scripts/shop_tile.gd")
var game: Node2D
var buying := true
var upgrading := false
var can_buy := true
var balance_label: Label
var status_label: Label
var help_label: Label
var buy_tab: Button
var equipment_tab: Button
var upgrade_tab: Button
var close_button: Button
var rows: Control
var focus_buttons: Array[Button] = []
var item_buttons: Dictionary = {}
var equipment_buttons: Dictionary = {}
var upgrade_buttons: Dictionary = {}
var current_cards: Dictionary = {}
var upgrade_message := ""
var _accept_held: Dictionary = {}
var _last_activation_ms := -1000

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color("040c16f5")
	add_child(shade)
	var card := Panel.new()
	card.position = Vector2(100, 44)
	card.size = Vector2(1080, 608)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("102235")
	style.border_color = T.MERCHANT_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	card.add_theme_stylebox_override("panel", style)
	add_child(card)
	var title := Label.new()
	title.text = "商人  /  装備"
	title.position = Vector2(132, 63)
	title.add_theme_font_size_override("font_size", 30)
	add_child(title)
	balance_label = Label.new()
	balance_label.position = Vector2(620, 71)
	balance_label.size = Vector2(526, 36)
	balance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	balance_label.modulate = T.CRYSTAL_COLOR
	add_child(balance_label)
	buy_tab = _button("買う", Vector2(132, 118), Vector2(150, 42))
	buy_tab.pressed.connect(_switch_tab.bind(true))
	equipment_tab = _button("装備", Vector2(294, 118), Vector2(150, 42))
	equipment_tab.pressed.connect(_switch_tab.bind(false))
	upgrade_tab = _button("強化", Vector2(456, 118), Vector2(150, 42))
	upgrade_tab.pressed.connect(_switch_tab.bind(false, true))
	upgrade_tab.visible = false
	close_button = _button("閉じる", Vector2(994, 118), Vector2(152, 42))
	close_button.pressed.connect(game.close_shop)
	rows = Control.new()
	rows.position = Vector2(132, 178)
	rows.size = Vector2(1014, 352)
	add_child(rows)
	status_label = Label.new()
	status_label.position = Vector2(132, 544)
	status_label.size = Vector2(1014, 48)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.modulate = Color("ffe0ab")
	add_child(status_label)
	help_label = Label.new()
	help_label.position = Vector2(132, 608)
	help_label.add_theme_font_size_override("font_size", 15)
	help_label.modulate = Color("a9c0cf")
	add_child(help_label)
	hide()

func _button(text: String, at: Vector2, extent: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.position = at
	button.size = extent
	add_child(button)
	return button

func open(from_merchant: bool) -> void:
	can_buy = from_merchant
	buying = from_merchant
	upgrading = false
	upgrade_message = ""
	_accept_held.clear()
	buy_tab.visible = from_merchant
	upgrade_tab.visible = from_merchant
	status_label.text = "装備は購入後、この画面の「装備」で選んで付けます。" if from_merchant else "枠ごとに1つ。付け替えはすぐに反映されます。"
	help_label.text = "↑↓←→ カードを選択　 Enter / Space 決定　 %sEsc / %s 閉じる" % ["Tab 買う・装備・強化　 " if from_merchant else "", game.key_bindings.get_binding_text("interact")]
	show()
	_rebuild()

func _switch_tab(next_buying: bool, next_upgrading: bool = false) -> void:
	if (next_buying or next_upgrading) and not can_buy: return
	if buying != (next_buying and not next_upgrading) or upgrading != next_upgrading: game.play_sound("ui_move")
	buying = next_buying and not next_upgrading
	upgrading = next_upgrading
	upgrade_message = ""
	status_label.text = "装備は自動で付きません。「装備」で選んでください。" if buying else ("各枠に1つ。選び直すか「外す」で変更できます。" if not upgrading else "")
	_rebuild()

func _tile(at: Vector2, extent: Vector2, category: String, small: bool = false) -> Button:
	var button := Tile.new()
	button.category = category
	button.tint = T.SHOP_CATEGORY_COLORS.get(category, Color.WHITE)
	button.position = at
	button.size = extent
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_font_size_override("font_size", 14 if small else 16)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("1b3448") if state == "normal" else Color("26475d")
		if state == "focus": style.bg_color = Color.TRANSPARENT
		style.border_color = Color("fff0bc") if state == "focus" else Color(button.tint, 0.45)
		style.set_border_width_all(3 if state == "focus" else 1)
		style.set_corner_radius_all(8)
		style.content_margin_left = 46
		style.content_margin_right = 12
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		button.add_theme_stylebox_override(state, style)
	rows.add_child(button)
	focus_buttons.append(button)
	return button

func _rebuild() -> void:
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	item_buttons.clear()
	equipment_buttons.clear()
	upgrade_buttons.clear()
	current_cards.clear()
	focus_buttons.clear()
	upgrade_tab.visible = can_buy
	if can_buy: focus_buttons.append_array([buy_tab, equipment_tab, upgrade_tab])
	else: focus_buttons.append(equipment_tab)
	focus_buttons.append(close_button)
	if buying:
		var equipment_index := 0
		var equipment_count: int = game.active_merchant.stock.filter(func(id): return T.EQUIPMENT.has(id)).size()
		for id: String in game.active_merchant.stock:
			var category: String = id if id in ["potion", "key"] else T.EQUIPMENT[id].slot
			var at: Vector2
			var extent: Vector2
			if id in ["potion", "key"]:
				at = Vector2(0, 0 if id == "potion" else 182)
				extent = Vector2(236, 170)
			else:
				if equipment_count <= 3:
					at = Vector2(248, 0) if equipment_index == 0 else Vector2(636, (equipment_index - 1) * 182)
					extent = Vector2(376, 352) if equipment_index == 0 else Vector2(378, 170)
				elif equipment_count == 4:
					at = Vector2(248 + equipment_index * 260, 0) if equipment_index < 2 else Vector2(767, (equipment_index - 2) * 182)
					extent = Vector2(248 if equipment_index == 0 else 247, 352 if equipment_index < 2 else 170)
				else:
					at = Vector2(248, 0) if equipment_index == 0 else Vector2(508 + ((equipment_index - 1) / 2) * 259, ((equipment_index - 1) % 2) * 182)
					extent = Vector2(248, 352) if equipment_index == 0 else Vector2(247, 170)
				equipment_index += 1
			var button := _tile(at, extent, category)
			button.art_id = id
			button.pressed.connect(_buy.bind(id))
			item_buttons[id] = button
	elif upgrading:
		var column := 0
		for slot: String in T.EQUIPMENT_SLOTS:
			var owned: Array = T.EQUIPMENT.keys().filter(func(k): return T.EQUIPMENT[k].slot == slot and game.owned_equipment.has(k))
			if owned.is_empty():
				var empty := Label.new()
				empty.text = "まだ持っていません"
				empty.position = Vector2(column * 338, 0)
				empty.size = Vector2(330, 44)
				empty.add_theme_font_size_override("font_size", 14)
				empty.modulate = Color("8496a6")
				rows.add_child(empty)
			for i in range(owned.size()):
				var id: String = owned[i]
				var button := _tile(Vector2(column * 338, i * 116), Vector2(330, 108), slot, true)
				button.art_id = id
				button.pressed.connect(_upgrade.bind(id))
				upgrade_buttons[id] = button
			column += 1
	else:
		var column := 0
		for slot: String in T.EQUIPMENT_SLOTS:
			var selected: String = game.player.equipment[slot]
			var current := _tile(Vector2(column * 342, 0), Vector2(330, 120), slot)
			current.art_id = selected
			current_cards[slot] = current
			current.pressed.connect(_equip.bind(slot, selected))
			if not selected.is_empty(): equipment_buttons[slot + ":" + selected] = current
			var alternatives: Array = T.EQUIPMENT.keys().filter(func(k): return T.EQUIPMENT[k].slot == slot and game.owned_equipment.has(k) and k != selected)
			alternatives.append("")
			for i in range(alternatives.size()):
				var id: String = alternatives[i]
				var button := _tile(Vector2(column * 342, 128 + i * 56), Vector2(330, 50), slot, true)
				button.art_id = id
				button.pressed.connect(_equip.bind(slot, id))
				equipment_buttons[slot + ":" + id] = button
			column += 1
	refresh()
	var first_card := 4 if can_buy else 2
	if focus_buttons.size() > first_card: focus_buttons[first_card].grab_focus()
	else: close_button.grab_focus()

func refresh() -> void:
	balance_label.text = "結晶 %d　 鍵 %d　 回復薬 %d/%d" % [game.crystals, game.keys, game.potions, T.POTION_CAPACITY]
	buy_tab.text = "● 買う" if buying else "買う"
	equipment_tab.text = "● 装備" if not buying and not upgrading else "装備"
	upgrade_tab.text = "● 強化" if upgrading else "強化"
	if upgrading:
		status_label.text = "強化できる回数 %d（ラスボスを倒すごとに1回）" % game.upgrade_tokens
		if not upgrade_message.is_empty(): status_label.text += "\n" + upgrade_message
	for id: String in item_buttons:
		var name: String = "回復薬" if id == "potion" else ("鍵" if id == "key" else T.EQUIPMENT[id].name)
		var category: String = "回復" if id == "potion" else ("宝箱" if id == "key" else T.EQUIPMENT_SLOTS[T.EQUIPMENT[id].slot])
		var description: String = "HPを%d回復 / 最大%d個\n%s で使う" % [T.POTION_HEAL, T.POTION_CAPACITY, game.key_bindings.get_binding_text("use_item")] if id == "potion" else ("宝箱を1つ開ける\nこの商人で1回のみ" if id == "key" else T.EQUIPMENT[id].description)
		var reason: String = game.purchase_reason(id)
		item_buttons[id].text = "%s / %s\n%s\n結晶 %d　 %s" % [category, name, description, game.item_price(id), "購入可" if reason.is_empty() else reason]
		item_buttons[id].modulate = Color.WHITE if reason.is_empty() else Color("8496a6")
	for slot: String in current_cards:
		var id: String = game.player.equipment[slot]
		var owned: bool = game.owned_equipment.keys().any(func(k): return T.EQUIPMENT[k].slot == slot)
		var current_name: String = "なし" if id.is_empty() else _equipment_name(id)
		current_cards[slot].text = "%s / 今の装備\n%s\n%s" % [T.EQUIPMENT_SLOTS[slot], current_name, ("下のカードで装備できます" if owned else "まだ持っていません") if id.is_empty() else T.EQUIPMENT[id].description]
	for key: String in equipment_buttons:
		var parts := key.split(":")
		var id := parts[1]
		var selected: bool = game.player.equipment[parts[0]] == id
		if current_cards[parts[0]] == equipment_buttons[key]: continue
		equipment_buttons[key].text = "外す（装備なし）" if id.is_empty() else _equipment_name(id) + " を付ける"
		equipment_buttons[key].tooltip_text = "" if id.is_empty() else T.EQUIPMENT[id].description
		equipment_buttons[key].modulate = T.MERCHANT_COLOR if selected else Color.WHITE
	for id: String in upgrade_buttons:
		var level: int = game.equipment_level(id)
		var category: String = T.EQUIPMENT_SLOTS[T.EQUIPMENT[id].slot]
		var reason: String = game.upgrade_reason(id)
		if level >= T.EQUIPMENT_MAX_LEVEL:
			upgrade_buttons[id].text = "%s / %s\nLv%d（最大）\n%s" % [category, T.EQUIPMENT[id].name, level, game.equipment_effect_text(id, level)]
		else:
			upgrade_buttons[id].text = "%s / %s\nLv%d → Lv%d：%s → %s\n結晶 %d　 %s" % [category, T.EQUIPMENT[id].name, level, level + 1, game.equipment_effect_text(id, level), game.equipment_effect_text(id, level + 1), game.upgrade_price(id), "強化可" if reason.is_empty() else reason]
		upgrade_buttons[id].modulate = Color.WHITE if reason.is_empty() else Color("8496a6")

func _equipment_name(id: String) -> String:
	var level: int = game.equipment_level(id)
	return T.EQUIPMENT[id].name + (" Lv%d" % level if level > 1 else "")

func _allow_activation() -> bool:
	var now := Time.get_ticks_msec()
	if now - _last_activation_ms < int(T.SHOP_ACTION_INTERVAL * 1000): return false
	_last_activation_ms = now
	return true

func _buy(id: String) -> void:
	if not visible or not buying or not _allow_activation(): return
	var reason: String = game.purchase_reason(id)
	if game.buy_item(id):
		status_label.text = "購入しました。装備は「装備」で選んで付けてください。" if T.EQUIPMENT.has(id) else "購入しました。"
	elif not reason.is_empty(): status_label.text = reason
	refresh()

func _equip(slot: String, id: String) -> void:
	if not visible or buying or upgrading or not _allow_activation(): return
	if game.equip(slot, id):
		status_label.text = "%s：%s" % [T.EQUIPMENT_SLOTS[slot], "装備なし" if id.is_empty() else T.EQUIPMENT[id].name]
		_rebuild()
		if equipment_buttons.has(slot + ":" + id): equipment_buttons[slot + ":" + id].grab_focus()

func _upgrade(id: String) -> void:
	if not visible or not upgrading or not _allow_activation(): return
	var reason: String = game.upgrade_reason(id)
	var before: int = game.equipment_level(id)
	if game.upgrade_item(id):
		upgrade_message = "%sを Lv%d に強化しました" % [T.EQUIPMENT[id].name, before + 1]
	elif not reason.is_empty():
		upgrade_message = reason
	refresh()
	if upgrade_buttons.has(id): upgrade_buttons[id].grab_focus()

func neighbor(button: Button, direction: Vector2) -> Button:
	var best: Button = button
	var distance := INF
	var at := button.get_global_rect().get_center()
	for candidate: Button in focus_buttons:
		if candidate == button: continue
		var delta := candidate.get_global_rect().get_center() - at
		var forward := delta.dot(direction)
		if forward <= 1: continue
		var extent := (button.size + candidate.size) / 2
		var side := maxf(0, absf(delta.cross(direction)) - absf(direction.y) * extent.x - absf(direction.x) * extent.y)
		var cost := forward + side * 10.0 + side * side / forward + absf(delta.cross(direction)) * 0.05
		if cost < distance:
			distance = cost
			best = candidate
	return best

func _input(event: InputEvent) -> void:
	if not visible: return
	if event.is_pressed() and not event.is_echo() and (event.is_action_pressed("pause_game") or event.is_action_pressed("interact") or (event is InputEventKey and event.keycode == KEY_ESCAPE)):
		game.close_shop()
		get_viewport().set_input_as_handled()
		return
	if event.is_action("ui_accept"):
		var source := str(event.keycode if event is InputEventKey and event.keycode != 0 else (event.physical_keycode if event is InputEventKey else "accept"))
		if not event.is_pressed(): _accept_held.erase(source)
		elif not event.is_echo() and _accept_held.is_empty():
			_accept_held[source] = true
			var focused := get_viewport().gui_get_focus_owner()
			if focused is Button and focus_buttons.has(focused): focused.pressed.emit()
		get_viewport().set_input_as_handled()
		return
	if not event.is_pressed(): return
	if event.is_echo():
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.keycode == KEY_TAB:
		if can_buy:
			if buying: _switch_tab(false)
			elif upgrading: _switch_tab(true)
			else: _switch_tab(false, true)
	else:
		var direction := Vector2.ZERO
		if event.is_action_pressed("ui_left"): direction = Vector2.LEFT
		elif event.is_action_pressed("ui_right"): direction = Vector2.RIGHT
		elif event.is_action_pressed("ui_up"): direction = Vector2.UP
		elif event.is_action_pressed("ui_down"): direction = Vector2.DOWN
		else: return
		var focused := get_viewport().gui_get_focus_owner() as Button
		if focused != null and focus_buttons.has(focused):
			var next := neighbor(focused, direction)
			if next != focused: game.play_sound("ui_move")
			next.grab_focus()
	get_viewport().set_input_as_handled()
