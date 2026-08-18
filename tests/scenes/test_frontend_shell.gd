extends GdUnitTestSuite


const FRONTEND_SCENE := "res://scenes/ui/frontend/frontend_shell.tscn"


func test_frontend_exposes_title_character_weapon_and_final_difficulty_pages() -> void:
	assert_bool(ResourceLoader.exists(FRONTEND_SCENE)).is_true()
	var frontend: Control = auto_free(load(FRONTEND_SCENE).instantiate())
	add_child(frontend)
	await await_idle_frame()

	for page_name: StringName in [&"TitlePage", &"ProfilePage", &"CharacterPage", &"WeaponPage", &"DifficultyPage"]:
		assert_object(frontend.find_child(String(page_name), true, false)).is_not_null()
	assert_bool(frontend.get_node("Pages/TitlePage").visible).is_true()
	assert_int(frontend.get("current_step")).is_equal(SelectionStep.Value.TITLE)


func test_character_to_compatible_weapon_to_final_overview_flow() -> void:
	var frontend: Control = auto_free(load(FRONTEND_SCENE).instantiate())
	add_child(frontend)
	await await_idle_frame()
	var character := Content.catalog.get_characters()[0]
	var character_id := character.get_stable_id(Content.catalog.pack_id)

	frontend.call("begin_new_run", 1, 734, AimMode.AUTO_TARGET)
	frontend.call("choose_character", character_id)

	assert_bool(frontend.get_node("Pages/WeaponPage").visible).is_true()
	var expected_weapons := character.starter_weapon_ids.duplicate()
	if expected_weapons.is_empty():
		for weapon: WeaponDef in Content.catalog.get_weapons():
			expected_weapons.append(weapon.get_stable_id(Content.catalog.pack_id))
	assert_array(frontend.call("visible_weapon_ids")).contains_exactly(expected_weapons)
	var weapon_id: StringName = expected_weapons[0]
	frontend.call("choose_weapon", weapon_id)

	assert_bool(frontend.get_node("Pages/DifficultyPage").visible).is_true()
	assert_str(frontend.get_node("Pages/DifficultyPage/Content/Overview/CharacterCard/Name").text).is_not_empty()
	assert_str(frontend.get_node("Pages/DifficultyPage/Content/Overview/WeaponCard/Name").text).is_not_empty()
	assert_int(frontend.get_node("Pages/DifficultyPage/Content/DifficultyChoices").get_child_count()).is_equal(5)


func test_back_navigation_preserves_draft_and_restores_page_focus() -> void:
	var frontend: Control = auto_free(load(FRONTEND_SCENE).instantiate())
	add_child(frontend)
	await await_idle_frame()
	var character := Content.catalog.get_characters()[0]
	var character_id := character.get_stable_id(Content.catalog.pack_id)
	var weapon_id: StringName = _first_allowed_weapon_id(character)

	frontend.call("begin_new_run", 1, 91, AimMode.MANUAL_MOUSE)
	frontend.call("choose_character", character_id)
	frontend.call("choose_weapon", weapon_id)
	frontend.call("go_back")

	assert_bool(frontend.get_node("Pages/WeaponPage").visible).is_true()
	assert_str(str(frontend.get("draft").character_id)).is_equal(str(character_id))
	assert_str(str(frontend.get("draft").weapon_id)).is_equal(str(weapon_id))
	assert_bool(frontend.get("last_focus_restored")).is_true()


func test_locked_difficulty_cannot_launch_and_unlocked_choice_emits_one_request() -> void:
	var frontend: Control = auto_free(load(FRONTEND_SCENE).instantiate())
	add_child(frontend)
	await await_idle_frame()
	var character := Content.catalog.get_characters()[0]
	var character_id := character.get_stable_id(Content.catalog.pack_id)
	var weapon_id: StringName = _first_allowed_weapon_id(character)
	var requests: Array[RunLaunchRequest] = []
	frontend.run_requested.connect(func(request: RunLaunchRequest) -> void: requests.append(request))

	frontend.call("begin_new_run", 1, 12, AimMode.AUTO_TARGET)
	frontend.call("choose_character", character_id)
	frontend.call("choose_weapon", weapon_id)
	frontend.call("choose_difficulty", 5, 1)
	frontend.call("choose_difficulty", 1, 1)

	assert_int(requests.size()).is_equal(1)
	assert_int(requests[0].difficulty).is_equal(1)
	assert_str(str(requests[0].character_id)).is_equal(str(character_id))
	assert_str(str(requests[0].weapon_id)).is_equal(str(weapon_id))


func test_endless_run_option_is_keyboard_focusable_and_reaches_launch_request() -> void:
	var frontend: Control = auto_free(load(FRONTEND_SCENE).instantiate())
	add_child(frontend)
	await await_idle_frame()
	var run_mode_option := frontend.get_node(
		"Pages/CharacterPage/Content/Body/OptionsCard/Options/RunMode"
	) as OptionButton
	assert_object(run_mode_option).is_not_null()
	assert_int(run_mode_option.focus_mode).is_equal(Control.FOCUS_ALL)
	var character := Content.catalog.get_characters()[0]
	var weapon_id := _first_allowed_weapon_id(character)
	var requests: Array[RunLaunchRequest] = []
	frontend.run_requested.connect(func(request: RunLaunchRequest) -> void: requests.append(request))

	frontend.call("begin_new_run", 1, 13, AimMode.AUTO_TARGET)
	frontend.call("_on_run_mode_selected", RunMode.ENDLESS)
	frontend.call("choose_character", character.get_stable_id(Content.catalog.pack_id))
	frontend.call("choose_weapon", weapon_id)
	frontend.call("choose_difficulty", 1, 1)

	assert_int(requests.size()).is_equal(1)
	assert_int(requests[0].run_mode).is_equal(RunMode.ENDLESS)
	assert_int(run_mode_option.selected).is_equal(RunMode.ENDLESS)


func test_frontend_branding_is_resolved_from_the_selected_skin_manifest() -> void:
	var frontend: Control = auto_free(load(FRONTEND_SCENE).instantiate())
	add_child(frontend)
	await await_idle_frame()

	assert_str(frontend.get_node("Pages/TitlePage/SafeArea/Layout/Logo/Name").text).is_equal(
		Presentation.active_skin.product_name
	)
	assert_object(frontend.get_node("Background").texture).is_same(Presentation.active_skin.background)


func test_button_feedback_keeps_visual_and_click_rect_stationary() -> void:
	var frontend: Control = auto_free(load(FRONTEND_SCENE).instantiate())
	add_child(frontend)
	await await_idle_frame()
	var button := frontend.get_node("Pages/TitlePage/SafeArea/Layout/Menu/PrimaryButton") as Button
	var position_before := button.position
	var size_before := button.size

	frontend.call("_animate_button", button, true)
	await get_tree().create_timer(0.12).timeout

	assert_vector(button.scale).is_equal(Vector2.ONE)
	assert_vector(button.position).is_equal(position_before)
	assert_vector(button.size).is_equal(size_before)


func _first_allowed_weapon_id(character: CharacterDef) -> StringName:
	if not character.starter_weapon_ids.is_empty():
		return character.starter_weapon_ids[0]
	return Content.catalog.get_weapons()[0].get_stable_id(Content.catalog.pack_id)
