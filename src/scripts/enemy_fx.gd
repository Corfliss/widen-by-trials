class_name EnemyFX

## Shared hit-feedback helpers for the enemy scripts (chaser/sniper/bomber).
## Not an autoload: both effects are spawned on demand and clean themselves up.

const BURST_SCENE: PackedScene = preload("res://src/objects/enemy_death_burst.tscn")
## Seconds the hit flash stays visible before the face color settles back.
const FLASH_SECONDS: float = 0.15

## One-shot particle splatter in `tint`, spawned in `world` at `at`.
## The burst frees itself once the emission finishes.
static func death_burst(world: Node, at: Vector3, tint: Color) -> void:
	if world == null:
		return
	var burst := BURST_SCENE.instantiate() as GPUParticles3D
	# Per-spawn copy: the scene's material would otherwise be shared by every
	# concurrent burst, and all of them would repaint to the last killer's tint.
	var mat := burst.process_material.duplicate() as ParticleProcessMaterial
	mat.color = tint
	burst.process_material = mat
	world.add_child(burst)
	burst.global_position = at
	burst.finished.connect(burst.queue_free)

## Hit frame in the enemy's own color: the mesh faces snap from their dark
## resting shade to the full tint and ease back over FLASH_SECONDS.
## Kills `previous` so rapid hits do not stack competing tweens.
## Returns the running tween (or the killed `previous` when `mat` is missing).
static func flash(host: Node, mat: ShaderMaterial, tint: Color, previous: Tween) -> Tween:
	if previous != null:
		previous.kill()
	if mat == null:
		return previous
	mat.set_shader_parameter("face_color", tint)
	var tween := host.create_tween()
	tween.tween_method(
		func(c: Color) -> void: mat.set_shader_parameter("face_color", c),
		tint, tint.darkened(0.8), FLASH_SECONDS)
	return tween
