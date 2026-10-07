extends Node3D

@onready var player = $Player
@onready var enemies = $Enemies

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	# First detect if enemy is hitting
	# If hitting, reduce by 20
	# If not hitting for after 5 seconds, increase by 5 per seconds
	pass
	
