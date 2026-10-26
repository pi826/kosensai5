extends RefCounted
const T := preload("res://scripts/tuning.gd")
const Stream := preload("res://scripts/sector_stream.gd")

static func ready(tree: SceneTree, game: Node2D, point: Vector2, radius: int = 1) -> bool:
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	game.player.position = point
	game.player.velocity = Vector2.ZERO
	var at := Stream.coord_at(point)
	var bounds := Rect2(Vector2(at - Vector2i.ONE * radius) * T.SECTOR_SIZE, Vector2.ONE * (2 * radius + 1) * T.SECTOR_SIZE)
	for tick in range(20000):
		for enemy in tree.get_nodes_in_group("enemies"): enemy.set_physics_process(false)
		game.stream.request_around(point)
		game.stream.service()
		await tree.physics_frame
		await tree.process_frame
		if game.stream.contains_rect(bounds):
			game._update_camera(0, true)
			return true
		OS.delay_msec(1)
	return false

static func release(tree: SceneTree, game: Node2D) -> void:
	for enemy in tree.get_nodes_in_group("enemies"): enemy.set_physics_process(false)
	game.set_physics_process(true)
	game.player.set_physics_process(true)
	game.world.process_mode = Node.PROCESS_MODE_INHERIT
