extends Node3D

@export var arena_radius: float = 14.0
@export var initial_interval: float = 5.0
@export var min_interval: float = 0.5
@export var ramp_rate: float = 0.95
@export var spawn_height: float = 1.0

var _time: float = 0.0
var _current_interval: float
var _chaser_scene: PackedScene
var _scout_scene: PackedScene

func _ready() -> void:
	_current_interval = initial_interval
	_chaser_scene = preload("res://_src/objects/chaser.tscn")
	_scout_scene = preload("res://_src/objects/scout.tscn")
	_spawn_wave()

func _process(delta: float) -> void:
	_time += delta
	if _time >= _current_interval:
		_time = 0.0
		_current_interval = max(min_interval, _current_interval * ramp_rate)
		_spawn_wave()

func _spawn_wave() -> void:
	var count: int = randi_range(1, 3)
	for i in count:
		var is_chaser: bool = randf() < 0.6
		var enemy: Node3D = _chaser_scene.instantiate() if is_chaser else _scout_scene.instantiate()
		var angle := randf_range(0.0, TAU)
		var dist := randf_range(2.0, arena_radius)
		enemy.position = Vector3(cos(angle) * dist, spawn_height, sin(angle) * dist)
		add_child(enemy)
