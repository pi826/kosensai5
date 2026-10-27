extends Control
## UI stays active while the same world subtree as pause is disabled.
const T := preload("res://scripts/tuning.gd")
var game: Node2D
var buying := true
var can_buy := true
var balance_label: Label
var status_label: Label
var buy_tab: Button
var equipment_tab: Button
var close_button: Button
var scroll: ScrollContainer
var rows: HBoxContainer
var focus_buttons: Array[Button] = []
var item_buttons: Dictionary = {}
var equipment_buttons: Dictionary = {}
var _accept_held: Dictionary = {}
var _last_activation_ms := -1000

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color("040c16eb")
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
	close_button = _button("閉じる", Vector2(994, 118), Vector2(152, 42))
	close_button.pressed.connect(game.close_shop)
	scroll = ScrollContainer.new()
	scroll.position = Vector2(132, 178)
	scroll.size = Vector2(1014, 352)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	rows = HBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 18)
	scroll.add_child(rows)
	status_label = Label.new()
	status_label.position = Vector2(132, 544)
	status_label.size = Vector2(1014, 42)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.modulate = Color("ffe0ab")
	add_child(status_label)
	var help := Label.new()
	help.text = "↑↓ / Tab 選択　 Enter / Space 決定　 ←→ 買う・装備　 Esc / 調べる 閉じる"
	help.position = Vector2(132, 608)
	help.add_theme_font_size_override("font_size", 15)
	help.modulate = Color("a9c0cf")
	add_child(help)
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
	_accept_held.clear()
	buy_tab.visible = from_merchant
	status_label.text = "装備は購入後、この画面の「装備」で選んで付けます。" if from_merchant else "枠ごとに1つ。付け替えはすぐに反映されます。"
	show()
	_rebuild()

func _switch_tab(next_buying: bool) -> void:
	if next_buying and not can_buy: return
	buying = next_buying
	status_label.text = "装備は自動で付きません。「装備」で選んでください。" if buying else "各枠に1つ。選び直すか「外す」で変更できます。"
	_rebuild()

func _rebuild() -> void:
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	item_buttons.clear()
	equipment_buttons.clear()
	focus_buttons.clear()
	if can_buy: focus_buttons.append(buy_tab)
	focus_buttons.append_array([equipment_tab, close_button])
	if buying:
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 8)
		rows.add_child(list)
		for id: String in game.active_merchant.stock:
			var button := _row_button(list)
			button.pressed.connect(_buy.bind(id))
			item_buttons[id] = button
	else:
		for slot: String in T.EQUIPMENT_SLOTS:
			var list := VBoxContainer.new()
			list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			list.custom_minimum_size.x = 316
			list.add_theme_constant_override("separation", 8)
			rows.add_child(list)
			var heading := Label.new()
			heading.text = T.EQUIPMENT_SLOTS[slot]
			heading.add_theme_font_size_override("font_size", 22)
			list.add_child(heading)
			for id: String in [""] + T.EQUIPMENT.keys().filter(func(k): return T.EQUIPMENT[k].slot == slot and game.owned_equipment.has(k)):
				var button := _row_button(list)
				button.pressed.connect(_equip.bind(slot, id))
				equipment_buttons[slot + ":" + id] = button
	refresh()
	scroll.scroll_vertical = 0
	if focus_buttons.size() > (3 if can_buy else 2): focus_buttons[3 if can_buy else 2].grab_focus()
	else: equipment_tab.grab_focus()

func _row_button(parent: Control) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 72)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_font_size_override("font_size", 16)
	parent.add_child(button)
	focus_buttons.append(button)
	return button

func refresh() -> void:
	balance_label.text = "結晶 %d　 鍵 %d　 回復薬 %d/%d" % [game.crystals, game.keys, game.potions, T.POTION_CAPACITY]
	buy_tab.text = "● 買う" if buying else "買う"
	equipment_tab.text = "● 装備" if not buying else "装備"
	for id: String in item_buttons:
		var name: String = "回復薬" if id == "potion" else ("鍵" if id == "key" else T.EQUIPMENT[id].name)
		var description: String = "HPを%d回復 / 最大%d個 / %s で使う" % [T.POTION_HEAL,T.POTION_CAPACITY,game.key_bindings.get_binding_text("use_item")] if id == "potion" else ("宝箱を1つ開ける / この商人で1回のみ" if id == "key" else T.EQUIPMENT_SLOTS[T.EQUIPMENT[id].slot] + "：" + T.EQUIPMENT[id].description)
		var reason: String = game.purchase_reason(id)
		item_buttons[id].text = "  %s　 /　結晶 %d　 %s\n  %s" % [name,game.item_price(id),"購入可" if reason.is_empty() else reason,description]
		item_buttons[id].modulate = Color.WHITE if reason.is_empty() else Color("a6b3be")
		# Keep unavailable rows focusable so keyboard users can read the reason.
	for key: String in equipment_buttons:
		var parts := key.split(":")
		var id := parts[1]
		var selected: bool = game.player.equipment[parts[0]] == id
		var text := "外す（装備なし）" if id.is_empty() else str(T.EQUIPMENT[id].name)
		var description := "" if id.is_empty() else str(T.EQUIPMENT[id].description)
		equipment_buttons[key].text = "  %s%s\n  %s" % ["● " if selected else "",text,description]
		equipment_buttons[key].modulate = T.MERCHANT_COLOR if selected else Color.WHITE

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
	if not visible or buying or not _allow_activation(): return
	if game.equip(slot, id): status_label.text = "%s：%s" % [T.EQUIPMENT_SLOTS[slot],"装備なし" if id.is_empty() else T.EQUIPMENT[id].name]
	refresh()

func _input(event: InputEvent) -> void:
	if not visible: return
	# A custom interact/pause binding can also be Enter or Space.
	if event.is_pressed() and not event.is_echo() and (event.is_action_pressed("pause_game") or event.is_action_pressed("interact") or (event is InputEventKey and event.keycode == KEY_ESCAPE)):
		game.close_shop()
		get_viewport().set_input_as_handled()
		return
	if event.is_action("ui_accept"):
		# Consume before native Button keyboard handling, including key echoes.
		var source := str(event.keycode if event is InputEventKey and event.keycode != 0 else (event.physical_keycode if event is InputEventKey else "accept"))
		if not event.is_pressed(): _accept_held.erase(source)
		elif not event.is_echo() and _accept_held.is_empty():
			_accept_held[source] = true
			var focused := get_viewport().gui_get_focus_owner()
			if focused is Button and focus_buttons.has(focused): focused.pressed.emit()
		get_viewport().set_input_as_handled()
		return
	if event.is_echo():
		get_viewport().set_input_as_handled()
		return
	if not event.is_pressed(): return
	if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		_switch_tab(not buying if can_buy else false)
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("ui_up") or event.is_action_pressed("ui_focus_next") or event.is_action_pressed("ui_focus_prev"):
		var index := focus_buttons.find(get_viewport().gui_get_focus_owner())
		var step := -1 if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_focus_prev") else 1
		focus_buttons[posmod(index + step, focus_buttons.size())].grab_focus()
	else: return
	get_viewport().set_input_as_handled()
