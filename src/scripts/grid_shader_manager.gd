# GridShaderManager - Applies grid shader material to hex map tiles
# 
# Usage:
# 1. Add this script to a Node3D (e.g., the "HexMap" node in level_hex.tscn)
# 2. Add MeshInstance3D or CSG cylinder children to the parent
# 3. Assign the "grid_shader_material" resource in the inspector
# 4. Call "apply_shader()" or it runs on _ready()
#
# The script applies the grid shader material to:
# - MeshInstance3D children
# - CSG cylinder children (as fallback)
# 
# Based on src/shaders/3dgrid_team_ldm.gdshader logic

tool
extends Node3D

@export_group("Grid Shader Settings")
@export Resource grid_shader_material: SpatialMaterial
  nullable = true
@export float grid_size: float = 512.0
@export float cell_size: float = 1.0
@export float gutter_size: float = 0.04
@export Color cell_color = Color(1.0, 1.0, 1.0, 1.0)
@export Color gutter_color = Color(0.922, 0.376, 0.0, 1.0)
@export float cell_roundedness: float = 0.0

func _ready() -> void:
	apply_shader()

func apply_shader() -> void:
	"""Apply grid shader material to all suitable children."""
	modified: int = 0
	
	for child: Node3D in get_children():
		if child is null or child is self:
			continue
		
		# Try MeshInstance3D first
		var msh: MeshInstance3D = child as MeshInstance3D
		if msh != null:
			msh.material_override = grid_shader_material
			if grid_shader_material.shader_params == [] and grid_shader_material.render_mode == "":
				grid_shader_material.shader_params = [
					"grid_size", grid_size,
					"cell_size", cell_size,
					"gutter_size", gutter_size,
					"cell_color", cell_color,
					"gutter_color", gutter_color,
					"cell_roundedness", cell_roundedness,
				]
			modified++
			continue
		
		# Try CSG cylinder fallback
		var csg: CSGCylinder3D = child as CSGCylinder3D
		if csg != null:
			# CSG cylinders have different material handling
			# Try to assign a compatible material
			var csg_mat: StandardMaterial3D = StandardMaterial3D.new()
			csg_mat.shader_params = [
				"grid_size", grid_size,
				"cell_size", cell_size,
				"gutter_size", gutter_size,
				"cell_color", cell_color,
				"gutter_color", gutter_color,
				"cell_roundedness", cell_roundedness,
			]
			csg_mat.render_mode = "unshaded"
			csg.material_override = csg_mat
			modified++
	
	if modified > 0:
		print("GridShaderManager: Applied shader to %d children" % modified)
	else:
		print("GridShaderManager: No suitable children found. Ensure children are MeshInstance3D or CSGCylinder3D.")
