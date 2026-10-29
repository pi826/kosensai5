extends RefCounted
## Dedicated salts keep progression independent of enemy/terrain RNG and order.
const T := preload("res://scripts/tuning.gd")
const G := preload("res://scripts/stage_generator.gd")
const M := preload("res://scripts/merchant_generator.gd")

static func ability_sectors(seed_value: int) -> Dictionary:
	var out := {T.ABILITY_DOUBLE: Vector2i.ZERO}
	for ability: int in [T.ABILITY_DASH, T.ABILITY_GLIDE]:
		var limits: Vector2i = T.ABILITY_SECTOR_DISTANCE[ability]
		var candidates: Array[Vector2i] = []
		for y in range(-limits.y, limits.y + 1):
			for x in range(-limits.y, limits.y + 1):
				var at := Vector2i(x, y)
				if maxi(absi(x), absi(y)) >= limits.x and not out.values().has(at): candidates.append(at)
		var rng := RandomNumberGenerator.new()
		rng.seed = ("%d:ability:%d" % [seed_value, ability]).hash()
		out[ability] = candidates[rng.randi_range(0, candidates.size() - 1)]
	return out

static func _site_obstacles(s: Dictionary) -> Array:
	var blocked: Array = s.breakables.map(func(r): return r.grow(8))
	for e: Dictionary in s.spawns:
		var size: Vector2 = T.BOSS_SIZE if e.kind == "boss" else T.ENEMY_SIZE
		var bob: float = T.ENHANCER_BOB_AMPLITUDE if e.kind == "enhancer" else (T.FLYER_BOB_AMPLITUDE if e.kind == "flyer" else 0.0)
		blocked.append(Rect2(Vector2(e.patrol.x-size.x/2,e.position.y-size.y/2-bob),Vector2(e.patrol.y-e.patrol.x+size.x,size.y+2*bob)).grow(8))
		if e.kind == "flyer": blocked.append(G.flight_lane(e.support))
	return blocked

static func site_valid(s: Dictionary, point: Vector2, blocked: Array = []) -> bool:
	var body := Rect2(point - T.PLAYER_SIZE / 2, T.PLAYER_SIZE)
	if not s.chambers.any(func(r): return r.kind != "boss" and r.rect.encloses(body.grow(8))): return false
	if G._embedded(point, T.PLAYER_SIZE, s.solids + s.breakables): return false
	if blocked.is_empty(): blocked = _site_obstacles(s)
	if G._any_intersects(blocked,body): return false
	if s.hearts.any(func(h): return h.position.distance_to(point) < T.LOOT_SPACING): return false
	if s.get("merchants", []).any(func(h): return h.position.distance_to(point) < T.LOOT_SPACING): return false
	return not s.get("loot", []).any(func(h): return h.position.distance_to(point) < T.LOOT_SPACING)

# Keep the public check independent of any cache, including on edited sectors.
static func _site_valid(s: Dictionary, point: Vector2, blocked: Array, solids: Array, breakables: Array) -> bool:
	var body := Rect2(point - T.PLAYER_SIZE / 2, T.PLAYER_SIZE)
	var inside := false
	var clearance := body.grow(8)
	for r: Dictionary in s.chambers:
		if r.kind != "boss" and r.rect.encloses(clearance):
			inside = true
			break
	if not inside: return false
	if G._embedded(point, T.PLAYER_SIZE, solids) or G._embedded(point, T.PLAYER_SIZE, breakables): return false
	if blocked.is_empty(): blocked = _site_obstacles(s)
	if G._any_intersects(blocked,body): return false
	for items: Array in [s.hearts, s.get("merchants", []), s.get("loot", [])]:
		for h: Dictionary in items:
			if h.position.distance_to(point) < T.LOOT_SPACING: return false
	return true

static func _append(s: Dictionary, point: Vector2, kind: String, contents: Array = []) -> void:
	var item := {"id": "%s:%d:%d" % [kind, roundi(point.x), roundi(point.y)], "kind": kind, "position": point}
	if kind == "chest": item.contents = contents
	if kind == "crystal": item.amount = T.DETOUR_REWARD
	s.loot.append(item)

static func decorate(s: Dictionary, graph: Dictionary = {}, damaged_graph: Dictionary = {}) -> Dictionary:
	s.loot = []
	s.detours = []
	s.optional_surfaces = []
	var terrain := s.duplicate(false)
	terrain.solids = s.solids + s.breakables
	if graph.is_empty(): graph = G.navigation_graph(terrain)
	var origin := G.node_at(graph, s.start_position)
	var forward := G.reachable_nodes(graph, origin)
	var backward := G.reachable_nodes(graph, origin, true)
	var sites: Array[Vector2] = []
	var blocked := _site_obstacles(s)
	var solid_buckets := G._x_buckets(s.solids, 0)
	var solid_cache := {}
	for i in range(graph.nodes.size()):
		if not forward.has(i) or not backward.has(i): continue
		var surface: Rect2 = graph.nodes[i]
		for x in range(int(surface.position.x) + 32, int(surface.end.x) - 31, 32):
			var point := Vector2(x, surface.position.y - 22)
			var nearby := G._x_near(s.solids, solid_buckets, x - 16, x + 16, solid_cache)
			if _site_valid(s, point, blocked, nearby, s.breakables): sites.append(point)
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d:%d:%d:loot" % [s.seed, s.coord.x, s.coord.y]).hash()
	G._shuffle(sites, rng)
	# The first key and double-jump chest are on the safe starting-room route.
	if s.coord == Vector2i.ZERO:
		sites.sort_custom(func(a, b): return a.distance_squared_to(s.start_position) < b.distance_squared_to(s.start_position))
	var sectors := ability_sectors(s.seed)
	var ability := 0
	for id: int in sectors:
		if sectors[id] == s.coord: ability = id
	var wants_key: bool = s.coord == Vector2i.ZERO or rng.randf() < T.SECTOR_KEY_CHANCE
	var wants_chest: bool = rng.randf() < T.SECTOR_CHEST_CHANCE
	var requests: Array = []
	if wants_key: requests.append({"kind": "key", "contents": []})
	if ability != 0: requests.append({"kind": "chest", "contents": [{"kind": "ability", "ability": ability}]})
	if wants_chest: requests.append({"kind": "chest", "contents": [{"kind": "crystal", "amount": rng.randi_range(T.CHEST_CRYSTAL_MIN, T.CHEST_CRYSTAL_MAX)}]})
	for request: Dictionary in requests:
		for point: Vector2 in sites:
			if not site_valid(s, point, blocked): continue
			_append(s, point, request.kind, request.contents)
			break
	_add_detour(s, graph, rng, damaged_graph)
	M.decorate(s, sites, blocked)
	var content_rng := RandomNumberGenerator.new()
	content_rng.seed = ("%d:%d:%d:chest_contents" % [s.seed,s.coord.x,s.coord.y]).hash()
	for item: Dictionary in s.loot:
		if item.kind != "chest" or item.contents[0].kind != "crystal": continue
		var roll := content_rng.randf()
		if roll < T.CHEST_POTION_CHANCE: item.contents = [{"kind": "potion"}]
		elif roll < T.CHEST_POTION_CHANCE + T.CHEST_EQUIPMENT_CHANCE:
			item.contents = [{"kind": "equipment", "roll": content_rng.randi()}]
	return s

static func _add_detour(s: Dictionary, base: Dictionary, rng, damaged_base: Dictionary = {}) -> void:
	var wanted: int = [1, 3, 7][rng.randi_range(0, 2)] if s.coord != Vector2i.ZERO else 1
	var wanted_profiles := G.flight_profiles(wanted)
	var prior := 1 if wanted==3 else 3
	var prior_profiles := G.flight_profiles(prior)
	var blocked := _site_obstacles(s)
	var candidates: Array = []
	var base_solids: Array = s.solids+s.breakables
	var spatial := {"solids":base_solids,"buckets":G._x_buckets(base_solids,0),"cache":{}}
	for room: Dictionary in s.chambers:
		if room.kind == "boss" or room.shelves.size() >= 4: continue
		var r: Rect2 = room.rect
		for y in range(int(r.position.y) + 96, int(r.end.y) - 191, 32):
			for x in range(int(r.position.x) + 32, int(r.end.x) - int(T.DETOUR_WIDTH) - 31, 64):
				candidates.append(Rect2(x, y, T.DETOUR_WIDTH, 16))
	G._shuffle(candidates, rng)
	for shelf: Rect2 in candidates:
		var point := Vector2(shelf.get_center().x, shelf.position.y - 22)
		var clearance := Rect2(shelf.position - Vector2(16, 80), shelf.size + Vector2(32, 160))
		var nearby := G._x_near(base_solids, spatial.buckets, clearance.position.x, clearance.end.x, spatial.cache)
		if G._any_intersects(nearby, clearance) or not _site_valid(s, point, blocked, nearby, []): continue
		var solids: Array = base_solids + [shelf]
		if G.initial_jump_reaches(base.nodes, shelf, solids): continue
		var arcs := {}
		# Test the cheaper preceding profiles before trying the longer flights.
		var prior_reaches := false
		if wanted != 1:
			for n: Rect2 in base.nodes:
				if not G._ability_edge(n, shelf, solids, prior, prior_profiles, spatial, arcs).is_empty():
					prior_reaches = true
					break
		if prior_reaches: continue
		var edge := {}
		for i in range(base.nodes.size()):
			var trial := G._ability_edge(base.nodes[i], shelf, solids, wanted, wanted_profiles, spatial, arcs)
			if not trial.is_empty():
				edge = trial
				break
		if edge.is_empty(): continue
		if s.spawns.any(func(e): return e.kind == "flyer" and not G.lane_is_clear(e.support, solids)): continue
		var sight := s.duplicate(false)
		sight.solids = solids
		if s.spawns.any(func(e): return e.kind != "boss" and not G.has_attack_sight(e, sight)): continue
		var trial := s.duplicate(false)
		trial.solids = solids
		trial.optional_surfaces = [shelf]
		var graph := G.navigation_graph(trial, false, base, [shelf], 0, true)
		var source := G.node_at(graph, s.start_position)
		var target := G.node_at(graph, point)
		if target < 0 or G.reachable_nodes(graph, source).has(target) or not G.reachable_nodes(graph, source, true).has(target): continue
		if not G.connectivity_errors(trial, false, graph).is_empty(): continue
		var damaged := G.navigation_graph(trial, true, damaged_base, [shelf], 0, true)
		if not G.connectivity_errors(trial, true, damaged).is_empty(): continue
		s.solids.append(shelf)
		s.optional_surfaces.append(shelf)
		for room: Dictionary in s.chambers:
			if room.rect.encloses(shelf): room.shelves.append(shelf)
		# Do not erode the launch/support area of an optional reward.
		s.detours.append({"required": wanted, "position": point, "shelf": shelf, "launch": edge.position, "profile": edge.profile})
		_append(s, point, "crystal")
		return

static func errors(s: Dictionary, graph: Dictionary = {}) -> Array[String]:
	var out: Array[String] = []
	if not s.has("loot"): return ["Missing loot"]
	var keys := 0
	var normal_chests := 0
	var abilities := {}
	var sectors := ability_sectors(s.seed)
	var terrain := s.duplicate(false)
	terrain.solids = s.solids + s.breakables
	if graph.is_empty(): graph = G.navigation_graph(terrain)
	var root := G.node_at(graph, s.start_position)
	var forward := G.reachable_nodes(graph, root)
	var backward := G.reachable_nodes(graph, root, true)
	out.append_array(M.errors(s, graph, _site_obstacles(s)))
	var ids := {}
	for item: Dictionary in s.loot:
		var copy := s.duplicate(false)
		copy.loot = s.loot.filter(func(other): return other.id != item.id)
		if ids.has(item.id) or not site_valid(copy, item.position): out.append("Loot overlap/identity")
		ids[item.id] = true
		if item.kind == "key": keys += 1
		if item.kind == "crystal": continue
		var node := G.node_at(graph, item.position)
		if not forward.has(node) or not backward.has(node): out.append("Main loot not initially reachable/returnable")
		if item.kind != "chest": continue
		for content: Dictionary in item.contents:
			if content.kind == "ability":
				if sectors.get(content.ability) != s.coord or abilities.has(content.ability): out.append("Ability chest assignment")
				abilities[content.ability] = true
			elif content.kind == "crystal": normal_chests += 1
	if keys > 1 or normal_chests > 1: out.append("Sector loot count")
	if s.coord == Vector2i.ZERO and keys != 1: out.append("Missing first key")
	for id: int in sectors:
		if sectors[id] == s.coord and not abilities.has(id): out.append("Missing ability chest")
	if s.get("optional_surfaces", []).size() != s.get("detours", []).size(): out.append("Optional surface metadata")
	for branch: Dictionary in s.get("detours", []):
		if branch.required not in [1,3,7] or not s.solids.has(branch.shelf) or not s.optional_surfaces.has(branch.shelf):
			out.append("Detour metadata")
			continue
		var node := G.node_at(graph,branch.position)
		var launch := G.node_at(graph,branch.launch)
		if node<0 or not forward.has(launch) or forward.has(node) or not backward.has(node): out.append("Detour initial/return route")
		if launch>=0 and G.ability_edge(graph.nodes[launch],branch.shelf,terrain.solids,branch.required).is_empty(): out.append("Detour ability route")
	return out
