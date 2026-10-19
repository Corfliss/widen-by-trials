class_name SpherePlayer
extends Node3D
## Parameter-space walker for the eversion level (plan D3).
##
## The player is a material point (theta, phi) plus a facing yaw. Each frame its
## world position is pole_basis * f(theta, phi, s) - glued to the surface - and its
## up-axis is the surface normal, so walking and riding stay oriented to the local
## ground through folds and self-intersections. There is no physics body: position
## is analytic, and a CharacterBody3D's gravity/collision would fight it (the plan's
## "custom radial gravity replaced by D3's up-vector"). The camera is first person:
## it rides at eye height in the player frame, so the surface (and the eversion)
## folds directly around the viewer.
##
## Walk integrates in material space with the sphere metric (constant world speed);
## it only runs while the level says walking is allowed (settled s), since mid-
## eversion the material point is frozen so the rider ends on the same patch.

@export_group("Walk")
@export var walk_speed := 1.1            ## world units / second on the surface
@export_group("Look")
@export var look_sensitivity := 0.0024   ## radians / pixel of mouse motion
@export var gamepad_look := 1.8          ## radians / second at full stick
@export var pitch_min := -0.9
@export var pitch_max := 0.9
@export_group("Camera")
@export var eye_height := 0.24           ## camera height above the surface point (top of the marker)
@export_group("Numerics")
@export var diff_h := 1e-4

## Material coordinates. Spawn a comfortable margin off the south pole so the
## walker starts where the coordinate frame is well behaved.
var theta := -PI * 0.5 + 0.55
var phi := 0.0
var yaw := 0.0          ## facing, measured from material-north toward material-east
var pitch := 0.0        ## look elevation, local +X pitch of the camera

var _mouse_captured := false

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_mouse_captured = true
	# First person: the camera sits inside the marker capsule, so the body mesh
	# could never be seen but would risk near-plane slices. Hide it.
	var marker := get_node_or_null("Marker") as MeshInstance3D
	if marker:
		marker.visible = false


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _mouse_captured:
		yaw -= event.relative.x * look_sensitivity
		pitch = clampf(pitch - event.relative.y * look_sensitivity, pitch_min, pitch_max)
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE and _mouse_captured:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			_mouse_captured = false
	elif event is InputEventMouseButton and event.pressed and not _mouse_captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_mouse_captured = true


## Advance the walker one frame. The level calls this after it updates s, so the
## surface (already rebuilt at s) and this rider always agree.
func update_frame(delta: float, s: float, pole_basis: Transform3D, walk_enabled: bool) -> void:
	_handle_gamepad_look(delta)
	if walk_enabled:
		_handle_walk(delta)

	var pm := SphereEversion.params(s)
	var fr: Dictionary = SphereEversion.surface_frame(theta, phi, pm, diff_h)
	var pos: Vector3 = pole_basis * fr["pos"]
	var up: Vector3 = (pole_basis.basis * fr["normal"]).normalized()
	var north: Vector3 = (pole_basis.basis * fr["north"]).normalized()
	var east: Vector3 = (pole_basis.basis * fr["east"]).normalized()
	var fwd: Vector3 = (north * cos(yaw) + east * sin(yaw)).normalized()

	# Stand the body on the surface: -Z faces the walk heading, +Y is the ground normal.
	global_transform = Transform3D(Basis.looking_at(fwd, up), pos)
	_place_camera()


## Movement is integrated in material space using the sphere metric
## (ds^2 = dtheta^2 + cos^2(theta) dphi^2), so world speed stays constant and the
## walker turns with its facing. cos(theta) is clamped and theta held clear of the
## poles so a coordinate singularity can never fling it.
func _handle_walk(delta: float) -> void:
	var inp := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if inp == Vector2.ZERO:
		return
	var fwd_amt := -inp.y        # move_forward reports y = -1
	var strafe_amt := inp.x
	var sin_y := sin(yaw)
	var cos_y := cos(yaw)
	var d_north := fwd_amt * cos_y + strafe_amt * sin_y
	var d_east := fwd_amt * sin_y - strafe_amt * cos_y
	var step := walk_speed * delta / SphereEversion.R_EXPECT
	theta = clampf(theta + d_north * step, -PI * 0.5 + 0.12, PI * 0.5 - 0.12)
	var cos_t := maxf(cos(theta), 0.15)
	phi = wrapf(phi + d_east * step / cos_t, -PI, PI)


func _handle_gamepad_look(delta: float) -> void:
	var rv := Input.get_vector("camera_right", "camera_left", "camera_down", "camera_up")
	if rv == Vector2.ZERO:
		return
	yaw -= rv.x * gamepad_look * delta
	# Pitch is a look angle now (positive = up), so stick-up raises the view —
	# matches player.gd's camera convention; the old orbit sign is inverted.
	pitch = clampf(pitch + rv.y * gamepad_look * delta, pitch_min, pitch_max)


func _place_camera() -> void:
	# First person: the parent frame already carries yaw + surface up, so the
	# camera only offsets to eye height in that frame and pitches around local +X.
	_camera.transform = Transform3D(
		Basis(Vector3.RIGHT, pitch), Vector3(0.0, eye_height, 0.0))
