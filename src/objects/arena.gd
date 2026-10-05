extends Area3D

@export var inner_radius: float = 15.0

var _player: CharacterBody3D
var _damage_timer: float = 0.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _process(delta: float) -> void:
	if _player == null:
		return
	if _player.global_position.length() <= inner_radius:
		_damage_timer = 0.0
		return
	_damage_timer += delta
	if _damage_timer >= 1.0:
		_damage_timer -= 1.0
		if _player.has_method("damage"):
			_player.damage(1)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player = body as CharacterBody3D
		_damage_timer = 0.0

func _on_body_exited(body: Node) -> void:
	if body == _player:
		_player = null
