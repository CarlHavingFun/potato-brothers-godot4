class_name GogoSettingsService
extends RefCounted

const SETTINGS_PATH := "user://GOGOBRO/settings.json"

var values: Dictionary = {
	"master_volume": 1.0,
	"music_volume": 0.8,
	"effects_volume": 0.9,
	"language": "cn",
	"fullscreen": false,
}


func load_settings() -> Error:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return OK
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return ERR_FILE_CORRUPT
	for key in values:
		if parsed.has(key): values[key] = parsed[key]
	return OK


func apply_display_settings() -> void:
	var target_mode := resolved_window_mode()
	if DisplayServer.window_get_mode() != target_mode:
		DisplayServer.window_set_mode(target_mode)


func resolved_window_mode() -> DisplayServer.WindowMode:
	return DisplayServer.WINDOW_MODE_FULLSCREEN \
		if bool(values.get("fullscreen", false)) \
		else DisplayServer.WINDOW_MODE_WINDOWED


func save_settings() -> Error:
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SETTINGS_PATH.get_base_dir()))
	if directory_error != OK:
		return directory_error
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(values, "\t"))
	file.flush()
	return file.get_error()
