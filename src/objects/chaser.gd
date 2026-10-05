extends Node3D

@export_group("Movement")
@export var charge_speed: float = 16.0
@export var charge_distance: float = 8.0
@export var charge_y_level: float = 0.5

@export_group("Combat")
@export var damage_amount: float = 5.0

@export_group("Timing")
@export var idle_duration: float = 0.4

var health: int = 3
var destroyed: bool = false
var kill_score: int = 2

enum State { IDLE, CHARGING }

var _state: State = State.IDLE
var _player: CharacterBody3D
var _charge_start: Vector3
var _charge_dir: Vector3
var _hit_this_charge: bool = false
var _idle_time: float = 0.0

func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if _player == null:
		push_warning("Chaser: no player in group")
	$HitBox.body_entered.connect(_on_hit_box_entered)

func _physics_process(delta: float) -> void:
	if _player == null or destroyed:
		return

	match _state:
		State.IDLE:
			_idle_time -= delta
			_face_player()
			if _idle_time <= 0.0:
				_begin_charge()

		State.CHARGING:
			global_position += _charge_dir * charge_speed * delta
			if _charge_start.distance_to(global_position) >= charge_distance:
				_state = State.IDLE
				_idle_time = idle_duration

func _begin_charge() -> void:
	_state = State.CHARGING
	_hit_this_charge = false
	_charge_start = global_position
	var to_player: Vector3 = _player.global_position - global_position
	to_player.y = 0.0
	if to_player.length() < 0.01:
		to_player = Vector3.FORWARD
	_charge_dir = to_player.normalized()
	_face_dir(_charge_dir)

func _face_player() -> void:
	if _player == null:
		return
	var dir: Vector3 = _player.global_position - global_position
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	_face_dir(dir)

func _face_dir(dir: Vector3) -> void:
	look_at(global_position + dir, Vector3.UP)

func _on_hit_box_entered(body: Node3D) -> void:
	if _state != State.CHARGING or _hit_this_charge or body != _player:
		return
	if _player.has_method("damage"):
		_player.damage(damage_amount)
		_hit_this_charge = true

func damage(amount: int) -> void:
	health -= amount
	if health <= 0 and not destroyed:
		destroyed = true
		var hud := get_tree().get_first_node_in_group("hud")
		if hud != null and hud.has_method("add_score"):
			hud.add_score(kill_score)
		queue_free()
