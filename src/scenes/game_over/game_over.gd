extends Control

## Game over screen (colorprune GameOver pattern): shows the final score
## captured by the GameManager autoload, then offers Retry / Main Menu.

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	%RetryButton.pressed.connect(_on_retry_pressed)
	%MenuButton.pressed.connect(_on_menu_pressed)
	%ScoreLabel.text = "SCORE: %d" % GameManager.final_score

func _on_retry_pressed() -> void:
	get_tree().change_scene_to_file("res://src/scenes/level.tscn")

func _on_menu_pressed() -> void:
	var path: String = AppConfig.main_menu_scene_path
	if path.is_empty():
		push_warning("GameOver: AppConfig.main_menu_scene_path is not configured.")
		return
	SceneLoader.load_scene(path)
