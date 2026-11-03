extends RefCounted
## Run-owned boss records. Selection jobs only read immutable procedural data.
const T := preload("res://scripts/tuning.gd")
const G := preload("res://scripts/stage_generator.gd")
const S := preload("res://scripts/sector_generator.gd")
const Job := preload("res://scripts/sector_job.gd")
const O := preload("res://scripts/origin_shift.gd")
var game: Node2D
var round_number := 1
var final_clears := 0
var phase := "guardians"
var records: Dictionary = {}
var used_sectors: Array[Vector2i] = []
var guardian_ids: Array[int] = [0, 1, 2]
var guardian_kills := 0
var secret_kills := 0
var selection: RefCounted
var live_actors: Dictionary = {} # Weak references; unloading never retains a node.

func nearest_target(from: Vector2) -> Dictionary:
	if selection != null or phase == "complete": return {}
	var ids: Array = guardian_ids if phase == "guardians" else records.keys()
	var origin: Dictionary = game.stable_point(from)
	var best := {}
	var nearest := INF
	for id: int in ids:
		if game.defeated_bosses.has(id): continue
		var record: Dictionary = records.get(id, {})
		var point := {}
		var role := "guardian"
		if not record.is_empty():
			role = record.role
			if not record.alive or role != ("guardian" if phase == "guardians" else phase): continue
			point = {"sector": record.sector, "local": record.position} if record.get("sector_local", false) else game.stable_point(record.position)
		elif phase == "guardians" and round_number == 1 and id >= 0 and id < 3:
			# initialize() caches the seeded sectors; never generate terrain for the aid.
			point = {"sector": used_sectors[id], "local": T.SECTOR_SIZE / 2}
		else: continue
		var actor = live_actors[id].get_ref() if live_actors.has(id) else null
		if is_instance_valid(actor) and actor.get_parent() == game.world:
			if actor.dead or actor.is_queued_for_deletion(): continue
			point = game.stable_point(actor.position)
		# Subtract integer sectors before converting to float, including at distant origins.
		var offset: Vector2 = Vector2(point.sector - origin.sector) * T.SECTOR_SIZE + (point.local - origin.local)
		var distance := offset.length_squared()
		if distance < nearest:
			nearest = distance
			best = {"boss_id": id, "offset": offset, "role": role}
	return best

class Selection extends RefCounted:
	var seed_value: int
	var center: Vector2i
	var round_number: int
	var roles: Array[String] = []
	var excluded: Array[Vector2i] = []
	var task_id := -1
	var result: Array = []
	var select: Callable
	func run() -> void:
		result = select.call(seed_value, center, round_number, roles, excluded)

static func size_for(role: String) -> Vector2:
	return T.FINAL_BOSS_SIZE if role == "final" else (T.SECRET_BOSS_SIZE if role == "secret" else T.BOSS_SIZE)

static func hp_for(role: String) -> int:
	return T.FINAL_BOSS_HP if role == "final" else (T.SECRET_BOSS_HP if role == "secret" else T.BOSS_HP)

static func name_for(role: String) -> String:
	return "ラスボス" if role == "final" else ("裏ボス" if role == "secret" else "ガーディアン")

static func display_name(role: String, boss_type: String) -> String:
	return "ガーディアン・" + T.GUARDIAN_TYPE_NAMES.get(boss_type, boss_type) if role == "guardian" else name_for(role)

static func guardian_types(seed_value: int, cycle: int) -> Array[String]:
	var types: Array[String] = []
	types.assign(T.GUARDIAN_TYPES)
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d:%d:guardian_types" % [seed_value, cycle]).hash()
	G._shuffle(types, rng)
	return types

static func roam_rect(data: Dictionary, room: Rect2, role: String, preferred: Vector2 = Vector2.INF, ignore_shelves: bool = false) -> Rect2:
	# Arena bosses pass through one-way shelves; other obstacles stay excluded.
	# Thus reflections never lead into a rock, a tunnel or a vertical shaft.
	var extent: Vector2 = size_for(role) + T.BOSS_ROAM_TRAVEL[role] + Vector2.ONE * T.BOSS_CLEARANCE * 2
	var obstacles: Array = data.solids.filter(func(r): return not ignore_shelves or r.size.y != 16) + data.breakables
	for item: Dictionary in data.get("loot", []): obstacles.append(Rect2(item.position - T.LOOT_SIZE / 2, T.LOOT_SIZE).grow(T.BOSS_CLEARANCE))
	for item: Dictionary in data.get("merchants", []): obstacles.append(Rect2(item.position - T.MERCHANT_SIZE / 2, T.MERCHANT_SIZE).grow(T.BOSS_CLEARANCE))
	var best := Rect2()
	var best_distance := INF
	for y in range(int(room.end.y - extent.y), int(room.position.y) - 1, -T.TILE_SIZE):
		for x in range(int(room.position.x), int(room.end.x - extent.x) + 1, T.TILE_SIZE):
			var volume := Rect2(Vector2(x, y), extent)
			var distance := volume.get_center().distance_squared_to(preferred) if preferred != Vector2.INF else 0.0
			if distance >= best_distance: continue
			if obstacles.any(func(r): return r.intersects(volume)): continue
			best = Rect2(volume.position + size_for(role) / 2 + Vector2.ONE * T.BOSS_CLEARANCE, T.BOSS_ROAM_TRAVEL[role])
			if preferred == Vector2.INF: return best
			best_distance = distance
	return best

static func select_sites(seed_value: int, center: Vector2i, cycle: int, roles: Array[String], excluded: Array[Vector2i]) -> Array:
	var guardians := S.guardian_sectors(seed_value)
	var types := guardian_types(seed_value, cycle)
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d:%d:%s" % [seed_value, cycle, ",".join(roles)]).hash()
	var result: Array = []
	var regions: Array[int] = []
	# Keep the first ring's random order, continuing the same RNG for expansion.
	for maximum: int in [T.BOSS_SPAWN_DISTANCE_MAX, T.BOSS_SPAWN_DISTANCE_FALLBACK_MAX]:
		var candidates: Array[Vector2i] = []
		for y in range(-maximum, maximum+1):
			for x in range(-maximum, maximum+1):
				var distance := maxi(absi(x), absi(y))
				var at := center+Vector2i(x,y)
				if maximum > T.BOSS_SPAWN_DISTANCE_MAX and distance <= T.BOSS_SPAWN_DISTANCE_MAX: continue
				if distance >= T.BOSS_SPAWN_DISTANCE_MIN and not excluded.has(at) and S.is_arena_sector(seed_value, at, guardians): candidates.append(at)
		G._shuffle(candidates, rng)
		for at: Vector2i in candidates:
			var region := S.region_at(seed_value, at)
			if roles.size() > 1 and regions.has(region): continue
			var role: String = roles[result.size()]
			var data := S.generate(seed_value, at)
			for room: Dictionary in data.chambers:
				if room.kind != "boss": continue
				var zone := G.arena_zone(room.rect, room.arena_tiers)
				var roam := roam_rect(data, zone, role, Vector2(zone.get_center().x, room.rect.end.y - T.ARENA_BOSS_CENTER_HEIGHT), true)
				if not roam.has_area(): continue
				result.append({"sector": at, "sector_local": true, "chamber_id": room.id, "arena": room.rect, "roam": roam,
					"position": roam.get_center(), "region": region, "role": role, "boss_type": types[result.size()] if role == "guardian" else ""})
				regions.append(region)
				break
			if result.size() == roles.size(): return result
	return result

func initialize() -> void:
	used_sectors = S.guardian_sectors(game.current_seed)

func world_record(record: Dictionary) -> Dictionary:
	if record.is_empty(): return {}
	var out := record.duplicate(true)
	if not record.get("sector_local", false): return out
	var delta: Vector2 = game.stream.sector_offset(record.sector)
	for field in ["position", "arena", "roam"]: out[field] = O.geometry(record[field], delta)
	out.patrol += Vector2.ONE * delta.x
	out.saved = O.actor(record.saved, delta)
	return out

func update_position(actor: CharacterBody2D) -> void:
	if records.has(actor.boss_id):
		var record: Dictionary = records[actor.boss_id]
		record.position = actor.position - game.stream.sector_offset(record.sector)

func shutdown() -> void:
	if selection != null:
		WorkerThreadPool.wait_for_task_completion(selection.task_id)
		selection = null

func initial_spawn(spawn: Dictionary, data: Dictionary) -> Dictionary:
	if phase != "guardians" or round_number != 1: return {}
	if records.has(spawn.boss_id): return records[spawn.boss_id]
	var record := spawn.duplicate(true)
	record.role = "guardian"
	record.boss_type = guardian_types(game.current_seed, 1)[spawn.boss_id]
	record.arena = Rect2()
	record.roam = Rect2()
	if not data.is_empty():
		record.arena = data.chambers[spawn.chamber_id].rect
		var zone := G.arena_zone(record.arena, data.chambers[spawn.chamber_id].arena_tiers)
		record.roam = roam_rect(data, zone, "guardian", Vector2(zone.get_center().x, record.arena.end.y - T.ARENA_BOSS_CENTER_HEIGHT), true)
		if record.roam.has_area(): record.position = record.roam.get_center()
	record.hp = T.BOSS_HP
	record.alive = true
	record.revealed = false
	record.saved = {}
	var delta: Vector2 = -game.stream.sector_offset(spawn.sector)
	for field in ["position", "arena", "roam"]: record[field] = O.geometry(record[field], delta)
	record.patrol += Vector2.ONE * delta.x
	record.sector_local = true
	records[spawn.boss_id] = record
	return record

func request(roles: Array[String]) -> void:
	if selection != null: return
	selection = Selection.new()
	selection.select = select_sites
	selection.seed_value = game.current_seed
	selection.center = game.stream.sector_at(game.player.position)
	selection.round_number = round_number
	selection.roles = roles
	selection.excluded = used_sectors.duplicate()
	selection.task_id = WorkerThreadPool.add_task(selection.run, false, "boss placement")

func service() -> void:
	if selection == null or not WorkerThreadPool.is_task_completed(selection.task_id): return
	WorkerThreadPool.wait_for_task_completion(selection.task_id)
	var sites: Array = selection.result
	var expected: int = selection.roles.size()
	selection = null
	if sites.size() != expected:
		push_error("No legal boss chambers found in the requested sector ring")
		game.announce("ボスの出現場所を確保できませんでした")
		return
	if phase == "guardians": guardian_ids.clear()
	for site: Dictionary in sites:
		var id := next_id()
		site.id = "boss:%d" % id
		site.boss_id = id
		site.kind = "boss"
		site.polarity = int(game.current_seed & 1)
		site.patrol = Vector2(site.position.x, site.position.x)
		site.hp = hp_for(site.role)
		site.alive = true
		site.revealed = true
		site.saved = {}
		records[id] = site
		used_sectors.append(site.sector)
		if site.role == "guardian": guardian_ids.append(id)
		game.discovered_bosses[id] = {"sector": site.sector, "local": site.position}
		game.stream.install_bosses(site.sector)
	if phase == "guardians":
		game.announce("ガーディアンが復活した！（%d周目）" % round_number)
		game.play_sound("boss_appear")
	else:
		game.announce(spawn_message(sites[0]))
		game.play_sound("boss_appear")

func next_id() -> int:
	var result := 3
	for id: int in records: result = maxi(result, id + 1)
	return result

func spawn_message(record: Dictionary) -> String:
	var offset: Vector2i = record.sector - game.stream.sector_at(game.player.position)
	var direction := ("右" if offset.x > 0 else ("左" if offset.x < 0 else "")) + ("下" if offset.y > 0 else ("上" if offset.y < 0 else ""))
	return "%sが%sに出現！（%s 約%d区画先）" % [display_name(record.role, record.get("boss_type", "")), T.BIOME_NAMES[record.region], direction, maxi(absi(offset.x), absi(offset.y))]

func defeated(actor: CharacterBody2D) -> void:
	if records.has(actor.boss_id):
		records[actor.boss_id].alive = false
		records[actor.boss_id].hp = 0
	match actor.boss_role:
		"guardian":
			guardian_kills += 1
			if current_guardian_defeats() == 3:
				phase = "final"
				request(["final"])
		"final":
			final_clears += 1
			game.update_loop_scaling()
			if final_clears >= T.FINAL_BOSS_CLEARS:
				phase = "secret"
				request(["secret"])
			else:
				round_number += 1
				phase = "guardians"
				guardian_ids.clear()
				request(["guardian", "guardian", "guardian"])
		"secret":
			secret_kills += 1
			phase = "complete"
			if not game.ending:
				game.ending = true
				game.call_deferred("_finish_run")

func current_guardian_defeats() -> int:
	var count := 0
	for id: int in guardian_ids: count += int(game.defeated_bosses.has(id))
	return count

func objective() -> String:
	match phase:
		"final": return "ラスボスを倒せ（%d回目）" % (final_clears + 1)
		"secret": return "裏ボスを倒せ"
		"complete": return "裏ボス撃破・クリア"
	return "ガーディアン %d / 3 撃破%s" % [current_guardian_defeats(), "（%d周目）" % round_number if round_number > 1 else ""]

func blocks_normal(spawn: Dictionary, sector_local: bool = false) -> bool:
	for record: Dictionary in records.values():
		# Keep the arena clear for the rest of this run, including 5C respawns.
		if record.revealed and record.sector == spawn.sector and (record.chamber_id == spawn.chamber_id or record.arena.has_point(spawn.position if sector_local else spawn.position - game.stream.sector_offset(spawn.sector))): return true
	return false

func remember(actor: CharacterBody2D, saved: Dictionary) -> void:
	if not records.has(actor.boss_id): return
	var record: Dictionary = records[actor.boss_id]
	record.saved = O.actor(saved, -game.stream.sector_offset(record.sector))
	record.hp = actor.hp
	update_position(actor)
	if record.revealed or game.discovered_bosses.has(actor.boss_id): game.discovered_bosses[actor.boss_id] = game.stable_point(actor.position)

