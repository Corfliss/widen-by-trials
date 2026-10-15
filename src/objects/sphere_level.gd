class_name SphereLevel
extends Node3D
## Drives one sphere eversion. Owns the master progress s, eases it toward a
## target toggled with X, rebuilds the eversion surface at s (only while s moves),
## and advances the player rider. The eversion frame (pole_basis) is fixed: it is
## set once so the spawn point's ground normal points up, and it places both the
## surface node and the player in the same world space.

const EVERSION_SPEED := 0.5   ## units of s per second
const S_EPS := 0.0005         ## |target - s| below this == settled (walking allowed)

@onready var _surface: EversionSurface = $EversionSurface
@onready var _player: SpherePlayer = $SpherePlayer
@onready var _light: DirectionalLight3D = $DirectionalLight3D

var s := 0.0
var target := 0.0
var pole_basis := Transform3D.IDENTITY
var _last_s := -1.0


func _ready() -> void:
	# Place the eversion so the spawn point's ground normal points up (+Y): the
	# sphere sits centred at the origin with the walker standing on top of it.
	var fr0: Dictionary = SphereEversion.surface_frame(
		_player.theta, _player.phi, SphereEversion.params(0.0), _player.diff_h)
	pole_basis = Transform3D(_align_up(fr0["normal"]), Vector3.ZERO)
	_surface.transform = pole_basis
	_surface.apply(0.0)
	_last_s = 0.0
	# Angle the sun onto the top hemisphere so the surface reads clearly.
	_light.rotation_degrees = Vector3(-58.0, 24.0, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_X:
		target = 0.0 if target > 0.5 else 1.0


func _process(delta: float) -> void:
	if absf(target - s) > S_EPS:
		s = move_toward(s, target, EVERSION_SPEED * delta)
	# Rebuild the mesh only while s is actually moving; a held s = held surface.
	if absf(s - _last_s) > 1e-6:
		_surface.apply(s)
		_last_s = s
	_player.update_frame(delta, s, pole_basis, absf(target - s) <= S_EPS)


## Shortest rotation taking vector n onto +Y (orients the spawn frame only).
func _align_up(n: Vector3) -> Basis:
	var d := n.dot(Vector3.UP)
	if d > 0.9999:
		return Basis.IDENTITY
	if d < -0.9999:
		return Basis(Vector3.RIGHT, PI)
	return Basis(n.cross(Vector3.UP).normalized(), acos(clampf(d, -1.0, 1.0)))
