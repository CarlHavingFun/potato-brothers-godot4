class_name ContentPackInstaller
extends RefCounted


const INDEX_SCHEMA_VERSION := 1
const DESCRIPTOR_SCHEMA_VERSION := 1
const DEFAULT_ROOT := "user://content_packs/installed"

var _root: String
var _mounted_pack_ids := {}


func _init(root: String = DEFAULT_ROOT) -> void:
	_root = root.trim_suffix("/")


func mark_mounted(pack_id: StringName) -> void:
	if not pack_id.is_empty():
		_mounted_pack_ids[pack_id] = true


func install(pck_path: String, descriptor_path: String) -> Dictionary:
	var validation := _validate_candidate(pck_path, descriptor_path)
	if not validation.errors.is_empty():
		return _failure(validation.errors)
	var descriptor: Dictionary = validation.descriptor
	var pack_id := StringName(descriptor.pack_id)
	var version := String(descriptor.pack_version)
	var setup_error := _ensure_directories()
	if setup_error != OK:
		return _failure(PackedStringArray([error_string(setup_error)]))

	var token := "%s-%d" % [pack_id, Time.get_ticks_usec()]
	var staged_pck := _staging_root().path_join(token + ".pck")
	var staged_descriptor := _staging_root().path_join(token + ".contents.json")
	var copy_error := _copy(pck_path, staged_pck)
	if copy_error == OK:
		copy_error = _copy(descriptor_path, staged_descriptor)
	if copy_error != OK:
		_cleanup([staged_pck, staged_descriptor])
		return _failure(PackedStringArray(["could not stage content pack: %s" % error_string(copy_error)]))
	if FileAccess.get_sha256(staged_pck) != String(descriptor.pck_sha256):
		_cleanup([staged_pck, staged_descriptor])
		return _failure(PackedStringArray(["staged PCK sha256 mismatch"]))

	var index := _load_index()
	var entries: Dictionary = index.entries
	var previous: Dictionary = entries.get(String(pack_id), {}).duplicate(true)
	if _mounted_pack_ids.has(pack_id) and not previous.is_empty():
		var hash_tag := String(descriptor.pck_sha256).left(12)
		var pending_pck := _pending_root().path_join(
			"%s-%s-%s.pck" % [pack_id, version, hash_tag]
		)
		var pending_descriptor := pending_pck.get_basename() + ".contents.json"
		_cleanup([pending_pck, pending_descriptor])
		var move_error := _rename(staged_pck, pending_pck)
		if move_error == OK:
			move_error = _rename(staged_descriptor, pending_descriptor)
		if move_error != OK:
			_cleanup([staged_pck, staged_descriptor, pending_pck, pending_descriptor])
			return _failure(PackedStringArray(["could not stage mounted update: %s" % error_string(move_error)]))
		var updated := previous.duplicate(true)
		updated["pending"] = {
			"operation": "replace",
			"version": version,
			"pck_path": pending_pck,
			"descriptor_path": pending_descriptor,
		}
		entries[String(pack_id)] = updated
		var save_error := _save_index(index)
		if save_error != OK:
			entries[String(pack_id)] = previous
			_cleanup([pending_pck, pending_descriptor])
			return _failure(PackedStringArray(["could not save installed index: %s" % error_string(save_error)]))
		return _success(pack_id, version, previous.pck_path, true)

	var final_pck := _root.path_join("%s-%s-%s.pck" % [
		pack_id, version, String(descriptor.pck_sha256).left(12)
	])
	var final_descriptor := final_pck.get_basename() + ".contents.json"
	var old_paths := PackedStringArray()
	if not previous.is_empty():
		old_paths.append(String(previous.get("pck_path", "")))
		old_paths.append(String(previous.get("descriptor_path", "")))
	var move_error := _rename(staged_pck, final_pck)
	if move_error == OK:
		move_error = _rename(staged_descriptor, final_descriptor)
	if move_error != OK:
		_cleanup([staged_pck, staged_descriptor, final_pck, final_descriptor])
		return _failure(PackedStringArray(["could not install content pack: %s" % error_string(move_error)]))
	entries[String(pack_id)] = {
		"pack_id": String(pack_id),
		"version": version,
		"pck_path": final_pck,
		"descriptor_path": final_descriptor,
		"manifest_virtual_path": descriptor.manifest_virtual_path,
		"source_root_virtual_path": descriptor.source_root_virtual_path,
	}
	var save_error := _save_index(index)
	if save_error != OK:
		if previous.is_empty():
			entries.erase(String(pack_id))
		else:
			entries[String(pack_id)] = previous
		_cleanup([final_pck, final_descriptor])
		return _failure(PackedStringArray(["could not save installed index: %s" % error_string(save_error)]))
	_cleanup(old_paths)
	return _success(pack_id, version, final_pck, false)


func remove(pack_id: StringName) -> Dictionary:
	if pack_id.is_empty() or pack_id == &"core":
		return _failure(PackedStringArray(["invalid removable pack id"]))
	var index := _load_index()
	var entries: Dictionary = index.entries
	var entry: Dictionary = entries.get(String(pack_id), {})
	if entry.is_empty():
		return _failure(PackedStringArray(["content pack is not installed: %s" % pack_id]))
	if _mounted_pack_ids.has(pack_id):
		var updated := entry.duplicate(true)
		updated["pending"] = {"operation": "remove"}
		entries[String(pack_id)] = updated
		var save_error := _save_index(index)
		if save_error != OK:
			return _failure(PackedStringArray([error_string(save_error)]))
		return _success(pack_id, String(entry.version), String(entry.pck_path), true)
	entries.erase(String(pack_id))
	var save_error := _save_index(index)
	if save_error != OK:
		entries[String(pack_id)] = entry
		return _failure(PackedStringArray([error_string(save_error)]))
	_cleanup(PackedStringArray([
		String(entry.get("pck_path", "")), String(entry.get("descriptor_path", ""))
	]))
	return _success(pack_id, String(entry.version), "", false)


func installed_entries() -> Array[Dictionary]:
	var values: Array[Dictionary] = []
	for value: Variant in (_load_index().entries as Dictionary).values():
		if value is Dictionary:
			values.append((value as Dictionary).duplicate(true))
	return values


func apply_pending_on_startup() -> Dictionary:
	var setup_error := _ensure_directories()
	if setup_error != OK:
		return _failure(PackedStringArray([error_string(setup_error)]))
	var index := _load_index()
	var entries: Dictionary = index.entries
	var changed := false
	var cleanup_after_save := PackedStringArray()
	var rollback_new_files := PackedStringArray()
	for pack_key: String in entries.keys():
		var entry := entries[pack_key] as Dictionary
		var pending: Dictionary = entry.get("pending", {})
		if pending.is_empty():
			continue
		match String(pending.get("operation", "")):
			"remove":
				cleanup_after_save.append_array(PackedStringArray([
					String(entry.get("pck_path", "")),
					String(entry.get("descriptor_path", "")),
				]))
				entries.erase(pack_key)
				changed = true
			"replace":
				var pending_pck := String(pending.get("pck_path", ""))
				var pending_descriptor := String(pending.get("descriptor_path", ""))
				if not FileAccess.file_exists(pending_pck) or not FileAccess.file_exists(pending_descriptor):
					return _failure(PackedStringArray(["pending update is incomplete: %s" % pack_key]))
				var version := String(pending.get("version", ""))
				var descriptor_data: Variant = JSON.parse_string(
					FileAccess.get_file_as_string(pending_descriptor)
				)
				if not descriptor_data is Dictionary:
					return _failure(PackedStringArray(["pending descriptor is invalid: %s" % pack_key]))
				var hash_tag := String(descriptor_data.get("pck_sha256", "")).left(12)
				var final_pck := _root.path_join("%s-%s-%s.pck" % [pack_key, version, hash_tag])
				var final_descriptor := final_pck.get_basename() + ".contents.json"
				if FileAccess.file_exists(final_pck) or FileAccess.file_exists(final_descriptor):
					return _failure(PackedStringArray(["pending destination already exists: %s" % final_pck]))
				var move_error := _copy(pending_pck, final_pck)
				if move_error == OK:
					move_error = _copy(pending_descriptor, final_descriptor)
				if move_error != OK:
					_cleanup([final_pck, final_descriptor])
					return _failure(PackedStringArray([
						"pending update could not be activated: %s" % error_string(move_error)
					]))
				rollback_new_files.append_array(PackedStringArray([
					final_pck, final_descriptor,
				]))
				cleanup_after_save.append_array(PackedStringArray([
					String(entry.get("pck_path", "")),
					String(entry.get("descriptor_path", "")),
					pending_pck,
					pending_descriptor,
				]))
				entry["version"] = version
				entry["pck_path"] = final_pck
				entry["descriptor_path"] = final_descriptor
				entry.erase("pending")
				entries[pack_key] = entry
				changed = true
	if changed:
		var save_error := _save_index(index)
		if save_error != OK:
			_cleanup(rollback_new_files)
			return _failure(PackedStringArray(["pending index activation failed: %s" % error_string(save_error)]))
		_cleanup(cleanup_after_save)
	return {"ok": true, "restart_required": false, "errors": PackedStringArray()}


func _validate_candidate(pck_path: String, descriptor_path: String) -> Dictionary:
	var errors := PackedStringArray()
	if not FileAccess.file_exists(pck_path):
		errors.append("PCK not found: %s" % pck_path)
	if not FileAccess.file_exists(descriptor_path):
		errors.append("descriptor not found: %s" % descriptor_path)
	if not errors.is_empty():
		return {"errors": errors, "descriptor": {}}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(descriptor_path))
	if not parsed is Dictionary:
		errors.append("descriptor is not valid JSON")
		return {"errors": errors, "descriptor": {}}
	var descriptor := parsed as Dictionary
	if int(descriptor.get("schema_version", -1)) != DESCRIPTOR_SCHEMA_VERSION:
		errors.append("unsupported descriptor schema")
	var pack_id := String(descriptor.get("pack_id", ""))
	var version := String(descriptor.get("pack_version", ""))
	var source_root := _normalized_virtual_path(String(descriptor.get("source_root_virtual_path", "")))
	var manifest := _normalized_virtual_path(String(descriptor.get("manifest_virtual_path", "")))
	if pack_id.is_empty() or pack_id == "core" or version.is_empty():
		errors.append("descriptor pack identity is invalid")
	if not _is_allowed_pack_root(source_root):
		errors.append("descriptor source root is not an independent pack namespace")
	if manifest != source_root.path_join("pack.tres"):
		errors.append("manifest must be the pack root pack.tres")
	if bool(descriptor.get("replace_files", true)):
		errors.append("PCK file replacement must be disabled")
	var expected_pck_hash := String(descriptor.get("pck_sha256", ""))
	if expected_pck_hash.length() != 64 or FileAccess.get_sha256(pck_path) != expected_pck_hash:
		errors.append("PCK sha256 mismatch")
	var raw_files: Variant = descriptor.get("files", null)
	if not raw_files is Array or raw_files.is_empty():
		errors.append("descriptor file list is empty")
	else:
		for raw_entry: Variant in raw_files:
			if not raw_entry is Dictionary:
				errors.append("descriptor file entry is invalid")
				continue
			var path := _normalized_virtual_path(String(raw_entry.get("path", "")))
			var file_hash := String(raw_entry.get("sha256", ""))
			if not path.begins_with(source_root + "/") or path.contains("/../"):
				errors.append("descriptor path escapes pack root: %s" % path)
			if ContentValidator.FORBIDDEN_EXTENSIONS.has(path.get_extension().to_lower()):
				errors.append("forbidden content file: %s" % path)
			if file_hash.length() != 64:
				errors.append("descriptor file hash is invalid: %s" % path)
	return {"errors": errors, "descriptor": descriptor}


func _is_allowed_pack_root(path: String) -> bool:
	return (
		path.begins_with("res://content_packs/characters/")
		or path.begins_with("res://content_packs/weapons/")
	) and not path.contains("..") and not path.contains("\\")


func _normalized_virtual_path(path: String) -> String:
	return path.replace("\\", "/").trim_suffix("/")


func _ensure_directories() -> Error:
	for path: String in [_root, _staging_root(), _pending_root()]:
		var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
		if error != OK:
			return error
	return OK


func _load_index() -> Dictionary:
	var fallback := {"schema_version": INDEX_SCHEMA_VERSION, "entries": {}}
	if not FileAccess.file_exists(_index_path()):
		return fallback
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_index_path()))
	if not parsed is Dictionary or int(parsed.get("schema_version", -1)) != INDEX_SCHEMA_VERSION:
		return fallback
	if not parsed.get("entries") is Dictionary:
		return fallback
	return parsed


func _save_index(index: Dictionary) -> Error:
	var temporary := _index_path() + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(index, "  ", false))
	file.flush()
	file.close()
	var backup := _index_path() + ".bak"
	_cleanup([backup])
	var had_primary := FileAccess.file_exists(_index_path())
	if had_primary:
		var error := _rename(_index_path(), backup)
		if error != OK:
			_cleanup([temporary])
			return error
	var replace_error := _rename(temporary, _index_path())
	if replace_error != OK and had_primary:
		_rename(backup, _index_path())
	return replace_error


func _copy(source: String, destination: String) -> Error:
	return DirAccess.copy_absolute(
		ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(destination)
	)


func _rename(source: String, destination: String) -> Error:
	return DirAccess.rename_absolute(
		ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(destination)
	)


func _cleanup(paths: Variant) -> void:
	for path: String in paths:
		if not path.is_empty() and FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _index_path() -> String:
	return _root.path_join("installed.json")


func _staging_root() -> String:
	return _root.path_join(".staging")


func _pending_root() -> String:
	return _root.path_join(".pending")


func _success(pack_id: StringName, version: String, path: String, restart: bool) -> Dictionary:
	return {
		"ok": true,
		"pack_id": pack_id,
		"version": version,
		"pck_path": path,
		"restart_required": restart,
		"errors": PackedStringArray(),
	}


func _failure(errors: PackedStringArray) -> Dictionary:
	return {"ok": false, "restart_required": false, "errors": errors}
