extends SceneTree
## Headless logic tests for MapHexGenerator.
## Run: godot --headless -s res://src/tests/test_map_hex_generator.gd

const MapHexGeneratorScript := preload("res://src/objects/map_hex_generator.gd")

var _gen: MapHexGenerator
var _failures: int = 0
var _passes: int = 0


func _initialize() -> void:
	_gen = MapHexGeneratorScript.new()
	_gen.name = "TestGenerator"
	root.add_child(_gen)

	_test_coordinate_count()
	_test_reset_is_flat_height_one()
	_test_round_trip()
	_test_bounds_check()
	_test_pattern_elevation_bounds()
	_test_vertical_aggression()
	_test_collision_enabled()
	_test_elevation_lookup()

	if _failures == 0:
		print("ALL TESTS PASSED (%d checks)" % _passes)
	else:
		printerr("TESTS FAILED: %d of %d checks" % [_failures, _passes + _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		_passes += 1
	else:
		_failures += 1
		printerr("FAIL: %s" % label)


func _test_coordinate_count() -> void:
	# Hex-shaped radius R contains 3R^2 + 3R + 1 tiles.
	var expected: int = 3 * _gen.map_radius * _gen.map_radius + 3 * _gen.map_radius + 1
	_gen.reset()
	_check(_gen.tile_nodes.size() == expected,
		"coordinate count: expected %d, got %d" % [expected, _gen.tile_nodes.size()])


func _test_reset_is_flat_height_one() -> void:
	_gen.generate_map(MapHexGenerator.Pattern.SPIKES)
	_gen.reset()
	var all_height_one: bool = true
	for coord: Vector2i in _gen.tile_elevations:
		if _gen.tile_elevations[coord] != 1:
			all_height_one = false
			break
	_check(all_height_one, "reset(): every tile at elevation 1")

	var tile: CSGCylinder3D = _gen.tile_nodes.values()[0]
	_check(is_equal_approx(tile.height, _gen.height_unit), "reset(): tile height == height_unit")
	_check(is_equal_approx(tile.position.y, tile.height * 0.5), "reset(): tile bottom rests on y=0")


func _test_round_trip() -> void:
	var samples: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(_gen.map_radius, 0), Vector2i(0, _gen.map_radius),
		Vector2i(-_gen.map_radius, -_gen.map_radius), Vector2i(3, -2), Vector2i(-1, 4),
	]
	var all_ok: bool = true
	for coord: Vector2i in samples:
		var pos: Vector3 = _gen.get_tile_world_position(coord.x, coord.y)
		var back: Vector2i = _gen.get_coord_from_world(pos)
		if back != coord:
			all_ok = false
			printerr("  round-trip failed for %s -> %s" % [coord, back])
	_check(all_ok, "axial <-> world round-trip")


func _test_bounds_check() -> void:
	var valid: bool = true
	for coord: Vector2i in _gen.tile_elevations.keys():
		if not _gen.is_valid_coord(coord.x, coord.y):
			valid = false
	_check(valid, "is_valid_coord: all generated coords valid")

	var invalids: Array[Vector2i] = [
		Vector2i(_gen.map_radius + 1, 0), Vector2i(0, _gen.map_radius + 1),
		Vector2i(_gen.map_radius, _gen.map_radius),
	]
	var rejects: bool = true
	for coord: Vector2i in invalids:
		if _gen.is_valid_coord(coord.x, coord.y):
			rejects = false
	_check(rejects, "is_valid_coord: out-of-bounds rejected")
	_check(_gen.get_elevation_at(999, -999) == 0, "get_elevation_at: invalid coord returns 0")


func _test_pattern_elevation_bounds() -> void:
	for pattern: int in [MapHexGenerator.Pattern.SPIKES, MapHexGenerator.Pattern.CLIFF_RINGS, MapHexGenerator.Pattern.NOISE_COLUMNS]:
		_gen.generate_map(pattern)
		var in_bounds: bool = true
		for elevation: int in _gen.tile_elevations.values():
			if elevation < _gen.elevation_min or elevation > _gen.elevation_max:
				in_bounds = false
		_check(in_bounds, "pattern %d: elevations within [%d, %d]" % [pattern, _gen.elevation_min, _gen.elevation_max])
		_check(_gen.tile_nodes.size() == _gen.tile_elevations.size(), "pattern %d: node/elevation dicts aligned" % pattern)


func _test_vertical_aggression() -> void:
	# Aggressive-vertical contract: every terrain pattern must actually reach
	# the full height, and towers must form true cliffs next to low ground.
	for pattern: int in [MapHexGenerator.Pattern.SPIKES, MapHexGenerator.Pattern.CLIFF_RINGS, MapHexGenerator.Pattern.NOISE_COLUMNS]:
		_gen.generate_map(pattern)
		var values: Array = _gen.tile_elevations.values()
		_check(values.max() == _gen.elevation_max,
			"pattern %d reaches max elevation (%d)" % [pattern, _gen.elevation_max])
		var span: int = _gen.elevation_max - _gen.elevation_min
		var max_delta: int = _max_neighbor_delta()
		_check(max_delta >= span / 2,
			"pattern %d has steep cliffs (max neighbor delta %d >= %d)" % [pattern, max_delta, span / 2])


func _max_neighbor_delta() -> int:
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1),
		Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1),
	]
	var max_delta: int = 0
	for coord: Vector2i in _gen.tile_elevations:
		for dir: Vector2i in dirs:
			var neighbor: Vector2i = coord + dir
			if _gen.tile_elevations.has(neighbor):
				max_delta = maxi(max_delta, absi(_gen.tile_elevations[coord] - _gen.tile_elevations[neighbor]))
	return max_delta


func _test_collision_enabled() -> void:
	_gen.generate_map(MapHexGenerator.Pattern.SPIKES)
	var all_collision: bool = true
	for tile: Node3D in _gen.tile_nodes.values():
		var csg := tile as CSGCylinder3D
		if csg == null or not csg.use_collision:
			all_collision = false
	_check(all_collision, "all tiles have use_collision enabled")


func _test_elevation_lookup() -> void:
	_gen.reset()
	_check(_gen.get_elevation_at(0, 0) == 1, "get_elevation_at: valid coord returns its elevation")
	_check(_gen.get_tile(0, 0) != null, "get_tile: valid coord returns a node")
