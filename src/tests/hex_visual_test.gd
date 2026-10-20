extends Node3D
## Human-eye inspection scene for MapHexGenerator.
## Open this scene and press F6 (Run Current Scene) to see all patterns side by side.

const PATTERNS: Array = [
	["RESET_FLAT", MapHexGenerator.Pattern.RESET_FLAT],
	["SPIKES", MapHexGenerator.Pattern.SPIKES],
	["CLIFF_RINGS", MapHexGenerator.Pattern.CLIFF_RINGS],
	["NOISE_COLUMNS", MapHexGenerator.Pattern.NOISE_COLUMNS],
]

const SPACING: float = 26.0
const TOP_Y: float = 9.5


func _ready() -> void:
	_build()


## Also callable directly (e.g. from detached inspection contexts).
func _build() -> void:
	var first_x: float = -float(PATTERNS.size() - 1) * SPACING / 2.0
	for i: int in PATTERNS.size():
		var gen: MapHexGenerator = MapHexGenerator.new()
		gen.name = "Map_" + PATTERNS[i][0]
		gen.position = Vector3(first_x + SPACING * i, 0.0, 0.0)
		add_child(gen)
		gen.generate_map(PATTERNS[i][1])

		var label := Label3D.new()
		label.name = "Label_" + PATTERNS[i][0]
		label.text = PATTERNS[i][0]
		label.font_size = 320
		label.outline_size = 48
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = gen.position + Vector3(0.0, TOP_Y, 0.0)
		add_child(label)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	add_child(sun)

	var camera := Camera3D.new()
	camera.name = "InspectCamera"
	camera.position = Vector3(0.0, 20.0, 58.0)
	camera.rotation_degrees = Vector3(-18.0, 0.0, 0.0)
	add_child(camera)
