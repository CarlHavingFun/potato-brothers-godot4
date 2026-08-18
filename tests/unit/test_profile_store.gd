extends GdUnitTestSuite


const TEST_ROOT := "user://tests/profile_store/profiles"
const LEGACY_PATH := "user://tests/profile_store/legacy/save_v1.json"


func before_test() -> void:
	_cleanup_files()


func after_test() -> void:
	_cleanup_files()


func test_profile_store_exposes_three_isolated_slots() -> void:
	var store := ProfileStore.new(TEST_ROOT, LEGACY_PATH)

	var profiles: Array[Dictionary] = store.list_profiles()

	assert_int(profiles.size()).is_equal(3)
	assert_str(profiles[0].get("name", "")).is_equal(
		LocalizedTextService.resolve(&"ui.profile.default_name", [1], "Profile %d")
	)
	assert_bool(profiles[0].get("exists", true)).is_false()
	assert_int(store.save_profile(1, {"materials": 15})).is_equal(OK)
	assert_int(store.save_profile(2, {"materials": 99})).is_equal(OK)
	assert_int(int(store.load_profile(1).get("materials", 0))).is_equal(15)
	assert_int(int(store.load_profile(2).get("materials", 0))).is_equal(99)
	assert_bool(store.load_profile(3).is_empty()).is_true()


func test_profile_rename_and_delete_change_only_the_target_slot() -> void:
	var store := ProfileStore.new(TEST_ROOT, LEGACY_PATH)
	store.save_profile(1, {"revision": 1})
	store.save_profile(2, {"revision": 2})

	assert_int(store.rename_profile(2, "冲刺档案")).is_equal(OK)
	assert_str(store.profile_summary(2).get("name", "")).is_equal("冲刺档案")
	assert_int(store.delete_profile(2)).is_equal(OK)
	assert_bool(store.load_profile(2).is_empty()).is_true()
	assert_int(int(store.load_profile(1).get("revision", 0))).is_equal(1)


func test_profile_load_recovers_from_valid_backup() -> void:
	var store := ProfileStore.new(TEST_ROOT, LEGACY_PATH)
	store.save_profile(1, {"revision": 1})
	store.save_profile(1, {"revision": 2})
	var primary := FileAccess.open(store.profile_path(1), FileAccess.WRITE)
	primary.store_string("{broken")
	primary.close()

	var recovered := store.load_profile(1)
	assert_int(int(recovered.get("revision", 0))).is_equal(1)
	assert_bool(store.call("_read_document_direct", store.profile_path(1)).is_empty()).is_false()
	var notices: Array = recovered.get("meta_progress", {}).get("repair_notices", [])
	assert_bool(notices.any(func(notice: Variant): return "backup" in str(notice).to_lower())).is_true()


func test_legacy_v1_payload_migrates_to_slot_one_without_deleting_source() -> void:
	var legacy := LocalSaveProvider.new(LEGACY_PATH)
	assert_int(legacy.save_slot({
		"meta_progress": {
			"highest_unlocked_difficulty": 3,
			"unlocked_character_ids": ["potato_default:character/brawler"],
			"discovered_content": {"potato_default:weapon/punch": true},
		},
		"run_state": {
			"character_id": "potato_default:character/brawler",
			"starting_weapon_id": "potato_default:weapon/punch",
		},
	})).is_equal(OK)
	var store := ProfileStore.new(TEST_ROOT, LEGACY_PATH)

	assert_bool(store.migrate_legacy_to_slot_one()).is_true()

	assert_int(int(
		store.load_profile(1).get("meta_progress", {}).get("highest_unlocked_difficulty", 0)
	)).is_equal(3)
	var migrated := store.load_profile(1)
	assert_array(migrated.get("meta_progress", {}).get("unlocked_character_ids", [])).contains_exactly(
		["core:character/brawler"]
	)
	assert_bool(migrated.get("meta_progress", {}).get("discovered_content", {}).get(
		"core:weapon/punch", false
	)).is_true()
	assert_str(migrated.get("run_state", {}).get("character_id", "")).is_equal(
		"core:character/brawler"
	)
	assert_str(migrated.get("run_state", {}).get("starting_weapon_id", "")).is_equal(
		"core:weapon/punch"
	)
	assert_bool(FileAccess.file_exists(LEGACY_PATH)).is_true()
	assert_bool(store.migrate_legacy_to_slot_one()).is_false()
	assert_str(store.profile_path(1)).ends_with("save_v4.json")


func test_v2_profile_is_migrated_to_v4_without_deleting_source() -> void:
	var v2_path := "%s/1/save_v2.json" % TEST_ROOT
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(v2_path.get_base_dir()))
	var file := FileAccess.open(v2_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"save_version": 2,
		"profile_id": 1,
		"profile_name": "Legacy",
		"updated_unix": 10,
		"payload": {
			"meta_progress": {
				"character_highest_clears": {"potato_default:character/brawler": 4},
			},
			"run_state": {
				"character_id": "potato_default:character/brawler",
				"starting_weapon_id": "potato_default:weapon/punch",
				"inventory": {
					"weapons": [{"weapon_id": "potato_default:weapon/punch", "tier": 2}],
					"passives": {"potato_default:passive/cape": 1},
				},
				"shop_slots": [{"offer_id": "potato_default:weapon/pistol", "tier": 1, "item_type": 0}],
			},
		},
	}))
	file.close()
	var store := ProfileStore.new(TEST_ROOT, LEGACY_PATH)

	var migrated := store.load_profile(1)

	assert_str(migrated.get("run_state", {}).get("character_id", "")).is_equal(
		"core:character/brawler"
	)
	assert_str(migrated.get("run_state", {}).get("inventory", {}).get("weapons", [])[0].get(
		"weapon_id", ""
	)).is_equal("core:weapon/punch")
	assert_int(int(migrated.get("run_state", {}).get("inventory", {}).get("passives", {}).get(
		"core:passive/cape", 0
	))).is_equal(1)
	assert_bool(FileAccess.file_exists(v2_path)).is_true()
	assert_bool(FileAccess.file_exists(store.profile_path(1))).is_true()


func test_v3_profile_migrates_to_v4_and_keeps_rebuild_source() -> void:
	var v3_path := "%s/1/save_v3.json" % TEST_ROOT
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(v3_path.get_base_dir()))
	var file := FileAccess.open(v3_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"save_version": 3,
		"profile_id": 1,
		"profile_name": "V3",
		"payload": {
			"run_state": {
				"character_id": "core:character/well_rounded",
				"starting_weapon_id": "core:weapon/pistol",
				"player_stats": {"damage": 17.0},
				"inventory": {},
			},
		},
	}))
	file.close()
	var store := ProfileStore.new(TEST_ROOT, LEGACY_PATH)

	var migrated := store.load_profile(1)
	var run_data: Dictionary = migrated.get("run_state", {})

	assert_bool(FileAccess.file_exists(v3_path)).is_true()
	assert_bool(FileAccess.file_exists(store.profile_path(1))).is_true()
	assert_str(run_data.get("stat_rules_version", "")).is_equal(RunState.LEGACY_STAT_RULES_VERSION)
	assert_str(run_data.get("balance_pack_version", "")).is_equal(RunState.LEGACY_BALANCE_PACK_VERSION)
	assert_float(run_data.get("stat_rebuild_source", {}).get(
		"legacy_player_stats", {}
	).get("damage", 0.0)).is_equal(17.0)


func test_profile_save_provider_switches_active_slot_without_cross_contamination() -> void:
	var store := ProfileStore.new(TEST_ROOT, LEGACY_PATH)
	var provider := ProfileSaveProvider.new(store, 1)

	assert_int(provider.save_slot({"slot": 1})).is_equal(OK)
	assert_bool(provider.set_active_profile(2)).is_true()
	assert_bool(provider.load_slot().is_empty()).is_true()
	assert_int(provider.save_slot({"slot": 2})).is_equal(OK)
	assert_bool(provider.set_active_profile(1)).is_true()
	assert_int(int(provider.load_slot().get("slot", 0))).is_equal(1)
	assert_bool(provider.set_active_profile(4)).is_false()
	assert_int(provider.active_profile_id).is_equal(1)


func test_active_profile_selection_survives_provider_recreation() -> void:
	var store := ProfileStore.new(TEST_ROOT, LEGACY_PATH)
	var provider := ProfileSaveProvider.new(store, 1)

	assert_bool(provider.set_active_profile(3)).is_true()

	var restored_provider := ProfileSaveProvider.new(ProfileStore.new(TEST_ROOT, LEGACY_PATH))
	assert_int(restored_provider.active_profile_id).is_equal(3)
	assert_int(store.load_active_profile_id()).is_equal(3)


func test_first_profile_index_prefers_the_only_resumable_checkpoint() -> void:
	var store := ProfileStore.new(TEST_ROOT, LEGACY_PATH)
	store.save_profile(1, {
		"meta_progress": MetaProgress.new().to_dict(),
		"run_state": {"phase": RunPhase.SELECTION},
	})
	store.save_profile(2, {
		"meta_progress": MetaProgress.new().to_dict(),
		"run_state": {
			"phase": RunPhase.COMBAT,
			"wave": 4,
			"character_id": "core:character/brawler",
			"starting_weapon_id": "core:weapon/punch",
		},
	})

	var provider := ProfileSaveProvider.new(ProfileStore.new(TEST_ROOT, LEGACY_PATH))

	assert_int(provider.active_profile_id).is_equal(2)
	assert_int(store.load_active_profile_id()).is_equal(2)


func test_deleted_migrated_legacy_profile_does_not_reappear() -> void:
	var legacy := LocalSaveProvider.new(LEGACY_PATH)
	assert_int(legacy.save_slot({"meta_progress": {"highest_unlocked_difficulty": 3}})).is_equal(OK)
	var store := ProfileStore.new(TEST_ROOT, LEGACY_PATH)

	assert_bool(store.migrate_legacy_to_slot_one()).is_true()
	assert_bool(store.profile_summary(1).get("exists", false)).is_true()
	assert_int(store.delete_profile(1)).is_equal(OK)
	var index := FileAccess.open(store.profile_index_path(), FileAccess.WRITE)
	index.store_string("{broken")
	index.close()

	var restarted_store := ProfileStore.new(TEST_ROOT, LEGACY_PATH)
	assert_int(restarted_store.load_active_profile_id()).is_between(1, 3)
	assert_bool(restarted_store.migrate_legacy_to_slot_one()).is_false()
	assert_bool(restarted_store.profile_summary(1).get("exists", true)).is_false()
	assert_bool(FileAccess.file_exists(LEGACY_PATH)).is_true()
	assert_bool(FileAccess.file_exists(restarted_store.legacy_migration_marker_path())).is_true()


func test_first_profile_index_prefers_real_progress_over_a_newer_named_only_slot() -> void:
	var store := ProfileStore.new(TEST_ROOT, LEGACY_PATH)
	var progress := MetaProgress.new()
	progress.highest_unlocked_difficulty = 2
	assert_int(store.save_profile(1, {"meta_progress": progress.to_dict()})).is_equal(OK)
	var progress_document := store.call("_read_document", store.profile_path(1)) as Dictionary
	progress_document["updated_unix"] = 1
	assert_int(store.call("_write_document", 1, progress_document)).is_equal(OK)
	assert_int(store.rename_profile(2, "仅命名的新档案")).is_equal(OK)

	var provider := ProfileSaveProvider.new(ProfileStore.new(TEST_ROOT, LEGACY_PATH))

	assert_int(provider.active_profile_id).is_equal(1)


func test_existing_index_migration_flag_is_promoted_to_durable_marker() -> void:
	var store := ProfileStore.new(TEST_ROOT, LEGACY_PATH)
	var legacy_index := {
		"version": ProfileStore.PROFILE_INDEX_VERSION,
		"active_profile_id": 2,
		"legacy_migration_completed": true,
	}
	assert_int(store.call("_write_profile_index_document", legacy_index)).is_equal(OK)
	assert_bool(FileAccess.file_exists(store.legacy_migration_marker_path())).is_false()

	assert_bool(store.call("_legacy_migration_completed")).is_true()

	assert_bool(FileAccess.file_exists(store.legacy_migration_marker_path())).is_true()


func test_delete_from_old_index_flag_survives_loss_of_both_index_copies() -> void:
	var legacy := LocalSaveProvider.new(LEGACY_PATH)
	assert_int(legacy.save_slot({"meta_progress": {"highest_unlocked_difficulty": 3}})).is_equal(OK)
	var store := ProfileStore.new(TEST_ROOT, LEGACY_PATH)
	assert_int(store.save_profile(1, {"meta_progress": {"highest_unlocked_difficulty": 3}})).is_equal(OK)
	var legacy_index := {
		"version": ProfileStore.PROFILE_INDEX_VERSION,
		"active_profile_id": 1,
		"legacy_migration_completed": true,
	}
	assert_int(store.call("_write_profile_index_document", legacy_index)).is_equal(OK)
	assert_bool(FileAccess.file_exists(store.legacy_migration_marker_path())).is_false()

	assert_int(store.delete_profile(1)).is_equal(OK)
	for path: String in [store.profile_index_path(), store.profile_index_path() + ".bak"]:
		var broken := FileAccess.open(path, FileAccess.WRITE)
		broken.store_string("{broken")
		broken.close()

	var restarted_store := ProfileStore.new(TEST_ROOT, LEGACY_PATH)
	assert_bool(restarted_store.migrate_legacy_to_slot_one()).is_false()
	assert_bool(restarted_store.profile_summary(1).get("exists", true)).is_false()


func test_renamed_empty_profile_is_created_without_claiming_gameplay_progress() -> void:
	var store := ProfileStore.new(TEST_ROOT, LEGACY_PATH)
	assert_int(store.rename_profile(3, "测试档案")).is_equal(OK)

	var renamed_summary := store.profile_summary(3)
	assert_bool(renamed_summary.get("exists", false)).is_true()
	assert_bool(renamed_summary.get("has_progress", true)).is_false()

	var progressed := MetaProgress.new()
	progressed.highest_unlocked_difficulty = 2
	assert_int(store.save_profile(3, {"meta_progress": progressed.to_dict()})).is_equal(OK)
	assert_bool(store.profile_summary(3).get("has_progress", false)).is_true()


func test_profile_summary_only_offers_continue_for_a_resumable_checkpoint() -> void:
	var store := ProfileStore.new(TEST_ROOT, LEGACY_PATH)
	store.save_profile(1, {
		"run_state": {
			"phase": RunPhase.SELECTION,
			"character_id": "",
			"starting_weapon_id": "",
		}
	})
	assert_bool(store.profile_summary(1).get("has_checkpoint", true)).is_false()

	store.save_profile(1, {
		"run_state": {
			"phase": RunPhase.COMBAT,
			"wave": 3,
			"character_id": "core:character/brawler",
			"starting_weapon_id": "core:weapon/punch",
		}
	})
	assert_bool(store.profile_summary(1).get("has_checkpoint", false)).is_true()


func _cleanup_files() -> void:
	for slot in range(1, 4):
		for version in [2, 3, 4]:
			for suffix in ["", ".tmp", ".bak"]:
				var profile_path: String = "%s/%d/save_v%d.json%s" % [TEST_ROOT, slot, version, suffix]
				if FileAccess.file_exists(profile_path):
					DirAccess.remove_absolute(ProjectSettings.globalize_path(profile_path))
	for suffix in ["", ".tmp", ".bak"]:
		var legacy_path: String = LEGACY_PATH + suffix
		if FileAccess.file_exists(legacy_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(legacy_path))
		var index_path: String = "%s/profile_index_v1.json%s" % [TEST_ROOT, suffix]
		if FileAccess.file_exists(index_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(index_path))
	for suffix in ["", ".tmp"]:
		var migration_marker := "%s/legacy_migration_v1.completed%s" % [TEST_ROOT, suffix]
		if FileAccess.file_exists(migration_marker):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(migration_marker))
