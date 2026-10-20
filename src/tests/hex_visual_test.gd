extends Node3D
## Human-eye inspection scene for MapHexGenerator.
## Open this scene and press F6 (Run Current Scene) to see all 10 HyperSync
## patterns side by side in a 5x2 grid.

const PATTERNS: Array = [
	["FLAT_ARENA", 1], ["CONCENTRIC_RINGS", 2], ["SPIRAL_ASCENT", 3],
	["DIAMOND_PYRAMID", 4], ["WAVE_INTERF", 5], ["HEX_FRACTALS", 6],
	["GOLDEN_SPIRAL", 7], ["MATH_VALLEYS", 8], ["TESSELLATION", 9], ["CHAOS", 10],
]

const SPACING: float = 26.0
const LIFT_Y: float = 11.0


func _ready() -> void:
	for i: int in PATTERNS.size():
		var gen: MapHexGenerator = MapHexGenerator.new()
		gen.name = "Map_" + PATTERNS[i][0]
		gen.position = Vector3(
			(float(i % 5) - 2.0) * SPACING,
			0.0,
			float(i / 5) * SPACING
		)
		add_child(gen)
		gen.generate_map(PATTERNS[i][1])

		var label := Label3D.new()
		label.name = "Label_" + PATTERNS[i][0]
		label.text = PATTERNS[i][0]
		label.font_size = 320
		label.outline_size = 48
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = gen.position + Vector3(0.0, LIFT_Y, 0.0)
		add_child(label)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	add_child(sun)

	var camera := Camera3D.new()
	camera.name = "InspectCamera"
	camera.position = Vector3(0.0, 34.0, 68.0)
	camera.rotation_degrees = Vector3(-28.0, 0.0, 0.0)
	add_child(camera)
