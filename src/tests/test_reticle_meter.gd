extends SceneTree
## Headless gate for the reticle meter arcs (src/scripts/reticle_meter.gd).
##
## Run:  godot --headless --path . -s src/tests/test_reticle_meter.gd
## Exit 0 = GREEN, 1 = RED.

const PLAYER_SCENE := "res://src/objects/player.tscn"

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var player = load(PLAYER_SCENE).instantiate()
	root.add_child(player)
	await process_frame
	await physics_frame

	var meter = player.get_node_or_null("HUD/ReticleMeter")
	_check(meter != null, "HUD/ReticleMeter exists on the player")
	_check(player.get_node_or_null("HUD/Health") == null,
		"old numeric Health label is gone")
	if meter == null:
		quit(1)
		return

	_check(meter.hp_color.r > meter.hp_color.g and meter.hp_color.r > meter.hp_color.b,
		"HP arc color is red")
	_check(is_equal_approx(meter.nullwide_color.r, meter.nullwide_color.g)
		and is_equal_approx(meter.nullwide_color.g, meter.nullwide_color.b)
		and meter.nullwide_color.r > 0.5, "NULLWIDE arc color is white")
	_check(meter.opacity > 0.0 and meter.opacity < 1.0,
		"arcs are semi-transparent (opacity %s)" % meter.opacity)

	# HP follows the existing health_updated signal
	player.health_updated.emit(40)
	await process_frame
	_check(is_equal_approx(meter.health_ratio, 0.4),
		"health 40/100 -> ratio 0.4 (got %s)" % meter.health_ratio)

	# NULLWIDE meter follows the player value (no regen while we probe)
	player.nullwide_regen = 0.0
	player.nullwide_meter = 25.0
	await process_frame
	_check(is_equal_approx(meter.meter_ratio, 0.25),
		"meter 25/100 -> ratio 0.25 (got %s)" % meter.meter_ratio)

	# Ratios clamp to 0..1
	meter.meter_ratio = 2.0
	_check(is_equal_approx(meter.meter_ratio, 1.0), "meter ratio clamps above 1")
	meter.health_ratio = -1.0
	_check(is_equal_approx(meter.health_ratio, 0.0), "health ratio clamps below 0")

	if failures == 0:
		print("VERDICT: GREEN  (reticle meter wired to HP + NULLWIDE)")
		quit(0)
	else:
		print("VERDICT: RED  (%d check(s) failed)" % failures)
		quit(1)


func _check(ok: bool, message: String) -> void:
	if ok:
		print("  ok - %s" % message)
	else:
		failures += 1
		print("  FAIL - %s" % message)
