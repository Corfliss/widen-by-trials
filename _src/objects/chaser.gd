extends Node3D

@export_group("Movement")
@export var chase_speed: float = 12.0
@export var y_offset: float = 0.5

@export_group("Combat")
@export var hit_radius: float = 2.0
@export var damage_amount: float = 5.0
@export var damage_cooldown: float = 0.5

var health: int = 3
var destroyed: bool = false
var kill_score: int = 2

var _player: CharacterBody3D
var _damage_time: float = 0.0

func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if _player == null:
		push_warning("Chaser: no player in group")

func _physics_process(delta: float) -> void:
	if _player == null or destroyed:
		return

	var dir: Vector3 = _player.global_position - global_position
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	dir = dir.normalized()

	global_position += dir * chase_speed * delta
	look_at(global_position + dir, Vector3.UP)

	_damage_time -= delta
	if _damage_time > 0.0:
		return
	if global_position.distance_to(_player.global_position) > hit_radius:
		return
	if _player.has_method("damage"):
		_player.damage(damage_amount)
		_damage_time = damage_cooldown

func damage(amount: int) -> void:
	health -= amount
	if health <= 0 and not destroyed:
		destroyed = true
		var hud := get_tree().get_first_node_in_group("hud")
		if hud != null and hud.has_method("add_score"):
			hud.add_score(kill_score)
		queue_free()
