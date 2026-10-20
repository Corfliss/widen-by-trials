@tool
## MapHexGenerator — aggressive-vertical hexagonal arena generator.
##
## Inspired by HyperSync's MapGenerator (axial hex grid + CSG hex tiles + 10
## mathematical patterns). Every HyperSync pattern is ported here and
## rebalanced for steep vertical terrain: instead of HyperSync's gentle
## center-anchored amplitudes, each pattern's raw field is normalized to the
## full [elevation_min, elevation_max] range, so every map spans tall towers
## (up to ~7.5 m with the defaults) on a small arena footprint.
##
## Editor behaviour: opening (or resetting) this scene in the editor shows the
## flat reset grid — every tile at the lowest elevation (height 1).
## Runtime behaviour: call generate_map(), or set random_pattern_on_ready to
## build one of the 10 patterns at random when the level starts.

class_name MapHexGenerator
extends Node3D

signal map_generated(tile_count: int)

enum Pattern {
	RESET_FLAT,
	FLAT_ARENA,          # Variation 0: flat arena with subtle elevation
	CONCENTRIC_RINGS,    # Variation 1: concentric circular elevation
	SPIRAL_ASCENT,       # Variation 2: golden-ratio spiral elevation
	DIAMOND_PYRAMID,     # Variation 3: diamond-shaped pyramid
	WAVE_INTERFERENCE,   # Variation 4: sine wave interference
	HEXAGONAL_FRACTALS,  # Variation 5: multi-octave fractal elevation
	GOLDEN_RATIO_SPIRAL, # Variation 6: phi-power spiral elevation
	MATHEMATICAL_VALLEYS,# Variation 7: gaussian attractor valleys/peaks
	TESSELLATION_STEPS,  # Variation 8: hexagonal tessellation terraces
	CHAOS_BEAUTIFUL,     # Variation 9: controlled chaos
	RANDOM,              # Pick one of the 10 at runtime
}

@export_group("Grid")
@export_range(1, 10) var map_radius: int = 5
@export_range(0.5, 8.0, 0.05) var hex_size: float = 1.5
@export_group("Vertical")
@export_range(0.05, 2.0, 0.05) var height_unit: float = 0.25
@export_range(1, 64) var elevation_min: int = 1
@export_range(1, 64) var elevation_max: int = 30
@export_group("Level Boot")
## When true (runtime only), _ready builds one of the 10 patterns at random
## instead of the flat reset grid.
@export var random_pattern_on_ready: bool = false
@export var noise_seed: int = 2026

const HEX_HORIZONTAL_FACTOR: float = 1.5
const HEX_VERTICAL_FACTOR: float = 1.7320508075688772  # sqrt(3)

const SUBTLE_SPAN: int = 6            # FLAT_ARENA's identity: low, rolling
const TESSELLATION_LEVELS: int = 4    # HyperSync tess_sum % 4
const SPIKE_THRESHOLD: float = 0.85   # kept for potential future patterns

var current_pattern: int = Pattern.RESET_FLAT
var tile_nodes: Dictionary = {}        # Vector2i -> Node3D
var tile_elevations: Dictionary = {}   # Vector2i -> int
var _materials: Dictionary = {}        # int -> StandardMaterial3D
var _pattern_generators: Array[Callable] = []


func _ready() -> void:
	_setup_pattern_generators()
	if not Engine.is_editor_hint() and random_pattern_on_ready:
		generate_map(Pattern.RANDOM)
	else:
		reset()


## The 10 HyperSync pattern generators, ordered FLAT_ARENA..CHAOS_BEAUTIFUL.
func _setup_pattern_generators() -> void:
	_pattern_generators = [
		_pattern_flat_arena,
		_pattern_concentric_rings,
		_pattern_spiral_ascent,
		_pattern_diamond_pyramid,
		_pattern_wave_interference,
		_pattern_hexagonal_fractals,
		_pattern_golden_ratio_spiral,
		_pattern_mathematical_valleys,
		_pattern_tessellation_steps,
		_pattern_chaos_beautiful,
	]


## Generate the hex map with the given pattern (RANDOM picks one of the 10).
func generate_map(pattern: Pattern = Pattern.RESET_FLAT) -> void:
	if _pattern_generators.is_empty():
		_setup_pattern_generators()  # safe when called before _ready
	_clear_tiles()
	if pattern == Pattern.RANDOM:
		pattern = _pick_random_pattern() as Pattern
	current_pattern = pattern
	var coords: Array[Vector2i] = _get_axial_coordinates()
	var elevations: Array[int] = _apply_pattern(pattern, coords)
	for i: int in coords.size():
		_create_tile(coords[i], elevations[i])
	map_generated.emit(coords.size())


## Rebuild the map as a flat grid at the lowest elevation (height 1).
func reset() -> void:
	generate_map(Pattern.RESET_FLAT)


func _pick_random_pattern() -> int:
	return randi_range(Pattern.FLAT_ARENA, Pattern.CHAOS_BEAUTIFUL)


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
		Pattern.RESET_FLAT:
			var out: Array[int] = []
			out.resize(coords.size())
			out.fill(elevation_min)
			return out
		_:
			return _pattern_generators[pattern - Pattern.FLAT_ARENA].call(coords)


# ------------ Pattern helpers ------------

## Normalize a raw field to [0, 1] across the coordinate set, then map to
## elevations. This is the aggressive-vertical rebalance: HyperSync anchored
## amplitudes around MAP_CENTER_HEIGHT (±4..5 units); here every non-subtle
## pattern uses the full [elevation_min, elevation_max] range.
func _pattern_from_raw(coords: Array[Vector2i], raw: Array[float], subtle: bool = false) -> Array[int]:
	var out: Array[int] = []
	out.resize(coords.size())
	var lo: float = raw.min()
	var hi: float = raw.max()
	var span: int = SUBTLE_SPAN if subtle else elevation_max - elevation_min
	for i: int in coords.size():
		var t: float = (raw[i] - lo) / maxf(hi - lo, 0.0001)
		out[i] = elevation_min + int(roundf(t * float(span)))
	return out


func _gaussian(x: float, y: float, sigma_scale: float) -> float:
	return exp(-(x * x + y * y) / sigma_scale)


# ------------ The 10 HyperSync patterns (ported, rebalanced vertical) ------------

## Variation 0: flat arena with subtle elevation variation.
func _pattern_flat_arena(coords: Array[Vector2i]) -> Array[int]:
	var raw: Array[float] = []
	raw.resize(coords.size())
	for i: int in coords.size():
		raw[i] = sin(coords[i].x * 0.5) + cos(coords[i].y * 0.5)
	return _pattern_from_raw(coords, raw, true)


## Variation 1: concentric rings radiating from center (HyperSync ring distance).
func _pattern_concentric_rings(coords: Array[Vector2i]) -> Array[int]:
	var raw: Array[float] = []
	raw.resize(coords.size())
	for i: int in coords.size():
		var x: float = float(coords[i].x)
		var y: float = float(coords[i].y)
		var distance: float = sqrt(x * x + y * y + x * y)
		raw[i] = sin(distance * 0.8)
	return _pattern_from_raw(coords, raw)


## Variation 2: golden-ratio spiral ascent.
func _pattern_spiral_ascent(coords: Array[Vector2i]) -> Array[int]:
	var phi: float = (1.0 + sqrt(5.0)) / 2.0
	var raw: Array[float] = []
	raw.resize(coords.size())
	for i: int in coords.size():
		var x: float = float(coords[i].x)
		var y: float = float(coords[i].y)
		var angle: float = atan2(y, x)
		var distance: float = sqrt(x * x + y * y)
		raw[i] = sin(angle + distance / phi) * cos(distance * 0.3)
	return _pattern_from_raw(coords, raw)


## Variation 3: diamond-shaped pyramid, peak at center (already [0, 1]).
func _pattern_diamond_pyramid(coords: Array[Vector2i]) -> Array[int]:
	var raw: Array[float] = []
	raw.resize(coords.size())
	for i: int in coords.size():
		var x: float = float(coords[i].x)
		var y: float = float(coords[i].y)
		var manhattan: float = absf(x) + absf(y) + absf(x + y)
		raw[i] = 1.0 - manhattan / float(2 * map_radius)
	return _pattern_from_raw(coords, raw)


## Variation 4: sine wave interference.
func _pattern_wave_interference(coords: Array[Vector2i]) -> Array[int]:
	var raw: Array[float] = []
	raw.resize(coords.size())
	for i: int in coords.size():
		var x: float = float(coords[i].x)
		var y: float = float(coords[i].y)
		var wave1: float = sin(x * 0.6) * cos(y * 0.4)
		var wave2: float = cos(x * 0.4) * sin(y * 0.6)
		var wave3: float = sin((x + y) * 0.3)
		raw[i] = (wave1 + wave2 + wave3) / 3.0
	return _pattern_from_raw(coords, raw)


## Variation 5: multi-octave hexagonal fractal elevation.
func _pattern_hexagonal_fractals(coords: Array[Vector2i]) -> Array[int]:
	var raw: Array[float] = []
	raw.resize(coords.size())
	for i: int in coords.size():
		var fractal_value: float = 0.0
		var octave_scale: float = 1.0
		for octave: int in 3:
			var x: float = float(coords[i].x) * octave_scale * 0.2
			var y: float = float(coords[i].y) * octave_scale * 0.2
			fractal_value += sin(x) * cos(y) * sin(x + y) / octave_scale
			octave_scale *= 2.0
		raw[i] = fractal_value
	return _pattern_from_raw(coords, raw)


## Variation 6: phi-power spiral elevation.
func _pattern_golden_ratio_spiral(coords: Array[Vector2i]) -> Array[int]:
	var phi: float = (1.0 + sqrt(5.0)) / 2.0
	var raw: Array[float] = []
	raw.resize(coords.size())
	for i: int in coords.size():
		var x: float = float(coords[i].x)
		var y: float = float(coords[i].y)
		var angle: float = atan2(y, x)
		var distance: float = sqrt(x * x + y * y)
		var spiral_radius: float = pow(phi, angle / PI)
		raw[i] = sin(distance * 0.5) * cos(spiral_radius * 0.1)
	return _pattern_from_raw(coords, raw)


## Variation 7: gaussian attractor valleys/peaks at 3 centers.
func _pattern_mathematical_valleys(coords: Array[Vector2i]) -> Array[int]:
	var raw: Array[float] = []
	raw.resize(coords.size())
	for i: int in coords.size():
		var x: float = float(coords[i].x)
		var y: float = float(coords[i].y)
		var valley1: float = _gaussian(x, y, 20.0)
		var valley2: float = _gaussian(x - 3.0, y - 3.0, 15.0)
		var valley3: float = _gaussian(x + 3.0, y + 3.0, 15.0)
		raw[i] = valley1 + valley2 * 0.7 + valley3 * 0.7
	return _pattern_from_raw(coords, raw)


## Variation 8: hexagonal tessellation terraces (quantized plateaus).
func _pattern_tessellation_steps(coords: Array[Vector2i]) -> Array[int]:
	var raw: Array[float] = []
	raw.resize(coords.size())
	for i: int in coords.size():
		var tess_x: int = absi(coords[i].x / 2) % 3
		var tess_y: int = absi(coords[i].y / 2) % 3
		var tess_sum: int = (tess_x + tess_y) % TESSELLATION_LEVELS
		raw[i] = float(tess_sum) / float(TESSELLATION_LEVELS - 1)
	return _pattern_from_raw(coords, raw)


## Variation 9: controlled chaos with an attractor for mathematical beauty.
func _pattern_chaos_beautiful(coords: Array[Vector2i]) -> Array[int]:
	var raw: Array[float] = []
	raw.resize(coords.size())
	for i: int in coords.size():
		var x: float = float(coords[i].x)
		var y: float = float(coords[i].y)
		var chaos1: float = sin(x * 0.7) * cos(y * 0.8)
		var chaos2: float = sin((x + y) * 0.4) * cos((x - y) * 0.6)
		var chaos3: float = sin(x * y * 0.1) if not is_zero_approx(x * y) else 0.0
		var attractor: float = _gaussian(x, y, 50.0)
		raw[i] = (chaos1 + chaos2 + chaos3) * (1.0 + attractor)
	return _pattern_from_raw(coords, raw)


# ------------ Tiles ------------

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
	var ratio: float = clampf((float(elevation) - float(elevation_min)) / span, 0.0, 1.0)
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


# ------------ Coordinates & lookups ------------

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
	return tile_elevations.get(Vector2i(q, r), 0)


func get_tile(q: int, r: int) -> Node3D:
	return tile_nodes.get(Vector2i(q, r))


## Highest walkable surface of the current map (tile top Y).
func get_max_top_y() -> float:
	var top: float = 0.0
	for coord: Vector2i in tile_elevations:
		top = maxf(top, height_unit * float(tile_elevations[coord]))
	return maxf(top, height_unit)
