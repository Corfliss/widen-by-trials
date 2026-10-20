extends Control
## HP (red, left) and NULLWIDE meter (white, right) arcs circling the reticle.
##
## Reticle base is the existing centred Crosshair in player.tscn; this node only
## draws the two meter arcs around it. Ratios are 0..1 and arrive from hud.gd,
## so this script never looks up parents.

@export var radius: float = 72.0
@export var thickness: float = 6.0
@export var hp_color: Color = Color("EE4444")
@export var nullwide_color: Color = Color.WHITE
@export_range(0.0, 1.0) var opacity: float = 0.5
@export_range(8, 128, 1) var segments: int = 48

@export_range(0.0, 1.0) var health_ratio: float = 1.0:
	set(value):
		health_ratio = clampf(value, 0.0, 1.0)
		queue_redraw()

@export_range(0.0, 1.0) var meter_ratio: float = 1.0:
	set(value):
		meter_ratio = clampf(value, 0.0, 1.0)
		queue_redraw()


func _draw() -> void:
	var center: Vector2 = size * 0.5
	# Both arcs start at 12 o'clock and sweep downward on their own side.
	_arc(center, -PI * 0.5, -1.0, health_ratio, hp_color)
	_arc(center, -PI * 0.5, 1.0, meter_ratio, nullwide_color)


func _arc(center: Vector2, start_angle: float, direction: float, ratio: float, color: Color) -> void:
	if ratio <= 0.0:
		return
	var tinted: Color = color
	tinted.a *= opacity
	draw_arc(center, radius, start_angle, start_angle + direction * PI * ratio,
		maxi(2, int(ceil(segments * ratio))), tinted, thickness, true)
