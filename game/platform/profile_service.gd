class_name ProfileService
extends RefCounted

const SAVE_DIRECTORY := "user://"
const PROFILE_PATH := "user://profile.json"
const TEMP_PATH := "user://profile.tmp"
const BACKUP_PATH := "user://profile.backup"
const LEGACY_PROFILE_PATH := "user://GOGOBRO/profile.json"
const LOCK_DIRECTORY := "user://profile.lock"
const RUN_CODEC := preload("res://game/session/run_state_codec.gd")
const JSON_CODEC := preload("res://game/platform/profile_json_codec.gd")

var last_error: String = ""
var profile_data: Dictionary = {"schema_version": 1, "completed_runs": 0, "best_wave": 0}
var _content: ContentSnapshot
var _write_blocked := false
var _diagnostic := {"error": OK, "path": "", "message": ""}
# Raw decoded input is retained separately; validation never migrates this payload.
var _loaded_profile_payload: Variant = null
var _loaded_profile_exists := false
var _loaded_profile_sha256 := ""


func load_profile(content: ContentSnapshot) -> Error:
	if is_write_blocked():
		return ERR_FILE_CORRUPT
	_content = content
	if _content == null:
		return _reject(_invalid("$", "content snapshot is required"), true)
	if FileAccess.file_exists(PROFILE_PATH) or DirAccess.dir_exists_absolute(PROFILE_PATH):
		var direct := _read_profile(PROFILE_PATH)
		if direct.error != OK:
			if direct.has("payload"):
				_loaded_profile_payload = _detached(direct.payload)
			return _reject(direct, true)
		_loaded_profile_payload = _detached(direct.payload)
		profile_data = _loaded_profile_payload.duplicate(true)
		_loaded_profile_exists = true
		_loaded_profile_sha256 = FileAccess.get_sha256(PROFILE_PATH)
		last_error = ""
		_diagnostic = {"error": OK, "path": "", "message": ""}
		return OK
	if _profile_lock_blocks_load():
		return _reject(_invalid("profile_lock", "profile write is in progress", ERR_BUSY), true)
	if not FileAccess.file_exists(LEGACY_PROFILE_PATH) and not DirAccess.dir_exists_absolute(LEGACY_PROFILE_PATH):
		_loaded_profile_exists = false
		_loaded_profile_sha256 = ""
		return OK
	var legacy := _read_profile(LEGACY_PROFILE_PATH, "legacy_profile")
	if legacy.error != OK:
		return _reject(legacy, true)
	var migration_error := _install_legacy_profile(String(legacy.text), legacy.payload)
	if migration_error == ERR_ALREADY_EXISTS:
		var direct_after_lock := _read_profile(PROFILE_PATH)
		if direct_after_lock.error != OK:
			return _reject(direct_after_lock, true)
		_loaded_profile_payload = _detached(direct_after_lock.payload)
		profile_data = _loaded_profile_payload.duplicate(true)
		_loaded_profile_exists = true
		_loaded_profile_sha256 = FileAccess.get_sha256(PROFILE_PATH)
		last_error = ""
		_diagnostic = {"error": OK, "path": "", "message": ""}
		return OK
	if migration_error != OK:
		return _reject(_invalid("legacy_profile", "cannot install validated legacy profile", migration_error), true)
	_loaded_profile_payload = _detached(legacy.payload)
	profile_data = _loaded_profile_payload.duplicate(true)
	_loaded_profile_exists = true
	_loaded_profile_sha256 = FileAccess.get_sha256(PROFILE_PATH)
	last_error = ""
	_diagnostic = {"error": OK, "path": "", "message": ""}
	return OK


func _read_profile(path: String, source: String = "") -> Dictionary:
	if DirAccess.dir_exists_absolute(path):
		return _profile_read_invalid(source, "$", "cannot read profile file", ERR_FILE_CANT_READ)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _profile_read_invalid(source, "$", "cannot open profile", FileAccess.get_open_error())
	var text := file.get_as_text()
	var read_error := file.get_error()
	file.close()
	if read_error != OK and read_error != ERR_FILE_EOF:
		return _profile_read_invalid(source, "$", "cannot read profile", read_error)
	var decoded := JSON_CODEC.decode(text, _numeric_domain)
	if decoded.error != OK:
		return _profile_read_invalid(source, String(decoded.path), String(decoded.message), decoded.error)
	var payload: Variant = _detached(decoded.value)
	var check := _validate_profile_payload(payload)
	if check.error != OK:
		var invalid := _profile_read_invalid(source, String(check.path), String(check.message), check.error)
		invalid["payload"] = payload
		return invalid
	return {"error": OK, "path": "", "message": "", "text": text, "payload": payload}


func _profile_read_invalid(source: String, path: String, message: String, error: Error) -> Dictionary:
	var qualified_path := path if source.is_empty() else source + ("" if path == "$" else "." + path)
	return _invalid(qualified_path, message, error)


func _install_legacy_profile(text: String, payload: Dictionary) -> Error:
	var lock := _acquire_profile_lock()
	if lock.error != OK:
		last_error = "legacy migration profile lock is busy"
		return lock.error
	# A direct profile that appeared while acquiring ownership is authoritative.
	if FileAccess.file_exists(PROFILE_PATH) or DirAccess.dir_exists_absolute(PROFILE_PATH):
		last_error = "direct profile appeared during legacy migration"
		return _finish_locked(lock, ERR_ALREADY_EXISTS)
	var temp_path := _migration_temp_path(lock.token)
	var temp := FileAccess.open(temp_path, FileAccess.WRITE)
	if temp == null:
		last_error = "cannot open legacy migration temporary profile"
		return _finish_locked(lock, FileAccess.get_open_error())
	temp.store_string(text)
	temp.flush()
	temp.close()
	var verify := FileAccess.open(temp_path, FileAccess.READ)
	if verify == null:
		last_error = "legacy migration temporary verification failed"
		_remove_owned_temp(temp_path)
		return _finish_locked(lock, ERR_FILE_CORRUPT)
	var verified_text := verify.get_as_text()
	verify.close()
	var wire_check := _validate_wire(verified_text, payload)
	if verified_text != text or wire_check.error != OK:
		last_error = "legacy migration temporary profile is invalid"
		_remove_owned_temp(temp_path)
		return _finish_locked(lock, wire_check.error if wire_check.error != OK else ERR_FILE_CORRUPT)
	var hook_error := _before_migration_final_install()
	if hook_error != OK:
		_remove_owned_temp(temp_path)
		return _finish_locked(lock, hook_error)
	if FileAccess.file_exists(PROFILE_PATH) or DirAccess.dir_exists_absolute(PROFILE_PATH):
		last_error = "direct profile appeared during legacy migration"
		_remove_owned_temp(temp_path)
		return _finish_locked(lock, ERR_ALREADY_EXISTS)
	var rename_error := _rename_owned_temp(temp_path, PROFILE_PATH)
	if rename_error != OK:
		last_error = "cannot install validated legacy profile"
		_remove_owned_temp(temp_path)
		return _finish_locked(lock, rename_error)
	var installed := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	var installed_text := installed.get_as_text() if installed != null else ""
	if installed != null:
		installed.close()
	var installed_check := _validate_wire(installed_text, payload)
	if installed_text != text or installed_check.error != OK:
		# Never delete a direct path on uncertainty; it may have changed externally.
		last_error = "installed legacy migration profile verification failed"
		return _finish_locked(lock, installed_check.error if installed_check.error != OK else ERR_FILE_CORRUPT)
	return _finish_locked(lock, OK)


func _before_migration_final_install() -> Error:
	return OK


func _rename_owned_temp(from_path: String, to_path: String) -> Error:
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(from_path), ProjectSettings.globalize_path(to_path))


func _migration_temp_path(token: String) -> String:
	return "user://profile.migrate.%s.tmp" % token


func _remove_owned_temp(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _acquire_profile_lock() -> Dictionary:
	var directory_error := _ensure_directory()
	if directory_error != OK:
		return {"error": directory_error, "token": ""}
	var token := _new_lock_token()
	var claim := _lock_claim_path(token)
	var create_error := DirAccess.make_dir_absolute(ProjectSettings.globalize_path(claim))
	if create_error != OK:
		return {"error": create_error, "token": ""}
	var owner_error := _write_lock_owner(claim.path_join("owner"), token)
	if owner_error != OK:
		var abort_error := _abort_profile_lock_acquisition(token)
		return {"error": abort_error if abort_error != OK else owner_error, "token": ""}
	var expected_owner := _lock_owner_text(token)
	if _read_lock_owner(claim.path_join("owner")) != expected_owner:
		var readback_abort_error := _abort_profile_lock_acquisition(token)
		return {"error": readback_abort_error if readback_abort_error != OK else ERR_CANT_CREATE, "token": ""}
	var publish_error := _rename_owned_lock(claim, LOCK_DIRECTORY)
	if publish_error != OK and _reclaim_stale_profile_lock(token) == OK:
		publish_error = _rename_owned_lock(claim, LOCK_DIRECTORY)
	if publish_error != OK:
		var publish_abort_error := _abort_profile_lock_acquisition(token)
		return {"error": publish_abort_error if publish_abort_error != OK else ERR_BUSY, "token": ""}
	if FileAccess.get_file_as_string(LOCK_DIRECTORY.path_join("owner")) != expected_owner:
		return {"error": ERR_FILE_CANT_READ, "token": ""}
	return {"error": OK, "token": token}


func _abort_profile_lock_acquisition(token: String) -> Error:
	var claim := _lock_claim_path(token)
	var owner := claim.path_join("owner")
	if FileAccess.file_exists(owner):
		var owner_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(owner))
		if owner_error != OK:
			return owner_error
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(claim)):
		return OK
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(claim))


func _finish_locked(lock: Dictionary, result: Error) -> Error:
	var release_error := _release_profile_lock(lock)
	if release_error != OK:
		_reject(_invalid("profile_lock", "profile lock release failed", release_error), true)
		return release_error
	return result


func _write_lock_owner(owner_path: String, token: String) -> Error:
	var owner := FileAccess.open(owner_path, FileAccess.WRITE)
	if owner == null:
		return FileAccess.get_open_error()
	owner.store_string(_lock_owner_text(token))
	owner.flush()
	var write_error := owner.get_error()
	owner.close()
	return write_error


func _read_lock_owner(owner_path: String) -> String:
	return FileAccess.get_file_as_string(owner_path)


func _release_profile_lock(lock: Dictionary) -> Error:
	var token := String(lock.get("token", ""))
	var owner_path := LOCK_DIRECTORY.path_join("owner")
	var expected_owner := _lock_owner_text(token)
	if token.is_empty() or FileAccess.get_file_as_string(owner_path) != expected_owner:
		return ERR_FILE_CANT_READ
	var quarantine := "user://profile.lock.release.%s" % token
	var rename_error := _rename_owned_lock(LOCK_DIRECTORY, quarantine)
	if rename_error != OK:
		return rename_error
	var quarantine_owner := quarantine.path_join("owner")
	if FileAccess.get_file_as_string(quarantine_owner) != expected_owner:
		return ERR_FILE_CANT_READ
	return _remove_owned_lock_quarantine(quarantine)


func _rename_owned_lock(from_path: String, to_path: String) -> Error:
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(from_path), ProjectSettings.globalize_path(to_path))


func _remove_owned_lock_quarantine(path: String) -> Error:
	var owner_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path.path_join("owner")))
	if owner_error != OK:
		return owner_error
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _profile_lock_blocks_load() -> bool:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(LOCK_DIRECTORY)):
		return false
	return _reclaim_stale_profile_lock(_new_lock_token()) != OK


func _reclaim_stale_profile_lock(reclaimer_token: String) -> Error:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(LOCK_DIRECTORY)):
		return OK
	var owner_path := LOCK_DIRECTORY.path_join("owner")
	var owner_text := FileAccess.get_file_as_string(owner_path)
	var owner := _parse_lock_owner(owner_text)
	if owner.error != OK or OS.is_process_running(int(owner.pid)):
		return ERR_BUSY
	var quarantine := "user://profile.lock.stale.%s" % reclaimer_token
	var rename_error := _rename_owned_lock(LOCK_DIRECTORY, quarantine)
	if rename_error != OK:
		return ERR_BUSY
	if FileAccess.get_file_as_string(quarantine.path_join("owner")) != owner_text:
		return ERR_FILE_CANT_READ
	return _remove_owned_lock_quarantine(quarantine)


func _parse_lock_owner(text: String) -> Dictionary:
	if text.is_empty() or not text.begins_with("{"):
		return {"error": ERR_FILE_CORRUPT, "pid": 0, "token": ""}
	var parser := JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary:
		return {"error": ERR_FILE_CORRUPT, "pid": 0, "token": ""}
	var payload: Dictionary = parser.data
	if payload.size() != 3 or not payload.has("schema_version") or not payload.has("pid") or not payload.has("token"):
		return {"error": ERR_FILE_CORRUPT, "pid": 0, "token": ""}
	var raw_schema: Variant = payload.schema_version
	var raw_pid: Variant = payload.pid
	if typeof(raw_schema) not in [TYPE_INT, TYPE_FLOAT] or int(raw_schema) != 1 or float(raw_schema) != 1.0:
		return {"error": ERR_FILE_CORRUPT, "pid": 0, "token": ""}
	if typeof(raw_pid) not in [TYPE_INT, TYPE_FLOAT] or int(raw_pid) <= 0 or float(int(raw_pid)) != float(raw_pid):
		return {"error": ERR_FILE_CORRUPT, "pid": 0, "token": ""}
	if typeof(payload.token) != TYPE_STRING or String(payload.token).is_empty():
		return {"error": ERR_FILE_CORRUPT, "pid": 0, "token": ""}
	return {"error": OK, "pid": int(raw_pid), "token": String(payload.token)}


func _new_lock_token() -> String:
	return "%d-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec(), get_instance_id()]


func _lock_claim_path(token: String) -> String:
	return "user://profile.lock.claim.%s" % token


func _lock_owner_text(token: String) -> String:
	return JSON.stringify({"schema_version": 1, "pid": OS.get_process_id(), "token": token}, "", true, true)


func _before_normal_final_install() -> Error:
	return OK


func save_checkpoint(state: GogoRunState) -> Error:
	var current_error := _validate_current_profile_before_mutation()
	if current_error != OK:
		return current_error
	if state == null:
		return _reject(_invalid("run_checkpoint", "run state is required", ERR_INVALID_PARAMETER))
	var payload := profile_data.duplicate(true)
	payload["run_checkpoint"] = state.to_dictionary()
	payload["best_wave"] = maxi(int(payload.get("best_wave", 0)), state.current_wave)
	var check := _validate_profile_payload(payload)
	if check.error != OK:
		return _reject(check)
	return _atomic_write(payload)


func record_settlement(state: GogoRunState) -> Error:
	var current_error := _validate_current_profile_before_mutation()
	if current_error != OK:
		return current_error
	if state == null:
		return _reject(_invalid("run_checkpoint", "run state is required", ERR_INVALID_PARAMETER))
	# Validate the incoming run before erasing its checkpoint from the candidate.
	var payload := profile_data.duplicate(true)
	payload["run_checkpoint"] = state.to_dictionary()
	var incoming := _validate_profile_payload(payload)
	if incoming.error != OK:
		return _reject(incoming)
	payload["best_wave"] = maxi(int(payload.best_wave), state.current_wave)
	payload["completed_runs"] = int(payload.completed_runs) + 1
	payload.erase("run_checkpoint")
	var check := _validate_profile_payload(payload)
	if check.error != OK:
		return _reject(check)
	return _atomic_write(payload)


func clear_checkpoint() -> Error:
	var current_error := _validate_current_profile_before_mutation()
	if current_error != OK:
		return current_error
	var payload := profile_data.duplicate(true)
	payload.erase("run_checkpoint")
	var check := _validate_profile_payload(payload)
	if check.error != OK:
		return _reject(check)
	return _atomic_write(payload)


func is_write_blocked() -> bool:
	return _write_blocked


func checkpoint_diagnostic() -> Dictionary:
	return _diagnostic.duplicate(true)


func parse_checkpoint(content: ContentSnapshot = null) -> Dictionary:
	if is_write_blocked():
		return _invalid("run_checkpoint", "profile writes are blocked", ERR_FILE_CORRUPT)
	var active_content := content if content != null else _content
	if active_content == null:
		return _invalid("run_checkpoint", "content snapshot is required", ERR_UNCONFIGURED)
	if not profile_data.has("run_checkpoint"):
		return _invalid("run_checkpoint", "checkpoint does not exist", ERR_DOES_NOT_EXIST)
	# The parser receives a deep detached candidate. Callers may restore or mutate
	# it without publishing changes into the loaded profile or touching disk.
	var raw: Variant = _detached(profile_data.get("run_checkpoint"))
	var parsed := GogoRunState.parse_dictionary(raw, active_content)
	if parsed.error != OK:
		return _invalid(
			"run_checkpoint" + ("." + String(parsed.path) if parsed.path != "$" else ""),
			String(parsed.message),
			parsed.error
		)
	return parsed


func _validate_current_profile_before_mutation() -> Error:
	if is_write_blocked():
		return ERR_FILE_CORRUPT
	var check := _validate_profile_payload(profile_data)
	if check.error != OK:
		return _reject(check, true)
	return OK


func validate_content_context(candidate: ContentSnapshot) -> Error:
	var current_error := _validate_current_profile_before_mutation()
	if current_error != OK: return current_error
	if candidate == null: return ERR_INVALID_DATA
	# Candidate incompatibility is not corruption of the still-active profile.
	return _validate_profile_payload(profile_data, candidate).error


func publish_content_context(candidate: ContentSnapshot) -> void:
	# Called only after preflight and successful static activation, before catalog signals.
	_content = candidate


func _validate_profile_payload(payload: Variant, content: ContentSnapshot = null) -> Dictionary:
	if content == null: content = _content
	if content == null:
		return _invalid("$", "content snapshot is required")
	if not payload is Dictionary:
		return _invalid("$", "expected profile object")
	# JSON.stringify substitutes null for NaN. Reject nonfinite extension values as
	# well as schema fields before encoding can conceal their original numeric type.
	var numbers := JSON_CODEC.compare_integers(payload, payload)
	if numbers.error != OK: return numbers
	for key in ["schema_version", "completed_runs", "best_wave"]:
		if not payload.has(key):
			return _invalid(key, "required profile field")
		var checked := RUN_CODEC.checked_integer(payload[key], 1 if key == "schema_version" else 0, 1 if key == "schema_version" else RUN_CODEC.INT64_MAX, key)
		if checked.error != OK:
			return checked
	if payload.has("run_checkpoint"):
		var parsed := GogoRunState.parse_dictionary(payload.run_checkpoint, content)
		if parsed.error != OK:
			return _invalid("run_checkpoint" + ("." + String(parsed.path) if parsed.path != "$" else ""), String(parsed.message))
		return parsed
	return {"state": null, "error": OK, "path": "", "message": ""}


func _reject(check: Dictionary, latch: bool = false) -> Error:
	_diagnostic = {"error": check.error, "path": check.path, "message": check.message}
	last_error = "%s: %s" % [check.path, check.message]
	if latch:
		_write_blocked = true
	return check.error


func _invalid(path: String, message: String, error: Error = ERR_FILE_CORRUPT) -> Dictionary:
	return {"state": null, "error": error, "path": path, "message": message}


func _detached(value: Variant) -> Variant:
	return value.duplicate(true) if value is Dictionary or value is Array else value


func _atomic_write(payload: Dictionary) -> Error:
	var current_error := _validate_current_profile_before_mutation()
	if current_error != OK:
		return current_error
	var check := _validate_profile_payload(payload)
	if check.error != OK:
		return _reject(check)
	# Validate the ACTUAL wire representation before directory/temp/backup operations.
	var encoded := JSON_CODEC.encode(payload, _numeric_domain)
	if encoded.error != OK: return _reject(encoded)
	var text: String = encoded.text
	var wire_check := _validate_wire(text, payload)
	if wire_check.error != OK: return _reject(wire_check)
	last_error = ""
	var lock := _acquire_profile_lock()
	if lock.error != OK:
		return _reject(_invalid("profile_lock", "profile write lock is busy", lock.error), true)
	var baseline_error := _validate_loaded_profile_baseline()
	if baseline_error != OK:
		return _finish_locked(lock, baseline_error)
	var temp := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if temp == null:
		last_error = "cannot open temporary profile"
		return _finish_locked(lock, FileAccess.get_open_error())
	temp.store_string(text)
	temp.flush()
	temp.close()
	var verify := FileAccess.open(TEMP_PATH, FileAccess.READ)
	if verify == null:
		last_error = "temporary profile verification failed"
		return _finish_locked(lock, ERR_FILE_CORRUPT)
	var temp_check := _validate_wire(verify.get_as_text(), payload)
	verify.close()
	if temp_check.error != OK: return _finish_locked(lock, _reject(temp_check))
	if FileAccess.file_exists(BACKUP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(BACKUP_PATH))
	var had_previous := FileAccess.file_exists(PROFILE_PATH)
	if had_previous:
		var previous_text := FileAccess.get_file_as_string(PROFILE_PATH)
		var backup := FileAccess.open(BACKUP_PATH, FileAccess.WRITE)
		if backup == null:
			last_error = "cannot create profile backup"
			return _finish_locked(lock, FileAccess.get_open_error())
		backup.store_string(previous_text)
		backup.flush()
		var backup_write_error := backup.get_error()
		backup.close()
		if backup_write_error != OK or FileAccess.get_file_as_string(BACKUP_PATH) != previous_text:
			last_error = "cannot verify profile backup"
			return _finish_locked(lock, backup_write_error if backup_write_error != OK else ERR_FILE_CORRUPT)
		var backup_check := _validate_wire(previous_text, profile_data)
		if backup_check.error != OK:
			last_error = "profile backup is invalid"
			return _finish_locked(lock, backup_check.error)
	var preinstall_error := _before_normal_final_install()
	if preinstall_error != OK:
		return _finish_locked(lock, preinstall_error)
	var rename_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(TEMP_PATH), ProjectSettings.globalize_path(PROFILE_PATH))
	if rename_error != OK:
		last_error = "cannot install verified profile"
		return _finish_locked(lock, rename_error)
	var installed := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	var installed_text := installed.get_as_text() if installed != null else ""
	var installed_valid: bool = installed != null and installed_text == text and _validate_wire(installed_text, payload).error == OK
	if installed != null:
		installed.close()
	if not installed_valid:
		# We may remove only bytes proven to be this owned temp before restoring.
		if had_previous and installed_text == text:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE_PATH))
			DirAccess.rename_absolute(ProjectSettings.globalize_path(BACKUP_PATH), ProjectSettings.globalize_path(PROFILE_PATH))
		last_error = "installed profile verification failed"
		return _finish_locked(lock, ERR_FILE_CORRUPT)
	if had_previous and FileAccess.file_exists(BACKUP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(BACKUP_PATH))
	profile_data = payload.duplicate(true)
	_loaded_profile_exists = true
	_loaded_profile_sha256 = FileAccess.get_sha256(PROFILE_PATH)
	_diagnostic = {"error": OK, "path": "", "message": ""}
	return _finish_locked(lock, OK)


func _validate_loaded_profile_baseline() -> Error:
	var file_exists := FileAccess.file_exists(PROFILE_PATH)
	var path_is_directory := DirAccess.dir_exists_absolute(PROFILE_PATH)
	var matches := false
	if _loaded_profile_exists:
		matches = file_exists and not path_is_directory \
			and not _loaded_profile_sha256.is_empty() \
			and FileAccess.get_sha256(PROFILE_PATH) == _loaded_profile_sha256
	else:
		matches = not file_exists and not path_is_directory
	if matches:
		return OK
	return _reject(_invalid("profile", "profile changed since load", ERR_BUSY), true)


func _validate_wire(text: String, expected: Dictionary) -> Dictionary:
	var decoded := JSON_CODEC.decode(text, _numeric_domain)
	if decoded.error != OK: return decoded
	var check := _validate_profile_payload(decoded.value)
	if check.error != OK: return check
	return JSON_CODEC.compare_exact_checkpoint_numbers(expected, decoded.value, _numeric_domain)


static func _numeric_domain(segments: Array) -> String:
	if segments.size() == 1:
		return "integer" if segments[0] in ["schema_version", "completed_runs", "best_wave"] else ""
	if segments.is_empty() or segments[0] != "run_checkpoint": return ""
	if segments.size() == 2:
		if segments[1] in ["schema_version", "run_seed", "rng_state", "current_wave", "total_waves", "shop_offer_wave", "shop_offer_initialization_id", "reroll_count", "upgrade_reroll_count", "pending_upgrade_count"]: return "integer"
		return "float" if segments[1] == "elapsed_seconds" else ""
	if segments.size() < 4 or segments[1] != "players" or not segments[2] is int: return ""
	if segments.size() == 4:
		if segments[3] in ["player_index", "level", "xp", "xp_to_next_level", "materials", "next_weapon_instance_id"]: return "integer"
		return "float" if segments[3] in ["current_health", "max_health", "economy_material_remainder"] else ""
	if segments.size() == 5:
		var has_text_key := segments[4] is String or segments[4] is StringName
		if segments[3] == "weapon_levels" and has_text_key: return "integer"
		if segments[3] in ["base_stats", "final_stats"] and has_text_key: return "float"
	if segments.size() == 6 and segments[3] == "weapons" and segments[4] is int and segments[5] in ["instance_id", "quality"]: return "integer"
	return ""


func _ensure_directory() -> Error:
	var absolute := ProjectSettings.globalize_path(SAVE_DIRECTORY)
	return DirAccess.make_dir_recursive_absolute(absolute)
