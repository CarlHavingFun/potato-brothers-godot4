extends Node

enum Sound {
	ENEMY_HIT,
	FIRE,
	UI
}

var sound_dictionary: Dictionary[Sound, Resource] = {
	Sound.ENEMY_HIT: preload("uid://blonjlaa37md0"),
	Sound.FIRE: preload("uid://g72hyxdnaath"),
	Sound.UI: preload("uid://6nolwqlami52"),
}

@export var stream_players: Array[AudioStreamPlayer]


func _ready() -> void:
	for stream_player in stream_players:
		stream_player.finished.connect(_on_stream_finished.bind(stream_player))


func play_sound(type: int) -> void:
	# Headless GdUnit/CI processes cannot output audio and can terminate on the
	# same frame. Starting MP3 playback there leaves AudioStreamPlaybackMP3
	# objects alive during engine teardown.
	if DisplayServer.get_name() == "headless":
		return
	var stream := get_free_stream_player()
	if not stream:
		return
	
	var audio := sound_dictionary[type]
	stream.stream = audio
	stream.pitch_scale = randf_range(0.8, 1.3)
	stream.play()


func _on_stream_finished(stream_player: AudioStreamPlayer) -> void:
	stream_player.stream = null


func _exit_tree() -> void:
	for stream_player in stream_players:
		stream_player.stop()
		stream_player.stream = null


func get_free_stream_player() -> AudioStreamPlayer:
	for stream: AudioStreamPlayer in stream_players:
		if not stream.playing:
			return stream
	
	return null
