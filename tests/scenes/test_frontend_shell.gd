extends GdUnitTestSuite


const FRONTEND_SCENE := "res://scenes/ui/frontend/frontend_shell.tscn"
const DEV_SKIN := "res://content_packs/skins/dev_placeholder/skin.tres"
const ALT_SKIN := "res://content_packs/skins/test_alt/skin.tres"
const FORMAL_SKIN := "res://content_packs/skins/lets_gooooo/skin.tres"
const FORMAL_FONT_STACK := "res://assets/font/brotato_font_stack.tres"

var _original_highest_unlocked_difficulty := 1
var _original_skin_manifest := ""


func before_test() -> void:
	_original_highest_unlocked_difficulty = Global.meta_progress.highest_unlocked_difficulty
	_original_skin_manifest = Presentation.manifest_path


func after_test() -> void:
	Global.meta_progress.highest_unlocked_difficulty = _original_highest_unlocked_difficulty
	if not _original_skin_manifest.is_empty():
		Presentation.load_manifest(_original_skin_manifest)


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


func test_generated_weapon_choice_buttons_inherit_the_formal_composite_font_stack() -> void:
	assert_int(Presentation.load_manifest(FORMAL_SKIN)).is_equal(OK)
	var frontend: FrontendShell = auto_free(load(FRONTEND_SCENE).instantiate())
	add_child(frontend)
	await await_idle_frame()
	var character: CharacterDef = Content.catalog.get_characters()[0]
	frontend.begin_new_run(1, 0xF07A, AimMode.AUTO_TARGET)
	assert_bool(frontend.choose_character(
		character.get_stable_id(Content.catalog.pack_id)
	)).is_true()
	await await_idle_frame()
	var generated_button := frontend.weapon_choices.get_child(1) as Button
	assert_object(generated_button).is_not_null()
	if generated_button == null:
		return
	var formal_stack := load(FORMAL_FONT_STACK) as Font
	assert_object(formal_stack).is_not_null()
	if formal_stack == null:
		return
	assert_object(generated_button.get_theme_font(&"font")).is_same(formal_stack)
	assert_bool(generated_button.has_theme_font_override(&"font")).is_false()


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
		LocalizedTextService.resolve(
			&"ui.title.name", [], Presentation.active_skin.product_name
		)
	)
	assert_str(frontend.get_node("Pages/TitlePage/SafeArea/Layout/Logo/Tagline").text).is_equal(
		LocalizedTextService.resolve(&"ui.frontend.subtitle")
	)
	assert_str(frontend.get_node("Pages/TitlePage/SafeArea/Layout/Version").text).is_equal(
		LocalizedTextService.resolve(&"ui.frontend.build")
	)
	assert_object(frontend.get_node("Background").texture).is_same(Presentation.active_skin.background)
	assert_bool(Presentation.active_skin.show_product_branding).is_false()
	assert_bool(frontend.get_node("Pages/TitlePage/SafeArea/Layout/Logo/Name").visible).is_false()
	assert_bool(frontend.get_node("Pages/TitlePage/SafeArea/Layout/Logo/BrandMark").visible).is_false()


func test_frontend_button_states_keep_equal_smooth_borders() -> void:
	var frontend: Control = auto_free(load(FRONTEND_SCENE).instantiate())
	add_child(frontend)
	await await_idle_frame()
	var button := frontend.get_node("Pages/TitlePage/SafeArea/Layout/Menu/PrimaryButton") as Button
	var normal := button.get_theme_stylebox(&"normal") as StyleBoxFlat
	var hover := button.get_theme_stylebox(&"hover") as StyleBoxFlat
	var pressed := button.get_theme_stylebox(&"pressed") as StyleBoxFlat

	for style: StyleBoxFlat in [normal, hover, pressed]:
		assert_object(style).is_not_null()
		assert_bool(style.anti_aliasing).is_true()
		assert_float(style.anti_aliasing_size).is_between(1.24, 1.26)
		assert_int(style.corner_detail).is_greater_equal(12)
	assert_int(normal.get_border_width_min()).is_equal(hover.get_border_width_min())
	assert_int(hover.get_border_width_min()).is_equal(pressed.get_border_width_min())


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


func test_character_page_uses_three_card_reference_hierarchy() -> void:
	var frontend_data: Array = await _spawn_frontend_in_viewport(Vector2i(1280, 720))
	var frontend := frontend_data[1] as FrontendShell
	frontend.begin_new_run(1, 401, AimMode.AUTO_TARGET)
	await await_idle_frame()

	var body := frontend.get_node("Pages/CharacterPage/Content/Body") as HBoxContainer
	var character_card := body.get_node_or_null("CharacterCard") as Panel
	var record_card := body.get_node_or_null("RecordCard") as Panel
	var options_card := body.get_node_or_null("OptionsCard") as Panel

	assert_object(character_card).is_not_null()
	assert_object(record_card).is_not_null()
	assert_object(options_card).is_not_null()
	assert_float(character_card.size.x).is_between(500.0, 520.0)
	assert_float(record_card.size.x).is_between(230.0, 250.0)
	assert_float(options_card.size.x).is_between(204.0, 224.0)
	assert_float(body.size.y).is_between(328.0, 338.0)
	var record_mark := record_card.get_node_or_null("Record/Mark") as Label
	assert_object(record_mark).is_not_null()
	if record_mark != null:
		assert_str(record_mark.text).is_not_empty()
	var grid_caption := frontend.get_node_or_null(
		"Pages/CharacterPage/Content/CharacterChoiceHint"
	) as Label
	assert_bool(grid_caption == null or not grid_caption.visible).is_true()


func test_character_preview_changes_details_without_mutating_selection_draft() -> void:
	var frontend: FrontendShell = auto_free(load(FRONTEND_SCENE).instantiate())
	add_child(frontend)
	await await_idle_frame()
	frontend.begin_new_run(1, 402, AimMode.AUTO_TARGET)
	await await_idle_frame()
	var previewed: CharacterDef = Content.catalog.get_characters().back()
	var original_draft: SelectionDraft = frontend.draft

	frontend.call("_preview_character", previewed)

	assert_int(frontend.current_step).is_equal(SelectionStep.Value.CHARACTER)
	assert_str(String(frontend.draft.character_id)).is_empty()
	assert_object(frontend.draft).is_same(original_draft)
	assert_str(frontend.character_name.text).is_equal(FrontendViewModel.character_name(previewed))


func test_returning_from_weapon_restores_selected_character_focus_and_visual_state() -> void:
	Global.meta_progress.highest_unlocked_difficulty = 5
	var frontend: FrontendShell = auto_free(load(FRONTEND_SCENE).instantiate())
	add_child(frontend)
	await await_idle_frame()
	frontend.begin_new_run(1, 403, AimMode.AUTO_TARGET)
	await await_idle_frame()
	var button := _first_unlocked_character_button(frontend)
	assert_object(button).is_not_null()
	if button == null:
		return
	button.grab_focus()
	await await_idle_frame()
	var stable_id := StringName(button.get_meta("content_id"))

	assert_bool(frontend.choose_character(stable_id)).is_true()
	await await_idle_frame()
	assert_bool(frontend.go_back()).is_true()
	await await_idle_frame()
	await await_idle_frame()

	assert_object(frontend.get_viewport().gui_get_focus_owner()).is_same(button)
	assert_bool(button.toggle_mode).is_true()
	assert_bool(button.button_pressed).is_true()


func test_character_grid_cards_use_stable_ids_and_icon_only_locked_states() -> void:
	Global.meta_progress.highest_unlocked_difficulty = 1
	var frontend: FrontendShell = auto_free(load(FRONTEND_SCENE).instantiate())
	add_child(frontend)
	await await_idle_frame()
	frontend.begin_new_run(1, 404, AimMode.AUTO_TARGET)
	await await_idle_frame()
	var choices := frontend.character_choices
	var stable_ids: Array[String] = []
	var locked_count := 0

	for child: Node in choices.get_children():
		var button := child as Button
		if button == null or not button.has_meta("content_id"):
			continue
		var stable_id := StringName(button.get_meta("content_id"))
		stable_ids.append(String(stable_id))
		var definition: CharacterDef = Content.catalog.get_character(stable_id)
		assert_object(definition).is_not_null()
		assert_str(button.tooltip_text).is_not_empty()
		if not bool(button.get_meta(&"unlocked", false)):
			locked_count += 1
			assert_bool(button.disabled).is_false()
			assert_int(button.focus_mode).is_equal(Control.FOCUS_ALL)
			assert_str(button.text).is_equal(LocalizedTextService.resolve(&"ui.character.lock_symbol"))
		else:
			assert_str(button.text).is_empty()
			assert_object(button.icon).is_not_null()

	assert_int(stable_ids.size()).is_equal(Content.catalog.get_characters().size())
	assert_int(stable_ids.size()).is_equal(stable_ids.duplicate().reduce(
		func(unique: Array, value: String) -> Array:
			if value not in unique:
				unique.append(value)
			return unique,
		[] as Array
	).size())
	assert_bool(locked_count > 0).is_true()


func test_locked_character_accept_keeps_draft_and_shows_unlock_requirement() -> void:
	Global.meta_progress.highest_unlocked_difficulty = 1
	var frontend_data: Array = await _spawn_frontend_in_viewport(Vector2i(1280, 720))
	var viewport := frontend_data[0] as SubViewport
	var frontend := frontend_data[1] as FrontendShell
	frontend.begin_new_run(1, 0x10CCED, AimMode.AUTO_TARGET)
	await await_idle_frame()
	await await_idle_frame()
	var initial := _first_unlocked_character_button(frontend)
	var locked_button := _first_locked_character_button(frontend)
	assert_object(initial).is_not_null()
	assert_object(locked_button).is_not_null()
	if initial == null or locked_button == null:
		return
	var steps_right := locked_button.get_index() - initial.get_index()
	for step: int in maxi(0, steps_right):
		await _send_ui_action(viewport, &"ui_right")

	assert_object(viewport.gui_get_focus_owner()).is_same(locked_button)
	assert_bool(locked_button.disabled).is_false()
	var locked_id := StringName(locked_button.get_meta(&"content_id"))
	var locked_definition := Content.catalog.get_character(locked_id)
	assert_object(locked_definition).is_not_null()
	if locked_definition == null:
		return
	assert_str(frontend.character_record.text).is_equal(LocalizedTextService.resolve(
		&"ui.character.unlock_requirement", [locked_definition.unlock_difficulty]
	))
	var draft_before := frontend.draft
	var received_cues: Array[StringName] = []
	var cue_listener := func(cue_id: StringName, _context: Dictionary) -> void:
		received_cues.append(cue_id)
	GameplayCues.cue_emitted.connect(cue_listener)
	await _send_ui_action(viewport, &"ui_accept")
	GameplayCues.cue_emitted.disconnect(cue_listener)

	assert_int(frontend.current_step).is_equal(SelectionStep.Value.CHARACTER)
	assert_object(frontend.draft).is_same(draft_before)
	assert_bool(frontend.draft.character_id.is_empty()).is_true()
	assert_bool(locked_button.button_pressed).is_false()
	assert_str(locked_button.text).is_equal(LocalizedTextService.resolve(
		&"ui.character.lock_symbol"
	))
	assert_array(received_cues).contains([&"ui.locked"])


func test_character_page_dpad_traverses_grid_options_back_and_returns_to_same_card() -> void:
	Global.meta_progress.highest_unlocked_difficulty = 1
	var frontend_data: Array = await _spawn_frontend_in_viewport(Vector2i(1280, 720))
	var viewport := frontend_data[0] as SubViewport
	var frontend := frontend_data[1] as FrontendShell
	frontend.begin_new_run(1, 405, AimMode.AUTO_TARGET)
	await await_idle_frame()
	await await_idle_frame()

	var first_unlocked := _first_unlocked_character_button(frontend)
	var random_button := frontend.character_choices.get_child(0) as Button
	var back_button := frontend.get_node(
		"Pages/CharacterPage/Content/Header/BackButton"
	) as Button
	var aim_mode := frontend.aim_mode_option
	var run_mode := frontend.run_mode_option
	assert_object(viewport.gui_get_focus_owner()).is_same(first_unlocked)
	for child: Node in frontend.character_choices.get_children():
		var button := child as Button
		if button != null:
			_assert_explicit_focus_neighbors(button)
	for control: Control in [back_button, aim_mode, run_mode]:
		_assert_explicit_focus_neighbors(control)

	await _send_ui_action(viewport, &"ui_left")
	assert_object(viewport.gui_get_focus_owner()).is_same(random_button)
	await _send_ui_action(viewport, &"ui_up")
	assert_object(viewport.gui_get_focus_owner()).is_same(run_mode)
	await _send_ui_action(viewport, &"ui_up")
	assert_object(viewport.gui_get_focus_owner()).is_same(aim_mode)
	await _send_ui_action(viewport, &"ui_up")
	assert_object(viewport.gui_get_focus_owner()).is_same(back_button)
	await _send_ui_action(viewport, &"ui_down")
	assert_object(viewport.gui_get_focus_owner()).is_same(aim_mode)
	await _send_ui_action(viewport, &"ui_down")
	assert_object(viewport.gui_get_focus_owner()).is_same(run_mode)
	await _send_ui_action(viewport, &"ui_down")
	assert_object(viewport.gui_get_focus_owner()).is_same(random_button)
	await _send_ui_action(viewport, &"ui_right")
	assert_object(viewport.gui_get_focus_owner()).is_same(first_unlocked)


func test_random_character_card_is_seeded_unlocked_and_advances_with_ui_accept() -> void:
	Global.meta_progress.highest_unlocked_difficulty = 1
	var chosen_ids: Array[StringName] = []
	for iteration: int in 2:
		var frontend_data: Array = await _spawn_frontend_in_viewport(Vector2i(1280, 720))
		var viewport := frontend_data[0] as SubViewport
		var frontend := frontend_data[1] as FrontendShell
		frontend.begin_new_run(1, 0x51EC710, AimMode.AUTO_TARGET)
		await await_idle_frame()
		await await_idle_frame()
		var random_button := frontend.character_choices.get_child(0) as Button

		await _send_ui_action(viewport, &"ui_left")
		assert_object(viewport.gui_get_focus_owner()).is_same(random_button)
		await _send_ui_action(viewport, &"ui_accept")

		assert_int(frontend.current_step).is_equal(SelectionStep.Value.WEAPON)
		assert_bool(frontend.get_node("Pages/WeaponPage").visible).is_true()
		assert_bool(frontend.draft.character_id.is_empty()).is_false()
		var selected := Content.catalog.get_character(frontend.draft.character_id)
		assert_object(selected).is_not_null()
		if selected != null:
			assert_bool(
				selected.unlock_difficulty <= Global.meta_progress.highest_unlocked_difficulty
			).is_true()
		chosen_ids.append(frontend.draft.character_id)

	assert_int(chosen_ids.size()).is_equal(2)
	assert_str(String(chosen_ids[0])).is_equal(String(chosen_ids[1]))


func test_character_card_styles_follow_skin_accent_without_changing_selection_state() -> void:
	Global.meta_progress.highest_unlocked_difficulty = 1
	var dev_snapshot: Dictionary = await _character_style_snapshot(DEV_SKIN)
	var alt_snapshot: Dictionary = await _character_style_snapshot(ALT_SKIN)

	assert_bool((dev_snapshot.accent as Color).is_equal_approx(
		Color(0.22, 0.68, 1.0, 1.0)
	)).is_true()
	assert_bool((alt_snapshot.accent as Color).is_equal_approx(
		Color(0.82, 0.42, 0.92, 1.0)
	)).is_true()
	for color_key: StringName in [
		&"normal", &"focus", &"selected_color", &"glow",
	]:
		assert_bool(not (dev_snapshot[color_key] as Color).is_equal_approx(
			alt_snapshot[color_key] as Color
		)).override_failure_message(String(color_key)).is_true()
	assert_str(String(dev_snapshot.character_id)).is_equal(String(alt_snapshot.character_id))
	assert_bool(bool(dev_snapshot.selected)).is_true()
	assert_bool(bool(alt_snapshot.selected)).is_true()


func test_character_page_fits_1280x720_and_1920x1080_without_clipping() -> void:
	for viewport_size: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		var frontend_data: Array = await _spawn_frontend_in_viewport(viewport_size)
		var frontend := frontend_data[1] as FrontendShell
		frontend.begin_new_run(1, viewport_size.x, AimMode.AUTO_TARGET)
		await await_idle_frame()
		await await_idle_frame()
		var body := frontend.get_node("Pages/CharacterPage/Content/Body") as Control
		var choices := frontend.character_choices
		_assert_rect_inside_viewport(body.get_global_rect(), viewport_size)
		_assert_rect_inside_viewport(choices.get_global_rect(), viewport_size)
		for child: Node in choices.get_children():
			var button := child as Button
			if button != null:
				_assert_rect_inside_viewport(button.get_global_rect(), viewport_size)
				if viewport_size.y <= 720:
					assert_float(button.size.x).is_between(68.0, 76.0)
					assert_float(button.size.y).is_between(60.0, 68.0)
				else:
					assert_float(button.size.x).is_between(88.0, 96.0)
					assert_float(button.size.y).is_between(80.0, 88.0)


func test_weapon_page_fits_all_choices_at_1280x720_and_1920x1080() -> void:
	for viewport_size: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		var frontend_data: Array = await _spawn_frontend_in_viewport(viewport_size)
		var frontend := frontend_data[1] as FrontendShell
		frontend.begin_new_run(1, viewport_size.y, AimMode.AUTO_TARGET)
		await await_idle_frame()
		var character: CharacterDef = Content.catalog.get_characters()[0]
		assert_bool(frontend.choose_character(
			character.get_stable_id(Content.catalog.pack_id)
		)).is_true()
		await await_idle_frame()
		await await_idle_frame()

		var header := frontend.get_node("Pages/WeaponPage/Content/Header") as Control
		var body := frontend.get_node("Pages/WeaponPage/Content/Body") as Control
		var choices := frontend.weapon_choices
		assert_int(choices.get_child_count()).is_equal(25)
		_assert_rect_inside_viewport(header.get_global_rect(), viewport_size)
		_assert_rect_inside_viewport(body.get_global_rect(), viewport_size)
		_assert_rect_inside_viewport(choices.get_global_rect(), viewport_size)
		for child: Node in choices.get_children():
			var button := child as Button
			if button == null:
				continue
			_assert_rect_inside_viewport(button.get_global_rect(), viewport_size)
			if button.icon != null:
				assert_int(button.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_NEAREST)
				assert_int(button.get_theme_constant(&"icon_max_width")).is_greater_equal(
					52 if viewport_size.x <= 1280 else 64
				)


func test_weapon_stats_dpad_scrolls_and_cancel_returns_to_originating_card() -> void:
	var frontend_data: Array = await _spawn_frontend_in_viewport(Vector2i(1280, 720))
	var viewport := frontend_data[0] as SubViewport
	var frontend := frontend_data[1] as FrontendShell
	frontend.begin_new_run(1, 0x57A75, AimMode.AUTO_TARGET)
	await await_idle_frame()
	var character: CharacterDef = Content.catalog.get_characters()[0]
	assert_bool(frontend.choose_character(
		character.get_stable_id(Content.catalog.pack_id)
	)).is_true()
	await await_idle_frame()
	await await_idle_frame()

	var choices := frontend.weapon_choices
	var weapon_button := choices.get_child(1) as Button
	var stats := frontend.weapon_stats
	var scroll_bar := stats.get_v_scroll_bar()
	assert_int(choices.get_child_count()).is_equal(25)
	assert_object(weapon_button).is_not_null()
	assert_object(stats).is_not_null()
	assert_int(stats.focus_mode).is_equal(Control.FOCUS_ALL)
	assert_bool(scroll_bar.max_value > scroll_bar.page).is_true()

	var back_button := frontend.weapon_back_button
	assert_object(viewport.gui_get_focus_owner()).is_same(back_button)
	await _send_ui_action(viewport, &"ui_down")
	assert_object(viewport.gui_get_focus_owner()).is_same(choices.get_child(0))
	await _send_ui_action(viewport, &"ui_right")
	assert_object(viewport.gui_get_focus_owner()).is_same(weapon_button)
	await _send_ui_action(viewport, &"ui_up")
	assert_object(viewport.gui_get_focus_owner()).is_same(stats)

	var initial_scroll := scroll_bar.value
	await _send_ui_action(viewport, &"ui_down")
	assert_float(scroll_bar.value).is_greater(initial_scroll)
	var scrolled_value := scroll_bar.value
	await _send_ui_action(viewport, &"ui_up")
	assert_float(scroll_bar.value).is_less(scrolled_value)

	await _send_ui_action(viewport, &"ui_cancel")
	assert_int(frontend.current_step).is_equal(SelectionStep.Value.WEAPON)
	assert_object(viewport.gui_get_focus_owner()).is_same(weapon_button)
	assert_int(choices.get_child_count()).is_equal(25)


func _first_allowed_weapon_id(character: CharacterDef) -> StringName:
	if not character.starter_weapon_ids.is_empty():
		return character.starter_weapon_ids[0]
	return Content.catalog.get_weapons()[0].get_stable_id(Content.catalog.pack_id)


func _spawn_frontend_in_viewport(viewport_size: Vector2i) -> Array:
	var viewport: SubViewport = auto_free(SubViewport.new())
	viewport.size = viewport_size
	viewport.gui_embed_subwindows = true
	add_child(viewport)
	var frontend := load(FRONTEND_SCENE).instantiate() as FrontendShell
	viewport.add_child(frontend)
	await await_idle_frame()
	await await_idle_frame()
	return [viewport, frontend]


func _first_unlocked_character_button(frontend: FrontendShell) -> Button:
	for child: Node in frontend.character_choices.get_children():
		var button := child as Button
		if button != null and button.has_meta("content_id") and not button.disabled:
			return button
	return null


func _first_locked_character_button(frontend: FrontendShell) -> Button:
	for child: Node in frontend.character_choices.get_children():
		var button := child as Button
		if button != null and button.has_meta(&"content_id") and not bool(
			button.get_meta(&"unlocked", true)
		):
			return button
	return null


func _character_style_snapshot(skin_path: String) -> Dictionary:
	assert_int(Presentation.load_manifest(skin_path)).is_equal(OK)
	var frontend_data: Array = await _spawn_frontend_in_viewport(Vector2i(1280, 720))
	var frontend := frontend_data[1] as FrontendShell
	frontend.begin_new_run(1, 0x5A1E, AimMode.AUTO_TARGET)
	await await_idle_frame()
	var button := _first_unlocked_character_button(frontend)
	assert_object(button).is_not_null()
	if button == null:
		return {}
	var character_id := StringName(button.get_meta(&"content_id"))
	assert_bool(frontend.choose_character(character_id)).is_true()
	await await_idle_frame()
	assert_bool(frontend.go_back()).is_true()
	await await_idle_frame()
	await await_idle_frame()
	var normal := button.get_theme_stylebox(&"normal") as StyleBoxFlat
	var focus := button.get_theme_stylebox(&"focus") as StyleBoxFlat
	var selected := button.get_theme_stylebox(&"pressed") as StyleBoxFlat
	return {
		"accent": Presentation.active_skin.accent_color,
		"normal": normal.border_color,
		"focus": focus.border_color,
		"selected_color": selected.border_color,
		"glow": selected.shadow_color,
		"character_id": frontend.draft.character_id,
		"selected": button.button_pressed,
	}


func _send_ui_action(viewport: Viewport, action: StringName) -> void:
	var pressed := InputEventAction.new()
	pressed.action = action
	pressed.pressed = true
	pressed.strength = 1.0
	viewport.push_input(pressed, true)
	await await_idle_frame()
	var released := InputEventAction.new()
	released.action = action
	released.pressed = false
	viewport.push_input(released, true)
	await await_idle_frame()


func _assert_explicit_focus_neighbors(control: Control) -> void:
	for property_name: StringName in [
		&"focus_neighbor_top",
		&"focus_neighbor_bottom",
		&"focus_neighbor_left",
		&"focus_neighbor_right",
	]:
		var neighbor_path: NodePath = control.get(property_name)
		assert_bool(not neighbor_path.is_empty()).is_true()
		assert_object(control.get_node_or_null(neighbor_path)).is_not_null()


func _assert_rect_inside_viewport(rect: Rect2, viewport_size: Vector2i) -> void:
	assert_bool(rect.position.x >= 0.0).is_true()
	assert_bool(rect.position.y >= 0.0).is_true()
	assert_bool(rect.end.x <= float(viewport_size.x)).is_true()
	assert_bool(rect.end.y <= float(viewport_size.y)).is_true()
