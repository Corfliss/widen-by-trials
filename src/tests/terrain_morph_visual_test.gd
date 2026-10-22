extends Node3D
## Human-eye inspection scene for the wave-driven terrain morph.
## Open this scene and press F6 (Run Current Scene): the hex map morphs to
## a new random pattern every few seconds. Watch the height lerp and
## screenshot before/mid/after as evidence (the pattern name floats above
## the map).

const MORPH_PAUSE_SECONDS: float = 1.5

var _gen: MapHexGenerator
var _label: Label3D


func _ready() -> void:
	_gen = MapHexGenerator.new()
	_gen.name = "HexMap"
	_gen.hex_size = 2.0
	_gen.random_pattern_on_ready = true
	add_child(_gen)

	_label = Label3D.new()
	_label.name = "PatternLabel"
	_label.font_size = 220
	_label.outline_size = 32
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0.0, 11.0, 0.0)
	add_child(_label)
	_gen.terrain_morph_started.connect(
		func(pattern: int) -> void: _label.text = MapHexGenerator.Pattern.keys()[pattern])
	_label.text = MapHexGenerator.Pattern.keys()[_gen.current_pattern]

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	add_child(sun)

	var camera := Camera3D.new()
	camera.name = "InspectCamera"
	camera.position = Vector3(0.0, 18.0, 34.0)
	camera.rotation_degrees = Vector3(-22.0, 0.0, 0.0)
	add_child(camera)

	_cycle()


func _cycle() -> void:
	while true:
		await get_tree().create_timer(_gen.morph_seconds + MORPH_PAUSE_SECONDS).timeout
		_gen.morph_to_random_pattern()
