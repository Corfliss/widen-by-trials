extends GdUnitTestSuite
## Calibration tutorial walkthrough for src/scenes/level.tscn:
## phase order (LOOK -> MOVE -> WEAPONS -> JUMP -> DONE), input gates
## (WASD frozen in LOOK, shooting blocked until DONE), the spawner hold,
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

	# --- Phase LOOK: movement frozen, shooting blocked, no enemies ---
	assert_int(tutorial.phase).is_equal(TutorialScript.Phase.LOOK)
	assert_bool(player.movement_locked).is_true()
	assert_bool(player.shooting_locked).is_true()
	assert_int(spawner._wave).is_equal(0)
	assert_bool(tutorial._keys_row.visible).is_false()

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

	# Shooting blocked: hold-to-fire weapon never starts the cooldown
	Input.action_press("shoot")
	for i in 3:
		await get_tree().physics_frame
	assert_bool(player.blaster_cooldown.is_stopped()).is_true()
	Input.action_release("shoot")
	await get_tree().physics_frame

	# --- Mouse look unlocks movement -> Phase MOVE ---
	await _send_mouse_look(250.0)
	assert_int(tutorial.phase).is_equal(TutorialScript.Phase.MOVE)
	assert_bool(player.movement_locked).is_false()
	assert_str(tutorial._title.text).is_equal("MOVE — press every key")
	assert_bool(tutorial._keys_row.visible).is_true()

	# Walking really works now (this also checks off move_right)
	Input.action_press("move_right")
	for i in 15:
		await get_tree().physics_frame
	Input.action_release("move_right")
	await get_tree().physics_frame
	assert_bool(absf(player.global_position.x - x0) > 0.3).is_true()

	# --- WASD check: each key checked off, last one advances the phase ---
	for action in ["move_forward", "move_left", "move_back", "move_right"]:
		Input.action_press(action)
		for i in 2:
			await get_tree().physics_frame
		Input.action_release(action)
		await get_tree().physics_frame
		if action == "move_forward":
			var key_w: Label = tutorial._key_labels[&"move_forward"]
			assert_bool(key_w.modulate == TutorialScript.COLOR_LIT).is_true()
	assert_int(tutorial.phase).is_equal(TutorialScript.Phase.WEAPONS)
	assert_bool(tutorial._weapons_row.visible).is_true()

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
	assert_int(tutorial.phase).is_equal(TutorialScript.Phase.JUMP)
	assert_int(player.weapon_index).is_equal(2)
	assert_bool(tutorial._jump_hint.visible).is_true()

	# --- Phase JUMP: a single jump + landing does NOT start play ---
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
	assert_bool(player.shooting_locked).is_true()

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
	assert_int(spawner._alive.size()).is_equal(6) # base_count default (2x difficulty)

	# Shooting unlocked: hold-to-fire starts the cooldown
	Input.action_press("shoot")
	for i in 3:
		await get_tree().physics_frame
	assert_bool(player.blaster_cooldown.is_stopped()).is_false()
	Input.action_release("shoot")
	await get_tree().physics_frame


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
