extends SceneTree

## Headless verification for the NULLWIDE mechanic. Run with:
##   godot --headless --path . --script res://src/tests/test_nullwide.gd

const PLAYER_SCENE := "res://src/objects/player.tscn"

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var player = load(PLAYER_SCENE).instantiate()
	root.add_child(player)

	# Let _ready + a physics tick run
	await process_frame
	await physics_frame

	_check(is_equal_approx(player.camera.fovx, 90.0),
		"camera fovx starts at 90 (got %s)" % player.camera.fovx)
	_check(is_equal_approx(player.nullwide_meter, 100.0),
		"meter starts at 100 (got %s)" % player.nullwide_meter)

	# Activate: fov lerps up, meter drains
	player.action_nullwide()
	_check(player.nullwide_active, "X press activates NULLWIDE")

	for _i in 30:
		await physics_frame
	_check(player.camera.fovx > 200.0,
		"fovx lerps upward toward 359.9 (got %s)" % player.camera.fovx)
	_check(player.nullwide_meter < 100.0,
		"meter drains while active (got %s)" % player.nullwide_meter)

	# Early toggle: second press deactivates
	player.nullwide_meter = 50.0
	player.action_nullwide()
	_check(not player.nullwide_active, "second X press deactivates early")

	# Drain to empty -> auto-deactivate and revert toward 90
	player.action_nullwide() # activate again
	player.nullwide_meter = 0.005
	await physics_frame
	await physics_frame
	_check(not player.nullwide_active, "meter empty auto-deactivates NULLWIDE")

	# X does nothing at (true) zero meter — disable regen so the meter stays flat
	var regen: float = player.nullwide_regen
	player.nullwide_meter = 0.0
	player.nullwide_regen = 0.0
	player.action_nullwide()
	_check(not player.nullwide_active, "X press at 0 meter does nothing")
	player.nullwide_regen = regen

	# Regen while inactive
	var before_regen: float = player.nullwide_meter
	await physics_frame
	await physics_frame
	_check(player.nullwide_meter > before_regen,
		"meter regenerates while inactive (%s -> %s)" % [before_regen, player.nullwide_meter])

	if failures == 0:
		print("PASS: all NULLWIDE checks passed")
	else:
		print("FAIL: %d check(s) failed" % failures)
	quit(1 if failures > 0 else 0)


func _check(ok: bool, message: String) -> void:
	if ok:
		print("  ok - %s" % message)
	else:
		failures += 1
		print("  FAIL - %s" % message)
