extends Node2D
## Fixed quadratic curve; only terrain clipping is refreshed at ignition.
const T := preload("res://scripts/tuning.gd")

var game: Node2D
var source: Node2D
var polarity := 0
var curve := PackedVector2Array()
var path := PackedVector2Array()
var phase := "warning"
var elapsed := 0.0
var remaining := T.LASER_DURATION
var contacted := false
var damage := T.LASER_DAMAGE

func build_curve(start: Vector2, target: Vector2, facing: int) -> void:
	curve = curve_points(start, target, facing)

# Shared with stage generation so sight checks need no node instance.
static func curve_points(start: Vector2, target: Vector2, facing: int) -> PackedVector2Array:
	var chord := target - start
	var normal := Vector2(chord.y, -chord.x).normalized()
	if absf(chord.x) <= chord.length() * T.LASER_VERTICAL_EPSILON:
		normal = Vector2(facing, 0)
	elif normal.y > 0:
		normal = -normal
	var control := (start + target) / 2 + normal * clampf(chord.length() * T.LASER_CURVE_RATIO, T.LASER_CURVE_MIN, T.LASER_CURVE_MAX)
	var points := PackedVector2Array()
	for index in range(T.LASER_SEGMENTS + 1):
		var t := float(index) / T.LASER_SEGMENTS
		points.append((1 - t) * (1 - t) * start + 2 * (1 - t) * t * control + t * t * target)
	return points

func clip_path() -> void:
	path.clear()
	if curve.is_empty() or not game.loaded_contains(curve[0]):
		return
	path.append(curve[0])
	for index in range(1, curve.size()):
		var start := path[-1]
		var end := curve[index]
		var outside: bool = not game.loaded_contains(end)
		if outside:
			var inside := start
			var beyond := end
			for step in range(20):
				var middle := (inside + beyond) / 2
				if game.loaded_contains(middle): inside = middle
				else: beyond = middle
			end = inside
		var ray := PhysicsRayQueryParameters2D.create(start, end, 1 | T.PLATFORM_LAYER)
		ray.hit_from_inside = true
		var hit := get_world_2d().direct_space_state.intersect_ray(ray)
		path.append(hit.position if not hit.is_empty() else end)
		if outside or not hit.is_empty():
			break
	queue_redraw()

func fire() -> void:
	clip_path()
	phase = "beam"
	remaining = T.LASER_DURATION
	queue_redraw()

func cancel() -> void:
	phase = "cancelled"
	hide()
	queue_free()

func _physics_process(delta: float) -> void:
	if not is_instance_valid(source) or source.dead or source.is_queued_for_deletion() or not game.is_on_screen(source.global_position, 20):
		cancel()
		return
	elapsed += delta
	if phase == "beam":
		if not contacted and is_instance_valid(game.player) and not game.player.dead:
			var body := Rect2(game.player.global_position - game.player.body_size / 2, game.player.body_size)
			for index in range(1, path.size()):
				if segment_touches_rect(path[index - 1], path[index], body, T.LASER_RADIUS):
					contacted = true
					game.player.receive_hit(polarity, damage)
					break
		remaining -= delta
		if remaining <= 0:
			cancel()
	queue_redraw()

static func segment_touches_rect(start: Vector2, end: Vector2, rect: Rect2, radius: float) -> bool:
	if rect.has_point(start) or rect.has_point(end):
		return true
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for index in range(4):
		if Geometry2D.segment_intersects_segment(start, end, corners[index], corners[(index + 1) % 4]) != null:
			return true
		var closest := Geometry2D.get_closest_point_to_segment(corners[index], start, end)
		if closest.distance_squared_to(corners[index]) <= radius * radius:
			return true
	for endpoint: Vector2 in [start, end]:
		if endpoint.distance_squared_to(endpoint.clamp(rect.position, rect.end)) <= radius * radius:
			return true
	return false

func _draw() -> void:
	if path.size() < 2 or phase == "cancelled":
		return
	var tint: Color = T.COLORS[polarity]
	if phase == "warning":
		tint.a = 0.35 if int(elapsed * 12) % 2 == 0 else 0.8
		for index in range(1, path.size(), 2):
			draw_line(to_local(path[index - 1]), to_local(path[index]), tint, 2, true)
	else:
		var local_path := PackedVector2Array()
		for point in path:
			local_path.append(to_local(point))
		draw_polyline(local_path, Color(tint, 0.25), T.LASER_RADIUS * 3, true)
		draw_polyline(local_path, tint, T.LASER_RADIUS * 2, true)
		draw_polyline(local_path, Color.WHITE, 2, true)
