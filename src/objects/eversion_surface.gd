class_name EversionSurface
extends MeshInstance3D
## Walkable eversion surface: Ball.glb re-placed every frame by the analytic map.
##
## Loads the sphere mesh once, recovers each vertex's material coordinates
## (theta, phi), then on apply(s) rewrites positions = f(theta, phi, s) and
## normals = the map's own central-difference normal. The eversion frame
## (pole_basis) is deliberately NOT baked into the vertices: this node's
## transform carries it, so a re-pole just moves the node and the local
## vertices stay put (invisible on the uniform sphere).
##
## Pole handling: positions use the exact theta, so the two Ball vertices that
## sit on the coordinate poles stay at a single finite point (no hole); only the
## normal nudges off-pole inside SphereEversion.normal, since jphi degenerates there.
##
## P5 note: the surface is rebuilt via clear_surfaces/add_surface_from_arrays each
## frame. For 559 verts that is far under the 2 ms budget. If a high-tessellation
## sphere is ever swapped in, switch positions to surface_update_vertex_region
## (plan D2) before this becomes the bottleneck.

@export var model_path: String = "res://src/assets/3d_models/Ball.glb"
@export var diff_h: float = 1e-4     ## central-difference step for normals

var _theta := PackedFloat32Array()
var _phi := PackedFloat32Array()
var _positions := PackedVector3Array()
var _normals := PackedVector3Array()
var _uvs := PackedVector2Array()
var _indices := PackedInt32Array()
var _count := 0


func _ready() -> void:
	_extract_ball()
	apply(0.0)   # seed a valid sphere mesh so the node renders before first driver tick


## Re-place every vertex for master progress s in [0, 1]. The level calls this
## only while s is actually moving (holding s = held surface = no rebuild).
func apply(s: float) -> void:
	var pm := SphereEversion.params(s)
	for i in _count:
		var th := _theta[i]
		var ph := _phi[i]
		_positions[i] = SphereEversion.eval(th, ph, pm)
		_normals[i] = SphereEversion.normal(th, ph, pm, diff_h)
	# Packed arrays are copy-on-write, so bundle them fresh each frame rather than
	# holding a stale reference to the buffers mutated above.
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _positions
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_INDEX] = _indices
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


func vertex_count() -> int:
	return _count


func _extract_ball() -> void:
	var ps: PackedScene = load(model_path)
	var inst := ps.instantiate()
	var src := _find_mesh(inst)
	var arr: Array = src.mesh.surface_get_arrays(0)
	var src_verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	_uvs = arr[Mesh.ARRAY_TEX_UV]
	_indices = arr[Mesh.ARRAY_INDEX]
	_count = src_verts.size()
	_theta.resize(_count)
	_phi.resize(_count)
	_positions.resize(_count)
	_normals.resize(_count)
	for i in _count:
		var v := src_verts[i]
		var r := v.length()
		# Ball is the unit sphere, so asin/atan2 recover the map's material coords.
		_theta[i] = asin(clampf(v.z / r, -1.0, 1.0))
		_phi[i] = atan2(v.y, v.x)
	inst.free()
	mesh = ArrayMesh.new()


func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _find_mesh(c)
		if r != null:
			return r
	return null
