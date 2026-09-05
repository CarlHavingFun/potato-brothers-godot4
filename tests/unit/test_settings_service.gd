extends GdUnitTestSuite


var _had_settings := false
var _original_bytes := PackedByteArray()


func before_test() -> void:
	_had_settings = FileAccess.file_exists(GogoSettingsService.SETTINGS_PATH)
	if _had_settings:
		_original_bytes = FileAccess.get_file_as_bytes(GogoSettingsService.SETTINGS_PATH)
	assert_int(DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(GogoSettingsService.SETTINGS_PATH.get_base_dir())
	)).is_equal(OK)


func after_test() -> void:
	if _had_settings:
		var file := FileAccess.open(GogoSettingsService.SETTINGS_PATH, FileAccess.WRITE)
		file.store_buffer(_original_bytes)
		file.close()
	elif FileAccess.file_exists(GogoSettingsService.SETTINGS_PATH):
		DirAccess.remove_absolute(GogoSettingsService.SETTINGS_PATH)


func test_invalid_known_field_rejects_entire_load_without_partial_publication() -> void:
	for invalid: Dictionary in [
		{"effects_volume": []},
		{"music_volume": {}},
		{"master_volume": "loud"},
		{"master_volume": true},
		{"fullscreen": "false"},
		{"fullscreen": 1},
		{"language": null},
	]:
		var settings := GogoSettingsService.new()
		var before := settings.values.duplicate(true)
		var payload := {"music_volume": 0.25}
		payload.merge(invalid, true)
		_write_settings(payload)
		assert_int(settings.load_settings()).is_equal(ERR_FILE_CORRUPT)
		assert_dict(settings.values).is_equal(before)


func test_sparse_valid_settings_keep_defaults_and_ignore_unknown_fields() -> void:
	_write_settings({"effects_volume": 0, "fullscreen": true, "future_setting": []})
	var settings := GogoSettingsService.new()
	assert_int(settings.load_settings()).is_equal(OK)
	assert_float(float(settings.values.effects_volume)).is_zero()
	assert_float(float(settings.values.music_volume)).is_equal(0.8)
	assert_str(settings.values.language).is_equal("cn")
	assert_int(settings.resolved_window_mode()).is_equal(DisplayServer.WINDOW_MODE_FULLSCREEN)
	assert_bool(settings.values.has("future_setting")).is_false()


func test_saved_settings_round_trip_through_audio_and_display_consumers() -> void:
	var settings := GogoSettingsService.new()
	settings.values.effects_volume = 0.5
	settings.values.music_volume = 0.25
	settings.values.fullscreen = false
	assert_int(settings.save_settings()).is_equal(OK)
	var restored := GogoSettingsService.new()
	assert_int(restored.load_settings()).is_equal(OK)
	var audio := auto_free(GogoAudioService.new()) as GogoAudioService
	add_child(audio)
	audio.apply_settings(restored)
	assert_float(audio.music_player.volume_db).is_equal_approx(linear_to_db(0.25), 0.001)
	assert_float(audio.effects_player.volume_db).is_equal_approx(linear_to_db(0.5), 0.001)
	assert_int(restored.resolved_window_mode()).is_equal(DisplayServer.WINDOW_MODE_WINDOWED)


func _write_settings(payload: Dictionary) -> void:
	var file := FileAccess.open(GogoSettingsService.SETTINGS_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(payload))
	file.close()
