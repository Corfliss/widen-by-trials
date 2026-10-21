extends CanvasLayer

## Calibration tutorial for level.tscn — four gated phases, then play starts:
##   LOOK    mouse-look check (WASD frozen)
##   MOVE    WASD check (movement unlocked, all four keys must be used)
##   WEAPONS cycle through every weapon in the loadout (Q / E / scroll)
##   JUMP    a double jump performed during this phase starts play
##   DONE    shooting unlocked, spawner releases wave 1, prompt fades out
##
## This node only observes input and flips the player's movement_locked /
## shooting_locked gates — gameplay rules stay in player.gd / spawner.gd.

enum Phase { LOOK, MOVE, WEAPONS, JUMP, DONE }

## Move actions checked during Phase MOVE, in UI row order (W A S D).
const MOVE_ACTIONS: Array[StringName] = [
	&"move_forward", &"move_left", &"move_back", &"move_right"
]

## Unchecked / checked label brightness (scene labels start dim).
const COLOR_DIM := Color(1, 1, 1, 0.35)
const COLOR_LIT := Color(0.45, 1.0, 0.55, 1.0)

## Look travel gained per physics frame while the gamepad stick is held;
## 200 threshold / 10 per frame ≈ 0.33 s of held stick.
const STICK_LOOK_STEP := 10.0

@export var player_path: NodePath
@export var spawner_path: NodePath
## Cumulative mouse pixels required to finish the LOOK phase.
@export_range(1.0, 2000.0) var look_threshold: float = 200.0

## Current phase — public so src/tests/test_tutorial.gd can assert on it.
var phase: Phase = Phase.LOOK
var _look_travel := 0.0
var _keys_checked: Array[StringName] = []
var _weapons_checked: Array[int] = []

# Untyped on purpose: player.gd and spawner.gd have no class_name, so member
# access is duck-typed — same pattern as GameManager._player.
@onready var _player = get_node(player_path)
@onready var _spawner = get_node(spawner_path)
@onready var _prompt: Control = %Prompt
@onready var _title: Label = %Title
@onready var _keys_row: HBoxContainer = %KeysRow
@onready var _weapons_row: HBoxContainer = %WeaponsRow
@onready var _jump_hint: Label = %JumpHint
@onready var _key_labels: Dictionary = {
	&"move_forward": %KeyW,
	&"move_left": %KeyA,
	&"move_back": %KeyS,
	&"move_right": %KeyD,
}
@onready var _weapon_labels: Array[Label] = [%Weapon1, %Weapon2, %Weapon3]


func _ready() -> void:
	_player.movement_locked = true
	_player.shooting_locked = true
	_player.double_jumped.connect(_on_double_jumped)
	_weapons_checked.append(_player.weapon_index) # weapon already in hand counts
	_refresh_ui()


func _input(event: InputEvent) -> void:
	if phase != Phase.LOOK:
		return
	if event is InputEventMouseMotion:
		_register_look(event.relative.length())


func _physics_process(_delta: float) -> void:
	match phase:
		Phase.LOOK:
			# Gamepad right stick counts as looking too — a mouse-only check
			# would soft-lock controller players.
			var stick := Input.get_vector("camera_right", "camera_left", "camera_down", "camera_up")
			if stick.length() > 0.5:
				_register_look(STICK_LOOK_STEP)
		Phase.MOVE:
			var changed := false
			for action in MOVE_ACTIONS:
				if Input.is_action_just_pressed(action) and not _keys_checked.has(action):
					_keys_checked.append(action)
					changed = true
			if _keys_checked.size() == MOVE_ACTIONS.size():
				_advance()
			elif changed:
				_refresh_ui()
		Phase.WEAPONS:
			var index: int = _player.weapon_index
			if not _weapons_checked.has(index):
				_weapons_checked.append(index)
				if _weapons_checked.size() >= _player.weapons.size():
					_advance()
				else:
					_refresh_ui()
		_:
			pass


## Accumulates look travel (mouse pixels or gamepad ticks) and unlocks
## movement the moment the LOOK threshold is crossed.
func _register_look(amount: float) -> void:
	_look_travel += amount
	if _look_travel >= look_threshold:
		_player.movement_locked = false
		_advance()


## Steps LOOK -> MOVE -> WEAPONS -> JUMP. The JUMP phase ends only through
## _on_double_jumped() -> _complete(), never by falling through here.
func _advance() -> void:
	match phase:
		Phase.LOOK:
			phase = Phase.MOVE
		Phase.MOVE:
			phase = Phase.WEAPONS
		_:
			phase = Phase.JUMP
	_refresh_ui()


## Double jump performed during Phase JUMP: open every gate and start play.
func _complete() -> void:
	phase = Phase.DONE
	_player.shooting_locked = false # movement already unlocked after LOOK
	_spawner.start_waves()
	set_physics_process(false)
	var tween := create_tween()
	tween.tween_property(_prompt, "modulate:a", 0.0, 0.5)


## Ignores double jumps performed before Phase JUMP — play starts only on
## one the player performs when the prompt asks for it.
func _on_double_jumped() -> void:
	if phase == Phase.JUMP:
		_complete()


func _refresh_ui() -> void:
	_title.text = _phase_text()
	_keys_row.visible = phase == Phase.MOVE
	_weapons_row.visible = phase == Phase.WEAPONS
	_jump_hint.visible = phase == Phase.JUMP
	for action in MOVE_ACTIONS:
		_lit(_key_labels[action] as Label, _keys_checked.has(action))
	for i in _weapon_labels.size():
		_lit(_weapon_labels[i], _weapons_checked.has(i))


func _phase_text() -> String:
	match phase:
		Phase.LOOK:
			return "LOOK AROUND — move the mouse"
		Phase.MOVE:
			return "MOVE — press every key"
		Phase.WEAPONS:
			return "SWITCH WEAPONS — Q / E / scroll"
		Phase.JUMP:
			return "DOUBLE JUMP TO BEGIN"
		_:
			return ""


func _lit(label: Label, checked: bool) -> void:
	label.modulate = COLOR_LIT if checked else COLOR_DIM
