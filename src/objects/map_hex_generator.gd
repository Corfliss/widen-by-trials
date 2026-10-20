@tool
## MapHexGenerator — aggressive-vertical hexagonal arena generator.
##
## Inspired by HyperSync's MapGenerator (axial hex grid + CSG hex tiles) but
## rebalanced for steep vertical terrain: narrow towers, quantized cliff rings
## and plateau columns instead of gentle rolling hills.
##
## Editor behaviour: opening (or resetting) this scene in the editor shows the
## flat reset grid — every tile at the lowest elevation (height 1).
## Runtime behaviour: call generate_map() to build a patterned map.

class_name MapHexGenerator
extends Node3D

signal map_generated(tile_count: int)

enum Pattern { RESET_FLAT, SPIKES, CLIFF_RINGS, NOISE_COLUMNS }

# HyperSync axial->world math: columns 1.5 * radius apart, rows sqrt(3) * radius
# apart with half-column offset. Keep the factors separate so hex_size scales both.
const HEX_HORIZONTAL_FACTOR: float = 1.5
const HEX_VERTICAL_FACTOR: float = 1.7320508075688772  # sqrt(3)

const SPIKE_THRESHOLD: float = 0.85    # top 15% of the noise field become towers
const CLIFF_RING_STEPS: int = 3        # giant terraces from center to rim (tall cliff jumps)
const NOISE_COLUMN_BANDS: int = 5      # discrete plateau heights

@export_group("Grid")
@export_range(1, 10) var map_radius: int = 5
@export_range(0.5, 8.0, 0.05) var hex_size: float = 1.5
@export_group("Vertical")
@export_range(0.05, 2.0, 0.05) var height_unit: float = 0.25
@export_range(1, 64) var elevation_min: int = 1
@export_range(1, 64) var elevation_max: int = 30
@export_group("Noise")
@export var noise_seed: int = 2026

var tile_nodes: Dictionary = {}        # Vector2i -> Node3D
var tile_elevations: Dictionary = {}   # Vector2i -> int
var _materials: Dictionary = {}        # int -> StandardMaterial3D


func _ready() -> void:
	# Editor or runtime: the default state is the flat reset grid (all height 1).
	reset()


## Rebuild the map as a flat grid at the lowest elevation (height 1).
func reset() -> void:
	generate_map(Pattern.RESET_FLAT)


## Generate the hex map with the given pattern.
func generate_map(pattern: Pattern = Pattern.RESET_FLAT) -> void:
	_clear_tiles()
	var coords: Array[Vector2i] = _get_axial_coordinates()
	var elevations: Array[int] = _apply_pattern(pattern, coords)
	for i: int in coords.size():
		_create_tile(coords[i], elevations[i])
	map_generated.emit(coords.size())


## All valid axial coords within the hex-shaped radius (HyperSync loop).
func _get_axial_coordinates() -> Array[Vector2i]:
	var coords: Array[Vector2i] = []
	for q: int in range(-map_radius, map_radius + 1):
		var r1: int = maxi(-map_radius, -q - map_radius)
		var r2: int = mini(map_radius, -q + map_radius)
		for r: int in range(r1, r2 + 1):
			coords.append(Vector2i(q, r))
	return coords


func _apply_pattern(pattern: Pattern, coords: Array[Vector2i]) -> Array[int]:
	match pattern:
		Pattern.SPIKES:
			return _pattern_spikes(coords)
		Pattern.CLIFF_RINGS:
			return _pattern_cliff_rings(coords)
		Pattern.NOISE_COLUMNS:
			return _pattern_noise_columns(coords)
		_:
			var out: Array[int] = []
			out.resize(coords.size())
			out.fill(elevation_min)
			return out


## Sparse narrow towers: low ground with occasional full-height spikes.
func _pattern_spikes(coords: Array[Vector2i]) -> Array[int]:
	var out: Array[int] = []
	out.resize(coords.size())
	var raw: Array[float] = _noise_field(coords, 0.35, noise_seed)
	var lo: float = raw.min()
	var hi: float = raw.max()
	for i: int in coords.size():
		var v: float = _normalize(raw[i], lo, hi)
		if v < SPIKE_THRESHOLD:
			out[i] = elevation_min + int(v * 2.0)
		else:
			out[i] = elevation_min + int((v - SPIKE_THRESHOLD) / (1.0 - SPIKE_THRESHOLD) * (elevation_max - elevation_min))
	return out


## Quantized cliff rings: flat plateaus rising in giant jumps toward the rim.
func _pattern_cliff_rings(coords: Array[Vector2i]) -> Array[int]:
	var out: Array[int] = []
	out.resize(coords.size())
	var span: int = elevation_max - elevation_min
	for i: int in coords.size():
		var x: float = float(coords[i].x)
		var y: float = float(coords[i].y)
		var distance: float = sqrt(x * x + y * y + x * y)  # HyperSync ring distance
		var t: float = distance / float(map_radius)        # 0 at center .. 1 at rim
		var level: int = mini(int(floor(t * CLIFF_RING_STEPS)), CLIFF_RING_STEPS - 1)
		out[i] = elevation_min + level * span / (CLIFF_RING_STEPS - 1)
	return out


## Quantized plateau columns from simplex noise — vertical jumps, no slopes.
func _pattern_noise_columns(coords: Array[Vector2i]) -> Array[int]:
	var out: Array[int] = []
	out.resize(coords.size())
	var raw: Array[float] = _noise_field(coords, 0.18, noise_seed + 1)
	var lo: float = raw.min()
	var hi: float = raw.max()
	var span: int = elevation_max - elevation_min
	for i: int in coords.size():
		var v: float = _normalize(raw[i], lo, hi)
		var band: int = mini(int(v * NOISE_COLUMN_BANDS), NOISE_COLUMN_BANDS - 1)
		out[i] = elevation_min + band * span / (NOISE_COLUMN_BANDS - 1)
	return out


func _noise_field(coords: Array[Vector2i], frequency: float, seed_value: int) -> Array[float]:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.seed = seed_value
	noise.frequency = frequency
	var out: Array[float] = []
	out.resize(coords.size())
	for i: int in coords.size():
		out[i] = noise.get_noise_2d(float(coords[i].x), float(coords[i].y))
	return out


func _normalize(value: float, lo: float, hi: float) -> float:
	return (value - lo) / maxf(hi - lo, 0.0001)


func _create_tile(coord: Vector2i, elevation: int) -> void:
	var clamped: int = clampi(elevation, elevation_min, elevation_max)
	var tile := CSGCylinder3D.new()
	tile.name = "Hex_%d_%d" % [coord.x, coord.y]
	tile.sides = 6
	tile.radius = hex_size
	tile.height = height_unit * float(clamped)
	tile.use_collision = true
	tile.position = get_tile_world_position(coord.x, coord.y)
	tile.position.y = tile.height * 0.5  # bottom rests on y = 0
	tile.material_override = _get_material(clamped)
	add_child(tile)
	tile_nodes[coord] = tile
	tile_elevations[coord] = clamped


func _clear_tiles() -> void:
	for coord: Vector2i in tile_nodes:
		var tile: Node3D = tile_nodes[coord]
		if is_instance_valid(tile):
			tile.queue_free()
	tile_nodes.clear()
	tile_elevations.clear()
	_materials.clear()


## Color-graded material per elevation; top elevations glow.
func _get_material(elevation: int) -> StandardMaterial3D:
	if _materials.has(elevation):
		return _materials[elevation]
	var mat := StandardMaterial3D.new()
	var span: float = maxf(float(elevation_max - elevation_min), 1.0)
	var ratio: float = (float(elevation) - float(elevation_min)) / span
	if ratio < 0.3:
		mat.albedo_color = Color(0.08 + ratio * 0.2, 0.12 + ratio * 0.3, 0.2 + ratio * 0.4)
	elif ratio < 0.7:
		mat.albedo_color = Color(0.15, 0.35 + ratio * 0.35, 0.55 + ratio * 0.45)
	else:
		mat.albedo_color = Color(0.45 + ratio * 0.4, 0.65 + ratio * 0.35, 0.8 + ratio * 0.2)
		mat.emission_enabled = true
		mat.emission = mat.albedo_color * 0.3
	mat.roughness = 0.7
	mat.metallic = 0.3
	_materials[elevation] = mat
	return mat


# ------------ Coordinates ------------

## Axial (q, r) -> world XZ using the HyperSync spacing formulas.
func get_tile_world_position(q: int, r: int) -> Vector3:
	var x: float = hex_size * HEX_HORIZONTAL_FACTOR * float(q)
	var z: float = hex_size * HEX_VERTICAL_FACTOR * (float(r) + float(q) * 0.5)
	return Vector3(x, 0.0, z)


## World XZ -> axial (q, r), inverse of get_tile_world_position.
func get_coord_from_world(world_pos: Vector3) -> Vector2i:
	var q: int = int(roundf(world_pos.x / (hex_size * HEX_HORIZONTAL_FACTOR)))
	var r: int = int(roundf(world_pos.z / (hex_size * HEX_VERTICAL_FACTOR) - float(q) * 0.5))
	return Vector2i(q, r)


func is_valid_coord(q: int, r: int) -> bool:
	return absi(q) <= map_radius and absi(r) <= map_radius and absi(q + r) <= map_radius


func get_elevation_at(q: int, r: int) -> int:
	var coord := Vector2i(q, r)
	return tile_elevations.get(coord, 0)


func get_tile(q: int, r: int) -> Node3D:
	return tile_nodes.get(Vector2i(q, r))
