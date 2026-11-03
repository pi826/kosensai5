extends Control
## Presentation-only skin. Existing controls own input, focus, values and text.
const Art := preload("res://scripts/sprite_art.gd")
const T := preload("res://scripts/tuning.gd")
var ui: CanvasLayer
var serial := -1
var age := 0.0
var _skinned_age := 0.0
var cursor_at := Vector2.ZERO
var focus_id := 0
var was_enabled := false

static func remember(control: Control, state: String, stylebox: StyleBox) -> void:
	var originals: Dictionary = control.get_meta("art_originals",{})
	if not originals.has(state): originals[state]=stylebox
	control.set_meta("art_originals",originals)

static func baseline(control: Control, state: String) -> StyleBox:
	remember(control,state,control.get_theme_stylebox(state))
	return control.get_meta("art_originals")[state]

static func image(name: String) -> Texture2D:
	var path := "res://assets/art/ui/"+name+".png"
	return Art.texture(path,path)

static func style(name: String, original: StyleBox = null) -> StyleBox:
	var texture := image(name)
	if texture == null: return original
	var result := StyleBoxTexture.new()
	result.texture = texture
	for edge in range(4):
		result.set_texture_margin(edge,10)
		result.set_content_margin(edge,original.get_content_margin(edge) if original != null else 10)
	return result

static func apply(control: Control) -> void:
	control.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if control is Button:
		for state in ["normal","hover","pressed","hover_pressed","disabled","focus"]:
			var name: String = "button-"+({"hover":"selected","hover_pressed":"pressed","disabled":"normal"}.get(state,state))
			var original := baseline(control,state)
			var replacement := style(name,original)
			if replacement != null: control.add_theme_stylebox_override(state,replacement)
	elif control is Panel or control is PanelContainer:
		var replacement := style("panel",baseline(control,"panel"))
		if replacement != null: control.add_theme_stylebox_override("panel",replacement)
	elif control is LineEdit:
		for state in ["normal","focus"]:
			var replacement := style("button-"+state,baseline(control,state))
			if replacement != null: control.add_theme_stylebox_override(state,replacement)
	elif control is HSlider:
		for state in ["slider","grabber_area","grabber_area_highlight"]:
			var replacement := style("button-normal" if state=="slider" else "button-selected",baseline(control,state))
			if replacement != null: control.add_theme_stylebox_override(state,replacement)
		var grabber := image("grabber")
		if grabber!=null:
			for state in ["grabber","grabber_highlight","grabber_disabled"]:
				if not control.has_meta("art_icon_"+state): control.set_meta("art_icon_"+state,control.get_theme_icon(state))
				control.add_theme_icon_override(state,grabber)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().node_added.connect(_node_added)

func _node_added(node: Node) -> void:
	if Art.enabled() and node is Control and ui.is_ancestor_of(node): apply.call_deferred(node)

func _skin(node: Node) -> void:
	if node is Control: apply(node)
	for child in node.get_children(): _skin(child)

func _restore(node: Node) -> void:
	if node is Control:
		for state: String in node.get_meta("art_originals",{}): node.add_theme_stylebox_override(state,node.get_meta("art_originals")[state])
		for state in ["grabber","grabber_highlight","grabber_disabled"]:
			if node.has_meta("art_icon_"+state): node.add_theme_icon_override(state,node.get_meta("art_icon_"+state))
	for child in node.get_children(): _restore(child)

func _process(delta: float) -> void:
	if was_enabled != Art.enabled():
		was_enabled = Art.enabled()
		if not was_enabled:
			_restore(ui.get_child(0))
			ui.menu_title.modulate.a=1.0
			queue_redraw()
		else: serial=-1
	if not Art.enabled(): return
	age += delta
	if ui.game.state=="title": ui.menu_title.modulate.a=0.0 if image("logo")!=null else 1.0
	if serial != Art.upload_serial and (Art._pending.is_empty() or age - _skinned_age >= 0.25):
		serial = Art.upload_serial
		_skinned_age = age
		_skin(ui.get_child(0))
	var focus := get_viewport().gui_get_focus_owner()
	if is_instance_valid(focus) and focus.is_visible_in_tree():
		var target := focus.get_global_rect().position + Vector2(-26,focus.size.y/2)
		if focus_id == 0: cursor_at = target
		cursor_at = cursor_at.lerp(target,1.0-exp(-delta*24))
		focus_id = focus.get_instance_id()
	else: focus_id = 0
	queue_redraw()

func object_icon(name: String, at: Vector2, extent: float = 24, tint: Color = Color.WHITE) -> bool:
	var desc := Art.description(name,"idle")
	if desc.is_empty(): return false
	var sheet := Art.texture(desc.path,desc.path)
	if sheet == null:
		var center := at+Vector2.ONE*extent/2
		draw_rect(Rect2(at+Vector2(4,4),Vector2.ONE*(extent-8)),Color("263c4b"))
		match name:
			"heart": draw_circle(center,extent/4,Color("ff75a5"))
			"key":
				draw_circle(center-Vector2(2,2),extent/5,Color("ffdf80"),false,2)
				draw_line(center,center+Vector2(7,7),Color("ffdf80"),2)
			"crystal": draw_colored_polygon(PackedVector2Array([center+Vector2(0,-8),center+Vector2(5,0),center+Vector2(0,8),center+Vector2(-5,0)]),Color("b495f2"))
			_: draw_rect(Rect2(at+Vector2(5,5),Vector2.ONE*(extent-10)),tint,false,2)
		return false
	var cell := Vector2(desc.cell[0],desc.cell[1])
	draw_texture_rect_region(sheet,Rect2(at,Vector2.ONE*extent),Rect2(Vector2(Art.frame_index(desc,age),desc.row)*cell,cell),tint)
	return true

func _draw() -> void:
	if not Art.enabled(): return
	var game: Node2D = ui.game
	var overlay_open: bool = ui.settings_overlay.visible or ui.audio_overlay.visible or ui.shop_panel.visible or ui.large_map.visible
	if ui.menu.visible and game.state == "title" and not overlay_open:
		var logo := image("logo")
		if logo != null: draw_texture_rect(logo,Rect2(370,86,540,64),false)
		var robot := image("title-robot")
		if robot != null:
			draw_texture_rect_region(robot,Rect2(28,170,224,448),Rect2(0,0,256,512))
			draw_texture_rect_region(robot,Rect2(1028,170,224,448),Rect2(0,0,256,512))
	if not ui.menu.visible and game.state == "playing" and not overlay_open:
		object_icon("heart",Vector2(40,30),26)
		if is_instance_valid(game.player):
			var player: Node2D = game.player
			for i in range(player.charge_capacity()):
				object_icon("missile",Vector2(584+i*24,25),26,Color.WHITE if i<player.homing_charges else Color(.3,.3,.3))
			for i in range(4):
				var at := Vector2(524+i*55,62)
				var frame := style("button-normal")
				if frame != null: draw_style_box(frame,Rect2(at,Vector2(53,12)))
				else: draw_rect(Rect2(at,Vector2(53,12)),Color("1c3547"))
				if float(player.gauge)/player.absorptions_per_charge() >= float(i+1)/4:
					var fill := style("button-selected")
					if fill != null: draw_style_box(fill,Rect2(at+Vector2(2,2),Vector2(49,8)))
					else: draw_rect(Rect2(at+Vector2(2,2),Vector2(49,8)),T.COLORS[player.polarity])
			if not game.is_tutorial():
				object_icon("crystal",Vector2(844,80),22)
				object_icon("key",Vector2(984,80),22)
				object_icon("potion",Vector2(1104,80),22)
				var font: Font = ui.loot_label.get_theme_font("font")
				for entry in [[Vector2(870,98),str(game.crystals)],[Vector2(1010,98),str(game.keys)],[Vector2(1132,98),"%d/%d" % [game.potions,T.POTION_CAPACITY]]]:
					draw_string(font,entry[0],entry[1],HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("dce9ef"))
				var row := 0
				for slot: String in ui.equipment_labels:
					var id: String = player.equipment[slot]
					object_icon(id if not id.is_empty() else slot,Vector2(878,236+row*26),24)
					row += 1
	if focus_id != 0:
		Art.draw_frame(self,"cursor","idle",0,age,cursor_at,1)
