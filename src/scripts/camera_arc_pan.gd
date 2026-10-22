class_name CameraArcPan
extends Node3D
## Orbits a camera child around this node's origin: endless horizontal yaw
## plus a sine-wave vertical arc, so a static scene reads as a panorama.
##
## Attach to a Node3D pivot; point camera_path at the Camera3D (or Camera360)
## child to drive. Because the rig is the camera's parent, this _process runs
## before Camera360._process copies the transform to its subcameras — no lag.
## Everything tunable is an instance export; there is no static state.

@export_group("Yaw")
## Endless horizontal pan speed in degrees/second; sign picks the direction.
@export_range(-180.0, 180.0, 0.1) var yaw_degrees_per_second: float = 10.0
## Yaw at t = 0, in degrees.
@export var yaw_start_degrees: float = 0.0

@export_group("Vertical Arc")
## Amplitude of the sine bob, in degrees of arc around the pivot. 60 is the
## design cap; the export range enforces the cap (max 89, below flip-over).
@export_range(0.0, 89.0, 0.5) var swing_degrees: float = 60.0
## Duration of one full up-and-down cycle, in seconds.
@export_range(0.1, 120.0, 0.1) var swing_period_seconds: float = 14.0
## Elevation the bob oscillates around; raise it to keep the arc above the floor.
@export var arc_center_degrees: float = 0.0

@export_group("Orbit")
## Distance from the pivot origin to the camera.
@export_range(1.0, 500.0, 0.5) var orbit_radius: float = 26.0
## Height of the arc's center above the pivot origin.
@export var center_height: float = 6.0
## Camera child driven by this rig.
@export var camera_path: NodePath = ^"Camera360"

@onready var _camera: Camera3D = get_node(camera_path)

var _elapsed: float = 0.0


func _process(delta: float) -> void:
	_elapsed += delta
	var yaw := deg_to_rad(yaw_start_degrees + yaw_degrees_per_second * _elapsed)
	var elevation := deg_to_rad(
		arc_center_degrees + swing_degrees * sin(TAU * _elapsed / swing_period_seconds)
	)
	rotation.y = fposmod(yaw, TAU)
	# Arc position with pitch exactly cancelling elevation, so the camera keeps
	# looking at the pivot origin while it sweeps and bobs.
	_camera.position = Vector3(
		0.0,
		center_height + orbit_radius * sin(elevation),
		orbit_radius * cos(elevation)
	)
	_camera.rotation = Vector3(-elevation, 0.0, 0.0)
