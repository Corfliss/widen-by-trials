extends GdUnitTestSuite
## Color palette (Red/Black/White) and weapon wheel contract tests.
## Wheel order per production notes: Blood Shotgun -> Sweat Carbine ->
## Tears Machine Gun, cycling back to the shotgun.

const PLAYER_SCENE := "res://src/objects/player.tscn"


func test_enum_order_is_red_black_white() -> void:
	assert_int(Weapon.GunColor.RED).is_equal(0)
	assert_int(Weapon.GunColor.BLACK).is_equal(1)
	assert_int(Weapon.GunColor.WHITE).is_equal(2)


func test_gun_color_values() -> void:
	assert_that(GameManager.gun_color_value(Weapon.GunColor.RED)).is_equal(Color("EE4444"))
	assert_that(GameManager.gun_color_value(Weapon.GunColor.BLACK)).is_equal(Color("222222"))
	assert_that(GameManager.gun_color_value(Weapon.GunColor.WHITE)).is_equal(Color("FFFFFF"))


func test_colors_match_is_equality() -> void:
	assert_bool(GameManager.colors_match(Weapon.GunColor.RED, Weapon.GunColor.RED)).is_true()
	assert_bool(GameManager.colors_match(Weapon.GunColor.RED, Weapon.GunColor.BLACK)).is_false()
	assert_bool(GameManager.colors_match(Weapon.GunColor.WHITE, Weapon.GunColor.WHITE)).is_true()


func test_random_gun_color_stays_in_palette() -> void:
	for n in 30:
		assert_int(GameManager.random_gun_color()).is_between(0, 2)


func test_player_weapon_wheel_order_and_colors() -> void:
	var scene := load(PLAYER_SCENE) as PackedScene
	assert_object(scene).is_not_null()
	var player = auto_free(scene.instantiate())
	# Wheel: Shotgun (red) -> Carbine (black) -> MG (white)
	var expected := [
		["double_barrel_vinrax", Weapon.GunColor.RED],
		["repeater_lonesomedukcy", Weapon.GunColor.BLACK],
		["heavy_machine_gun_kometfox", Weapon.GunColor.WHITE],
	]
	assert_int(player.weapons.size()).is_equal(3)
	for i in expected.size():
		var weapon: Weapon = player.weapons[i]
		assert_str(weapon.model.resource_path.get_file().get_basename()) \
			.is_equal(expected[i][0])
		assert_int(weapon.gun_color).is_equal(expected[i][1])
