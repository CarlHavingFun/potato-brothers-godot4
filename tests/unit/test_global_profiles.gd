extends GdUnitTestSuite


const TEST_ROOT := "user://tests/global_profiles/profiles"
const LEGACY_PATH := "user://tests/global_profiles/legacy/save_v1.json"

var _original_provider: SaveProvider


class FailingProfileSaveProvider:
	extends ProfileSaveProvider

	func save_slot(_payload: Variant) -> Error:
		return ERR_CANT_CREATE


func before_test() -> void:
	_original_provider = Global.save_provider
	_cleanup_files()


func after_test() -> void:
	Global.end_run()
	Global.save_provider = _original_provider
	Global.meta_progress = MetaProgress.new()
	Global.restored_run = null
	_cleanup_files()


func test_switch_profile_loads_its_progress_and_clears_live_run() -> void:
	var store := ProfileStore.new(TEST_ROOT, LEGACY_PATH)
	var profile_one := MetaProgress.new()
	profile_one.highest_unlocked_difficulty = 2
	var profile_two := MetaProgress.new()
	profile_two.highest_unlocked_difficulty = 4
	store.save_profile(1, {"meta_progress": profile_one.to_dict()})
	store.save_profile(2, {"meta_progress": profile_two.to_dict()})
	Global.save_provider = ProfileSaveProvider.new(store, 1)
	Global.load_progress()
	Global.begin_run(77)

	assert_bool(Global.switch_profile(2)).is_true()

	assert_object(Global.current_run).is_null()
	assert_int(Global.meta_progress.highest_unlocked_difficulty).is_equal(4)
	assert_int(Global.active_profile_id()).is_equal(2)
	assert_bool(Global.switch_profile(4)).is_false()


func test_switch_profile_keeps_live_run_when_checkpoint_save_fails() -> void:
	var store := ProfileStore.new(TEST_ROOT, LEGACY_PATH)
	store.save_profile(1, {"meta_progress": MetaProgress.new().to_dict()})
	store.save_profile(2, {"meta_progress": MetaProgress.new().to_dict()})
	Global.save_provider = FailingProfileSaveProvider.new(store, 1)
	Global.meta_progress = MetaProgress.new()
	Global.begin_run(88)
	Global.current_run.materials = 321
	var live_run := Global.current_run

	assert_bool(Global.switch_profile(2)).is_false()

	assert_object(Global.current_run).is_same(live_run)
	assert_int(Global.current_run.materials).is_equal(321)
	assert_int(Global.active_profile_id()).is_equal(1)


func test_selecting_the_active_profile_is_a_noop_for_the_live_run() -> void:
	var store := ProfileStore.new(TEST_ROOT, LEGACY_PATH)
	store.save_profile(1, {"meta_progress": MetaProgress.new().to_dict()})
	Global.save_provider = ProfileSaveProvider.new(store, 1)
	Global.meta_progress = MetaProgress.new()
	Global.begin_run(99)
	Global.current_run.materials = 123
	var live_run := Global.current_run

	assert_bool(Global.switch_profile(1)).is_true()

	assert_object(Global.current_run).is_same(live_run)
	assert_int(Global.current_run.materials).is_equal(123)
	assert_int(Global.active_profile_id()).is_equal(1)


func _cleanup_files() -> void:
	for slot in range(1, 4):
		for suffix in ["", ".tmp", ".bak"]:
			var path: String = "%s/%d/save_v4.json%s" % [TEST_ROOT, slot, suffix]
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for suffix in ["", ".tmp", ".bak"]:
		var index_path: String = "%s/profile_index_v1.json%s" % [TEST_ROOT, suffix]
		if FileAccess.file_exists(index_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(index_path))
