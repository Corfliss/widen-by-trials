extends GdUnitTestSuite
## Calibration tutorial walkthrough for src/scenes/level.tscn:
## phase order (WASD -> WEAPONS -> SHOOT -> NULLWIDE -> JUMP -> DONE), input
## gates (movement+jump frozen in WASD, shooting blocked until SHOOT), the
## dummy target, the spawner hold, and the forced double jump that starts play.
## Run: godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a src/tests/test_tutorial.gd
##
## Note: just_pressed/just_released edges last the whole frame, so press and
## release are separated by awaited physics frames — same as in test_repeater_tap.

const LEVEL := "res://src/scenes/level.tscn"
const TutorialScript := preload("res://src/scenes/tutorial/tutorial.gd")


func test_tutorial_walkthrough() -> void:
	var level = auto_free(load(LEVEL).instantiate())
	add_child(level)
	var player = level.get_node("Player")
	var tutorial = level.get_node("Tutorial")
	var spawner = level.get_node("Spawner")

	# --- Phase WASD: movement, jump and shooting frozen, no enemies ---
	assert_int(tutorial.phase).is_equal(TutorialScript.Phase.WASD)
	assert_bool(player.movement_locked).is_true()
	assert_bool(player.shooting_locked).is_true()
	assert_int(spawner._wave).is_equal(0)
	assert_bool(tutorial._keys_row.visible).is_true()
	assert_bool(tutorial._weapons_row.visible).is_false()

	var grounded := await _wait_until(func() -> bool: return player.is_on_floor(), 300)
	assert_bool(grounded).is_true() # gates are tested on solid ground

	# WASD is observed but ignored: position must not budge horizontally
	var x0: float = player.global_position.x
	var z0: float = player.global_position.z
	Input.action_press("move_right")
	for i in 10:
		await get_tree().physics_frame
	Input.action_release("move_right")
	await get_tree().physics_frame
	assert_bool(absf(player.global_position.x - x0) < 0.01).is_true()
	assert_bool(absf(player.global_position.z - z0) < 0.01).is_true()

	# Jump is frozen too: pressing it must not leave the floor
	Input.action_press("jump")
	for i in 5:
		await get_tree().physics_frame
	Input.action_release("jump")
	await get_tree().physics_frame
	assert_bool(player.is_on_floor()).is_true()

	# Shooting blocked: hold-to-fire weapon never starts the cooldown
	Input.action_press("shoot")
	for i in 3:
		await get_tree().physics_frame
	assert_bool(player.blaster_cooldown.is_stopped()).is_true()
	Input.action_release("shoot")
	await get_tree().physics_frame

	# --- Intersection check: keys alone do NOT advance (look still owed) ---
	# move_right was already checked off by the frozen test above — that's
	# by design: observed even while movement is locked. W A S completes
	# the key half; look travel is still 0, so the phase must hold.
	for action in ["move_forward", "move_left", "move_back"]:
		Input.action_press(action)
		for i in 2:
			await get_tree().physics_frame
		Input.action_release(action)
		await get_tree().physics_frame
	assert_int(tutorial.phase).is_equal(TutorialScript.Phase.WASD)
	assert_bool(player.movement_locked).is_true()

	# Look alone does NOT advance either — send it now to complete the
	# intersection -> WEAPONS, movement unlocked
	await _send_mouse_look(250.0)
	assert_int(tutorial.phase).is_equal(TutorialScript.Phase.WEAPONS)
	assert_bool(player.movement_locked).is_false()
	assert_bool(player.shooting_locked).is_true() # still frozen
	assert_str(tutorial._title.text).is_equal("SWITCH WEAPONS — Q / E / scroll")
	assert_bool(tutorial._keys_row.visible).is_false()
	assert_bool(tutorial._weapons_row.visible).is_true()
	var key_w: Label = tutorial._key_labels[&"move_forward"]
	assert_bool(key_w.modulate == TutorialScript.COLOR_LIT).is_true()

	# The spec's "Q / E or scroll" must really be bound in the InputMap
	assert_bool(_has_physical_key("weapon_toggle_next", KEY_E)).is_true()
	assert_bool(_has_physical_key("weapon_toggle_prev", KEY_Q)).is_true()
	assert_bool(_has_wheel("weapon_toggle_next", MOUSE_BUTTON_WHEEL_DOWN)).is_true()
	assert_bool(_has_wheel("weapon_toggle_prev", MOUSE_BUTTON_WHEEL_UP)).is_true()

	# --- Weapon cycle: starting weapon counts, two "next" presses visit all 3 ---
	for i in 2:
		Input.action_press("weapon_toggle_next")
		for j in 2:
			await get_tree().physics_frame
		Input.action_release("weapon_toggle_next")
		await get_tree().physics_frame
	assert_int(tutorial.phase).is_equal(TutorialScript.Phase.SHOOT)
	assert_int(player.weapon_index).is_equal(2)
	assert_bool(player.shooting_locked).is_false() # shot gate opens on entry
	assert_str(tutorial._title.text).is_equal("SHOOT THE TARGET")
	assert_bool(tutorial._weapons_row.visible).is_false()

	# A dummy stands in the enemy group ahead of the player, color-matched
	var dummy = tutorial._dummy
	assert_bool(is_instance_valid(dummy)).is_true()
	assert_bool(dummy.is_in_group("enemy")).is_true()
	assert_int(dummy.enemy_color_code).is_equal(int(player.weapon.gun_color))

	# --- SHOOT: a landed hit completes the phase ---
	# Held fire in a retry loop: the hitscan spread jitter can miss a 2 m box
	var shot_hit := false
	for attempt in 10:
		Input.action_press("shoot")
		for i in 6:
			await get_tree().physics_frame
		Input.action_release("shoot")
		for i in 6:
			await get_tree().physics_frame
		if tutorial.phase == TutorialScript.Phase.NULLWIDE:
			shot_hit = true
			break
	assert_bool(shot_hit).is_true()
	assert_str(tutorial._title.text).is_equal("HOLD X — RELEASE TO KILL")

	# Ordinary bullets during NULLWIDE don't skip the phase (damage < 9999)
	Input.action_press("shoot")
	for i in 6:
		await get_tree().physics_frame
	Input.action_release("shoot")
	for i in 6:
		await get_tree().physics_frame
	assert_int(tutorial.phase).is_equal(TutorialScript.Phase.NULLWIDE)

	# --- NULLWIDE: X press locks the dummy, release kill completes the phase ---
	_send_key(KEY_X, true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_bool(player.nullwide_active).is_true()
	assert_int(player._nullwide_locks.size()).is_equal(1)
	_send_key(KEY_X, false)
	var jump_phase := await _wait_until(
		func() -> bool: return tutorial.phase == TutorialScript.Phase.JUMP, 60)
	assert_bool(jump_phase).is_true()
	# Freed on exit — either already gone (typical after 60 frames) or still
	# pending deletion; calling a method on a freed object would crash.
	assert_bool(not is_instance_valid(dummy) or dummy.is_queued_for_deletion()).is_true()
	assert_int(spawner._wave).is_equal(0) # waves still held

	# --- Phase JUMP: a single jump + landing does NOT start play ---
	assert_str(tutorial._title.text).is_equal("DOUBLE JUMP TO BEGIN")
	assert_bool(tutorial._jump_hint.visible).is_true()
	Input.action_press("jump")
	for i in 2:
		await get_tree().physics_frame
	Input.action_release("jump")
	var left_floor := await _wait_until(func() -> bool: return not player.is_on_floor(), 60)
	assert_bool(left_floor).is_true()
	var landed := await _wait_until(func() -> bool: return player.is_on_floor(), 180)
	assert_bool(landed).is_true()
	assert_int(tutorial.phase).is_equal(TutorialScript.Phase.JUMP)
	assert_int(spawner._wave).is_equal(0) # waves still held

	# --- The forced double jump starts play ---
	Input.action_press("jump")
	for i in 2:
		await get_tree().physics_frame
	Input.action_release("jump")
	var airborne := await _wait_until(func() -> bool: return not player.is_on_floor(), 60)
	assert_bool(airborne).is_true()
	Input.action_press("jump")
	for i in 2:
		await get_tree().physics_frame
	Input.action_release("jump")
	await get_tree().physics_frame

	assert_int(tutorial.phase).is_equal(TutorialScript.Phase.DONE)
	assert_bool(player.movement_locked).is_false()
	assert_bool(player.shooting_locked).is_false()
	assert_int(spawner._wave).is_equal(1)
	assert_int(spawner._alive.size()).is_equal(6) # base_count default


## Awaits physics frames until cond() holds or max_frames elapses.
## Returns whether cond() actually became true.
func _wait_until(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		await get_tree().physics_frame
		if cond.call():
			return true
	return cond.call()


## Dispatches cumulative mouse motion through the real input pipeline
## (tutorial._input consumes InputEventMouseMotion events).
func _send_mouse_look(travel: float) -> void:
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(travel, 0.0)
	Input.parse_input_event(motion)
	for i in 3:
		await get_tree().process_frame


## Dispatches a raw key through the real input pipeline — player.gd's NULLWIDE
## hold reads InputEventKey.keycode directly (no InputMap action).
func _send_key(key: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = key
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _has_physical_key(action: StringName, key: Key) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and event.physical_keycode == key:
			return true
	return false


func _has_wheel(action: StringName, button: MouseButton) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventMouseButton and event.button_index == button:
			return true
	return false
