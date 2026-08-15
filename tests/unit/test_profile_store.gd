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
	assert_str(profiles[0].get("name", "")).is_equal("档案 1")
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
	assert_str(store.profile_path(1)).ends_with("save_v3.json")


func test_v2_profile_is_migrated_to_v3_without_deleting_source() -> void:
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


func _cleanup_files() -> void:
	for slot in range(1, 4):
		for version in [2, 3]:
			for suffix in ["", ".tmp", ".bak"]:
				var profile_path: String = "%s/%d/save_v%d.json%s" % [TEST_ROOT, slot, version, suffix]
				if FileAccess.file_exists(profile_path):
					DirAccess.remove_absolute(ProjectSettings.globalize_path(profile_path))
	for suffix in ["", ".tmp", ".bak"]:
		var legacy_path: String = LEGACY_PATH + suffix
		if FileAccess.file_exists(legacy_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(legacy_path))
