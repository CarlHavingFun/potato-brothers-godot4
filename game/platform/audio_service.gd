class_name GogoAudioService
extends Node

var music_player: AudioStreamPlayer
var effects_player: AudioStreamPlayer


func _ready() -> void:
	music_player = AudioStreamPlayer.new()
	music_player.name = "Music"
	add_child(music_player)
	effects_player = AudioStreamPlayer.new()
	effects_player.name = "Effects"
	add_child(effects_player)


func apply_settings(settings: GogoSettingsService) -> void:
	if settings == null:
		return
	music_player.volume_db = linear_to_db(clampf(float(settings.values.get("music_volume", 0.8)), 0.0, 1.0))
	effects_player.volume_db = linear_to_db(clampf(float(settings.values.get("effects_volume", 0.9)), 0.0, 1.0))


func play_effect(stream: AudioStream) -> void:
	if stream == null:
		return
	effects_player.stream = stream
	effects_player.play()
