#!/usr/bin/env -S godot -s
extends "res://addons/gdUnit4/bin/GdUnitCmdTool.gd"


var _isolation_ready := false


func _initialize() -> void:
	var expected_appdata := OS.get_environment("GOGOBRO_TEST_EXPECTED_APPDATA")
	var expected_local := OS.get_environment("GOGOBRO_TEST_EXPECTED_LOCALAPPDATA")
	var expected_user_data := OS.get_environment("GOGOBRO_TEST_EXPECTED_USER_DATA_DIR")
	var actual_appdata := OS.get_environment("APPDATA")
	var actual_local := OS.get_environment("LOCALAPPDATA")
	var actual_user_data := OS.get_user_data_dir()
	if not _matches(expected_appdata, actual_appdata) or not _matches(expected_local, actual_local) or not _matches(expected_user_data, actual_user_data):
		print("ISOLATION_GUARD_FAIL expected_appdata=%s actual_appdata=%s expected_local=%s actual_local=%s expected_user=%s actual_user=%s" % [expected_appdata, actual_appdata, expected_local, actual_local, expected_user_data, actual_user_data])
		quit(2)
		return
	print("ISOLATION_GUARD_OK appdata=%s localappdata=%s user_data=%s" % [actual_appdata, actual_local, actual_user_data])
	_isolation_ready = true
	super._initialize()


func _finalize() -> void:
	if _isolation_ready:
		super._finalize()


func _matches(expected: String, actual: String) -> bool:
	return not expected.is_empty() and _canonical_path(expected) == _canonical_path(actual)


func _canonical_path(value: String) -> String:
	return value.replace("\\", "/").simplify_path()
