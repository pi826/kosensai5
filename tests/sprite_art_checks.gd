extends RefCounted
const Art := preload("res://scripts/sprite_art.gd")

static func run(check: Callable) -> void:
	var metadata := Art.metadata()
	var expected := {"idle":4,"run":8,"jump":2,"fall":2,"land":2,"dash":3,"glide":3,"wall":3,"hurt":2,"death":6,"switch":3}
	for kind: String in Art.STATES:
		for state: String in Art.STATES[kind]:
			var info := Art.description(kind,state)
			check.call(not info.is_empty(),kind+" has "+state)
			if info.is_empty(): continue
			var boss := kind in ["guardian","final","secret"]
			check.call(Vector2(info.cell[0],info.cell[1]) == (Vector2(320,320) if boss else Vector2(96,96)) and Vector2(info.pivot[0],info.pivot[1]) == (Vector2(160,275) if boss else Vector2(48,88)),kind+" cell and foot anchor "+state)
			check.call(info.frames > 0 and info.frames <= 8 and info.fps > 0,kind+" valid animation "+state)
			if kind == "player": check.call(info.frames == expected[state],"required player frame count "+state)
			for color in ["blue","orange"]:
				var path: String = info.path.replace("{color}",color)
				# Read only the PNG IHDR, never construct/decode an Image in headless.
				var file := FileAccess.open(path,FileAccess.READ)
				check.call(file != null,"PNG exists "+path)
				if file == null: continue
				file.big_endian = true
				file.seek(16)
				var width := file.get_32()
				var height := file.get_32()
				check.call(width == 8*info.cell[0] and height >= (info.row+1)*info.cell[1],"PNG dimensions contain state "+state)
	for state: String in expected:
		check.call(metadata.has("player_arm/"+state),"replacement arm covers "+state)
	for state in ["shoot_front","shoot_up","shoot_down"]:
		check.call(metadata.has("player_arm/"+state),"directional firing arm "+state)
	var before := Art.image_read_attempts
	if DisplayServer.get_name() == "headless":
		for selected in ["shapes","sprites"]:
			Art.mode_override = selected
			check.call(not Art.enabled(),"headless disables images in "+selected)
			check.call(Art.texture("headless","res://assets/art/player/blue.png") == null,"headless never decodes PNG")
			check.call(Art.icon(0) == null,"headless HUD uses fallback")
		check.call(Art.image_read_attempts == before,"headless image-read counter unchanged")
		Art.mode_override = ""
	var land := Art.description("player","land")
	check.call(Art.frame_index(land,100.0) == 1,"one-shot landing clamps at final frame")
	check.call(Art.frame_index(Art.description("player","run"),8.0/12.0) == 0,"run animation loops")
	check.call(Art.cell_hash(Vector2i(-400,900),37) == Art.cell_hash(Vector2i(-400,900),37),"variant hash stable for negative world coordinates")
	for divisor in [3,4]:
		for shift in [Vector2i(4,0),Vector2i(0,4),Vector2i(4,4)]:
			var matches := 0
			for y in range(16):
				for x in range(16):
					var cell := Vector2i(x,y)
					if Art.cell_hash(cell,37)%divisor == Art.cell_hash(cell+shift,37)%divisor: matches += 1
			var rate := float(matches)/256
			check.call(absf(rate-1.0/divisor)<0.12,"tile variants have no period four: %s / %d = %.3f" % [shift,divisor,rate])
	var extra := {"bullet_player":["flight"],"bullet_player_homing":["flight"],"bullet_enemy":["flight"],"bullet_enemy_homing":["flight"],"laser":["warning","beam"],"bomb":["flight"],"wall":["idle","appear","vanish"],"boss_arrow":["idle"],"burst":["defeat","hit","absorb","switch","land","jump","bomb","dash"]}
	for kind: String in extra:
		for state: String in extra[kind]:
			var info := Art.description(kind,state)
			check.call(not info.is_empty(),"stage 2 sheet "+kind+"/"+state)
			if info.is_empty(): continue
			for color in ["blue","orange"] if info.path.contains("{color}") else ["blue"]:
				var path: String=info.path.replace("{color}",color)
				var file := FileAccess.open(path,FileAccess.READ)
				check.call(file != null,"stage 2 PNG exists "+path)
				if file == null: continue
				file.big_endian=true; file.seek(16)
				check.call(file.get_32()==8*int(info.cell[0]) and file.get_32()>=(info.row+1)*info.cell[1],"stage 2 dimensions "+kind+"/"+state)
	for role in ["guardian","final","secret"]:
		var death := Art.description(role,"death")
		check.call(float(death.frames)/float(death.fps)>=1.0,"boss death spans one game second "+role)
	var stage3 := {"heart":["idle"],"crystal":["idle"],"key":["idle"],"potion":["idle"],"chest":["idle","locked","opening","open"],"merchant":["idle"],"target":["idle"],"cursor":["idle"],"map_player":["idle"],"map_boss":["idle"],"map_chest":["idle"],"map_key":["idle"],"map_merchant":["idle"],"missile":["idle"]}
	for id: String in preload("res://scripts/tuning.gd").EQUIPMENT: stage3[id]=["idle"]
	for kind: String in stage3:
		for state: String in stage3[kind]:
			var info := Art.description(kind,state)
			check.call(not info.is_empty(),"stage 3 all states "+kind+"/"+state)
			if info.is_empty(): continue
			check.call(info.frames>0 and info.frames<=8 and info.fps>0,"stage 3 frames "+kind+"/"+state)
			var file := FileAccess.open(info.path,FileAccess.READ)
			check.call(file!=null,"stage 3 sheet exists "+kind)
			if file!=null:
				file.big_endian=true; file.seek(16)
				check.call(file.get_32()==8*int(info.cell[0]) and file.get_32()>=(info.row+1)*info.cell[1],"stage 3 sheet dimensions "+kind)
	for region in range(3):
		for special in [false,true]: check.call(FileAccess.file_exists(Art.terrain_path(region,special)),"regional terrain sheet "+str(region))
		for layer in range(2): check.call(FileAccess.file_exists("res://assets/art/backdrops/%d-%d.png" % [region,layer]),"two regional parallax layers")
	check.call(not Art.description("chest","opening").loop and Art.frame_index(Art.description("chest","opening"),10)==3,"chest opening clamps without changing contents")
	check.call(Art.LOAD_BUDGET_USEC==1500,"threaded art service keeps 1.5ms budget")
	for id in ["panel","button-normal","button-selected","button-pressed","button-focus","logo","title-robot","grabber"]:
		check.call(FileAccess.file_exists("res://assets/art/ui/"+id+".png"),"all menu art states "+id)
	if DisplayServer.get_name()=="headless":
		for id in ["heart","key","merchant","cursor"]:
			var info := Art.description(id,"idle")
			check.call(Art.texture(info.path,info.path)==null,"headless stage 3 never reads "+id)
	Art.prewarm(); Art.service_loading()
	if DisplayServer.get_name()=="headless": check.call(Art._pending.is_empty() and Art.image_read_attempts==before,"headless prewarm does no work")
