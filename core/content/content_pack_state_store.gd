class_name ContentPackStateStore
extends RefCounted


const SCHEMA_VERSION := 1
const DEFAULT_ROOT := "user://content_packs"
const FILE_NAME := "enabled.json"

var recovered_from_backup := false
var last_error: Error = OK
var _root: String


func _init(root: String = DEFAULT_ROOT) -> void:
	_root = root.trim_suffix("/")


func state_path() -> String:
	return _root.path_join(FILE_NAME)


func load_state() -> Dictionary:
	recovered_from_backup = false
	last_error = OK
	var primary := _read(state_path())
	if not primary.is_empty():
		return primary
	var backup := _read(state_path() + ".bak")
	if not backup.is_empty():
		recovered_from_backup = true
		last_error = _promote(backup)
		return backup
	if FileAccess.file_exists(state_path()) or FileAccess.file_exists(state_path() + ".bak"):
		last_error = ERR_FILE_CORRUPT
	return {"schema_version": SCHEMA_VERSION, "enabled_pack_ids": PackedStringArray()}


func save_enabled(pack_ids: PackedStringArray) -> Error:
	var normalized := PackedStringArray()
	var seen := {}
	for raw_id: String in pack_ids:
		var pack_id := raw_id.strip_edges()
		if pack_id.is_empty() or pack_id == "core" or seen.has(pack_id):
			continue
		seen[pack_id] = true
		normalized.append(pack_id)
	normalized.sort()
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(_root)
	)
	if directory_error != OK:
		last_error = directory_error
		return last_error
	var temporary := state_path() + ".tmp"
	last_error = _write(temporary, normalized)
	if last_error != OK:
		return last_error
	if _read(temporary).is_empty():
		_remove(temporary)
		last_error = ERR_INVALID_DATA
		return last_error
	var primary := state_path()
	var backup := primary + ".bak"
	var had_primary := FileAccess.file_exists(primary)
	if had_primary:
		_remove(backup)
		last_error = _rename(primary, backup)
		if last_error != OK:
			_remove(temporary)
			return last_error
	last_error = _rename(temporary, primary)
	if last_error != OK:
		if had_primary:
			_rename(backup, primary)
		_remove(temporary)
		return last_error
	return OK


func _write(path: String, enabled: PackedStringArray) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({
		"schema_version": SCHEMA_VERSION,
		"enabled_pack_ids": Array(enabled),
	}, "  ", false))
	file.flush()
	file.close()
	return OK


func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary or int(parsed.get("schema_version", -1)) != SCHEMA_VERSION:
		return {}
	var ids: Variant = parsed.get("enabled_pack_ids")
	if not ids is Array:
		return {}
	var enabled := PackedStringArray()
	for value: Variant in ids:
		if not value is String or String(value).is_empty() or value == "core":
			return {}
		enabled.append(value)
	return {"schema_version": SCHEMA_VERSION, "enabled_pack_ids": enabled}


func _promote(state: Dictionary) -> Error:
	var ids := state.get("enabled_pack_ids", PackedStringArray()) as PackedStringArray
	var temporary := state_path() + ".tmp"
	var error := _write(temporary, ids)
	if error != OK:
		return error
	_remove(state_path())
	return _rename(temporary, state_path())


func _rename(source: String, destination: String) -> Error:
	return DirAccess.rename_absolute(
		ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(destination)
	)


func _remove(path: String) -> Error:
	if not FileAccess.file_exists(path):
		return OK
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
