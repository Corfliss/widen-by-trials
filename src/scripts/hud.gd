extends CanvasLayer

var score: int = 0
var _drain_time: float = 0.0

@onready var score_label: Label = $Score

func _ready() -> void:
	add_to_group("hud")
	# Player owns health_updated; this HUD node is Player's direct child.
	var player: Node = get_parent()
	if player.has_signal(&"health_updated"):
		player.connect(&"health_updated", _on_health_updated)

func _process(delta: float) -> void:
	_drain_time += delta
	if _drain_time >= 1.0:
		_drain_time -= 1.0
		score -= 1  # Score may go negative (per design: no clamp)
		score_label.text = str(score)

func add_score(amount: int) -> void:
	score += amount
	score_label.text = str(score)

func _on_health_updated(health: int) -> void:
	$Health.text = str(health) + "%"
