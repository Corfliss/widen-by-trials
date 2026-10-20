extends Node3D

## Wave-based enemy spawner — replaces the old timer-ramp spawner.
##
## Wave 1 fires immediately on scene start. A wave ends when every enemy in
## the tracked pool has left the tree (clear), or when its countdown expires
## — expiry does NOT free survivors: they stay alive and carry into the next
## wave's clear-set, so pressure compounds and a full clear is still required.
## Every wave is harder: bigger burst, higher chaser ratio, less time.
## The player losing is game over (GameManager); the waves never stop until
## then.
##
## Tunables are @exports on this scene node (level.tscn) so they are editable
## in the Inspector — GameManager is an autoload and cannot expose them there.

signal wave_started(wave: int)
signal wave_cleared(wave: int)

@export_group("Waves")
## Enemies in wave 1.
@export var base_count: int = 3
## Extra enemies added to every burst beyond wave 1.
@export var count_per_wave: int = 1
## Ceiling for the per-wave burst size.
@export var max_count: int = 12
## Wave 1 countdown in seconds.
@export var countdown_base: float = 30.0
## Seconds removed from the countdown each wave.
@export var countdown_decrease: float = 2.0
## Countdown floor.
@export var countdown_min: float = 10.0
## Chance that a spawned enemy is a chaser in wave 1.
@export var chaser_ratio_base: float = 0.6
## Chaser-chance increase per wave.
@export var chaser_ratio_per_wave: float = 0.05
## Breather in seconds after a wave ends before the next one spawns.
@export var rest_seconds: float = 3.0

@export_group("Spawn Area")
@export var arena_radius: float = 14.0
@export var spawn_height: float = 5.0

var _wave: int = 0
var _time_left: float = 0.0
var _rest_left: float = 0.0
var _is_resting: bool = false
## Enemies still expected to die (includes carry-over survivors from expired
## waves).
var _alive: Array[Node3D] = []
var _chaser_scene: PackedScene
var _scout_scene: PackedScene

func _ready() -> void:
	# load() (not preload) so headless -s gates don't compile-load the enemy
	# scripts and their GameManager autoload references.
	_chaser_scene = load("res://src/objects/chaser.tscn")
	_scout_scene = load("res://src/objects/scout.tscn")
	_start_wave(1)

func _process(delta: float) -> void:
	if _is_resting:
		_rest_left -= delta
		if _rest_left <= 0.0:
			_is_resting = false
			_start_wave(_wave + 1)
		return
	_time_left -= delta
	if _time_left <= 0.0:
		_end_wave()

## Countdown expiry: survivors are kept — they join the next wave's clear-set.
func _end_wave() -> void:
	_is_resting = true
	_rest_left = rest_seconds
	wave_cleared.emit(_wave)

func _start_wave(wave: int) -> void:
	_wave = wave
	_time_left = _countdown_for(wave)
	for i in _count_for(wave):
		_spawn_one(_chaser_ratio_for(wave))
	wave_started.emit(wave)

func _spawn_one(chaser_ratio: float) -> void:
	var enemy: Node3D = _instantiate_enemy(randf() < chaser_ratio)
	var angle := randf_range(0.0, TAU)
	var dist := randf_range(2.0, arena_radius)
	enemy.position = Vector3(cos(angle) * dist, spawn_height, sin(angle) * dist)
	enemy.tree_exited.connect(_on_enemy_exited.bind(enemy))
	_alive.append(enemy)
	add_child(enemy)

## Virtual so the wave gate (src/tests/wave_verify.gd) can inject dummies.
func _instantiate_enemy(is_chaser: bool) -> Node3D:
	return _chaser_scene.instantiate() if is_chaser else _scout_scene.instantiate()

## Scaling rules — one-liners so the wave gate can assert them directly.
func _count_for(wave: int) -> int:
	return clampi(base_count + count_per_wave * (wave - 1), 1, max_count)

func _countdown_for(wave: int) -> float:
	return maxf(countdown_min, countdown_base - countdown_decrease * float(wave - 1))

func _chaser_ratio_for(wave: int) -> float:
	return clampf(chaser_ratio_base + chaser_ratio_per_wave * float(wave - 1), 0.0, 1.0)

func _on_enemy_exited(enemy: Node3D) -> void:
	_alive.erase(enemy)
	if not is_inside_tree() or _is_resting:
		return
	if _alive.is_empty():
		_end_wave()
