extends Node

## GameManager — autoloaded gameplay loop controller.
## Registered as "GameManager" in project.godot [autoload].
##
## Responsibilities:
##  - hit bookkeeping: any damage resets the regeneration grace timer
##  - regeneration: after HIT_GRACE_SECONDS without damage, heal REGEN_PER_SECOND
##  - game over: capture the final HUD score and switch to the game over scene
##
## The player registers itself from its _ready(). Autoloads live outside the
## scene tree paths, so child-path lookups like $Player are impossible here.

## Scene shown when the player dies.
const GAME_OVER_SCENE: String = "res://src/scenes/game_over/game_over.tscn"
## Seconds without damage before regeneration starts.
const HIT_GRACE_SECONDS: float = 5.0
## Health points restored per second once the grace period has passed.
const REGEN_PER_SECOND: int = 5

## Final score of the last run; read by the game over screen.
var final_score: int = 0

## Duck-typed reference to the registered player (player.gd has no class_name).
var _player = null
var _time_since_last_hit: float = 0.0
var _regen_remainder: float = 0.0
var _is_game_over: bool = false

## Called by player.gd in _ready(). Resets run state for a fresh scene.
func register_player(player) -> void:
	_player = player
	_time_since_last_hit = 0.0
	_regen_remainder = 0.0
	_is_game_over = false

func _process(delta: float) -> void:
	if _is_game_over:
		return
	if not is_instance_valid(_player):
		_player = null
		return
	if _player.health <= 0:
		return
	_time_since_last_hit += delta
	if _time_since_last_hit < HIT_GRACE_SECONDS:
		return
	_regen_remainder += float(REGEN_PER_SECOND) * delta
	if _regen_remainder < 1.0:
		return
	var whole_points: int = int(_regen_remainder)
	_regen_remainder -= float(whole_points)
	_player.heal(whole_points)

## Called by player.gd damage(). Resets the regeneration grace timer.
func notify_player_hit() -> void:
	if _is_game_over:
		return
	_time_since_last_hit = 0.0
	_regen_remainder = 0.0

## Called by player.gd when health reaches 0. Captures the score, then
## switches to the game over scene (deferred, so it is safe mid-signal).
func notify_player_died() -> void:
	if _is_game_over:
		return
	_is_game_over = true
	final_score = _read_score()
	get_tree().call_deferred("change_scene_to_file", GAME_OVER_SCENE)

func _read_score() -> int:
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud == null:
		return 0
	var score: Variant = hud.get("score")
	return int(score) if score != null else 0
