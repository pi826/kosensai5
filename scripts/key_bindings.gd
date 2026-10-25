extends RefCounted
## Keyboard bindings are independent of the built-in UI actions.

const ACTIONS := {
	"move_left": "左へ移動",
	"move_right": "右へ移動",
	"jump": "ジャンプ",
	"move_down": "下へ降りる",
	"shoot": "通常射撃",
	"switch_color": "色を切り替え",
	"aim_cycle": "射撃角度を切り替え",
	"special": "誘導弾",
	"interact": "調べる",
	"pause_game": "一時停止",
}
const DEFAULTS := {
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"jump": [KEY_SPACE, KEY_W],
	"move_down": [KEY_S, KEY_DOWN],
	"shoot": [KEY_J, KEY_NONE],
	"switch_color": [KEY_K, KEY_NONE],
	"aim_cycle": [KEY_L, KEY_NONE],
	"special": [KEY_SEMICOLON, KEY_NONE],
	"interact": [KEY_E, KEY_NONE],
	"pause_game": [KEY_ESCAPE, KEY_NONE],
}

var _bindings: Dictionary = DEFAULTS.duplicate(true)

func load_settings(path: String = "user://controls.cfg") -> void:
	var config := ConfigFile.new()
	_bindings = DEFAULTS.duplicate(true)
	if config.load(path) == OK and config.get_value("controls", "version", 0) == 3:
		for action: String in ACTIONS:
			if not config.has_section_key("bindings", action):
				continue
			var stored: Variant = config.get_value("bindings", action)
			# Recover a damaged or missing action without discarding other valid rows.
			if _valid_pair(action, stored):
				_bindings[action] = [int(stored[0]), int(stored[1])]
		# A damaged row can restore a default key already used by another row.
		# In that case the complete default set is the safe, conflict-free recovery.
		if not _has_unique_keys():
			_bindings = DEFAULTS.duplicate(true)
	apply()

func apply() -> void:
	for action: String in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		for key: int in _bindings[action]:
			if key == KEY_NONE:
				continue
			var physical := InputEventKey.new()
			physical.physical_keycode = key
			InputMap.action_add_event(action, physical)
			# Logical-only events also support IME layouts and synthetic short taps.
			var logical := InputEventKey.new()
			logical.keycode = key
			InputMap.action_add_event(action, logical)

func get_key(action: String, slot: int) -> int:
	if not ACTIONS.has(action) or slot < 0 or slot > 1:
		return KEY_NONE
	return int(_bindings[action][slot])

func get_binding_text(action: String) -> String:
	if not ACTIONS.has(action):
		return "未設定"
	var names := PackedStringArray()
	for slot in range(2):
		var key := get_key(action, slot)
		if key != KEY_NONE:
			names.append(key_text(key))
	return " / ".join(names) if not names.is_empty() else "未設定"

static func key_text(key: int) -> String:
	match key:
		KEY_NONE: return "未設定"
		KEY_SPACE: return "Space"
		KEY_ESCAPE: return "Esc"
		KEY_LEFT: return "←"
		KEY_RIGHT: return "→"
		KEY_UP: return "↑"
		KEY_DOWN: return "↓"
		KEY_SEMICOLON: return ";"
		_: return OS.get_keycode_string(key)

func try_bind(action: String, slot: int, key: int) -> String:
	if not ACTIONS.has(action) or slot < 0 or slot > 1:
		return "変更する操作を選んでください。"
	var reason := _key_error(action, key)
	if not reason.is_empty():
		return reason
	if key == get_key(action, slot):
		return ""
	if key == KEY_NONE:
		if get_key(action, 1 - slot) == KEY_NONE:
			return "操作には少なくとも1つのキーが必要です。"
	else:
		for other_action: String in ACTIONS:
			for other_slot in range(2):
				if get_key(other_action, other_slot) != key:
					continue
				if other_action == action:
					return "同じ操作の2つの欄には、別のキーを指定してください。"
				return "%s は「%s」で使用中です。先にその割り当てを変更してください。" % [key_text(key), ACTIONS[other_action]]
	_bindings[action][slot] = key
	apply()
	return ""

func reset_defaults() -> void:
	_bindings = DEFAULTS.duplicate(true)
	apply()

func save_settings(path: String = "user://controls.cfg") -> Error:
	var config := ConfigFile.new()
	config.set_value("controls", "version", 3)
	for action: String in ACTIONS:
		config.set_value("bindings", action, _bindings[action].duplicate())
	return config.save(path)

func _valid_pair(action: String, value: Variant) -> bool:
	if not value is Array or value.size() != 2:
		return false
	for item: Variant in value:
		if typeof(item) != TYPE_INT or not _key_error(action, int(item)).is_empty():
			return false
	if value[0] == KEY_NONE and value[1] == KEY_NONE:
		return false
	return value[0] == KEY_NONE or value[0] != value[1]

func _key_error(action: String, key: int) -> String:
	if key == KEY_NONE:
		return ""
	if key == KEY_META:
		return "Windows / Meta キーは割り当てできません。"
	if key == KEY_ESCAPE and action != "pause_game":
		return "Esc は設定の取消に使うため、一時停止にだけ割り当てできます。"
	if key < 0 or key != (key & KEY_CODE_MASK) or OS.get_keycode_string(key).is_empty():
		return "このキーは割り当てできません。"
	return ""

func _has_unique_keys() -> bool:
	var used := {}
	for action: String in ACTIONS:
		for key: int in _bindings[action]:
			if key == KEY_NONE:
				continue
			if used.has(key):
				return false
			used[key] = true
	return true
