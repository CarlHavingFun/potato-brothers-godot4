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
