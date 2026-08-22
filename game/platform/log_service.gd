class_name GogoLogService
extends Node

const LOG_DIRECTORY := "user://GOGOBRO/logs"
const LOG_PATH := LOG_DIRECTORY + "/game.log"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LOG_DIRECTORY))


func info(message: String) -> void:
	_write("INFO", message)


func warning(message: String) -> void:
	_write("WARN", message)


func error(message: String) -> void:
	_write("ERROR", message)


func _write(level: String, message: String) -> void:
	var file := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_line("%s [%s] %s" % [Time.get_datetime_string_from_system(), level, message])
