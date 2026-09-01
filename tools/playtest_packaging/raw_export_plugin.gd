@tool
extends EditorPlugin

class RawPngExport extends EditorExportPlugin:
	var raw_count := 0

	func _get_name() -> String:
		return "ExperimentalPlaytestRawPng"

	func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
		# Keep imported .ctex resources AND byte-exact PNGs required by preview validation.
		if path.begins_with("res://game/") and path.ends_with(".png"):
			add_file(path, FileAccess.get_file_as_bytes(path), false)
			raw_count += 1

	func _export_end() -> void:
		print("PLAYTEST_RAW_PNG_EXPORTED count=%d" % raw_count)

var exporter: EditorExportPlugin = null

func _enter_tree() -> void:
	if not _validate_build_environment():
		return
	exporter = RawPngExport.new()
	add_export_plugin(exporter)

func _exit_tree() -> void:
	if exporter != null:
		remove_export_plugin(exporter)
		exporter = null

func _validate_build_environment() -> bool:
	# This runs at our plugin entry, NOT before EditorNode or arbitrary project code.
	var report: Dictionary = _guard_report("plugin-entry")
	if not report.failures.is_empty():
		print("BUILD_GUARD_FAIL " + JSON.stringify(report))
		OS.kill(OS.get_process_id())
		# Self-owned failure only; the outer owned-process watchdog remains bounded.
		while true:
			OS.delay_msec(50)
	print("BUILD_GUARD_OK " + JSON.stringify(report))
	return true

func _guard_report(assurance: String) -> Dictionary:
	var user_arguments: PackedStringArray = OS.get_cmdline_user_args()
	var engine_arguments: PackedStringArray = OS.get_cmdline_args()
	var editor_hint: bool = Engine.is_editor_hint()
	var phase: String = ""
	var phase_ok: bool = user_arguments.size() == 2 and user_arguments[0] == "--guard-phase"
	if phase_ok:
		phase = user_arguments[1]
	var debug_count: int = engine_arguments.count("--export-debug")
	var script_count: int = engine_arguments.count("--script") + engine_arguments.count("-s")
	var conflicts: bool = "--import" in engine_arguments
	for argument in engine_arguments:
		if argument.begins_with("--export") and argument != "--export-debug":
			conflicts = true
	# --import is consumed by Main::setup. The pinned outer argv proves import;
	# this API only supplies editor/phase consistency and visible conflicts.
	if assurance == "version-info-early":
		phase_ok = phase_ok and phase == "version-info" and not editor_hint \
			and not conflicts and debug_count == 0 and script_count <= 1
	else:
		phase_ok = phase_ok and editor_hint and not conflicts and script_count == 0 \
			and ((phase == "import" and debug_count == 0) or (phase == "export" and debug_count == 1))
	var version: Dictionary = Engine.get_version_info()
	var report: Dictionary = {"schema_version": 2,
		"termination_contract": "godot-4.7.1-windows-self-kill-v1",
		"platform": OS.get_name(), "phase": phase, "assurance_stage": assurance,
		"pid": OS.get_process_id(), "engine_arguments": engine_arguments,
		"user_arguments": user_arguments, "editor_hint": editor_hint,
		"appdata": OS.get_environment("APPDATA"), "localappdata": OS.get_environment("LOCALAPPDATA"),
		"user_data": OS.get_user_data_dir(),
		"expected_appdata": OS.get_environment("GOGOBRO_TEST_EXPECTED_APPDATA"),
		"expected_localappdata": OS.get_environment("GOGOBRO_TEST_EXPECTED_LOCALAPPDATA"),
		"expected_user_data": OS.get_environment("GOGOBRO_TEST_EXPECTED_USER_DATA_DIR"), "version": version}
	var version_ok: bool = version.major == 4 and version.minor == 7 and version.patch == 1 \
		and version.status == "stable" and version.build == "official" \
		and version.hash == "a13da4feb8d8aefc283c3763d33a2f170a18d541" and version.hex == 263937 \
		and version.string == "4.7.1-stable (official)" and version.timestamp == 0
	var checks: Dictionary = {"phase": phase_ok, "version": version_ok, "platform": report.platform == "Windows",
		"expected_nonempty": not report.expected_appdata.is_empty() and not report.expected_localappdata.is_empty() and not report.expected_user_data.is_empty(),
		"appdata": _canonical(report.appdata) == _canonical(report.expected_appdata),
		"localappdata": _canonical(report.localappdata) == _canonical(report.expected_localappdata),
		"user_data": _canonical(report.user_data) == _canonical(report.expected_user_data)}
	var failures: Array[String] = []
	for key in checks:
		if not checks[key]:
			failures.append(key)
	report["checks"] = checks
	report["failures"] = failures
	return report

func _canonical(value: String) -> String:
	return value.replace("\\", "/").simplify_path()
