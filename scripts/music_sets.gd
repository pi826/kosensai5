extends RefCounted
## Hand-written music set tables. sound_assets.gd remains generated.
const Assets := preload("res://scripts/sound_assets.gd")
const SETS := ["standard", "dark", "junkala"]
const DISPLAY := {"standard": "Standard", "dark": "Dark", "junkala": "Junkala"}
const DARK_MUSIC := {
	"title": {"gain_db":-5.83920590576437,"loop_offset":0.0,"path":"res://assets/audio/music/hydrogene_goofy_monster.ogg","pitch":1.0},
	"region0": {"gain_db":-5.52251086411641,"loop_offset":0.0,"path":"res://assets/audio/music/hydrogene_ancient_library.ogg","pitch":1.0},
	"region1": {"gain_db":-7.30159191520658,"loop_offset":0.0,"path":"res://assets/audio/music/hydrogene_the_old_magician.ogg","pitch":1.0},
	"region2": {"gain_db":-2.94727505171011,"loop_offset":0.0,"path":"res://assets/audio/music/hydrogene_malicious_scheme.ogg","pitch":1.0},
	"boss": {"gain_db":-6.02992104460954,"loop_offset":0.0,"path":"res://assets/audio/music/hydrogene_the_evil_one.ogg","pitch":1.0},
}
const JUNKALA_MUSIC := {
	"title": {"gain_db":-13.3723276582386,"path":"res://assets/audio/music/junkala_title_screen.wav","pitch":1.0},
	"region0": {"gain_db":-14.5629289263587,"path":"res://assets/audio/music/junkala_level1.wav","pitch":1.0},
	"region1": {"gain_db":-14.7903711008406,"path":"res://assets/audio/music/junkala_level2.wav","pitch":1.0},
	"region2": {"gain_db":-14.5655743520657,"path":"res://assets/audio/music/junkala_level3.wav","pitch":1.0},
}
const MUSIC := {"dark": DARK_MUSIC, "junkala": JUNKALA_MUSIC}
const SYNTH_MUSIC := {"standard": [], "dark": [], "junkala": ["boss"]}
const SYNTH_GAIN_DB := {"standard": 0.0, "dark": 0.0, "junkala": -9.22395637003538}
const SHA256 := {
	"res://assets/audio/music/hydrogene_traveling_the_sky.ogg": "13dddc6e6b1d057429d2fea4937b558f11dddde983a4aad49be8217faf83f57d",
	"res://assets/audio/music/hydrogene_spirits_forest_full.ogg": "2e8d4a1dc7fd408c2accc232f2baefd1b3b94ad6d3039bd1a26842e4d8715cd2",
	"res://assets/audio/music/hydrogene_dangerous_cave.ogg": "40a90d6af70f4663a4217976c00da96abc71afd9024a73b44d6a39ef73d9bae4",
	"res://assets/audio/music/hydrogene_volcanic_crater.ogg": "b3af540674bae1f73deb4c90a844427cfde4505417e0109aa0e3823695af1413",
	"res://assets/audio/music/hydrogene_battle_theme_iv_full.ogg": "919161a0a54887891983115290c312445082ddc63a2025c5594d8abb5592b2eb",
	"res://assets/audio/music/hydrogene_goofy_monster.ogg": "71940f1a69f30d062a911721412e4c1bd1d6fbef9c93100977288b107408cd3d",
	"res://assets/audio/music/hydrogene_ancient_library.ogg": "084c5e8ede117ee3d83902763b111dc08d4ef08f7b1b61fd5c3caba407fa8cc9",
	"res://assets/audio/music/hydrogene_the_old_magician.ogg": "d5038dfd0508b1d777030d8df0f53e812d28a861a86298f02a1e98c104a89f96",
	"res://assets/audio/music/hydrogene_malicious_scheme.ogg": "b5406e882704e1799ffc9a65609fe88ac40cbf958d59b05b6ca4232d8edc171e",
	"res://assets/audio/music/hydrogene_the_evil_one.ogg": "1636b312d488025f348513014aa063497058c686aedd1c5975cbd9840e56729a",
	"res://assets/audio/music/junkala_title_screen.wav": "d1590ec1b4a9e0ff948437c8e1d7f416ee382600af6e454fa0452903d8de1964",
	"res://assets/audio/music/junkala_level1.wav": "6f79ae4c6f2b59baa62c46bcd264c9d157f5dca2c30845fabc3c5be4e2b64a43",
	"res://assets/audio/music/junkala_level2.wav": "c782eccc0634db2818feee4b1f01360dd355505df036732359f2bedb7c772758",
	"res://assets/audio/music/junkala_level3.wav": "c30ae8521119deefd0e22224310e45c07ca726c20760dd93e64e02b9b59a8e6c",
}
static func is_known(set_name: String) -> bool:
	return SETS.has(set_name)
static func normalize(set_name: String) -> String:
	return set_name if is_known(set_name) else "standard"
static func music(set_name: String) -> Dictionary:
	if set_name == "standard": return Assets.MUSIC
	return MUSIC.get(set_name, Assets.MUSIC)
static func synth_music(set_name: String) -> Array:
	return SYNTH_MUSIC.get(set_name, [])
static func synth_gain_db(set_name: String) -> float:
	return float(SYNTH_GAIN_DB.get(set_name, 0.0))
