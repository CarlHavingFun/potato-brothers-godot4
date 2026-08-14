class_name LocalSaveProvider
extends SaveProvider


const SAVE_VERSION := 1
const DEFAULT_SAVE_PATH := "user://save/packs/potato_default/save_v1.json"

var _save_path: String


func _init(save_path: String = DEFAULT_SAVE_PATH) -> void:
	_save_path = save_path


func is_available() -> bool:
	return _ensure_parent_directory() == OK


func load_slot() -> Dictionary:
	var primary: Variant = _read_payload(_save_path)
	if primary is Dictionary:
		return primary
	var backup: Variant = _read_payload(_backup_path())
	if backup is Dictionary:
		return backup
	return {}


func save_slot(payload: Variant) -> Error:
	if not payload is Dictionary:
		return ERR_INVALID_DATA
	var directory_error := _ensure_parent_directory()
	if directory_error != OK:
		return directory_error
	var temporary_path := _temporary_path()
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({
		"save_version": SAVE_VERSION,
		"payload": payload,
	}))
	file.flush()
	file.close()
	if not _read_payload(temporary_path) is Dictionary:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
		return ERR_INVALID_DATA

	var primary_path_absolute := ProjectSettings.globalize_path(_save_path)
	var backup_path_absolute := ProjectSettings.globalize_path(_backup_path())
	var temporary_path_absolute := ProjectSettings.globalize_path(temporary_path)
	var primary_was_backed_up := false
	if FileAccess.file_exists(_save_path):
		if _read_payload(_save_path) is Dictionary:
			if FileAccess.file_exists(_backup_path()):
				DirAccess.remove_absolute(backup_path_absolute)
			var backup_error := DirAccess.rename_absolute(primary_path_absolute, backup_path_absolute)
			if backup_error != OK:
				DirAccess.remove_absolute(temporary_path_absolute)
				return backup_error
			primary_was_backed_up = true
		else:
			DirAccess.remove_absolute(primary_path_absolute)

	var replace_error := DirAccess.rename_absolute(temporary_path_absolute, primary_path_absolute)
	if replace_error != OK:
		if primary_was_backed_up:
			DirAccess.rename_absolute(backup_path_absolute, primary_path_absolute)
		return replace_error
	return OK


func _ensure_parent_directory() -> Error:
	var absolute_directory := ProjectSettings.globalize_path(_save_path.get_base_dir())
	return DirAccess.make_dir_recursive_absolute(absolute_directory)


func _temporary_path() -> String:
	return _save_path + ".tmp"


func _backup_path() -> String:
	return _save_path + ".bak"


func _read_payload(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		return null
	var parsed: Variant = json.data
	if not parsed is Dictionary:
		return null
	if int(parsed.get("save_version", -1)) != SAVE_VERSION:
		return null
	var payload: Variant = parsed.get("payload")
	if not payload is Dictionary:
		return null
	return payload
