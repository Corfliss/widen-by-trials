extends Node3D

@export_group("Movement")
@export var charge_speed: float = 16.0
## Distance flown past the lead point, along the locked aim direction.
@export var overshoot_distance: float = 3.0

@export_group("Aim")
## Player-movement lead, in seconds.
@export var look_ahead_time: float = 0.5
## Stationary aim-lerp time before the charge locks.
@export var reorient_duration: float = 0.5
## Aim-direction slerp rate (1/s). At 12 the aim converges in about 0.5 s.
@export var reorient_speed: float = 12.0

@export_group("Vertical")
## Random aim height above the player, in multiples of the player capsule height.
@export var min_height_scale: float = 0.5
@export var max_height_scale: float = 1.5
## Used when the player's capsule cannot be measured.
@export var fallback_player_height: float = 1.0

@export_group("Combat")
@export var damage_amount: int = 10

var health: int = 3
var destroyed: bool = false
var kill_score: int = 2
## Color code rolled on spawn — guns of any other color deal no damage to this enemy.
var enemy_color_code: int = Weapon.GunColor.WHITE
## Tutorial targets set this before add_child to force a color instead of rolling.
var preset_color := -1

enum State { REORIENT, CHARGE }

var _state: State = State.REORIENT
var _state_time: float = 0.0
var _player: CharacterBody3D
var _player_height: float = 1.0
var _aim_dir: Vector3 = Vector3.FORWARD
var _height_scale: float = 1.0
var _charge_target: Vector3
var _hit_this_charge: bool = false
var _tint: Color = Color.WHITE
var _wire_mat: ShaderMaterial
var _flash_tween: Tween

func _ready() -> void:
	add_to_group("enemy")
	_apply_random_color()
	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if _player == null:
		push_warning("Chaser: no player in group")
	else:
		_player_height = _measure_player_height()
	$HitBox.body_entered.connect(_on_hit_box_entered)
	_begin_reorient()

## Rolls this enemy's color and tints its wireframe material to match,
## so the player can read which gun will damage it (colorprune-style).
func _apply_random_color() -> void:
	enemy_color_code = preset_color if preset_color >= 0 else GameManager.random_gun_color()
	var tint: Color = GameManager.gun_color_value(enemy_color_code)
	_tint = tint
	var mesh := $Cone as MeshInstance3D
	var base := mesh.get_surface_override_material(0) as ShaderMaterial
	if base == null:
		return
	var mat := base.duplicate() as ShaderMaterial
	mat.set_shader_parameter("wire_color", tint)
	mat.set_shader_parameter("face_color", tint.darkened(0.8))
	mesh.set_surface_override_material(0, mat)
	_wire_mat = mat

func _physics_process(delta: float) -> void:
	if _player == null or destroyed:
		return

	match _state:
		State.REORIENT:
			_tick_reorient(delta)
		State.CHARGE:
			_tick_charge(delta)

## Stationary lead-in: slerp the aim at the predicted player position, then lock.
func _tick_reorient(delta: float) -> void:
	_state_time += delta
	var to_target: Vector3 = _aim_point() - global_position
	if to_target.length_squared() > 0.0001:
		_aim_dir = _aim_dir.slerp(to_target.normalized(), minf(delta * reorient_speed, 1.0))
	_face_dir(_aim_dir)
	if _state_time >= reorient_duration:
		_begin_charge()

func _tick_charge(delta: float) -> void:
	global_position = global_position.move_toward(_charge_target, charge_speed * delta)
	if global_position.distance_squared_to(_charge_target) < 0.0001:
		_begin_reorient()

func _begin_reorient() -> void:
	_state = State.REORIENT
	_state_time = 0.0
	_height_scale = randf_range(min_height_scale, max_height_scale)

func _begin_charge() -> void:
	_state = State.CHARGE
	_hit_this_charge = false
	_charge_target = _aim_point() + _aim_dir * overshoot_distance

## Full-3D lead point, plus the per-charge random height offset.
func _aim_point() -> Vector3:
	var point: Vector3 = _player.global_position + _player.velocity * look_ahead_time
	point.y += _height_scale * _player_height
	return point

func _measure_player_height() -> float:
	for child in _player.find_children("*", "CollisionShape3D", true, false):
		var capsule := (child as CollisionShape3D).shape as CapsuleShape3D
		if capsule != null:
			return capsule.height
	return fallback_player_height

func _face_dir(dir: Vector3) -> void:
	if dir.length_squared() < 0.0001:
		return
	var up := Vector3.UP
	if absf(dir.normalized().dot(up)) > 0.99:
		up = Vector3.FORWARD # look_at breaks if aim is straight up/down
	look_at(global_position + dir, up)

func _on_hit_box_entered(body: Node3D) -> void:
	if _state != State.CHARGE or _hit_this_charge or body != _player:
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
		EnemyFX.death_burst(get_tree().current_scene, global_position, _tint)
		queue_free()
	elif not destroyed:
		_flash_tween = EnemyFX.flash(self, _wire_mat, _tint, _flash_tween)
