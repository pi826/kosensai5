extends "res://tests/stream_driver.gd"

func release():
	super.release()
	Input.action_release("dash")

func step(command: Dictionary) -> bool:
	if command.action != "ability_jump": return await super.step(command)
	error = ""
	if not await walk(command.position.x): return false
	if absf(point().y - command.position.y) > 2:
		error = "ability launch floor differs: %s expected %s" % [point(), command.position]
		return false
	input("jump", true)
	jumps += 1
	var airborne := false
	var profile: Dictionary = command.profile
	# Extra unlocked abilities must not force glide on a non-gliding schedule.
	# Release at the apex, after the variable-height cut can affect the arc.
	var release_frame: int = (profile.second + ceili(T.JUMP_SPEED*T.DOUBLE_JUMP_RATIO/T.GRAVITY*60)) if profile.second >= 0 else ceili(T.JUMP_SPEED/T.GRAVITY*60)
	for frame in range(T.ABILITY_FLIGHT_FRAMES):
		if not profile.glide and frame == release_frame: input("jump",false)
		if frame == profile.second:
			input("jump", false)
			input("jump", true)
			jumps += 1
		if frame == profile.dash: input("dash", true)
		if frame == profile.dash + 1: input("dash", false)
		steer(command.target.x)
		await tick()
		if not game.player.is_on_floor(): airborne = true
		elif airborne: break
	input("jump", false)
	input("dash", false)
	await stop()
	if not airborne or absf(point().y - command.target.y) > 2:
		error = "ability landing differs: %s expected %s profile=%s" % [point(), command.target, profile]
		return false
	return await walk(command.target.x)
