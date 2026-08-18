extends Node


const LOGGER_SCRIPT := preload("res://core/logging/rolling_file_logger.gd")
const FLUSH_INTERVAL_SECONDS := 0.25
const SENSITIVE_KEY_PARTS: Array[String] = [
	"password", "passwd", "secret", "token", "credential", "authorization", "cookie",
]

var logger: RollingFileLogger
var _flush_elapsed := 0.0


func _init() -> void:
	logger = LOGGER_SCRIPT.new()
	OS.add_logger(logger)


func _ready() -> void:
	logger.set_runtime_context(_runtime_context())
	info(&"lifecycle", "session_started")


func _process(delta: float) -> void:
	_flush_elapsed += delta
	if _flush_elapsed < FLUSH_INTERVAL_SECONDS:
		return
	_flush_elapsed = 0.0
	logger.set_runtime_context(_runtime_context())
	logger.flush_due()


func _exit_tree() -> void:
	if logger == null:
		return
	info(&"lifecycle", "session_stopped")
	logger.close()


func info(category: StringName, message: String, context: Dictionary = {}) -> void:
	_write("INFO", category, message, context)


func warning(category: StringName, message: String, context: Dictionary = {}) -> void:
	_write("WARNING", category, message, context)


func error(category: StringName, message: String, context: Dictionary = {}) -> void:
	_write("ERROR", category, message, context)


func _write(level: String, category: StringName, message: String, context: Dictionary) -> void:
	if logger == null:
		return
	logger.set_runtime_context(_runtime_context())
	logger.write_record(level, category, message, _redact_dictionary(context))


func _runtime_context() -> Dictionary:
	var build_version := str(
		ProjectSettings.get_setting("application/config/version", "")
	).strip_edges()
	var context := {
		"build": build_version if not build_version.is_empty() else "dev",
		"skin": str(ProjectSettings.get_setting("presentation/skin_manifest", "")),
	}
	var global := get_node_or_null("/root/Global")
	if global == null:
		return context
	var run: Variant = global.get("current_run")
	if typeof(run) != TYPE_OBJECT or not is_instance_valid(run):
		return context
	context["wave"] = int(run.get("wave"))
	context["seed"] = int(run.get("random_seed"))
	return context


func _redact_dictionary(source: Dictionary) -> Dictionary:
	var result := {}
	for raw_key: Variant in source:
		var key := str(raw_key)
		var value: Variant = source[raw_key]
		if _is_sensitive_key(key):
			result[key] = "[redacted]"
		elif value is Dictionary:
			result[key] = _redact_dictionary(value as Dictionary)
		elif value is Array:
			result[key] = _redact_array(value as Array)
		elif typeof(value) == TYPE_OBJECT:
			result[key] = "[object]"
		else:
			result[key] = value
	return result


func _redact_array(source: Array) -> Array:
	var result: Array = []
	for value: Variant in source:
		if value is Dictionary:
			result.append(_redact_dictionary(value as Dictionary))
		elif value is Array:
			result.append(_redact_array(value as Array))
		elif typeof(value) == TYPE_OBJECT:
			result.append("[object]")
		else:
			result.append(value)
	return result


func _is_sensitive_key(key: String) -> bool:
	var normalized := key.to_lower()
	for fragment: String in SENSITIVE_KEY_PARTS:
		if normalized.contains(fragment):
			return true
	return false
