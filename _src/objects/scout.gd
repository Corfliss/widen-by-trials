extends Node3D

@export_group("Timing")
@export var idle_time_min: float = 0.2
@export var idle_time_max: float = 0.6
@export var predict_seconds: float = 2.0
@export var telegraph_duration: float = 1.0
@export var fire_duration: float = 1.0
@export var reposition_timeout: float = 4.0

@export_group("Movement")
@export var move_speed: float = 6.0
@export var min_safe_distance: float = 15.0
@export var max_safe_distance: float = 25.0
@export var arrival_threshold: float = 1.0

@export_group("Combat")
@export var attack_damage: float = 5.0
@export var raycast_range: float = 60.0

enum State { IDLE, REPOSITION, TELEGRAPH, FIRE }
var _state: int = State.IDLE
var _state_timer: float = 0.0
var _player: CharacterBody3D
var _reposition_target: Vector3
var _predicted_target: Vector3

@onready var _raycast: RayCast3D = $RayCast3D

func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if _player == null:
		push_warning("Scout: no player in group")
		return
	_raycast.enabled = false
	_enter_idle()

func _process(delta: float) -> void:
	if _player == null:
		return
	_state_timer -= delta
	match _state:
		State.IDLE:
			if _state_timer <= 0.0:
				_enter_reposition()
		State.REPOSITION:
			global_position = global_position.move_toward(_reposition_target, move_speed * delta)
			var arrived := global_position.distance_to(_reposition_target) <= arrival_threshold
			if arrived or _state_timer <= 0.0:
				_enter_telegraph()
		State.TELEGRAPH:
			if _state_timer <= 0.0:
				_enter_fire()
		State.FIRE:
			if _state_timer <= 0.0:
				_enter_idle()

func _enter_idle() -> void:
	_state = State.IDLE
	_state_timer = randf_range(idle_time_min, idle_time_max)
	_raycast.enabled = false

func _enter_reposition() -> void:
	_state = State.REPOSITION
	_state_timer = reposition_timeout
	var angle := randf_range(0.0, TAU)
	var dist := randf_range(min_safe_distance, max_safe_distance)
	var target := _player.global_position + Vector3(cos(angle), 0.0, sin(angle)) * dist
	target.y = global_position.y
	_reposition_target = target

func _enter_telegraph() -> void:
	_state = State.TELEGRAPH
	_state_timer = telegraph_duration
	_predicted_target = _player.global_position + _player.velocity * predict_seconds
	_face_target(_predicted_target)
	_raycast.target_position = _raycast.to_local(_predicted_target)
	_raycast.enabled = true

func _enter_fire() -> void:
	_state = State.FIRE
	_state_timer = fire_duration
	_raycast.force_raycast_update()
	if _raycast.is_colliding():
		var collider := _raycast.get_collider()
		if collider == _player and _player.has_method("damage"):
			_player.damage(attack_damage)
	_raycast.enabled = false

func _face_target(target_pos: Vector3) -> void:
	var flat_target := Vector3(target_pos.x, global_position.y, target_pos.z)
	if global_position.distance_to(flat_target) < 0.01:
		return
	look_at(flat_target, Vector3.UP)
	rotate_object_local(Vector3.UP, -PI / 2.0)
