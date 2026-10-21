extends SceneTree
## Wave gate for the wave-based spawner (src/objects/spawner.gd).
##
## Run:  godot --headless --path . -s src/tests/wave_verify.gd
## Exit code 0 = GREEN (safe to ship), 1 = RED (do NOT use).
##
## Uses a TestSpawner subclass that injects dummy enemies via the
## _instantiate_enemy() virtual, disables engine-driven _process, and drives
## the spawner manually so every tick is deterministic:
##   1. wave 1 bursts base_count enemies immediately on scene start
##   2. clearing the pool -> wave_cleared + rest -> next wave with
##      base_count + count_per_wave (wave_started / wave_cleared heard)
##   3. clear-only: time passing while enemies live never advances the wave
##      (no countdown); only a full clear does
##   4. scaling rules: burst count capped, chaser ratio clamped at 1.0

class TestSpawner:
	extends "res://src/objects/spawner.gd"
	func _instantiate_enemy(_is_chaser: bool) -> Node3D:
		return Node3D.new()

var _spawner: TestSpawner
var _waves_started: Array[int] = []
var _waves_cleared: Array[int] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_setup()
	var fails := 0
	print("=== wave spawner verifier (headless gate) ===")

	fails += await _check_first_wave()
	fails += await _check_clear_advances_wave()
	fails += await _check_clear_only_no_countdown()
	fails += _check_scaling_rules()

	if fails == 0:
		print("\nVERDICT: GREEN  (waves spawn, clear, advance and scale)")
		quit(0)
	else:
		print("\nVERDICT: RED  (%d check(s) failed)" % fails)
		quit(1)


func _setup() -> void:
	_spawner = TestSpawner.new()
	_spawner.base_count = 2
	_spawner.count_per_wave = 1
	_spawner.max_count = 4
	_spawner.chaser_ratio_base = 0.0
	_spawner.chaser_ratio_per_wave = 0.0
	_spawner.rest_seconds = 0.05
	_spawner.wave_started.connect(func(w: int) -> void: _waves_started.append(w))
	_spawner.wave_cleared.connect(func(w: int) -> void: _waves_cleared.append(w))
	root.add_child(_spawner)
	# Engine ticks would make rest timing nondeterministic; the gate
	# drives _process manually with fixed deltas instead.
	_spawner.set_process(false)


## One deterministic manual tick plus a frame so deferred frees resolve.
func _step(dt: float) -> void:
	_spawner._process(dt)
	await process_frame
	await process_frame


func _free_all() -> void:
	for enemy in _spawner._alive.duplicate():
		enemy.queue_free()
	await process_frame
	await process_frame


func _check_first_wave() -> int:
	var ok := _waves_started == [1] and _spawner._wave == 1 \
			and _spawner._alive.size() == 2
	print("  [wave 1 immediate burst] started=%s wave=%d alive=%d  %s" % [
		_waves_started, _spawner._wave, _spawner._alive.size(),
		"OK" if ok else "FAIL"])
	return 0 if ok else 1


func _check_clear_advances_wave() -> int:
	await _free_all()
	# Pool empty -> wave cleared, resting before wave 2.
	var cleared_ok := _waves_cleared == [1] and _spawner._is_resting \
			and _spawner._alive.is_empty()
	await _step(0.1)  # rest_seconds = 0.05 -> far enough to fire wave 2
	var wave_ok := _spawner._wave == 2 and _waves_started == [1, 2] \
			and _spawner._alive.size() == 3 and not _spawner._is_resting
	var ok := cleared_ok and wave_ok
	print("  [clear -> next wave] cleared=%s started=%s wave2 alive=%d  %s" % [
		_waves_cleared, _waves_started, _spawner._alive.size(),
		"OK" if ok else "FAIL"])
	return 0 if ok else 1


## Clear-only: enemies still alive means the wave must NOT advance, no
## matter how much time passes. Only a full clear ends a wave.
func _check_clear_only_no_countdown() -> int:
	# Wave 2 is live with 3 enemies. Tick far longer than any old countdown
	# would have allowed — the wave must hold.
	for i in 4:
		await _step(0.5)  # 2.0s total; old countdown_base was 0.4s
	var held := _spawner._wave == 2 and not _spawner._is_resting \
			and _spawner._alive.size() == 3 and _waves_cleared == [1]
	# Now actually clear it — only then does it advance.
	await _free_all()
	var cleared := _spawner._is_resting and _waves_cleared == [1, 2]
	await _step(0.1)  # rest_seconds = 0.05 -> wave 3 spawns
	var advanced := _spawner._wave == 3 and _waves_started == [1, 2, 3] \
			and _spawner._alive.size() == 4 and not _spawner._is_resting
	var ok := held and cleared and advanced
	print("  [clear-only] held=%s cleared=%s advanced=%s  %s" % [
		held, cleared, advanced, "OK" if ok else "FAIL"])
	return 0 if ok else 1


func _check_scaling_rules() -> int:
	# Math-only instance: defaults-ish values, no scene tree needed.
	var s := TestSpawner.new()
	s.base_count = 3
	s.count_per_wave = 1
	s.max_count = 12
	s.chaser_ratio_base = 0.6
	s.chaser_ratio_per_wave = 0.05

	var ok := true
	ok = ok and s._count_for(1) == 3 and s._count_for(10) == 12 \
			and s._count_for(50) == 12
	ok = ok and is_equal_approx(s._chaser_ratio_for(1), 0.6) \
			and is_equal_approx(s._chaser_ratio_for(19), 1.0)
	print("  [scaling rules] count cap / ratio clamp  %s" % [
		"OK" if ok else "FAIL"])
	s.free()
	return 0 if ok else 1
