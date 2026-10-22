extends SceneTree
## Terrain morph gate for the wave-driven map morph (map_hex_generator.gd).
##
## Run:  godot --headless --path . -s src/tests/terrain_wave_verify.gd
## Exit code 0 = GREEN (safe to ship), 1 = RED (do NOT use).
##
## Uses a TestSpawner that injects dummy Node3D enemies via the
## _instantiate_enemy() virtual and is driven manually, plus a real
## MapHexGenerator wired through spawner_path. Checks:
##   1. dummy wave clear -> terrain morph starts toward a random pattern;
##      tile_elevations flip to the target at once and the tile nodes are
##      the same instances (morph, not rebuild)
##   2. mid-morph the tile heights are still travelling (lerp, not snap)
##   3. a second clear mid-morph kills the old tween and retargets; once it
##      finishes, every height matches the newest target
##   4. a generator without spawner_path wired never morphs

class TestSpawner:
	extends "res://src/objects/spawner.gd"
	func _instantiate_enemy(_is_chaser: bool) -> Node3D:
		return Node3D.new()

const MapHexGeneratorScript := preload("res://src/objects/map_hex_generator.gd")

var _spawner: TestSpawner
var _gen: MapHexGenerator
var _morph_starts: Array[int] = []
var _fails: int = 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	print("=== wave terrain morph verifier (headless gate) ===")
	_setup()
	await _check_clear_triggers_morph()
	_check_mid_morph_is_lerping()
	await _check_interrupt_retargets()
	await _check_unwired_stays_flat()
	if _fails == 0:
		print("\nVERDICT: GREEN  (wave clears morph the terrain)")
		quit(0)
	else:
		print("\nVERDICT: RED  (%d check(s) failed)" % _fails)
		quit(1)


func _setup() -> void:
	_spawner = TestSpawner.new()
	_spawner.base_count = 2
	_spawner.count_per_wave = 1
	_spawner.max_count = 4
	_spawner.chaser_ratio_base = 0.0
	_spawner.chaser_ratio_per_wave = 0.0
	_spawner.bomber_ratio_base = 0.0
	_spawner.bomber_ratio_per_wave = 0.0
	_spawner.rest_seconds = 30.0  # holds wave 2 until the gate drives it
	_spawner.auto_start = false
	root.add_child(_spawner)
	# Engine rest timing must not race the gate; _process is driven manually.
	_spawner.set_process(false)

	_gen = MapHexGeneratorScript.new()
	_gen.name = "TestHexMap"
	_gen.map_radius = 3
	_gen.morph_seconds = 10.0  # long window so mid-morph state is observable
	_gen.spawner_path = _spawner.get_path()
	root.add_child(_gen)
	_gen.terrain_morph_started.connect(func(p: int) -> void: _morph_starts.append(p))

	_spawner.start_waves()  # wave 1: 2 dummy enemies


func _fail_if_not(ok: bool) -> void:
	if not ok:
		_fails += 1


## One deterministic manual tick plus frames so deferred frees resolve.
func _step(dt: float) -> void:
	_spawner._process(dt)
	await process_frame
	await process_frame


func _free_enemies() -> void:
	for enemy in _spawner._alive.duplicate():
		enemy.queue_free()
	await process_frame
	await process_frame


## Recompute a pattern's per-coord targets independently of the morph.
func _expected_targets(pattern: int) -> Dictionary:
	var coords: Array[Vector2i] = []
	coords.assign(_gen.tile_nodes.keys())
	var targets: Array[int] = _gen._apply_pattern(pattern, coords)
	var out := {}
	for i: int in coords.size():
		out[coords[i]] = targets[i]
	return out


func _check_clear_triggers_morph() -> void:
	var ids_before := {}
	for coord: Vector2i in _gen.tile_nodes:
		ids_before[coord] = _gen.tile_nodes[coord].get_instance_id()

	await _free_enemies()  # pool empty -> wave_cleared(1) -> morph

	var pattern: int = _gen.current_pattern
	var expected := _expected_targets(pattern)
	var pattern_ok := pattern >= MapHexGenerator.Pattern.FLAT_ARENA \
			and pattern <= MapHexGenerator.Pattern.CHAOS_BEAUTIFUL
	var started_ok := _morph_starts == [pattern]
	var data_ok := _gen.tile_elevations == expected
	var same_nodes := true
	for coord: Vector2i in _gen.tile_nodes:
		if _gen.tile_nodes[coord].get_instance_id() != ids_before[coord]:
			same_nodes = false
			break
	var ok := pattern_ok and started_ok and data_ok and same_nodes \
			and _spawner._is_resting
	_fail_if_not(ok)
	print("  [clear -> morph] started=%s pattern=%d data=target same-tiles=%s resting=%s  %s" % [
		_morph_starts, pattern, same_nodes, _spawner._is_resting,
		"OK" if ok else "FAIL"])


## With morph_seconds = 10 only a couple of engine frames have run, so at
## least one tile must still be below its (taller) target height.
func _check_mid_morph_is_lerping() -> void:
	var expected := _expected_targets(_gen.current_pattern)
	var travelling := false
	for coord: Vector2i in _gen.tile_nodes:
		var tile: CSGCylinder3D = _gen.tile_nodes[coord]
		if tile.height < _gen.height_unit * float(expected[coord]) - 0.01:
			travelling = true
			break
	_fail_if_not(travelling)
	print("  [mid-morph still lerping] %s" % ["OK" if travelling else "FAIL"])


func _check_interrupt_retargets() -> void:
	_spawner._process(31.0)  # rest elapsed -> wave 2: 3 dummy enemies
	if _spawner._wave != 2:
		_fail_if_not(false)
		print("  [interrupt retarget] setup failed (wave %d)" % _spawner._wave)
		return
	_gen.morph_seconds = 0.1  # the retargeted morph finishes fast
	await _free_enemies()     # wave_cleared(2) -> kill old tween, morph again
	# Poll instead of awaiting the signal: with a short morph the finished
	# emission could land between the free and the await.
	for i: int in 300:
		if _gen._morph_tween == null:
			break
		await process_frame
	var pattern: int = _gen.current_pattern
	var expected := _expected_targets(pattern)
	var heights_ok := true
	for coord: Vector2i in _gen.tile_nodes:
		var tile: CSGCylinder3D = _gen.tile_nodes[coord]
		if not is_equal_approx(tile.height, _gen.height_unit * float(expected[coord])):
			heights_ok = false
			break
	var ok := _morph_starts.size() == 2 and _morph_starts[1] == pattern \
			and heights_ok and _gen._morph_tween == null
	_fail_if_not(ok)
	print("  [interrupt retargets] started=%s final-heights=new-target=%s settled=%s  %s" % [
		_morph_starts, heights_ok, _gen._morph_tween == null,
		"OK" if ok else "FAIL"])


func _check_unwired_stays_flat() -> void:
	var flat := MapHexGeneratorScript.new()
	flat.name = "UnwiredHexMap"
	root.add_child(flat)  # random_pattern_on_ready = false -> flat reset
	await process_frame
	_spawner.wave_cleared.emit(99)  # wired gen morphs; unwired must not
	var ok := flat.current_pattern == MapHexGenerator.Pattern.RESET_FLAT
	for elevation: int in flat.tile_elevations.values():
		if elevation != flat.elevation_min:
			ok = false
	_fail_if_not(ok)
	print("  [unwired ignores wave_cleared] %s" % ["OK" if ok else "FAIL"])
	flat.free()
