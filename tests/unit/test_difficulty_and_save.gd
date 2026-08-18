extends GdUnitTestSuite


const TEST_SAVE_PATH := "user://tests/save_provider/save_v1.json"


func before_test() -> void:
	_cleanup_save_files()


func after_test() -> void:
	_cleanup_save_files()


func test_five_default_difficulties_match_approved_multipliers() -> void:
	assert_object(DifficultyDef.for_level(0)).is_null()
	assert_object(DifficultyDef.for_level(6)).is_null()

	var difficulty_one := DifficultyDef.for_level(1)
	var difficulty_five := DifficultyDef.for_level(5)

	assert_float(difficulty_one.health_multiplier).is_equal(1.0)
	assert_float(difficulty_one.damage_multiplier).is_equal(1.0)
	assert_float(difficulty_five.health_multiplier).is_equal(1.7)
	assert_float(difficulty_five.damage_multiplier).is_equal(1.4)
	assert_float(difficulty_five.speed_multiplier).is_equal(1.1)
	assert_float(difficulty_five.spawn_density_multiplier).is_equal(1.4)
	assert_float(difficulty_five.elite_health_multiplier).is_greater(1.0)
	assert_float(difficulty_five.shop_price_multiplier).is_greater(1.0)
	assert_float(difficulty_five.material_drop_multiplier).is_less(1.0)
	assert_bool(difficulty_five.rule_tags.has(&"elite_frenzy")).is_true()
	assert_bool(difficulty_five.mutator.randomized_encounters).is_true()
	assert_int(difficulty_five.mutator.horde_event_count).is_equal(3)
	assert_bool(difficulty_five.mutator.double_final_boss).is_true()
	assert_int(difficulty_five.final_boss_count()).is_equal(2)


func test_difficulty_scaling_is_deterministic() -> void:
	var difficulty := DifficultyDef.for_level(3)

	assert_int(difficulty.scale_health(101)).is_equal(126)
	assert_float(difficulty.scale_damage(10.0)).is_equal(11.5)
	assert_float(difficulty.scale_speed(200.0)).is_equal(206.0)
	assert_int(difficulty.scale_spawn_count(11)).is_equal(13)
	assert_int(difficulty.scale_elite_health(101)).is_greater(difficulty.scale_health(101))
	assert_int(difficulty.scale_shop_price(11)).is_greater(11)
	assert_int(difficulty.scale_material_drop(10)).is_less(10)


func test_meta_progress_unlocks_only_the_next_difficulty() -> void:
	var progress := MetaProgress.new()

	assert_int(progress.highest_unlocked_difficulty).is_equal(1)
	assert_bool(progress.record_victory(&"well_rounded", 1)).is_true()
	assert_int(progress.highest_unlocked_difficulty).is_equal(2)
	assert_bool(progress.record_victory(&"well_rounded", 1)).is_false()
	assert_bool(progress.record_victory(&"well_rounded", 3)).is_false()
	assert_int(progress.highest_unlocked_difficulty).is_equal(2)
	assert_int(progress.highest_clear_for(&"well_rounded")).is_equal(3)


func test_local_save_round_trip_and_backup_recovery() -> void:
	var provider := LocalSaveProvider.new(TEST_SAVE_PATH)
	assert_bool(provider.is_available()).is_true()
	assert_int(provider.save_slot({"revision": 1, "materials": 10})).is_equal(OK)
	assert_int(provider.save_slot({"revision": 2, "materials": 35})).is_equal(OK)

	var primary := provider.load_slot()
	assert_int(int(primary.get("revision", 0))).is_equal(2)
	assert_int(int(primary.get("materials", 0))).is_equal(35)

	var file := FileAccess.open(TEST_SAVE_PATH, FileAccess.WRITE)
	assert_object(file).is_not_null()
	file.store_string("{corrupt json")
	file.close()

	var recovered := provider.load_slot()
	assert_int(int(recovered.get("revision", 0))).is_equal(1)
	assert_int(int(recovered.get("materials", 0))).is_equal(10)


func test_local_save_rejects_non_dictionary_payload_without_destroying_primary() -> void:
	var provider := LocalSaveProvider.new(TEST_SAVE_PATH)
	assert_int(provider.save_slot({"safe": true})).is_equal(OK)

	var invalid_result := provider.save_slot(["not", "a", "dictionary"])

	assert_int(invalid_result).is_equal(ERR_INVALID_DATA)
	assert_bool(provider.load_slot().get("safe", false)).is_true()


func test_run_and_meta_progress_restore_through_local_provider() -> void:
	var run_state := RunState.new(20260814)
	run_state.character_id = &"almighty"
	run_state.difficulty = 2
	run_state.materials = 99
	run_state.player_stats.set_stat(StatId.ELEMENTAL_DAMAGE, 14.0)
	var progress := MetaProgress.new()
	progress.record_victory(&"well_rounded", 1)
	var provider := LocalSaveProvider.new(TEST_SAVE_PATH)

	assert_int(provider.save_slot({
		"run_state": run_state.to_dict(),
		"meta_progress": progress.to_dict(),
	})).is_equal(OK)
	var payload := provider.load_slot()
	var restored_run := RunState.from_dict(payload.get("run_state", {}))
	var restored_progress := MetaProgress.from_dict(payload.get("meta_progress", {}))

	assert_str(restored_run.character_id).is_equal("almighty")
	assert_int(restored_run.difficulty).is_equal(2)
	assert_int(restored_run.materials).is_equal(99)
	assert_float(restored_run.player_stats.get_stat(StatId.ELEMENTAL_DAMAGE)).is_equal(14.0)
	assert_int(restored_progress.highest_unlocked_difficulty).is_equal(2)
	assert_int(restored_progress.highest_clear_for(&"well_rounded")).is_equal(1)


func test_default_save_path_is_namespaced_by_content_pack() -> void:
	assert_str(LocalSaveProvider.DEFAULT_SAVE_PATH).is_equal(
		"user://save/packs/potato_default/save_v1.json"
	)


func test_meta_progress_reads_legacy_settings_but_new_payload_omits_them() -> void:
	var legacy_payload := {
		"highest_unlocked_difficulty": 2,
		"music_volume": 0.35,
		"sfx_volume": 0.65,
		"fullscreen": true,
		"resolution": "1280x720",
		"aim_mode": AimMode.MANUAL_MOUSE,
		"locale": "en",
		"enemy_health_scale": 0.75,
		"enemy_damage_scale": 1.25,
		"enemy_speed_scale": 0.9,
		"input_bindings": {"dash": [{"type": "key", "physical_keycode": KEY_SPACE}]},
		"discovered_content": {"potato_default:weapon/axe": true},
		"recent_run_summary": {"wave": 20, "victory": true},
	}

	var restored := MetaProgress.from_dict(legacy_payload)

	assert_float(restored.music_volume).is_equal(0.35)
	assert_float(restored.sfx_volume).is_equal(0.65)
	assert_bool(restored.fullscreen).is_true()
	assert_str(restored.resolution).is_equal("1280x720")
	assert_int(restored.aim_mode).is_equal(AimMode.MANUAL_MOUSE)
	assert_str(restored.locale).is_equal("en")
	assert_float(restored.enemy_health_scale).is_equal(0.75)
	assert_float(restored.enemy_damage_scale).is_equal(1.25)
	assert_float(restored.enemy_speed_scale).is_equal(0.9)
	assert_bool(restored.input_bindings.has("dash")).is_true()

	var new_payload := restored.to_dict()
	for legacy_setting_key: String in [
		"music_volume", "sfx_volume", "fullscreen", "resolution", "aim_mode", "locale",
		"enemy_health_scale", "enemy_damage_scale", "enemy_speed_scale", "input_bindings",
	]:
		assert_bool(new_payload.has(legacy_setting_key)).is_false()
	var round_trip := MetaProgress.from_dict(new_payload)
	assert_int(round_trip.highest_unlocked_difficulty).is_equal(2)
	assert_bool(round_trip.is_discovered(&"potato_default:weapon/axe")).is_true()
	assert_int(round_trip.recent_run_summary.get("wave", 0)).is_equal(20)
	assert_float(round_trip.music_volume).is_equal(0.7)
	assert_float(round_trip.enemy_health_scale).is_equal(1.0)


func _cleanup_save_files() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		var path: String = TEST_SAVE_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
