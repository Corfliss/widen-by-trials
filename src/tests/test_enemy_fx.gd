extends GdUnitTestSuite
## EnemyFX contract tests: the death splatter spawns tinted and isolated per
## spawn, and the non-lethal hit flash snaps to the enemy color without
## stacking tweens under rapid fire.

const WIRE_SHADER := preload("res://src/shaders/wireframe_SuperDoomKing.gdshader")
const ENEMY_SCENES: Array[String] = [
	"res://src/objects/chaser.tscn",
	"res://src/objects/sniper.tscn",
	"res://src/objects/bomber.tscn",
]


func test_death_burst_spawns_one_shot_at_target_position() -> void:
	var world: Node3D = auto_free(Node3D.new())
	add_child(world)
	EnemyFX.death_burst(world, Vector3(1, 2, 3), Color("EE4444"))
	var burst := world.get_child(0) as GPUParticles3D
	assert_object(burst).is_not_null()
	assert_bool(burst.one_shot).is_true()
	assert_that(burst.global_position).is_equal(Vector3(1, 2, 3))
	var pm := burst.process_material as ParticleProcessMaterial
	assert_object(pm).is_not_null()
	assert_that(pm.color).is_equal(Color("EE4444"))


func test_concurrent_bursts_get_distinct_process_materials() -> void:
	var world: Node3D = auto_free(Node3D.new())
	add_child(world)
	EnemyFX.death_burst(world, Vector3.ZERO, Color.RED)
	EnemyFX.death_burst(world, Vector3.ZERO, Color.BLUE)
	var first := (world.get_child(0) as GPUParticles3D).process_material
	var second := (world.get_child(1) as GPUParticles3D).process_material
	# A shared material would repaint the first burst to the second's color.
	assert_bool(first != second).is_true()
	assert_that((second as ParticleProcessMaterial).color).is_equal(Color.BLUE)
	assert_that((first as ParticleProcessMaterial).color).is_equal(Color.RED)


func test_death_burst_tolerates_null_world() -> void:
	EnemyFX.death_burst(null, Vector3.ZERO, Color.RED)


func test_flash_snaps_face_to_enemy_color_and_returns_live_tween() -> void:
	var host: Node3D = auto_free(Node3D.new())
	add_child(host)
	var mat := ShaderMaterial.new()
	mat.shader = WIRE_SHADER
	mat.set_shader_parameter("face_color", Color("222222"))
	var tween := EnemyFX.flash(host, mat, Color("EE4444"), null)
	assert_object(tween).is_not_null()
	# The snap is synchronous — visible from the hit frame itself, not frame 2.
	assert_that(mat.get_shader_parameter("face_color")).is_equal(Color("EE4444"))
	assert_bool(tween.is_running()).is_true()


func test_flash_kills_previous_tween_so_hits_do_not_stack() -> void:
	var host: Node3D = auto_free(Node3D.new())
	add_child(host)
	var mat := ShaderMaterial.new()
	mat.shader = WIRE_SHADER
	var first := EnemyFX.flash(host, mat, Color.RED, null)
	var second := EnemyFX.flash(host, mat, Color.RED, first)
	assert_bool(first.is_running()).is_false()
	assert_bool(second.is_running()).is_true()


func test_flash_without_material_returns_previous() -> void:
	var host: Node3D = auto_free(Node3D.new())
	add_child(host)
	assert_object(EnemyFX.flash(host, null, Color.RED, null)).is_null()


func test_enemy_scripts_flash_on_hit_then_destroy_on_kill() -> void:
	var dummy_player: CharacterBody3D = auto_free(CharacterBody3D.new())
	dummy_player.add_to_group("player")
	add_child(dummy_player)
	for path in ENEMY_SCENES:
		var enemy = load(path).instantiate()  # untyped: scene scripts have no class_name
		add_child(enemy)
		await get_tree().process_frame  # _ready rolls color and wire material
		assert_object(enemy._wire_mat).is_not_null()
		enemy.damage(1)  # non-lethal: face snaps to the enemy color
		assert_that(enemy._wire_mat.get_shader_parameter("face_color")).is_equal(enemy._tint)
		await get_tree().create_timer(EnemyFX.FLASH_SECONDS + 0.1).timeout
		assert_that(enemy._wire_mat.get_shader_parameter("face_color")) \
			.is_equal(enemy._tint.darkened(0.8))
		enemy.damage(100)  # killing blow: death branch runs without error
		assert_bool(enemy.destroyed).is_true()
