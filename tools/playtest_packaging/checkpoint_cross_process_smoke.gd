extends SceneTree

# External source/PCK fixture. No project class is preloaded or type-annotated
# before isolation_guard() proves that every user/profile path is synthetic.

const PROFILE_PATH := "user://profile.json"
const TEMP_PROFILE_PATH := "user://profile.tmp"
const BACKUP_PROFILE_PATH := "user://profile.backup"
const PROFILE_LOCK_PATH := "user://profile.lock"
const STATE_ARTIFACT_NAME := "checkpoint-cross-process-a-state.bin"
const RAW_ARTIFACT_NAME := "checkpoint-cross-process-a-raw.bin"
# ProfileService persists JSON with sort_keys=true, so the raw-wire contract is
# deliberately alphabetical. Runtime Dictionaries compare exact key types/values
# without insertion-order semantics; Arrays retain strict order via the typed artifact.
const RAW_RUN_FIELD_ORDER := ["current_wave", "difficulty_id", "elapsed_seconds", "ended", "endless",
	"locked_shop_offer_ids", "pending_upgrade_count", "phase", "players", "reroll_count",
	"rng_state", "run_seed", "schema_version", "shop_offer_ids",
	"shop_offer_initialization_id", "shop_offer_initialized", "shop_offer_wave", "total_waves",
	"upgrade_reroll_count", "won", "zone_id"]
const RAW_PLAYER_FIELD_ORDER := ["base_stats", "character_id", "current_health",
	"economy_material_remainder", "final_stats", "item_ids", "level", "materials", "max_health",
	"next_weapon_instance_id", "player_index", "upgrade_ids", "weapons", "xp", "xp_to_next_level"]
const RAW_WEAPON_FIELD_ORDER := ["content_id", "instance_id", "quality"]

var failures: Array[String] = []
var options := {}
var app: Node


func _initialize() -> void:
	options = _parse_options(OS.get_cmdline_user_args())
	if not isolation_guard():
		_finish()
		return
	call_deferred("_run")


func _run() -> void:
	if options.role == "A":
		await _run_writer()
	elif options.role == "B":
		await _run_reader()
	elif options.role == "C":
		await _run_crash_lock_holder()
	else:
		await _run_crash_lock_recovery()
	_finish()


func isolation_guard() -> bool:
	_check(options.keys() == ["role", "mode", "subject_root"], "exact role/mode/subject options")
	if not failures.is_empty():
		_print_guard(false, {})
		return false
	var role: String = options.role
	var mode: String = options.mode
	var subject_root: String = options.subject_root
	_check(role in ["A", "B", "C", "D"], "role A, B, C, or D")
	_check(mode in ["source", "pck"], "mode source or pck")
	var appdata := OS.get_environment("APPDATA")
	var localappdata := OS.get_environment("LOCALAPPDATA")
	var temp := OS.get_environment("TEMP")
	var tmp := OS.get_environment("TMP")
	var userprofile := OS.get_environment("USERPROFILE")
	var expected_appdata := OS.get_environment("GOGOBRO_TEST_EXPECTED_APPDATA")
	var expected_localappdata := OS.get_environment("GOGOBRO_TEST_EXPECTED_LOCALAPPDATA")
	var expected_temp := OS.get_environment("GOGOBRO_TEST_EXPECTED_TEMP")
	var expected_tmp := OS.get_environment("GOGOBRO_TEST_EXPECTED_TMP")
	var expected_userprofile := OS.get_environment("GOGOBRO_TEST_EXPECTED_USERPROFILE")
	var expected_user_data := OS.get_environment("GOGOBRO_TEST_EXPECTED_USER_DATA_DIR")
	var actual_user_data := OS.get_user_data_dir()
	var paths := [appdata, localappdata, temp, tmp, userprofile, expected_appdata,
		expected_localappdata, expected_temp, expected_tmp, expected_userprofile,
		expected_user_data, actual_user_data, subject_root]
	for path in paths:
		_check(not String(path).is_empty() and String(path).is_absolute_path(), "absolute guarded path")
	_check(_same_path(appdata, expected_appdata), "APPDATA expected binding")
	_check(_same_path(localappdata, expected_localappdata), "LOCALAPPDATA expected binding")
	_check(_same_path(temp, expected_temp), "TEMP expected binding")
	_check(_same_path(tmp, expected_tmp), "TMP expected binding")
	_check(_same_path(userprofile, expected_userprofile), "USERPROFILE expected binding")
	_check(_same_path(actual_user_data, expected_user_data), "user data expected binding")
	_check(_same_path(temp, tmp), "TEMP/TMP exact binding")
	_check(_same_path(expected_user_data, appdata.path_join("GOGOBRO")), "custom user dir relation")
	var fresh_root := _canonical(appdata).get_base_dir()
	_check(_same_path(_canonical(localappdata).get_base_dir(), fresh_root), "LOCALAPPDATA fresh root")
	_check(_same_path(_canonical(temp).get_base_dir(), fresh_root), "TEMP fresh root")
	_check(_same_path(_canonical(userprofile).get_base_dir(), fresh_root), "USERPROFILE fresh root")
	_check(not _within_or_equal(fresh_root, subject_root)
		and not _within_or_equal(subject_root, fresh_root),
		"synthetic root outside subject")
	_check(not _within_or_equal(expected_user_data, subject_root)
		and not _within_or_equal(subject_root, expected_user_data),
		"synthetic profile outside subject")
	var receipt := {
		"schema_version": 1,
		"phase": "before-project-profile-read",
		"pid": OS.get_process_id(),
		"role": role,
		"mode": mode,
		"subject_root": subject_root,
		"appdata": appdata,
		"localappdata": localappdata,
		"temp": temp,
		"tmp": tmp,
		"userprofile": userprofile,
		"user_data": actual_user_data,
		"expected_appdata": expected_appdata,
		"expected_localappdata": expected_localappdata,
		"expected_temp": expected_temp,
		"expected_tmp": expected_tmp,
		"expected_userprofile": expected_userprofile,
		"expected_user_data": expected_user_data,
	}
	if not failures.is_empty():
		_print_guard(false, receipt)
		return false
	# user:// is touched only after every actual/expected OS path agrees.
	var presence := _profile_presence()
	receipt["profile_before"] = presence
	receipt["lock_before"] = DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(PROFILE_LOCK_PATH))
	if role == "A":
		_check(presence == {"profile": false, "temporary": false, "backup": false},
			"A begins without any profile file")
		_check(not FileAccess.file_exists(_state_artifact_path()), "A state artifact absent")
		_check(not FileAccess.file_exists(_raw_artifact_path()), "A raw artifact absent")
	else:
		_check(presence == {"profile": true, "temporary": false, "backup": false},
			"role begins with only A profile")
		_check(FileAccess.file_exists(_state_artifact_path()), "role sees A state artifact")
		_check(FileAccess.file_exists(_raw_artifact_path()), "role sees A raw artifact")
	_check(bool(receipt.lock_before) == (role == "D"), "only D begins with the crashed C lock")
	_print_guard(failures.is_empty(), receipt)
	return failures.is_empty()


func _run_writer() -> void:
	app = load("res://game/app/app_root.tscn").instantiate()
	root.add_child(app)
	await process_frame
	_check(app.boot_result != null and app.boot_result.is_ok(), "A application boot")
	_check(app.current_session == null, "A has no session before new run")
	if not failures.is_empty():
		return
	app.begin_selection()
	app.selection_draft.seed = 9007199254740993
	app.selection_draft.character_id = &"character.niko:character/niko"
	app.selection_draft.weapon_id = &"weapon.training_blaster:weapon/training_blaster"
	_check(app.create_session_from_draft() == OK, "A creates real new run")
	if not failures.is_empty():
		return
	var session = app.current_session
	_check(session.run_state.current_wave == 1 and session.run_state.phase == &"combat", "A W1 combat boundary")
	# Prove create_session itself installed W1 on disk before the later explicit
	# RNG-advanced save. An in-memory profile check cannot earn this claim.
	var profile_type = load("res://game/platform/profile_service.gd")
	var w1_presence := _profile_presence()
	var w1_sha := FileAccess.get_sha256(PROFILE_PATH).to_upper()
	var w1_reader = profile_type.new()
	var w1_load_error: int = w1_reader.load_profile(app.content_snapshot)
	_check(w1_presence == {"profile": true, "temporary": false, "backup": false},
		"A immediate W1 disk presence")
	_check(w1_sha.length() == 64, "A immediate W1 disk SHA")
	_check(w1_load_error == OK, "A immediate W1 independent disk load")
	var w1_parsed: Dictionary = {}
	if w1_load_error == OK:
		w1_parsed = w1_reader.parse_checkpoint()
	_check(w1_parsed.get("error", ERR_UNAVAILABLE) == OK, "A immediate W1 detached disk parse")
	if w1_parsed.get("error", ERR_UNAVAILABLE) == OK:
		var w1_state = w1_parsed.state
		_check(w1_state.schema_version == 3 and w1_state.current_wave == 1 and w1_state.phase == &"combat",
			"A immediate W1 schema/phase")
		_check(w1_state.run_seed == session.run_state.run_seed and w1_state.rng_state == session.rng.state,
			"A immediate W1 seed/RNG")
		_check(_variant_exact(session.run_state.to_dictionary(), w1_state.to_dictionary(), "$w1"),
			"A immediate W1 full state")
	if not failures.is_empty():
		return
	var w1_disk_immediate := true
	# Advance the canonical RNG before the explicit save so persistence must carry
	# the generator state, not merely reconstruct the original seed.
	session.rng.randi()
	session.rng.randf()
	session.rng.randi_range(7, 7007)
	_check(_configure_rich_w22_boundary(session), "A configures legal rich W22 combat boundary")
	if not failures.is_empty():
		return
	_check(app.save_checkpoint() == OK, "A schema3 checkpoint save")
	if not failures.is_empty():
		return
	var live_expected: Dictionary = session.run_state.to_dictionary()
	_check(live_expected.schema_version == 3, "A schema3")
	_check(live_expected.current_wave == 22 and live_expected.total_waves == 20
		and live_expected.endless and live_expected.phase == "combat", "A rich W22 boundary")
	_check(typeof(live_expected.run_seed) == TYPE_INT and live_expected.run_seed == 9007199254740993, "A exact run seed")
	_check(typeof(live_expected.rng_state) == TYPE_INT and live_expected.rng_state == session.rng.state, "A exact RNG state")
	var reader = profile_type.new()
	_check(reader.load_profile(app.content_snapshot) == OK, "A independent disk reader")
	var parsed: Dictionary = reader.parse_checkpoint()
	_check(parsed.error == OK, "A detached disk parse")
	var expected: Dictionary = {}
	if parsed.error == OK:
		expected = parsed.state.to_dictionary()
		_check(_variant_exact(live_expected, expected, "$"), "A live/disk exact variant")
	if expected.is_empty():
		return
	var raw: Dictionary = reader.profile_data.run_checkpoint
	_check(_canonical_raw_shape(raw), "A canonical raw field/type/order")
	var bytes := var_to_bytes(expected)
	var raw_bytes := var_to_bytes(raw)
	_check(_write_artifact(_state_artifact_path(), bytes), "A state artifact write")
	_check(_write_artifact(_raw_artifact_path(), raw_bytes), "A raw artifact write")
	var sha := FileAccess.get_sha256(PROFILE_PATH).to_upper()
	var presence := _profile_presence()
	_check(sha.length() == 64, "A profile SHA")
	_check(presence == {"profile": true, "temporary": false, "backup": false}, "A profile sidecars absent")
	if failures.is_empty():
		print("CROSS_A_SAVED " + JSON.stringify({
			"pid": OS.get_process_id(),
			"schema": expected.schema_version,
			"wave": expected.current_wave,
			"phase": expected.phase,
			"run_seed": str(expected.run_seed),
			"rng_state": str(expected.rng_state),
			"rng_next": _rng_sequence(expected.run_seed, expected.rng_state),
			"state_digest": _variant_digest(expected),
			"state_bytes_sha256": _bytes_digest(bytes),
			"raw_digest": _variant_digest(raw),
			"raw_bytes_sha256": _bytes_digest(raw_bytes),
			"profile_sha256": sha,
			"profile_presence": presence,
			"w1_disk_immediate": w1_disk_immediate,
			"w1_profile_sha256": w1_sha,
			"w1_profile_presence": w1_presence,
			"rich_w22_boundary_exact": true,
			"rich_summary": _rich_summary(expected),
			"variant_type_array_order_exact": true,
			"rng_state_exact": true,
			"wave_boundary_restart": true,
			"mid_wave_claim": false,
		}))


func _run_reader() -> void:
	var profile_sha_preboot := FileAccess.get_sha256(PROFILE_PATH).to_upper()
	var raw_wire_text := FileAccess.get_file_as_string(PROFILE_PATH)
	_check(not raw_wire_text.is_empty(), "B raw profile bytes before boot")
	var state_bytes := FileAccess.get_file_as_bytes(_state_artifact_path())
	# Godot 4.7 keeps object deserialization on the separate
	# bytes_to_var_with_objects API; this verifier intentionally uses the safe decoder.
	var expected: Variant = bytes_to_var(state_bytes)
	_check(expected is Dictionary, "B expected state artifact")
	if not expected is Dictionary:
		return
	var raw_bytes := FileAccess.get_file_as_bytes(_raw_artifact_path())
	var expected_raw: Variant = bytes_to_var(raw_bytes)
	_check(expected_raw is Dictionary, "B expected raw artifact")
	if not expected_raw is Dictionary:
		return
	app = load("res://game/app/app_root.tscn").instantiate()
	root.add_child(app)
	await process_frame
	_check(app.boot_result != null and app.boot_result.is_ok(), "B application boot")
	_check(app.current_session == null, "B boot publishes no session")
	if not failures.is_empty():
		return
	_check(app.profile_service.profile_data.has("run_checkpoint"), "B decoded raw checkpoint")
	if not app.profile_service.profile_data.has("run_checkpoint"):
		return
	# ProfileService's exact-integer decoder is the authoritative raw-wire view;
	# built-in JSON.parse_string is intentionally not used for int64 evidence.
	var raw: Dictionary = app.profile_service.profile_data.run_checkpoint
	_check(raw.schema_version == 3, "B raw schema3")
	_check(typeof(raw.run_seed) == TYPE_INT, "B raw run seed integer")
	_check(typeof(raw.rng_state) == TYPE_INT, "B raw RNG integer")
	_check(_canonical_raw_shape(raw), "B canonical raw field/type/order")
	_check(_variant_exact(expected_raw, raw, "$raw"), "B/A raw exact variant")
	var profile_sha_postboot := FileAccess.get_sha256(PROFILE_PATH).to_upper()
	var parsed: Dictionary = app.profile_service.parse_checkpoint()
	_check(parsed.error == OK, "B detached profile parse")
	if parsed.error == OK:
		_check(_variant_exact(expected, parsed.state.to_dictionary(), "$"), "B raw-parsed/A exact variant")
	var button := app.get_node_or_null("SceneHost/MainMenuScreen/ContentRoot/Body/MenuActions/ContinueButton") as Button
	_check(button != null and button.is_visible_in_tree() and not button.disabled, "B real ContinueButton")
	if button == null or not button.is_visible_in_tree() or button.disabled or not failures.is_empty():
		return
	var published := [0]
	var captured := [{}]
	var captured_rng := [0]
	app.session_created.connect(func(session) -> void:
		published[0] += 1
		captured[0] = session.run_state.to_dictionary()
		captured_rng[0] = session.rng.state
	)
	button.pressed.emit()
	_check(published[0] == 1, "B publishes one resumed session")
	_check(app.current_session != null, "B current session published")
	_check(app.scene_flow.current_route() == &"combat", "B combat route")
	if not failures.is_empty() or app.current_session == null:
		return
	_check(_variant_exact(expected, captured[0], "$"), "B captured/A exact variant")
	_check(_variant_exact(expected, app.current_session.run_state.to_dictionary(), "$"), "B live/A exact variant")
	_check(captured_rng[0] == expected.rng_state and app.current_session.rng.state == expected.rng_state,
		"B exact RNG publication")
	var combat := app.get_node_or_null("SceneHost/CombatScreen")
	var world = combat.get("world") if combat != null else null
	_check(world != null and world.running, "B live combat world")
	if world == null or not world.running:
		return
	var wave_runtime: Variant = world.get("wave_runtime")
	_check(wave_runtime != null, "B resumed wave runtime")
	if wave_runtime == null:
		return
	var authored_wave: Variant = wave_runtime.get("wave")
	_check(authored_wave != null, "B resolved authored wave")
	if authored_wave == null:
		return
	_check(authored_wave.wave_number == expected.current_wave, "B authored resumed wave")
	var profile_sha_postcontinue := FileAccess.get_sha256(PROFILE_PATH).to_upper()
	var presence := _profile_presence()
	_check(profile_sha_preboot == profile_sha_postboot and profile_sha_postboot == profile_sha_postcontinue,
		"B read/resume profile SHA unchanged")
	_check(presence == {"profile": true, "temporary": false, "backup": false}, "B profile sidecars absent")
	_check(str(raw.run_seed) == str(expected.run_seed) and str(raw.rng_state) == str(expected.rng_state),
		"B raw/runtime integer identity")
	if failures.is_empty():
		print("CROSS_B_RESUMED " + JSON.stringify({
			"pid": OS.get_process_id(),
			"schema": raw.schema_version,
			"wave": app.current_session.run_state.current_wave,
			"phase": String(app.current_session.run_state.phase),
			"route": String(app.scene_flow.current_route()),
			"world_running": world.running,
			"published_count": published[0],
			"continue_button_pressed": true,
			"ui_control_signal": true,
			"os_input": false,
			"run_seed": str(raw.run_seed),
			"rng_state": str(captured_rng[0]),
			"rng_next": _rng_sequence(expected.run_seed, captured_rng[0]),
			"state_digest": _variant_digest(captured[0]),
			"state_bytes_sha256": _bytes_digest(var_to_bytes(captured[0])),
			"raw_digest": _variant_digest(raw),
			"raw_bytes_sha256": _bytes_digest(var_to_bytes(raw)),
			"profile_sha_preboot": profile_sha_preboot,
			"profile_sha_postboot": profile_sha_postboot,
			"profile_sha_postcontinue": profile_sha_postcontinue,
			"profile_presence": presence,
			"rich_w22_boundary_exact": true,
			"rich_summary": _rich_summary(captured[0]),
			"variant_type_array_order_exact": true,
			"rng_state_exact": true,
			"wave_boundary_restart": true,
			"mid_wave_claim": false,
		}))


func _run_crash_lock_holder() -> void:
	app = load("res://game/app/app_root.tscn").instantiate()
	root.add_child(app)
	await process_frame
	_check(app.boot_result != null and app.boot_result.is_ok(), "C application boot")
	if not failures.is_empty():
		return
	var lock: Dictionary = app.profile_service._acquire_profile_lock()
	_check(lock.error == OK and not String(lock.token).is_empty(), "C acquires profile lock")
	var owner_text := FileAccess.get_file_as_string(PROFILE_LOCK_PATH.path_join("owner"))
	var owner: Variant = JSON.parse_string(owner_text)
	_check(owner is Dictionary and int(owner.get("schema_version", 0)) == 1, "C lock owner schema")
	_check(owner is Dictionary and int(owner.get("pid", 0)) == OS.get_process_id(), "C lock owner PID")
	_check(owner is Dictionary and String(owner.get("token", "")) == String(lock.token), "C lock owner token")
	if not failures.is_empty():
		return
	print("CROSS_C_LOCK_HELD " + JSON.stringify({
		"pid": OS.get_process_id(),
		"token": String(lock.token),
		"owner_sha256": owner_text.sha256_text().to_upper(),
	}))
	while true:
		await process_frame


func _run_crash_lock_recovery() -> void:
	var profile_sha_before := FileAccess.get_sha256(PROFILE_PATH).to_upper()
	var owner_text := FileAccess.get_file_as_string(PROFILE_LOCK_PATH.path_join("owner"))
	var stale_owner: Variant = JSON.parse_string(owner_text)
	_check(stale_owner is Dictionary, "D reads structured stale owner")
	var stale_pid := int(stale_owner.get("pid", 0)) if stale_owner is Dictionary else 0
	_check(stale_pid > 0 and not OS.is_process_running(stale_pid), "D proves crashed C PID absent")
	app = load("res://game/app/app_root.tscn").instantiate()
	root.add_child(app)
	await process_frame
	_check(app.boot_result != null and app.boot_result.is_ok(), "D application boot")
	if not failures.is_empty():
		return
	var parsed: Dictionary = app.profile_service.parse_checkpoint()
	_check(parsed.error == OK, "D parses A checkpoint")
	if parsed.error != OK:
		return
	_check(app.profile_service.save_checkpoint(parsed.state) == OK, "D saves after reclaiming crashed C lock")
	var profile_sha_after := FileAccess.get_sha256(PROFILE_PATH).to_upper()
	_check(profile_sha_before == profile_sha_after, "D recovery preserves canonical profile bytes")
	_check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(PROFILE_LOCK_PATH)), "D releases recovered lock")
	_check(_profile_presence() == {"profile": true, "temporary": false, "backup": false}, "D leaves no profile sidecars")
	if failures.is_empty():
		print("CROSS_D_LOCK_RECOVERED " + JSON.stringify({
			"pid": OS.get_process_id(),
			"stale_owner_pid": stale_pid,
			"profile_sha_before": profile_sha_before,
			"profile_sha_after": profile_sha_after,
			"lock_recovered": true,
		}))


func _configure_rich_w22_boundary(session: Variant) -> bool:
	var state = session.run_state
	var player = state.player()
	var snapshot = session.content_snapshot
	var weapons: Array = snapshot.all(&"weapon")
	var items: Array = snapshot.all(&"item")
	var upgrades: Array = snapshot.all(&"upgrade")
	if player == null or weapons.size() < 6 or items.size() < 4 or upgrades.size() < 4:
		return false

	var records: Array[Dictionary] = []
	var qualities := [1, 2, 3, 4, 2, 3]
	for index in 6:
		records.append({
			"instance_id": (index + 1) * 11,
			"content_id": weapons[index].content_id,
			"quality": qualities[index],
		})
	var inventory_result: Dictionary = load("res://game/session/weapon_inventory.gd").parse_records(
		records,
		77,
		snapshot
	)
	if inventory_result.error != OK:
		return false
	player.weapon_inventory = inventory_result.inventory
	player.level = 12
	player.xp = 37
	player.xp_to_next_level = 125
	player.materials = 98765
	player.economy_material_remainder = 0.375
	player.current_health = 37.25
	player.max_health = 64.5
	player.base_stats = {
		&"max_health": 64.5,
		&"movement_speed": 333.25,
		&"pickup_range": 141.5,
		&"armor": 7.0,
		&"health_regen": 1.75,
		&"damage_multiplier": 1.625,
		&"attack_speed": 1.375,
		&"dodge": 0.125,
	}
	player.final_stats = player.base_stats.duplicate(true)
	player.final_stats[&"critical_chance"] = 0.225
	player.final_stats[&"explosion_damage_multiplier"] = 1.4
	var item_ids: Array[StringName] = []
	var upgrade_ids: Array[StringName] = []
	for index in 4:
		item_ids.append(items[index].content_id)
		upgrade_ids.append(upgrades[index].content_id)
	player.item_ids = item_ids
	player.upgrade_ids = upgrade_ids

	state.current_wave = 22
	state.total_waves = 20
	state.phase = &"combat"
	state.won = false
	state.ended = false
	state.endless = true
	var locked_shop_offer_ids: Array[StringName] = []
	locked_shop_offer_ids.append(items[0].content_id)
	locked_shop_offer_ids.append(weapons[0].content_id)
	state.locked_shop_offer_ids = locked_shop_offer_ids
	state.shop_offer_wave = 21
	var shop_offer_ids: Array[StringName] = []
	shop_offer_ids.append(items[0].content_id)
	shop_offer_ids.append(weapons[0].content_id)
	shop_offer_ids.append(&"")
	shop_offer_ids.append(items[1].content_id)
	state.shop_offer_ids = shop_offer_ids
	state.shop_offer_initialized = true
	state.shop_offer_initialization_id = 41
	state.reroll_count = 5
	state.upgrade_reroll_count = 3
	state.pending_upgrade_count = 0
	state.elapsed_seconds = 987.625
	return true


func _rich_summary(state: Dictionary) -> Dictionary:
	var player: Dictionary = state.players[0]
	return {
		"wave": state.current_wave,
		"total_waves": state.total_waves,
		"phase": String(state.phase),
		"endless": state.endless,
		"elapsed_seconds": str(state.elapsed_seconds),
		"weapon_count": player.weapons.size(),
		"item_count": player.item_ids.size(),
		"upgrade_count": player.upgrade_ids.size(),
		"shop_offer_wave": state.shop_offer_wave,
		"shop_offer_count": state.shop_offer_ids.size(),
		"shop_initialized": state.shop_offer_initialized,
		"locked_count": state.locked_shop_offer_ids.size(),
		"level": player.level,
		"materials": player.materials,
		"economy_remainder": str(player.economy_material_remainder),
		"current_health": str(player.current_health),
		"max_health": str(player.max_health),
		"base_stat_count": player.base_stats.size(),
		"final_stat_count": player.final_stats.size(),
		"shop_initialization_id": state.shop_offer_initialization_id,
		"reroll_count": state.reroll_count,
		"upgrade_reroll_count": state.upgrade_reroll_count,
		"pending_upgrade_count": state.pending_upgrade_count,
	}


func _variant_exact(expected: Variant, actual: Variant, path: String) -> bool:
	if typeof(expected) != typeof(actual):
		_check(false, path + " type")
		return false
	if expected is Dictionary:
		if not expected.is_same_typed(actual):
			_check(false, path + " dictionary typed metadata")
			return false
		var expected_keys: Array = expected.keys()
		var actual_keys: Array = actual.keys()
		if expected_keys.size() != actual_keys.size():
			_check(false, path + " dictionary size")
			return false
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
			if found_index < 0:
				_check(false, path + "." + str(expected_key) + " exact key")
				return false
			matched_indices.append(found_index)
			var actual_key: Variant = actual_keys[found_index]
			if not _variant_exact(expected[expected_key], actual[actual_key], path + "." + str(expected_key)):
				return false
		return true
	if expected is Array:
		if not expected.is_same_typed(actual):
			_check(false, path + " array typed metadata")
			return false
		if expected.size() != actual.size():
			_check(false, path + " array size")
			return false
		for index in expected.size():
			if not _variant_exact(expected[index], actual[index], "%s[%d]" % [path, index]):
				return false
		return true
	if var_to_bytes(expected) != var_to_bytes(actual):
		_check(false, path + " leaf value")
		return false
	return true


func _variant_digest(value: Variant) -> String:
	return _bytes_digest(var_to_bytes(value))


func _canonical_raw_shape(raw: Dictionary) -> bool:
	if not _string_key_order(raw, RAW_RUN_FIELD_ORDER):
		return false
	if not raw.players is Array or raw.players.size() != 1 or not raw.players[0] is Dictionary:
		_check(false, "raw player container")
		return false
	var player: Dictionary = raw.players[0]
	if not _string_key_order(player, RAW_PLAYER_FIELD_ORDER):
		return false
	if not player.weapons is Array:
		_check(false, "raw weapons container")
		return false
	for weapon in player.weapons:
		if not weapon is Dictionary or not _string_key_order(weapon, RAW_WEAPON_FIELD_ORDER):
			_check(false, "raw weapon field order")
			return false
	return true


func _string_key_order(value: Dictionary, expected: Array) -> bool:
	var keys: Array = value.keys()
	if keys.size() != expected.size():
		_check(false, "raw field count")
		return false
	for index in keys.size():
		if typeof(keys[index]) != TYPE_STRING or keys[index] != expected[index]:
			_check(false, "raw field key type/order")
			return false
	return true


func _bytes_digest(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if hashing.update(bytes) != OK:
		return ""
	return hashing.finish().hex_encode().to_upper()


func _rng_sequence(seed: int, state: int) -> Array[String]:
	var probe := RandomNumberGenerator.new()
	probe.seed = seed
	probe.state = state
	var result: Array[String] = []
	for _index in 3:
		result.append(str(probe.randi()))
	return result


func _parse_options(args: PackedStringArray) -> Dictionary:
	if args.size() != 6:
		return {}
	var parsed := {}
	for index in range(0, args.size(), 2):
		var key := String(args[index]).trim_prefix("--").replace("-", "_")
		if not String(args[index]).begins_with("--") or parsed.has(key):
			return {}
		parsed[key] = String(args[index + 1]).replace("\\", "/").simplify_path() if key == "subject_root" else String(args[index + 1])
	return parsed


func _state_artifact_path() -> String:
	return OS.get_environment("TEMP").path_join(STATE_ARTIFACT_NAME)


func _raw_artifact_path() -> String:
	return OS.get_environment("TEMP").path_join(RAW_ARTIFACT_NAME)


func _write_artifact(path: String, bytes: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.flush()
	var error := file.get_error()
	file.close()
	return error == OK


func _profile_presence() -> Dictionary:
	return {
		"profile": FileAccess.file_exists(PROFILE_PATH),
		"temporary": FileAccess.file_exists(TEMP_PROFILE_PATH),
		"backup": FileAccess.file_exists(BACKUP_PROFILE_PATH),
	}


func _same_path(left: String, right: String) -> bool:
	return _canonical(left).nocasecmp_to(_canonical(right)) == 0


func _within_or_equal(path: String, root_path: String) -> bool:
	var candidate := _canonical(path).to_lower()
	var root_value := _canonical(root_path).to_lower()
	return candidate == root_value or candidate.begins_with(root_value + "/")


func _canonical(path: String) -> String:
	return path.replace("\\", "/").simplify_path().trim_suffix("/")


func _print_guard(ok: bool, receipt: Dictionary) -> void:
	print(("CROSS_ISOLATION_OK " if ok else "CROSS_ISOLATION_FAIL ") + JSON.stringify(receipt))


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
		print("CROSS_FAILED " + label)


func _finish() -> void:
	if app != null and is_instance_valid(app):
		app.free()
	print("CROSS_PROCESS_RESULT failures=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)
