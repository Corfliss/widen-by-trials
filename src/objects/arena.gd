extends Area3D

## OuterKillZone — bounds the playable area of arena.tscn.
##
## Reports whether the player is inside this Area3D *and* beyond `inner_radius`
## from the arena centre. Damage itself is owned by GameManager, which runs the
## 5 HP/sec tick once player_hit() is reached.

## Emitted whenever the player crosses in or out of the damaging region.
signal player_in_killzone_changed(in_killzone: bool)

@export var inner_radius: float = 15.0

var _player: CharacterBody3D
var _is_in_killzone: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	GameManager.register_kill_zone(self)

func _process(_delta: float) -> void:
	if _player == null:
		_set_in_killzone(false)
		return
	_set_in_killzone(_player.global_position.length() > inner_radius)

func _set_in_killzone(value: bool) -> void:
	if _is_in_killzone == value:
		return
	_is_in_killzone = value
	player_in_killzone_changed.emit(value)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player = body as CharacterBody3D
		_set_in_killzone(_player.global_position.length() > inner_radius)

func _on_body_exited(body: Node) -> void:
	if body == _player:
		_player = null
		_set_in_killzone(false)
