extends SceneTree
## Headless logic tests for MapHexGenerator.
## Run: godot --headless -s res://src/tests/test_map_hex_generator.gd

const LEVEL_SCENE := "res://src/scenes/level_hex.tscn"
const MapHexGeneratorScript := preload("res://src/objects/map_hex_generator.gd")

var _gen: MapHexGenerator
var _failures: int = 0
var _passes: int = 0


func _initialize() -> void:
	_gen = MapHexGeneratorScript.new()
	_gen.name = "TestGenerator"
	root.add_child(_gen)
	_gen._setup_pattern_generators()

	_test_coordinate_count()
	_test_reset_is_flat_height_one()
	_test_round_trip()
	_test_bounds_check()
	_test_all_ten_patterns()
	_test_subtle_flat_arena()
	_test_tessellation_terraces()
	_test_random_pick()
	_test_determinism()
	_test_collision_enabled()
	_test_elevation_lookup()

	# Live level integration (spawner, player, randomized map boot).
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	if condition:
		_passes += 1
	else:
		_failures += 1
		printerr("FAIL: %s" % label)


func _test_coordinate_count() -> void:
	var expected: int = 3 * _gen.map_radius * _gen.map_radius + 3 * _gen.map_radius + 1
	_gen.reset()
	_check(_gen.tile_nodes.size() == expected,
		"coordinate count: expected %d, got %d" % [expected, _gen.tile_nodes.size()])


func _test_reset_is_flat_height_one() -> void:
	_gen.generate_map(MapHexGenerator.Pattern.CHAOS_BEAUTIFUL)
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


## The 10 HyperSync algorithms, rebalanced: all in bounds, and every non-subtle
## pattern's tallest tile must reach the full elevation_max.
func _test_all_ten_patterns() -> void:
	for pattern: int in range(MapHexGenerator.Pattern.FLAT_ARENA, MapHexGenerator.Pattern.CHAOS_BEAUTIFUL + 1):
		_gen.generate_map(pattern)
		_check(_gen.current_pattern == pattern, "pattern %d: current_pattern stored" % pattern)
		var values: Array = _gen.tile_elevations.values()
		var in_bounds: bool = true
		for elevation: int in _gen.tile_elevations.values():
			if elevation < _gen.elevation_min or elevation > _gen.elevation_max:
				in_bounds = false
		_check(in_bounds, "pattern %d: elevations within [%d, %d]" % [pattern, _gen.elevation_min, _gen.elevation_max])
		_check(_gen.tile_nodes.size() == _gen.tile_elevations.size(),
			"pattern %d: node/elevation dicts aligned" % pattern)
		if pattern != MapHexGenerator.Pattern.FLAT_ARENA:
			_check(values.max() == _gen.elevation_max,
				"pattern %d reaches max elevation %d (got %d)" % [pattern, _gen.elevation_max, values.max()])


func _test_subtle_flat_arena() -> void:
	_gen.generate_map(MapHexGenerator.Pattern.FLAT_ARENA)
	var values: Array = _gen.tile_elevations.values()
	_check(values.max() <= _gen.elevation_min + 6,
		"FLAT_ARENA stays subtle (max %d)" % values.max())
	_check(values.min() == _gen.elevation_min, "FLAT_ARENA touches min elevation")


func _test_tessellation_terraces() -> void:
	_gen.generate_map(MapHexGenerator.Pattern.TESSELLATION_STEPS)
	var max_delta: int = _max_neighbor_delta()
	var terrace: int = (_gen.elevation_max - _gen.elevation_min) / (4 - 1)
	_check(max_delta >= terrace,
		"TESSELLATION_STEPS forms vertical terraces (max delta %d >= %d)" % [max_delta, terrace])
	var distinct: Array = []
	for elevation: int in _gen.tile_elevations.values():
		if not distinct.has(elevation):
			distinct.append(elevation)
	_check(distinct.size() >= 3, "TESSELLATION_STEPS has at least 3 distinct levels (got %d)" % distinct.size())


func _test_random_pick() -> void:
	seed(111)
	var seen: Array[int] = []
	for i: int in 40:
		_gen.generate_map(MapHexGenerator.Pattern.RANDOM)
		var picked: int = _gen.current_pattern
		if picked < MapHexGenerator.Pattern.FLAT_ARENA or picked > MapHexGenerator.Pattern.CHAOS_BEAUTIFUL:
			_failures += 1
			printerr("FAIL: RANDOM picked invalid pattern %d" % picked)
			return
		if not seen.has(picked):
			seen.append(picked)
	_check(seen.size() >= 8, "RANDOM covers most of the 10 patterns across 40 rolls (%d seen)" % seen.size())


func _test_determinism() -> void:
	_gen.generate_map(MapHexGenerator.Pattern.CHAOS_BEAUTIFUL)
	var first: Dictionary = _gen.tile_elevations.duplicate()
	_gen.generate_map(MapHexGenerator.Pattern.CHAOS_BEAUTIFUL)
	_check(_gen.tile_elevations == first, "pattern generation is deterministic")


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
	_gen.generate_map(MapHexGenerator.Pattern.TESSELLATION_STEPS)
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
	_check(is_equal_approx(_gen.get_max_top_y(), _gen.height_unit), "get_max_top_y: reset map tops at height_unit")


func _run() -> void:
	_test_level_hex_integration()
	if _failures == 0:
		print("ALL TESTS PASSED (%d checks)" % _passes)
		quit(0)
	else:
		printerr("TESTS FAILED: %d of %d checks" % [_failures, _passes + _failures])
		quit(1)


## The level boots with a random 10-pattern map and is fully populated.
func _test_level_hex_integration() -> void:
	seed(2026)
	var level: Node = (load(LEVEL_SCENE) as PackedScene).instantiate()
	root.add_child(level)
	await process_frame
	await process_frame

	var hex_map: Node = level.get_node_or_null("HexMap")
	if hex_map == null:
		_check(false, "level_hex: HexMap node exists")
		return
	_check(hex_map.tile_nodes.size() > 0, "level_hex: random map generated at boot (%d tiles)" % hex_map.tile_nodes.size())
	_check(hex_map.current_pattern >= MapHexGenerator.Pattern.FLAT_ARENA
		and hex_map.current_pattern <= MapHexGenerator.Pattern.CHAOS_BEAUTIFUL,
		"level_hex: boot used one of the 10 patterns (got %d)" % hex_map.current_pattern)
	_check(level.get_node_or_null("Player") != null, "level_hex: Player present")
	_check(level.get_node_or_null("Spawner") != null, "level_hex: Spawner present")
	_check(level.get_node_or_null("FallZone") != null, "level_hex: fall zone kill area present")
	var max_top: float = hex_map.get_max_top_y()
	_check(level.get_node("Player").position.y >= max_top,
		"level_hex: player spawns above the tallest tile (spawn y %s vs max %s)" % [level.get_node("Player").position.y, max_top])
	level.free()
