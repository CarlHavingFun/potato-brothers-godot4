class_name GogoAudioService
extends Node

const SFX_VOICE_COUNT := 12

var music_player: AudioStreamPlayer
var effects_player: AudioStreamPlayer
var sfx_players: Array[AudioStreamPlayer] = []

var _effects_volume_db := 0.0
var _activation_serial := 0
var _voice_activation_serials: Array[int] = []


func _ready() -> void:
	music_player = AudioStreamPlayer.new()
	music_player.name = "Music"
	music_player.bus = &"Music"
	add_child(music_player)
	for index in SFX_VOICE_COUNT:
		var voice := AudioStreamPlayer.new()
		voice.name = "SFXVoice%02d" % (index + 1)
		voice.bus = &"SFX"
		add_child(voice)
		sfx_players.append(voice)
		_voice_activation_serials.append(0)
	effects_player = sfx_players[0]


func apply_settings(settings: GogoSettingsService) -> void:
	if settings == null:
		return
	AudioServer.set_bus_volume_db(0, linear_to_db(clampf(float(settings.values.get("master_volume", 1.0)), 0.0, 1.0)))
	music_player.volume_db = linear_to_db(clampf(float(settings.values.get("music_volume", 0.8)), 0.0, 1.0))
	_effects_volume_db = linear_to_db(clampf(float(settings.values.get("effects_volume", 0.9)), 0.0, 1.0))
	for voice in sfx_players:
		voice.volume_db = _effects_volume_db


func play_effect(
	stream: AudioStream,
	volume_db: float = 0.0,
	pitch_scale: float = 1.0
) -> AudioStreamPlayer:
	if stream == null:
		return null
	var voice_index := _select_sfx_voice()
	var voice := sfx_players[voice_index]
	if voice.playing:
		voice.stop()
	voice.stream = stream
	voice.volume_db = _effects_volume_db + volume_db
	voice.pitch_scale = maxf(pitch_scale, 0.01)
	voice.play()
	_activation_serial += 1
	_voice_activation_serials[voice_index] = _activation_serial
	return voice


func _select_sfx_voice() -> int:
	for index in sfx_players.size():
		if not sfx_players[index].playing:
			return index
	var oldest_index := 0
	var oldest_serial := _voice_activation_serials[0]
	for index in range(1, _voice_activation_serials.size()):
		if _voice_activation_serials[index] < oldest_serial:
			oldest_index = index
			oldest_serial = _voice_activation_serials[index]
	return oldest_index
