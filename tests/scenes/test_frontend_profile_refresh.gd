extends GdUnitTestSuite


const FRONTEND_SCENE := "res://scenes/ui/frontend/frontend_shell.tscn"
const TEST_SAVE_ROOT := "user://tests/frontend_profile_refresh"

var _original_provider: SaveProvider


func before_test() -> void:
	_original_provider = Global.save_provider
	var store := ProfileStore.new(TEST_SAVE_ROOT, "")
	Global.save_provider = ProfileSaveProvider.new(store, 1)
	Global.end_run()
	Global.meta_progress = MetaProgress.new()
	Global.meta_progress.highest_unlocked_difficulty = 5
	Global.save_progress(false)
	Global.switch_profile(2)
	Global.meta_progress.highest_unlocked_difficulty = 1
	Global.save_progress(false)
	Global.switch_profile(1)


func after_test() -> void:
	Global.end_run()
	Global.save_provider = _original_provider
	Global.meta_progress = MetaProgress.new()
	for slot: int in range(1, ProfileStore.MAX_PROFILES + 1):
		ProfileStore.new(TEST_SAVE_ROOT, "").delete_profile(slot)


func test_switching_profile_rebuilds_character_unlock_buttons() -> void:
	var frontend: Control = auto_free(load(FRONTEND_SCENE).instantiate())
	add_child(frontend)
	await await_idle_frame()
	var choices := frontend.get_node("Pages/CharacterPage/Content/CharacterChoices")
	assert_int(_disabled_character_count(choices)).is_equal(0)

	frontend.call("_select_profile", 2)

	assert_bool(_disabled_character_count(choices) > 0).is_true()


func test_profile_page_displays_persisted_save_repair_notice() -> void:
	Global.meta_progress.repair_notices = ["Recovered profile from backup after corrupted primary save."]
	var frontend: Control = auto_free(load(FRONTEND_SCENE).instantiate())
	add_child(frontend)
	await await_idle_frame()

	var notice := frontend.get_node_or_null("Pages/ProfilePage/Content/RepairNotice") as Label
	assert_object(notice).is_not_null()
	if notice != null:
		assert_bool(notice.visible).is_true()
		assert_str(notice.text).is_equal(tr("ui.profile.repair.backup"))


func _disabled_character_count(choices: Node) -> int:
	var result := 0
	for child: Node in choices.get_children():
		if child is Button and child.has_meta("content_id") and (child as Button).disabled:
			result += 1
	return result
