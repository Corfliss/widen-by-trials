extends Control
## Human-eye inspection of the reticle meter: four states side by side.
## Open this scene and press F6, or capture it through Fennara.

const METER := preload("res://src/scripts/reticle_meter.gd")
const CROSSHAIR := "res://src/sprites/crosshair_self-made.png"

const STATES: Array = [
	[1.0, 1.0, "100 / 100"],
	[0.5, 0.6, "50 / 60"],
	[0.1, 0.2, "10 / 20"],
	[0.0, 0.0, "0 / 0"],
]


func _ready() -> void:
	_build()


## Also callable directly (e.g. from a detached capture context).
func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.04, 0.04)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	center.add_child(row)

	var reticle_texture: Texture2D = load(CROSSHAIR)
	for state in STATES:
		var cell := VBoxContainer.new()
		row.add_child(cell)

		var box := Control.new()
		box.custom_minimum_size = Vector2(280, 280)
		cell.add_child(box)

		var reticle := TextureRect.new()
		reticle.texture = reticle_texture
		reticle.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		reticle.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		reticle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		box.add_child(reticle)

		var meter: Control = METER.new()
		meter.radius = 100.0
		meter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		meter.health_ratio = state[0]
		meter.meter_ratio = state[1]
		box.add_child(meter)

		var label := Label.new()
		label.text = state[2]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		cell.add_child(label)
