extends GdUnitTestSuite
## Tap-fire gate for RepeaterWeapon (Sweat Carbine): one volley per press,
## holding does nothing, release re-arms.
## Note: just_pressed/just_released edges last the whole frame, so press and
## release must be separated by an awaited frame — same as in gameplay.

const SHOOT := "shoot"


func test_press_fires_once_and_hold_does_not_refire() -> void:
	var gun: RepeaterWeapon = auto_free(RepeaterWeapon.new())
	Input.action_press(SHOOT)
	assert_bool(gun.can_fire()).is_true()   # press = fire
	assert_bool(gun.can_fire()).is_false()  # armed latch blocks refire
	await get_tree().process_frame          # press edge expires
	assert_bool(gun.can_fire()).is_false()  # held = still no refire
	Input.action_release(SHOOT)


func test_release_rearms_next_press() -> void:
	var gun: RepeaterWeapon = auto_free(RepeaterWeapon.new())
	Input.action_press(SHOOT)
	assert_bool(gun.can_fire()).is_true()
	await get_tree().process_frame
	Input.action_release(SHOOT)
	assert_bool(gun.can_fire()).is_false()  # release alone never fires
	assert_bool(gun.armed).is_true()        # ...but re-armed the next press
	Input.action_press(SHOOT)
	assert_bool(gun.can_fire()).is_true()
	Input.action_release(SHOOT)
