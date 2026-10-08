extends Node

## GameManager — autoloaded gameplay loop controller.
## Registered as "GameManager" in project.godot [autoload].
##
## Responsibilities:
##  - damage authority: player_hit() owns every incoming HP subtraction
##  - hit bookkeeping: any damage resets the regeneration grace timer
##  - kill zone: while the player is inside the arena's OuterKillZone, absorb
##    KILLZONE_DAMAGE_PER_SECOND once per KILLZONE_TICK_SECONDS
##  - regeneration: after HIT_GRACE_SECONDS without damage, heal REGEN_PER_SECOND
##  - color rules: colorprune hit gate, gun/enemy display colors, per-enemy
##    spawn roll — outgoing gun damage only, incoming hits are never gated
##  - game over: capture the final HUD score and switch to the game over scene
##
## The player and the kill zone register themselves from _ready(). Autoloads
## live outside the scene tree paths, so child-path lookups like $Player are
## impossible here.

## Scene shown when the player dies.
const GAME_OVER_SCENE: String = "res://src/scenes/game_over/game_over.tscn"
## Seconds without damage before regeneration starts.
const HIT_GRACE_SECONDS: float = 5.0
## Health points restored per second once the grace period has passed.
const REGEN_PER_SECOND: int = 5
## Health absorbed per second while the player is inside the OuterKillZone.
const KILLZONE_DAMAGE_PER_SECOND: int = 5
## Seconds between OuterKillZone damage ticks.
const KILLZONE_TICK_SECONDS: float = 1.0
## All color codes guns and enemies can carry (colorprune order: Red, Green, Blue).
const GUN_COLOR_CODES: Array[int] = [Weapon.GunColor.RED, Weapon.GunColor.GREEN, Weapon.GunColor.BLUE]

## Which system dealt a blow routed through player_hit().
enum HitSource { ENEMY, KILLZONE }

## Final score of the last run; read by the game over screen.
var final_score: int = 0

## Duck-typed reference to the registered player (player.gd has no class_name).
var _player = null
## Duck-typed reference to the registered OuterKillZone (arena.gd has no class_name).
var _kill_zone = null
var _time_since_last_hit: float = 0.0
var _regen_remainder: float = 0.0
var _killzone_tick: float = 0.0
var _is_killzone_active: bool = false
var _is_game_over: bool = false

func _process(delta: float) -> void:
	if _is_game_over:
		return
	if not is_instance_valid(_player):
		_player = null
		return
	if _player.health <= 0:
		return
	_tick_killzone(delta)
	_time_since_last_hit += delta
	if _time_since_last_hit < HIT_GRACE_SECONDS:
		return
	_regen_remainder += float(REGEN_PER_SECOND) * delta
	if _regen_remainder < 1.0:
		return
	var whole_points: int = int(_regen_remainder)
	_regen_remainder -= float(whole_points)
	_player.heal(whole_points)

## Called by player.gd in _ready(). Resets run state for a fresh scene.
func register_player(player) -> void:
	_player = player
	_time_since_last_hit = 0.0
	_regen_remainder = 0.0
	_is_game_over = false

## Called by arena.gd in _ready(). Subscribes to the OuterKillZone state.
func register_kill_zone(kill_zone) -> void:
	if is_instance_valid(_kill_zone) and _kill_zone.player_in_killzone_changed.is_connected(_on_killzone_changed):
		_kill_zone.player_in_killzone_changed.disconnect(_on_killzone_changed)
	_kill_zone = kill_zone
	_is_killzone_active = false
	_killzone_tick = 0.0
	if is_instance_valid(_kill_zone):
		_kill_zone.player_in_killzone_changed.connect(_on_killzone_changed)

## Single entry point for every incoming hit — enemy melee and the OuterKillZone
## tick today, projectiles later. Owns the HP subtraction, resets the
## regeneration grace timer, and routes death.
##
## `source` tags the origin so a projectile branch has somewhere to key off.
## Color matching deliberately does NOT gate this path — the colorprune rule is
## offense-only; see colors_match().
func player_hit(source: HitSource, amount: int) -> void:
	if _is_game_over or amount <= 0:
		return
	if not is_instance_valid(_player) or _player.health <= 0:
		return
	_player.health -= amount
	_time_since_last_hit = 0.0
	_regen_remainder = 0.0
	_player.health_updated.emit(_player.health)
	if OS.is_debug_build():
		print("[player_hit] ", HitSource.keys()[source], " -", amount, " -> ", _player.health)
	if _player.health <= 0:
		notify_player_died()

## Called when health reaches 0. Captures the score, then switches to the game
## over scene (deferred, so it is safe mid-signal).
func notify_player_died() -> void:
	if _is_game_over:
		return
	_is_game_over = true
	final_score = _read_score()
	get_tree().call_deferred("change_scene_to_file", GAME_OVER_SCENE)

## Display color for a color code — used to tint guns and enemies.
func gun_color_value(code: int) -> Color:
	match code:
		Weapon.GunColor.RED:
			return Color("EE4444")
		Weapon.GunColor.GREEN:
			return Color("44EE44")
		Weapon.GunColor.BLUE:
			return Color("4444EE")
		_:
			push_warning("GameManager: unknown gun color code %d, assuming BLUE" % code)
			return Color("4444EE")

## Color each enemy rolls on spawn (0 = RED, 1 = GREEN, 2 = BLUE).
func random_gun_color() -> int:
	return GUN_COLOR_CODES[randi() % GUN_COLOR_CODES.size()]

## Hit gate called by player.gd before gun damage is applied:
## colors match = the hit lands, mismatch = no damage at all.
## Outgoing only — player_hit() never consults this.
func colors_match(weapon_color: int, enemy_color: int) -> bool:
	return weapon_color == enemy_color

## Accumulates time inside the kill zone and applies one damage tick per second.
func _tick_killzone(delta: float) -> void:
	if not _is_killzone_active:
		return
	_killzone_tick += delta
	if _killzone_tick < KILLZONE_TICK_SECONDS:
		return
	_killzone_tick -= KILLZONE_TICK_SECONDS
	player_hit(HitSource.KILLZONE, KILLZONE_DAMAGE_PER_SECOND)

func _read_score() -> int:
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud == null:
		return 0
	var score: Variant = hud.get("score")
	return int(score) if score != null else 0

## Fired by arena.gd whenever the player crosses the OuterKillZone boundary.
func _on_killzone_changed(in_killzone: bool) -> void:
	_is_killzone_active = in_killzone
	_killzone_tick = 0.0
