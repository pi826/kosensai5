extends RefCounted
## Spatial conversions never form an absolute pixel Vector2.
const T := preload("res://scripts/tuning.gd")

static func offset(at: Vector2i, origin: Vector2i) -> Vector2:
	return Vector2(at - origin) * T.SECTOR_SIZE

static func point(value: Vector2, origin: Vector2i) -> Dictionary:
	var at := Vector2i((value / T.SECTOR_SIZE).floor())
	return {"sector": origin + at, "local": value - Vector2(at) * T.SECTOR_SIZE}

static func unpack(value: Dictionary, origin: Vector2i) -> Vector2:
	return offset(value.sector, origin) + value.local

# Only generated geometry uses the recursive translation. Actor velocities,
# sizes, directions and clocks must never pass through it.
static func geometry(value, delta: Vector2):
	if value is Rect2: return Rect2(value.position + delta, value.size)
	if value is Vector2: return value + delta
	if value is Array:
		var out: Array = []
		for item in value:
			match typeof(item):
				TYPE_RECT2: out.append(Rect2(item.position + delta, item.size))
				TYPE_VECTOR2: out.append(item + delta)
				TYPE_ARRAY, TYPE_DICTIONARY: out.append(geometry(item, delta))
				_: out.append(item)
		return out
	if value is Dictionary:
		var out := {}
		for key in value:
			if (key is String or key is StringName) and key == "patrol":
				out[key] = value[key] + Vector2.ONE * delta.x
				continue
			var item = value[key]
			match typeof(item):
				TYPE_RECT2: out[key] = Rect2(item.position + delta, item.size)
				TYPE_VECTOR2: out[key] = item + delta
				TYPE_ARRAY, TYPE_DICTIONARY: out[key] = geometry(item, delta)
				_: out[key] = item
		return out
	return value

static func actor(saved: Dictionary, delta: Vector2) -> Dictionary:
	var out := saved.duplicate(true)
	if out.has("position"): out.position += delta
	if out.has("flight_center_y"): out.flight_center_y += delta.y
	return out

static func keyed(source: Dictionary, delta: Vector2i) -> Dictionary:
	var out := {}
	for key: Vector2i in source: out[key + delta] = source[key]
	return out

static func cells(source: Array, delta: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell: Vector2i in source: out.append(cell + delta)
	return out

static func snapshot(saved: Dictionary, delta: Vector2) -> Dictionary:
	var out := saved.duplicate(true)
	out.destroyed = keyed(saved.get("destroyed", {}), Vector2i(delta / T.TILE_SIZE))
	out.blocks = {}
	for key: Vector2 in saved.get("blocks", {}): out.blocks[key + delta] = saved.blocks[key]
	if saved.has("actors"):
		for id in saved.actors: out.actors[id] = actor(saved.actors[id], delta)
	return out

static func payload(p: Dictionary, delta: Vector2, shift_blocks: bool = true) -> void:
	p.data = geometry(p.data, delta)
	if shift_blocks:
		for block: Dictionary in p.blocks:
			block.bounds.position += delta
	p.shelves = geometry(p.shelves, delta)
	p.collisions = geometry(p.collisions, delta)

static func points(values: PackedVector2Array, delta: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in values: out.append(p + delta)
	return out
