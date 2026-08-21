class_name ProfileStore
extends RefCounted


const SAVE_VERSION := 4
const PREVIOUS_PROFILE_VERSION := 3
const LEGACY_PROFILE_VERSION := 2
const MAX_PROFILES := 3
const DEFAULT_ROOT_PATH := "user://save/profiles"
const PROFILE_INDEX_VERSION := 1
const PROFILE_INDEX_FILE := "profile_index_v1.json"
const LEGACY_MIGRATION_MARKER_FILE := "legacy_migration_v1.completed"
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
			"name": "",
			"exists": false,
			"has_progress": false,
			"has_checkpoint": false,
			"updated_unix": 0,
			"highest_endless_wave": 0,
		}
	var payload: Variant = document.get("payload", {})
	var checkpoint: RunState
	if payload is Dictionary and payload.get("run_state", null) is Dictionary:
		checkpoint = RunState.from_dict(payload.get("run_state", {}))
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
		"name": _display_profile_name(str(document.get("profile_name", "")), slot),
		"exists": true,
		"has_progress": _payload_has_progress(payload as Dictionary),
		"has_checkpoint": checkpoint != null and checkpoint.is_resumable_checkpoint(),
		"updated_unix": int(document.get("updated_unix", 0)),
		"highest_endless_wave": highest_endless_wave,
	}


func profile_path(slot: int) -> String:
	if not _is_valid_slot(slot):
		return ""
	return "%s/%d/save_v4.json" % [_root_path, slot]


func previous_profile_path(slot: int) -> String:
	if not _is_valid_slot(slot):
		return ""
	return "%s/%d/save_v3.json" % [_root_path, slot]


func legacy_profile_path(slot: int) -> String:
	if not _is_valid_slot(slot):
		return ""
	return "%s/%d/save_v2.json" % [_root_path, slot]


func profile_index_path() -> String:
	return "%s/%s" % [_root_path, PROFILE_INDEX_FILE]


func legacy_migration_marker_path() -> String:
	return "%s/%s" % [_root_path, LEGACY_MIGRATION_MARKER_FILE]


func load_active_profile_id() -> int:
	var path := profile_index_path()
	var active_id := _read_profile_index(path)
	if _profile_exists(active_id):
		return active_id
	active_id = _read_profile_index(path + ".bak")
	if _profile_exists(active_id):
		# Repairing the small global index is safe and keeps the valid backup. A
		# failed promotion still returns the recovered selection for this session.
		save_active_profile_id(active_id)
		return active_id
	active_id = _choose_initial_profile_id()
	# This is a one-time migration for builds that predate the profile index.
	# Prefer a real resumable run so an older slot-one shell cannot hide it.
	if active_id > 0:
		save_active_profile_id(active_id)
	return active_id


func save_active_profile_id(profile_id: int) -> Error:
	if not _profile_exists(profile_id):
		return ERR_INVALID_PARAMETER
	var document := _read_profile_index_document(profile_index_path())
	if document.is_empty():
		document = _read_profile_index_document(profile_index_path() + ".bak")
	document["version"] = PROFILE_INDEX_VERSION
	document["active_profile_id"] = profile_id
	return _write_profile_index_document(document)


func clear_active_profile_id() -> Error:
	var first_error := OK
	for suffix: String in ["", ".bak", ".tmp"]:
		var path := profile_index_path() + suffix
		if not FileAccess.file_exists(path):
			continue
		var result := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if result != OK and first_error == OK:
			first_error = result
	return first_error


func _write_profile_index_document(document: Dictionary) -> Error:
	var path := profile_index_path()
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
	if _read_profile_index_document(temporary_path).is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
		return ERR_INVALID_DATA

	var primary_absolute := ProjectSettings.globalize_path(path)
	var backup_absolute := ProjectSettings.globalize_path(path + ".bak")
	var temporary_absolute := ProjectSettings.globalize_path(temporary_path)
	var backed_up := false
	if FileAccess.file_exists(path):
		if _is_valid_slot(_read_profile_index(path)):
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
		"profile_name": str(existing.get("profile_name", "")),
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
	if slot == 1 and not _legacy_path.is_empty():
		# Deletion is irreversible from the UI, so require the independent
		# tombstone even when an older index already claims migration completed.
		# If it cannot be persisted, leave the profile untouched.
		var marker_error := _write_legacy_migration_marker()
		if marker_error != OK:
			return marker_error
	for base_path in [profile_path(slot), previous_profile_path(slot), legacy_profile_path(slot)]:
		var absolute_path := ProjectSettings.globalize_path(base_path)
		for suffix in ["", ".tmp", ".bak"]:
			var target: String = absolute_path + suffix
			if FileAccess.file_exists(target):
				var error := DirAccess.remove_absolute(target)
				if error != OK:
					return error
	return OK


func migrate_legacy_to_slot_one() -> bool:
	if _legacy_path.is_empty() or _legacy_migration_completed():
		return false
	if profile_summary(1).get("exists", false):
		_mark_legacy_migration_completed()
		return false
	var legacy := LocalSaveProvider.new(_legacy_path)
	var payload := legacy.load_slot()
	if payload.is_empty():
		return false
	if save_profile(1, _migrate_payload(payload)) != OK:
		return false
	return _mark_legacy_migration_completed() == OK


func _load_or_migrate_document(slot: int) -> Dictionary:
	var current := _read_document(profile_path(slot))
	if not current.is_empty():
		return current
	var legacy := _read_previous_document(previous_profile_path(slot))
	if legacy.is_empty():
		legacy = _read_legacy_document(legacy_profile_path(slot))
	if legacy.is_empty():
		return {}
	var migrated := {
		"save_version": SAVE_VERSION,
		"profile_id": slot,
		"profile_name": str(legacy.get("profile_name", "")),
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


func _read_previous_document(path: String) -> Dictionary:
	var document := _read_document_direct_version(path, PREVIOUS_PROFILE_VERSION)
	if not document.is_empty():
		return document
	var backup := _read_document_direct_version(path + ".bak", PREVIOUS_PROFILE_VERSION)
	if backup.is_empty():
		return {}
	var payload := backup.get("payload", {}) as Dictionary
	var meta_progress := payload.get("meta_progress", {}) as Dictionary
	var notices: Array = meta_progress.get("repair_notices", [])
	var notice := "Recovered v3 profile from backup during v4 migration."
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


func _read_profile_index(path: String) -> int:
	var document := _read_profile_index_document(path)
	return int(document.get("active_profile_id", 0)) if not document.is_empty() else 0


func _read_profile_index_document(path: String) -> Dictionary:
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
	if int(document.get("version", -1)) != PROFILE_INDEX_VERSION:
		return {}
	var active_id := int(document.get("active_profile_id", 0))
	return document if _is_valid_slot(active_id) else {}


func _choose_initial_profile_id() -> int:
	var best_slot := 0
	var best_priority := 0
	var best_updated := -1
	for slot in range(1, MAX_PROFILES + 1):
		var document := _load_or_migrate_document(slot)
		if document.is_empty():
			continue
		var priority := 1
		var payload: Variant = document.get("payload", {})
		if payload is Dictionary:
			if _payload_has_progress(payload as Dictionary):
				priority = 2
			if payload.get("run_state", null) is Dictionary:
				var checkpoint := RunState.from_dict(payload.get("run_state", {}))
				if checkpoint.is_resumable_checkpoint():
					priority = 3
		var updated := int(document.get("updated_unix", 0))
		if priority > best_priority or (priority == best_priority and updated > best_updated):
			best_slot = slot
			best_priority = priority
			best_updated = updated
	return best_slot


func _legacy_migration_completed() -> bool:
	if FileAccess.file_exists(legacy_migration_marker_path()):
		return true
	var primary := _read_profile_index_document(profile_index_path())
	var backup := _read_profile_index_document(profile_index_path() + ".bak")
	var completed := (
		bool(primary.get("legacy_migration_completed", false))
		or bool(backup.get("legacy_migration_completed", false))
	)
	if completed:
		# Upgrade the former index-only flag to an independent one-way tombstone.
		# The index can then be repaired or rolled back without reviving a deleted
		# legacy slot. A transient write failure is retried on every later check.
		_write_legacy_migration_marker()
	return completed


func _mark_legacy_migration_completed() -> Error:
	var marker_error := _write_legacy_migration_marker()
	if marker_error != OK:
		return marker_error
	var document := _read_profile_index_document(profile_index_path())
	if document.is_empty():
		document = _read_profile_index_document(profile_index_path() + ".bak")
	if document.is_empty():
		var fallback_id := _choose_initial_profile_id()
		if fallback_id == 0:
			return OK
		document = {"version": PROFILE_INDEX_VERSION, "active_profile_id": fallback_id}
	document["legacy_migration_completed"] = true
	return _write_profile_index_document(document)


func _write_legacy_migration_marker() -> Error:
	var marker_path := legacy_migration_marker_path()
	if FileAccess.file_exists(marker_path):
		return OK
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(marker_path.get_base_dir())
	)
	if directory_error != OK:
		return directory_error
	var temporary_path := marker_path + ".tmp"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string("completed\n")
	file.flush()
	file.close()
	var temporary_absolute := ProjectSettings.globalize_path(temporary_path)
	if not FileAccess.file_exists(temporary_path):
		return ERR_CANT_CREATE
	var replace_error := DirAccess.rename_absolute(
		temporary_absolute, ProjectSettings.globalize_path(marker_path)
	)
	if replace_error != OK:
		DirAccess.remove_absolute(temporary_absolute)
	return replace_error


func _payload_has_progress(payload: Dictionary) -> bool:
	var raw_run: Variant = payload.get("run_state", null)
	if raw_run is Dictionary:
		var run_data := raw_run as Dictionary
		var checkpoint := RunState.from_dict(run_data)
		if (
			checkpoint.is_resumable_checkpoint()
			or not str(run_data.get("character_id", "")).is_empty()
			or int(run_data.get("wave", 1)) > 1
		):
			return true
	var raw_meta: Variant = payload.get("meta_progress", {})
	if not raw_meta is Dictionary:
		return false
	var meta := raw_meta as Dictionary
	if int(meta.get("highest_unlocked_difficulty", 1)) > 1:
		return true
	for key: String in [
		"character_highest_clears",
		"character_endless_highs",
		"discovered_content",
		"unlocked_character_ids",
		"recent_run_summary",
	]:
		var value: Variant = meta.get(key, null)
		if value is Dictionary and not (value as Dictionary).is_empty():
			return true
		if value is Array and not (value as Array).is_empty():
			return true
	return false


func _default_name(slot: int) -> String:
	return LocalizedTextService.resolve(
		&"ui.profile.default_name", [slot], "Profile %d"
	)


func _display_profile_name(stored_name: String, slot: int) -> String:
	var clean_name := stored_name.strip_edges()
	if clean_name.is_empty() or clean_name in ["档案 %d" % slot, "Profile %d" % slot]:
		return _default_name(slot)
	return clean_name


func _is_valid_slot(slot: int) -> bool:
	return slot in range(1, MAX_PROFILES + 1)


func _profile_exists(slot: int) -> bool:
	return _is_valid_slot(slot) and not _load_or_migrate_document(slot).is_empty()


func _migrate_payload(payload: Dictionary) -> Dictionary:
	var migrated := _migrate_variant(payload) as Dictionary
	var run_data: Variant = migrated.get("run_state", null)
	if run_data is Dictionary:
		migrated["run_state"] = RunState.from_dict(run_data).to_dict()
	return migrated


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
