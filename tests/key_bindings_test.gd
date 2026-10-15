extends SceneTree
const KeyBindings := preload("res://scripts/key_bindings.gd")
const SettingsPanel := preload("res://scripts/key_settings_panel.gd")

class InputSpy extends Node:
	var unhandled_keys := 0
	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey:
			unhandled_keys += 1

class SaveFailure extends "res://scripts/key_bindings.gd":
	func save_settings(_path: String = "user://controls.cfg") -> Error:
		return ERR_FILE_CANT_WRITE

var checks := 0
var failures: Array[String] = []
var _test_paths: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: ", message)

func _new_path() -> String:
	var path := "user://key_bindings_test_%d_%d.cfg" % [Time.get_ticks_usec(), _test_paths.size()]
	_test_paths.append(path)
	return path

func _snapshot(keys: RefCounted) -> Dictionary:
	var result := {}
	for action: String in KeyBindings.ACTIONS:
		result[action] = [keys.get_key(action, 0), keys.get_key(action, 1)]
	return result

func _tap(key: int) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	event = InputEventKey.new()
	event.keycode = key
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _held_key(key: int, pressed: bool, physical: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	if physical:
		event.physical_keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func run() -> void:
	var keys := KeyBindings.new()
	check(_snapshot(keys) == KeyBindings.DEFAULTS, "new settings hold default keys")
	var ui_actions := {}
	for action in InputMap.get_actions():
		if str(action).begins_with("ui_"):
			var events: Array[String] = []
			for event in InputMap.action_get_events(action):
				events.append(event.as_text())
			ui_actions[action] = events
	keys.apply()
	for action in ui_actions:
		var events: Array[String] = []
		for event in InputMap.action_get_events(action):
			events.append(event.as_text())
		check(events == ui_actions[action], "built-in UI mapping preserved: %s" % action)
	for action: String in KeyBindings.ACTIONS:
		check(not keys.get_binding_text(action).is_empty(), "readable binding: %s" % action)
		var input_events := InputMap.action_get_events(action)
		check(input_events.any(func(event): return event is InputEventKey and event.physical_keycode == keys.get_key(action, 0)), "physical key registered: %s" % action)
		check(input_events.any(func(event): return event is InputEventKey and event.keycode == keys.get_key(action, 0) and event.physical_keycode == 0), "logical key registered: %s" % action)
	check(not keys.try_bind("jump", 1, KEY_Z).is_empty(), "different-action duplicate rejected")
	check(not keys.try_bind("move_left", 1, KEY_A).is_empty(), "same-action duplicate rejected")
	check(not keys.try_bind("jump", 0, KEY_NONE).is_empty(), "last key cannot be removed")
	check(not keys.try_bind("jump", 1, KEY_ESCAPE).is_empty(), "Esc reserved for pause")
	check(not keys.try_bind("jump", 1, KEY_META).is_empty(), "Meta key rejected")
	check(not keys.try_bind("jump", 1, KEY_A | KEY_MASK_SHIFT).is_empty(), "modifier combinations rejected")
	check(not keys.try_bind("unknown", 0, KEY_Q).is_empty(), "unknown action rejected")
	check(not keys.try_bind("jump", 2, KEY_Q).is_empty(), "invalid slot rejected")
	check(keys.try_bind("jump", 1, KEY_SHIFT).is_empty(), "standalone Shift accepted")
	check(keys.try_bind("jump", 1, KEY_Q).is_empty(), "second slot can be changed")
	check(keys.try_bind("jump", 0, KEY_NONE).is_empty(), "first slot can be removed when second remains")
	check(keys.get_key("jump", 0) == KEY_NONE and keys.get_key("jump", 1) == KEY_Q, "slot placement retained")
	check(keys.try_bind("jump", 0, KEY_SPACE).is_empty(), "empty first slot can be restored")
	check(keys.try_bind("jump", 1, KEY_NONE).is_empty(), "second slot can be removed")
	keys.try_bind("jump", 1, KEY_Q)
	var saved := _snapshot(keys)
	var path := _new_path()
	check(keys.save_settings(path) == OK, "settings save succeeds")
	var reloaded := KeyBindings.new()
	reloaded.load_settings(path)
	check(_snapshot(reloaded) == saved, "saved settings round-trip")
	for physical in [false, true]:
		Input.action_release("jump")
		_held_key(KEY_SPACE, true, physical)
		check(Input.is_action_pressed("jump"), "first jump key holds action (physical=%s)" % physical)
		_held_key(KEY_Q, true, physical)
		check(Input.is_action_pressed("jump"), "both jump keys hold action (physical=%s)" % physical)
		_held_key(KEY_SPACE, false, physical)
		var still_held := Input.is_action_pressed("jump")
		print("MULTIKEY RELEASE: physical=", physical, "; Space released while Q held; jump pressed=", still_held)
		check(still_held, "releasing first jump key preserves held second key (physical=%s)" % physical)
		_held_key(KEY_Q, false, physical)
		check(not Input.is_action_pressed("jump"), "releasing both jump keys releases action (physical=%s)" % physical)
	# Version 1 files predate interaction. New defaults must not erase old custom
	# controls just because the player's preferred shooting key happened to be E.
	var legacy := ConfigFile.new()
	legacy.set_value("controls", "version", 1)
	for action: String in KeyBindings.ACTIONS:
		if action != "interact":
			legacy.set_value("bindings", action, KeyBindings.DEFAULTS[action].duplicate())
	path = _new_path()
	legacy.save(path)
	reloaded.load_settings(path)
	check(reloaded.get_key("interact", 0) == KEY_E, "legacy file gets default interaction key when free")
	legacy.set_value("bindings", "shoot", [KEY_E, KEY_NONE])
	legacy.set_value("bindings", "pause_game", [KEY_P, KEY_NONE])
	legacy.save(path)
	reloaded.load_settings(path)
	check(reloaded.get_key("interact", 0) == KEY_F, "legacy E collision gives new interaction an unused nearby key")
	for action: String in KeyBindings.ACTIONS:
		if action != "interact":
			check([reloaded.get_key(action, 0), reloaded.get_key(action, 1)] == legacy.get_value("bindings", action), "legacy custom binding survives migration: %s" % action)
	check(reloaded.get_key("pause_game", 0) == KEY_P, "legacy custom pause key survives migration")
	var migrated := _snapshot(reloaded)
	check(reloaded.save_settings(path) == OK, "migrated bindings can be saved")
	var upgraded := ConfigFile.new()
	upgraded.load(path)
	check(upgraded.get_value("controls", "version") == 2, "saved migration writes current controls version")
	reloaded.load_settings(path)
	check(_snapshot(reloaded) == migrated, "migrated interaction and old bindings survive reload")
	# Exhaust all preferred migration keys and verify that a later free key is
	# selected without dropping any of the two-slot bindings.
	legacy.set_value("bindings", "jump", [KEY_F, KEY_R])
	legacy.set_value("bindings", "special", [KEY_V, KEY_NONE])
	legacy.save(path)
	reloaded.load_settings(path)
	check(reloaded.get_key("interact", 0) == KEY_B, "migration finds a free letter after E F R V are occupied")
	for action: String in KeyBindings.ACTIONS:
		if action != "interact":
			check([reloaded.get_key(action, 0), reloaded.get_key(action, 1)] == legacy.get_value("bindings", action), "crowded legacy binding survives migration: %s" % action)
	_held_key(KEY_B, true, true)
	check(Input.is_action_pressed("interact"), "migrated interaction key registers in InputMap")
	_held_key(KEY_B, false, true)
	check(not Input.is_action_pressed("interact"), "migrated interaction releases correctly")
	var partial := ConfigFile.new()
	partial.set_value("bindings", "jump", [KEY_Q, KEY_NONE])
	partial.set_value("bindings", "shoot", "broken")
	partial.set_value("bindings", "special", [KEY_NONE, KEY_NONE])
	partial.set_value("bindings", "switch_color", [KEY_META, KEY_NONE])
	path = _new_path()
	partial.save(path)
	reloaded.load_settings(path)
	check(reloaded.get_key("jump", 0) == KEY_Q, "valid row retained beside corrupted settings")
	check(reloaded.get_key("shoot", 0) == KEY_Z, "invalid row falls back to default")
	check(reloaded.get_key("special", 0) == KEY_C, "empty row falls back to playable default")
	check(reloaded.get_key("switch_color", 0) == KEY_X, "unsafe key falls back to default")
	check(reloaded.get_key("move_left", 0) == KEY_A, "missing row falls back to default")
	partial.set_value("bindings", "move_right", [KEY_A, KEY_NONE])
	partial.save(path)
	reloaded.load_settings(path)
	check(_snapshot(reloaded) == KeyBindings.DEFAULTS, "conflicting file recovers to safe defaults")
	reloaded.try_bind("jump", 1, KEY_Q)
	reloaded.load_settings(_new_path())
	check(_snapshot(reloaded) == KeyBindings.DEFAULTS, "missing file recovers to defaults")
	reloaded.try_bind("jump", 1, KEY_Q)
	reloaded.reset_defaults()
	check(_snapshot(reloaded) == KeyBindings.DEFAULTS, "reset restores all defaults")
	# Exercise the actual panel using logical short taps between physics ticks.
	var input_spy := InputSpy.new()
	root.add_child(input_spy)
	var panel := SettingsPanel.new()
	panel.bindings = reloaded
	panel.settings_path = _new_path()
	root.add_child(panel)
	await process_frame
	check(not panel.visible, "settings panel initially hidden")
	panel.open()
	await process_frame
	check(panel.visible and panel.get_rect().end.x <= 1280 and panel.get_rect().end.y <= 720, "settings panel fits 1280 by 720")
	check(panel._buttons.has("interact"), "settings panel includes interaction action")
	check(panel._list_scroll.size.y < panel._list_scroll.get_child(0).size.y, "eight action rows scroll inside a fixed-height panel")
	panel._buttons["pause_game"][0].grab_focus()
	await process_frame
	await process_frame
	var pause_button: Button = panel._buttons["pause_game"][0]
	var scroll_rect: Rect2 = panel._list_scroll.get_global_rect()
	check(pause_button.get_global_rect().position.y >= scroll_rect.position.y and pause_button.get_global_rect().end.y <= scroll_rect.end.y, "keyboard focus scrolls the final action into view")
	panel._focus_controls[0].grab_focus()
	await process_frame
	_tap(KEY_ENTER)
	check(panel._waiting_action == "move_left" and panel._waiting_slot == 0, "Enter selects focused key slot")
	_tap(KEY_ESCAPE)
	check(panel._waiting_action.is_empty() and reloaded.get_key("move_left", 0) == KEY_A, "Esc cancels a waiting binding")
	panel._begin_wait("jump", 1)
	_tap(KEY_Q)
	check(reloaded.get_key("jump", 1) == KEY_Q and panel._waiting_action.is_empty(), "panel assigns a short logical-key tap")
	var panel_saved := KeyBindings.new()
	panel_saved.load_settings(panel.settings_path)
	check(panel_saved.get_key("jump", 1) == KEY_Q, "panel saves each successful binding change")
	panel._begin_wait("jump", 1)
	_tap(KEY_BACKSPACE)
	check(reloaded.get_key("jump", 1) == KEY_NONE, "panel deletes a selected slot")
	panel._begin_wait("jump", 0)
	_tap(KEY_BACKSPACE)
	check(reloaded.get_key("jump", 0) == KEY_SPACE and not panel._status.text.is_empty(), "panel explains why final key cannot be deleted")
	_tap(KEY_ESCAPE)
	check(input_spy.unhandled_keys == 0, "visible panel consumes key presses and releases before gameplay")
	panel.bindings = SaveFailure.new()
	panel._assign("jump", 1, KEY_Q)
	check(panel.bindings.get_key("jump", 1) == KEY_Q and panel._status.text.contains("保存できません"), "save failure keeps live change and displays an explanation")
	panel.bindings = reloaded
	panel._reset()
	panel_saved.load_settings(panel.settings_path)
	check(_snapshot(panel_saved) == KeyBindings.DEFAULTS, "panel reset saves defaults")
	var close_count := [0]
	panel.closed.connect(func(): close_count[0] += 1)
	_tap(KEY_ESCAPE)
	check(not panel.visible and close_count[0] == 1, "Esc closes panel and emits closed once")
	_tap(KEY_Q)
	check(input_spy.unhandled_keys > 0, "hidden panel no longer intercepts keys")
	panel.queue_free()
	input_spy.queue_free()
	await process_frame
	# Temporary files include panel saves; the player's actual settings stay intact.
	for test_path in _test_paths:
		if FileAccess.file_exists(test_path):
			DirAccess.remove_absolute(test_path)
	print("KEY BINDINGS TEST: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
