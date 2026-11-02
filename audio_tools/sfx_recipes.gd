extends RefCounted
const H := ["boss_defeat", "boss_appear", "bomb_explode", "enhancer_defeat", "death", "hurt"]
const M := ["enemy_defeat", "block_break", "boss_hit", "laser_fire", "chest_open", "key", "item_get", "ability_get", "arrow_unlock", "charge"]
const QUIET := ["enemy_shot", "enemy_warn", "enemy_warn_special", "bomb_warn", "enemy_switch", "enemy_absorb", "enemy_homing", "boss_shot", "laser_charge"]
const UI := ["aim", "empty", "chest_locked", "deny", "shop_open", "buy", "equip", "pause", "map_open", "map_close", "ui_move", "ui_confirm", "ui_back"]

static func all() -> Dictionary:
	var result := {}
	for id: String in BASE.keys() + ["win", "lose"]:
		var old: Dictionary = BASE.get(id, {})
		var seconds := 0.45
		var layers: Array = []
		if REVISED.has(id):
			seconds = REVISED[id].seconds
			layers = REVISED[id].layers.duplicate(true)
		elif id == "hurt":
			# Retain the reviewed metal/body/downward-sub recipe.
			seconds = 0.42
			layers = [
				{"source":"impactMetal.ogg","gain":0.6,"hp":180.0},
				{"source":"bang.ogg","gain":0.5,"pitch":1.6,"lp":1800.0},
				{"synth":"sub","gain":1.4,"frequency":120.0,"end":38.0,"duration":0.42},
				{"synth":"noise","gain":0.25,"duration":0.42,"lp":2700.0,"echo":0.075},
				{"source":"impactPlate.ogg","gain":0.3,"pitch":0.72,"delay":0.012}]
		elif UI.has(id) or QUIET.has(id):
			layers = [{"source":old.source,"pitch":old.pitch,"gain":0.8}]
		elif id in ["heal", "potion"]:
			seconds = 1.5 if id == "potion" else 1.35
			layers = [
				{"source":"Cure2.wav" if id == "potion" else "Cure1.wav","gain":0.22,"hp":350.0},
				{"synth":"arp","frequency":523.25,"gain":0.65,"duration":0.85,"echo":0.16},
				{"synth":"bell","frequency":2093.0,"gain":0.12,"delay":0.3,"duration":0.55,"echo":0.19}]
			if id == "potion": layers.append({"source":"bottle.ogg","gain":0.35,"hp":1800.0,"pitch":1.5})
		elif id in ["win", "lose"]:
			seconds = 3.5 if id == "win" else 2.5
			layers = [
				{"synth":id,"gain":0.8},
				{"synth":"bell","frequency":660.0,"gain":0.24,"duration":0.45*0.65,"echo":0.035},
				{"synth":"arp","gain":0.22,"frequency":588.0 if id == "win" else 440.0,"duration":1.8,"echo":0.15,"descending":id == "lose"}]
		else:
			layers = [{"source":old.source,"pitch":old.pitch,"gain":0.55}]
			if id in ["crystal", "tutorial_step"]:
				layers.append({"synth":"bell","frequency":660.0,"gain":0.24,"duration":0.45*0.65,"echo":0.035})
			else:
				layers.append({"synth":"noise","gain":0.08,"duration":0.055,"hp":1800.0,"lp":6500.0})
		var target := -17.0
		if H.has(id): target = -6.8
		elif M.has(id): target = -10.5
		elif id in ["heal", "potion"]: target = -13.0
		if id == "death": target = -5.1
		if id == "boss_defeat": target = -4.7
		result[id] = {"seconds":seconds,"layers":layers,"target_k":target}
	return result
const REVISED := {
	"boss_defeat": {"seconds":2.6,"layers":[
		{"source":"sfx_exp_cluster9.wav","gain":1.1},
		{"source":"cannon.ogg","gain":0.8,"pitch":0.8},
		{"synth":"sub","gain":1.0,"frequency":126.0,"end":36.0,"duration":0.75,"sweep":0.24},
		{"source":"cannon_03.ogg","gain":0.7,"pitch":0.7,"delay":0.25},
		{"source":"sfx_exp_cluster9.wav","gain":0.65,"pitch":0.65,"delay":0.55},
		{"synth":"noise","gain":0.4,"duration":2.6,"lp":2100.0,"echo":0.13}]},
	"boss_appear": {"seconds":2.2,"layers":[
		{"source":"sfx_movement_portal2.wav","gain":0.9,"pitch":0.8},
		{"synth":"sub","gain":1.1,"frequency":32.0,"end":95.0,"duration":1.9,"sweep":1.9,"attack":0.04,"envelope_power":0.5},
		{"synth":"noise","gain":0.45,"duration":1.8,"attack":1.65,"hp":140.0,"lp":3300.0,"envelope_power":0.2},
		{"source":"impactSoft_heavy_000.ogg","gain":1.8,"pitch":0.65,"delay":1.65}]},
	"bomb_explode": {"seconds":0.62,"layers":[
		{"source":"sfx_exp_short_hard10.wav","gain":1.2},
		{"source":"bang_07.ogg","gain":0.8,"pitch":1.2},
		{"synth":"sub","gain":1.9,"frequency":170.0,"end":60.0,"duration":0.24,"sweep":0.07},
		{"synth":"noise","gain":0.35,"duration":0.23,"hp":700.0,"lp":7000.0}]},
	"enhancer_defeat": {"seconds":0.95,"layers":[
		{"source":"sfx_exp_short_hard1.wav","gain":0.85},
		{"source":"impactGlass_heavy_003.ogg","gain":1.5,"pitch":1.4},
		{"source":"impactGlass_light_000.ogg","gain":0.7,"pitch":1.7,"delay":0.075,"echo":0.085},
		{"synth":"bell","gain":0.13,"frequency":2800.0,"duration":0.65,"delay":0.025,"echo":0.11},
		{"synth":"sub","gain":1.1,"frequency":84.0,"end":48.0,"duration":0.24,"sweep":0.15}]},
	"death": {"seconds":1.6,"layers":[
		{"source":"sfx_deathscream_robot2.wav","gain":0.8,"pitch":1.15,"pitch_end":0.28,"pitch_seconds":1.4,"gate_hz":13.0,"gate_after":0.35},
		{"synth":"sweep","gain":0.32,"frequency":1100.0,"end":70.0,"duration":1.45,"gate_hz":11.0,"gate_after":0.35},
		{"source":"impactPlate_heavy_003.ogg","gain":0.7,"pitch":0.65},
		{"synth":"sub","gain":2.3,"frequency":69.0,"end":30.0,"duration":0.9,"sweep":0.55,"envelope_power":0.5}]},
	"enemy_defeat": {"seconds":0.64,"layers":[
		{"source":"sfx_exp_shortest_hard2.wav","gain":1.2},
		{"source":"bang.ogg","gain":0.7,"pitch":1.8},
		{"synth":"sub","gain":0.65,"frequency":145.0,"end":47.0,"duration":0.27,"sweep":0.12},
		{"synth":"noise","gain":0.35,"duration":0.32,"hp":350.0,"lp":4200.0}]},
	"block_break": {"seconds":0.85,"layers":[
		{"source":"sfx_exp_shortest_hard5.wav","gain":0.8},
		{"source":"impactMining_000.ogg","gain":1.8,"pitch":1.1},
		{"synth":"sub","gain":0.65,"frequency":76.0,"end":39.0,"duration":0.2,"sweep":0.18},
		{"synth":"noise","gain":0.5,"duration":0.65,"lp":3800.0,"hp":350.0,"gate_hz":21.0}]},
	"boss_hit": {"seconds":0.48,"layers":[
		{"source":"sfx_sounds_impact8.wav","gain":0.8},
		{"source":"impactMetal_heavy_003.ogg","gain":1.7,"pitch":1.2},
		{"source":"impactPlate_heavy_003.ogg","gain":0.7,"pitch":1.6,"delay":0.016},
		{"synth":"sub","gain":0.6,"frequency":100.0,"end":62.0,"duration":0.16,"sweep":0.09}]},
	"laser_fire": {"seconds":0.8,"layers":[
		{"source":"sfx_wpn_laser12.wav","gain":0.9},
		{"source":"cannon_03.ogg","gain":0.5,"pitch":1.8,"hp":1800.0},
		{"synth":"noise","gain":0.55,"duration":0.7,"hp":2200.0,"lp":10000.0},
		{"synth":"sub","gain":0.3,"frequency":180.0,"end":45.0,"duration":0.12,"sweep":0.09}]},
	"chest_open": {"seconds":0.85,"layers":[
		{"source":"sfx_sounds_interaction10.wav","gain":0.8},
		{"source":"impactPunch_medium_003.ogg","gain":0.5,"pitch":1.7},
		{"synth":"arp","gain":0.25,"frequency":392.0,"ratios":[1.0,1.5,2.0],"note_seconds":0.16,"duration":0.48,"delay":0.12,"echo":0.08}]},
	"key": {"seconds":0.42,"layers":[
		{"source":"sfx_sounds_powerup10.wav","gain":0.7,"duration":0.32},
		{"synth":"arp","gain":0.35,"frequency":1174.66,"ratios":[1.0,1.5],"note_seconds":0.11,"duration":0.22},
		{"synth":"noise","gain":0.04,"duration":0.018,"hp":4000.0}]},
	"item_get": {"seconds":0.75,"layers":[
		{"source":"sfx_sounds_powerup12.wav","gain":0.7},
		{"synth":"arp","gain":0.32,"frequency":783.99,"ratios":[1.0,1.333333,2.0],"note_seconds":0.12,"duration":0.5,"echo":0.09},
		{"synth":"bell","gain":0.08,"frequency":3135.96,"delay":0.23,"duration":0.4}]},
	"ability_get": {"seconds":1.2,"layers":[
		{"source":"sfx_sounds_powerup1.wav","gain":0.8},
		{"synth":"arp","gain":0.4,"frequency":587.33,"ratios":[1.0,1.25,1.5,2.0,2.5,3.0],"note_seconds":0.13,"duration":1.0,"echo":0.14},
		{"synth":"bell","gain":0.18,"frequency":2349.32,"duration":0.8,"delay":0.32,"echo":0.16},
		{"synth":"bell","gain":0.12,"frequency":3523.98,"duration":0.65,"delay":0.52,"echo":0.12}]},
	"arrow_unlock": {"seconds":0.9,"layers":[
		{"source":"sfx_sounds_powerup7.wav","gain":0.8},
		{"synth":"arp","gain":0.3,"frequency":880.0,"ratios":[1.0,1.5,1.25,2.0],"note_seconds":0.15,"duration":0.65,"echo":0.1},
		{"synth":"noise","gain":0.05,"duration":0.18,"hp":4500.0,"delay":0.3}]},
	"charge": {"seconds":0.7,"layers":[
		{"source":"sfx_sounds_powerup8.wav","gain":0.7},
		{"synth":"sweep","gain":0.23,"frequency":420.0,"end":1900.0,"duration":0.55},
		{"synth":"noise","gain":0.13,"duration":0.45,"attack":0.15,"hp":2200.0}]},
	"land": {"seconds":0.22,"layers":[
		{"source":"sfx_movement_jump12_landing.wav","gain":1.0},
		{"source":"impactPunch_medium_003.ogg","gain":0.8,"pitch":1.7},
		{"synth":"sweep","gain":0.65,"frequency":155.0,"end":48.0,"duration":0.15}]},
	"jump": {"seconds":0.24,"layers":[
		{"source":"sfx_movement_jump1.wav","gain":1.0},
		{"synth":"noise","gain":0.16,"duration":0.19,"attack":0.03,"hp":1200.0,"lp":8000.0,"rise_filter":true}]},
	"air_jump": {"seconds":0.27,"layers":[
		{"source":"sfx_movement_jump10.wav","gain":1.0},
		{"synth":"noise","gain":0.2,"duration":0.22,"attack":0.04,"hp":1800.0,"lp":10000.0,"rise_filter":true}]},
	"dash": {"seconds":0.32,"layers":[
		{"source":"sfx_wpn_sword1.wav","gain":1.0},
		{"synth":"noise","gain":0.4,"duration":0.29,"attack":0.008,"hp":1300.0,"lp":8500.0}]},
	"glide": {"seconds":0.4,"layers":[
		{"source":"sfx_wpn_sword3.wav","gain":1.0,"pitch":0.85},
		{"synth":"noise","gain":0.3,"duration":0.37,"attack":0.05,"hp":900.0,"lp":5500.0}]},
	"shot_a": {"seconds":0.18,"layers":[
		{"source":"sfx_wpn_laser2.wav","gain":1.0,"pitch":1.0},
		{"synth":"noise","gain":0.28,"duration":0.012,"hp":4000.0,"lp":14000.0},
		{"synth":"sweep","gain":0.17,"frequency":1450.0,"end":480.0,"duration":0.085}]},
	"shot_b": {"seconds":0.22,"layers":[
		{"source":"sfx_wpn_laser2.wav","gain":1.0,"pitch":0.75},
		{"synth":"noise","gain":0.18,"duration":0.016,"hp":2300.0,"lp":7000.0},
		{"synth":"sweep","gain":0.32,"frequency":330.0,"end":130.0,"duration":0.12}]},
	"homing": {"seconds":0.32,"layers":[
		{"source":"sfx_wpn_laser6.wav","gain":1.0},
		{"synth":"sweep","gain":0.22,"frequency":1800.0,"end":230.0,"duration":0.22}]},
}
## Baseline source/pitch/gain retained for objective 8C comparisons.
const BASE := {
	"shot_a": {"source": "sfx_wpn_laser2.wav", "pitch": 1, "gain_db": -21.55264381},
	"shot_b": {"source": "sfx_wpn_laser2.wav", "pitch": 0.75, "gain_db": -19.73345632},
	"aim": {"source": "sfx_menu_move4.wav", "pitch": 1, "gain_db": -17.00464276},
	"jump": {"source": "sfx_movement_jump1.wav", "pitch": 1, "gain_db": -16.74152324},
	"air_jump": {"source": "sfx_movement_jump10.wav", "pitch": 1, "gain_db": -4.59199316},
	"land": {"source": "sfx_movement_jump12_landing.wav", "pitch": 1, "gain_db": -5.89107488},
	"dash": {"source": "sfx_wpn_sword1.wav", "pitch": 1, "gain_db": -16.25885727},
	"glide": {"source": "sfx_wpn_sword3.wav", "pitch": 0.85, "gain_db": -13.68390330},
	"homing": {"source": "sfx_wpn_laser6.wav", "pitch": 1, "gain_db": -9.95339501},
	"empty": {"source": "sfx_wpn_noammo3.wav", "pitch": 1, "gain_db": -11.61639836},
	"switch_a": {"source": "sfx_sounds_interaction14.wav", "pitch": 1.26, "gain_db": -9.39476070},
	"switch_b": {"source": "sfx_sounds_interaction14.wav", "pitch": 0.84, "gain_db": -8.65629907},
	"absorb_a": {"source": "sfx_coin_double4.wav", "pitch": 1, "gain_db": -5.78002970},
	"absorb_b": {"source": "sfx_coin_double4.wav", "pitch": 0.67, "gain_db": -4.86439700},
	"hurt": {"source": "sfx_sounds_damage3.wav", "pitch": 1, "gain_db": -0.65439310},
	"death": {"source": "sfx_deathscream_robot2.wav", "pitch": 1, "gain_db": -0.44117875},
	"heal": {"source": "sfx_sounds_powerup13.wav", "pitch": 1, "gain_db": -7.87423188},
	"potion": {"source": "sfx_sounds_powerup15.wav", "pitch": 1, "gain_db": -13.10757837},
	"charge": {"source": "sfx_sounds_powerup8.wav", "pitch": 1, "gain_db": -4.97092757},
	"crystal": {"source": "sfx_coin_single3.wav", "pitch": 1, "gain_db": -11.35113000},
	"key": {"source": "sfx_sounds_powerup10.wav", "pitch": 1, "gain_db": -5.20768941},
	"item_get": {"source": "sfx_sounds_powerup12.wav", "pitch": 1, "gain_db": -7.80302180},
	"ability_get": {"source": "sfx_sounds_powerup1.wav", "pitch": 1, "gain_db": -8.26989251},
	"arrow_unlock": {"source": "sfx_sounds_powerup7.wav", "pitch": 1, "gain_db": -9.33792797},
	"chest_open": {"source": "sfx_sounds_interaction10.wav", "pitch": 1, "gain_db": -5.12664764},
	"chest_locked": {"source": "sfx_sounds_error15.wav", "pitch": 1, "gain_db": -16.97860551},
	"deny": {"source": "sfx_sounds_error3.wav", "pitch": 1, "gain_db": -10.51735478},
	"buy": {"source": "sfx_coin_double2.wav", "pitch": 1, "gain_db": -10.32853123},
	"equip": {"source": "sfx_menu_select2.wav", "pitch": 1, "gain_db": -14.24645711},
	"shop_open": {"source": "sfx_sounds_pause7_in.wav", "pitch": 1, "gain_db": -11.46242573},
	"pause": {"source": "sfx_sounds_pause2_in.wav", "pitch": 1, "gain_db": -10.92197737},
	"map_open": {"source": "sfx_sounds_pause6_in.wav", "pitch": 1, "gain_db": -8.73236940},
	"map_close": {"source": "sfx_sounds_pause6_out.wav", "pitch": 1, "gain_db": -9.58370234},
	"ui_move": {"source": "sfx_menu_move2.wav", "pitch": 1, "gain_db": -16.55776844},
	"ui_confirm": {"source": "sfx_menu_select5.wav", "pitch": 1, "gain_db": -17.23656731},
	"ui_back": {"source": "sfx_sounds_Blip9.wav", "pitch": 1, "gain_db": -18.02341483},
	"tutorial_step": {"source": "sfx_sounds_fanfare3.wav", "pitch": 1, "gain_db": -3.55087041},
	"enemy_shot": {"source": "sfx_weapon_singleshot14.wav", "pitch": 1, "gain_db": -26.21962454},
	"enemy_hit": {"source": "sfx_damage_hit1.wav", "pitch": 1, "gain_db": -14.04642728},
	"enemy_defeat": {"source": "sfx_exp_shortest_hard2.wav", "pitch": 1, "gain_db": -9.55918412},
	"boss_hit": {"source": "sfx_sounds_impact8.wav", "pitch": 1, "gain_db": -11.17521095},
	"boss_defeat": {"source": "sfx_exp_cluster9.wav", "pitch": 1, "gain_db": -0.85300943},
	"enhancer_defeat": {"source": "sfx_exp_short_hard1.wav", "pitch": 1, "gain_db": 0.12554939},
	"block_break": {"source": "sfx_exp_shortest_hard5.wav", "pitch": 1, "gain_db": -9.03416216},
	"bomb_explode": {"source": "sfx_exp_short_hard10.wav", "pitch": 1, "gain_db": -3.02907159},
	"bomb_warn": {"source": "sfx_wpn_grenadewhistle1.wav", "pitch": 1, "gain_db": -20.34177361},
	"enemy_warn": {"source": "sfx_sounds_Blip11.wav", "pitch": 1, "gain_db": -23.99474508},
	"enemy_warn_special": {"source": "sfx_lowhealth_alarmloop6.wav", "pitch": 1, "gain_db": -11.38742336},
	"enemy_homing": {"source": "sfx_wpn_missilelaunch.wav", "pitch": 1, "gain_db": -17.40339379},
	"enemy_absorb": {"source": "sfx_sounds_interaction9.wav", "pitch": 1, "gain_db": -15.55023897},
	"enemy_switch": {"source": "sfx_sounds_Blip6.wav", "pitch": 1, "gain_db": -19.80250353},
	"boss_shot": {"source": "sfx_weapon_singleshot21.wav", "pitch": 1, "gain_db": -13.70151408},
	"laser_charge": {"source": "sfx_sound_poweron.wav", "pitch": 1, "gain_db": -13.75787912},
	"laser_fire": {"source": "sfx_wpn_laser12.wav", "pitch": 1, "gain_db": -9.85336249},
	"boss_appear": {"source": "sfx_movement_portal2.wav", "pitch": 1, "gain_db": -3.45821048},
	"loop_up": {"source": "sfx_alarm_loop8.wav", "pitch": 1, "gain_db": -12.11439702},
	"wall_place": {"source": "sfx_sounds_impact12.wav", "pitch": 1, "gain_db": -17.36432079},
	"wall_vanish": {"source": "sfx_sounds_high5.wav", "pitch": 1, "gain_db": -24.66939002},
}

## Frozen 8C measurements: same K weighting / 30..120Hz Butterworth meter.
const BASE_K := {
"ability_get": -14.2024102606775,
"absorb_a": -14.4814184752313,
"absorb_b": -14.6181684969511,
"aim": -29.9987651198544,
"air_jump": -20.8751110876002,
"arrow_unlock": -15.5251201924594,
"block_break": -18.3451563634271,
"bomb_explode": -11.9261572845391,
"bomb_warn": -26.4576828641059,
"boss_appear": -9.08721105009286,
"boss_defeat": -9.55165021772304,
"boss_hit": -18.3410810487294,
"boss_shot": -21.900167277223,
"buy": -16.450684227818,
"charge": -12.2914873966543,
"chest_locked": -24.9549514335798,
"chest_open": -13.6617835417674,
"crystal": -21.1541922926883,
"dash": -20.646832219552,
"death": -11.4604839453137,
"deny": -25.2368753430141,
"empty": -28.7502673091482,
"enemy_absorb": -24.6172796928619,
"enemy_defeat": -15.4687598347934,
"enemy_hit": -23.1565245750439,
"enemy_homing": -26.564719183562,
"enemy_shot": -34.5794007059562,
"enemy_switch": -28.1073260833789,
"enemy_warn": -33.5197760661477,
"enemy_warn_special": -24.651755587269,
"enhancer_defeat": -9.13800172124444,
"equip": -20.5293561980798,
"glide": -25.0125863635599,
"heal": -15.0215391493897,
"homing": -19.1701219188819,
"hurt": -14.1013562534624,
"item_get": -15.1980951138429,
"jump": -22.5257699098808,
"key": -13.5537934488765,
"land": -23.4203901342291,
"laser_charge": -22.8069611444961,
"laser_fire": -19.7064984637103,
"loop_up": -18.0664489056619,
"map_close": -24.9953856733502,
"map_open": -22.908891647689,
"pause": -23.5366680722783,
"potion": -20.8357603560977,
"shop_open": -21.0485927261604,
"shot_a": -24.7227472078899,
"shot_b": -23.6608614182356,
"switch_a": -17.5714852577606,
"switch_b": -17.3205752847737,
"tutorial_step": -15.1171201816975,
"ui_back": -25.9599699221314,
"ui_confirm": -21.7332403905703,
"ui_move": -30.1779749366806,
"wall_place": -25.2791790455754,
"wall_vanish": -29.848133421372,
}
const BASE_LOW := {
"ability_get": -44.225439618044,
"absorb_a": -48.1198500716151,
"absorb_b": -42.8960572515263,
"aim": -200,
"air_jump": -30.6701215239072,
"arrow_unlock": -49.8019512146445,
"block_break": -27.2465137119963,
"bomb_explode": -15.2308692823851,
"bomb_warn": -62.4572800651929,
"boss_appear": -29.7872107057824,
"boss_defeat": -17.2865441135055,
"boss_hit": -32.2177689108269,
"boss_shot": -27.0666910337236,
"buy": -65.6789794025738,
"charge": -43.408316445309,
"chest_locked": -48.7405179275745,
"chest_open": -39.5498305313444,
"crystal": -57.1654818895909,
"dash": -52.5260581378977,
"death": -12.3010130746815,
"deny": -36.6558972129799,
"empty": -38.4427405118044,
"enemy_absorb": -40.350943139891,
"enemy_defeat": -36.5704845418503,
"enemy_hit": -38.1208725864431,
"enemy_homing": -44.6322872626403,
"enemy_shot": -200,
"enemy_switch": -50.3061547777603,
"enemy_warn": -49.9029560304025,
"enemy_warn_special": -35.5129845092551,
"enhancer_defeat": -17.7327525291402,
"equip": -51.0154107667734,
"glide": -34.8370085494363,
"heal": -45.340896532859,
"homing": -34.2852495452338,
"hurt": -22.9657721411496,
"item_get": -37.6572373439246,
"jump": -42.332023960952,
"key": -35.6458525514038,
"land": -62.8611461901063,
"laser_charge": -52.2879719795494,
"laser_fire": -31.0986357083338,
"loop_up": -40.4359295041147,
"map_close": -37.6947105654143,
"map_open": -37.6810324935222,
"pause": -38.2522748880971,
"potion": -52.3288709087323,
"shop_open": -40.6073950983184,
"shot_a": -58.1085605405223,
"shot_b": -56.2835794052848,
"switch_a": -37.9889611754634,
"switch_b": -33.7338778274664,
"tutorial_step": -31.2161088981093,
"ui_back": -48.4290811908665,
"ui_confirm": -48.4230937730588,
"ui_move": -58.2105373202871,
"wall_place": -31.9543263692839,
"wall_vanish": -51.4772044792254,
}

const SOURCE_SHA256 := {
"impactGlass_light_000.ogg": "d750cf88097d0c3e69920e6e14496e1444e1a9da01aa4cca8f5ec8cb44c57b4f",
"sfx_exp_cluster9.wav": "43199cb227fb790cf6b8255ea7f17a2c8d135d0440d3b35cb568cc4634be1932",
"cannon_03.ogg": "c3690a013befc16be1432e6fe62422db71c7b606980ddfe62429e864c5caf1d2",
"sfx_exp_short_hard10.wav": "58c1f2568d1f8c3a943498bbedc6eef38e84fdd279ddce33383752868b14eb81",
"sfx_movement_portal2.wav": "b895fd0da24a85fc640ce00f73b9954bb303ff48ebd3d5b7e41e2688e4ef1700",
"impactMining_000.ogg": "36b4ea107222d073c67ca64dde26944975609202d5090b2f2021213c1a7e35cd",
"impactPlate_heavy_003.ogg": "59775f8979a396c8a793b0a1db206d5bdc651eae808d858e9acaee8ebda5bc6d",
"impactPunch_medium_003.ogg": "2d7c719c05999e0532f4384e1018e04cd916db715140bf16dee2dff3f820e908",
"impactSoft_heavy_000.ogg": "49e7ca88743fca974bb8676ea138b751cfd8f9033b5e7af8736c2a215d6edbc1",
"sfx_exp_short_hard1.wav": "c5fdc18752339a39fa8b4819227bdbdd3cf29b92302ed0c81b47946d4c83b089",
"impactGlass_heavy_003.ogg": "aed07b154f24410c17e5262bbef832842fb275d41fe297f721af7501d0e9c23a",
"bang_07.ogg": "a16c416e8715aa937d9009c7337a35a21d85bb087ba866e9eed89c1c7862b4f3",
"sfx_deathscream_robot2.wav": "971b70c67a99fb0311ee3ccec3b87885c977193814c8344b6ca8db036dffa044",
"impactMetal_heavy_003.ogg": "b0f2ba4dabde9a87eb9c188a19d31e0c2300fd321adeba08d3b9b8aa011d7037",
"bang.ogg": "b823f53557ca9702f57b3f9e997fc92d5b87da99d464309d14199aabf2d620c4",
"bottle.ogg": "b44b39a940e8948e74b9bd3776bff980df43cf220abdaf0d467dc4c43c0244a5",
"cannon.ogg": "e87ca0ee6b53da1f21cd9086cb75f456495871618fdfed63388bd2208a872596",
"Cure1.wav": "559cc4826ef19ce466e5c40b7309d1ed9b50656cedda2dab8c9267e04a6a9fb1",
"Cure2.wav": "d3b2f85990def3ade8958f415a4b0e0dc74026a6de894f469838379be6586e2a",
"impactMetal.ogg": "e07045693e4a2b3d165c424e3dab4c781d9ff8880a386880ac89a51315d7f831",
"impactPlate.ogg": "112d4f93ddcc370b410630f971c0f5d991856102da9c76bc5c5540d388e75aaa",
"sfx_alarm_loop8.wav": "7a3420e9d7fb20b175560da61c5c82582fbac10c7b270b62c62b841e92bb66fb",
"sfx_coin_double2.wav": "6ea3335e38d23be656598b2a8be8c6c6a31e04a770183183d758a9a70099a828",
"sfx_coin_double4.wav": "a2d2984218cad5c85e3d5a5c4367620d45e2d8dea5c627f0561b014dc08d61a0",
"sfx_coin_single3.wav": "12c495610ac1b97076edb19e0bc6c180c30dfc9a49d134c31cb4107b191d6500",
"sfx_damage_hit1.wav": "0d56e04829ea9bcbbba40e5db9c9fc04ada278a893a0698dc2dcc2b2173db375",
"sfx_exp_shortest_hard2.wav": "b7fa33f210937021546043800aab0956a41a99eeb7a0fcc477ae799f56d2dfc1",
"sfx_exp_shortest_hard5.wav": "c1003413524abef76abe3961282bdacf2d720c9664ac8eb7451078544796d848",
"sfx_lowhealth_alarmloop6.wav": "c7bcd3332495f12e52a247de0edef5626627e9537dbaefc841ee0a93cfcc28ab",
"sfx_menu_move2.wav": "f8704e22a03bf45c5f1a9c244ea025b1e33a8e5cf39dd936131f40f60e3afef5",
"sfx_menu_move4.wav": "6662d2033a876fe3764866789f932160f408f3a1958fde82775365b6b42b4fc6",
"sfx_menu_select2.wav": "d3cbe3fcd20ffb777c4fffa8a8e1f558657fb9a9c15d764718360c1fb0268dfb",
"sfx_menu_select5.wav": "64ded09531ed2591dafc8415635607f03875224fe75c79bf720c0fa4d0aa1ccf",
"sfx_movement_jump1.wav": "99ff174713ca233a06d3fdb723a9d767681f03b48a6e16e9be546ae42efbd806",
"sfx_movement_jump10.wav": "01f287fd44a6937e91ec2bf634a7bf1c9f5aa9523ef9c27030d0a1d621be55cf",
"sfx_movement_jump12_landing.wav": "02cb59f234d4df3caf0192d45a1000cb11d91eb966fe5b4dc0fd7d886552624e",
"sfx_sound_poweron.wav": "5067145bae0933e19b21ac1944a74eff94f4df8995c45cc69013b077782bbf34",
"sfx_sounds_Blip11.wav": "afc10f0d0b51021a67ba1241e6b151ae658f24e2eeca2cf4f3c17cdd48c1aec4",
"sfx_sounds_Blip6.wav": "88136aed3e57229b7361304ed92a8bd5ec07ab97b4b89d4ec52fc76c902f5bfb",
"sfx_sounds_Blip9.wav": "f9cb14a7493fca7688bec342446c6dce35be4e875514c1ca5ad1ffb06703c1ba",
"sfx_sounds_error15.wav": "5a20a2fde185161110ac0d09885ee1c59148fb2556a847b8474541af88f47168",
"sfx_sounds_error3.wav": "b1d49574020a176280562871a6f5aa42293a2d24a50290f301a0bd76bc1a08a5",
"sfx_sounds_fanfare3.wav": "08e8f0377e0a820d158728c0cfdf7a0e6da77888fefb83ff20d40bf40f98ce94",
"sfx_sounds_high5.wav": "22329047fdf3cff9630e2ef892db4e7240ef06939a96a53fb6a6e08c2f51b7f3",
"sfx_sounds_impact12.wav": "93b3d0cf28c21c2fdf7376f4b04cfe17047b263e73710c8a805578371ade7452",
"sfx_sounds_impact8.wav": "08f59097b7728d320af979995fe49c9c064938d367a9afd88974dcd495f6b4f1",
"sfx_sounds_interaction10.wav": "360b92bfbede13139a992711136034c3988a801764d6578c54d9238828dec59e",
"sfx_sounds_interaction14.wav": "cbdd3af56b37f37d45c9e3c4144ea4c84e30dd5293ecbaf5b465490cabb0ddfd",
"sfx_sounds_interaction9.wav": "8453640ca7338e2f7bf07f3f85328346320c980db6e994249147baa72434f141",
"sfx_sounds_pause2_in.wav": "4411c3f7d10a5aa8d3b0c3b34f594a749051942f7ecfb0a0c302a9a287b23850",
"sfx_sounds_pause6_in.wav": "9da43f3bb033a8f9b5a034af23b1756f812d76d5611914dc44efc94388b39785",
"sfx_sounds_pause6_out.wav": "d1b638b9b648191d5f4e8fcec77b4f964cd800dd0ffb8518d31658f6b443ca8b",
"sfx_sounds_pause7_in.wav": "fd07fb2594bceb7ff3acf2c645e11efb366d8ad01f984eb7e387fda0aec1111a",
"sfx_sounds_powerup1.wav": "ded83f9452006571efa231e3be8a0a0cc9c48d4b316df204417e02c0e54c538b",
"sfx_sounds_powerup10.wav": "c558f38e4b6c39a4948b2b8a5659294a7dc62bbd34e75b1243799309f38b1a07",
"sfx_sounds_powerup12.wav": "dbdfd1627bf9b9021916eba0b949e660217f98aee06ead551b76d8865cb7abdf",
"sfx_sounds_powerup7.wav": "09830a5f4d2ee511613451aeee2d40eeb5bde46330df82550957b7ef9aea0321",
"sfx_sounds_powerup8.wav": "8d3fbcacc162719fb18404a22c2e205c0ef73a84cc604aec9efc88129c8e6a64",
"sfx_weapon_singleshot14.wav": "8a8e31fe033c6cea623104a8bdf3efc9ef940e8d55553680895ed7bd05342ff6",
"sfx_weapon_singleshot21.wav": "dbbaee294a6fac4dac270b6f955a38dc68d7b7aee7f9f21d3463edd9ddeb5996",
"sfx_wpn_grenadewhistle1.wav": "1b528bebf777c7b9ee6b4436456508c4d5e3c041a5bcc515d83f19aa94af7e1f",
"sfx_wpn_laser12.wav": "8e4284bb5a941fafd0c5cfcea5d92b141e8a39c58a393ba7c5fc8533081c592d",
"sfx_wpn_laser2.wav": "141e8db71eb4c28a1f91965e5c4976832116dc4285a14986e3899d227975d907",
"sfx_wpn_laser6.wav": "c418c24e53e36600e56938473d429303e2109ce63938702460ef772ebc96bd2c",
"sfx_wpn_missilelaunch.wav": "35c9c654a34f414524e80f18d1cafbc8e0c6b478f7ec51c37cfe94e97df41acd",
"sfx_wpn_noammo3.wav": "fd200835babcdaefb3103947b5d752db1f6ace5410d6df3193b9dbade93d92da",
"sfx_wpn_sword1.wav": "2e21c1d5a09ef753d1e2f50d41549a93cea4d7f5bf80ec6b82b6327f6b5f788b",
"sfx_wpn_sword3.wav": "cb11e32087310ff94540342cc0fe2c6a52bfb9f764a7433ab9c52d9d97450022",
}
