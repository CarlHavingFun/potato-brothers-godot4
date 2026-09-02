extends GdUnitTestSuite

const SHOP_SCREEN := preload("res://game/ui/shop_screen.gd")
const INVENTORY := preload("res://game/session/weapon_inventory.gd")
const RANGED := ValidationContentFactory.RANGED_ID
const PLAYABLE := [FlowRoute.MAIN_MENU, FlowRoute.CHARACTER_SELECT, FlowRoute.WEAPON_SELECT,
	FlowRoute.DIFFICULTY_SELECT, FlowRoute.COMBAT, FlowRoute.SHOP, FlowRoute.UPGRADE, FlowRoute.SETTLEMENT]

class ObservedProfile extends ProfileService:
	var writer_attempts := 0
	var directory_attempts := 0
	func _atomic_write(payload: Dictionary) -> Error:
		writer_attempts += 1
		return super._atomic_write(payload)
	func _ensure_directory() -> Error:
		directory_attempts += 1
		return super._ensure_directory()

class FailingStaticService extends GogoStaticAssetRuntimeService:
	var fail_stage := false
	var fail_activate := false
	func stage(content: ContentSnapshot) -> Error:
		return ERR_CANT_CREATE if fail_stage else super.stage(content)
	func activate_staged(route: StringName, session: GameSession) -> Error:
		return ERR_CANT_CREATE if fail_activate else super.activate_staged(route, session)

class RejectingCheckpointProfile extends ProfileService:
	func save_checkpoint(_state: GogoRunState) -> Error:
		last_error = "synthetic checkpoint rejection"
		return ERR_CANT_CREATE

var _content: ContentSnapshot


func before_test() -> void:
	# This suite can delete only its three synthetic files in the runner's actual user://.
	assert_str(OS.get_user_data_dir().replace("\\", "/")).is_equal(OS.get_environment("GOGOBRO_TEST_EXPECTED_USER_DATA_DIR").replace("\\", "/"))
	_content = GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs(true))
	_clean_synthetic()


func after_test() -> void:
	_clean_synthetic()


# Catches read-side mkdir and treating an absent checkpoint differently from absent file.
func test_absent_file_and_absent_checkpoint_load_without_file_operations() -> void:
	var service := ObservedProfile.new()
	var before := _snapshot(service)
	assert_int(_load(service)).is_equal(OK)
	assert_dict(_snapshot(service)).is_equal(before)
	assert_int(service.directory_attempts).is_equal(0)
	var payload := _envelope()
	payload["extension"] = {"keep": [1, "custom"]}
	_write(payload)
	var disk := _disk()
	assert_int(_load(service)).is_equal(OK)
	_assert_small_fixture_semantics(service.profile_data, payload)
	assert_dict(_disk()).is_equal(disk)
	assert_int(service.writer_attempts).is_equal(0)
	assert_int(service.directory_attempts).is_equal(0)


# Catches accepting null/empty/wrong checkpoint, lossy v1 ranks, or invalid schema3.
func test_real_file_invalid_checkpoints_preserve_memory_bytes_and_latch() -> void:
	var ambiguous := _legacy()
	ambiguous.players[0].weapon_levels = {String(RANGED): 2}
	var orphan := _legacy()
	orphan.players[0].weapon_levels = {String(ValidationContentFactory.MELEE_ID): 1}
	var invalid := _state().to_dictionary()
	invalid.players[0].weapons[0].quality = 5
	for checkpoint in [null, {}, [], "bad", 42, ambiguous, orphan, invalid]:
		var payload := _envelope()
		payload.run_checkpoint = checkpoint
		var original := payload.duplicate(true)
		_write(payload)
		var service := ObservedProfile.new()
		service.profile_data["sentinel"] = {"precall": [7]}
		var before := _snapshot(service)
		assert_int(_load(service)).is_not_equal(OK)
		assert_dict(_snapshot(service)).is_equal(before)
		assert_dict(payload).is_equal(original)
		assert_int(service.directory_attempts).is_equal(0)
		if _guard_api(service):
			assert_bool(service.call("is_write_blocked")).is_true()
			var diagnostic: Dictionary = service.call("checkpoint_diagnostic")
			assert_str(diagnostic.path).contains("run_checkpoint")
			assert_int(diagnostic.error).is_not_equal(OK)
			assert_int(diagnostic.size()).is_equal(3)
			diagnostic.path = "tampered"
			assert_str(service.call("checkpoint_diagnostic").path).is_not_equal("tampered")
			_assert_small_fixture_semantics(service.get("_loaded_profile_payload"), original)


# Catches outer-envelope coercion and JSON/read failures leaving writable defaults.
func test_json_envelope_and_read_errors_are_fail_closed() -> void:
	var bad_payloads: Array = [null, [], {}, {"schema_version": 1}, {"schema_version": true, "completed_runs": 0, "best_wave": 0}]
	for key in ["schema_version", "completed_runs", "best_wave"]:
		for value in [true, "1", 1.5, -1]:
			var payload := _envelope()
			payload[key] = value
			bad_payloads.append(payload)
	for raw in bad_payloads:
		_write(raw)
		_assert_failed_read_preserved()
	_write_text("{ broken json")
	_assert_failed_read_preserved()
	_clean_synthetic()
	assert_int(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ProfileService.PROFILE_PATH))).is_equal(OK)
	_assert_failed_read_preserved()


func test_valid_v1_load_is_readonly_and_keeps_raw_checkpoint_while_schema3_validates() -> void:
	for checkpoint in [_legacy(), _state().to_dictionary()]:
		var payload := _envelope()
		payload.run_checkpoint = checkpoint
		_write(payload)
		var before := _disk()
		var service := ObservedProfile.new()
		assert_int(_load(service)).is_equal(OK)
		_assert_small_fixture_semantics(service.profile_data, payload)
		assert_dict(_disk()).is_equal(before)
		assert_int(service.writer_attempts).is_equal(0)
		assert_int(service.directory_attempts).is_equal(0)
		if _guard_api(service): assert_bool(service.call("is_write_blocked")).is_false()


func test_profile_guard_enforces_only_initialized_current_wave_shop_cache_shape_and_phase() -> void:
	var current := _state().to_dictionary()
	current.shop_offer_wave = current.current_wave
	current.shop_offer_ids = ["", "", "", ""]
	current.shop_offer_initialized = true
	var ended_settlement := current.duplicate(true)
	ended_settlement.phase = "settlement"
	ended_settlement.ended = true
	var uninitialized_same_wave := current.duplicate(true)
	uninitialized_same_wave.shop_offer_initialized = false
	uninitialized_same_wave.shop_offer_ids = []
	uninitialized_same_wave.phase = "combat"
	var previous_wave := current.duplicate(true)
	previous_wave.current_wave = 2
	previous_wave.phase = "combat"
	previous_wave.shop_offer_wave = 1
	previous_wave.shop_offer_ids = [String(RANGED), ""]
	for checkpoint in [current, ended_settlement, uninitialized_same_wave, previous_wave]:
		_clean_synthetic()
		var payload := _envelope()
		payload.run_checkpoint = checkpoint
		_write(payload)
		var disk_before := _disk()
		var service := ObservedProfile.new()
		assert_int(_load(service)).is_equal(OK)
		_assert_small_fixture_semantics(service.profile_data, payload)
		var parsed := service.parse_checkpoint()
		assert_int(parsed.error).is_equal(OK)
		assert_dict(_disk()).is_equal(disk_before)
		assert_int(service.writer_attempts).is_zero()
		assert_int(service.directory_attempts).is_zero()

	var partial := current.duplicate(true)
	partial.shop_offer_ids = ["", "", ""]
	var wrong_phase := current.duplicate(true)
	wrong_phase.phase = "combat"
	for pair in [[partial, "run_checkpoint.shop_offer_ids"], [wrong_phase, "run_checkpoint.phase"]]:
		_clean_synthetic()
		var payload := _envelope()
		payload.run_checkpoint = pair[0]
		var original := payload.duplicate(true)
		_write(payload)
		var service := ObservedProfile.new()
		service.profile_data["sentinel"] = {"before": [7]}
		var before := _snapshot(service)
		assert_int(_load(service)).is_not_equal(OK)
		assert_dict(_snapshot(service)).is_equal(before)
		assert_dict(payload).is_equal(original)
		assert_str(service.checkpoint_diagnostic().path).is_equal(pair[1])
		assert_bool(service.is_write_blocked()).is_true()
		assert_int(service.writer_attempts).is_zero()
		assert_int(service.directory_attempts).is_zero()


# Each upper entrance must reject BEFORE writer dispatch; direct dispatch is one attempt, zero I/O.
func test_invalid_load_blocks_all_three_entrances_and_direct_writer() -> void:
	var payload := _envelope()
	payload.run_checkpoint = null
	_write(payload)
	_seed_sidecars()
	var service := ObservedProfile.new()
	assert_int(_load(service)).is_not_equal(OK)
	var before := _snapshot(service)
	var diagnostic_before: String = service.last_error
	var good := _state()
	assert_int(service.save_checkpoint(good)).is_not_equal(OK)
	assert_dict(_snapshot(service)).is_equal(before)
	good.ended = true
	good.phase = &"settlement"
	assert_int(service.record_settlement(good)).is_not_equal(OK)
	assert_dict(_snapshot(service)).is_equal(before)
	assert_int(service.clear_checkpoint()).is_not_equal(OK)
	assert_dict(_snapshot(service)).is_equal(before)
	assert_int(service.writer_attempts).is_equal(0)
	assert_int(service._atomic_write(_envelope())).is_not_equal(OK)
	assert_int(service.writer_attempts).is_equal(1)
	assert_int(service.directory_attempts).is_equal(0)
	assert_dict(_snapshot(service)).is_equal(before)
	assert_str(service.last_error).is_equal(diagnostic_before)


func test_injected_bad_current_blocks_replacement_clear_settlement_and_direct_writer() -> void:
	for entrance in ["save", "clear", "settlement", "direct"]:
		_write(_envelope())
		_seed_sidecars()
		var service := ObservedProfile.new()
		assert_int(_load(service)).is_equal(OK)
		service.profile_data.run_checkpoint = {}
		var before := _snapshot(service)
		var state := _state()
		state.ended = true
		state.phase = &"settlement"
		var error: int
		match entrance:
			"save": error = service.save_checkpoint(state)
			"clear": error = service.clear_checkpoint()
			"settlement": error = service.record_settlement(state)
			_: error = service._atomic_write(_envelope())
		assert_int(error).is_not_equal(OK)
		assert_dict(_snapshot(service)).is_equal(before)
		assert_int(service.directory_attempts).is_equal(0)
		assert_int(service.writer_attempts).is_equal(1 if entrance == "direct" else 0)
		if _guard_api(service): assert_bool(service.call("is_write_blocked")).is_true()


# Catches trusting valid old data as evidence for a malformed NEW run, or poisoning valid current state.
func test_invalid_incoming_state_and_candidate_reject_without_latching_then_valid_write_succeeds() -> void:
	_write(_envelope())
	var service := ObservedProfile.new()
	assert_int(_load(service)).is_equal(OK)
	for defect in ["null", "empty_players", "null_player", "null_inventory", "quality_schema", "negative_wave"]:
		var state := _state()
		match defect:
			"null": state = null
			"empty_players": state.players.clear()
			"null_player": state.players[0] = null
			"null_inventory": state.player().weapon_inventory = null
			"quality_schema": state.schema_version = 99
			"negative_wave": state.current_wave = -1
		var before := _snapshot(service)
		assert_int(service.save_checkpoint(state)).is_not_equal(OK)
		assert_dict(_snapshot(service)).is_equal(before)
		assert_int(service.record_settlement(state)).is_not_equal(OK)
		assert_dict(_snapshot(service)).is_equal(before)
		assert_int(service.directory_attempts).is_equal(0)
	assert_int(service.writer_attempts).is_equal(0)
	var candidate := _envelope()
	candidate.run_checkpoint = null
	var candidate_before := candidate.duplicate(true)
	var before := _snapshot(service)
	assert_int(service._atomic_write(candidate)).is_not_equal(OK)
	assert_dict(candidate).is_equal(candidate_before)
	assert_dict(_snapshot(service)).is_equal(before)
	assert_int(service.directory_attempts).is_equal(0)
	assert_int(service.writer_attempts).is_equal(1)
	if _guard_api(service): assert_bool(service.call("is_write_blocked")).is_false()
	assert_int(service.save_checkpoint(_state())).is_equal(OK)
	assert_int(service.directory_attempts).is_equal(1)
	assert_int(service.writer_attempts).is_equal(2)
	assert_int(int(service.profile_data.run_checkpoint.schema_version)).is_equal(3)
	assert_bool(FileAccess.file_exists(ProfileService.PROFILE_PATH)).is_true()


func test_parse_checkpoint_is_detached_read_only_and_absence_is_explicit() -> void:
	var absent := ProfileService.new()
	assert_int(_load(absent)).is_equal(OK)
	var absent_before := _snapshot(absent)
	var diagnostic_before := absent.checkpoint_diagnostic()
	var missing := absent.parse_checkpoint()
	assert_int(missing.error).is_equal(ERR_DOES_NOT_EXIST)
	assert_object(missing.state).is_null()
	assert_dict(_snapshot(absent)).is_equal(absent_before)
	assert_dict(absent.checkpoint_diagnostic()).is_equal(diagnostic_before)

	var service := ProfileService.new()
	assert_int(_load(service)).is_equal(OK)
	assert_int(service.save_checkpoint(_state())).is_equal(OK)
	var before := _snapshot(service)
	var profile_bytes := var_to_bytes(service.profile_data)
	var first := service.parse_checkpoint()
	var second := service.parse_checkpoint()
	assert_int(first.error).is_equal(OK)
	assert_int(second.error).is_equal(OK)
	assert_bool(first.state != second.state).is_true()
	if first.error != OK or second.error != OK:
		return
	first.state.player().materials = 999999
	first.state.player().base_stats[&"detached_probe"] = 1.0
	assert_int(second.state.player().materials).is_not_equal(999999)
	assert_bool(second.state.player().base_stats.has(&"detached_probe")).is_false()
	assert_array(var_to_bytes(service.profile_data)).is_equal(profile_bytes)
	assert_dict(_snapshot(service)).is_equal(before)


# Catches a successful legal int64 save that cannot be reloaded losslessly through actual JSON.
func test_legal_materials_int64_boundaries_survive_actual_profile_json_round_trip() -> void:
	for expected: int in [9223372036854775807, 9007199254740993]:
		_clean_synthetic()
		var service := ObservedProfile.new()
		assert_int(_load(service)).is_equal(OK)
		var state := _state()
		state.player().materials = expected
		var candidate_check := GogoRunState.parse_dictionary(state.to_dictionary(), _content)
		assert_int(candidate_check.error).is_equal(OK)
		var save_error := service.save_checkpoint(state)
		assert_int(save_error).is_equal(OK)
		assert_int(state.player().materials).is_equal(expected)
		if save_error != OK: continue
		var disk_before := _disk()
		var text := FileAccess.get_file_as_string(ProfileService.PROFILE_PATH)
		var materials_token := ""
		for line in text.split("\n"):
			if line.strip_edges().begins_with("\"materials\":"):
				materials_token = line.strip_edges().trim_prefix("\"materials\":").trim_suffix(",").strip_edges()
		var decoded: Dictionary = JSON.parse_string(text)
		var decoded_materials: Variant = decoded.run_checkpoint.players[0].materials
		var loaded := ProfileService.new()
		var load_error := _load(loaded)
		var reloaded_materials := "unavailable"
		var recovered: GogoRunState = null
		if load_error == OK:
			recovered = GogoRunState.from_dictionary(loaded.profile_data.run_checkpoint, _content)
			if recovered != null: reloaded_materials = "%d" % recovered.player().materials
		print("INT64_PROFILE_PROBE " + JSON.stringify({
			"input_decimal": "%d" % expected,
			"candidate_error": candidate_check.error,
			"save_error": save_error,
			"saved_memory_decimal": "%d" % service.profile_data.run_checkpoint.players[0].materials,
			"json_numeric_token": materials_token,
			"decoded_type": type_string(typeof(decoded_materials)),
			"decoded_decimal": "%.0f" % decoded_materials,
			"load_error": load_error,
			"load_diagnostic": loaded.checkpoint_diagnostic(),
			"reloaded_decimal": reloaded_materials,
			"profile_sha256": FileAccess.get_sha256(ProfileService.PROFILE_PATH),
		}))
		assert_dict(_disk()).is_equal(disk_before)
		assert_int(load_error).is_equal(OK)
		if load_error == OK:
			assert_object(recovered).is_not_null()
			if recovered != null: assert_int(recovered.player().materials).is_equal(expected)


func test_settlement_and_clear_use_detached_validated_candidates() -> void:
	_write(_envelope())
	var service := ObservedProfile.new()
	assert_int(_load(service)).is_equal(OK)
	assert_int(service.save_checkpoint(_state())).is_equal(OK)
	var ended := _state()
	ended.phase = &"settlement"
	ended.ended = true
	ended.current_wave = 8
	assert_int(service.record_settlement(ended)).is_equal(OK)
	assert_int(service.profile_data.completed_runs).is_equal(1)
	assert_int(service.profile_data.best_wave).is_equal(8)
	assert_bool(service.profile_data.has("run_checkpoint")).is_false()
	assert_int(service.save_checkpoint(_state())).is_equal(OK)
	assert_int(service.clear_checkpoint()).is_equal(OK)
	assert_bool(service.profile_data.has("run_checkpoint")).is_false()
	assert_int(service.profile_data.completed_runs).is_equal(1)


# A real temp-file open failure must not publish the candidate or erase current checkpoint.
func test_settlement_and_clear_file_failure_preserve_canonical_memory_and_old_file() -> void:
	for entrance in ["settlement", "clear"]:
		_clean_synthetic()
		var payload := _envelope()
		payload.run_checkpoint = _state().to_dictionary()
		_write(payload)
		var service := ObservedProfile.new()
		assert_int(_load(service)).is_equal(OK)
		assert_int(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ProfileService.TEMP_PATH))).is_equal(OK)
		var before := _snapshot(service)
		var ended := _state()
		ended.ended = true
		ended.phase = &"settlement"
		var error := service.record_settlement(ended) if entrance == "settlement" else service.clear_checkpoint()
		assert_int(error).is_not_equal(OK)
		assert_dict(_snapshot(service)).is_equal(before)
		assert_int(service.writer_attempts).is_equal(1)
		assert_int(service.directory_attempts).is_equal(1)
		assert_bool(service.is_write_blocked()).is_false()


func test_pure_candidate_validation_does_not_latch_or_publish_and_requires_explicit_content() -> void:
	var service := ObservedProfile.new()
	assert_int(service.load_profile(_content)).is_equal(OK)
	var bad := _envelope()
	bad.run_checkpoint = null
	var original := bad.duplicate(true)
	var before := _snapshot(service)
	var diagnostic := service.checkpoint_diagnostic()
	assert_int(service._validate_profile_payload(bad).error).is_not_equal(OK)
	assert_dict(bad).is_equal(original)
	assert_dict(_snapshot(service)).is_equal(before)
	assert_dict(service.checkpoint_diagnostic()).is_equal(diagnostic)
	assert_bool(service.is_write_blocked()).is_false()
	assert_int(service.directory_attempts).is_equal(0)
	assert_int(service.writer_attempts).is_equal(0)
	var unconfigured := ObservedProfile.new()
	assert_int(unconfigured.save_checkpoint(_state())).is_not_equal(OK)
	assert_int(unconfigured.directory_attempts).is_equal(0)
	assert_int(unconfigured.writer_attempts).is_equal(0)


# Actual boot must consume codec failures, and direct route/session entry cannot bypass them.
func test_bad_profile_boot_reports_save_error_and_blocks_session_and_playable_routes() -> void:
	var payload := _envelope()
	payload.run_checkpoint = null
	_write(payload)
	var app := _kernel()
	var before := _disk()
	assert_int(app.boot().status).is_equal(BootResult.Status.SAVE_ERROR)
	assert_str(" ".join(app.boot_result.details)).contains("run_checkpoint")
	var created := [0]
	app.session_created.connect(func(_session: GameSession) -> void: created[0] += 1)
	_draft(app)
	assert_int(app.create_session_from_draft()).is_not_equal(OK)
	assert_object(app.current_session).is_null()
	assert_int(created[0]).is_equal(0)
	for route in PLAYABLE: assert_int(app.route(route)).is_not_equal(OK)
	assert_int(app.route(FlowRoute.DIAGNOSTIC)).is_equal(OK)
	app.current_session = _session()
	assert_int(app.save_checkpoint()).is_not_equal(OK)
	assert_int(app.profile_service.clear_checkpoint()).is_not_equal(OK)
	app.current_session.run_state.ended = true
	app.current_session.run_state.phase = &"settlement"
	assert_int(app.profile_service.record_settlement(app.current_session.run_state)).is_not_equal(OK)
	assert_dict(_disk()).is_equal(before)


func test_healthy_absent_and_valid_profile_boot_allow_configuration_and_single_session() -> void:
	for present in [false, true]:
		if present: _write(_envelope())
		var app := _kernel()
		assert_int(app.boot().status).is_equal(BootResult.Status.OK)
		assert_int(app.route(FlowRoute.CHARACTER_SELECT)).is_equal(OK)
		_draft(app)
		var created := [0]
		app.session_created.connect(func(_session: GameSession) -> void: created[0] += 1)
		assert_int(app.create_session_from_draft()).is_equal(OK)
		assert_int(created[0]).is_equal(1)


func test_new_session_checkpoint_failure_publishes_no_session_or_signal() -> void:
	var stale := _state()
	stale.current_wave = 7
	var payload := _envelope()
	payload.run_checkpoint = stale.to_dictionary()
	_write(payload)
	var app := _kernel()
	app.profile_service = RejectingCheckpointProfile.new()
	assert_int(app.boot().status).is_equal(BootResult.Status.OK)
	_draft(app)
	var created := [0]
	app.session_created.connect(func(_session: GameSession) -> void: created[0] += 1)
	var before := _snapshot(app.profile_service)
	assert_int(app.create_session_from_draft()).is_equal(ERR_CANT_CREATE)
	assert_object(app.current_session).is_null()
	assert_int(created[0]).is_equal(0)
	assert_dict(_snapshot(app.profile_service)).is_equal(before)
	assert_int(app.boot_result.status).is_equal(BootResult.Status.SAVE_ERROR)
	var reader := ProfileService.new()
	assert_int(reader.load_profile(app.content_snapshot)).is_equal(OK)
	var preserved: Dictionary = reader.parse_checkpoint()
	assert_int(preserved.error).is_equal(OK)
	if preserved.error == OK:
		assert_int(preserved.state.current_wave).is_equal(7)


func test_new_session_without_profile_context_fails_closed_before_publication() -> void:
	var app := _kernel()
	app.content_snapshot = _content
	_draft(app)
	var created := [0]
	app.session_created.connect(func(_session: GameSession) -> void: created[0] += 1)
	var before := _disk()
	assert_int(app.create_session_from_draft()).is_not_equal(OK)
	assert_object(app.current_session).is_null()
	assert_int(created[0]).is_zero()
	assert_dict(_disk()).is_equal(before)
	assert_int(app.boot_result.status).is_equal(BootResult.Status.SAVE_ERROR)


func test_resume_route_failure_balances_publication_with_close_and_rolls_back() -> void:
	var app := _kernel()
	assert_int(app.boot().status).is_equal(BootResult.Status.OK)
	var state := _state()
	assert_int(app.profile_service.save_checkpoint(state)).is_equal(OK)
	var expected: Dictionary = app.profile_service.parse_checkpoint()
	assert_int(expected.error).is_equal(OK)
	app.scene_flow = null
	var created := [0]
	var closed := [0]
	var published: Array[GameSession] = []
	app.session_created.connect(func(session: GameSession) -> void:
		created[0] += 1
		published.append(session)
	)
	app.session_closed.connect(func() -> void: closed[0] += 1)
	assert_int(app.resume_checkpoint()).is_equal(ERR_UNCONFIGURED)
	assert_object(app.current_session).is_null()
	assert_int(created[0]).is_equal(1)
	assert_int(closed[0]).is_equal(1)
	assert_int(published.size()).is_equal(1)
	if not published.is_empty() and expected.error == OK:
		assert_dict(published[0].run_state.to_dictionary()).is_equal(expected.state.to_dictionary())
		assert_int(published[0].rng.state).is_equal(expected.state.rng_state)


func test_newly_invalid_current_profile_exposes_kernel_save_error() -> void:
	var app := _kernel()
	assert_int(app.boot().status).is_equal(BootResult.Status.OK)
	app.current_session = _session()
	app.profile_service.profile_data.run_checkpoint = {}
	var before := _disk()
	assert_int(app.save_checkpoint()).is_not_equal(OK)
	assert_int(app.boot_result.status).is_equal(BootResult.Status.SAVE_ERROR)
	assert_str(" ".join(app.boot_result.details)).contains("run_checkpoint")
	assert_int(app.route(FlowRoute.COMBAT)).is_not_equal(OK)
	assert_dict(_disk()).is_equal(before)


func test_shop_continue_and_endless_route_diagnostic_on_save_error() -> void:
	for final_shop in [false, true]:
		_clean_synthetic()
		var app := _kernel()
		assert_int(app.boot().status).is_equal(BootResult.Status.OK)
		app.current_session = _session()
		app.current_session.run_state.current_wave = 20 if final_shop else 1
		app.profile_service.profile_data.run_checkpoint = null
		var screen := auto_free(SHOP_SCREEN.new()) as GogoScreenBase
		screen.set("_app", app)
		screen.call("_continue_endless" if final_shop else "_continue_run")
		assert_str(String(app.scene_flow.current_route())).is_equal(String(FlowRoute.DIAGNOSTIC))
		assert_int(app.boot_result.status).is_equal(BootResult.Status.SAVE_ERROR)
		assert_bool(FileAccess.file_exists(ProfileService.PROFILE_PATH)).is_false()


# Controlled transition, NOT a twenty-wave pilot: real shop combine, real handler and real JSON file.
func test_controlled_final_shop_combine_endless_handler_and_json_preserve_copy_identity() -> void:
	var app := _kernel()
	assert_int(app.boot().status).is_equal(BootResult.Status.OK)
	var session := _session()
	app.current_session = session
	session.run_state.current_wave = 20
	var parsed := INVENTORY.parse_records([
		{"instance_id": 11, "content_id": RANGED, "quality": 1},
		{"instance_id": 22, "content_id": RANGED, "quality": 1},
		{"instance_id": 33, "content_id": RANGED, "quality": 2}], 50, session.content_snapshot)
	session.run_state.player().weapon_inventory = parsed.inventory
	var shop := ShopRuntimeService.new()
	assert_int(shop.open_shop(session).size()).is_equal(4)
	assert_int(shop.combine_weapon(session, 22)).is_equal(OK)
	var screen := auto_free(SHOP_SCREEN.new()) as GogoScreenBase
	screen.set("_app", app)
	screen.call("_continue_endless")
	assert_str(String(app.scene_flow.current_route())).is_equal(String(FlowRoute.COMBAT))
	assert_int(session.run_state.current_wave).is_equal(21)
	assert_bool(session.run_state.endless).is_true()
	var loaded := ProfileService.new()
	assert_int(_load(loaded)).is_equal(OK)
	var decoded := GogoRunState.from_dictionary(loaded.profile_data.run_checkpoint, _content)
	assert_object(decoded).is_not_null()
	if decoded == null: return
	assert_int(decoded.current_wave).is_equal(21)
	assert_int(decoded.player().next_weapon_instance_id).is_equal(50)
	assert_array(decoded.player().weapon_inventory.records()).is_equal([
		{"instance_id": 22, "content_id": RANGED, "quality": 2},
		{"instance_id": 33, "content_id": RANGED, "quality": 2}])
	assert_int(decoded.player().weapon_inventory.add_weapon(RANGED, _content).error).is_equal(OK)
	assert_int(decoded.player().next_weapon_instance_id).is_equal(51)
	assert_int(decoded.player().weapon_inventory.records().back().instance_id).is_equal(50)


# Catches profile keeping its boot context after the real catalog activates a new weapon.
func test_content_activation_new_weapon_is_saveable_and_catalog_observers_see_new_context() -> void:
	var app := _kernel()
	assert_int(app.boot().status).is_equal(BootResult.Status.OK)
	assert_int(app.route(FlowRoute.MAIN_MENU)).is_equal(OK)
	var pack := _new_weapon_pack(app.content_snapshot)
	assert_int(app.content_catalog.install(pack, false)).is_equal(OK)
	assert_int(app.content_catalog.stage_enabled(pack.pack_id, true)).is_equal(OK)
	var signals := [0]
	app.content_catalog.active_packs_changed.connect(func(ids: Array[StringName]) -> void:
		signals[0] += 1
		assert_bool(ids.has(&"b3.new_weapon")).is_true()
		assert_bool(app.content_snapshot.has_definition(&"b3.new_weapon:weapon/test", &"weapon")).is_true()
		assert_object(app.profile_service.get("_content")).is_same(app.content_snapshot)
		# New pending edits during publication must stay pending, not be overwritten.
		app.content_catalog.stage_enabled(&"b3.new_weapon", false)
	)
	assert_int(app.apply_pending_content_packs()).is_equal(OK)
	assert_int(signals[0]).is_equal(1)
	assert_bool(app.content_catalog.has_pending_changes()).is_true()
	_draft(app)
	app.selection_draft.weapon_id = &"b3.new_weapon:weapon/test"
	assert_int(app.create_session_from_draft()).is_equal(OK)
	assert_int(app.save_checkpoint()).is_equal(OK)
	assert_bool(app.profile_service.is_write_blocked()).is_false()
	var loaded := ProfileService.new()
	assert_int(loaded.load_profile(app.content_snapshot)).is_equal(OK)
	assert_bool(loaded.profile_data.has("run_checkpoint")).is_true()
	if loaded.profile_data.has("run_checkpoint"):
		assert_str(loaded.profile_data.run_checkpoint.players[0].weapons[0].content_id).is_equal("b3.new_weapon:weapon/test")


func test_incompatible_pending_removal_preserves_old_context_profile_active_ids_and_writeability() -> void:
	var app := _kernel()
	assert_int(app.boot().status).is_equal(BootResult.Status.OK)
	assert_int(app.route(FlowRoute.MAIN_MENU)).is_equal(OK)
	var state := _state()
	assert_int(app.profile_service.save_checkpoint(state)).is_equal(OK)
	_seed_sidecars()
	var before := _snapshot(app.profile_service)
	var old_context := app.content_snapshot
	var old_ids := app.content_catalog.active_pack_ids()
	var old_raw: Variant = app.profile_service.get("_loaded_profile_payload")
	var old_diagnostic := app.profile_service.checkpoint_diagnostic()
	assert_int(app.content_catalog.stage_enabled(&"weapon.training_blaster", false)).is_equal(OK)
	assert_int(app.apply_pending_content_packs()).is_not_equal(OK)
	assert_object(app.content_snapshot).is_same(old_context)
	assert_object(app.profile_service.get("_content")).is_same(old_context)
	assert_array(app.content_catalog.active_pack_ids()).is_equal(old_ids)
	assert_dict(_snapshot(app.profile_service)).is_equal(before)
	assert_array(var_to_bytes(app.profile_service.get("_loaded_profile_payload"))).is_equal(var_to_bytes(old_raw))
	assert_dict(app.profile_service.checkpoint_diagnostic()).is_equal(old_diagnostic)
	assert_bool(app.profile_service.is_write_blocked()).is_false()
	assert_int(app.profile_service.save_checkpoint(state)).is_equal(OK)


func test_static_stage_or_activation_failure_does_not_commit_profile_or_active_packs() -> void:
	for stage_fails in [true, false]:
		_clean_synthetic()
		var app := _kernel()
		var static_service := FailingStaticService.new()
		app.static_asset_service = static_service
		assert_int(app.boot().status).is_equal(BootResult.Status.OK)
		assert_int(app.route(FlowRoute.MAIN_MENU)).is_equal(OK)
		var pack := _new_weapon_pack(app.content_snapshot)
		assert_int(app.content_catalog.install(pack, false)).is_equal(OK)
		assert_int(app.content_catalog.stage_enabled(pack.pack_id, true)).is_equal(OK)
		var old_ids := app.content_catalog.active_pack_ids()
		var old_context := app.content_snapshot
		var before := _snapshot(app.profile_service)
		var signals := [0]
		app.content_catalog.active_packs_changed.connect(func(_ids: Array[StringName]) -> void: signals[0] += 1)
		static_service.fail_stage = stage_fails
		static_service.fail_activate = not stage_fails
		assert_int(app.apply_pending_content_packs()).is_equal(ERR_CANT_CREATE)
		assert_object(app.content_snapshot).is_same(old_context)
		assert_object(app.profile_service.get("_content")).is_same(old_context)
		assert_array(app.content_catalog.active_pack_ids()).is_equal(old_ids)
		assert_dict(_snapshot(app.profile_service)).is_equal(before)
		assert_int(signals[0]).is_equal(0)
		assert_bool(app.content_catalog.has_pending_changes()).is_true()


func test_content_activation_cannot_wash_invalid_current_profile_or_clear_latch() -> void:
	var app := _kernel()
	assert_int(app.boot().status).is_equal(BootResult.Status.OK)
	assert_int(app.route(FlowRoute.MAIN_MENU)).is_equal(OK)
	var old_context := app.content_snapshot
	var old_ids := app.content_catalog.active_pack_ids()
	app.profile_service.profile_data.run_checkpoint = null
	var before := _snapshot(app.profile_service)
	assert_int(app.apply_pending_content_packs()).is_not_equal(OK)
	assert_bool(app.profile_service.is_write_blocked()).is_true()
	assert_int(app.boot_result.status).is_equal(BootResult.Status.SAVE_ERROR)
	assert_object(app.content_snapshot).is_same(old_context)
	assert_object(app.profile_service.get("_content")).is_same(old_context)
	assert_array(app.content_catalog.active_pack_ids()).is_equal(old_ids)
	assert_dict(_snapshot(app.profile_service)).is_equal(before)


func test_handwritten_wire_retains_int64_extensions_seed_and_finite_float_domain() -> void:
	_write_text(_handwritten_wire("9223372036854775807"))
	var service := ObservedProfile.new()
	var before := _disk()
	assert_int(_load(service)).is_equal(OK)
	assert_dict(_disk()).is_equal(before)
	if not service.profile_data.has("run_checkpoint"): return
	assert_int(service.profile_data.extension[0]).is_equal(9007199254740993)
	assert_str(service.profile_data.extension[1]).is_equal("9007199254740993")
	assert_int(service.profile_data.run_checkpoint.run_seed).is_equal(-9223372036854775808)
	assert_int(service.profile_data.run_checkpoint.players[0].materials).is_equal(9223372036854775807)
	assert_float(service.profile_data.run_checkpoint.players[0].current_health).is_equal(1e100)
	var state := GogoRunState.from_dictionary(service.profile_data.run_checkpoint, _content)
	assert_object(state).is_not_null()
	if state == null: return
	assert_int(service.save_checkpoint(state)).is_equal(OK)
	var reloaded := ProfileService.new()
	assert_int(_load(reloaded)).is_equal(OK)
	assert_int(reloaded.profile_data.run_checkpoint.players[0].materials).is_equal(9223372036854775807)
	assert_float(reloaded.profile_data.run_checkpoint.players[0].current_health).is_equal(1e100)
	assert_int(reloaded.profile_data.extension[0]).is_equal(9007199254740993)


func test_profile_save_roundtrip_preserves_adjacent_double_exactly() -> void:
	var state := _state()
	# Construct the exact binary64 produced by the real wave-22 economy accumulator.
	# A decimal literal is not suitable here because Godot's parser rounds this
	# particular value one ULP upward before the test can exercise profile JSON.
	var expected_remainder := PackedByteArray([0x00, 0x6a, 0x14, 0xae, 0x47, 0xe1, 0xca, 0x3f]).decode_double(0)
	state.player().economy_material_remainder = expected_remainder
	var service := ProfileService.new()
	assert_int(_load(service)).is_equal(OK)
	var save_error := service.save_checkpoint(state)
	assert_int(save_error).is_equal(OK)
	var reloaded := ProfileService.new()
	assert_int(_load(reloaded)).is_equal(OK)
	if not reloaded.profile_data.has("run_checkpoint"): return
	var actual_remainder: float = reloaded.profile_data.run_checkpoint.players[0].economy_material_remainder
	assert_array(var_to_bytes(actual_remainder)).is_equal(var_to_bytes(expected_remainder))


func test_wire_integer_domains_reject_rounded_fractional_tokens_before_publishing() -> void:
	for token in ["1.00000000000000001", "9007199254740992.1", "9223372036854775808", "1e100", "true", '"1"']:
		_write_text(_handwritten_wire(token))
		_assert_failed_read_preserved()
	for replacement in ['"schema_version":1.00000000000000001', '"run_seed":-9223372036854775809',
		'"player_index":0.00000000000000000001', '"level":1.00000000000000001']:
		var key: String = replacement.split(":")[0]
		var source := _handwritten_wire("1")
		var old_token := '"run_seed":-9223372036854775808' if key == '"run_seed"' else key + (":0" if key == '"player_index"' else ":1")
		_write_text(source.replace(old_token, replacement))
		_assert_failed_read_preserved()
	_write_text(_handwritten_wire("1").replace('"weapon_levels":{}', '"weapon_levels":{"weapon.training_blaster:weapon/training_blaster":1.00000000000000001}'))
	_assert_failed_read_preserved()
	for token in ["9007199254740993.0", "9.223372036854775807e18"]:
		_write_text(_handwritten_wire(token))
		var service := ProfileService.new()
		assert_int(_load(service)).is_equal(OK)
		if service.profile_data.has("run_checkpoint"):
			assert_int(service.profile_data.run_checkpoint.players[0].materials).is_equal(9007199254740993 if token.begins_with("9007") else 9223372036854775807)
	_clean_synthetic()
	var schema3 := ProfileService.new()
	assert_int(_load(schema3)).is_equal(OK)
	assert_int(schema3.save_checkpoint(_state())).is_equal(OK)
	var source := FileAccess.get_file_as_string(ProfileService.PROFILE_PATH)
	var rng_value: int = schema3.profile_data.run_checkpoint.rng_state
	var rng_token := '"rng_state": %d' % rng_value
	for replacement in ['"rng_state": 1.00000000000000001', '"rng_state": 9223372036854775808']:
		_write_text(source.replace(rng_token, replacement))
		_assert_failed_read_preserved()


func test_structured_numeric_paths_do_not_confuse_dotted_escaped_or_numeric_string_keys() -> void:
	_write_text('{"schema_version":1,"completed_runs":0,"best_wave":0,"run_checkpoint.players[0].materials":1e100,"extension":{"0":{"materials":1e100},"schema_version":1.00000000000000001,"escaped\\u002ekey":9007199254740993}}')
	var service := ProfileService.new()
	assert_int(_load(service)).is_equal(OK)
	assert_float(service.profile_data["run_checkpoint.players[0].materials"]).is_equal(1e100)
	assert_int(service.profile_data.extension["escaped.key"]).is_equal(9007199254740993)


func test_encoded_candidate_fidelity_failure_precedes_directory_and_sidecar_actions() -> void:
	var service := ObservedProfile.new()
	assert_int(_load(service)).is_equal(OK)
	_seed_sidecars()
	var before := _snapshot(service)
	var candidate := _envelope()
	# Legal extension Variant, but JSON object keys become strings: integer cannot be found at its original path.
	candidate.extension = {1: 9007199254740993}
	assert_int(service.call("_atomic_write", candidate)).is_not_equal(OK)
	assert_int(service.directory_attempts).is_equal(0)
	assert_dict(_snapshot(service)).is_equal(before)
	assert_bool(service.is_write_blocked()).is_false()
	for nonfinite in [NAN, INF, -INF]:
		candidate.extension = [nonfinite]
		assert_int(service.call("_atomic_write", candidate)).is_not_equal(OK)
		assert_int(service.directory_attempts).is_equal(0)
		assert_dict(_snapshot(service)).is_equal(before)
		assert_bool(service.is_write_blocked()).is_false()


func _handwritten_wire(materials: String) -> String:
	# Raw legacy JSON independent of production serialization and numeric decoding.
	return '{"schema_version":1,"completed_runs":0,"best_wave":0,"extension":[9007199254740993,"9007199254740993"],"run_checkpoint":{"schema_version":1,"run_seed":-9223372036854775808,"current_wave":1,"total_waves":20,"phase":"shop","zone_id":"gogobro.core:zone/training_ground","difficulty_id":"gogobro.core:difficulty/standard","won":false,"ended":false,"players":[{"player_index":0,"character_id":"character.niko:character/niko","level":1,"xp":0,"xp_to_next_level":20,"materials":' + materials + ',"current_health":1e100,"max_health":1e100,"base_stats":{},"final_stats":{},"weapon_ids":["weapon.training_blaster:weapon/training_blaster"],"weapon_levels":{},"item_ids":[],"upgrade_ids":[]}]}}'


func _new_weapon_pack(content: ContentSnapshot) -> GogoContentPackDefinition:
	var weapon := content.definition(RANGED, &"weapon").duplicate(true) as GogoWeaponDefinition
	weapon.content_id = &"b3.new_weapon:weapon/test"
	weapon.display_name = "Synthetic context test weapon"
	var pack := GogoContentPackDefinition.new()
	pack.pack_id = &"b3.new_weapon"
	pack.pack_kind = &"weapon"
	pack.definitions.append(weapon)
	return pack


func _assert_failed_read_preserved() -> void:
	var service := ObservedProfile.new()
	var before := _snapshot(service)
	assert_int(_load(service)).is_not_equal(OK)
	assert_dict(_snapshot(service)).is_equal(before)
	assert_int(service.directory_attempts).is_equal(0)
	if _guard_api(service): assert_bool(service.call("is_write_blocked")).is_true()


func _assert_small_fixture_semantics(actual: Dictionary, expected: Dictionary) -> void:
	# Legacy small-number fixtures compare their full JSON value, not the old decoder's
	# float-only representation. Large-number identity has separate literal assertions.
	assert_dict(JSON.parse_string(JSON.stringify(actual))).is_equal(JSON.parse_string(JSON.stringify(expected)))


func _guard_api(service: ProfileService) -> bool:
	assert_bool(service.has_method("is_write_blocked")).is_true()
	return service.has_method("is_write_blocked")


func _load(service: ProfileService) -> int:
	return service.load_profile(_content)


func _envelope() -> Dictionary:
	return {"schema_version": 1, "completed_runs": 0, "best_wave": 0}


func _session() -> GameSession:
	var config := SessionConfig.new()
	config.seed = 19
	config.character_id = NikoContentFactory.CHARACTER_ID
	config.starting_weapon_id = RANGED
	config.difficulty_id = ValidationContentFactory.DIFFICULTY_ID
	config.zone_id = ValidationContentFactory.ZONE_ID
	var session := GameSession.new()
	assert_int(session.start(config, _content)).is_equal(OK)
	assert_int(session.transition(&"shop")).is_equal(OK)
	return session


func _state() -> GogoRunState:
	return _session().run_state


func _legacy() -> Dictionary:
	return {"schema_version": 1, "run_seed": 15, "current_wave": 1, "total_waves": 20,
		"phase": "shop", "zone_id": String(ValidationContentFactory.ZONE_ID),
		"difficulty_id": String(ValidationContentFactory.DIFFICULTY_ID), "won": false, "ended": false,
		"players": [{"player_index": 0, "character_id": String(NikoContentFactory.CHARACTER_ID),
			"level": 1, "xp": 0, "xp_to_next_level": 20, "materials": 100,
			"current_health": 20.0, "max_health": 20.0, "base_stats": {}, "final_stats": {},
			"weapon_ids": [String(RANGED)], "item_ids": [], "upgrade_ids": []}]}


func _kernel() -> AppKernel:
	var app := auto_free(AppKernel.new()) as AppKernel
	add_child(app)
	var host := Control.new()
	app.add_child(host)
	var flow := SceneFlow.new()
	app.add_child(flow)
	var node := Control.new()
	var scene := PackedScene.new()
	assert_int(scene.pack(node)).is_equal(OK)
	node.free()
	var routes := {FlowRoute.DIAGNOSTIC: scene}
	for route in PLAYABLE: routes[route] = scene
	flow.configure(host, routes)
	app.configure(flow, null)
	return app


func _draft(app: AppKernel) -> void:
	app.begin_selection()
	app.selection_draft.character_id = NikoContentFactory.CHARACTER_ID
	app.selection_draft.weapon_id = RANGED


func _snapshot(service: ProfileService) -> Dictionary:
	return {"memory": service.profile_data.duplicate(true), "disk": _disk()}


func _disk() -> Dictionary:
	var result := {"save_directory_exists": DirAccess.dir_exists_absolute(ProfileService.SAVE_DIRECTORY)}
	for path in [ProfileService.PROFILE_PATH, ProfileService.TEMP_PATH, ProfileService.BACKUP_PATH]:
		result[path] = {"exists": FileAccess.file_exists(path), "directory": DirAccess.dir_exists_absolute(path),
			"sha256": FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""}
	return result


func _write(payload: Variant) -> void:
	_write_text(JSON.stringify(payload))


func _write_text(text: String, path: String = ProfileService.PROFILE_PATH) -> void:
	assert_int(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ProfileService.SAVE_DIRECTORY))).is_equal(OK)
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_object(file).is_not_null()
	if file != null:
		file.store_string(text)
		file.close()


func _seed_sidecars() -> void:
	_write_text("synthetic untouched temporary", ProfileService.TEMP_PATH)
	_write_text("synthetic untouched backup", ProfileService.BACKUP_PATH)


func _clean_synthetic() -> void:
	var expected := OS.get_environment("GOGOBRO_TEST_EXPECTED_USER_DATA_DIR").replace("\\", "/")
	if expected.is_empty() or OS.get_user_data_dir().replace("\\", "/") != expected: return
	for path in [ProfileService.PROFILE_PATH, ProfileService.TEMP_PATH, ProfileService.BACKUP_PATH]:
		if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):
			assert_int(DirAccess.remove_absolute(ProjectSettings.globalize_path(path))).is_equal(OK)
