extends GdUnitTestSuite
## Audio voice-pool contract: play() picks one path from the comma pool,
## carries the requested pitch window through the queue, and the player that
## dequeues it ends up with a pitch inside that window.

const AUDIO_SCRIPT := preload("res://src/scripts/audio.gd")
const POOL_PATHS: Array[String] = [
	"res://src/sounds/jump_a.ogg",
	"res://src/sounds/jump_b.ogg",
]


func test_play_picks_one_path_from_comma_pool() -> void:
	var audio: Node = auto_free(AUDIO_SCRIPT.new())
	add_child(audio)  # _ready builds the player pool
	for i in 20:
		audio.play("src/sounds/jump_a.ogg, src/sounds/jump_b.ogg")
		var entry: Dictionary = audio.queue[i]
		assert_bool(POOL_PATHS.has(entry.path)).is_true() \
			.override_failure_message("pool must pick one of the given paths")


func test_play_stores_pitch_window_and_strips_whitespace() -> void:
	var audio: Node = auto_free(AUDIO_SCRIPT.new())
	add_child(audio)
	audio.play(" src/sounds/jump_a.ogg , src/sounds/jump_b.ogg ", 1.5, 0.2)
	var entry: Dictionary = audio.queue[0]
	assert_bool(entry.path.begins_with("res://")).is_true() \
		.override_failure_message("paths are stored res-prefixed")
	assert_bool(entry.path.contains(" ") == false).is_true() \
		.override_failure_message("pool entries must be edge-trimmed")
	assert_that(entry.pitch).is_equal(1.5)
	assert_that(entry.spread).is_equal(0.2)


func test_play_defaults_reproduce_original_jitter_window() -> void:
	var audio: Node = auto_free(AUDIO_SCRIPT.new())
	add_child(audio)
	audio.play("src/sounds/jump_a.ogg")
	var entry: Dictionary = audio.queue[0]
	# Defaults: pitch 1.0, spread 0.1 -> randf_range(0.9, 1.1), the legacy window.
	assert_that(entry.pitch).is_equal(1.0)
	assert_that(entry.spread).is_equal(0.1)


func test_dequeued_player_gets_pitch_inside_window() -> void:
	var audio: Node = auto_free(AUDIO_SCRIPT.new())
	add_child(audio)
	audio.play("src/sounds/jump_a.ogg", 1.5, 0.2)
	await get_tree().process_frame  # _process dequeues and plays
	# The dequeued player leaves `available` (popped once started), so find
	# the voice that is actually playing among the pool children.
	var player: AudioStreamPlayer = null
	for child in audio.get_children():
		if child is AudioStreamPlayer and child.playing:
			player = child
			break
	assert_object(player).is_not_null() \
		.override_failure_message("queued sound must reach a playing pool player")
	assert_bool(player.stream != null).is_true() \
		.override_failure_message("pool player must have its stream loaded")
	assert_bool(player.pitch_scale >= 1.3 and player.pitch_scale <= 1.7).is_true() \
		.override_failure_message("pitch %f must sit in [1.3, 1.7]" % player.pitch_scale)


func test_pool_recycles_finished_players() -> void:
	var audio: Node = auto_free(AUDIO_SCRIPT.new())
	add_child(audio)
	var before: int = audio.available.size()
	audio.play("src/sounds/jump_a.ogg")
	await get_tree().process_frame
	assert_that(audio.available.size()).is_equal(before - 1) \
		.override_failure_message("playing voice leaves the available pool")
