extends GdUnitTestSuite


const LOGGER_SCRIPT := preload("res://core/logging/rolling_file_logger.gd")
const TEST_LOG_PATH := "user://tests/rolling_logger/latest.log"


func before_test() -> void:
	_cleanup_log()


func after_test() -> void:
	_cleanup_log()


func test_rotation_keeps_latest_complete_utf8_lines_below_hard_limit() -> void:
	var logger := LOGGER_SCRIPT.new(TEST_LOG_PATH, 16 * 1024, 12 * 1024)
	for index: int in range(600):
		logger.write_record(
			"INFO",
			&"rotation",
			"记录-%04d-%s" % [index, "新".repeat(80)],
			{},
			index
		)
	logger.write_record("INFO", &"rotation", "latest-marker-完整", {}, 1000)
	logger.close()

	var bytes := FileAccess.get_file_as_bytes(TEST_LOG_PATH)
	var text := FileAccess.get_file_as_string(TEST_LOG_PATH)
	assert_int(bytes.size()).is_less_equal(16 * 1024)
	assert_str(text).contains("latest-marker-完整")
	assert_bool(text.contains("�")).is_false()
	assert_bool(text.begins_with("[")).is_true()


func test_repeated_errors_are_suppressed_and_summarized() -> void:
	var logger := LOGGER_SCRIPT.new(TEST_LOG_PATH, 16 * 1024, 12 * 1024)
	for _index: int in range(100_000):
		logger.write_record("ERROR", &"runtime", "same recurring error", {}, 100)
	logger.flush_due(1200)
	logger.close()

	var text := FileAccess.get_file_as_string(TEST_LOG_PATH)
	assert_str(text).contains("Repeated message suppressed 99999 times")
	assert_int(FileAccess.get_file_as_bytes(TEST_LOG_PATH).size()).is_less_equal(16 * 1024)


func test_reopening_preserves_the_latest_tail() -> void:
	var first := LOGGER_SCRIPT.new(TEST_LOG_PATH, 64 * 1024, 48 * 1024)
	for index: int in range(200):
		first.write_record(
			"INFO", &"lifecycle", "historical-%03d-%s" % [index, "x".repeat(80)], {}, index
		)
	first.write_record("INFO", &"lifecycle", "persisted-tail", {}, 1)
	first.close()
	var reopened := LOGGER_SCRIPT.new(TEST_LOG_PATH, 4096, 3072)
	reopened.write_record("INFO", &"lifecycle", "new-session", {}, 2)
	reopened.close()

	var text := FileAccess.get_file_as_string(TEST_LOG_PATH)
	assert_str(text).contains("persisted-tail")
	assert_str(text).contains("new-session")
	assert_int(FileAccess.get_file_as_bytes(TEST_LOG_PATH).size()).is_less_equal(4096)


func test_builtin_file_logging_is_disabled_in_favor_of_the_bounded_logger() -> void:
	assert_bool(bool(ProjectSettings.get_setting(
		"debug/file_logging/enable_file_logging", true
	))).is_false()
	assert_bool(bool(ProjectSettings.get_setting(
		"debug/file_logging/enable_file_logging.pc", true
	))).is_false()
	assert_int(LOGGER_SCRIPT.DEFAULT_MAX_BYTES).is_equal(1024 * 1024)
	assert_int(LOGGER_SCRIPT.DEFAULT_COMPACT_BYTES).is_equal(768 * 1024)


func test_engine_bridge_ignores_routine_stdout_but_keeps_stderr() -> void:
	var logger := LOGGER_SCRIPT.new(TEST_LOG_PATH, 4096, 3072)
	logger._log_message("routine-output", false)
	logger._log_message("important-error", true)
	logger.close()

	var text := FileAccess.get_file_as_string(TEST_LOG_PATH)
	assert_bool(text.contains("routine-output")).is_false()
	assert_str(text).contains("important-error")
	assert_str(text).contains("\"build\":\"dev\"")
	assert_str(text).contains("\"skin\"")


func test_game_log_redacts_sensitive_context_before_persistence() -> void:
	var redacted: Dictionary = GameLog._redact_dictionary({
		"profile_id": 2,
		"access_token": "do-not-write",
		"nested": {"password": "do-not-write-either"},
	})
	assert_int(int(redacted.get("profile_id", 0))).is_equal(2)
	assert_str(str(redacted.get("access_token", ""))).is_equal("[redacted]")
	assert_str(str((redacted.get("nested", {}) as Dictionary).get("password", ""))).is_equal(
		"[redacted]"
	)


func _cleanup_log() -> void:
	if FileAccess.file_exists(TEST_LOG_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_LOG_PATH))
