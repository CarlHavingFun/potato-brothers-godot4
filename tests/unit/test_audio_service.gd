extends GdUnitTestSuite


func test_ready_builds_twelve_sfx_voices_and_keeps_music_on_music_bus() -> void:
	var service := await _ready_service()
	assert_bool(_has_property(service, &"sfx_players")).is_true()
	if not _has_property(service, &"sfx_players"):
		return
	var voices: Array = service.get(&"sfx_players")
	assert_int(voices.size()).is_equal(12)
	assert_str(service.music_player.bus).is_equal("Music")
	assert_object(service.effects_player).is_same(voices[0])
	for index in voices.size():
		var voice := voices[index] as AudioStreamPlayer
		assert_str(voice.bus).is_equal("SFX")
		assert_str(voice.name).is_equal("SFXVoice%02d" % (index + 1))


func test_play_effect_one_argument_remains_supported_and_fast_calls_use_distinct_voices() -> void:
	var service := await _ready_service()
	if not _has_property(service, &"sfx_players"):
		assert_bool(false).is_true()
		return
	var first_stream := _looping_stream(900)
	var second_stream := _looping_stream(1200)
	var first := service.call(&"play_effect", first_stream) as AudioStreamPlayer
	var second := service.call(&"play_effect", second_stream) as AudioStreamPlayer

	assert_object(first).is_not_null()
	assert_object(second).is_not_null()
	assert_object(first).is_not_same(second)
	assert_object(first.stream).is_same(first_stream)
	assert_object(second.stream).is_same(second_stream)
	assert_bool(first.playing).is_true()
	assert_bool(second.playing).is_true()


func test_optional_volume_and_pitch_combine_with_effect_settings_on_every_voice() -> void:
	var service := await _ready_service()
	if not _has_property(service, &"sfx_players"):
		assert_bool(false).is_true()
		return
	var settings := GogoSettingsService.new()
	settings.values["music_volume"] = 0.25
	settings.values["effects_volume"] = 0.5
	service.apply_settings(settings)
	var player := service.call(&"play_effect", _looping_stream(1500), -6.0, 1.25) as AudioStreamPlayer

	assert_float(service.music_player.volume_db).is_equal_approx(linear_to_db(0.25), 0.001)
	assert_float(player.volume_db).is_equal_approx(linear_to_db(0.5) - 6.0, 0.001)
	assert_float(player.pitch_scale).is_equal_approx(1.25, 0.001)
	for voice_variant in service.get(&"sfx_players"):
		var voice := voice_variant as AudioStreamPlayer
		if voice != player:
			assert_float(voice.volume_db).is_equal_approx(linear_to_db(0.5), 0.001)


func test_idle_voice_wins_before_oldest_active_voice() -> void:
	var service := await _ready_service()
	if not _has_property(service, &"sfx_players"):
		assert_bool(false).is_true()
		return
	var voices: Array = service.get(&"sfx_players")
	for index in voices.size():
		assert_object(service.call(&"play_effect", _looping_stream(500 + index))).is_same(voices[index])
	(voices[4] as AudioStreamPlayer).stop()

	var reused := service.call(&"play_effect", _looping_stream(2200)) as AudioStreamPlayer
	assert_object(reused).is_same(voices[4])


func test_saturation_steals_oldest_voice_in_stable_index_order() -> void:
	var service := await _ready_service()
	if not _has_property(service, &"sfx_players"):
		assert_bool(false).is_true()
		return
	var voices: Array = service.get(&"sfx_players")
	for index in voices.size():
		assert_object(service.call(&"play_effect", _looping_stream(700 + index))).is_same(voices[index])

	assert_object(service.call(&"play_effect", _looping_stream(1800))).is_same(voices[0])
	assert_object(service.call(&"play_effect", _looping_stream(1900))).is_same(voices[1])


func test_null_effect_is_a_backward_compatible_no_op() -> void:
	var service := await _ready_service()
	assert_object(service.call(&"play_effect", null)).is_null()


func _ready_service() -> GogoAudioService:
	var service := auto_free(GogoAudioService.new()) as GogoAudioService
	add_child(service)
	await get_tree().process_frame
	return service


func _looping_stream(frequency_hint: int) -> AudioStreamWAV:
	var sample_count := 4410
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	for index in sample_count:
		var sample := int(round(sin(TAU * float(frequency_hint) * float(index) / 44100.0) * 8000.0))
		bytes.encode_s16(index * 2, sample)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 44100
	stream.stereo = false
	stream.data = bytes
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = sample_count
	return stream


func _has_property(object: Object, property_name: StringName) -> bool:
	for property in object.get_property_list():
		if StringName(property.get("name", "")) == property_name:
			return true
	return false
