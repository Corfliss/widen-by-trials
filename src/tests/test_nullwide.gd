extends SceneTree

## Headless verification for the hold-to-lock NULLWIDE mechanic: meter,
## locks (remembered on detection, sticky on cone-exit, forgotten on a
## lost line of sight), the color gate, and the Engine.time_scale slow-mo.
## Run with:
##   godot --headless --path . --script res://src/tests/test_nullwide.gd

const PLAYER_SCENE := "res://src/objects/player.tscn"

var failures := 0

## (from, to, color) tuples recorded from nullwide_shot_fired.
var shots: Array = []


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

	# Record shot-visual signals the beam spawner listens for
	player.nullwide_shot_fired.connect(
		func(from: Vector3, to: Vector3, color: Color) -> void:
			shots.append([from, to, color]))

	# Let _ready + a physics tick run
	await process_frame
	await physics_frame

	# Starts at the 120 gameplay FOV and holds there while inactive
	_check(is_equal_approx(player.camera.fovx, 120.0),
		"fovx starts at the 120 gameplay FOV (got %s)" % player.camera.fovx)
	_check(is_equal_approx(player.nullwide_meter, 100.0),
		"meter starts at 100 (got %s)" % player.nullwide_meter)
	_check(not player.nullwide_active, "NULLWIDE starts inactive")

	# Press: activates, fov lerps up, meter drains, slow-mo engages
	player.action_nullwide_press()
	_check(player.nullwide_active, "X press activates NULLWIDE")
	_check(is_equal_approx(Engine.time_scale, player.nullwide_time_scale),
		"slow-mo engages on press (time_scale=%s)" % Engine.time_scale)

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
	_check(is_equal_approx(Engine.time_scale, 1.0),
		"release restores real time (time_scale=%s)" % Engine.time_scale)
	_check(stub.damage_taken >= 9999,
		"release instantly kills the color-matched lock (took %s)" % stub.damage_taken)
	_check(player._nullwide_locks.is_empty(), "release clears the lock set")
	_check(shots.size() == 1,
		"a color-matched kill fires exactly one shot signal (got %d)" % shots.size())
	if shots.size() == 1:
		var shot_from: Vector3 = shots[0][0]
		var shot_to: Vector3 = shots[0][1]
		var shot_color: Color = shots[0][2]
		_check(shot_from.distance_to(player.camera.global_transform.origin) < 0.01,
			"shot starts at the camera eye")
		_check(shot_to.distance_to(stub.global_position) < 0.01,
			"shot ends at the killed enemy")
		_check(shot_color == player.get_node("/root/GameManager").gun_color_value(match_color),
			"shot is tinted with the gun color (got %s)" % shot_color)
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
	_check(shots.size() == 1,
		"a color-mismatched lock fires no shot signal (got %d)" % shots.size())
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
	_check(is_equal_approx(Engine.time_scale, 1.0),
		"meter-empty cancel restores real time (time_scale=%s)" % Engine.time_scale)
	player.action_nullwide_release()
	_check(doomed.damage_taken >= 9999,
		"release still kills the kept locks (took %s)" % doomed.damage_taken)
	doomed.queue_free()

	# Lock memory: remembered on detection, sticky on cone-exit,
	# forgotten only when line of sight is lost
	player.nullwide_meter = 100.0 # fresh hold budget after the cancel drain
	var sticky := _spawn_stub(match_color, player)
	player.action_nullwide_press()
	await physics_frame
	await physics_frame
	_check(player._nullwide_locks.has(sticky),
		"enemy in the cone is remembered on detection")
	sticky.position += Vector3.RIGHT * 10.0 # Walks out of the 30 deg cone
	await physics_frame
	await physics_frame
	_check(player._nullwide_locks.has(sticky),
		"leaving the cone does not forget the lock")
	var wall := _spawn_wall(player, sticky)
	await physics_frame
	await physics_frame
	_check(not player._nullwide_locks.has(sticky),
		"a wall between camera and enemy forgets the lock")
	player.action_nullwide_release()
	_check(sticky.damage_taken == 0,
		"release spares the forgotten lock (took %s)" % sticky.damage_taken)
	sticky.queue_free()
	wall.queue_free()

	# X does nothing at (true) zero meter — disable regen so the meter stays flat
	var regen: float = player.nullwide_regen
	player.nullwide_meter = 0.0
	player.nullwide_regen = 0.0
	player.action_nullwide_press()
	_check(not player.nullwide_active, "X press at 0 meter does nothing")
	_check(is_equal_approx(Engine.time_scale, 1.0),
		"no slow-mo without activation (time_scale=%s)" % Engine.time_scale)
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


## Box collider dropped on the camera->enemy ray to break line of sight.
func _spawn_wall(player, enemy: Node3D) -> StaticBody3D:
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 4, 4)
	shape.shape = box
	wall.add_child(shape)
	root.add_child(wall)
	wall.global_position = (player.camera.global_transform.origin \
		+ enemy.global_position) / 2.0
	return wall


func _check(ok: bool, message: String) -> void:
	if ok:
		print("  ok - %s" % message)
	else:
		failures += 1
		print("  FAIL - %s" % message)
