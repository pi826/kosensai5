extends "res://tests/test_tree.gd"
const S := preload("res://scripts/sector_generator.gd")
const G := preload("res://scripts/stage_generator.gd")
const L := preload("res://scripts/loot_generator.gd")
const M := preload("res://scripts/merchant_generator.gd")
const T := preload("res://scripts/tuning.gd")
var checks := 0
var failures: Array[String] = []
var merchants := 0
var contents := {}

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)

func inspect(s: Dictionary) -> void:
	check(S.validate(s).is_empty(), "geometry, initial routes, NPC and loot separation %d %s" % [s.seed,s.coord])
	for npc: Dictionary in s.merchants:
		var body := Rect2(npc.position - T.MERCHANT_SIZE / 2, T.MERCHANT_SIZE)
		check(not G._any_intersects(s.solids+s.breakables, body), "merchant body clear of terrain and blocks")
		check(not G._any_intersects(L._site_obstacles(s), body), "merchant clear of enemy bodies, patrols and flying lanes")
		check((s.hearts+s.loot).all(func(item): return item.position.distance_to(npc.position)>=T.LOOT_SPACING), "merchant separated from hearts, keys, chests and rewards")
		check(npc.stock.has("potion") and npc.stock.has("key"), "every merchant sells consumables")
		check(npc.stock.size() in range(5,8) and npc.stock.all(func(id): return npc.stock.count(id)==1), "3-5 distinct equipment items")
	for item: Dictionary in s.loot:
		if item.kind == "chest": contents[item.contents[0].kind] = true

func run() -> void:
	for seed_value in range(32):
		test_progress()
		var s := S.generate(seed_value, Vector2i.ZERO)
		check(s.merchants.size()==1, "one starting merchant seed=%d" % seed_value)
		check(s.merchants[0].stock == ["potion","key","rapid","shell","homing"], "starter stock includes one item from each slot")
		inspect(s)
	for index in range(200):
		test_progress()
		var at := Vector2i(index%20-10, index/20+8)
		var s := S.generate(700+index, at)
		merchants += s.merchants.size()
		inspect(s)
		if index%25==0:
			check(S.signature(s)==S.signature(S.generate(700+index,at)), "generation reproducible including NPC and stock")
			print("MERCHANT GENERATION PROGRESS ", index)
	check(merchants>=20 and merchants<=60, "roughly one merchant per five sectors: %d/200" % merchants)
	check(contents.has("potion") and contents.has("equipment") and contents.has("crystal"), "ordinary chests generate potions, equipment and crystals")
	for seed_value in [1,37,2026]:
		var s := S.generate_fallback(seed_value, Vector2i.ZERO)
		inspect(s)
		check(s.merchants.size()==1, "fallback also guarantees a reachable starting merchant")
	var original := S.generate(37, Vector2i.ZERO)
	var bad := original.duplicate(true)
	bad.merchants.clear()
	check(not S.validate(bad).is_empty(), "validator rejects missing starting merchant")
	bad = original.duplicate(true)
	bad.merchants[0].position = bad.loot[0].position
	check(not S.validate(bad).is_empty(), "validator rejects overlapping NPC and key")
	for at: Vector2i in [Vector2i(-99999,200000),Vector2i(100000,-200000)]:
		var first := S.generate(37,at)
		check(S.signature(first)==S.signature(S.generate(37,at)), "far signed coordinate determinism")
	print("MERCHANT GENERATION: %d checks, %d failures; merchants=%d/200" % [checks,failures.size(),merchants])
	quit(0 if failures.is_empty() else 1)
