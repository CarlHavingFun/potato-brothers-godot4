extends GdUnitTestSuite

const ACTIONS := "ContentRoot/Body/MenuActions/"
const GROUP_IDS := [
	["weapon.training_blade:weapon/training_blade", "gogobro.preview:weapon/community_tapper"],
	["weapon.training_blaster:weapon/training_blaster", "gogobro.preview:weapon/suppressed_tactical_pistol", "gogobro.preview:weapon/heavy_hand_cannon"],
	["gogobro.preview:weapon/box_submachine_gun", "gogobro.preview:weapon/compact_submachine_gun", "gogobro.preview:weapon/bullpup_pdw", "gogobro.preview:weapon/folding_stock_submachine_gun"],
	["gogobro.preview:weapon/wood_stock_assault_rifle", "gogobro.preview:weapon/suppressed_carbine"],
	["gogobro.preview:weapon/heavy_bolt_sniper"],
]

var _profile_case_app: AppKernel
var _profile_case_originals: Dictionary = {}
var _profile_sequence_originals: Dictionary = {}

func after_test() -> void:
	_dispose_profile_case_app()
	_restore_profile_case_files()
	if _profile_case_originals.is_empty() and not _profile_sequence_originals.is_empty():
		_profile_case_originals = _profile_sequence_originals
		_profile_sequence_originals = {}
		_restore_profile_case_files()

# Catches missing menu destinations and focus escaping a visible page on return.
func test_menu_pages_open_real_data_and_restore_origin_focus() -> void:
	var fixture := await _fixture()
	var app := fixture.app as AppKernel
	var menu := fixture.host.get_child(0) as Control
	app.profile_service.profile_data["completed_runs"] = 7
	app.profile_service.profile_data["best_wave"] = 13
	for name in ["StartButton", "ProfileButton", "CodexButton", "SettingsButton", "ExitButton"]:
		assert_object(menu.get_node_or_null(ACTIONS + name)).is_not_null()
	for name in ["ProfileButton", "CodexButton", "SettingsButton"]:
		var button := menu.get_node_or_null(ACTIONS + name) as Button
		if button == null:
			continue
		button.grab_focus()
		button.pressed.emit()
		await _settle()
		var page := menu.get_node_or_null("MenuPage") as Control
		assert_object(page).is_not_null()
		if page == null:
			continue
		assert_bool(menu.get_node("ContentRoot/Body").visible).is_false()
		assert_bool(page.is_ancestor_of(get_viewport().gui_get_focus_owner())).is_true()
		if name == "ProfileButton":
			assert_str((page.get_node("CompletedRuns") as Label).text).contains("7")
			assert_str((page.get_node("BestWave") as Label).text).contains("13")
		(page.get_node("BackButton") as Button).pressed.emit()
		await _settle()
		assert_bool(menu.has_node("MenuPage")).is_false()
		assert_object(get_viewport().gui_get_focus_owner()).is_same(button)

# Catches fabricated unlock entries, omitted live content, or stale category lists.
func test_codex_browses_actual_snapshot_ids_without_discovering_them() -> void:
	var fixture := await _fixture()
	var app := fixture.app as AppKernel
	var menu := fixture.host.get_child(0) as Control
	var button := menu.get_node_or_null(ACTIONS + "CodexButton") as Button
	assert_object(button).is_not_null()
	if button == null:
		return
	button.pressed.emit()
	await _settle()
	var page := menu.get_node("MenuPage")
	var categories := page.get_node("Categories") as OptionButton
	var entries := page.get_node("Entries") as ItemList
	for index in categories.item_count:
		categories.select(index)
		categories.item_selected.emit(index)
		var kind := StringName(categories.get_item_metadata(index))
		var definitions := app.content_snapshot.all(kind)
		assert_int(entries.item_count).is_equal(definitions.size())
		for entry_index in entries.item_count:
			var content_id := StringName(entries.get_item_metadata(entry_index))
			assert_object(app.content_snapshot.definition(content_id, kind)).is_not_null()
			entries.select(entry_index)
			entries.item_selected.emit(entry_index)
			assert_str((page.get_node("EntryDetail") as Label).text).contains(String(content_id))
	assert_int(app.codex_service.discovered_ids.size()).is_equal(0)

# Catches save-only UI that never applies audio or loses values upon reload.
func test_settings_save_reload_and_apply_actual_audio_and_display_choice() -> void:
	var fixture := await _fixture()
	var app := fixture.app as AppKernel
	var menu := fixture.host.get_child(0) as Control
	var button := menu.get_node_or_null(ACTIONS + "SettingsButton") as Button
	assert_object(button).is_not_null()
	if button == null:
		return
	var old_master := AudioServer.get_bus_volume_db(0)
	button.pressed.emit()
	await _settle()
	var page := menu.get_node("MenuPage")
	(page.get_node("master_volume") as HSlider).value = 0.35
	(page.get_node("music_volume") as HSlider).value = 0.25
	(page.get_node("effects_volume") as HSlider).value = 0.45
	(page.get_node("Fullscreen") as CheckButton).button_pressed = true
	(page.get_node("SaveButton") as Button).pressed.emit()
	var reloaded := GogoSettingsService.new()
	assert_int(reloaded.load_settings()).is_equal(OK)
	assert_float(float(reloaded.values["master_volume"])).is_equal_approx(0.35, 0.001)
	assert_float(float(reloaded.values["music_volume"])).is_equal_approx(0.25, 0.001)
	assert_float(float(reloaded.values["effects_volume"])).is_equal_approx(0.45, 0.001)
	assert_bool(reloaded.values["fullscreen"]).is_true()
	assert_int(app.settings_service.resolved_window_mode()).is_equal(DisplayServer.WINDOW_MODE_FULLSCREEN)
	assert_float(AudioServer.get_bus_volume_db(0)).is_equal_approx(linear_to_db(0.35), 0.001)
	assert_float(app.audio_service.music_player.volume_db).is_equal_approx(linear_to_db(0.25), 0.001)
	assert_float(app.audio_service.effects_player.volume_db).is_equal_approx(linear_to_db(0.45), 0.001)
	if DisplayServer.get_name() != "headless":
		assert_int(DisplayServer.window_get_mode()).is_equal(DisplayServer.WINDOW_MODE_FULLSCREEN)
	AudioServer.set_bus_volume_db(0, old_master)
	(page.get_node("BackButton") as Button).pressed.emit()
	await _settle()
	button.pressed.emit()
	assert_float((menu.get_node("MenuPage/master_volume") as HSlider).value).is_equal_approx(0.35, 0.001)

# Catches two-category grouping, duplicate/omitted IDs and unusable tiny cells.
func test_weapon_five_columns_cover_live_ids_and_keep_grid_dominant() -> void:
	var fixture := await _fixture()
	var app := fixture.app as AppKernel
	app.begin_selection()
	app.selection_draft["character_id"] = NikoContentFactory.CHARACTER_ID
	app.route(FlowRoute.WEAPON_SELECT)
	await _settle()
	var screen := fixture.host.get_child(0) as Control
	var columns := screen.get_node_or_null("WeaponStage/WeaponColumns") as Control
	assert_object(columns).is_not_null()
	if columns == null:
		return
	assert_int(columns.get_child_count()).is_equal(5)
	assert_float(columns.size.y).is_greater_equal(350)
	var seen: Array[String] = []
	for index in 5:
		var column := columns.get_child(index)
		assert_str((column.get_node("Heading") as Label).text).is_equal(["近战", "手枪", "冲锋枪", "步枪", "狙击枪"][index])
		var buttons := column.find_children("WeaponOption*", "Button", true, false)
		var ids: Array[String] = []
		for option: Button in buttons:
			ids.append(String(option.get_meta(&"content_id")))
			seen.append(ids.back())
			assert_bool(Rect2(0, 0, 1280, 720).encloses(option.get_global_rect())).is_true()
			assert_float(option.size.x).is_greater_equal(172)
			assert_float(option.size.y).is_greater_equal(72)
			assert_bool(columns.get_global_rect().encloses(option.get_global_rect())).is_true()
			assert_int((option.get_node("Name") as Label).get_theme_font_size("font_size")).is_greater_equal(18)
			option.grab_focus()
			await _settle()
			assert_str((screen.get_node("WeaponStage/SelectedWeaponDetail/Name") as Label).text).is_equal(option.tooltip_text)
			assert_str(String(app.selection_draft["weapon_id"])).is_empty()
		assert_array(ids).is_equal(GROUP_IDS[index])
	assert_int(seen.size()).is_equal(12)
	var unique := {}
	for id in seen:
		unique[id] = true
	assert_int(unique.size()).is_equal(12)

# Catches a Back control without the common material and inaccessible tiny difficulty.
func test_selection_back_controls_and_difficulty_remain_native_safe() -> void:
	var fixture := await _fixture()
	var app := fixture.app as AppKernel
	app.begin_selection()
	for route in [FlowRoute.CHARACTER_SELECT, FlowRoute.WEAPON_SELECT, FlowRoute.DIFFICULTY_SELECT]:
		app.route(route)
		await _settle()
		var screen := fixture.host.get_child(0) as Control
		var back := screen.get_node("BackButton") as Button
		assert_bool(back.get_theme_stylebox("normal") is StyleBoxTexture).is_true()
		assert_bool(back.get_theme_stylebox("focus") is StyleBoxTexture).is_true()
		assert_str(app.scene_flow.current_route()).is_equal(String(FlowRoute.CHARACTER_SELECT))
		assert_bool((screen.get_node("WeaponStage") as Control).visible).is_false()
		assert_bool((screen.get_node("DifficultyStage") as Control).visible).is_false()

# Catches dead Tab targets, non-progressive Back shortcuts, dropped draft IDs, or wrong focus restoration.
func test_keyboard_traversal_and_escape_keep_the_configuration_draft() -> void:
	var fixture := await _fixture()
	var app := fixture.app as AppKernel
	var host := fixture.host as Control
	var expected := ["StartButton", "ProfileButton", "CodexButton", "SettingsButton", "ExitButton"]
	for index in 5:
		assert_str(String(get_viewport().gui_get_focus_owner().name)).is_equal(expected[index])
		await _key(KEY_TAB)
	await _key(KEY_ENTER)
	assert_str(app.scene_flow.current_route()).is_equal(String(FlowRoute.CHARACTER_SELECT))
	var screen := host.get_child(0) as Control
	assert_bool(screen.has_node("WeaponStage/WeaponColumns")).is_true()
	if not screen.has_node("WeaponStage/WeaponColumns"):
		return
	var niko := screen.get_node("RosterStrip/NikoCell") as Button
	var roster := screen.get_node("RosterStrip") as GridContainer
	var weapon_stage := screen.get_node("WeaponStage") as Control
	var difficulty_stage := screen.get_node("DifficultyStage") as Control
	assert_int(roster.columns).is_equal(6)
	assert_int(roster.get_child_count()).is_equal(24)
	for child in roster.get_children():
		var cell := child as Button
		if cell == niko:
			continue
		assert_bool(cell.disabled).is_true()
		assert_int(cell.focus_mode).is_equal(Control.FOCUS_NONE)
		assert_bool(cell.has_meta(&"content_id")).is_false()
	assert_object(get_viewport().gui_get_focus_owner()).is_same(niko)
	assert_str(String(app.selection_draft["character_id"])).is_empty()
	assert_bool(weapon_stage.visible).is_false()
	assert_bool(difficulty_stage.visible).is_false()
	niko.grab_focus()
	await _key(KEY_ENTER)
	assert_str(String(app.selection_draft["character_id"])).is_equal(String(NikoContentFactory.CHARACTER_ID))
	assert_str(app.scene_flow.current_route()).is_equal(String(FlowRoute.CHARACTER_SELECT))
	assert_bool(weapon_stage.visible).is_true()
	var smg := screen.get_node("WeaponStage/WeaponColumns/Class2/WeaponOption8") as Button
	assert_str(String(app.selection_draft["weapon_id"])).is_empty()
	await _click(smg)
	assert_bool(difficulty_stage.visible).is_true()
	assert_str(String(app.scene_flow.current_route())).is_equal(String(FlowRoute.CHARACTER_SELECT))
	var selected_focus := get_viewport().gui_get_focus_owner() as Control
	assert_object(selected_focus).is_not_null()
	if selected_focus != null:
		assert_bool(selected_focus.is_visible_in_tree()).is_true()
		assert_bool(selected_focus != niko).is_true()
	var before_back := app.selection_draft.duplicate(true)
	await _key(KEY_ESCAPE)
	assert_str(app.scene_flow.current_route()).is_equal(String(FlowRoute.CHARACTER_SELECT))
	assert_dict(app.selection_draft).is_equal(before_back)
	assert_bool(roster.visible).is_false()
	assert_bool(weapon_stage.visible).is_true()
	assert_bool(difficulty_stage.visible).is_false()
	assert_object(get_viewport().gui_get_focus_owner()).is_same(smg)
	await _key(KEY_ESCAPE)
	assert_str(app.scene_flow.current_route()).is_equal(String(FlowRoute.CHARACTER_SELECT))
	assert_dict(app.selection_draft).is_equal(before_back)
	assert_bool(roster.visible).is_true()
	assert_bool(weapon_stage.visible).is_false()
	assert_bool(difficulty_stage.visible).is_false()
	assert_object(get_viewport().gui_get_focus_owner()).is_same(niko)
	await _key(KEY_ESCAPE)
	assert_str(app.scene_flow.current_route()).is_equal(String(FlowRoute.MAIN_MENU))
	assert_dict(app.selection_draft).is_equal(before_back)
	assert_object(app.current_session).is_null()

# Catches route aliases that leave a dead weapon page or reset the persistent draft.
func test_legacy_weapon_route_resolves_to_configuration_without_changing_draft() -> void:
	var fixture := await _fixture()
	var app := fixture.app as AppKernel
	app.begin_selection()
	app.selection_draft["character_id"] = NikoContentFactory.CHARACTER_ID
	app.selection_draft["weapon_id"] = &"gogobro.preview:weapon/heavy_bolt_sniper"
	var before := app.selection_draft.duplicate(true)
	assert_int(app.route(FlowRoute.WEAPON_SELECT)).is_equal(OK)
	await _settle()
	assert_str(app.scene_flow.current_route()).is_equal(String(FlowRoute.CHARACTER_SELECT))
	assert_dict(app.selection_draft).is_equal(before)
	var screen := fixture.host.get_child(0) as Control
	assert_bool(screen.has_node("NikoDetail")).is_true()
	assert_bool(screen.has_node("WeaponStage/WeaponColumns")).is_true()
	var niko := screen.get_node("RosterStrip/NikoCell") as Button
	assert_bool((screen.get_node("RosterStrip") as Control).visible).is_false()
	assert_bool(niko.visible).is_false()
	var focus := get_viewport().gui_get_focus_owner() as Control
	assert_object(focus).is_not_null()
	if focus != null:
		assert_bool(focus.is_visible_in_tree()).is_true()
		assert_int(focus.focus_mode).is_not_equal(Control.FOCUS_NONE)
		assert_bool(focus != niko).is_true()
		assert_str(String(focus.get_meta(&"content_id", &""))).is_equal(
			"gogobro.preview:weapon/heavy_bolt_sniper"
		)
	assert_object(app.current_session).is_null()
	var back := screen.get_node("BackButton") as Button
	await _click(back)
	assert_str(app.scene_flow.current_route()).is_equal(String(FlowRoute.CHARACTER_SELECT))
	assert_dict(app.selection_draft).is_equal(before)
	assert_bool((screen.get_node("RosterStrip") as Control).visible).is_false()
	assert_bool((screen.get_node("WeaponStage") as Control).visible).is_true()
	assert_bool((screen.get_node("DifficultyStage") as Control).visible).is_false()
	assert_object(get_viewport().gui_get_focus_owner()).is_same(focus)
	await _click(back)
	assert_str(app.scene_flow.current_route()).is_equal(String(FlowRoute.CHARACTER_SELECT))
	assert_dict(app.selection_draft).is_equal(before)
	assert_bool((screen.get_node("RosterStrip") as Control).visible).is_true()
	assert_object(get_viewport().gui_get_focus_owner()).is_same(niko)
	await _click(back)
	assert_str(app.scene_flow.current_route()).is_equal(String(FlowRoute.MAIN_MENU))
	assert_dict(app.selection_draft).is_equal(before)

# Catches early/duplicate session creation and loss of the selected AWP on Back.
func test_configuration_return_restores_pair_and_difficulty_creates_exactly_one_session() -> void:
	var fixture := await _fixture()
	var app := fixture.app as AppKernel
	var sessions: Array[GameSession] = []
	app.session_created.connect(func(session: GameSession) -> void: sessions.append(session))
	app.begin_selection()
	app.route(FlowRoute.CHARACTER_SELECT)
	await _settle()
	var screen := fixture.host.get_child(0) as Control
	assert_bool(screen.has_node("WeaponStage/WeaponColumns")).is_true()
	if not screen.has_node("WeaponStage/WeaponColumns"):
		return
	await _click(screen.get_node("RosterStrip/NikoCell") as Button)
	await _click(screen.get_node("WeaponStage/WeaponColumns/Class4/WeaponOption11") as Button)
	var before := app.selection_draft.duplicate(true)
	var back := screen.get_node("BackButton") as Button
	await _click(back)
	assert_str(app.scene_flow.current_route()).is_equal(String(FlowRoute.CHARACTER_SELECT))
	assert_bool((screen.get_node("DifficultyStage") as Control).visible).is_false()
	assert_object(get_viewport().gui_get_focus_owner()).is_same(
		screen.get_node("WeaponStage/WeaponColumns/Class4/WeaponOption11") as Button
	)
	await _click(back)
	assert_str(app.scene_flow.current_route()).is_equal(String(FlowRoute.CHARACTER_SELECT))
	assert_bool((screen.get_node("RosterStrip") as Control).visible).is_true()
	assert_object(get_viewport().gui_get_focus_owner()).is_same(
		screen.get_node("RosterStrip/NikoCell") as Button
	)
	await _click(back)
	assert_dict(app.selection_draft).is_equal(before)
	assert_object(app.current_session).is_null()
	assert_str(app.scene_flow.current_route()).is_equal(String(FlowRoute.MAIN_MENU))
	app.route(FlowRoute.CHARACTER_SELECT)
	await _settle()
	await _click(fixture.host.get_child(0).get_node("DifficultyStage/DifficultyStrip/DifficultyOption0") as Button)
	assert_int(sessions.size()).is_equal(1)
	assert_object(app.current_session).is_same(sessions[0])
	assert_str(app.scene_flow.current_route()).is_equal(String(FlowRoute.COMBAT))
	assert_array(app.current_session.run_state.player().weapon_ids).is_equal([&"gogobro.preview:weapon/heavy_bolt_sniper"])

# Catches confirmation trusting a stale enabled button or bypassing allows_weapon.
func test_configuration_rejects_corrupt_and_unauthorized_drafts_without_side_effects() -> void:
	var fixture := await _fixture()
	var app := fixture.app as AppKernel
	var packs := ValidationContentFactory.create_packs(true)
	var forbidden := GogoWeaponDefinition.new()
	forbidden.content_id = &"weapon.training_blaster:weapon/test_forbidden"
	forbidden.display_name = "Unauthorized test weapon"
	forbidden.tags.assign([&"test_forbidden"])
	for pack in packs:
		if pack.pack_id == &"weapon.training_blaster":
			pack.definitions.append(forbidden)
		if pack.pack_id == &"character.niko":
			(pack.definitions[0] as CharacterDefinition).allowed_weapon_tags.assign([&"ranged", &"melee"])
	app.content_snapshot = GogoContentRegistry.new().build_snapshot(packs)
	assert_object(app.content_snapshot).is_not_null()
	assert_object(app.content_snapshot.definition(forbidden.content_id, &"weapon")).is_not_null()
	var niko := app.content_snapshot.definition(NikoContentFactory.CHARACTER_ID, &"character") as CharacterDefinition
	assert_bool(niko.allows_weapon(forbidden)).is_false()
	app.begin_selection()
	app.selection_draft["character_id"] = NikoContentFactory.CHARACTER_ID
	app.selection_draft["weapon_id"] = &"gogobro.preview:weapon/heavy_bolt_sniper"
	app.route(FlowRoute.CHARACTER_SELECT)
	await _settle()
	var screen := fixture.host.get_child(0) as Control
	assert_bool(screen.has_method("_select_difficulty_and_start")).is_true()
	if not screen.has_method("_select_difficulty_and_start"):
		return
	for bad_id in [&"missing:weapon/not_real", forbidden.content_id]:
		app.selection_draft["weapon_id"] = bad_id
		screen.call("_select_difficulty_and_start", ValidationContentFactory.DIFFICULTY_ID)
		await _settle()
		assert_str(app.scene_flow.current_route()).is_equal(String(FlowRoute.CHARACTER_SELECT))
		assert_object(app.current_session).is_null()
	screen.call("_sync_selection")
	assert_bool((screen.get_node("DifficultyStage") as Control).visible).is_false()
	var unchanged := app.selection_draft.duplicate(true)
	screen.call("_select_character", &"missing:character/not_shown")
	screen.call("_select_weapon", forbidden.content_id)
	screen.call("_select_weapon", &"missing:weapon/not_shown")
	assert_dict(app.selection_draft).is_equal(unchanged)

# A discarded, nonterminal session must not become a persisted completed run.
func test_profile_page_ignores_nonterminal_close() -> void:
	await _run_profile_case(false)

# Catch missing terminal-signal persistence and a second settlement on close.
func test_profile_page_reads_persisted_settlement_records() -> void:
	await _run_profile_case(true)

# One engine/user:// must support the reverse order and a repeated positive.
func test_profile_cases_restore_isolation_in_reverse_order_and_on_repeat() -> void:
	var paths := _checked_profile_case_paths()
	if paths.is_empty():
		return
	var original_files := _snapshot_profile_case_files(paths)
	if original_files.is_empty():
		return
	_profile_sequence_originals = original_files
	for terminal in [true, false, true, true]:
		print("ORACLE_PROFILE_SEQUENCE terminal=", terminal, " pid=", OS.get_process_id())
		await _run_profile_case(terminal)
		assert_dict(_snapshot_profile_case_files(paths)).is_equal(original_files)
	# A real completed run stands in for another case's pre-existing file.
	# The inner cases must restore those exact bytes, not erase or increment it.
	if not _begin_profile_case():
		return
	await _check_terminal_profile_case()
	_dispose_profile_case_app()
	# The outer sequence snapshot now owns restoration of the original baseline.
	_profile_case_originals.clear()
	var retained_files := _snapshot_profile_case_files(paths)
	for terminal in [false, true]:
		await _run_profile_case(terminal)
		assert_dict(_snapshot_profile_case_files(paths)).is_equal(retained_files)
		print("ORACLE_PROFILE_SEQUENCE preserved_existing_terminal=true terminal=", terminal, " pid=", OS.get_process_id())
	# Exercise the actual GdUnit after_test hook with a still-armed transaction,
	# as also happens if a body returns early or its coroutine is aborted.
	if not _begin_profile_case():
		return
	await _check_terminal_profile_case()
	print("ORACLE_PROFILE_SEQUENCE pending_after_test=true pid=", OS.get_process_id())

func _run_profile_case(terminal: bool) -> void:
	if not _begin_profile_case():
		_restore_profile_case_files()
		return
	if terminal:
		await _check_terminal_profile_case()
	else:
		await _check_nonterminal_profile_case()
	_dispose_profile_case_app()
	_restore_profile_case_files()

func _dispose_profile_case_app() -> void:
	if is_instance_valid(_profile_case_app):
		_profile_case_app.close_session(false)
		_profile_case_app.free()
	_profile_case_app = null

func _checked_profile_case_paths() -> PackedStringArray:
	var user_root := _profile_path(OS.get_user_data_dir())
	var roaming := _profile_path(OS.get_environment("APPDATA"))
	var local := _profile_path(OS.get_environment("LOCALAPPDATA"))
	var temp := _profile_path(OS.get_environment("TEMP"))
	var runner_root := roaming.get_base_dir()
	var root_pattern := RegEx.new()
	root_pattern.compile("^gogobro-task6-[0-9a-f]{32}$")
	var valid := not temp.is_empty() and temp.is_absolute_path() \
		and user_root == _profile_path(OS.get_environment("GOGOBRO_TEST_EXPECTED_USER_DATA_DIR")) \
		and roaming == _profile_path(OS.get_environment("GOGOBRO_TEST_EXPECTED_APPDATA")) \
		and local == _profile_path(OS.get_environment("GOGOBRO_TEST_EXPECTED_LOCALAPPDATA")) \
		and runner_root.get_base_dir() == temp \
		and root_pattern.search(runner_root.get_file()) != null \
		and roaming == runner_root.path_join("Roaming") \
		and local == runner_root.path_join("Local") \
		and user_root == roaming.path_join("GOGOBRO") \
		and not runner_root.begins_with(_profile_path(ProjectSettings.globalize_path("res://")).trim_suffix("/") + "/")
	assert_bool(valid).override_failure_message("Profile fixture requires the current external task6 runner user directory").is_true()
	if not valid:
		return PackedStringArray()
	# Match this live runner receipt, not merely a plausible GUID-shaped old root.
	# The unchanged runner creates invocation before launch and completion on exit.
	var arguments := OS.get_cmdline_args()
	var report_index := arguments.find("-rd")
	if report_index < 0 or report_index + 1 >= arguments.size():
		assert_bool(false).override_failure_message("Missing live task6 report argument").is_true()
		return PackedStringArray()
	var report_dir := _profile_path(arguments[report_index + 1]).get_base_dir()
	valid = report_dir.begins_with("res://reports/playtest-feedback-v1/task6/") \
		and not FileAccess.file_exists(report_dir.path_join("completion.json"))
	var invocation: Variant = JSON.parse_string(FileAccess.get_file_as_string(report_dir.path_join("invocation.json"))) if valid else null
	valid = valid and invocation is Dictionary
	if valid:
		valid = _profile_path(str(invocation.get("profile_root", ""))) == runner_root \
			and _profile_path(str(invocation.get("appdata", ""))) == roaming \
			and _profile_path(str(invocation.get("localappdata", ""))) == local \
			and _profile_path(str(invocation.get("expected_user_data_dir", ""))) == user_root
	assert_bool(valid).override_failure_message("Profile fixture refuses missing, completed, or different-run receipts").is_true()
	if not valid:
		return PackedStringArray()
	var paths := PackedStringArray()
	for path in [ProfileService.PROFILE_PATH, ProfileService.TEMP_PATH, ProfileService.BACKUP_PATH]:
		var absolute := _profile_path(ProjectSettings.globalize_path(path))
		valid = absolute == user_root.path_join("GOGOBRO").path_join(String(path).get_file())
		assert_bool(valid).is_true()
		if not valid:
			return PackedStringArray()
		paths.append(absolute)
	return paths

func _profile_path(path: String) -> String:
	return path.replace("\\", "/").simplify_path().trim_suffix("/")

func _snapshot_profile_case_files(paths: PackedStringArray) -> Dictionary:
	var snapshot := {}
	for path in paths:
		var is_directory := DirAccess.dir_exists_absolute(path)
		assert_bool(is_directory).override_failure_message("Refusing directory at exact profile fixture path: " + path).is_false()
		if is_directory:
			return {}
		var exists := FileAccess.file_exists(path)
		var bytes := PackedByteArray()
		if exists:
			var file := FileAccess.open(path, FileAccess.READ)
			assert_object(file).is_not_null()
			if file == null:
				return {}
			bytes = file.get_buffer(file.get_length())
			var error := file.get_error()
			file.close()
			assert_bool(error == OK or error == ERR_FILE_EOF).is_true()
			if error != OK and error != ERR_FILE_EOF:
				return {}
		snapshot[path] = {"exists": exists, "bytes": bytes}
	return snapshot

func _begin_profile_case() -> bool:
	assert_bool(_profile_case_originals.is_empty()).override_failure_message("Previous profile transaction must restore before the next case").is_true()
	if not _profile_case_originals.is_empty():
		return false
	var paths := _checked_profile_case_paths()
	if paths.is_empty():
		return false
	var originals := _snapshot_profile_case_files(paths)
	if originals.size() != 3:
		return false
	# Arm only after all original bytes are captured, before the first mutation.
	_profile_case_originals = originals
	return _remove_profile_case_files(paths)

func _remove_profile_case_files(paths: PackedStringArray) -> bool:
	var success := true
	for path in paths:
		if DirAccess.dir_exists_absolute(path):
			assert_bool(false).override_failure_message("Never remove a profile-path directory: " + path).is_true()
			success = false
		elif FileAccess.file_exists(path):
			var error := DirAccess.remove_absolute(path)
			assert_int(error).is_equal(OK)
			success = success and error == OK
	return success

func _restore_profile_case_files() -> void:
	if _profile_case_originals.is_empty():
		return
	var paths := _checked_profile_case_paths()
	if paths.size() != 3:
		return
	for path in paths:
		if not _profile_case_originals.has(path):
			assert_bool(false).override_failure_message("Restore path changed during profile transaction").is_true()
			return
	var success := _remove_profile_case_files(paths)
	for path in paths:
		var original: Dictionary = _profile_case_originals[path]
		if not original.exists:
			continue
		var file := FileAccess.open(path, FileAccess.WRITE)
		assert_object(file).is_not_null()
		if file == null:
			success = false
			continue
		file.store_buffer(original.bytes)
		file.flush()
		var error := file.get_error()
		file.close()
		assert_int(error).is_equal(OK)
		success = success and error == OK
	var restored := _snapshot_profile_case_files(paths)
	assert_dict(restored).is_equal(_profile_case_originals)
	if success and restored == _profile_case_originals:
		_profile_case_originals.clear()
		print("ORACLE_PROFILE_TEARDOWN restored_original_bytes=true pid=", OS.get_process_id())

func _check_nonterminal_profile_case() -> void:
	var fixture := await _fixture(true)
	var app := fixture.app as AppKernel
	assert_int(app.profile_service.load_profile(app.content_snapshot)).is_equal(OK)
	assert_int(app.profile_service.profile_data.completed_runs).is_zero()
	assert_int(app.profile_service.profile_data.best_wave).is_zero()
	assert_bool(FileAccess.file_exists(ProfileService.PROFILE_PATH)).is_false()
	app.begin_selection()
	app.selection_draft["character_id"] = NikoContentFactory.CHARACTER_ID
	app.selection_draft["weapon_id"] = ValidationContentFactory.RANGED_ID
	assert_int(app.create_session_from_draft()).is_equal(OK)
	app.current_session.run_state.current_wave = 9
	assert_bool(app.current_session.run_state.ended).is_false()
	app.close_session(true)
	assert_object(app.current_session).is_null()
	assert_int(app.profile_service.profile_data.completed_runs).is_zero()
	assert_int(app.profile_service.profile_data.best_wave).is_zero()
	for path in [ProfileService.PROFILE_PATH, ProfileService.TEMP_PATH, ProfileService.BACKUP_PATH]:
		assert_bool(FileAccess.file_exists(path)).is_false()
	app.profile_service = ProfileService.new()
	assert_int(app.profile_service.load_profile(app.content_snapshot)).is_equal(OK)
	assert_int(app.profile_service.profile_data.completed_runs).is_zero()
	assert_int(app.profile_service.profile_data.best_wave).is_zero()
	var menu := fixture.host.get_child(0) as Control
	var button := menu.get_node_or_null(ACTIONS + "ProfileButton") as Button
	assert_object(button).is_not_null()
	if button == null:
		return
	button.pressed.emit()
	assert_str((menu.get_node("MenuPage/CompletedRuns") as Label).text).is_equal("已记录局数  0")
	assert_str((menu.get_node("MenuPage/BestWave") as Label).text).is_equal("最高波次  0")
	print("ORACLE_PROFILE_NONTERMINAL wave=9 completed_runs=", app.profile_service.profile_data.completed_runs, " best_wave=", app.profile_service.profile_data.best_wave, " profile_exists=", FileAccess.file_exists(ProfileService.PROFILE_PATH))

func _check_terminal_profile_case() -> void:
	var fixture := await _fixture(true)
	var app := fixture.app as AppKernel
	assert_int(app.profile_service.load_profile(app.content_snapshot)).is_equal(OK)
	assert_int(app.profile_service.profile_data.completed_runs).is_zero()
	assert_int(app.profile_service.profile_data.best_wave).is_zero()
	assert_bool(FileAccess.file_exists(ProfileService.PROFILE_PATH)).is_false()
	app.begin_selection()
	app.selection_draft["character_id"] = NikoContentFactory.CHARACTER_ID
	app.selection_draft["weapon_id"] = ValidationContentFactory.RANGED_ID
	assert_int(app.create_session_from_draft()).is_equal(OK)
	var session := app.current_session
	var final_wave := session.run_state.total_waves
	assert_int(final_wave).is_greater(0)
	session.run_state.current_wave = final_wave
	assert_bool(session.run_state.ended).is_false()
	assert_bool(session.run_state.endless).is_false()
	assert_float(session.run_state.player().current_health).is_greater(0.0)
	assert_int(session.run_state.pending_upgrade_count).is_zero()
	assert_int(session.transition(&"shop")).is_equal(OK)
	assert_bool(session.is_final_shop()).is_true()
	var terminal_events: Array[bool] = []
	session.run_ended.connect(func(victory: bool): terminal_events.append(victory))
	assert_bool(session.finish_normal_run()).is_true()
	assert_array(terminal_events).is_equal([true])
	assert_bool(session.run_state.ended).is_true()
	assert_bool(session.run_state.won).is_true()
	assert_str(String(session.run_state.phase)).is_equal("settlement")
	# Check before close: only the real run_ended -> AppKernel path has run.
	assert_str(app.profile_service.last_error).is_empty()
	assert_int(app.profile_service.profile_data.completed_runs).is_equal(1)
	assert_int(app.profile_service.profile_data.best_wave).is_equal(final_wave)
	assert_bool(FileAccess.file_exists(ProfileService.PROFILE_PATH)).is_true()
	var terminal_file_hash := FileAccess.get_sha256(ProfileService.PROFILE_PATH)
	assert_bool(session.finish_normal_run()).is_false()
	app.close_session(true)
	assert_object(app.current_session).is_null()
	assert_array(terminal_events).is_equal([true])
	assert_int(app.profile_service.profile_data.completed_runs).is_equal(1)
	assert_str(FileAccess.get_sha256(ProfileService.PROFILE_PATH)).is_equal(terminal_file_hash)
	app.profile_service = ProfileService.new()
	assert_int(app.profile_service.load_profile(app.content_snapshot)).is_equal(OK)
	assert_int(app.profile_service.profile_data.completed_runs).is_equal(1)
	assert_int(app.profile_service.profile_data.best_wave).is_equal(final_wave)
	var menu := fixture.host.get_child(0) as Control
	var button := menu.get_node_or_null(ACTIONS + "ProfileButton") as Button
	assert_object(button).is_not_null()
	if button == null:
		return
	button.pressed.emit()
	assert_str((menu.get_node("MenuPage/CompletedRuns") as Label).text).is_equal("已记录局数  1")
	assert_str((menu.get_node("MenuPage/BestWave") as Label).text).is_equal("最高波次  %d" % final_wave)
	print("ORACLE_PROFILE_TERMINAL completed_runs=", app.profile_service.profile_data.completed_runs, " final_wave=", final_wave, " run_ended_count=", terminal_events.size(), " unchanged_close_sha256=", terminal_file_hash)

func test_settings_keyboard_controls_stay_on_page_and_escape_restores_entry() -> void:
	var fixture := await _fixture()
	var menu := fixture.host.get_child(0) as Control
	var button := menu.get_node(ACTIONS + "SettingsButton") as Button
	button.pressed.emit()
	await _settle()
	var slider := menu.get_node("MenuPage/master_volume") as HSlider
	slider.value = 0.5
	assert_object(get_viewport().gui_get_focus_owner()).is_same(slider)
	await _key(KEY_RIGHT)
	assert_float(slider.value).is_equal_approx(0.55, 0.001)
	var expected := ["music_volume", "effects_volume", "Fullscreen", "SaveButton", "BackButton", "master_volume"]
	for name in expected:
		await _key(KEY_TAB)
		assert_str(String(get_viewport().gui_get_focus_owner().name)).is_equal(name)
	await _key(KEY_ESCAPE)
	assert_bool(menu.has_node("MenuPage")).is_false()
	assert_object(get_viewport().gui_get_focus_owner()).is_same(button)

func test_native_labels_and_buttons_fit_their_visible_panels() -> void:
	var fixture := await _fixture()
	var app := fixture.app as AppKernel
	app.begin_selection()
	for route in [FlowRoute.MAIN_MENU, FlowRoute.CHARACTER_SELECT, FlowRoute.WEAPON_SELECT, FlowRoute.DIFFICULTY_SELECT]:
		app.route(route)
		await _settle()
		var screen := fixture.host.get_child(0) as Control
		for button: Button in screen.find_children("*", "Button", true, false):
			assert_bool(Rect2(0, 0, 1280, 720).encloses(button.get_global_rect())).is_true()
		for label: Label in screen.find_children("*", "Label", true, false):
			if label.text.is_empty() or not label.is_visible_in_tree():
				continue
			assert_bool(Rect2(0, 0, 1280, 720).encloses(label.get_global_rect())).is_true()
			var parent := label.get_parent() as Control
			assert_bool(parent.get_global_rect().encloses(label.get_global_rect())).override_failure_message("Label escapes parent: " + String(label.get_path())).is_true()
			assert_float(float(label.get_line_height() * label.get_line_count())).is_less_equal(label.size.y)

func test_menu_and_selection_use_reviewed_versioned_background_with_light_veil() -> void:
	var fixture := await _fixture()
	var app := fixture.app as AppKernel
	app.begin_selection()
	for route in [FlowRoute.MAIN_MENU, FlowRoute.CHARACTER_SELECT, FlowRoute.WEAPON_SELECT, FlowRoute.DIFFICULTY_SELECT]:
		app.route(route)
		await _settle()
		var screen := fixture.host.get_child(0) as Control
		var background := screen.get_node("StaticMenuBackground") as TextureRect
		assert_object(background.texture).is_not_null()
		if background.texture != null:
			assert_str(background.texture.resource_path).is_equal("res://game/assets/ui/hud_v2/menu_background_v2.png")
		assert_int(background.stretch_mode).is_equal(TextureRect.STRETCH_KEEP_ASPECT_COVERED)
		assert_float((screen.get_node("ReadabilityVeil") as ColorRect).color.a).is_less_equal(0.20)

# Catches the old separated pages and selection clicks that navigate or only preview.
func test_configuration_clicks_commit_one_draft_without_advancing() -> void:
	var f := await _fixture()
	var app := f.app as AppKernel
	app.begin_selection()
	app.route(FlowRoute.CHARACTER_SELECT)
	await _settle()
	var screen := f.host.get_child(0) as Control
	assert_object(screen.get_node_or_null("WeaponStage/WeaponColumns")).is_not_null()
	if not screen.has_node("WeaponStage/WeaponColumns"):
		return
	assert_bool((screen.get_node("WeaponStage") as Control).visible).is_false()
	assert_bool((screen.get_node("DifficultyStage") as Control).visible).is_false()
	await _click(screen.get_node("RosterStrip/NikoCell") as Button)
	assert_str(String(app.selection_draft["character_id"])).is_equal(String(NikoContentFactory.CHARACTER_ID))
	assert_bool((screen.get_node("WeaponStage") as Control).visible).is_true()
	await _click(screen.get_node("WeaponStage/WeaponColumns/Class4/WeaponOption11") as Button)
	assert_str(String(app.selection_draft["weapon_id"])).is_equal("gogobro.preview:weapon/heavy_bolt_sniper")
	assert_str(String(app.scene_flow.current_route())).is_equal(String(FlowRoute.CHARACTER_SELECT))
	assert_object(app.current_session).is_null()
	assert_bool((screen.get_node("DifficultyStage") as Control).visible).is_true()
	assert_str(String(app.scene_flow.current_route())).is_equal(String(FlowRoute.CHARACTER_SELECT))
	assert_object(app.current_session).is_null()

func _click(button: Button) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.position = button.get_global_rect().get_center()
	down.pressed = true
	get_viewport().push_input(down)
	await _settle()
	var up := down.duplicate() as InputEventMouseButton
	up.pressed = false
	get_viewport().push_input(up)
	await _settle()

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	get_viewport().push_input(event)
	await _settle()
	event = event.duplicate() as InputEventKey
	event.pressed = false
	get_viewport().push_input(event)
	await _settle()

func _fixture(profile_case: bool = false) -> Dictionary:
	var app := auto_free(AppKernel.new()) as AppKernel
	if profile_case:
		_profile_case_app = app
	app.add_to_group(&"gogobro_app")
	app.content_snapshot = GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs(true))
	add_child(app)
	var host := Control.new()
	host.size = Vector2(1280, 720)
	app.add_child(host)
	var flow := SceneFlow.new()
	app.add_child(flow)
	var audio := GogoAudioService.new()
	app.add_child(audio)
	app.configure(flow, audio)
	var combat_node := Control.new()
	combat_node.name = "CombatStub"
	var combat_scene := PackedScene.new()
	assert_int(combat_scene.pack(combat_node)).is_equal(OK)
	combat_node.free()
	flow.configure(host, {
		FlowRoute.MAIN_MENU: preload("res://game/ui/main_menu_screen.tscn"),
		FlowRoute.CHARACTER_SELECT: preload("res://game/ui/character_select_screen.tscn"),
		FlowRoute.WEAPON_SELECT: preload("res://game/ui/weapon_select_screen.tscn"),
		FlowRoute.DIFFICULTY_SELECT: preload("res://game/ui/difficulty_select_screen.tscn"),
		FlowRoute.COMBAT: combat_scene,
	})
	app.route(FlowRoute.MAIN_MENU)
	await _settle()
	return {"app": app, "host": host}

func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
