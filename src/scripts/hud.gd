extends CanvasLayer

const HIT_MARKER_DURATION := 0.2

var score: int = 0
var _drain_time: float = 0.0

@onready var score_label: Label = $Score
@onready var hit_marker: TextureRect = $HitMarker

var _hit_tween: Tween

func _ready() -> void:
	add_to_group("hud")
	# Player owns health_updated; this HUD node is Player's direct child.
	var player: Node = get_parent()
	if player.has_signal(&"health_updated"):
		player.connect(&"health_updated", _on_health_updated)
	if player.has_signal(&"enemy_hit"):
		player.connect(&"enemy_hit", show_hit_marker)

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

## Flash the centered hit marker. Retrigger-safe for multi-pellet/rapid fire.
func show_hit_marker() -> void:
	if not is_node_ready():
		return
	if _hit_tween:
		_hit_tween.kill()
	hit_marker.modulate.a = 1.0
	hit_marker.scale = Vector2.ONE * 1.5
	_hit_tween = create_tween()
	_hit_tween.tween_property(hit_marker, "scale", Vector2.ONE, 0.08).set_ease(Tween.EASE_OUT)
	_hit_tween.parallel().tween_property(hit_marker, "modulate:a", 0.0, HIT_MARKER_DURATION).set_ease(Tween.EASE_OUT)
