extends CanvasLayer
## Real-time presentation. Persistent center uses integer sector + local point.
const T := preload("res://scripts/tuning.gd")
var game: Node
var override_enabled := -1
var active := false
var age := 0.0
var hold := 0.0
var depth := 1.0
var entry_factor := 1.0
var amplitude := 22.0
var center := {}
var saved_time := 1.0
var saved_speed := 1.0
var saved_ticks := 60
var started_usec := 0
var last_usec := 0
var ring_age := 0.0
var ring_travel := 1000.0
var rect: ColorRect
var material_fx: ShaderMaterial

func _ready() -> void:
	layer = 0 # World defaults to canvas 0; HUD defaults to CanvasLayer 1.
	process_priority = -1000
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() != "headless":
		rect = ColorRect.new()
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.size = get_viewport().get_visible_rect().size
		material_fx = ShaderMaterial.new()
		material_fx.shader = preload("res://scripts/boss_impact.gdshader")
		rect.material = material_fx
		add_child(rect)
	hide()
	set_process(false)

func allowed() -> bool:
	return (override_enabled == 1 or override_enabled < 0 and DisplayServer.get_name() != "headless") and game.state == "playing" and not game.is_tutorial() and not is_instance_valid(game.tutorial_session)

func start(point: Vector2, role: String) -> void:
	if not allowed() or not role in ["guardian", "final", "secret"]: return
	entry_factor = Engine.time_scale / saved_time if active else 1.0
	if not active:
		saved_time = Engine.time_scale
		saved_speed = AudioServer.playback_speed_scale
		saved_ticks = Engine.physics_ticks_per_second
		active = true
		started_usec = Time.get_ticks_usec()
	last_usec = Time.get_ticks_usec()
	age = 0.0
	ring_age = 0.0
	hold = T.IMPACT_GUARDIAN_HOLD if role == "guardian" else T.IMPACT_MAJOR_HOLD
	depth = T.IMPACT_GUARDIAN_SCALE if role == "guardian" else T.IMPACT_MAJOR_SCALE
	amplitude = T.IMPACT_GUARDIAN_AMPLITUDE if role == "guardian" else T.IMPACT_MAJOR_AMPLITUDE
	center = game.stable_point(point)
	if rect != null:
		var screen := screen_center()
		var size := get_viewport().get_visible_rect().size
		ring_travel = 0.0
		for corner: Vector2 in [Vector2.ZERO, Vector2(size.x, 0), Vector2(0, size.y), size]:
			ring_travel = maxf(ring_travel, screen.distance_to(corner))
		ring_travel += 90.0 # Leave room for the last band's width outside the image.
	show()
	set_process(true)
	update_visual()

func factor(at: float) -> float:
	if at < T.IMPACT_DOWN: return lerpf(entry_factor, depth, smoothstep(0.0, T.IMPACT_DOWN, at))
	if at < T.IMPACT_DOWN+hold: return depth
	return lerpf(depth, 1.0, smoothstep(0.0, T.IMPACT_UP, at-T.IMPACT_DOWN-hold))

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	advance((now-last_usec)/1000000.0)
	last_usec = now

func advance(real_delta: float) -> void:
	if not active: return
	if game.state != "playing" or game.is_tutorial() or is_instance_valid(game.player) and game.player.dead:
		cancel()
		return
	age += real_delta
	ring_age += real_delta
	var scale := factor(age)
	Engine.time_scale = saved_time*scale
	AudioServer.playback_speed_scale = saved_speed*scale
	# Godot 4.7.2 keeps physics callbacks at the configured REAL tick rate;
	# time_scale reduces delta, not callbacks/sec (see impact_realtime_test).
	# Raising ticks to 60/scale actually produced ~202 real callbacks/sec.
	Engine.physics_ticks_per_second = saved_ticks
	update_visual()
	if age >= maxf(T.IMPACT_DOWN+hold+T.IMPACT_UP, T.IMPACT_RING_SECONDS):
		cancel()
		if game.ending and game.boss_cycle.phase == "complete": game.call_deferred("_finish_run")

func screen_center() -> Vector2:
	return game.get_viewport().get_canvas_transform()*game.local_point(center)

func update_visual() -> void:
	if rect == null: return
	var size := get_viewport().get_visible_rect().size
	rect.size = size
	game.impact_shake = Vector2(sin(ring_age*85.0), cos(ring_age*103.0))*5.0*maxf(0.0, 1.0-ring_age/0.3)
	game.apply_camera_offset()
	game.camera.force_update_scroll()
	material_fx.set_shader_parameter("center_px", screen_center())
	material_fx.set_shader_parameter("viewport_px", size)
	material_fx.set_shader_parameter("age", ring_age)
	material_fx.set_shader_parameter("amplitude", amplitude)
	material_fx.set_shader_parameter("travel_px", ring_travel)
	material_fx.set_shader_parameter("ring_seconds", T.IMPACT_RING_SECONDS)
	if ring_age >= T.IMPACT_RING_SECONDS: hide()

func cancel() -> void:
	if active:
		Engine.time_scale = saved_time
		Engine.physics_ticks_per_second = saved_ticks
		AudioServer.playback_speed_scale = saved_speed
	active = false
	game.impact_shake = Vector2.ZERO
	if is_instance_valid(game.camera): game.apply_camera_offset()
	hide()
	set_process(false)

func _exit_tree() -> void:
	cancel()
