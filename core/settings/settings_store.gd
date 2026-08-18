class_name SettingsStore
extends RefCounted


const SAVE_VERSION := 1
const DEFAULT_ROOT_PATH := "user://save"
const FILE_NAME := "settings_v1.json"
const DEFAULT_SETTINGS_PATH := "user://save/settings_v1.json"

var recovered_from_backup: bool = false
var last_error: Error = OK

var _root_path: String


func _init(root_path: String = DEFAULT_ROOT_PATH) -> void:
	_root_path = root_path.trim_suffix("/")


func settings_path() -> String:
	return "%s/%s" % [_root_path, FILE_NAME]


func has_saved_settings() -> bool:
	return (
		_read_settings_dictionary(settings_path()) is Dictionary
		or _read_settings_dictionary(_backup_path()) is Dictionary
	)


func load_settings() -> ProductSettings:
	recovered_from_backup = false
	last_error = OK
	var primary: Variant = _read_settings_dictionary(settings_path())
	if primary is Dictionary:
		return ProductSettings.from_dict(primary)
	var backup: Variant = _read_settings_dictionary(_backup_path())
	if backup is Dictionary:
		recovered_from_backup = true
		last_error = _promote_recovered_settings(backup)
		return ProductSettings.from_dict(backup)
	if FileAccess.file_exists(settings_path()) or FileAccess.file_exists(_backup_path()):
		last_error = ERR_FILE_CORRUPT
	return ProductSettings.new()


func save_settings(settings: ProductSettings) -> Error:
	if settings == null:
		last_error = ERR_INVALID_PARAMETER
		return last_error
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(settings_path().get_base_dir())
	)
	if directory_error != OK:
		last_error = directory_error
		return last_error
	var normalized := settings.copy()
	var temporary_path := _temporary_path()
	var write_error := _write_document(temporary_path, normalized.to_dict())
	if write_error != OK:
		last_error = write_error
		return last_error
	if not _read_settings_dictionary(temporary_path) is Dictionary:
		_remove_file(temporary_path)
		last_error = ERR_INVALID_DATA
		return last_error

	var primary_path := settings_path()
	var primary_absolute := ProjectSettings.globalize_path(primary_path)
	var backup_absolute := ProjectSettings.globalize_path(_backup_path())
	var temporary_absolute := ProjectSettings.globalize_path(temporary_path)
	var backed_up := false
	if FileAccess.file_exists(primary_path):
		if _read_settings_dictionary(primary_path) is Dictionary:
			if FileAccess.file_exists(_backup_path()):
				var remove_backup_error := _remove_file(_backup_path())
				if remove_backup_error != OK:
					_remove_file(temporary_path)
					last_error = remove_backup_error
					return last_error
			var backup_error := DirAccess.rename_absolute(primary_absolute, backup_absolute)
			if backup_error != OK:
				_remove_file(temporary_path)
				last_error = backup_error
				return last_error
			backed_up = true
		else:
			var remove_primary_error := _remove_file(primary_path)
			if remove_primary_error != OK:
				_remove_file(temporary_path)
				last_error = remove_primary_error
				return last_error
	var replace_error := DirAccess.rename_absolute(temporary_absolute, primary_absolute)
	if replace_error != OK:
		if backed_up:
			DirAccess.rename_absolute(backup_absolute, primary_absolute)
		last_error = replace_error
		return last_error
	last_error = OK
	return OK


func migrate_from_legacy_meta(legacy_meta_progress: Dictionary) -> ProductSettings:
	if has_saved_settings():
		return load_settings()
	var migrated_data := {}
	for key: String in [
		"master_volume",
		"music_volume",
		"sfx_volume",
		"mute_on_focus_lost",
		"display_mode",
		"fullscreen",
		"resolution",
		"vsync_enabled",
		"fps_cap",
		"aim_mode",
		"pause_on_focus_lost",
		"show_damage_numbers",
		"show_player_health_bar",
		"show_boss_health_bar",
		"enemy_health_scale",
		"enemy_damage_scale",
		"enemy_speed_scale",
		"ui_scale",
		"screen_shake_intensity",
		"gamepad_rumble_intensity",
		"reduce_flashes",
		"high_contrast_projectiles",
		"locale",
		"input_bindings",
		"gamepad_deadzone",
	]:
		if legacy_meta_progress.has(key):
			migrated_data[key] = legacy_meta_progress[key]
	var migrated := ProductSettings.from_dict(migrated_data)
	last_error = save_settings(migrated)
	return migrated


func _temporary_path() -> String:
	return settings_path() + ".tmp"


func _backup_path() -> String:
	return settings_path() + ".bak"


func _write_document(path: String, data: Dictionary) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({
		"save_version": SAVE_VERSION,
		"settings": data,
	}))
	file.flush()
	file.close()
	return OK


func _read_settings_dictionary(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	file.close()
	if parse_error != OK or not json.data is Dictionary:
		return null
	var document := json.data as Dictionary
	if int(document.get("save_version", -1)) != SAVE_VERSION:
		return null
	var data: Variant = document.get("settings", null)
	return data.duplicate(true) if data is Dictionary else null


func _promote_recovered_settings(data: Dictionary) -> Error:
	var temporary_path := _temporary_path()
	var write_error := _write_document(temporary_path, data)
	if write_error != OK:
		return write_error
	if not _read_settings_dictionary(temporary_path) is Dictionary:
		_remove_file(temporary_path)
		return ERR_INVALID_DATA
	if FileAccess.file_exists(settings_path()):
		var remove_error := _remove_file(settings_path())
		if remove_error != OK:
			_remove_file(temporary_path)
			return remove_error
	return DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temporary_path),
		ProjectSettings.globalize_path(settings_path()),
	)


func _remove_file(path: String) -> Error:
	if not FileAccess.file_exists(path):
		return OK
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
