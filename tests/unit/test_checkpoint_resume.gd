extends GdUnitTestSuite

const APP_SCENE := preload("res://game/app/app_root.tscn")
const PROFILE_PATHS := [
	ProfileService.PROFILE_PATH,
	ProfileService.TEMP_PATH,
	ProfileService.BACKUP_PATH,
]


func before_test() -> void:
	_assert_isolated_profile_root()
	_remove_synthetic_profile()


func after_test() -> void:
	_remove_synthetic_profile()


func test_schema3_preserves_rng_and_schema2_uses_seed_fallback() -> void:
	var content := _content()
	var session := _session(content, 9007199254740993)
	session.rng.randi()
	session.rng.randf()
	assert_int(session.prepare_checkpoint()).is_equal(OK)
	var schema3 := session.run_state.to_dictionary()
	assert_int(schema3.schema_version).is_equal(3)
	assert_int(typeof(schema3.rng_state)).is_equal(TYPE_INT)
	assert_int(schema3.rng_state).is_equal(session.rng.state)
	var parsed3 := GogoRunState.parse_dictionary(schema3, content)
	assert_int(parsed3.error).is_equal(OK)
	assert_int(parsed3.state.rng_state).is_equal(session.rng.state)

	var schema2 := schema3.duplicate(true)
	schema2.schema_version = 2
	schema2.erase("rng_state")
	var parsed2 := GogoRunState.parse_dictionary(schema2, content)
	assert_int(parsed2.error).is_equal(OK)
	var fallback := RandomNumberGenerator.new()
	fallback.seed = int(schema2.run_seed)
	assert_int(parsed2.state.schema_version).is_equal(3)
	assert_int(parsed2.state.rng_state).is_equal(fallback.state)
	var resumed := GameSession.new()
	assert_int(resumed.restore_from_checkpoint(parsed2.state, content)).is_equal(OK)
	assert_int(resumed.rng.state).is_equal(fallback.state)


func test_new_run_replaces_stale_checkpoint_and_second_app_resumes_exact_live_combat() -> void:
	var stale_writer := ProfileService.new()
	var content := _content()
	assert_int(stale_writer.load_profile(content)).is_equal(OK)
	var stale := _session(content, 41)
	stale.run_state.current_wave = 7
	assert_int(stale.prepare_checkpoint()).is_equal(OK)
	assert_int(stale_writer.save_checkpoint(stale.run_state)).is_equal(OK)

	var app_a := await _app()
	assert_bool(app_a.boot_result.is_ok()).is_true()
	app_a.begin_selection()
	app_a.selection_draft.seed = 6202122
	app_a.selection_draft.character_id = ValidationContentFactory.CHARACTER_ID
	app_a.selection_draft.weapon_id = ValidationContentFactory.RANGED_ID
	assert_int(app_a.create_session_from_draft()).is_equal(OK)
	assert_int(app_a.current_session.run_state.current_wave).is_equal(1)
	assert_int(app_a.profile_service.profile_data.run_checkpoint.current_wave).is_equal(1)
	app_a.current_session.rng.randi()
	assert_int(app_a.save_checkpoint()).is_equal(OK)
	var disk_reader := ProfileService.new()
	assert_int(disk_reader.load_profile(app_a.content_snapshot)).is_equal(OK)
	var expected: Dictionary = disk_reader.parse_checkpoint()
	assert_int(expected.error).is_equal(OK)
	var expected_state: Dictionary = expected.state.to_dictionary()
	var expected_rng := expected.state.rng_state as int
	var profile_hash := FileAccess.get_sha256(ProfileService.PROFILE_PATH)
	await _dispose_app(app_a)

	var app_b := await _app()
	assert_bool(app_b.boot_result.is_ok()).is_true()
	assert_object(app_b.current_session).is_null()
	var continue_button := app_b.get_node_or_null(
		"SceneHost/MainMenuScreen/ContentRoot/Body/MenuActions/ContinueButton"
	) as Button
	assert_object(continue_button).is_not_null()
	if continue_button == null:
		await _dispose_app(app_b)
		return
	var actions := continue_button.get_parent()
	assert_str(String(actions.get_child(0).name)).is_equal("ContinueButton")
	assert_str(String(actions.get_child(1).name)).is_equal("StartButton")
	continue_button.pressed.emit()
	assert_object(app_b.current_session).is_not_null()
	assert_str(String(app_b.scene_flow.current_route())).is_equal(String(FlowRoute.COMBAT))
	assert_int(app_b.current_session.rng.state).is_equal(expected_rng)
	_assert_variant_exact(expected_state, app_b.current_session.run_state.to_dictionary(), "$")
	var combat := app_b.get_node_or_null("SceneHost/CombatScreen")
	assert_object(combat).is_not_null()
	if combat != null:
		var world := combat.get("world") as CombatWorld
		assert_object(world).is_not_null()
		if world != null:
			assert_bool(world.running).is_true()
			assert_int(world.wave_runtime.wave.wave_number).is_equal(1)
	assert_str(FileAccess.get_sha256(ProfileService.PROFILE_PATH)).is_equal(profile_hash)
	assert_bool(FileAccess.file_exists(ProfileService.TEMP_PATH)).is_false()
	assert_bool(FileAccess.file_exists(ProfileService.BACKUP_PATH)).is_false()
	await _dispose_app(app_b)


func test_resume_routes_all_safe_phases_and_publishes_exactly_once() -> void:
	for spec in [[&"combat", FlowRoute.COMBAT], [&"upgrade", FlowRoute.UPGRADE], [&"shop", FlowRoute.SHOP]]:
		_remove_synthetic_profile()
		var content := _content()
		var writer := ProfileService.new()
		assert_int(writer.load_profile(content)).is_equal(OK)
		var session := _session(content, 73)
		session.run_state.phase = spec[0]
		session.run_state.pending_upgrade_count = 1 if spec[0] == &"upgrade" else 0
		assert_int(session.prepare_checkpoint()).is_equal(OK)
		assert_int(writer.save_checkpoint(session.run_state)).is_equal(OK)
		var app := await _app()
		assert_bool(app.boot_result.is_ok()).is_true()
		assert_bool(app.can_resume_checkpoint()).is_true()
		var continue_button := app.get_node_or_null(
			"SceneHost/MainMenuScreen/ContentRoot/Body/MenuActions/ContinueButton"
		) as Button
		assert_object(continue_button).is_not_null()
		if continue_button == null:
			await _dispose_app(app)
			continue
		assert_str(continue_button.text).is_equal("继续游戏 · 从最近波次边界恢复")
		var parsed: Dictionary = app.profile_service.parse_checkpoint()
		assert_int(parsed.error).is_equal(OK)
		var expected_state: Dictionary = parsed.state.to_dictionary()
		var expected_rng: int = parsed.state.rng_state
		var created := [0]
		var routed := [0]
		var state_at_signal := [{}]
		var rng_at_signal := [0]
		var route_at_signal := [&""]
		app.scene_flow.route_changed.connect(func(_previous: StringName, _current: StringName) -> void:
			routed[0] += 1
		)
		app.session_created.connect(func(resumed: GameSession) -> void:
			created[0] += 1
			state_at_signal[0] = resumed.run_state.to_dictionary()
			rng_at_signal[0] = resumed.rng.state
			route_at_signal[0] = app.scene_flow.current_route()
		)
		assert_int(app.resume_checkpoint()).is_equal(OK)
		assert_object(app.current_session).is_not_null()
		assert_str(String(app.scene_flow.current_route())).is_equal(String(spec[1]))
		assert_int(created[0]).is_equal(1)
		assert_int(routed[0]).is_equal(1)
		assert_str(String(route_at_signal[0])).is_equal(String(FlowRoute.MAIN_MENU))
		assert_int(rng_at_signal[0]).is_equal(expected_rng)
		_assert_variant_exact(expected_state, state_at_signal[0], "$signal")
		assert_int(app.resume_checkpoint()).is_equal(ERR_ALREADY_IN_USE)
		assert_int(created[0]).is_equal(1)
		assert_int(routed[0]).is_equal(1)
		await _dispose_app(app)


func test_nonresumable_checkpoints_do_not_publish_continue_or_session() -> void:
	for defect in [&"selection", &"ended", &"dead"]:
		_remove_synthetic_profile()
		var content := _content()
		var writer := ProfileService.new()
		assert_int(writer.load_profile(content)).is_equal(OK)
		var session := _session(content, 73)
		match defect:
			&"selection": session.run_state.phase = &"selection"
			&"ended":
				session.run_state.phase = &"settlement"
				session.run_state.ended = true
			&"dead": session.run_state.player().current_health = 0.0
		assert_int(session.prepare_checkpoint()).is_equal(OK)
		assert_int(writer.save_checkpoint(session.run_state)).is_equal(OK)
		var app := await _app()
		assert_bool(app.boot_result.is_ok()).is_true()
		assert_bool(app.can_resume_checkpoint()).is_false()
		assert_object(app.get_node_or_null(
			"SceneHost/MainMenuScreen/ContentRoot/Body/MenuActions/ContinueButton"
		)).is_null()
		var created := [0]
		app.session_created.connect(func(_session: GameSession) -> void: created[0] += 1)
		assert_int(app.resume_checkpoint()).is_not_equal(OK)
		assert_object(app.current_session).is_null()
		assert_int(created[0]).is_zero()
		await _dispose_app(app)


func _content() -> ContentSnapshot:
	return GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs(true))


func _session(content: ContentSnapshot, seed: int) -> GameSession:
	var config := SessionConfig.new()
	config.seed = seed
	config.character_id = ValidationContentFactory.CHARACTER_ID
	config.starting_weapon_id = ValidationContentFactory.RANGED_ID
	config.difficulty_id = ValidationContentFactory.DIFFICULTY_ID
	config.zone_id = ValidationContentFactory.ZONE_ID
	var session := GameSession.new()
	assert_int(session.start(config, content)).is_equal(OK)
	return session


func _app() -> AppKernel:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	get_tree().root.add_child(viewport)
	var app := APP_SCENE.instantiate() as AppKernel
	viewport.add_child(app)
	await get_tree().process_frame
	return app


func _dispose_app(app: AppKernel) -> void:
	if app == null or not is_instance_valid(app):
		return
	var viewport := app.get_parent()
	app.free()
	if viewport != null and is_instance_valid(viewport):
		viewport.free()
	await get_tree().process_frame


func _assert_variant_exact(expected: Variant, actual: Variant, path: String) -> void:
	assert_int(typeof(actual)).override_failure_message(path + " type").is_equal(typeof(expected))
	if typeof(actual) != typeof(expected):
		return
	if expected is Dictionary:
		assert_bool(expected.is_same_typed(actual)).override_failure_message(
			path + " dictionary typed metadata"
		).is_true()
		if not expected.is_same_typed(actual):
			return
		var expected_keys: Array = expected.keys()
		var actual_keys: Array = actual.keys()
		assert_int(actual_keys.size()).override_failure_message(path + " key count").is_equal(expected_keys.size())
		if actual_keys.size() != expected_keys.size():
			return
		var matched_indices: Array[int] = []
		for expected_key: Variant in expected_keys:
			var found_index := -1
			for actual_index in actual_keys.size():
				if actual_index in matched_indices:
					continue
				var candidate_key: Variant = actual_keys[actual_index]
				if typeof(candidate_key) == typeof(expected_key) and var_to_bytes(candidate_key) == var_to_bytes(expected_key):
					found_index = actual_index
					break
			assert_int(found_index).override_failure_message(path + "." + str(expected_key) + " exact key").is_greater_equal(0)
			if found_index < 0:
				continue
			matched_indices.append(found_index)
			var actual_key: Variant = actual_keys[found_index]
			_assert_variant_exact(expected[expected_key], actual[actual_key], path + "." + str(expected_key))
	elif expected is Array:
		assert_bool(expected.is_same_typed(actual)).override_failure_message(
			path + " array typed metadata"
		).is_true()
		if not expected.is_same_typed(actual):
			return
		assert_int(actual.size()).override_failure_message(path + " length").is_equal(expected.size())
		if actual.size() != expected.size():
			return
		for index in expected.size():
			_assert_variant_exact(expected[index], actual[index], "%s[%d]" % [path, index])
	else:
		assert_that(actual).override_failure_message(path + " value").is_equal(expected)


func _assert_isolated_profile_root() -> void:
	var expected := OS.get_environment("GOGOBRO_TEST_EXPECTED_USER_DATA_DIR").replace("\\", "/").simplify_path()
	var actual := OS.get_user_data_dir().replace("\\", "/").simplify_path()
	assert_bool(not expected.is_empty() and expected.is_absolute_path()).is_true()
	assert_str(actual).is_equal(expected)


func _remove_synthetic_profile() -> void:
	var expected := OS.get_environment("GOGOBRO_TEST_EXPECTED_USER_DATA_DIR").replace("\\", "/").simplify_path()
	if expected.is_empty() or OS.get_user_data_dir().replace("\\", "/").simplify_path() != expected:
		return
	for path in PROFILE_PATHS:
		if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
