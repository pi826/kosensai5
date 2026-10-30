extends PanelContainer
signal closed
var game: Node
var sliders: Array[HSlider] = []
var percentages: Array[Label] = []
var focus_controls: Array[Control] = []
var focus_index := 0
var status: Label
var refreshing := false

func _ready() -> void:
	position = Vector2(260, 170)
	size = Vector2(760, 380)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("102235")
	style.border_color = Color("4c7189")
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	add_theme_stylebox_override("panel", style)
	var margin := MarginContainer.new()
	for edge in ["left", "top", "right", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 24)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 15)
	margin.add_child(column)
	var title := Label.new()
	title.text = "音量"
	title.add_theme_font_size_override("font_size", 27)
	column.add_child(title)
	var help := Label.new()
	help.text = "↑↓ 選択　←→ 10%ずつ変更　Enter 決定　Esc 閉じる"
	help.add_theme_font_size_override("font_size", 16)
	help.modulate = Color("a9c0cf")
	column.add_child(help)
	for i in range(3):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 20)
		column.add_child(row)
		var label := Label.new()
		label.text = ["全体", "BGM", "効果音"][i]
		label.custom_minimum_size = Vector2(115, 42)
		row.add_child(label)
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 10
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.custom_minimum_size.y = 42
		row.add_child(slider)
		sliders.append(slider)
		_add_focus(slider)
		slider.value_changed.connect(_changed.bind(i))
		var percent := Label.new()
		percent.custom_minimum_size.x = 68
		percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(percent)
		percentages.append(percent)
	status = Label.new()
	status.add_theme_font_size_override("font_size", 14)
	status.text = "変更はすぐ反映され、閉じると保存します。"
	column.add_child(status)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 16)
	column.add_child(actions)
	for i in range(2):
		var button := Button.new()
		button.text = "既定に戻す" if i == 0 else "閉じる / Esc"
		button.custom_minimum_size = Vector2(345, 44)
		button.pressed.connect(_reset if i == 0 else _close)
		actions.add_child(button)
		_add_focus(button)
	hide()
	set_process_input(false)

func _add_focus(control: Control) -> void:
	var i := focus_controls.size()
	focus_controls.append(control)
	control.focus_entered.connect(func(): focus_index = i)

func open() -> void:
	_refresh()
	status.text = "変更はすぐ反映され、閉じると保存します。"
	show()
	set_process_input(true)
	focus_controls[0].grab_focus()

func _refresh() -> void:
	refreshing = true
	for i in range(3):
		var value: int = game.audio.settings.values[["master", "bgm", "se"][i]]
		sliders[i].value = value
		percentages[i].text = "%d%%" % value
	refreshing = false

func _changed(value: float, i: int) -> void:
	if refreshing: return
	game.audio.settings.values[["master", "bgm", "se"][i]] = roundi(value)
	percentages[i].text = "%d%%" % roundi(value)
	game.audio.settings.apply()
	status.text = "変更はすぐ反映され、閉じると保存します。"
	if i != 1: game.play_sound("ui_confirm")

func _save() -> void:
	var result: Error = game.audio.settings.save_settings(game.audio_settings_path)
	status.text = "保存しました。" if result == OK else "保存できませんでした（%s）" % error_string(result)

func _reset() -> void:
	game.audio.settings.values = preload("res://scripts/audio_settings.gd").DEFAULTS.duplicate()
	game.audio.settings.apply()
	_refresh()
	_save()
	game.play_sound("ui_confirm")

func _close() -> void:
	_save()
	hide()
	set_process_input(false)
	game.play_sound("ui_back")
	closed.emit()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree(): return
	# Capture all key/action events, including releases and gameplay bindings.
	if event is InputEventKey or event is InputEventAction:
		get_viewport().set_input_as_handled()
	else: return # Mouse remains available to the sliders' native GUI handling.
	if not event is InputEventKey or not event.pressed: return
	var key: int = event.physical_keycode if event.physical_keycode else event.keycode
	match key:
		KEY_ESCAPE:
			if not event.echo: _close()
		KEY_UP, KEY_DOWN, KEY_TAB:
			focus_index = posmod(focus_index + (-1 if key == KEY_UP or key == KEY_TAB and event.shift_pressed else 1), 5)
			focus_controls[focus_index].grab_focus()
			game.play_sound("ui_move")
		KEY_LEFT, KEY_RIGHT:
			if focus_index < 3: sliders[focus_index].value += -10 if key == KEY_LEFT else 10
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if focus_index >= 3 and not event.echo: focus_controls[focus_index].pressed.emit()
