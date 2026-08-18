class_name RollingFileLogger
extends Logger


const DEFAULT_LOG_PATH := "user://logs/latest.log"
const DEFAULT_MAX_BYTES := 1024 * 1024
const DEFAULT_COMPACT_BYTES := 768 * 1024
const REPEAT_WINDOW_MSEC := 1000
const MAX_REPEAT_KEYS := 256
const MAX_MESSAGE_CHARACTERS := 16_000
const MAX_RECORD_CHARACTERS := 20_000

var log_path: String
var max_bytes: int
var compact_bytes: int

var _mutex := Mutex.new()
var _repeat_states: Dictionary = {}
var _active_thread_ids: Dictionary = {}
var _base_context: Dictionary = {}
var _runtime_context: Dictionary = {}


func _init(
	path: String = DEFAULT_LOG_PATH,
	maximum_bytes: int = DEFAULT_MAX_BYTES,
	compact_to_bytes: int = DEFAULT_COMPACT_BYTES
) -> void:
	log_path = path
	max_bytes = maxi(1024, maximum_bytes)
	compact_bytes = clampi(compact_to_bytes, 512, max_bytes)
	var build_version := str(ProjectSettings.get_setting("application/config/version", "")).strip_edges()
	_base_context = {
		"build": build_version if not build_version.is_empty() else "dev",
		"skin": str(ProjectSettings.get_setting("presentation/skin_manifest", "")),
	}
	_mutex.lock()
	_prepare_path_locked()
	_compact_if_needed_locked()
	_mutex.unlock()


func _log_message(message: String, error: bool) -> void:
	# Routine stdout is intentionally excluded. Product events use GameLog's
	# structured API; the engine bridge is reserved for stderr and diagnostics.
	if error:
		write_record("ERROR", &"engine", message)


func _log_error(
	function: String,
	file: String,
	line: int,
	code: String,
	rationale: String,
	_editor_notify: bool,
	error_type: int,
	_script_backtraces: Array[ScriptBacktrace]
) -> void:
	var level := "WARNING" if error_type == Logger.ERROR_TYPE_WARNING else "ERROR"
	var detail := rationale if not rationale.is_empty() else code
	write_record(
		level,
		&"engine",
		"%s:%d %s: %s" % [file, line, function, detail]
	)


func write_record(
	level: String,
	category: StringName,
	message: String,
	context: Dictionary = {},
	monotonic_msec: int = -1
) -> void:
	var now := Time.get_ticks_msec() if monotonic_msec < 0 else monotonic_msec
	var normalized_level := level.to_upper()
	var safe_message := _single_line(message)
	var key := "%s|%s|%s" % [normalized_level, category, safe_message]
	var suppressible := normalized_level == "ERROR" or normalized_level == "WARNING"
	# File APIs may themselves emit an engine error. The mutex is re-entrant, so
	# track the owning thread as well and discard only that recursive callback.
	if not _enter_write():
		return
	if suppressible and _suppress_or_roll_window_locked(
		key, normalized_level, category, safe_message, context, now
	):
		_leave_write()
		return
	_append_line_locked(_format_line(normalized_level, category, safe_message, context))
	_leave_write()


func flush_due(monotonic_msec: int = -1, force: bool = false) -> void:
	var now := Time.get_ticks_msec() if monotonic_msec < 0 else monotonic_msec
	if not _enter_write():
		return
	for raw_key: Variant in _repeat_states.keys():
		var key := str(raw_key)
		var state := _repeat_states.get(key, {}) as Dictionary
		if not force and now - int(state.get("last_seen", now)) < REPEAT_WINDOW_MSEC:
			continue
		_append_suppression_summary_locked(state)
		_repeat_states.erase(key)
	_leave_write()


func close() -> void:
	flush_due(-1, true)


func set_runtime_context(context: Dictionary) -> void:
	if not _enter_write():
		return
	_runtime_context = context.duplicate(true)
	_leave_write()


func _enter_write() -> bool:
	_mutex.lock()
	var thread_id := OS.get_thread_caller_id()
	if _active_thread_ids.has(thread_id):
		_mutex.unlock()
		return false
	_active_thread_ids[thread_id] = true
	return true


func _leave_write() -> void:
	_active_thread_ids.erase(OS.get_thread_caller_id())
	_mutex.unlock()


func _suppress_or_roll_window_locked(
	key: String,
	level: String,
	category: StringName,
	message: String,
	context: Dictionary,
	now: int
) -> bool:
	if _repeat_states.has(key):
		var state := _repeat_states[key] as Dictionary
		if now - int(state.get("window_start", now)) < REPEAT_WINDOW_MSEC:
			state["suppressed"] = int(state.get("suppressed", 0)) + 1
			state["last_seen"] = now
			_repeat_states[key] = state
			return true
		_append_suppression_summary_locked(state)
	if _repeat_states.size() >= MAX_REPEAT_KEYS:
		var oldest_key := str(_repeat_states.keys()[0])
		_append_suppression_summary_locked(_repeat_states[oldest_key] as Dictionary)
		_repeat_states.erase(oldest_key)
	_repeat_states[key] = {
		"level": level,
		"category": category,
		"message": message,
		"context": _merged_context(context),
		"window_start": now,
		"last_seen": now,
		"suppressed": 0,
	}
	return false


func _append_suppression_summary_locked(state: Dictionary) -> void:
	var count := int(state.get("suppressed", 0))
	if count <= 0:
		return
	_append_line_locked(_format_line(
		str(state.get("level", "WARNING")),
		StringName(str(state.get("category", "engine"))),
		"Repeated message suppressed %d times: %s" % [count, str(state.get("message", ""))],
		state.get("context", {}) as Dictionary
	))


func _format_line(
	level: String,
	category: StringName,
	message: String,
	context: Dictionary
) -> String:
	var merged_context := _merged_context(context)
	var suffix := ""
	if not merged_context.is_empty():
		suffix = " " + JSON.stringify(merged_context)
	return "[%sZ] [%s] [%s] %s%s\n" % [
		Time.get_datetime_string_from_system(true, false),
		level,
		category,
		message,
		suffix,
	]


func _merged_context(context: Dictionary) -> Dictionary:
	var result := _base_context.duplicate(true)
	result.merge(_runtime_context, true)
	result.merge(context, true)
	return result


func _single_line(message: String) -> String:
	var result := message.replace("\r", "\\r").replace("\n", "\\n")
	if result.length() > MAX_MESSAGE_CHARACTERS:
		result = result.substr(0, MAX_MESSAGE_CHARACTERS - 1) + "…"
	return result


func _prepare_path_locked() -> void:
	var absolute_directory := ProjectSettings.globalize_path(log_path.get_base_dir())
	DirAccess.make_dir_recursive_absolute(absolute_directory)
	if not FileAccess.file_exists(log_path):
		var file := FileAccess.open(log_path, FileAccess.WRITE)
		if file != null:
			file.flush()


func _append_line_locked(line: String) -> void:
	var character_limit := mini(
		MAX_RECORD_CHARACTERS, maxi(32, floori(float(max_bytes - 64) / 4.0))
	)
	if line.length() > character_limit:
		line = line.substr(0, character_limit - 25) + "…[record truncated]\n"
	var encoded := line.to_utf8_buffer()
	_compact_if_needed_locked(encoded.size())
	var file := FileAccess.open(log_path, FileAccess.READ_WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_buffer(encoded)
	file.flush()


func _compact_if_needed_locked(incoming_bytes: int = 0) -> void:
	if not FileAccess.file_exists(log_path):
		return
	var bytes := FileAccess.get_file_as_bytes(log_path)
	if bytes.size() + maxi(0, incoming_bytes) <= max_bytes:
		return
	var retained_limit := mini(compact_bytes, maxi(0, max_bytes - incoming_bytes))
	var target_start := maxi(0, bytes.size() - retained_limit)
	var retained_start := target_start
	while retained_start < bytes.size() and bytes[retained_start] != 10:
		retained_start += 1
	if retained_start < bytes.size():
		retained_start += 1
	else:
		retained_start = bytes.size()
	var retained := bytes.slice(retained_start)
	var file := FileAccess.open(log_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_buffer(retained)
	file.flush()
