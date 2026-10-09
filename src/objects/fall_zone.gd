extends Area3D

## FallZone — catches the player falling below the arena. Replaces the old
## player.gd `position.y < -10` scene reload; routes to the same game over
## flow (score capture + Retry/Menu) as a normal death.

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		GameManager.notify_player_died()
