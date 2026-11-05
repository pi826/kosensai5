extends CanvasLayer
signal finished

const T := preload("res://scripts/tuning.gd")

var video_path := T.TITLE_DEMO_PATH
var video: VideoStreamPlayer
var demo_panel: Panel
var demo_label: Label
var hint_band: ColorRect
var hint: Label
var active := false
var blink_clock := 0.0

func _ready() -> void:
	layer = 20
	var shade := ColorRect.new()
	shade.color = Color.BLACK
	shade.position = Vector2.ZERO
	shade.size = T.VIEW_SIZE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	video = VideoStreamPlayer.new()
	video.position = Vector2.ZERO
	video.size = T.VIEW_SIZE
	video.expand = true
	video.autoplay = false
	video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	video.finished.connect(_on_video_finished)
	add_child(video)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Yu Gothic UI", "Meiryo", "Noto Sans CJK JP"])
	demo_panel = Panel.new()
	demo_panel.position = Vector2((T.VIEW_SIZE.x - 200.0) * 0.5, 116.0)
	demo_panel.size = Vector2(200, 64)
	demo_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var demo_style := StyleBoxFlat.new()
	demo_style.bg_color = Color(0, 0, 0, 0.62)
	demo_style.border_color = Color("ffe16a")
	demo_style.set_border_width_all(2)
	demo_style.set_corner_radius_all(8)
	demo_panel.add_theme_stylebox_override("panel", demo_style)
	demo_label = _make_label("DEMO", 44, Color("ffe16a"), font)
	demo_label.position = Vector2.ZERO
	demo_label.size = demo_panel.size
	demo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	demo_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	demo_panel.add_child(demo_label)
	add_child(demo_panel)
	hint_band = ColorRect.new()
	hint_band.color = Color(0, 0, 0, 0.7)
	hint_band.position = Vector2(0, 632)
	hint_band.size = Vector2(T.VIEW_SIZE.x, 52)
	hint_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint_band)
	hint = _make_label("キーを押すか画面をクリックするとすぐに遊べます", 22, Color("f4f0d8"), font)
	hint.position = hint_band.position
	hint.size = hint_band.size
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(hint)
	hide()
	set_process(false)

func _make_label(text: String, font_size: int, tint: Color, font: Font) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_override("font", font)
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", tint)
	result.add_theme_color_override("font_outline_color", Color("05080d"))
	result.add_theme_constant_override("outline_size", 6)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result

func start() -> bool:
	if active: return true
	if not FileAccess.file_exists(video_path): return false
	var stream := ResourceLoader.load(video_path)
	if not stream is VideoStream: return false
	video.stream = stream
	active = true
	blink_clock = 0.0
	demo_panel.modulate.a = 1.0
	show()
	set_process(true)
	video.play()
	return true

func stop() -> void:
	active = false
	if is_instance_valid(video):
		video.stop()
		video.stream = null
	set_process(false)
	hide()

func playing() -> bool:
	return active and visible

func _process(delta: float) -> void:
	if not active: return
	blink_clock = fmod(blink_clock + delta, 0.6)
	demo_panel.modulate.a = 1.0 if blink_clock < 0.3 else 0.55

func _on_video_finished() -> void:
	if not active: return
	stop()
	finished.emit()
