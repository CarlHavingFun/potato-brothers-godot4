extends GdUnitTestSuite


const TEST_ROOT := "user://tests/settings_store"


func before_test() -> void:
	_cleanup_files()


func after_test() -> void:
	_cleanup_files()


func test_defaults_match_product_baseline() -> void:
	var settings := ProductSettings.new()

	assert_float(settings.master_volume).is_equal(1.0)
	assert_float(settings.music_volume).is_equal(0.7)
	assert_float(settings.sfx_volume).is_equal(0.8)
	assert_bool(settings.mute_on_focus_lost).is_false()
	assert_int(settings.display_mode).is_equal(DisplayMode.BORDERLESS_FULLSCREEN)
	assert_object(settings.resolution).is_equal(Vector2i(1920, 1080))
	assert_bool(settings.vsync_enabled).is_true()
	assert_int(settings.fps_cap).is_equal(0)
	assert_int(settings.aim_mode).is_equal(AimMode.AUTO_TARGET)
	assert_bool(settings.pause_on_focus_lost).is_true()
	assert_bool(settings.show_damage_numbers).is_true()
	assert_bool(settings.show_player_health_bar).is_true()
	assert_bool(settings.show_boss_health_bar).is_true()
	assert_float(settings.enemy_health_scale).is_equal(1.0)
	assert_float(settings.enemy_damage_scale).is_equal(1.0)
	assert_float(settings.enemy_speed_scale).is_equal(1.0)
	assert_float(settings.ui_scale).is_equal(1.0)
	assert_float(settings.screen_shake_intensity).is_equal(1.0)
	assert_float(settings.gamepad_rumble_intensity).is_equal(1.0)
	assert_bool(settings.reduce_flashes).is_false()
	assert_bool(settings.high_contrast_projectiles).is_false()
	assert_float(settings.gamepad_deadzone).is_equal(0.25)


func test_round_trip_clamps_invalid_values_and_normalizes_resolution() -> void:
	var restored := ProductSettings.from_dict({
		"master_volume": 2.0,
		"music_volume": -1.0,
		"sfx_volume": 0.45,
		"display_mode": 99,
		"resolution": "320x200",
		"vsync_enabled": false,
		"fps_cap": 141,
		"aim_mode": 99,
		"enemy_health_scale": 0.1,
		"enemy_damage_scale": 3.0,
		"enemy_speed_scale": 1.2,
		"ui_scale": 2.0,
		"screen_shake_intensity": -0.2,
		"gamepad_rumble_intensity": 4.0,
		"gamepad_deadzone": 2.0,
	})

	assert_float(restored.master_volume).is_equal(1.0)
	assert_float(restored.music_volume).is_equal(0.0)
	assert_float(restored.sfx_volume).is_equal(0.45)
	assert_int(restored.display_mode).is_equal(DisplayMode.BORDERLESS_FULLSCREEN)
	assert_object(restored.resolution).is_equal(Vector2i(640, 360))
	assert_bool(restored.vsync_enabled).is_false()
	assert_int(restored.fps_cap).is_equal(144)
	assert_int(restored.aim_mode).is_equal(AimMode.AUTO_TARGET)
	assert_float(restored.enemy_health_scale).is_equal(0.25)
	assert_float(restored.enemy_damage_scale).is_equal(2.0)
	assert_float(restored.enemy_speed_scale).is_equal(1.2)
	assert_float(restored.ui_scale).is_equal(1.5)
	assert_float(restored.screen_shake_intensity).is_equal(0.0)
	assert_float(restored.gamepad_rumble_intensity).is_equal(1.0)
	assert_float(restored.gamepad_deadzone).is_equal(1.0)

	var round_trip := ProductSettings.from_dict(restored.to_dict())
	assert_bool(round_trip.is_equal_to(restored)).is_true()


func test_copy_and_dirty_comparison_deep_copy_input_bindings() -> void:
	var settings := ProductSettings.new()
	settings.input_bindings = {
		"move_up": [{"type": "key", "physical_keycode": 87}],
	}
	var copied := settings.copy()

	assert_bool(copied.is_equal_to(settings)).is_true()
	assert_bool(copied.is_dirty_from(settings)).is_false()
	(copied.input_bindings["move_up"] as Array)[0]["physical_keycode"] = 38

	assert_bool(copied.is_dirty_from(settings)).is_true()
	assert_int(int((settings.input_bindings["move_up"] as Array)[0]["physical_keycode"])).is_equal(87)


func test_malformed_field_types_fall_back_without_discarding_valid_fields() -> void:
	var restored := ProductSettings.from_dict({
		"master_volume": "loud",
		"music_volume": null,
		"sfx_volume": 0.4,
		"display_mode": "fullscreen",
		"resolution": {"width": "wide", "height": []},
		"vsync_enabled": "yes",
		"input_bindings": [],
	})

	assert_float(restored.master_volume).is_equal(1.0)
	assert_float(restored.music_volume).is_equal(0.7)
	assert_float(restored.sfx_volume).is_equal(0.4)
	assert_int(restored.display_mode).is_equal(DisplayMode.BORDERLESS_FULLSCREEN)
	assert_object(restored.resolution).is_equal(ProductSettings.DEFAULT_RESOLUTION)
	assert_bool(restored.vsync_enabled).is_true()
	assert_bool(restored.input_bindings.is_empty()).is_true()


func test_store_returns_defaults_without_creating_a_file() -> void:
	var store := SettingsStore.new(TEST_ROOT)

	var settings := store.load_settings()

	assert_str(SettingsStore.DEFAULT_SETTINGS_PATH).is_equal("user://save/settings_v1.json")
	assert_str(SettingsStore.new().settings_path()).is_equal(SettingsStore.DEFAULT_SETTINGS_PATH)
	assert_bool(settings.is_equal_to(ProductSettings.new())).is_true()
	assert_bool(FileAccess.file_exists(store.settings_path())).is_false()
	assert_bool(store.recovered_from_backup).is_false()


func test_store_recovers_corrupted_primary_from_valid_backup() -> void:
	var store := SettingsStore.new(TEST_ROOT)
	var first := ProductSettings.new()
	first.master_volume = 0.2
	assert_int(store.save_settings(first)).is_equal(OK)
	var second := first.copy()
	second.master_volume = 0.8
	assert_int(store.save_settings(second)).is_equal(OK)
	assert_bool(FileAccess.file_exists(store.settings_path() + ".bak")).is_true()
	assert_bool(FileAccess.file_exists(store.settings_path() + ".tmp")).is_false()
	var primary := FileAccess.open(store.settings_path(), FileAccess.WRITE)
	primary.store_string("{broken")
	primary.close()

	var recovered := store.load_settings()

	assert_float(recovered.master_volume).is_equal(0.2)
	assert_bool(store.recovered_from_backup).is_true()
	assert_float(store.load_settings().master_volume).is_equal(0.2)


func test_legacy_meta_migration_maps_known_fields_and_never_overwrites_global_settings() -> void:
	var store := SettingsStore.new(TEST_ROOT)
	var legacy := {
		"music_volume": 0.22,
		"sfx_volume": 0.31,
		"fullscreen": true,
		"resolution": "1280x720",
		"aim_mode": AimMode.MANUAL_MOUSE,
		"locale": "en",
		"enemy_health_scale": 0.5,
		"enemy_damage_scale": 1.25,
		"enemy_speed_scale": 0.9,
		"input_bindings": {"dash": [{"type": "key", "physical_keycode": 32}]},
	}

	var migrated := store.migrate_from_legacy_meta(legacy)

	assert_float(migrated.master_volume).is_equal(1.0)
	assert_float(migrated.music_volume).is_equal(0.22)
	assert_float(migrated.sfx_volume).is_equal(0.31)
	assert_int(migrated.display_mode).is_equal(DisplayMode.BORDERLESS_FULLSCREEN)
	assert_object(migrated.resolution).is_equal(Vector2i(1280, 720))
	assert_int(migrated.aim_mode).is_equal(AimMode.MANUAL_MOUSE)
	assert_str(migrated.locale).is_equal("en")
	assert_float(migrated.enemy_health_scale).is_equal(0.5)
	assert_float(migrated.enemy_damage_scale).is_equal(1.25)
	assert_float(migrated.enemy_speed_scale).is_equal(0.9)
	assert_bool(FileAccess.file_exists(store.settings_path())).is_true()

	var kept := store.migrate_from_legacy_meta({"music_volume": 0.99})
	assert_float(kept.music_volume).is_equal(0.22)


func test_reset_to_defaults_replaces_mutable_values() -> void:
	var settings := ProductSettings.new()
	settings.master_volume = 0.1
	settings.locale = "en"
	settings.input_bindings = {"dash": [1]}

	settings.reset_to_defaults()

	assert_bool(settings.is_equal_to(ProductSettings.new())).is_true()
	assert_bool(settings.input_bindings.is_empty()).is_true()


func _cleanup_files() -> void:
	var path := "%s/settings_v1.json" % TEST_ROOT
	for suffix: String in ["", ".tmp", ".bak"]:
		var target := path + suffix
		if FileAccess.file_exists(target):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(target))
