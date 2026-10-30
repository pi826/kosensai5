extends RefCounted
const DEFAULTS := {"master": 80, "bgm": 60, "se": 80}
var values := DEFAULTS.duplicate()

func load_settings(path: String) -> void:
	values = DEFAULTS.duplicate()
	var config := ConfigFile.new()
	if config.load(path) != OK or config.get_value("audio", "version", 0) != 1: return
	for key: String in DEFAULTS:
		var value: Variant = config.get_value("audio", key, DEFAULTS[key])
		if (value is int or value is float) and is_finite(float(value)):
			values[key] = clampi(roundi(float(value) / 10.0) * 10, 0, 100)

func save_settings(path: String) -> Error:
	var config := ConfigFile.new()
	config.set_value("audio", "version", 1)
	for key: String in values: config.set_value("audio", key, values[key])
	return config.save(path)

func apply() -> void:
	for key: String in values:
		var bus := AudioServer.get_bus_index({"master": "Master", "bgm": "BGM", "se": "SE"}[key])
		if bus < 0: continue
		AudioServer.set_bus_mute(bus, values[key] == 0)
		AudioServer.set_bus_volume_db(bus, db_for(values[key]))

static func db_for(value: int) -> float:
	return linear_to_db(pow(maxi(1, value) / 100.0, 2)) if value > 0 else -80.0
