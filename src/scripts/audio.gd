extends Node

## Voice-pooled SFX player. Autoloaded as "Audio".
## Code adapted from KidsCanCode.
##
## play() accepts a comma-separated pool of res-relative paths (one is picked
## at random per call) plus a center pitch and a random spread: the final
## pitch_scale is randf_range(pitch - spread, pitch + spread). The defaults
## (1.0 ± 0.1) reproduce the original hardcoded 0.9–1.1 jitter.

## Pool size, default jitter and bus/volume are instance vars on purpose:
## they are tunable in one place and are not statics.
var num_players = 12
var bus = "master"
var player_volume_db = -10.0
var default_pitch = 1.0
var default_spread = 0.1

var available = []  # The available players.
var queue = []  # The queue of {path, pitch, spread} entries to play.

func _ready():
	for i in num_players:
		var p = AudioStreamPlayer.new()
		add_child(p)

		available.append(p)

		p.volume_db = player_volume_db
		p.finished.connect(_on_stream_finished.bind(p))
		p.bus = bus

func _on_stream_finished(stream):
	available.append(stream)

## Queues one sound from `sound_path` (or multiple, separated by commas).
## `pitch` is the center of the pitch window, `spread` its half-width.
func play(sound_path, pitch = default_pitch, spread = default_spread):
	var sounds = sound_path.split(",")
	queue.append({
		"path": "res://" + sounds[randi() % sounds.size()].strip_edges(),
		"pitch": pitch,
		"spread": spread,
	})

func _process(_delta):
	if not queue.is_empty() and not available.is_empty():
		var entry = queue.pop_front()
		available[0].stream = load(entry.path)
		available[0].play()
		available[0].pitch_scale = randf_range(
			entry.pitch - entry.spread, entry.pitch + entry.spread)

		available.pop_front()
