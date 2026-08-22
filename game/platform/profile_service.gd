class_name ProfileService
extends RefCounted

const SAVE_DIRECTORY := "user://GOGOBRO"
const PROFILE_PATH := SAVE_DIRECTORY + "/profile.json"
const TEMP_PATH := SAVE_DIRECTORY + "/profile.tmp"
const BACKUP_PATH := SAVE_DIRECTORY + "/profile.backup"

var last_error: String = ""
var profile_data: Dictionary = {"schema_version": 1, "completed_runs": 0, "best_wave": 0}


func load_profile() -> Error:
	last_error = ""
	var directory_error := _ensure_directory()
	if directory_error != OK:
		return directory_error
	if not FileAccess.file_exists(PROFILE_PATH):
		return OK
	var file := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	if file == null:
		last_error = "cannot open profile"
		return FileAccess.get_open_error()
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or int(parsed.get("schema_version", -1)) != 1:
		last_error = "unsupported or invalid profile"
		return ERR_FILE_CORRUPT
	profile_data = parsed.duplicate(true)
	return OK


func save_checkpoint(state: GogoRunState) -> Error:
	if state == null:
		return ERR_INVALID_PARAMETER
	var payload := profile_data.duplicate(true)
	payload["schema_version"] = 1
	payload["run_checkpoint"] = state.to_dictionary()
	payload["best_wave"] = maxi(int(payload.get("best_wave", 0)), state.current_wave)
	return _atomic_write(payload)


func record_settlement(state: GogoRunState) -> Error:
	if state == null:
		return ERR_INVALID_PARAMETER
	profile_data["best_wave"] = maxi(int(profile_data.get("best_wave", 0)), state.current_wave)
	profile_data["completed_runs"] = int(profile_data.get("completed_runs", 0)) + 1
	profile_data.erase("run_checkpoint")
	return _atomic_write(profile_data)


func clear_checkpoint() -> Error:
	profile_data.erase("run_checkpoint")
	return _atomic_write(profile_data)


func _atomic_write(payload: Dictionary) -> Error:
	last_error = ""
	var directory_error := _ensure_directory()
	if directory_error != OK:
		return directory_error
	var text := JSON.stringify(payload, "\t")
	var temp := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if temp == null:
		last_error = "cannot open temporary profile"
		return FileAccess.get_open_error()
	temp.store_string(text)
	temp.flush()
	temp.close()
	var verify := FileAccess.open(TEMP_PATH, FileAccess.READ)
	if verify == null or JSON.parse_string(verify.get_as_text()) == null:
		last_error = "temporary profile verification failed"
		return ERR_FILE_CORRUPT
	verify.close()
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
	var installed_valid := installed != null and JSON.parse_string(installed.get_as_text()) is Dictionary
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
	return OK


func _ensure_directory() -> Error:
	var absolute := ProjectSettings.globalize_path(SAVE_DIRECTORY)
	return DirAccess.make_dir_recursive_absolute(absolute)
