extends SceneTree

## Headless verification for the hold-to-lock NULLWIDE mechanic. Run with:
##   godot --headless --path . --script res://src/tests/test_nullwide.gd

const PLAYER_SCENE := "res://src/objects/player.tscn"

var failures := 0


## Minimal enemy stand-in: joins the "enemy" group, records damage calls.
class StubEnemy:
	extends Node3D
	var enemy_color_code: int = Weapon.GunColor.WHITE
	var damage_taken: int = 0

	func damage(amount: int) -> void:
		damage_taken += amount


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var player = load(PLAYER_SCENE).instantiate()
	root.add_child(player)

	# Let _ready + a physics tick run
	await process_frame
	await physics_frame

	# Not == 90: the inactive lerp toward the 120 gameplay FOV already ticks
	# once before this point, depending on headless physics timing.
	_check(player.camera.fovx < 120.0,
		"fovx starts below the NULLWIDE target (got %s)" % player.camera.fovx)
	_check(is_equal_approx(player.nullwide_meter, 100.0),
		"meter starts at 100 (got %s)" % player.nullwide_meter)
	_check(not player.nullwide_active, "NULLWIDE starts inactive")

	# Press: activates, fov lerps up, meter drains
	player.action_nullwide_press()
	_check(player.nullwide_active, "X press activates NULLWIDE")

	for _i in 30:
		await physics_frame
	_check(player.camera.fovx > 200.0,
		"fovx lerps upward toward 359.9 (got %s)" % player.camera.fovx)
	_check(player.nullwide_meter < 100.0,
		"meter drains while holding (got %s)" % player.nullwide_meter)

	# An enemy in the aim cone locks; releasing kills the color-matched lock
	var match_color: int = int(player.weapon.gun_color)
	var stub := _spawn_stub(match_color, player)
	await physics_frame
	await physics_frame
	_check(player._nullwide_locks.size() == 1,
		"enemy dead ahead is locked while holding (locks=%d)" % player._nullwide_locks.size())
	player.action_nullwide_release()
	_check(not player.nullwide_active, "release deactivates NULLWIDE")
	_check(stub.damage_taken >= 9999,
		"release instantly kills the color-matched lock (took %s)" % stub.damage_taken)
	_check(player._nullwide_locks.is_empty(), "release clears the lock set")
	stub.queue_free()

	# Color gate: a mismatched enemy in the cone survives the release
	var mismatch_color := (match_color + 1) % 3 # GunColor has 3 entries
	var survivor := _spawn_stub(mismatch_color, player)
	player.action_nullwide_press()
	await physics_frame
	await physics_frame
	_check(player._nullwide_locks.size() == 1,
		"mismatched enemy is still locked (locking is color-blind)")
	player.action_nullwide_release()
	_check(survivor.damage_taken == 0,
		"release spares the color-mismatched lock (took %s)" % survivor.damage_taken)
	survivor.queue_free()

	# Meter empty mid-hold: hold cancels, but release still kills the locks
	var doomed := _spawn_stub(match_color, player)
	player.nullwide_meter = 0.005
	player.action_nullwide_press()
	await physics_frame
	await physics_frame
	_check(not player.nullwide_active, "meter empty auto-cancels the hold")
	_check(player._nullwide_locks.size() == 1,
		"locks acquired before the cancel are kept")
	player.action_nullwide_release()
	_check(doomed.damage_taken >= 9999,
		"release still kills the kept locks (took %s)" % doomed.damage_taken)
	doomed.queue_free()

	# X does nothing at (true) zero meter — disable regen so the meter stays flat
	var regen: float = player.nullwide_regen
	player.nullwide_meter = 0.0
	player.nullwide_regen = 0.0
	player.action_nullwide_press()
	_check(not player.nullwide_active, "X press at 0 meter does nothing")
	player.action_nullwide_release() # must be a safe no-op
	player.nullwide_regen = regen

	# Regen while inactive (scarce: 8/s, well below the old 15/s)
	_check(is_equal_approx(player.nullwide_regen, 8.0),
		"regen is the scarce 8/s (got %s)" % player.nullwide_regen)
	var before_regen: float = player.nullwide_meter
	await physics_frame
	await physics_frame
	_check(player.nullwide_meter > before_regen,
		"meter regenerates while inactive (%s -> %s)" % [before_regen, player.nullwide_meter])

	await process_frame # let the queue_free'd stubs actually die before quit

	if failures == 0:
		print("PASS: all NULLWIDE checks passed")
	else:
		print("FAIL: %d check(s) failed" % failures)
	quit(1 if failures > 0 else 0)


## Places a stub enemy directly ahead of the camera (inside the lock cone,
## unobstructed) and joins it to the "enemy" group the lock scan reads.
func _spawn_stub(color: int, player) -> StubEnemy:
	var stub := StubEnemy.new()
	stub.enemy_color_code = color
	root.add_child(stub)
	stub.add_to_group("enemy")
	stub.global_position = player.camera.global_transform.origin \
		- player.camera.global_transform.basis.z * 5.0
	return stub


func _check(ok: bool, message: String) -> void:
	if ok:
		print("  ok - %s" % message)
	else:
		failures += 1
		print("  FAIL - %s" % message)
