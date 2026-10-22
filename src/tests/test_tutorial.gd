extends GdUnitTestSuite
## Calibration tutorial walkthrough for src/scenes/level.tscn:
## phase order (WASD -> WEAPONS -> SHOOT -> NULLWIDE -> JUMP -> DONE), input
## gates (movement+jump frozen in WASD, shooting blocked until SHOOT), the
## frozen tutorial targets (3 in SHOOT, 6 in NULLWIDE), the spawner hold,
## and the forced double jump that starts play.
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

	# NULLWIDE must be reachable on gamepad too (raw KEY_X once soft-locked
	# controller players here) — X key and gamepad X button both bound
	assert_bool(_has_physical_key("nullwide", KEY_X)).is_true()
	assert_bool(_has_joy_button("nullwide", JOY_BUTTON_X)).is_true()

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

	# --- SHOOT: 3 frozen enemies ahead, colors {WHITE, BLACK, RED}, types random ---
	var shoot_targets: Array = tutorial._spawned.duplicate()
	assert_int(shoot_targets.size()).is_equal(3)
	var colors: Array[int] = []
	for target in shoot_targets:
		assert_bool(target.is_in_group("enemy")).is_true()
		assert_bool(target.is_processing()).is_false() # frozen prop — AI off
		assert_bool(target.is_physics_processing()).is_false()
		assert_bool(target.global_position.y > player.global_position.y).is_true() # airborne
		colors.append(target.enemy_color_code)
	colors.sort()
	assert_int(colors[0]).is_equal(int(Weapon.GunColor.RED))
	assert_int(colors[1]).is_equal(int(Weapon.GunColor.BLACK))
	assert_int(colors[2]).is_equal(int(Weapon.GunColor.WHITE))

	# Wait out the weapon-change tween so the held gun is the real one.
	var synced := await _wait_until(
		func() -> bool: return player.weapon == player.weapons[player.weapon_index], 30)
	assert_bool(synced).is_true()
	var home: Vector3 = player.global_position

	# Kill all three: each target only dies to the matching gun color.
	for target in shoot_targets:
		var want: int = target.enemy_color_code
		var presses := 0
		while int(player.weapon.gun_color) != want and presses < 4:
			Input.action_press("weapon_toggle_next")
			for i in 2:
				await get_tree().physics_frame
			Input.action_release("weapon_toggle_next")
			await get_tree().physics_frame
			# player.weapon lags weapon_index by the change tween — wait it out.
			await _wait_until(func() -> bool: return int(player.weapon.gun_color) == want, 30)
			presses += 1
		assert_int(int(player.weapon.gun_color)).is_equal(want)

		# Hold fire until the target dies. Each shot kicks the camera and
		# shoves the player; with no mouse move in a headless run those never
		# recover, so snap the aim back before every attempt.
		var dead := false
		for attempt in 10:
			player.global_position = home
			await _send_mouse_look(0.01) # any motion event re-syncs pitch
			Input.action_press("shoot")
			for i in 8:
				await get_tree().physics_frame
			Input.action_release("shoot")
			for i in 6:
				await get_tree().physics_frame
			if not is_instance_valid(target) or target.is_queued_for_deletion():
				dead = true
				break
		assert_bool(dead).is_true()

	var nullwide := await _wait_until(
		func() -> bool: return tutorial.phase == TutorialScript.Phase.NULLWIDE, 30)
	assert_bool(nullwide).is_true()
	assert_str(tutorial._title.text).is_equal("HOLD X — RELEASE TO KILL")

	# --- NULLWIDE: 6 frozen targets in a fan, all the held gun's color ---
	var fan: Array = tutorial._spawned.duplicate()
	assert_int(fan.size()).is_equal(6)
	for target in fan:
		assert_bool(target.is_in_group("enemy")).is_true()
		assert_bool(target.is_processing()).is_false()
		assert_bool(target.global_position.y > player.global_position.y).is_true()
		assert_int(int(target.enemy_color_code)).is_equal(int(player.weapon.gun_color))

	# Ordinary bullets can't clear the fan — the release is the only kill path
	Input.action_press("shoot")
	for i in 6:
		await get_tree().physics_frame
	Input.action_release("shoot")
	for i in 6:
		await get_tree().physics_frame
	assert_int(tutorial.phase).is_equal(TutorialScript.Phase.NULLWIDE)

	# --- NULLWIDE: gamepad X hold locks the fan, one release clears it ---
	# Dispatched as a gamepad button because that's the path that soft-locked
	# before the fix; the X key flows through the identical action branch.
	_send_joy_button(JOY_BUTTON_X, true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_bool(player.nullwide_active).is_true()
	assert_int(player._nullwide_locks.size()).is_equal(6)
	_send_joy_button(JOY_BUTTON_X, false)
	var jump_phase := await _wait_until(
		func() -> bool: return tutorial.phase == TutorialScript.Phase.JUMP, 60)
	assert_bool(jump_phase).is_true()
	# Freed on exit — either already gone (typical after 60 frames) or still
	# pending deletion; calling a method on a freed object would crash.
	for target in fan:
		assert_bool(not is_instance_valid(target) or target.is_queued_for_deletion()).is_true()
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


## Dispatches a gamepad button through the real input pipeline — player.gd's
## NULLWIDE hold reads the "nullwide" InputMap action (gamepad X bound to it).
func _send_joy_button(button: JoyButton, pressed: bool) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
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


func _has_joy_button(action: StringName, button: JoyButton) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton and event.button_index == button:
			return true
	return false
