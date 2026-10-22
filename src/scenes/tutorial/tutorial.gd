extends Node

## Calibration tutorial for level.tscn — five gated phases, then play starts:
##   WASD     movement+jump+frozen, WASD and look observed (not obeyed)
##   WEAPONS  movement unlocked; every weapon in the loadout must be visited
##   SHOOT    shooting unlocked; kill 3 frozen targets (colors force switching)
##   NULLWIDE hold X, release to kill 6 color-matched frozen targets (9999)
##   JUMP     a double jump starts play
##   DONE     waves running, onboarding hidden
##
## UI lives in the player's HUD (HUD/Onboarding, see player.tscn); this
## controller sits in level.tscn next to the spawner. It only observes input
## and flips the player's movement_locked / shooting_locked gates — gameplay
## rules stay in player.gd / spawner.gd. Tutorial targets are real enemy
## scenes spawned frozen (AI off): they never fight back.

enum Phase { WASD, WEAPONS, SHOOT, NULLWIDE, JUMP, DONE }

## Complete-look travel in pixels before the WASD phase completes.
const LOOK_TRAVEL_REQ := 200.0

const ENEMY_SCENES: Array[PackedScene] = [
	preload("res://src/objects/chaser.tscn"),
	preload("res://src/objects/sniper.tscn"),
	preload("res://src/objects/bomber.tscn"),
]
## SHOOT target colors, nearest first: the player holds WHITE on entry, so the
## nearest dies immediately and the rest force weapon switches.
const SHOOT_COLORS := [Weapon.GunColor.WHITE, Weapon.GunColor.BLACK, Weapon.GunColor.RED]

const COLOR_LIT := Color(0.45, 1.0, 0.55)
const COLOR_DIM := Color(1, 1, 1, 0.35)
const COLOR_CURRENT := Color(1, 1, 1, 1)

const WASD_ACTIONS: Array[StringName] = [&"move_forward", &"move_back", &"move_left", &"move_right"]

@export var player_path: NodePath = NodePath("../Player")
@export var spawner_path: NodePath = NodePath("../Spawner")

var phase: Phase = Phase.WASD
var _keys_seen: Dictionary = {}
var _look_traveled := 0.0
var _weapons_seen: Dictionary = {}
var _spawned: Array[Node3D] = []

@onready var _player = get_node(player_path)
@onready var _spawner = get_node(spawner_path)
var _onboarding: Control
var _title: Label
var _steps: Array[Label] = []
var _keys_row: HBoxContainer
var _weapons_row: HBoxContainer
var _jump_hint: Label
var _key_labels: Dictionary = {}
var _weapon_labels: Array[Label] = []


func _ready() -> void:
	# Sibling paths resolve inside level.tscn; bail quietly if run standalone.
	if _player == null or _spawner == null:
		set_physics_process(false)
		return
	_setup_ui()
	_player.movement_locked = true
	_player.shooting_locked = true
	_player.double_jumped.connect(_on_player_double_jumped)
	_start_phase(Phase.WASD)


func _setup_ui() -> void:
	_onboarding = _player.get_node("HUD/Onboarding")
	_title = _onboarding.get_node("Stack/Title")
	for i in 5:
		_steps.append(_onboarding.get_node("Stack/StepsList/Step%d" % (i + 1)))
	_keys_row = _onboarding.get_node("Stack/KeysRow")
	_weapons_row = _onboarding.get_node("Stack/WeaponsRow")
	_jump_hint = _onboarding.get_node("Stack/JumpHint")
	_key_labels = {
		&"move_forward": _onboarding.get_node("Stack/KeysRow/KeyW"),
		&"move_back": _onboarding.get_node("Stack/KeysRow/KeyS"),
		&"move_left": _onboarding.get_node("Stack/KeysRow/KeyA"),
		&"move_right": _onboarding.get_node("Stack/KeysRow/KeyD"),
	}
	for i in 3:
		_weapon_labels.append(_onboarding.get_node("Stack/WeaponsRow/Weapon%d" % (i + 1)))


func _input(event: InputEvent) -> void:
	if phase != Phase.WASD or not event is InputEventMouseMotion:
		return
	_look_traveled += event.relative.length()
	# Look can complete the WASD phase on its own frame — the test (and a
	# quick mouse flick) may not wait for a physics tick to confirm it.
	_check_wasd()


func _physics_process(_delta: float) -> void:
	match phase:
		Phase.WASD:
			_check_wasd()
		Phase.WEAPONS:
			_weapons_seen[_player.weapon_index] = true
			if _weapons_seen.size() >= _player.weapons.size():
				_advance()
		Phase.SHOOT, Phase.NULLWIDE:
			_prune_dead()
			if _spawned.is_empty():
				_advance()
			elif phase == Phase.NULLWIDE:
				# Mirror the held color so one release clears the whole fan,
				# even if the player toggles weapons mid-phase.
				# ponytail: only the kill gate follows the gun — the spawned
				# tint stays as-is on a mid-phase toggle (visual-only mismatch).
				for enemy in _spawned:
					enemy.enemy_color_code = int(_player.weapon.gun_color)


func _check_wasd() -> void:
	for action in WASD_ACTIONS:
		if not _keys_seen.has(action) and Input.is_action_pressed(action):
			_keys_seen[action] = true
			var label: Label = _key_labels[action]
			label.modulate = COLOR_LIT
	if _keys_seen.size() >= WASD_ACTIONS.size() and _look_traveled >= LOOK_TRAVEL_REQ:
		_advance()


func _start_phase(p: Phase) -> void:
	phase = p
	_refresh_ui()
	match phase:
		Phase.WEAPONS:
			_player.movement_locked = false
			_weapons_seen = {_player.weapon_index: true}
			var start_label: Label = _weapon_labels[_player.weapon_index]
			start_label.modulate = COLOR_LIT
		Phase.SHOOT:
			_player.shooting_locked = false
			_spawn_shoot_line()
		Phase.NULLWIDE:
			# 3 hp vs 8-25 damage guns: bullets would bypass the one-release
			# requirement, so normal fire is re-locked until the release.
			_player.shooting_locked = true
			_spawn_nullwide_fan()
		Phase.JUMP:
			pass
		Phase.DONE:
			_free_spawned()
			_player.movement_locked = false
			_player.shooting_locked = false
			_spawner.start_waves()
			_onboarding.visible = false # instant hide — play starts now
			set_physics_process(false)


func _advance() -> void:
	if phase == Phase.DONE:
		return
	_start_phase(phase as int + 1)


func _refresh_ui() -> void:
	_title.text = phase_text()
	for i in _steps.size():
		if i < int(phase):
			_steps[i].modulate = COLOR_LIT
		elif i == int(phase):
			_steps[i].modulate = COLOR_CURRENT
		else:
			_steps[i].modulate = COLOR_DIM
	_keys_row.visible = phase == Phase.WASD
	_weapons_row.visible = phase == Phase.WEAPONS
	_jump_hint.visible = phase == Phase.JUMP


func phase_text() -> String:
	match phase:
		Phase.WASD:
			return "LOOK + MOVE — mouse and every key"
		Phase.WEAPONS:
			return "SWITCH WEAPONS — Q / E / scroll"
		Phase.SHOOT:
			return "SHOOT THE TARGET"
		Phase.NULLWIDE:
			return "HOLD X — RELEASE TO KILL"
		Phase.JUMP:
			return "DOUBLE JUMP TO BEGIN"
		Phase.DONE:
			return ""
	return ""


## ponytail: single sightline — the targets sit on the aim axis and die
## nearest-first, so the test needs no camera aiming. Upgrade to a lateral
## spread (plus test-driven look) if targets must be independently hittable.
func _spawn_shoot_line() -> void:
	var cam: Transform3D = _player.camera.global_transform
	for i in SHOOT_COLORS.size():
		var enemy := _instantiate_enemy(ENEMY_SCENES[randi() % ENEMY_SCENES.size()], int(SHOOT_COLORS[i]))
		enemy.name = "TutorialEnemy%d" % i
		get_parent().add_child(enemy)
		enemy.global_position = cam.origin - cam.basis.z * (6.0 + i * 3.0)
		_freeze(enemy)


## Fan inside the 30 deg lock cone (4.8 m off-axis at 10 m ≈ 25.6 deg).
func _spawn_nullwide_fan() -> void:
	var cam: Transform3D = _player.camera.global_transform
	var held := int(_player.weapon.gun_color)
	for i in 6:
		var enemy := _instantiate_enemy(ENEMY_SCENES[i % ENEMY_SCENES.size()], held)
		enemy.name = "TutorialEnemy%d" % i
		get_parent().add_child(enemy)
		enemy.global_position = cam.origin + cam.basis.x * (-4.8 + i * 1.92) - cam.basis.z * 10.0
		_freeze(enemy)
		# ponytail: the lock sweep must be deterministic — enemy hitboxes are
		# offset from their roots and vary wildly per type (a sniper sphere is
		# ~1.9 m radius), so a neighbour's collider can swallow another's LOS
		# ray depending on the player's yaw. Zero the layers so only the cone
		# check gates calibration locks; the ray segment ends at the fan, well
		# short of the arena wall. Wave enemies keep their real layers.
		# Ceiling: adjacent frozen props can still visually overlap; upgrade to
		# per-type spacing once a wider arena guarantees a clean fan.
		for area in enemy.find_children("*", "Area3D", true, false):
			area.collision_layer = 0


func _instantiate_enemy(scene: PackedScene, color: int) -> Node3D:
	var enemy = scene.instantiate() # untyped: preset_color only exists on the enemy scripts
	enemy.preset_color = color # forced before add_child — _ready must not roll its own
	_spawned.append(enemy)
	return enemy


## Frozen prop: no AI ticks, no attacks; damage()/death still work.
func _freeze(enemy: Node3D) -> void:
	enemy.set_process(false)
	enemy.set_physics_process(false)


func _prune_dead() -> void:
	for i in range(_spawned.size() - 1, -1, -1):
		var enemy := _spawned[i]
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			_spawned.remove_at(i)


func _free_spawned() -> void:
	for enemy in _spawned:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_spawned.clear()


func _on_player_double_jumped() -> void:
	if phase == Phase.JUMP:
		_advance()
