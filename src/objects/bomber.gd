extends Node3D

## Bomber — flying mortar that kites the player.
##
## FSM: REPOSITION → AIM → (recover) → REPOSITION.
##  - REPOSITION: pick a fresh bearing on the 3–5 m ring around the player and
##    glide to it at a random hover altitude in the 1.5–3 m band. It always
##    faces the player, in every state.
##  - AIM: the landing point is locked at the *start* of AIM and marked on the
##    floor for telegraph_duration. The shot is aimed where the player will be
##    predict_seconds after it is fired, i.e. telegraph_duration + predict_seconds
##    ahead of the moment the marker appears. A 45°-up Ball is launched from the
##    barrel tip with the speed that makes the arc land exactly on the marker,
##    then the bomber idles for recover_duration before repositioning.
##
## The projectile has no script of its own: the bomber drives it with a tween
## that samples the exact parabola, so the ball dies cleanly with itself and
## still lands (and damages) if the bomber is killed mid-flight.

const WIRE_SHADER := preload("res://src/shaders/wireframe_SuperDoomKing.gdshader")
const BALL_SCENE := preload("res://src/assets/3d_models/Ball.glb")
## cos(45°) == sin(45°), the horizontal and vertical share of the launch speed.
const LAUNCH_SPLIT := 0.70710678

@export_group("Movement")
@export var move_speed: float = 5.0
@export var min_distance: float = 3.0
@export var max_distance: float = 5.0
## Hover band, measured from the player's feet.
@export var min_altitude: float = 1.5
@export var max_altitude: float = 3.0
@export var arrival_threshold: float = 0.3
## Safety valve so a fleeing player cannot stall the bomber in REPOSITION.
@export var reposition_timeout: float = 3.0

@export_group("Aim")
## How long the landing marker is visible before the shot.
@export var telegraph_duration: float = 1.5
## Player prediction lead measured from the shot.
@export var predict_seconds: float = 0.5
## Idle time after the shot before repositioning.
@export var recover_duration: float = 0.5

@export_group("Projectile")
@export var aoe_radius: float = 1.5
@export var aoe_damage: int = 20
@export var ball_scale: float = 0.25
## Arc gravity. The ball is tween-driven, not a RigidBody, so this is the real value.
@export var gravity: float = 9.8

var health: int = 3
var destroyed: bool = false
var kill_score: int = 3
## Color code rolled on spawn — guns of any other color deal no damage to this enemy.
var enemy_color_code: int = Weapon.GunColor.WHITE

enum State { REPOSITION, AIM }

var _state: State = State.REPOSITION
var _timer: float = 0.0
var _target: Vector3
## Floor point where the telegraphed shot will land.
var _landing: Vector3
var _fired: bool = false
var _player: CharacterBody3D
var _tint: Color = Color.WHITE
var _marker_mat: StandardMaterial3D
var _wire_mat: ShaderMaterial
var _flash_tween: Tween

@onready var _marker: MeshInstance3D = $Marker

func _ready() -> void:
	add_to_group("enemy")
	_apply_random_color()
	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if _player == null:
		push_warning("Bomber: no player in group")
		return
	_enter_reposition()

## Rolls this enemy's color, tints its wireframe material to match (so the
## player can read which gun damages it), and colors the landing marker.
func _apply_random_color() -> void:
	enemy_color_code = GameManager.random_gun_color()
	_tint = GameManager.gun_color_value(enemy_color_code)

	var mat := ShaderMaterial.new()
	mat.shader = WIRE_SHADER
	mat.set_shader_parameter("wire_color", _tint)
	mat.set_shader_parameter("face_color", _tint.darkened(0.8))
	mat.set_shader_parameter("wire_width", 1.0)
	for node in $Model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for surface in mesh.mesh.get_surface_count():
			mesh.set_surface_override_material(surface, mat)
	_wire_mat = mat

	# Disc radius must equal the real blast radius: duplicate the mesh and the
	# material so bombers rolling different colors do not share one resource.
	var disc := _marker.mesh.duplicate() as CylinderMesh
	disc.top_radius = aoe_radius
	disc.bottom_radius = aoe_radius
	_marker.mesh = disc
	_marker_mat = _marker.get_surface_override_material(0).duplicate() as StandardMaterial3D
	_marker_mat.albedo_color = Color(_tint, _marker_mat.albedo_color.a)
	_marker.set_surface_override_material(0, _marker_mat)

func _physics_process(delta: float) -> void:
	if _player == null or destroyed:
		return
	_face_player()
	if _state == State.REPOSITION:
		_tick_reposition(delta)
	else:
		_tick_aim(delta)

func _tick_reposition(delta: float) -> void:
	global_position = global_position.move_toward(_target, move_speed * delta)
	_timer -= delta
	if global_position.distance_to(_target) <= arrival_threshold or _timer <= 0.0:
		_enter_aim()

func _enter_reposition() -> void:
	_state = State.REPOSITION
	_fired = false
	_marker.visible = false
	_timer = reposition_timeout
	var angle := randf_range(0.0, TAU)
	var distance := randf_range(min_distance, max_distance)
	_target = _player.global_position + Vector3(cos(angle), 0.0, sin(angle)) * distance
	_target.y = _player.global_position.y + randf_range(min_altitude, max_altitude)

func _enter_aim() -> void:
	_state = State.AIM
	_fired = false
	_timer = telegraph_duration

	var velocity := _player.velocity
	velocity.y = 0.0
	var predicted := _player.global_position + velocity * (telegraph_duration + predict_seconds)
	_landing = _floor_under(predicted)

	_marker.global_position = _landing + Vector3.UP * 0.03
	_marker.scale = Vector3(0.6, 1.0, 0.6)
	_marker.visible = true
	create_tween().tween_property(_marker, "scale", Vector3.ONE, telegraph_duration)

func _tick_aim(delta: float) -> void:
	_timer -= delta
	if _fired:
		if _timer <= 0.0:
			_enter_reposition()
	elif _timer <= 0.0:
		_fire()
		_fired = true
		_timer = recover_duration

func _fire() -> void:
	_marker.visible = false
	var muzzle := ($Model/Muzzle as Node3D).global_position
	var lob := _lob(muzzle, _landing)
	if lob.is_empty():
		return
	var velocity: Vector3 = lob.velocity
	var flight: float = lob.flight
	_spawn_ball(muzzle, velocity, flight)

## 45°-up launch from `from` that lands on `landing`.
## Solves v² = g·d² / (d − Δh) (the 2·cos²45 term is 1), then the flight time.
## Returns {} when the shot is degenerate.
func _lob(from: Vector3, landing: Vector3) -> Dictionary:
	var to_target := landing - from
	var distance := Vector2(to_target.x, to_target.z).length()
	if distance < 0.05:
		return {}
	var speed_sq := gravity * distance * distance / (distance - to_target.y)
	if speed_sq <= 0.0:
		return {}
	var speed := sqrt(speed_sq)
	var direction := Vector3(to_target.x, 0.0, to_target.z) / distance
	return {
		"velocity": (direction + Vector3.UP) * (speed * LAUNCH_SPLIT),
		"flight": distance / (speed * LAUNCH_SPLIT),
	}

func _spawn_ball(from: Vector3, velocity: Vector3, flight: float) -> void:
	var ball := BALL_SCENE.instantiate() as Node3D
	ball.scale = Vector3.ONE * ball_scale
	var mesh := ball.get_child(0) as MeshInstance3D
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = _tint
	mesh.material_override = mat

	get_parent().add_child(ball)
	ball.global_position = from

	# Locals copied on purpose: the lambda must outlive this bomber, since the
	# ball keeps flying (and still hits) after the bomber dies.
	var origin := from
	var start_velocity := velocity
	var ball_gravity := gravity
	var duration := flight
	var landing := _landing
	var radius := aoe_radius
	var damage_amount := aoe_damage
	var target := _player
	var tween := ball.create_tween()
	tween.tween_method(func(u: float) -> void:
		var t := u * duration
		ball.global_position = origin + start_velocity * t + Vector3.DOWN * (0.5 * ball_gravity * t * t),
		0.0, 1.0, duration)
	tween.tween_callback(func() -> void:
		if is_instance_valid(target) and target.has_method("damage") \
				and target.global_position.distance_to(landing) <= radius:
			target.damage(damage_amount)
		ball.queue_free())

## Floor point under `point`, or the player's feet level when the ray misses
## (e.g. the predicted spot is outside the arena).
func _floor_under(point: Vector3) -> Vector3:
	var feet_y := _player.global_position.y
	var from := Vector3(point.x, feet_y + 30.0, point.z)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 60.0)
	query.exclude.append(_player.get_rid())
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return Vector3(point.x, feet_y, point.z)
	var floor_point: Vector3 = hit.position
	return floor_point

func _face_player() -> void:
	var dir := _player.global_position - global_position
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	look_at(global_position + dir, Vector3.UP)

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
