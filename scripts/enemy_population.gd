extends RefCounted
## Pure placement, after terrain/loot generation; never modifies the cave shape.
const T := preload("res://scripts/tuning.gd")
const G := preload("res://scripts/stage_generator.gd")

static func area(e: Dictionary) -> Rect2:
	var size: Vector2 = T.BOSS_SIZE if e.kind == "boss" else T.ENEMY_SIZE
	var bob: float = T.ENHANCER_BOB_AMPLITUDE if e.kind == "enhancer" else (T.FLYER_BOB_AMPLITUDE if e.kind == "flyer" else 0.0)
	return Rect2(Vector2(e.patrol.x - size.x / 2, e.position.y - size.y / 2 - bob), Vector2(e.patrol.y - e.patrol.x + size.x, size.y + 2 * bob))

static func obstacles(s: Dictionary) -> Array:
	var out: Array = s.solids + s.breakables
	for item: Dictionary in s.get("hearts", []):
		var size := (T.HEART_SIZE+Vector2.ONE*T.HEART_BOB_HEIGHT*2).max(T.PLAYER_SIZE)
		out.append(Rect2(item.position-size/2,size))
	for item: Dictionary in s.get("loot", []):
		var size := T.LOOT_SIZE.max(T.PLAYER_SIZE)
		out.append(Rect2(item.position-size/2,size))
	for item: Dictionary in s.get("merchants", []): out.append(Rect2(item.position - T.MERCHANT_SIZE / 2, T.MERCHANT_SIZE))
	return out

static func occupied(spawns: Array) -> Array:
	var out: Array = []
	for e: Dictionary in spawns:
		out.append(area(e).grow(T.ENEMY_PLACEMENT_MARGIN))
		if e.kind == "flyer": out.append(flight_lane(e))
	return out

static func flight_lane(e: Dictionary) -> Rect2:
	return area(e).grow(T.FLYER_CLEARANCE)

static func lane_clear(e: Dictionary, solids: Array) -> bool:
	var lane := flight_lane(e)
	for solid: Rect2 in solids:
		if lane.intersects(solid): return false
		if solid.size.y==16 and solid.position.x<lane.end.x and solid.end.x>lane.position.x and solid.position.y>=lane.end.y and solid.position.y-lane.end.y<T.PLAYER_SIZE.y+8: return false
	return true

static func reachable_shot(e: Dictionary, s: Dictionary) -> bool:
	return G.has_attack_sight(e,s)

static func enhancer_valid(e: Dictionary, s: Dictionary, blocked: Array = []) -> bool:
	var volume := area(e).grow(T.ENEMY_PLACEMENT_MARGIN)
	if not s.chambers[e.chamber_id].rect.encloses(volume) or s.chambers[e.chamber_id].kind != "normal": return false
	if s.coord == Vector2i.ZERO and volume.grow(T.CAVE_SAFE_RADIUS).has_point(T.SECTOR_START): return false
	if G._any_intersects(obstacles(s), volume): return false
	if blocked.is_empty(): blocked = occupied(s.spawns.filter(func(other): return other.id != e.id))
	if G._any_intersects(blocked, volume): return false
	var nearby := 0
	for other: Dictionary in s.spawns:
		if other.kind not in ["boss", "enhancer"] and other.position.distance_to(e.position) <= T.ENHANCER_RADIUS: nearby += 1
	return nearby >= T.ENHANCER_MIN_NEIGHBORS and reachable_shot(e, s)

static func decorate(s: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d:%d:%d:enhancer" % [s.seed, s.coord.x, s.coord.y]).hash()
	# The starting sector always has the first lantern; other sectors use 60%.
	if s.coord != Vector2i.ZERO and rng.randf() >= T.ENHANCER_CHANCE: return s
	var blocked := occupied(s.spawns)
	var candidates: Array = []
	for room: Dictionary in s.chambers:
		if room.kind != "normal": continue
		for y in range(int(room.rect.position.y) + 64, int(room.rect.end.y) - 63, 32):
			for x in range(int(room.rect.position.x) + 64, int(room.rect.end.x) - 63, 32):
				candidates.append({"id": "enhancer", "kind": "enhancer", "boss_id": -1, "polarity": int(rng.seed & 1), "position": Vector2(x,y), "patrol": Vector2(x-T.ENHANCER_DRIFT, x+T.ENHANCER_DRIFT), "chamber_id": room.id, "support": Rect2()})
	G._shuffle(candidates, rng)
	for e: Dictionary in candidates:
		if enhancer_valid(e, s, blocked):
			s.spawns.append(e)
			break
	return s

static func reserve(s: Dictionary, level: int = T.FINAL_BOSS_CLEARS, attempt: int = 0) -> Array:
	var out: Array = []
	var all_spawns: Array = s.spawns.duplicate()
	var fixed := obstacles(s)
	var blocked := occupied(all_spawns)
	var base: Array = s.spawns.filter(func(e): return e.kind != "boss")
	var candidates := {}
	for kind: String in ["turret","walker","flyer"]:
		candidates[kind] = []
		for room: Dictionary in s.chambers:
			if room.kind != "normal": continue
			# Supports were certified by the same initial-ability graph used for base enemies.
			for surface: Rect2 in s.solids:
				if surface.position.y <= room.rect.position.y or surface.position.y > room.rect.end.y: continue
				var left := maxf(surface.position.x, room.rect.position.x)
				var right := minf(surface.end.x, room.rect.end.x)
				for x in range(ceili((left+32)/16)*16, int(right)-31, 16):
					var altitudes: Array = T.LOOP_FLYER_ALTITUDES if kind=="flyer" else [T.ENEMY_SIZE.y/2]
					for altitude: float in altitudes:
						var point := Vector2(x, surface.position.y - altitude)
						var lane := Rect2(x-T.LOOP_FLYER_LANE_WIDTH/2, surface.position.y, T.LOOP_FLYER_LANE_WIDTH, 32)
						var patrol := Vector2(x,x)
						if kind == "walker": patrol = Vector2(x-T.LOOP_WALKER_PATROL,x+T.LOOP_WALKER_PATROL)
						if kind == "flyer": patrol = Vector2(lane.position.x+T.FLYER_LANE_MARGIN,lane.end.x-T.FLYER_LANE_MARGIN)
						var e := {"id": "", "kind": kind, "boss_id": -1, "polarity": 0, "position": point, "patrol": patrol, "chamber_id": room.id, "support": lane, "thick_support":surface.size.y!=16}
						var volume := area(e)
						if not room.rect.encloses(volume): continue
						if s.coord == Vector2i.ZERO and volume.grow(T.CAVE_SAFE_RADIUS).has_point(T.SECTOR_START): continue
						if G._any_intersects(blocked,volume): continue
						if kind == "flyer":
							if lane.position.x < left or lane.end.x > right or not lane_clear(e,s.solids+s.breakables): continue
						else:
							# This exact solid is the full supporting surface, avoiding a
							# repeated scan of the same cave for every ground-enemy kind.
							if volume.position.x<surface.position.x or volume.end.x>surface.end.x: continue
						if G._any_intersects(fixed,volume): continue
						candidates[kind].append(e)
	for kind: String in ["shifter","breaker","laser"]: candidates[kind] = candidates.turret.duplicate()
	candidates.builder = candidates.turret.filter(func(e):return e.thick_support)
	for stage in range(1, mini(level,T.LOOP_COUNT_CAP-1)+1):
		var rng := RandomNumberGenerator.new()
		rng.seed = ("%d:%d:%d:population:%d:packing:%d" % [s.seed,s.coord.x,s.coord.y,stage,attempt]).hash()
		var kinds: Array = base.map(func(e): return e.kind if e.kind != "enhancer" else "turret")
		G._shuffle(kinds,rng)
		for kind: String in candidates: G._shuffle(candidates[kind],rng)
		for kind: String in kinds:
			var alternatives: Array = ["flyer","breaker","laser"] if kind in ["flyer","breaker","laser"] else ["turret","walker","shifter","builder"]
			alternatives.erase(kind)
			alternatives.sort_custom(func(a,b): return out.filter(func(e): return e.kind==a).size() < out.filter(func(e): return e.kind==b).size())
			alternatives.push_front(kind)
			# Preserve the attack-class ratio when possible; use the least numerous
			# remaining kind if the furnished cave has exhausted that class's sites.
			var remaining: Array = G.NORMAL_KINDS.filter(func(k): return not alternatives.has(k))
			remaining.sort_custom(func(a,b): return out.filter(func(e):return e.kind==a).size()<out.filter(func(e):return e.kind==b).size())
			alternatives.append_array(remaining)
			var placed := false
			for choice: String in alternatives:
				for e: Dictionary in candidates[choice]:
					var volume := area(e)
					if G._any_intersects(blocked,volume): continue
					if choice == "flyer" and G._any_intersects(blocked,flight_lane(e)): continue
					var spawn := e.duplicate(true)
					spawn.kind = choice
					spawn.erase("thick_support")
					if not G.has_attack_sight(spawn,s): continue
					spawn.id = "extra_%d_%d" % [stage,out.size()]
					spawn.spawn_stage = stage
					spawn.polarity = rng.randi_range(0,1)
					out.append(spawn)
					blocked.append(volume.grow(T.ENEMY_PLACEMENT_MARGIN))
					if choice == "flyer": blocked.append(flight_lane(spawn))
					placed = true
					break
				if placed: break
	if out.size()<base.size()*mini(level,T.LOOP_COUNT_CAP-1) and attempt<T.LOOP_PLACEMENT_RETRIES:
		var alternative := reserve(s,level,attempt+1)
		if alternative.size()>out.size(): return alternative
	return out
