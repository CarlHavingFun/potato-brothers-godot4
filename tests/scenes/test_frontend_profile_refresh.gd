extends GdUnitTestSuite


const FRONTEND_SCENE := "res://scenes/ui/frontend/frontend_shell.tscn"
const TEST_SAVE_ROOT := "user://tests/frontend_profile_refresh"

var _original_provider: SaveProvider
var _store: ProfileStore


func before_test() -> void:
	_original_provider = Global.save_provider
	_store = ProfileStore.new(TEST_SAVE_ROOT, "")
	Global.save_provider = ProfileSaveProvider.new(_store, 1)
	Global.end_run()
	Global.meta_progress = MetaProgress.new()
	Global.meta_progress.highest_unlocked_difficulty = 5
	Global.save_progress(false)
	Global.stage_profile_for_new_run(2)
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
	assert_int(_locked_character_count(choices)).is_equal(0)

	frontend.call("_select_profile", 2)

	assert_bool(_locked_character_count(choices) > 0).is_true()


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


func test_profile_labels_use_localized_words_without_unsupported_marker_glyphs() -> void:
	var frontend: Control = auto_free(load(FRONTEND_SCENE).instantiate())
	add_child(frontend)
	await await_idle_frame()

	var title_profile_button := frontend.get_node(
		"Pages/TitlePage/SafeArea/Layout/Menu/ProfileButton"
	) as Button
	var profile_choices := frontend.get_node("Pages/ProfilePage/Content/ProfileChoices")
	var active_select_button := profile_choices.get_child(0).get_child(0) as Button
	var profile_name := str(Global.profile_summaries()[0].get("name", ""))

	assert_str(title_profile_button.text).is_equal(
		LocalizedTextService.resolve(&"ui.profile.current", [profile_name])
	)
	assert_str(active_select_button.text).starts_with(
		LocalizedTextService.resolve(&"ui.profile.active_name", [profile_name])
	)
	for unsupported_marker: String in ["›", "●", "▤"]:
		assert_str(title_profile_button.text).not_contains(unsupported_marker)
		assert_str(active_select_button.text).not_contains(unsupported_marker)


func test_fresh_install_shows_no_profile_until_a_run_is_created() -> void:
	for slot: int in range(1, ProfileStore.MAX_PROFILES + 1):
		assert_int(_store.delete_profile(slot)).is_equal(OK)
	Global.end_run()
	Global.meta_progress = MetaProgress.new()

	var frontend: Control = auto_free(load(FRONTEND_SCENE).instantiate())
	add_child(frontend)
	await await_idle_frame()

	var title_profile_button := frontend.get_node(
		"Pages/TitlePage/SafeArea/Layout/Menu/ProfileButton"
	) as Button
	var profile_choices := frontend.get_node("Pages/ProfilePage/Content/ProfileChoices")
	var first_select := profile_choices.get_child(0).get_child(0) as Button
	var first_create := profile_choices.get_child(0).get_child(1) as Button
	var empty_slot_name := LocalizedTextService.resolve(&"ui.profile.empty_slot", [1])

	assert_str(title_profile_button.text).is_equal(
		LocalizedTextService.resolve(&"ui.profile.none")
	)
	assert_str(first_select.text).starts_with(
		LocalizedTextService.resolve(&"ui.profile.pending_name", [empty_slot_name])
	)
	assert_str(first_select.text).not_contains(
		LocalizedTextService.resolve(&"ui.profile.default_name", [1])
	)
	assert_str(first_create.text).is_equal(
		LocalizedTextService.resolve(&"ui.profile.create")
	)
	assert_bool(FileAccess.file_exists(_store.profile_path(1))).is_false()

	frontend.call("_on_primary_pressed")
	await await_idle_frame()
	assert_int(int(frontend.get("current_step"))).is_equal(SelectionStep.Value.CHARACTER)
	assert_bool(FileAccess.file_exists(_store.profile_path(1))).is_false()


func test_profile_page_focuses_active_slot_and_has_explicit_row_navigation() -> void:
	var frontend: Control = auto_free(load(FRONTEND_SCENE).instantiate())
	add_child(frontend)
	await await_idle_frame()

	frontend.call("_on_profiles_pressed")
	await await_idle_frame()
	await await_idle_frame()

	var choices := frontend.get_node("Pages/ProfilePage/Content/ProfileChoices")
	var active_select := choices.get_child(0).get_child(0) as Button
	var active_rename := choices.get_child(0).get_child(1) as Button
	assert_object(frontend.get_viewport().gui_get_focus_owner()).is_same(active_select)
	assert_str(String(active_select.focus_neighbor_right)).is_not_empty()
	assert_str(String(active_select.focus_neighbor_top)).is_not_empty()
	assert_str(String(active_select.focus_neighbor_bottom)).is_not_empty()

	_push_action(frontend.get_viewport(), &"ui_right")
	await await_idle_frame()
	assert_object(frontend.get_viewport().gui_get_focus_owner()).is_same(active_rename)


func test_profile_back_button_returns_to_title_and_remains_clickable_after_reentry() -> void:
	var frontend: Control = auto_free(load(FRONTEND_SCENE).instantiate())
	add_child(frontend)
	await await_idle_frame()
	var back_button := frontend.get_node("Pages/ProfilePage/Content/Header/BackButton") as Button

	for iteration: int in 2:
		frontend.call("_on_profiles_pressed")
		await await_idle_frame()
		assert_int(int(frontend.get("current_step"))).is_equal(SelectionStep.Value.PROFILE)
		back_button.emit_signal("pressed")
		await await_idle_frame()
		assert_int(int(frontend.get("current_step"))).is_equal(SelectionStep.Value.TITLE)
		assert_bool(frontend.get_node("Pages/TitlePage").visible).is_true()


func test_profile_page_distinguishes_created_slot_and_keeps_rename_validation_visible() -> void:
	assert_int(Global.rename_profile(3, "仅命名")).is_equal(OK)
	var frontend: Control = auto_free(load(FRONTEND_SCENE).instantiate())
	add_child(frontend)
	await await_idle_frame()

	var choices := frontend.get_node("Pages/ProfilePage/Content/ProfileChoices")
	var third_select := choices.get_child(2).get_child(0) as Button
	assert_str(third_select.text).contains(
		LocalizedTextService.resolve(&"ui.profile.state.created")
	)
	assert_str(third_select.text).not_contains(
		LocalizedTextService.resolve(&"ui.profile.state.progress")
	)

	frontend.call("_request_rename_profile", 3, "仅命名")
	var rename_input := frontend.get("_rename_input") as LineEdit
	var rename_error := frontend.get("_rename_error") as Label
	assert_object(rename_input.get_parent()).is_instanceof(VBoxContainer)
	assert_bool(rename_input.custom_minimum_size.x >= 420.0).is_true()
	rename_input.text = ""
	frontend.call("_confirm_rename_profile")
	assert_bool(rename_error.visible).is_true()
	assert_str(rename_error.text).is_equal(
		LocalizedTextService.resolve(&"ui.profile.rename.invalid")
	)


func test_profile_rebuild_restores_gamepad_focus_after_rename_and_delete() -> void:
	var frontend: Control = auto_free(load(FRONTEND_SCENE).instantiate())
	add_child(frontend)
	await await_idle_frame()
	frontend.call("_on_profiles_pressed")
	await await_idle_frame()
	await await_idle_frame()

	frontend.call("_request_rename_profile", 1, "档案 1")
	var rename_dialog := frontend.get("_rename_dialog") as ConfirmationDialog
	var rename_input := frontend.get("_rename_input") as LineEdit
	rename_input.text = "改名后"
	rename_dialog.hide()
	frontend.call("_confirm_rename_profile")
	await await_idle_frame()
	await await_idle_frame()
	var choices := frontend.get_node("Pages/ProfilePage/Content/ProfileChoices")
	var active_select := choices.get_child(0).get_child(0) as Button
	assert_object(frontend.get_viewport().gui_get_focus_owner()).is_same(active_select)

	frontend.call("_request_delete_profile", 2)
	var delete_dialog := frontend.get("_delete_dialog") as ConfirmationDialog
	delete_dialog.hide()
	frontend.call("_confirm_delete_profile")
	await await_idle_frame()
	await await_idle_frame()
	choices = frontend.get_node("Pages/ProfilePage/Content/ProfileChoices")
	var deleted_slot_select := choices.get_child(1).get_child(0) as Button
	assert_object(frontend.get_viewport().gui_get_focus_owner()).is_same(deleted_slot_select)


func _push_action(viewport: Viewport, action: StringName) -> void:
	var pressed := InputEventAction.new()
	pressed.action = action
	pressed.pressed = true
	viewport.push_input(pressed)
	var released := InputEventAction.new()
	released.action = action
	released.pressed = false
	viewport.push_input(released)


func _locked_character_count(choices: Node) -> int:
	var result := 0
	for child: Node in choices.get_children():
		if (
			child is Button
			and child.has_meta("content_id")
			and not bool(child.get_meta(&"unlocked", true))
		):
			result += 1
	return result
