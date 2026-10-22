class_name ArenaLevelLoader
extends SubViewport
## Instances a level scene as backdrop-only 3D content.
##
## The listed children are removed from the instance BEFORE it enters the
## tree, so their _ready side effects never run behind the menu: the Player
## mounts a HUD CanvasLayer and input handling, and the Spawner auto-starts
## wave 1 on _ready (src/objects/spawner.gd).

## Level instanced at runtime as this viewport's content.
@export var level_scene: PackedScene
## Direct children of the level root dropped before the level enters the tree.
## Defaults match src/scenes/level_hex.tscn's gameplay actors.
@export var excluded_children: Array[StringName] = [
	&"Player", &"Spawner", &"FallZone", &"Tutorial",
]


func _ready() -> void:
	if level_scene == null:
		push_warning("ArenaLevelLoader: no level_scene assigned.")
		return
	var level := level_scene.instantiate()
	for child_name in excluded_children:
		var excluded := level.get_node_or_null(NodePath(child_name))
		if excluded == null:
			continue
		level.remove_child(excluded)
		excluded.free()
	add_child(level)
