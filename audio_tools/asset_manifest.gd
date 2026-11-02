extends RefCounted
## Keep each replacement editable on one line, especially the five music slots.
static func table(value: Dictionary) -> String:
	var result := "{\n"
	for key: String in value:
		result += "\t"+JSON.stringify(key)+": "+JSON.stringify(value[key])+",\n"
	return result+"}"

static func write(effects: Dictionary, music: Dictionary, hashes: Dictionary) -> void:
	var code := 'extends RefCounted\n## One row per replacement. Pitch is baked; gain remains adjustable.\nconst EFFECTS := '+table(effects)+'\nconst MUSIC := '+table(music)+'\nconst SYNTH_EFFECTS := ["amb0_drop", "amb0_ripple", "amb1_chime", "amb1_ring", "amb2_ember", "amb2_metal"]\nconst SYNTH_MUSIC := []\nconst SHA256 := '+table(hashes)+'\n'
	FileAccess.open("res://scripts/sound_assets.gd", FileAccess.WRITE).store_string(code)
