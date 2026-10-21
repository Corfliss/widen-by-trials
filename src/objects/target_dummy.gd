extends StaticBody3D

## Calibration dummy for the tutorial's SHOOT and NULLWIDE phases
## (src/scenes/tutorial/tutorial.gd). Stands still, reports every damage()
## call and never dies on its own — the tutorial frees it when done.
##
## Joins the "enemy" group so the NULLWIDE lock scan sees it, and carries
## enemy_color_code so the hitscan color gate (player.gd) lets shots through;
## the tutorial mirrors the held weapon's color into it every frame.

signal damaged(amount: int)

## Duck-typed contract shared with every shootable — player.gd's hitscan and
## the NULLWIDE release both resolve targets via this method.
var enemy_color_code: int = Weapon.GunColor.WHITE

const SIZE := 2.0

func _ready() -> void:
	add_to_group("enemy")
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(SIZE, SIZE, SIZE)
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.45, 0.1) # bright orange, reads on any theme
	mesh.material_override = mat
	add_child(mesh)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(SIZE, SIZE, SIZE)
	shape.shape = box_shape
	add_child(shape)


## Records the hit and notifies the tutorial. Death (9999 = NULLWIDE release)
## is the tutorial's business, not ours — it frees us when the phase ends.
func damage(amount: int) -> void:
	damaged.emit(amount)
