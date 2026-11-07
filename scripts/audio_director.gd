extends Node
## All pools live in the host viewport. Panning uses the requesting game's view,
## independent of physics World2D, camera audio listeners and floating origins.
const Bank := preload("res://scripts/sound_bank.gd")
const Settings := preload("res://scripts/audio_settings.gd")
const Assets := preload("res://scripts/sound_assets.gd")
const MusicSets := preload("res://scripts/music_sets.gd")
const LIMIT := 32
const RESERVED := 8
const PRIORITY := ["hurt", "death", "absorb", "charge", "heal", "potion", "homing", "ability_get", "arrow_unlock", "boss_appear", "boss_defeat", "loop_up", "key", "item_get", "buy", "deny", "equip", "shop_open", "tutorial_step", "win", "lose", "pause", "map_open", "map_close", "empty"]
const LIMITS := {"shot": [4, 40], "enemy_shot": [4, 60], "enemy_warn": [3, 120], "enemy_warn_special": [3, 120], "crystal": [3, 50], "enemy_hit": [4, 30], "ui_move": [2, 30], "laser_charge": [3, 100], "ui_confirm": [3, 60]}
var game: Node
var bank := Bank.new()
var settings := Settings.new()
var streams: Dictionary = {}
var synthesis_override := -1 # -1 auto, 0 off, 1 on (also --audio-synthesis=on)
var sound_set_override := "" # "", "synth", "assets"; set before _ready for tests.
var sound_set := "assets"
var music_set_override := "" # "", "standard", "dark", "junkala"; set before _ready for tests.
var music_set := "standard"
var music_set_warned := false
var music_set_warnings := 0
var asset_paths_override: Dictionary = {} # Test-only missing/import-failure fixtures.
var asset_loaded: Dictionary = {}
var asset_pending: Dictionary = {}
var asset_queue: Array = []
var asset_warned: Dictionary = {}
var fallback_pending: Array = []
var fallback_bank: RefCounted
var asset_started_usec := 0
var asset_ready_ms: Dictionary = {}
var asset_service_max_usec := 0
var asset_operation_max_usec := 0
var asset_stream_bytes := 0
var asset_sizes: Dictionary = {}
var enabled := true:
	set(value):
		enabled = value
		if not value:
			for voice: Dictionary in voices: stop_handle(voice.handle)
			for player: AudioStreamPlayer in music: player.stop()
			current_music = ""
			requested_music = ""
			music_gain = [0.0, 0.0]
			music_target = [0.0, 0.0]
var voices: Array[Dictionary] = []
var music: Array[AudioStreamPlayer] = []
var music_gain := [0.0, 0.0]
var music_target := [0.0, 0.0]
var music_result_db := [0.0, 0.0]
var music_slot := 0
var music_ids := ["", ""]
var current_music := ""
var requested_music := ""
var fade_seconds := 1.0
var duck_db := 0.0
var duck_target := 0.0
var impact_duck_db := 0.0
var impact_duck_age := 1.0
var impact_duck_depth := 0.0
const HEAVY := ["boss_defeat", "boss_appear", "bomb_explode", "enhancer_defeat", "death", "hurt"]
const MEDIUM_DEFEAT := ["enemy_defeat", "block_break", "boss_hit"]
var last_id: Dictionary = {}
var last_frame: Dictionary = {}
var requests: Array[Dictionary] = []
var request_cursor := 0
var clock_ms := 0.0
var ambient_in := 5.0
var region := -1
var candidate_region := -1
var region_time := 0.0
var boss_inside := 0.0
var boss_outside := 0.0
var boss_music := false
var ending_timer := -1.0
var ending_id := ""
var ending_started := false
var last_state := ""
var rng := RandomNumberGenerator.new()
var setup_ms := 0.0
var process_usec_total := 0
var process_usec_max := 0
var process_samples := 0
var play_usec_total := 0
var play_usec_max := 0
var play_samples := 0
var handle_serial := 0
var tick_active := false
var pending_play_usec := 0
var frame_work_usec_total := 0
var frame_work_usec_max := 0

func _ready() -> void:
	var began := Time.get_ticks_usec()
	rng.seed = 73182
	for name: String in ["BGM", "SE"]:
		if AudioServer.get_bus_index(name) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, name)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	var has_limiter := false
	for i in range(AudioServer.get_bus_effect_count(0)):
		if AudioServer.get_bus_effect(0, i) is AudioEffectHardLimiter: has_limiter = true
	if not has_limiter:
		var limiter := AudioEffectHardLimiter.new()
		limiter.ceiling_db = -0.5
		AudioServer.add_bus_effect(0, limiter)
	for i in range(LIMIT):
		# Stable shared bus names avoid growth across sequential main instances.
		var name := "SoundVoice%02d" % i
		var bus := AudioServer.get_bus_index(name)
		if bus < 0:
			AudioServer.add_bus()
			bus = AudioServer.bus_count - 1
			AudioServer.set_bus_name(bus, name)
			AudioServer.set_bus_send(bus, "SE")
			AudioServer.add_bus_effect(bus, AudioEffectPanner.new())
		var player := AudioStreamPlayer.new()
		player.bus = name
		add_child(player)
		voices.append({"player": player, "bus": bus, "pan": AudioServer.get_bus_effect(bus, 0), "id": "", "world": false, "source": null, "point": null, "until": 0.0, "priority": false, "handle": -1})
	for i in range(2):
		var player := AudioStreamPlayer.new()
		player.bus = "BGM"
		player.volume_db = -80
		add_child(player)
		music.append(player)
	settings.load_settings(game.audio_settings_path)
	settings.apply()
	requests.resize(512)
	var synth := DisplayServer.get_name() != "headless"
	for arg in OS.get_cmdline_user_args():
		if arg == "--audio-synthesis=on": synth = true
		if arg == "--audio-synthesis=off": synth = false
		if arg == "--sound-set=synth": sound_set = "synth"
		if arg == "--sound-set=assets": sound_set = "assets"
		if arg.begins_with("--music-set="): _select_music_set(arg.get_slice("=", 1))
	if sound_set_override.is_empty(): sound_set_override = game.get_meta("sound_set_override", "")
	if sound_set_override in ["synth", "assets"]: sound_set = sound_set_override
	if music_set_override.is_empty(): music_set_override = game.get_meta("music_set_override", "")
	if not music_set_override.is_empty(): _select_music_set(music_set_override)
	if DisplayServer.get_name() != "headless":
		print("Audio music set: ", music_set)
	if synthesis_override >= 0: synth = synthesis_override == 1
	if synth:
		if sound_set == "assets":
			asset_started_usec = Time.get_ticks_usec()
			asset_queue = Assets.EFFECTS.keys() + MusicSets.music(music_set).keys()
			bank.start(asset_queue)
		else: bank.start()
	setup_ms = (Time.get_ticks_usec() - began) / 1000.0

func _select_music_set(value: String) -> void:
	if MusicSets.is_known(value):
		music_set = value
		return
	music_set = "standard"
	music_set_warnings += 1
	if not music_set_warned:
		music_set_warned = true
		push_warning("Unknown music set; using standard: " + value)

func _exit_tree() -> void:
	for voice: Dictionary in voices:
		voice.player.stop()
		voice.player.stream = null
	for player: AudioStreamPlayer in music:
		player.stop()
		player.stream = null
	bank.shutdown()
	if fallback_bank != null: fallback_bank.shutdown()
	# A completed threaded request must be retrieved even if the host closes.
	# This cleanup is outside the frame/service timing and never changes state.
	var joined: Dictionary = {}
	for path: String in asset_pending.values():
		if not joined.has(path):
			ResourceLoader.load_threaded_get(path)
			joined[path] = true
	asset_pending.clear()

func asset_spec(id: String) -> Dictionary:
	if not asset_loaded.has(id): return {}
	var table := MusicSets.music(music_set)
	return table.get(id, Assets.EFFECTS.get(id, {}))

func source_spec(id: String) -> Dictionary:
	var table := MusicSets.music(music_set)
	return table.get(id, Assets.EFFECTS.get(id, {}))

func music_gain_db(id: String) -> float:
	if sound_set != "assets": return 0.0
	var spec := asset_spec(id)
	if not spec.is_empty(): return float(spec.get("gain_db", 0.0))
	if MusicSets.synth_music(music_set).has(id): return MusicSets.synth_gain_db(music_set)
	return 0.0

func music_asset_db(slot: int) -> float:
	return music_gain_db(music_ids[slot])

func _asset_failed(id: String) -> void:
	if not asset_warned.has(id):
		asset_warned[id] = true
		push_warning("Audio asset unavailable; using synthesis for ID: " + id)
		fallback_pending.append(id)

func _service_assets() -> void:
	if asset_started_usec == 0: return
	if asset_queue.is_empty() and asset_pending.is_empty() and fallback_pending.is_empty() and fallback_bank == null: return
	var began := Time.get_ticks_usec()
	# Queue/get only while within a small frame budget. Never get before LOADED.
	# Both effects and QOA tracks use Godot's background resource loader.
	while not asset_queue.is_empty() and Time.get_ticks_usec() - began < 1500:
		var id: String = asset_queue.pop_front()
		var spec: Dictionary = source_spec(id)
		var path: String = asset_paths_override.get(id, spec.path)
		var op := Time.get_ticks_usec()
		if asset_pending.values().has(path):
			asset_pending[id] = path
		elif ResourceLoader.exists(path) and ResourceLoader.load_threaded_request(path, "AudioStream") == OK:
			asset_pending[id] = path
		else: _asset_failed(id)
		asset_operation_max_usec = maxi(asset_operation_max_usec, Time.get_ticks_usec() - op)
	for id: String in asset_pending.keys():
		if not asset_pending.has(id): continue
		if Time.get_ticks_usec() - began >= 1500: break
		var path: String = asset_pending[id]
		var op := Time.get_ticks_usec()
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var stream := ResourceLoader.load_threaded_get(path) as AudioStream
			if stream != null and not asset_sizes.has(stream.get_instance_id()):
				asset_sizes[stream.get_instance_id()] = stream_bytes(stream)
			for sharing: String in asset_pending.keys():
				if asset_pending[sharing] != path: continue
				if stream != null:
					streams[sharing] = stream
					asset_loaded[sharing] = true
					asset_ready_ms[sharing] = (Time.get_ticks_usec() - asset_started_usec) / 1000.0
				else: _asset_failed(sharing)
				asset_pending.erase(sharing)
		elif status in [ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE]:
			# Failed threaded requests also own a loader reference until retrieved.
			if status == ResourceLoader.THREAD_LOAD_FAILED: ResourceLoader.load_threaded_get(path)
			for sharing: String in asset_pending.keys():
				if asset_pending[sharing] != path: continue
				_asset_failed(sharing)
				asset_pending.erase(sharing)
		asset_operation_max_usec = maxi(asset_operation_max_usec, Time.get_ticks_usec() - op)
	if fallback_bank != null:
		streams.merge(fallback_bank.collect())
		if fallback_bank.snapshot().complete:
			fallback_bank.shutdown()
			fallback_bank = null
	if fallback_bank == null and not fallback_pending.is_empty():
		var skip: Array = Bank.SOUNDS.keys() + Bank.MUSIC_IDS
		for id: String in fallback_pending: skip.erase(id)
		fallback_pending.clear()
		fallback_bank = Bank.new()
		fallback_bank.start(skip)
	# Shared source files (shot/switch/absorb) count once in resident stream data.
	var seen: Dictionary = {}
	asset_stream_bytes = 0
	for id: String in asset_loaded:
		var stream: AudioStream = streams[id]
		if not seen.has(stream.get_instance_id()):
			seen[stream.get_instance_id()] = true
			asset_stream_bytes += int(asset_sizes[stream.get_instance_id()])
	asset_service_max_usec = maxi(asset_service_max_usec, Time.get_ticks_usec() - began)

static func stream_bytes(stream: AudioStream) -> int:
	if stream is AudioStreamWAV: return stream.data.size()
	if stream is AudioStreamOggVorbis:
		var count := 0
		for page in stream.packet_sequence.packet_data:
			for packet in page: count += packet.size()
		return count
	return 0

func trigger_impact_duck(id: String) -> void:
	var depth := -7.0 if HEAVY.has(id) else (-4.0 if MEDIUM_DEFEAT.has(id) else 0.0)
	if depth == 0.0: return
	impact_duck_depth = minf(depth, impact_duck_db)
	impact_duck_age = 0.0
	# Immediate attack meets the 30ms bound even at low rendering rates.
	impact_duck_db = impact_duck_depth
	for i in range(music.size()):
		var attenuation := maxf(-14.0, duck_db+music_result_db[i]+impact_duck_db)
		var target := linear_to_db(maxf(0.0001, music_gain[i]))+attenuation+music_asset_db(i)
		music[i].volume_db = minf(music[i].volume_db, target)

func source_game() -> Node:
	return game.tutorial_session if is_instance_valid(game.tutorial_session) else game

func history() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i in range(512):
		var entry := requests[(request_cursor + i) % 512]
		if not entry.is_empty(): result.append(entry)
	return result

func _record(entry: Dictionary, began: int) -> int:
	requests[request_cursor % 512] = entry
	request_cursor += 1
	var usec := Time.get_ticks_usec() - began
	play_usec_total += usec
	play_usec_max = maxi(play_usec_max, usec)
	play_samples += 1
	if not tick_active: pending_play_usec += usec
	return int(entry.get("voice", -1))

func play(id: String, point: Variant = null, volume_db: float = 0, pitch: float = 1, source: Node = null, color: int = -1) -> int:
	var began := Time.get_ticks_usec()
	if source == null: source = source_game()
	var world := point is Vector2
	var frame := Engine.get_physics_frames()
	var actual := id + ("_a" if color == 0 else "_b") if id in ["shot", "switch", "absorb"] else id
	if id == "shot": pitch *= rng.randf_range(0.97, 1.03)
	var spec := asset_spec(actual)
	pitch *= float(spec.get("pitch", 1.0))
	volume_db += float(spec.get("gain_db", 0.0))
	var entry := {"frame": frame, "id": id, "sample": actual, "position": point, "played": false, "reason": "", "volume_db": volume_db, "pitch": pitch, "pan": 0.0, "voice": -1}
	var reason := ""
	var priority := PRIORITY.has(id) or id.begins_with("ui_")
	var bgm := id in ["win", "lose"] or id.begins_with("amb")
	var limits: Array = LIMITS.get(id, [3, 45])
	if not enabled: reason = "disabled"
	elif world and (source != source_game() or source.state != "playing"): reason = "state"
	elif not streams.has(actual): reason = "unsynthesized"
	elif settings.values.master == 0 or settings.values.bgm == 0 and bgm or settings.values.se == 0 and not bgm: reason = "volume_zero"
	elif last_frame.get(id, -1) == frame: reason = "same_frame"
	elif clock_ms - float(last_id.get(id, -100000)) < limits[1]: reason = "interval"
	var pan := 0.0
	if reason.is_empty() and world:
		var view: Rect2 = source.view_rect()
		var distance: float = point.distance_to(point.clamp(view.position, view.end))
		if distance > view.size.x / 2: reason = "offscreen"
		else:
			pan = clampf((point.x - view.get_center().x) / (view.size.x / 2), -1, 1) * 0.85
			entry.volume_db -= 18.0 * distance / (view.size.x / 2)
	entry.pan = pan
	var chosen := -1
	if reason.is_empty():
		var count := 0
		for i in range(LIMIT):
			var voice: Dictionary = voices[i]
			if voice.until > clock_ms and voice.id == id: count += 1
			if chosen < 0 and voice.until <= clock_ms and (priority or i >= RESERVED): chosen = i
		if count >= int(limits[0]): reason = "id_limit"
		elif chosen < 0 and priority:
			for i in range(LIMIT):
				if not voices[i].priority:
					chosen = i
					break
		if reason.is_empty() and chosen < 0: reason = "voice_limit"
	if reason.is_empty():
		var voice: Dictionary = voices[chosen]
		var player: AudioStreamPlayer = voice.player
		player.stop()
		player.stream_paused = false
		player.stream = streams[actual]
		player.volume_db = entry.volume_db
		player.pitch_scale = clampf(pitch, 0.25, 4.0)
		AudioServer.set_bus_send(voice.bus, "BGM" if bgm else "SE")
		voice.pan.pan = pan
		player.play()
		trigger_impact_duck(id)
		voice.id = id
		voice.world = world
		voice.source = weakref(source)
		voice.point = point
		voice.base_db = volume_db
		voice.priority = priority
		handle_serial += 1
		voice.handle = handle_serial * LIMIT + chosen
		voice.until = clock_ms + player.stream.get_length() / player.pitch_scale * 1000
		last_frame[id] = frame
		last_id[id] = clock_ms
		entry.played = true
		entry.voice = voice.handle
		entry.reason = "played"
	else: entry.reason = reason
	return _record(entry, began)

func stop_handle(handle: int) -> void:
	if handle < 0: return
	var index := handle % LIMIT
	if voices[index].handle != handle: return # A finished warning cannot stop a reused voice.
	voices[index].player.stop()
	voices[index].until = 0.0

func stop_world() -> void:
	for i in range(voices.size()):
		if voices[i].world or voices[i].id in ["win", "lose"]: stop_handle(voices[i].handle)
	last_id.clear()
	last_frame.clear()

func shift_origin(source: Node, delta: Vector2) -> void:
	for voice: Dictionary in voices:
		if voice.world and voice.source != null and voice.source.get_ref() == source: voice.point += delta

func reset_run() -> void:
	impact_duck_db = 0.0
	impact_duck_age = 1.0
	stop_world()
	region = -1
	candidate_region = -1
	region_time = 0
	boss_inside = 0
	boss_outside = 0
	boss_music = false
	ending_timer = -1
	ending_id = ""
	ending_started = false
	last_state = ""
	# Actual music selection runs after start_run, never prepares PCM here.

func set_music(id: String, seconds: float) -> void:
	requested_music = id
	if not streams.has(id) or current_music == id: return
	fade_seconds = maxf(0.1, seconds)
	# Reversing a boundary crossfade keeps the outgoing track's playhead.
	var existing := music_ids.find(id)
	if id != "boss" and existing >= 0 and music[existing].playing:
		music_slot = existing
		music_target[existing] = 1.0
		music_target[1 - existing] = 0.0
		current_music = id
		return
	# If a third track arrives mid-fade, keep the louder player audible.
	var outgoing := music_slot
	if music_gain[1 - outgoing] > music_gain[outgoing]: outgoing = 1 - outgoing
	music_slot = 1 - outgoing
	var player := music[music_slot]
	player.stop()
	player.stream = streams[id]
	player.volume_db = -80.0 + music_gain_db(id)
	player.play()
	music_result_db[music_slot] = -9.0 if ending_started and source_game().state != "audio_settings" else 0.0
	music_ids[music_slot] = id
	music_gain[music_slot] = 0.0
	music_target[music_slot] = 1.0
	music_target[1 - music_slot] = 0.0
	current_music = id

func _process(delta: float) -> void:
	var began := Time.get_ticks_usec()
	tick_active = true
	streams.merge(bank.collect())
	_service_assets()
	# Voice deadlines use media time, not wall time: global pitch changes affect
	# BGM and all SE together, including voices started before the slow motion.
	var real_delta := delta / maxf(0.0001, Engine.time_scale)
	var media_delta := real_delta * AudioServer.playback_speed_scale
	clock_ms += media_delta * 1000
	delta = real_delta
	impact_duck_age += real_delta
	impact_duck_db = lerpf(impact_duck_depth, 0.0, clampf(impact_duck_age/0.3, 0.0, 1.0))
	var source := source_game()
	var state: String = source.state
	var paused := paused_state(state)
	duck_target = -10.0 if paused and state != "audio_settings" else 0.0
	duck_db = move_toward(duck_db, duck_target, delta * 40)
	for voice: Dictionary in voices:
		if voice.until <= clock_ms: continue
		if voice.world:
			voice.player.stream_paused = paused
			if paused: voice.until += media_delta * 1000
			if not paused and voice.source != null:
				var owner: Node = voice.source.get_ref()
				if is_instance_valid(owner):
					var view: Rect2 = owner.view_rect()
					var point: Vector2 = voice.point
					var distance := point.distance_to(point.clamp(view.position, view.end))
					if distance > view.size.x / 2:
						voice.player.stop()
						voice.until = 0.0
						continue
					voice.player.volume_db = voice.base_db - 18.0 * distance / (view.size.x / 2)
					voice.pan.pan = clampf((voice.point.x - view.get_center().x) / (view.size.x / 2), -1, 1) * 0.85
	if enabled: _update_music(source, state, delta)
	if paused_state(state) and not requested_music.is_empty() and current_music != requested_music:
		set_music(requested_music, 1.0)
	for i in range(2):
		var asset_db := music_asset_db(i)
		var previous := db_to_linear(music[i].volume_db - asset_db)
		# Outgoing tracks retain their result attenuation until stopped. An
		# active title recovers over at least one second after leaving results.
		if music_target[i] > 0:
			var result_target := -9.0 if ending_started and state != "audio_settings" else 0.0
			# A retry can precede region synthesis. Keep the old title quiet
			# while waiting, as well as during its eventual crossfade.
			if not ending_started and state == "playing" and not source.is_tutorial() and music_ids[i] == "title":
				result_target = music_result_db[i]
			var speed := 9.0 if not ending_started and state != "audio_settings" else 40.0
			music_result_db[i] = move_toward(music_result_db[i], result_target, delta * speed)
		music_gain[i] = move_toward(music_gain[i], music_target[i], delta / fade_seconds)
		var attenuation := maxf(-14.0, duck_db + music_result_db[i] + impact_duck_db)
		var amplitude := maxf(0.0001, music_gain[i]) * db_to_linear(attenuation)
		# Bound every upward step, including simultaneous fade-in and unduck.
		# Keep the original envelope bound and the actual output bound with makeup.
		amplitude = minf(amplitude, previous + delta * 6.0 / maxf(1.0, db_to_linear(asset_db)))
		if music_target[i] == 0:
			amplitude = minf(amplitude, previous)
		music[i].volume_db = linear_to_db(maxf(0.00000001, amplitude)) + asset_db
		if music_gain[i] == 0 and music_target[i] == 0: music[i].stop()
	var usec := Time.get_ticks_usec() - began
	process_usec_total += usec
	process_usec_max = maxi(process_usec_max, usec)
	process_samples += 1
	var work := usec + pending_play_usec
	frame_work_usec_total += work
	frame_work_usec_max = maxi(frame_work_usec_max, work)
	pending_play_usec = 0
	tick_active = false

func _update_music(source: Node, state: String, delta: float) -> void:
	if paused_state(state):
		# A result's music sequence keeps advancing while its settings are open.
		if state == "audio_settings" and last_state in ["lost", "won"]: state = last_state
		else: return
	if state in ["lost", "won"]:
		if state != last_state:
			music_target = [0.0, 0.0]
			fade_seconds = 0.5
			ending_timer = 0.8 if state == "lost" else 1.5
			ending_id = "lose" if state == "lost" else "win"
			ending_started = false
			current_music = ""
			requested_music = ""
		if ending_timer >= 0:
			ending_timer -= delta
			if ending_timer < 0:
				if not ending_started:
					play(ending_id)
					ending_started = true
					ending_timer = 2.5 if state == "lost" else 3.5
				else: set_music("title", 2)
		last_state = state
		return
	last_state = state
	ending_started = false
	if state in ["title", "tutorial_complete"] or source.is_tutorial():
		set_music("title", 1.0)
		return
	if state != "playing" or not is_instance_valid(source.camera): return
	var next_region: int = source.biome_at(source.camera.position)
	if region < 0: region = next_region
	if next_region != candidate_region:
		candidate_region = next_region
		region_time = 0
	else: region_time += delta
	if region_time >= 1.5: region = candidate_region
	var visible_boss := false
	if source.boss_cycle != null:
		for ref: WeakRef in source.boss_cycle.live_actors.values():
			var actor: Node = ref.get_ref()
			if is_instance_valid(actor) and not actor.dead and source.view_rect().has_point(actor.position):
				visible_boss = true
				break
	if visible_boss:
		boss_inside += delta
		boss_outside = 0
		if boss_inside >= 0.3: boss_music = true
	else:
		boss_inside = 0
		boss_outside += delta
		if boss_outside >= 4: boss_music = false
	set_music("boss" if boss_music else "region%d" % region, 1.0 if boss_music else (2.5 if current_music == "boss" else 3.0))
	ambient_in -= delta
	if ambient_in <= 0:
		ambient_in = rng.randf_range(3, 9)
		var ids: Array = [["amb0_drop", "amb0_ripple"], ["amb1_chime", "amb1_ring"], ["amb2_ember", "amb2_metal"]][next_region]
		var point: Vector2 = source.view_rect().get_center() + Vector2(rng.randf_range(-480, 480), 0)
		play(ids[rng.randi_range(0, 1)], point, -10, rng.randf_range(0.92, 1.08), source)

func paused_state(state: String) -> bool:
	return state in ["paused", "map", "shop", "equipment", "settings", "audio_settings"]

func boss_defeated() -> void:
	boss_music = false
	boss_inside = 0
	boss_outside = 4

func measurements() -> Dictionary:
	var result := {"setup_ms": setup_ms, "process_mean_ms": process_usec_total / float(maxi(1, process_samples)) / 1000, "process_max_ms": process_usec_max / 1000.0, "play_mean_ms": play_usec_total / float(maxi(1, play_samples)) / 1000, "play_max_ms": play_usec_max / 1000.0, "play_calls": play_samples, "process_frames": process_samples, "frame_work_mean_ms": frame_work_usec_total / float(maxi(1, process_samples)) / 1000, "frame_work_max_ms": frame_work_usec_max / 1000.0, "synthesis": bank.snapshot()}
	result.assets = {"sound_set": sound_set, "music_set": music_set, "loaded": asset_loaded.size(), "pending": asset_pending.size(), "stream_bytes": asset_stream_bytes, "ready_ms": asset_ready_ms.duplicate(), "service_max_ms": asset_service_max_usec / 1000.0, "operation_max_ms": asset_operation_max_usec / 1000.0, "fallback_ids": asset_warned.keys()}
	return result
