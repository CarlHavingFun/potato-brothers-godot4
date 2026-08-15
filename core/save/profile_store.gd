class_name ProfileStore
extends RefCounted


const SAVE_VERSION := 3
const LEGACY_PROFILE_VERSION := 2
const MAX_PROFILES := 3
const DEFAULT_ROOT_PATH := "user://save/profiles"
const LEGACY_NAMESPACE := "potato_default:"
const CORE_NAMESPACE := "core:"

var _root_path: String
var _legacy_path: String


func _init(
	root_path: String = DEFAULT_ROOT_PATH,
	legacy_path: String = LocalSaveProvider.DEFAULT_SAVE_PATH
) -> void:
	_root_path = root_path.trim_suffix("/")
	_legacy_path = legacy_path


func list_profiles() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot in range(1, MAX_PROFILES + 1):
		result.append(profile_summary(slot))
	return result


func profile_summary(slot: int) -> Dictionary:
	if not _is_valid_slot(slot):
		return {}
	var document := _load_or_migrate_document(slot)
	if document.is_empty():
		return {
			"id": slot,
			"name": _default_name(slot),
			"exists": false,
			"has_checkpoint": false,
			"updated_unix": 0,
			"highest_endless_wave": 0,
		}
	var payload: Variant = document.get("payload", {})
	var highest_endless_wave := 0
	if payload is Dictionary:
		var meta: Variant = payload.get("meta_progress", {})
		if meta is Dictionary:
			var highs: Variant = meta.get("character_endless_highs", {})
			if highs is Dictionary:
				for value: Variant in highs.values():
					highest_endless_wave = maxi(highest_endless_wave, int(value))
	return {
		"id": slot,
		"name": str(document.get("profile_name", _default_name(slot))),
		"exists": true,
		"has_checkpoint": payload is Dictionary and payload.has("run_state"),
		"updated_unix": int(document.get("updated_unix", 0)),
		"highest_endless_wave": highest_endless_wave,
	}


func profile_path(slot: int) -> String:
	if not _is_valid_slot(slot):
		return ""
	return "%s/%d/save_v3.json" % [_root_path, slot]


func legacy_profile_path(slot: int) -> String:
	if not _is_valid_slot(slot):
		return ""
	return "%s/%d/save_v2.json" % [_root_path, slot]


func load_profile(slot: int) -> Dictionary:
	if not _is_valid_slot(slot):
		return {}
	var document := _load_or_migrate_document(slot)
	var payload: Variant = document.get("payload", {})
	return payload.duplicate(true) if payload is Dictionary else {}


func save_profile(slot: int, payload: Dictionary) -> Error:
	if not _is_valid_slot(slot):
		return ERR_INVALID_PARAMETER
	var existing := _load_or_migrate_document(slot)
	var document := {
		"save_version": SAVE_VERSION,
		"profile_id": slot,
		"profile_name": str(existing.get("profile_name", _default_name(slot))),
		"updated_unix": int(Time.get_unix_time_from_system()),
		"payload": _migrate_payload(payload),
	}
	return _write_document(slot, document)


func rename_profile(slot: int, new_name: String) -> Error:
	if not _is_valid_slot(slot):
		return ERR_INVALID_PARAMETER
	var clean_name := new_name.strip_edges()
	if clean_name.is_empty() or clean_name.length() > 24:
		return ERR_INVALID_DATA
	var document := _load_or_migrate_document(slot)
	if document.is_empty():
		document = {
			"save_version": SAVE_VERSION,
			"profile_id": slot,
			"payload": {},
		}
	document["profile_name"] = clean_name
	document["updated_unix"] = int(Time.get_unix_time_from_system())
	return _write_document(slot, document)


func delete_profile(slot: int) -> Error:
	if not _is_valid_slot(slot):
		return ERR_INVALID_PARAMETER
	for base_path in [profile_path(slot), legacy_profile_path(slot)]:
		var absolute_path := ProjectSettings.globalize_path(base_path)
		for suffix in ["", ".tmp", ".bak"]:
			var target: String = absolute_path + suffix
			if FileAccess.file_exists(target):
				var error := DirAccess.remove_absolute(target)
				if error != OK:
					return error
	return OK


func migrate_legacy_to_slot_one() -> bool:
	if profile_summary(1).get("exists", false) or _legacy_path.is_empty():
		return false
	var legacy := LocalSaveProvider.new(_legacy_path)
	var payload := legacy.load_slot()
	if payload.is_empty():
		return false
	return save_profile(1, _migrate_payload(payload)) == OK


func _load_or_migrate_document(slot: int) -> Dictionary:
	var current := _read_document(profile_path(slot))
	if not current.is_empty():
		return current
	var legacy := _read_legacy_document(legacy_profile_path(slot))
	if legacy.is_empty():
		return {}
	var migrated := {
		"save_version": SAVE_VERSION,
		"profile_id": slot,
		"profile_name": str(legacy.get("profile_name", _default_name(slot))),
		"updated_unix": int(legacy.get("updated_unix", Time.get_unix_time_from_system())),
		"payload": _migrate_payload(legacy.get("payload", {}) as Dictionary),
	}
	return migrated if _write_document(slot, migrated) == OK else {}


func _read_legacy_document(path: String) -> Dictionary:
	var document := _read_document_direct_version(path, LEGACY_PROFILE_VERSION)
	if not document.is_empty():
		return document
	var backup := _read_document_direct_version(path + ".bak", LEGACY_PROFILE_VERSION)
	if backup.is_empty():
		return {}
	var payload := backup.get("payload", {}) as Dictionary
	var meta_progress := payload.get("meta_progress", {}) as Dictionary
	var notices: Array = meta_progress.get("repair_notices", [])
	var notice := "Recovered legacy profile from backup during v3 migration."
	if notice not in notices:
		notices.append(notice)
	meta_progress["repair_notices"] = notices
	payload["meta_progress"] = meta_progress
	backup["payload"] = payload
	return backup


func _write_document(slot: int, document: Dictionary) -> Error:
	var path := profile_path(slot)
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(path.get_base_dir())
	)
	if directory_error != OK:
		return directory_error
	var temporary_path := path + ".tmp"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(document))
	file.flush()
	file.close()
	if _read_document_direct(temporary_path).is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
		return ERR_INVALID_DATA

	var primary_absolute := ProjectSettings.globalize_path(path)
	var backup_absolute := ProjectSettings.globalize_path(path + ".bak")
	var temporary_absolute := ProjectSettings.globalize_path(temporary_path)
	var backed_up := false
	if FileAccess.file_exists(path):
		if not _read_document_direct(path).is_empty():
			if FileAccess.file_exists(path + ".bak"):
				DirAccess.remove_absolute(backup_absolute)
			var backup_error := DirAccess.rename_absolute(primary_absolute, backup_absolute)
			if backup_error != OK:
				DirAccess.remove_absolute(temporary_absolute)
				return backup_error
			backed_up = true
		else:
			DirAccess.remove_absolute(primary_absolute)
	var replace_error := DirAccess.rename_absolute(temporary_absolute, primary_absolute)
	if replace_error != OK:
		if backed_up:
			DirAccess.rename_absolute(backup_absolute, primary_absolute)
		return replace_error
	return OK


func _read_document(path: String) -> Dictionary:
	var primary := _read_document_direct(path)
	if not primary.is_empty():
		return primary
	var backup := _read_document_direct(path + ".bak")
	if backup.is_empty():
		return {}
	var recovered := backup.duplicate(true)
	var payload := recovered.get("payload", {}) as Dictionary
	var meta_progress := payload.get("meta_progress", {}) as Dictionary
	var notices: Array = meta_progress.get("repair_notices", [])
	var notice := "Recovered profile from backup after corrupted primary save."
	if notice not in notices:
		notices.append(notice)
	meta_progress["repair_notices"] = notices
	payload["meta_progress"] = meta_progress
	recovered["payload"] = payload
	_promote_recovered_document(path, recovered)
	return recovered


func _promote_recovered_document(path: String, document: Dictionary) -> bool:
	var temporary_path := path + ".tmp"
	var temporary_absolute := ProjectSettings.globalize_path(temporary_path)
	var primary_absolute := ProjectSettings.globalize_path(path)
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(document))
	file.flush()
	file.close()
	if _read_document_direct(temporary_path).is_empty():
		DirAccess.remove_absolute(temporary_absolute)
		return false
	if FileAccess.file_exists(path) and DirAccess.remove_absolute(primary_absolute) != OK:
		DirAccess.remove_absolute(temporary_absolute)
		return false
	return DirAccess.rename_absolute(temporary_absolute, primary_absolute) == OK


func _read_document_direct(path: String) -> Dictionary:
	return _read_document_direct_version(path, SAVE_VERSION)


func _read_document_direct_version(path: String, expected_version: int) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	file.close()
	if parse_error != OK or not json.data is Dictionary:
		return {}
	var document := json.data as Dictionary
	if (
		int(document.get("save_version", -1)) != expected_version
		or not document.get("payload", null) is Dictionary
	):
		return {}
	return document


func _default_name(slot: int) -> String:
	return "档案 %d" % slot


func _is_valid_slot(slot: int) -> bool:
	return slot in range(1, MAX_PROFILES + 1)


func _migrate_payload(payload: Dictionary) -> Dictionary:
	return _migrate_variant(payload) as Dictionary


func _migrate_variant(value: Variant) -> Variant:
	if value is Dictionary:
		var migrated_dict := {}
		for raw_key: Variant in value:
			var key: Variant = _migrate_content_id(raw_key)
			migrated_dict[key] = _migrate_variant(value[raw_key])
		return migrated_dict
	if value is Array:
		var migrated_array: Array = []
		for entry: Variant in value:
			migrated_array.append(_migrate_variant(entry))
		return migrated_array
	return _migrate_content_id(value)


func _migrate_content_id(value: Variant) -> Variant:
	if value is StringName:
		var name_value := String(value)
		return StringName(CORE_NAMESPACE + name_value.trim_prefix(LEGACY_NAMESPACE)) \
			if name_value.begins_with(LEGACY_NAMESPACE) else value
	if value is String:
		var string_value := value as String
		return CORE_NAMESPACE + string_value.trim_prefix(LEGACY_NAMESPACE) \
			if string_value.begins_with(LEGACY_NAMESPACE) else value
	return value
