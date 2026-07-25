extends Node3D

@export var player: Node3D
@export var idle_duration: float = 0.5
@export var chase_speed: float = 15.0
@export var look_ahead_time: float = 1.0
@export var overshoot_distance: float = 3.0
@export var hit_radius: float = 1.5
@export var damage_amount: float = 10.0
@export var chaser_y_offset: float = 0.5

# ponytail: distance-based hit check, linear approach, minimalState machine, no collision

enum State { IDLE, CHASING }

var _state: int = State.IDLE
var _time: float = 0.0
var _predicted_target: Vector3
var _hit_this_chase: bool = false

func _ready() -> void:
	if player == null:
		push_warning("Chaser: player not assigned")

func _process(delta: float) -> void:
	match _state:
		State.IDLE:
			_time += delta
			if _time >= idle_duration and player != null:
				_state = State.CHASING
				_hit_this_chase = false
				_time = 0.0
		State.CHASING:
			_predicted_target = player.global_position + player.velocity * look_ahead_time
			var dir: Vector3 = (_predicted_target - global_position).normalized()
			if dir.length() == 0:
				dir = Vector3.FORWARD
			var chase_end: Vector3 = _predicted_target + dir * overshoot_distance
			
			look_at(player.global_position + Vector3.UP * chaser_y_offset, Vector3.UP)
			rotate_y(deg_to_rad(-90))
			
			global_position = global_position.move_toward(chase_end, chase_speed * delta)
			
			if !_hit_this_chase and global_position.distance_to(player.global_position) <= hit_radius:
				if player.has_method("damage"):
					player.damage(damage_amount)
					_hit_this_chase = true
			
			if global_position.distance_to(chase_end) <= (chase_speed * delta):
				_state = State.IDLE
				_time = 0.0
