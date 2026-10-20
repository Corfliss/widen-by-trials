extends Node3D

## Sniper — slow, high-altitude marksman.
##
## FSM: IDLE → REORIENT → AIM → FIRE → IDLE.
##  - IDLE: short cooldown, beam hidden.
##  - REORIENT: only flies when the player is outside the 12 ± 3 m band or the
##    hover altitude is wrong. Keeps its current bearing (no orbiting) and
##    hovers 3.5–5 m above the ground under the player.
##  - AIM: locks where the player will be predict_seconds from now, paints the
##    beam in the enemy color and waits aim_duration.
##  - FIRE: one instant hitscan along the beam; the beam widens/brightens and
##    fades out over glow_duration.

@export_group("Timing")
@export var idle_time_min: float = 0.2
@export var idle_time_max: float = 0.6
@export var aim_duration: float = 2.0
@export var predict_seconds: float = 1.0
@export var glow_duration: float = 0.25
@export var reposition_timeout: float = 4.0

@export_group("Movement")
@export var move_speed: float = 3.0
@export var preferred_distance: float = 12.0
## Reorient only when the horizontal distance leaves preferred_distance ± this.
@export var distance_band: float = 3.0
@export var hover_height_min: float = 3.5
@export var hover_height_max: float = 5.0
@export var arrival_threshold: float = 1.0

@export_group("Combat")
@export var attack_damage: int = 25
@export var laser_width_aim: float = 0.04
@export var laser_width_fire: float = 0.15

var health: int = 3
var destroyed: bool = false
var kill_score: int = 3
## Color code rolled on spawn — guns of any other color deal no damage to this enemy.
var enemy_color_code: int = Weapon.GunColor.WHITE

enum State { IDLE, REORIENT, AIM, FIRE }
var _state: State = State.IDLE
var _state_timer: float = 0.0
var _player: CharacterBody3D
var _reposition_target: Vector3
var _aim_point: Vector3
var _laser_material: StandardMaterial3D
var _glow_tween: Tween

@onready var _raycast: RayCast3D = $RayCast3D
@onready var _laser: MeshInstance3D = $Laser

func _ready() -> void:
	_apply_random_color()
	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if _player == null:
		push_warning("Sniper: no player in group")
		return
	_raycast.enabled = false
	_laser.visible = false
	_enter_idle()

## Rolls this enemy's color and tints its wireframe and laser to match,
## so the player can read which gun will damage it (colorprune-style).
func _apply_random_color() -> void:
	enemy_color_code = GameManager.random_gun_color()
	var tint: Color = GameManager.gun_color_value(enemy_color_code)
	var mesh := $Icosphere as MeshInstance3D
	var base := mesh.get_surface_override_material(0) as ShaderMaterial
	if base != null:
		var mat := base.duplicate() as ShaderMaterial
		mat.set_shader_parameter("wire_color", tint)
		mat.set_shader_parameter("face_color", tint.darkened(0.8))
		mesh.set_surface_override_material(0, mat)
	var laser_base := _laser.get_active_material(0) as StandardMaterial3D
	if laser_base != null:
		_laser_material = laser_base.duplicate() as StandardMaterial3D
		_laser_material.albedo_color = tint
		_laser_material.emission = tint
		_laser.set_surface_override_material(0, _laser_material)

func _process(delta: float) -> void:
	if _player == null or destroyed:
		return
	_state_timer -= delta
	match _state:
		State.IDLE:
			if _state_timer <= 0.0:
				_enter_reorient()
		State.REORIENT:
			global_position = global_position.move_toward(_reposition_target, move_speed * delta)
			var arrived := global_position.distance_to(_reposition_target) <= arrival_threshold
			if arrived or _state_timer <= 0.0:
				_enter_aim()
		State.AIM:
			if _state_timer <= 0.0:
				_enter_fire()
		State.FIRE:
			if _state_timer <= 0.0:
				_laser.visible = false
				_enter_idle()

func _enter_idle() -> void:
	_state = State.IDLE
	_state_timer = randf_range(idle_time_min, idle_time_max)
	_laser.visible = false
	_raycast.enabled = false

func _enter_reorient() -> void:
	_state = State.REORIENT
	_state_timer = reposition_timeout
	_laser.visible = false
	_raycast.enabled = false
	var bearing := global_position - _player.global_position
	bearing.y = 0.0
	var distance := bearing.length()
	if distance < 0.01:
		var angle := randf_range(0.0, TAU)
		bearing = Vector3(cos(angle), 0.0, sin(angle))
	var ground := _ground_under_player()
	var altitude := global_position.y - ground
	var in_band := absf(distance - preferred_distance) <= distance_band
	var at_altitude := altitude >= hover_height_min and altitude <= hover_height_max
	if in_band and at_altitude:
		_enter_aim()
		return
	var target := _player.global_position + bearing.normalized() * preferred_distance
	target.y = ground + randf_range(hover_height_min, hover_height_max)
	_reposition_target = target

## Floor height below the player, skipping the player's own capsule.
func _ground_under_player() -> float:
	var from := _player.global_position + Vector3.UP * 10.0
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 60.0)
	query.exclude = [_player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position.y if not hit.is_empty() else _player.global_position.y

func _enter_aim() -> void:
	_state = State.AIM
	_state_timer = aim_duration
	_aim_point = _player_center() + _player.velocity * predict_seconds
	_look_at_point(_aim_point)
	_raycast.target_position = _raycast.to_local(_aim_point)
	_raycast.enabled = true
	_show_laser(laser_width_aim, 2.0)

func _enter_fire() -> void:
	_state = State.FIRE
	_state_timer = glow_duration
	_raycast.force_raycast_update()
	if _raycast.is_colliding() and _raycast.get_collider() == _player and _player.has_method("damage"):
		_player.damage(attack_damage)
	_raycast.enabled = false
	_show_laser(laser_width_fire, 6.0)
	if _laser_material == null:
		return
	if _glow_tween != null:
		_glow_tween.kill()
	_glow_tween = create_tween()
	_glow_tween.tween_property(_laser_material, "albedo_color:a", 0.0, glow_duration)
	_glow_tween.parallel().tween_property(_laser_material, "emission_energy_multiplier", 0.0, glow_duration)

## Center of the player's capsule. Aiming at the feet puts the target below the
## floor surface, so the beam is clipped by the ground before it reaches them.
func _player_center() -> Vector3:
	var collider := _player.get_node_or_null("Collider") as CollisionShape3D
	return collider.global_position if collider != null else _player.global_position

## Points the whole body (and therefore the beam) at the locked aim point.
func _look_at_point(target: Vector3) -> void:
	var dir := (target - global_position).normalized()
	if dir.length_squared() < 0.01:
		return
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	look_at(target, up)

## Laser spans sniper → aim point, with the cylinder's +Y bent onto -Z.
func _show_laser(width: float, energy: float) -> void:
	var length := global_position.distance_to(_aim_point)
	_laser.visible = true
	_laser.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
	_laser.position = Vector3(0.0, 0.0, -length * 0.5)
	_laser.scale = Vector3(width, length, width)
	if _laser_material != null:
		_laser_material.albedo_color.a = 1.0
		_laser_material.emission_energy_multiplier = energy

func damage(amount: int) -> void:
	health -= amount
	if health <= 0 and not destroyed:
		destroyed = true
		var hud := get_tree().get_first_node_in_group("hud")
		if hud != null and hud.has_method("add_score"):
			hud.add_score(kill_score)
		queue_free()
