class_name NullwideBeamSpawner
extends Node

## Visual-only listener for the player's nullwide_shot_fired signal: draws one
## world-space beam per NULLWIDE kill, from the camera eye to the dead enemy,
## fading out over fade_duration. Not an autoload and no statics — every
## tunable is an export, and the player never references this script (it only
## emits the signal), so either side can be rewritten or removed alone.

@export_range(0.01, 1.0, 0.01) var beam_width := 0.12
@export_range(0.05, 2.0, 0.05) var fade_duration := 0.25
@export_range(0.0, 20.0, 0.5) var emission_energy := 6.0

func _ready() -> void:
	# Duck-typed hookup, same pattern hud.gd uses: works with any node that
	# exposes the signal, and silently no-ops when it does not.
	var player := get_parent()
	if player.has_signal(&"nullwide_shot_fired"):
		player.connect(&"nullwide_shot_fired", _on_shot_fired)

func _on_shot_fired(from: Vector3, to: Vector3, color: Color) -> void:
	var length := from.distance_to(to)
	if length < 0.001:
		return

	var beam := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = beam_width * 0.5
	mesh.bottom_radius = beam_width * 0.5
	mesh.height = length
	mesh.radial_segments = 8 # cheap: the beam lives under a second
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = emission_energy
	mesh.material = mat
	beam.mesh = mesh

	# Scene root, world space: player movement/rotation never drags the beam
	# (same convention impact.tscn uses). current_scene is nil in the project's
	# headless SceneTree tests, which have no current scene — fall back to root.
	var world: Node = get_tree().current_scene
	if world == null:
		world = get_tree().root
	world.add_child(beam)
	# Cylinder's +Y bent onto the shot direction, body centered on the segment.
	beam.global_transform = Transform3D(
		Basis(Quaternion(Vector3.UP, (to - from) / length)),
		(from + to) * 0.5)

	var tween := beam.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, fade_duration)
	tween.parallel().tween_property(mat, "emission_energy_multiplier", 0.0, fade_duration)
	tween.tween_callback(beam.queue_free)
