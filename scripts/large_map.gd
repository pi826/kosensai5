extends "res://scripts/minimap.gd"
## Large map queries only sector buckets intersecting the viewport.
var center_point: Dictionary = {}
var zoom := T.LARGE_MAP_SCALE
var dragging := false
var last_draw_ms := 0.0
var drawn_fragments := 0
var close_button: Button
var help_label: Label
var _directions: Dictionary = {}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var heading := Label.new()
	heading.text = "探索の地図"
	heading.position = Vector2(32, 18)
	heading.add_theme_font_size_override("font_size", 28)
	add_child(heading)
	var legends := [[Vector2(50,62), "自分"], [Vector2(145,62), "ボス（白: ガーディアン / 金: ラスボス / 紫: 裏ボス）"], [Vector2(764,62), "撃破済み"], [Vector2(52,87), "商人（緑）"], [Vector2(224,87), "宝箱（金）"], [Vector2(364,87), "鍵（金）"], [Vector2(514,87), "能力の箱（紫）"], [Vector2(758,87), "区画境界"]]
	for entry: Array in legends:
		var legend := Label.new()
		legend.text = entry[1]
		legend.position = entry[0]
		legend.add_theme_font_size_override("font_size", 15)
		add_child(legend)
	close_button = Button.new()
	close_button.text = "閉じる"
	close_button.position = Vector2(1110, 24)
	close_button.size = Vector2(138, 36)
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(game.close_map)
	add_child(close_button)
	help_label = Label.new()
	help_label.position = Vector2(32, 638)
	help_label.add_theme_font_size_override("font_size", 16)
	add_child(help_label)
	set_process(false)

func open() -> void:
	center_on_player()
	zoom = T.LARGE_MAP_SCALE
	dragging = false
	_directions.clear()
	help_label.text = "↑↓←→ / WASD / ドラッグ 移動　 ホイール / + − 拡大縮小　 Space 自分へ\n%s / Esc 閉じる　（地図を開いている間は一時停止）" % game.key_bindings.get_binding_text("world_map")
	get_viewport().gui_release_focus()
	show()
	set_process(true)
	queue_redraw()

func center_on_player() -> void:
	center_point = game.stable_point(game.player.position)
	queue_redraw()

func map_area() -> Rect2:
	return Rect2(24, 112, 1232, 508)

func world_area() -> Rect2:
	var extent := map_area().size / zoom
	return Rect2(game.local_point(center_point) - extent / 2, extent)

func pan(pixels: Vector2) -> void:
	center_point = game.stable_point(game.local_point(center_point) + pixels / zoom)
	queue_redraw()

func change_zoom(factor: float, anchor: Vector2 = map_area().get_center()) -> void:
	var before := zoom
	zoom = clampf(zoom * factor, T.LARGE_MAP_MIN_SCALE, T.LARGE_MAP_MAX_SCALE)
	var offset := anchor - map_area().get_center()
	center_point = game.stable_point(game.local_point(center_point) + offset / before - offset / zoom)
	queue_redraw()

func displayed_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if center_point.is_empty(): return out
	var area := world_area()
	var first: Vector2i = Vector2i((area.position / T.SECTOR_SIZE).floor()) + game.origin_sector
	var last: Vector2i = Vector2i((area.end / T.SECTOR_SIZE).floor()) + game.origin_sector
	var map_origin: Vector2i = game.map_origin()
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			for stable: Vector2i in game.explored_by_sector.get(Vector2i(x, y), {}):
				var cell := stable - map_origin
				if area.intersects(Rect2(Vector2(cell) * CELL_SIZE, Vector2.ONE * CELL_SIZE)): out.append(cell)
	return out

func _geometry_for_cell(cell: Vector2i) -> Array:
	var geometry: Array = game.explored_geometry.get(cell + game.map_origin(), [])
	drawn_fragments += geometry.size()
	return preload("res://scripts/origin_shift.gd").geometry(geometry, Vector2(cell) * CELL_SIZE)

func _panel_style() -> StyleBoxFlat:
	var style := super._panel_style()
	style.bg_color = Color("080e15")
	return style

func _draw() -> void:
	if center_point.is_empty(): return
	var started := Time.get_ticks_usec()
	drawn_fragments = 0
	super._draw()
	# Same image silhouettes as map markers; each missing ID keeps its fallback.
	if not draw_mark("map_player",Vector2(38,73),20): draw_circle(Vector2(38,73),3,Color.WHITE)
	for at: Vector2 in [Vector2(134,73), Vector2(500,98)]:
		if draw_mark("map_boss" if at.y==73 else "map_chest",at,20): continue
		draw_colored_polygon(PackedVector2Array([at+Vector2(0,-4),at+Vector2(4,0),at+Vector2(0,4),at+Vector2(-4,0)]), Color("f0d8b2") if at.y == 73 else T.CRYSTAL_COLOR)
	draw_polyline(PackedVector2Array([Vector2(746,73),Vector2(750,77),Vector2(757,69)]),Color("d9f4d9"),2)
	if not draw_mark("map_merchant",Vector2(38,98),20): draw_rect(Rect2(34,96,8,6),T.MERCHANT_COLOR,false,1.5)
	if not draw_mark("map_chest",Vector2(210,98),20): draw_rect(Rect2(206,95,8,6),Color("ffdf80"),false,1.5)
	if not draw_mark("map_key",Vector2(350,98),20):
		draw_circle(Vector2(348,95),3,Color("ffdf80"),false,1.5,true)
		draw_line(Vector2(350,97),Vector2(356,103),Color("ffdf80"),1.5)
	draw_line(Vector2(736,98),Vector2(751,98),Color("9fb7cc"),1)
	var world := world_area()
	var area := map_area()
	# The subtraction happens in nearby relative coordinates, before scaling.
	var first := Vector2i((world.position / T.SECTOR_SIZE).floor())
	var last := Vector2i((world.end / T.SECTOR_SIZE).ceil())
	for x in range(first.x, last.x + 1):
		var screen_x: float = area.position.x + (x * T.SECTOR_SIZE.x - world.position.x) * zoom
		if screen_x < area.position.x or screen_x > area.end.x: continue
		draw_line(Vector2(screen_x, area.position.y), Vector2(screen_x, area.end.y), Color("9fb7cc25"), 1)
	for y in range(first.y, last.y + 1):
		var screen_y: float = area.position.y + (y * T.SECTOR_SIZE.y - world.position.y) * zoom
		if screen_y < area.position.y or screen_y > area.end.y: continue
		draw_line(Vector2(area.position.x, screen_y), Vector2(area.end.x, screen_y), Color("9fb7cc25"), 1)
	var player_at: Vector2 = area.get_center() + (game.player.position - world.get_center()) * zoom
	if area.grow(-10).has_point(player_at):
		draw_arc(player_at, 8, 0, TAU, 24, Color.WHITE, 2, true)
		draw_line(player_at-Vector2(12,0),player_at-Vector2(5,0),Color.WHITE,2)
		draw_line(player_at+Vector2(5,0),player_at+Vector2(12,0),Color.WHITE,2)
	last_draw_ms = (Time.get_ticks_usec() - started) / 1000.0

func _process(delta: float) -> void:
	if not visible:
		_directions.clear()
		set_process(false)
		return
	var direction := Vector2.ZERO
	for code: int in _directions:
		match code:
			KEY_LEFT, KEY_A: direction.x -= 1
			KEY_RIGHT, KEY_D: direction.x += 1
			KEY_UP, KEY_W: direction.y -= 1
			KEY_DOWN, KEY_S: direction.y += 1
	if direction != Vector2.ZERO: pan(direction.normalized() * T.LARGE_MAP_PAN_SPEED * delta)

func _input(event: InputEvent) -> void:
	if not visible: return
	if event is InputEventKey:
		var code: int = event.keycode if event.keycode != 0 else event.physical_keycode
		# The configured close key wins over navigation keys.
		if event.pressed and not event.echo and (event.is_action_pressed("world_map") or code == KEY_ESCAPE or event.is_action_pressed("pause_game")):
			game.close_map()
		elif code in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_A, KEY_D, KEY_W, KEY_S]:
			if event.pressed: _directions[code] = true
			else: _directions.erase(code)
		elif event.pressed and not event.echo:
			if code == KEY_SPACE: center_on_player()
			elif code in [KEY_PLUS, KEY_EQUAL, KEY_KP_ADD]: change_zoom(T.LARGE_MAP_ZOOM_STEP)
			elif code in [KEY_MINUS, KEY_KP_SUBTRACT]: change_zoom(1.0 / T.LARGE_MAP_ZOOM_STEP)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed and map_area().has_point(event.position)
		elif event.pressed and map_area().has_point(event.position):
			if event.button_index == MOUSE_BUTTON_WHEEL_UP: change_zoom(T.LARGE_MAP_ZOOM_STEP, event.position)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: change_zoom(1.0 / T.LARGE_MAP_ZOOM_STEP, event.position)
		# Allow the close button to receive its native GUI click.
		if not close_button.get_global_rect().has_point(event.position): get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and dragging:
		pan(-event.relative)
		get_viewport().set_input_as_handled()
