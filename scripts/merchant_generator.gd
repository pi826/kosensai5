extends RefCounted
## Pure sector-local placement and stock; no run state or global RNG.
const T := preload("res://scripts/tuning.gd")
const G := preload("res://scripts/stage_generator.gd")

static func rng_for(seed_value: int, at: Vector2i) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d:%d:%d:merchant" % [seed_value, at.x, at.y]).hash()
	return rng

static func stock(seed_value: int, at: Vector2i) -> Array:
	if at == Vector2i.ZERO: return ["potion", "key"] + T.STARTER_EQUIPMENT
	var rng := rng_for(seed_value, at)
	var ids := T.EQUIPMENT.keys()
	G._shuffle(ids, rng)
	return ["potion", "key"] + ids.slice(0, rng.randi_range(T.MERCHANT_EQUIPMENT_MIN, T.MERCHANT_EQUIPMENT_MAX))

static func site_valid(s: Dictionary, point: Vector2, blocked: Array) -> bool:
	var body := Rect2(point - T.MERCHANT_SIZE / 2, T.MERCHANT_SIZE)
	if not s.chambers.any(func(r): return r.kind != "boss" and r.rect.encloses(body.grow(8))): return false
	if G._embedded(point, T.MERCHANT_SIZE, s.solids + s.breakables): return false
	if not G._supported(point, T.MERCHANT_SIZE, s.solids): return false
	var protection := body.grow(T.TILE_SIZE)
	if s.breakables.any(func(r): return r.grow(1).intersects(protection)): return false
	if G._any_intersects(s.erodible_surfaces, protection): return false
	if G._any_intersects(blocked, body): return false
	for item: Dictionary in s.hearts + s.get("loot", []):
		if item.position.distance_to(point) < T.LOOT_SPACING: return false
	return true

static func decorate(s: Dictionary, sites: Array[Vector2], blocked: Array) -> void:
	s.merchants = []
	var rng := rng_for(s.seed, s.coord)
	if s.coord != Vector2i.ZERO and rng.randf() >= T.MERCHANT_CHANCE: return
	var candidates := sites.duplicate()
	G._shuffle(candidates, rng)
	if s.coord == Vector2i.ZERO:
		candidates.sort_custom(func(a, b): return a.distance_squared_to(s.start_position) < b.distance_squared_to(s.start_position))
	for point: Vector2 in candidates:
		if point.distance_to(s.start_position) < T.LOOT_SPACING: continue
		if not site_valid(s, point, blocked): continue
		s.merchants.append({"id": "merchant:%d:%d" % [roundi(point.x), roundi(point.y)], "position": point, "stock": stock(s.seed, s.coord)})
		# Keep the standing surface intact and prevent builders walling in the NPC.
		s.protected_rects.append(Rect2(point - T.MERCHANT_SIZE / 2, T.MERCHANT_SIZE).grow(T.TILE_SIZE))
		return

static func errors(s: Dictionary, graph: Dictionary, blocked: Array) -> Array[String]:
	var out: Array[String] = []
	if s.coord == Vector2i.ZERO and s.get("merchants", []).size() != 1: out.append("Missing first merchant")
	if s.get("merchants", []).size() > 1: out.append("Too many merchants")
	var root := G.node_at(graph, s.start_position)
	var forward := G._search(graph, root)
	var backward := G._search(graph, root, true)
	for merchant: Dictionary in s.get("merchants", []):
		if not site_valid(s, merchant.position, blocked): out.append("Merchant overlap")
		var node := G.node_at(graph, merchant.position)
		if not forward.has(node) or not backward.has(node): out.append("Merchant initial round trip")
		if merchant.stock != stock(s.seed, s.coord): out.append("Merchant stock mismatch")
	return out
