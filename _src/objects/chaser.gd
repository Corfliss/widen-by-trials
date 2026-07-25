extends Node3D

@export_group("Timing")
@export var idle_duration: float = 0.5
@export var idle_duration_variance: float = 0.0

@export_group("Movement")
@export var chase_speed: float = 15.0
@export var look_ahead_time: float = 1.0
@export var overshoot_distance: float = 3.0

@export_group("Combat")
@export var hit_radius: float = 1.5
@export var damage_amount: float = 10.0
@export var chaser_y_offset: float = 0.5

@export_group("Facing")
@export var facing_offset_degrees: float = 90.0

enum State { IDLE, CHASING }

var _state: State = State.IDLE
var _player: CharacterBody3D
var _hit_this_chase: bool = false
var _chase_dir: Vector3 = Vector3.FORWARD
var _chase_end: Vector3

@onready var _idle_timer: Timer = $IdleTimer
@onready var _hit_box: Area3D = $HitBox
@onready var _hit_shape: CollisionShape3D = $HitBox/HitShape


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if _player == null:
		push_warning("Chaser: no player in group")
		return

	var sphere := SphereShape3D.new()
	sphere.radius = hit_radius
	_hit_shape.shape = sphere

	_idle_timer.one_shot = true
	_idle_timer.timeout.connect(_on_idle_timeout)
	_hit_box.body_entered.connect(_on_hit_box_entered)

	_start_idle()


func _physics_process(delta: float) -> void:
	if _player == null or _state != State.CHASING:
		return

	global_position = global_position.move_toward(_chase_end, chase_speed * delta)

	if global_position.distance_to(_chase_end) <= chase_speed * delta:
		_start_idle()


func _start_idle() -> void:
	_state = State.IDLE
	if _player != null:
		_face_target(_player.global_position + Vector3.UP * chaser_y_offset)
	var jitter := randf_range(-idle_duration_variance, idle_duration_variance)
	_idle_timer.wait_time = max(0.01, idle_duration + jitter)
	_idle_timer.start()


func _begin_chase() -> void:
	_state = State.CHASING
	_hit_this_chase = false

	var predicted: Vector3 = _player.global_position + _player.velocity * look_ahead_time
	var to_predicted: Vector3 = predicted - global_position
	_chase_dir = to_predicted.normalized() if to_predicted.length() > 0.001 else Vector3.FORWARD
	_chase_end = predicted + _chase_dir * overshoot_distance
	_chase_end.y = global_position.y

	_face_target(global_position + _chase_dir)


func _face_target(target: Vector3) -> void:
	if global_position.distance_squared_to(target) < 0.0001:
		return
	look_at(target, Vector3.UP)
	rotate_y(deg_to_rad(facing_offset_degrees))


func _on_idle_timeout() -> void:
	if _player != null:
		_begin_chase()


func _on_hit_box_entered(body: CharacterBody3D) -> void:
	if _state != State.CHASING or _hit_this_chase:
		return
	if body == _player and _player.has_method("damage"):
		_player.damage(damage_amount)
		_hit_this_chase = true
