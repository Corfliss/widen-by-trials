extends Control
## HP (red, left) and NULLWIDE meter (white, right) arcs circling the reticle.
##
## Reticle base is the existing centred Crosshair in player.tscn; this node only
## draws the two meter arcs around it. Ratios are 0..1 and arrive from hud.gd,
## so this script never looks up parents.

@export var radius: float = 104.0
@export var thickness: float = 6.0
@export var hp_color: Color = Color("EE4444")
@export var nullwide_color: Color = Color.WHITE
@export var lock_circle_radius: float = 160.0
@export_range(0.0, 1.0) var lock_circle_opacity: float = 0.35
@export_range(0.0, 1.0) var opacity: float = 0.5
@export_range(8, 128, 1) var segments: int = 48
@export_range(0.0, 1.0) var low_hp_threshold: float = 0.25
@export var low_hp_pulse_speed: float = 2.0 # full fade cycles per second

## Arc span: 30 degrees from the top (top end) to 150 degrees (bottom anchor).
const ARC_SPAN := 2.0 * PI / 3.0
const ARC_BOTTOM_LEFT := 2.0 * PI / 3.0 # 150 deg counter-clockwise from the top
const ARC_BOTTOM_RIGHT := PI / 3.0 # 150 deg clockwise from the top

var _warning_phase: float = 0.0
var _warning_tween: Tween
var _lock_circle: bool = false:
	set(value):
		_lock_circle = value
		queue_redraw()

@export_range(0.0, 1.0) var health_ratio: float = 1.0:
	set(value):
		health_ratio = clampf(value, 0.0, 1.0)
		queue_redraw()
		_update_warning()

@export_range(0.0, 1.0) var meter_ratio: float = 1.0:
	set(value):
		meter_ratio = clampf(value, 0.0, 1.0)
		queue_redraw()


func _draw() -> void:
	var center: Vector2 = size * 0.5
	# Both arcs are anchored at 150 degrees from the top and grow upward toward
	# 30 degrees, so a shrinking value eats the top end first.
	_arc(center, ARC_BOTTOM_LEFT, 1.0, ARC_SPAN, health_ratio, hp_color,
		1.0 - 0.7 * _warning_phase)
	_arc(center, ARC_BOTTOM_RIGHT, -1.0, ARC_SPAN, meter_ratio, nullwide_color)
	if _lock_circle:
		var tint: Color = nullwide_color
		tint.a *= lock_circle_opacity
		draw_arc(center, lock_circle_radius, 0.0, TAU, 64, tint, thickness)


## Shown while the player holds NULLWIDE: the lock-on detection circle.
func set_lock_circle(holding: bool) -> void:
	_lock_circle = holding


func _arc(center: Vector2, start_angle: float, direction: float, span: float,
		ratio: float, color: Color, alpha_scale: float = 1.0) -> void:
	if ratio <= 0.0:
		return
	var tinted: Color = color
	tinted.a *= opacity * alpha_scale
	draw_arc(center, radius, start_angle, start_angle + direction * span * ratio,
		maxi(2, int(ceil(segments * ratio))), tinted, thickness, true)


func _update_warning() -> void:
	if not is_inside_tree():
		return
	if health_ratio >= low_hp_threshold:
		if _warning_tween == null:
			return
		_warning_tween.kill()
		_warning_tween = null
		_warning_phase = 0.0
		queue_redraw()
		return
	if _warning_tween != null:
		return
	var period: float = 1.0 / maxf(low_hp_pulse_speed, 0.01)
	_warning_tween = create_tween().set_loops()
	_warning_tween.tween_method(_pulse, 0.0, 1.0, period).set_trans(Tween.TRANS_SINE)
	_warning_tween.tween_method(_pulse, 1.0, 0.0, period).set_trans(Tween.TRANS_SINE)


func _pulse(phase: float) -> void:
	_warning_phase = phase
	queue_redraw()
