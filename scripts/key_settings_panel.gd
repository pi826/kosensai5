extends PanelContainer
## The parent pauses the world before opening this panel.
signal closed

const KeyBindings := preload("res://scripts/key_bindings.gd")
var bindings: RefCounted
var game: Node
var settings_path := "user://controls.cfg"
var _buttons: Dictionary = {}
var _status: Label
var _focus_controls: Array[Button] = []
var _focus_index := 0
var _waiting_action := ""
var _waiting_slot := -1
var _built := false
var _list_scroll: ScrollContainer

func _ready() -> void:
	_build()
	hide()
	set_process_input(false)

func open() -> void:
	if not _built:
		_build()
	if bindings == null:
		return
	_waiting_action = ""
	_waiting_slot = -1
	_status.text = "変更する欄を選んでください。設定は変更ごとに保存されます。"
	_status.modulate = Color("a9c0cf")
	_refresh()
	show()
	set_process_input(true)
	_focus_controls[0].grab_focus()

func _build() -> void:
	if _built:
		return
	_built = true
	position = Vector2(210, 48)
	custom_minimum_size = Vector2(860, 624)
	size = custom_minimum_size
	var style := StyleBoxFlat.new()
	style.bg_color = Color("102235")
	style.border_color = Color("4c7189")
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	add_theme_stylebox_override("panel", style)
	preload("res://scripts/art_skin.gd").apply(self)
	var margin := MarginContainer.new()
	for edge in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 24)
	add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)
	var title := Label.new()
	title.text = "キー設定"
	title.add_theme_font_size_override("font_size", 27)
	content.add_child(title)
	var help := Label.new()
	help.text = "1つの操作に2つまで設定できます。欄を選び、使いたいキーを押してください。\n入力待ち：Escで取消 / Backspaceで削除　　移動：矢印・Tab / 決定：Enter"
	help.add_theme_font_size_override("font_size", 15)
	help.modulate = Color("a9c0cf")
	content.add_child(help)
	_list_scroll = ScrollContainer.new()
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_list_scroll.follow_focus = true
	_list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list_scroll.custom_minimum_size.y = 240
	content.add_child(_list_scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 7)
	_list_scroll.add_child(grid)
	for heading in ["操作", "キー 1", "キー 2"]:
		var label := Label.new()
		label.text = heading
		label.custom_minimum_size = Vector2(250, 26)
		label.add_theme_font_size_override("font_size", 16)
		label.modulate = Color("a9c0cf")
		grid.add_child(label)
	for action: String in KeyBindings.ACTIONS:
		var name_label := Label.new()
		name_label.text = KeyBindings.ACTIONS[action]
		name_label.custom_minimum_size = Vector2(250, 40)
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(name_label)
		var row: Array[Button] = []
		for slot in range(2):
			var button := Button.new()
			button.custom_minimum_size = Vector2(250, 40)
			button.pressed.connect(_begin_wait.bind(action, slot))
			grid.add_child(button)
			row.append(button)
			_add_focus_control(button)
		_buttons[action] = row
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(780, 55)
	_status.add_theme_font_size_override("font_size", 16)
	content.add_child(_status)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 16)
	content.add_child(actions)
	var defaults := Button.new()
	defaults.text = "既定値へ戻す"
	defaults.custom_minimum_size = Vector2(382, 44)
	defaults.pressed.connect(_reset)
	actions.add_child(defaults)
	_add_focus_control(defaults)
	var done := Button.new()
	done.text = "閉じる / Esc"
	done.custom_minimum_size = Vector2(382, 44)
	done.pressed.connect(_close)
	actions.add_child(done)
	_add_focus_control(done)

func _add_focus_control(button: Button) -> void:
	var index := _focus_controls.size()
	_focus_controls.append(button)
	button.focus_entered.connect(func(): _focus_index = index)

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey:
		return
	get_viewport().set_input_as_handled()
	if not event.pressed or event.echo:
		return
	var key: int = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	key &= KEY_CODE_MASK
	if not _waiting_action.is_empty():
		if key == KEY_ESCAPE:
			_waiting_action = ""
			_waiting_slot = -1
			_status.text = "変更を取り消しました。"
			_status.modulate = Color("a9c0cf")
			_refresh()
		else:
			_assign(_waiting_action, _waiting_slot, KEY_NONE if key == KEY_BACKSPACE else key)
		return
	match key:
		KEY_ESCAPE:
			_close()
		KEY_BACKSPACE:
			if _focus_index < KeyBindings.ACTIONS.size() * 2:
				var action: String = KeyBindings.ACTIONS.keys()[_focus_index / 2]
				_assign(action, _focus_index % 2, KEY_NONE)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_focus_controls[_focus_index].pressed.emit()
		KEY_TAB:
			_move_focus(-1 if event.shift_pressed else 1)
		KEY_LEFT:
			_move_focus(-1)
		KEY_RIGHT:
			_move_focus(1)
		KEY_UP:
			_move_focus(-2)
		KEY_DOWN:
			_move_focus(2)

func _move_focus(offset: int) -> void:
	if is_instance_valid(game): game.play_sound("ui_move")
	_focus_index = posmod(_focus_index + offset, _focus_controls.size())
	_focus_controls[_focus_index].grab_focus()

func _begin_wait(action: String, slot: int) -> void:
	if is_instance_valid(game): game.play_sound("ui_confirm")
	_waiting_action = action
	_waiting_slot = slot
	_status.text = "「%s」のキー%dを入力してください。Escで取消 / Backspaceで削除。" % [KeyBindings.ACTIONS[action], slot + 1]
	_status.modulate = Color("57d8ff")
	_refresh()

func _assign(action: String, slot: int, key: int) -> void:
	var reason: String = bindings.try_bind(action, slot, key)
	if not reason.is_empty():
		_status.text = reason
		_status.modulate = Color("ffac63")
		return
	_waiting_action = ""
	_waiting_slot = -1
	_save("「%s」を %s に変更しました。" % [KeyBindings.ACTIONS[action], bindings.get_binding_text(action)])
	_refresh()

func _reset() -> void:
	bindings.reset_defaults()
	_waiting_action = ""
	_waiting_slot = -1
	_save("キー設定を既定値へ戻しました。")
	_refresh()

func _save(message: String) -> void:
	var result: Error = bindings.save_settings(settings_path)
	if result == OK:
		_status.text = message
		_status.modulate = Color("a9c0cf")
	else:
		_status.text = "変更は今回の起動中に反映されましたが、保存できませんでした。（%s）" % error_string(result)
		_status.modulate = Color("ffac63")

func _refresh() -> void:
	for action: String in KeyBindings.ACTIONS:
		for slot in range(2):
			var button: Button = _buttons[action][slot]
			button.text = "キーを入力…" if action == _waiting_action and slot == _waiting_slot else KeyBindings.key_text(bindings.get_key(action, slot))

func _close() -> void:
	_waiting_action = ""
	_waiting_slot = -1
	hide()
	set_process_input(false)
	closed.emit()
