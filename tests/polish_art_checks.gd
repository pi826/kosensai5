extends RefCounted
const Art := preload("res://scripts/sprite_art.gd")
const S := preload("res://scripts/sector_generator.gd")
const T := preload("res://scripts/tuning.gd")

static func boundaries(check: Callable, terrain: Node2D) -> void:
	var extent := Vector2i(T.SECTOR_SIZE/32)
	var near_count := 0
	var far_count := 0
	var samples := 0
	var stage_before: Dictionary = terrain.stage.duplicate(true)
	var origin_before: Vector2i = terrain.stage.get("origin_sector",Vector2i.ZERO)
	for axis in range(2):
		for side in [-1,1]:
			for seed_value in range(1,33):
				for coord in [Vector2i.ZERO,Vector2i(-3,-2),Vector2i(4096,-4096)]:
					var neighbor: Vector2i = coord
					neighbor[axis] += side
					var own := S.region_at(seed_value,coord)
					var other := S.region_at(seed_value,neighbor)
					for i in range(12,44):
						var cell: Vector2i = coord*extent
						cell[1-axis] += i
						for distance in range(4):
							cell[axis] = coord[axis]*extent[axis]+(distance if side<0 else extent[axis]-1-distance)
							var region := Art.tile_visual_region(cell,seed_value)
							if distance>=2:
								check.call(region==own,"outside two-cell strip retains region")
							else:
								check.call(region in [own,other],"boundary uses only its two adjacent regions")
								if own!=other:
									if distance==0:
										samples+=1
										if region==other: near_count+=1
									elif region==other: far_count+=1
							# Use the real coordinate conversion before/after origin movement.
							terrain.stage.origin_sector=Vector2i.ZERO
							var a: Vector2i = terrain.cell_at(terrain.pixel_of_cell(cell)+Vector2(16,16))
							terrain.stage.origin_sector=coord+Vector2i(2,-3)
							var b: Vector2i = terrain.cell_at(terrain.pixel_of_cell(cell)+Vector2(16,16))
							check.call(a==cell and b==cell and Art.tile_visual_region(a,seed_value)==Art.tile_visual_region(b,seed_value),"stable world-cell texture across origin shift")
	check.call(samples>1000,"boundary distribution includes distinct regional neighbors")
	check.call(absf(float(near_count)/samples-.375)<.04,"closest row mixes about 3/8")
	check.call(absf(float(far_count)/samples-.125)<.04 and near_count>far_count,"second row mixes about 1/8, less than closest row")
	# Corners may select any of the four genuinely neighboring sectors.
	for coord in [Vector2i.ZERO,Vector2i(-2,-3)]:
		for offset in [Vector2i.ZERO,Vector2i(1,1),Vector2i(-1,-1)]:
			var cell: Vector2i = coord*extent+offset
			check.call(Art.tile_visual_region(cell,37) in [0,1,2],"corner selects a valid regional tile")
	terrain.stage=stage_before
	check.call(terrain.stage.get("origin_sector",Vector2i.ZERO)==origin_before,"boundary checks restore stage")

static func hud(check: Callable, ui: CanvasLayer) -> void:
	var labels: Array = [ui.location_label,ui.objective_label,ui.boss_arrow_label,ui.equipment_hint,ui.loot_notice,ui.controls_label,ui.boss_label,ui.hint_label,ui.announcement_label]
	labels.append_array(ui.equipment_labels.values())
	for label: Label in labels:
		var color := label.get_theme_color("font_outline_color")
		check.call(label.get_theme_constant("outline_size")>=6,"HUD prompt has a six-pixel dark outline")
		check.call(color.a==1 and maxf(color.r,maxf(color.g,color.b))<.07,"HUD outline is opaque and dark over every regional tile")

static func image_stats(image: Image, mask: Image = null) -> Dictionary:
	var total := Vector3.ZERO
	var sum_luma := 0.0
	var sum_square := 0.0
	var count := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if mask!=null and mask.get_pixel(x,y).r<.5: continue
			var c := image.get_pixel(x,y)
			if c.a<.5: continue
			var rgb := Vector3(c.r,c.g,c.b)*255
			var luma := rgb.dot(Vector3(.2126,.7152,.0722))
			total+=rgb; sum_luma+=luma; sum_square+=luma*luma; count+=1
	if count==0: return {"pixels":0,"mean_rgb":[0,0,0],"mean_luma":0,"std_luma":0}
	var mean := total/count
	var light := sum_luma/count
	return {"pixels":count,"mean_rgb":[mean.x,mean.y,mean.z],"mean_luma":light,"std_luma":sqrt(maxf(0,sum_square/count-light*light))}

static func image_periods(image: Image, mask: Image, check: Callable) -> Dictionary:
	var result := {}
	for shift in [Vector2i(128,0),Vector2i(0,128),Vector2i(128,128)]:
		var sums := [0.0,0.0,0.0,0.0,0.0]
		var count := 0
		var matches := 0
		for y in range(0,image.get_height()-shift.y,2):
			for x in range(0,image.get_width()-shift.x,2):
				if mask.get_pixel(x,y).r<.5 or mask.get_pixel(x+shift.x,y+shift.y).r<.5: continue
				var a := image.get_pixel(x,y)
				var b := image.get_pixel(x+shift.x,y+shift.y)
				var u := Vector3(a.r,a.g,a.b).dot(Vector3(.2126,.7152,.0722))
				var v := Vector3(b.r,b.g,b.b).dot(Vector3(.2126,.7152,.0722))
				sums[0]+=u; sums[1]+=v; sums[2]+=u*u; sums[3]+=v*v; sums[4]+=u*v
				count+=1
				if a==b: matches+=1
		var correlation: float = (sums[4]-sums[0]*sums[1]/count)/sqrt(maxf(.000001,(sums[2]-sums[0]*sums[0]/count)*(sums[3]-sums[1]*sums[1]/count)))
		var rate := float(matches)/count
		check.call(count>10000 and correlation<.6 and rate<.6,"rendered rock has no strong four-cell repeat: "+str(shift))
		result[str(shift)]={"samples":count,"luminance_correlation":correlation,"identical_pixel_fraction":rate}
	return result

static func sheets(check: Callable) -> void:
	# Called only by the normal-renderer run_tests branch. Headless art never
	# reads or decodes image data.
	var water := Image.load_from_file(Art.terrain_path(0))
	check.call(image_stats(water.get_region(Rect2i(8160,0,32,128))).std_luma>=18,"waterway interior PNG preserves stone relief")
	for region in range(3):
		var rock := Image.load_from_file(Art.terrain_path(region))
		var rock_stats := image_stats(rock.get_region(Rect2i(8160,0,32,128)))
		for layer in range(2):
			var im := Image.load_from_file("res://assets/art/backdrops/%d-%d.png" % [region,layer])
			var stats := image_stats(im)
			var rgb: Array = stats.mean_rgb
			check.call(stats.mean_luma<=30,"background layer stays below luminance 30")
			check.call(stats.std_luma<rock_stats.std_luma,"background contrast stays below foreground rock")
			check.call((rgb[1]-rgb[0]>=6 if region==0 else rgb[2]-rgb[1]>=8 if region==1 else rgb[0]-rgb[2]>=8),"background layer has its regional color")
			var valid := true
			var checker := 0
			for y in range(im.get_height()):
				for x in range(im.get_width()):
					var a := im.get_pixel(x,y).a
					if a!=0 and a!=1: valid=false
					if x<im.get_width()-1 and y<im.get_height()-1:
						var b := im.get_pixel(x+1,y).a
						if a!=b and im.get_pixel(x,y+1).a==b and im.get_pixel(x+1,y+1).a==a: checker+=1
			check.call(valid,"binary background alpha")
			check.call(checker==0,"no two-by-two alpha checkerboard in middle scenery")
			check.call(im.get_region(Rect2i(0,0,1,1024)).get_data()==im.get_region(Rect2i(511,0,1,1024)).get_data(),"background horizontal repeat edges match")
			check.call(im.get_region(Rect2i(0,0,512,1)).get_data()==im.get_region(Rect2i(0,1023,512,1)).get_data(),"background vertical repeat edges match")
