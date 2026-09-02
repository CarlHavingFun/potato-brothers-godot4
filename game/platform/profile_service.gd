class_name ProfileService
extends RefCounted

const SAVE_DIRECTORY := "user://GOGOBRO"
const PROFILE_PATH := SAVE_DIRECTORY + "/profile.json"
const TEMP_PATH := SAVE_DIRECTORY + "/profile.tmp"
const BACKUP_PATH := SAVE_DIRECTORY + "/profile.backup"
const RUN_CODEC := preload("res://game/session/run_state_codec.gd")
const JSON_CODEC := preload("res://game/platform/profile_json_codec.gd")

var last_error: String = ""
var profile_data: Dictionary = {"schema_version": 1, "completed_runs": 0, "best_wave": 0}
var _content: ContentSnapshot
var _write_blocked := false
var _diagnostic := {"error": OK, "path": "", "message": ""}
# Raw decoded input is retained separately; validation never migrates this payload.
var _loaded_profile_payload: Variant = null


func load_profile(content: ContentSnapshot) -> Error:
	if is_write_blocked():
		return ERR_FILE_CORRUPT
	_content = content
	if _content == null:
		return _reject(_invalid("$", "content snapshot is required"), true)
	if DirAccess.dir_exists_absolute(PROFILE_PATH):
		return _reject(_invalid("$", "cannot read profile file", ERR_FILE_CANT_READ), true)
	if not FileAccess.file_exists(PROFILE_PATH):
		return OK
	var file := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	if file == null:
		return _reject(_invalid("$", "cannot open profile", FileAccess.get_open_error()), true)
	var text := file.get_as_text()
	var read_error := file.get_error()
	file.close()
	if read_error != OK and read_error != ERR_FILE_EOF:
		return _reject(_invalid("$", "cannot read profile", read_error), true)
	var decoded := JSON_CODEC.decode(text, _numeric_domain)
	if decoded.error != OK:
		return _reject(decoded, true)
	_loaded_profile_payload = _detached(decoded.value)
	var check := _validate_profile_payload(_loaded_profile_payload)
	if check.error != OK:
		return _reject(check, true)
	profile_data = _loaded_profile_payload.duplicate(true)
	last_error = ""
	_diagnostic = {"error": OK, "path": "", "message": ""}
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
	var text := JSON.stringify(payload, "\t", true, true)
	var wire_check := _validate_wire(text, payload)
	if wire_check.error != OK: return _reject(wire_check)
	last_error = ""
	var directory_error := _ensure_directory()
	if directory_error != OK:
		return directory_error
	var temp := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if temp == null:
		last_error = "cannot open temporary profile"
		return FileAccess.get_open_error()
	temp.store_string(text)
	temp.flush()
	temp.close()
	var verify := FileAccess.open(TEMP_PATH, FileAccess.READ)
	if verify == null:
		last_error = "temporary profile verification failed"
		return ERR_FILE_CORRUPT
	var temp_check := _validate_wire(verify.get_as_text(), payload)
	verify.close()
	if temp_check.error != OK: return _reject(temp_check)
	if FileAccess.file_exists(BACKUP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(BACKUP_PATH))
	var had_previous := FileAccess.file_exists(PROFILE_PATH)
	if had_previous:
		var backup_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(PROFILE_PATH), ProjectSettings.globalize_path(BACKUP_PATH))
		if backup_error != OK:
			last_error = "cannot back up existing profile"
			return backup_error
	var rename_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(TEMP_PATH), ProjectSettings.globalize_path(PROFILE_PATH))
	if rename_error != OK:
		if had_previous:
			DirAccess.rename_absolute(ProjectSettings.globalize_path(BACKUP_PATH), ProjectSettings.globalize_path(PROFILE_PATH))
		last_error = "cannot install verified profile"
		return rename_error
	var installed := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	var installed_valid: bool = installed != null and _validate_wire(installed.get_as_text(), payload).error == OK
	if installed != null:
		installed.close()
	if not installed_valid:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE_PATH))
		if had_previous:
			DirAccess.rename_absolute(ProjectSettings.globalize_path(BACKUP_PATH), ProjectSettings.globalize_path(PROFILE_PATH))
		last_error = "installed profile verification failed"
		return ERR_FILE_CORRUPT
	if had_previous and FileAccess.file_exists(BACKUP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(BACKUP_PATH))
	profile_data = payload.duplicate(true)
	_diagnostic = {"error": OK, "path": "", "message": ""}
	return OK


func _validate_wire(text: String, expected: Dictionary) -> Dictionary:
	var decoded := JSON_CODEC.decode(text, _numeric_domain)
	if decoded.error != OK: return decoded
	var check := _validate_profile_payload(decoded.value)
	if check.error != OK: return check
	return JSON_CODEC.compare_integers(expected, decoded.value)


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
		if segments[3] == "weapon_levels" and segments[4] is String: return "integer"
		if segments[3] in ["base_stats", "final_stats"] and segments[4] is String: return "float"
	if segments.size() == 6 and segments[3] == "weapons" and segments[4] is int and segments[5] in ["instance_id", "quality"]: return "integer"
	return ""


func _ensure_directory() -> Error:
	var absolute := ProjectSettings.globalize_path(SAVE_DIRECTORY)
	return DirAccess.make_dir_recursive_absolute(absolute)
