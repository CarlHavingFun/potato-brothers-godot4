extends GdUnitTestSuite


const Service = preload("res://tools/video_sprites/video_sprite_job_service.gd")
const TEMP_ROOT := "res://reports/video_sprite_job_service"
const PIPELINE_ROOT := TEMP_ROOT + "/pipeline"
const SPRITE_GEN_ROOT := TEMP_ROOT + "/sprite-gen"
const PYTHON_PATH := TEMP_ROOT + "/python.exe"
const FFPROBE_PATH := TEMP_ROOT + "/ffprobe.exe"
const SOURCE_VIDEO := TEMP_ROOT + "/clip.mp4"

var launched_arguments := PackedStringArray()


func before_test() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PIPELINE_ROOT + "/pixelmotion2d"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PIPELINE_ROOT + "/characters"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SPRITE_GEN_ROOT + "/scripts"))
	_write(PYTHON_PATH, "fixture")
	_write(FFPROBE_PATH, "fixture")
	_write(SOURCE_VIDEO, "fixture")
	_write(PIPELINE_ROOT + "/pixelmotion2d/video_sprite_library.py", "# fixture")
	_write(PIPELINE_ROOT + "/characters.json", "{\"sprite\": {}}")
	_write(PIPELINE_ROOT + "/characters/niko-walk.json", "{\"sprite\": {}}")
	_write(SPRITE_GEN_ROOT + "/scripts/prepare_sprite_run.py", "# fixture")
	_write(SPRITE_GEN_ROOT + "/scripts/extract_sprite_row_frames.py", "# fixture")


func after_test() -> void:
	launched_arguments = PackedStringArray()


func test_single_video_job_uses_only_external_staging_and_never_res_output() -> void:
	var service := Service.new()
	var staging := ProjectSettings.globalize_path("user://video_sprite_workspace/external-job")
	var result: Dictionary = service.start_single_video_job(
		_dependencies(staging), Callable(self, "_fake_launcher"), "external-job"
	)

	assert_array(result.get("errors", PackedStringArray())).is_empty()
	assert_str(result.get("output_directory", "")).is_equal(staging)
	assert_str(result.get("output_directory", "")).not_contains(ProjectSettings.globalize_path("res://"))
	assert_str(result.get("receipt_path", "")).contains("user://video_sprite_jobs/")
	assert_array(launched_arguments).contains("--output-directory")
	assert_array(launched_arguments).contains(staging)
	assert_array(launched_arguments).not_contains("res://tools/sprites/niko_video_library")


func test_single_video_job_keeps_legacy_config_default_and_uses_a_unique_external_staging_default() -> void:
	var service := Service.new()
	var params := _dependencies("")
	params.erase("staging_directory")
	params.erase("config_path")
	var result: Dictionary = service.start_single_video_job(params, Callable(self, "_fake_launcher"), "defaulted-job")

	assert_array(result.get("errors", PackedStringArray())).is_empty()
	assert_str(result.get("output_directory", "")).contains("video_sprite_workspace/defaulted-job")
	assert_array(launched_arguments).contains(ProjectSettings.globalize_path(PIPELINE_ROOT + "/characters/niko-walk.json"))


func test_single_video_job_rejects_project_staging_path() -> void:
	var service := Service.new()
	var params := _dependencies(ProjectSettings.globalize_path("res://tools/sprites/bad"))
	var result: Dictionary = service.start_single_video_job(params, Callable(self, "_fake_launcher"), "bad")

	assert_str("\n".join(result.get("errors", PackedStringArray()))).contains("outside res://")


func test_single_video_job_rejects_a_sibling_prefix_escape() -> void:
	var service := Service.new()
	var root := ProjectSettings.globalize_path("user://video_sprite_workspace")
	var result: Dictionary = service.start_single_video_job(
		_dependencies(root + "-escape/clip"), Callable(self, "_fake_launcher"), "prefix-escape"
	)

	assert_str("\n".join(result.get("errors", PackedStringArray()))).contains("staging_directory")


func test_staging_root_link_detector_rejects_a_root_reparse_point() -> void:
	var root := ProjectSettings.globalize_path("user://video_sprite_workspace")
	var error := Service.validate_staging_directory(root.path_join("safe-job"), Callable(self, "_root_is_link"))

	assert_str(error).contains("symlink, junction, or reparse point")


func test_dependency_status_names_every_ui_dependency_and_reports_paths() -> void:
	var service := Service.new()
	var status: Dictionary = service.dependency_status(_dependencies("E:/not-used"))

	assert_array(status.keys()).contains_exactly_in_any_order([
		"python", "pixelmotion", "sprite_gen", "worker_script", "ffprobe", "ready",
	])
	for dependency in ["python", "pixelmotion", "sprite_gen", "worker_script", "ffprobe"]:
		var value := status[dependency] as Dictionary
		assert_bool(value.get("resolved", false)).is_true()
		assert_str(value.get("path", "")).is_not_empty()
	assert_bool(status.get("ready", false)).is_true()


func test_cancellation_writes_a_job_token_scoped_cooperative_request_and_polls_terminal() -> void:
	var service := Service.new()
	var result: Dictionary = service.start_single_video_job(
		_dependencies(ProjectSettings.globalize_path("user://video_sprite_workspace/cancel-job")),
		Callable(self, "_fake_launcher"),
		"cancel-job"
	)
	assert_array(result.get("errors", PackedStringArray())).is_empty()
	var cancelled: Dictionary = service.cancel_job("cancel-job")
	assert_array(cancelled.get("errors", PackedStringArray())).is_empty()
	assert_str(cancelled.get("state", "")).is_equal("cancellation_requested")
	var request := _read_absolute(ProjectSettings.globalize_path(str(result["cancel_request_path"])))
	assert_str(request.get("job_id", "")).is_equal("cancel-job")
	assert_str(request.get("job_token", "")).is_equal(str(result["job_token"]))
	_write_absolute(ProjectSettings.globalize_path(str(result["receipt_path"])), JSON.stringify({
		"job_id": "cancel-job", "job_token": result["job_token"], "pid": 4321, "state": "cancelled"
	}))
	assert_str(service.poll_job("cancel-job").get("state", "")).is_equal("cancelled")


func test_terminal_worker_receipt_is_normalized_and_never_terminates_a_reused_pid() -> void:
	var service := Service.new()
	var result: Dictionary = service.start_single_video_job(
		_dependencies(ProjectSettings.globalize_path("user://video_sprite_workspace/complete-job")),
		Callable(self, "_fake_launcher"),
		"complete-job"
	)
	_write_absolute(ProjectSettings.globalize_path(str(result["receipt_path"])), JSON.stringify({
		"job_id": "complete-job", "pid": 4321, "state": "worker_complete"
	}))

	var complete: Dictionary = service.poll_job("complete-job", Callable(), Callable(self, "_running_process"))
	assert_str(complete.get("state", "")).is_equal("complete")
	var cancelled: Dictionary = service.cancel_job("complete-job")
	assert_str(cancelled.get("state", "")).is_equal("complete")


func test_cancellation_requires_the_receipt_job_token_to_match_the_tracked_job() -> void:
	var service := Service.new()
	var result: Dictionary = service.start_single_video_job(
		_dependencies(ProjectSettings.globalize_path("user://video_sprite_workspace/pid-mismatch")),
		Callable(self, "_fake_launcher"),
		"pid-mismatch"
	)
	_write_absolute(ProjectSettings.globalize_path(str(result["receipt_path"])), JSON.stringify({
		"job_id": "pid-mismatch", "job_token": "wrong-token", "pid": 9999, "state": "running"
	}))
	var cancelled: Dictionary = service.cancel_job("pid-mismatch")
	assert_str("\n".join(cancelled.get("errors", PackedStringArray()))).contains("token")


func test_cancellation_rejects_a_numeric_receipt_job_id_as_corrupt() -> void:
	var service := Service.new()
	var result: Dictionary = service.start_single_video_job(
		_dependencies(ProjectSettings.globalize_path("user://video_sprite_workspace/numeric-job-id")),
		Callable(self, "_fake_launcher"),
		"123"
	)
	_write_absolute(ProjectSettings.globalize_path(str(result["receipt_path"])), JSON.stringify({
		"job_id": 123, "job_token": result["job_token"], "pid": 4321, "state": "running"
	}))

	var cancelled: Dictionary = service.cancel_job("123")
	assert_str("\n".join(cancelled.get("errors", PackedStringArray()))).contains("malformed")
	assert_bool(FileAccess.file_exists(ProjectSettings.globalize_path(str(result["cancel_request_path"])))).is_false()


func test_cancellation_rejects_an_unknown_receipt_state_as_corrupt() -> void:
	var service := Service.new()
	var result: Dictionary = service.start_single_video_job(
		_dependencies(ProjectSettings.globalize_path("user://video_sprite_workspace/unknown-cancel-state")),
		Callable(self, "_fake_launcher"),
		"unknown-cancel-state"
	)
	_write_absolute(ProjectSettings.globalize_path(str(result["receipt_path"])), JSON.stringify({
		"job_id": "unknown-cancel-state", "job_token": result["job_token"], "pid": 4321, "state": "unknown"
	}))

	var cancelled: Dictionary = service.cancel_job("unknown-cancel-state")
	assert_str("\n".join(cancelled.get("errors", PackedStringArray()))).contains("malformed")
	assert_bool(FileAccess.file_exists(ProjectSettings.globalize_path(str(result["cancel_request_path"])))).is_false()


func test_polling_marks_an_exited_queued_worker_failed_loudly() -> void:
	var service := Service.new()
	service.start_single_video_job(
		_dependencies(ProjectSettings.globalize_path("user://video_sprite_workspace/exited-job")),
		Callable(self, "_fake_launcher"),
		"exited-job"
	)
	var failed: Dictionary = service.poll_job("exited-job", Callable(self, "_queued_receipt"), Callable(self, "_exited_process"), Callable(self, "_exit_code"))
	assert_str(failed.get("state", "")).is_equal("failed")
	assert_str(failed.get("error", "")).contains("exit 17")


func test_polling_marks_a_nonterminal_receipt_without_a_tracked_pid_failed() -> void:
	var service := Service.new()
	service.track_job("missing-pid", "user://video_sprite_jobs/missing-pid.json")

	var failed: Dictionary = service.poll_job("missing-pid", Callable(self, "_missing_pid_receipt"))
	assert_str(failed.get("state", "")).is_equal("failed")
	assert_str(failed.get("error", "")).contains("no recorded worker PID")


func test_polling_persists_a_failed_terminal_receipt_when_the_receipt_is_missing_after_exit() -> void:
	var service := Service.new()
	var result: Dictionary = service.start_single_video_job(
		_dependencies(ProjectSettings.globalize_path("user://video_sprite_workspace/missing-receipt")),
		Callable(self, "_fake_launcher"),
		"missing-receipt"
	)
	var receipt_path := ProjectSettings.globalize_path(str(result["receipt_path"]))
	DirAccess.remove_absolute(receipt_path)

	var failed: Dictionary = service.poll_job("missing-receipt", Callable(self, "_missing_receipt"), Callable(self, "_exited_process"), Callable(self, "_exit_code"))
	assert_str(failed.get("state", "")).is_equal("failed")
	assert_str(_read_absolute(receipt_path).get("state", "")).is_equal("failed")


func test_polling_persists_an_atomic_fallback_receipt_when_the_receipt_is_corrupt_after_exit() -> void:
	var service := Service.new()
	var result: Dictionary = service.start_single_video_job(
		_dependencies(ProjectSettings.globalize_path("user://video_sprite_workspace/corrupt-receipt")),
		Callable(self, "_fake_launcher"),
		"corrupt-receipt"
	)
	var receipt_path := ProjectSettings.globalize_path(str(result["receipt_path"]))
	var fallback_path := receipt_path.trim_suffix(".json") + ".failed.json"
	DirAccess.remove_absolute(fallback_path)
	_write_absolute(receipt_path, "{not-json")

	var failed: Dictionary = service.poll_job("corrupt-receipt", Callable(self, "_missing_receipt"), Callable(self, "_exited_process"), Callable(self, "_exit_code"))
	assert_str(failed.get("state", "")).is_equal("failed")
	assert_str(_read_absolute(fallback_path).get("state", "")).is_equal("failed")


func test_polling_keeps_a_stateful_nonterminal_response_while_a_missing_receipt_worker_runs() -> void:
	var service := Service.new()
	service.start_single_video_job(
		_dependencies(ProjectSettings.globalize_path("user://video_sprite_workspace/awaiting-receipt")),
		Callable(self, "_fake_launcher"),
		"awaiting-receipt"
	)

	var pending: Dictionary = service.poll_job("awaiting-receipt", Callable(self, "_missing_receipt"), Callable(self, "_running_process"))
	assert_str(pending.get("state", "")).is_equal("running")
	assert_str(pending.get("error", "")).contains("missing or malformed")


func test_polling_treats_legal_json_with_a_wrong_job_id_as_corrupt_while_worker_runs() -> void:
	var service := Service.new()
	service.start_single_video_job(
		_dependencies(ProjectSettings.globalize_path("user://video_sprite_workspace/wrong-job-id")),
		Callable(self, "_fake_launcher"),
		"wrong-job-id"
	)

	var pending: Dictionary = service.poll_job("wrong-job-id", Callable(self, "_wrong_job_id_receipt"), Callable(self, "_running_process"))
	assert_str(pending.get("state", "")).is_equal("running")
	assert_str(pending.get("error", "")).contains("corrupt")


func test_polling_treats_legal_json_without_state_as_failed_after_worker_exit() -> void:
	var service := Service.new()
	service.start_single_video_job(
		_dependencies(ProjectSettings.globalize_path("user://video_sprite_workspace/missing-state")),
		Callable(self, "_fake_launcher"),
		"missing-state"
	)

	var failed: Dictionary = service.poll_job("missing-state", Callable(self, "_missing_state_receipt"), Callable(self, "_exited_process"), Callable(self, "_exit_code"))
	assert_str(failed.get("state", "")).is_equal("failed")
	assert_str(failed.get("error", "")).contains("corrupt")


func test_polling_treats_missing_and_bad_typed_receipt_fields_as_corrupt() -> void:
	var service := Service.new()
	service.start_single_video_job(
		_dependencies(ProjectSettings.globalize_path("user://video_sprite_workspace/bad-fields")),
		Callable(self, "_fake_launcher"),
		"bad-fields"
	)

	var missing_id: Dictionary = service.poll_job("bad-fields", Callable(self, "_missing_job_id_receipt"), Callable(self, "_running_process"))
	assert_str(missing_id.get("state", "")).is_equal("running")
	assert_str(missing_id.get("error", "")).contains("corrupt")
	var bad_pid: Dictionary = service.poll_job("bad-fields", Callable(self, "_bad_pid_receipt"), Callable(self, "_running_process"))
	assert_str(bad_pid.get("state", "")).is_equal("running")
	assert_str(bad_pid.get("error", "")).contains("corrupt")
	var bad_state: Dictionary = service.poll_job("bad-fields", Callable(self, "_bad_state_receipt"), Callable(self, "_running_process"))
	assert_str(bad_state.get("state", "")).is_equal("running")
	assert_str(bad_state.get("error", "")).contains("corrupt")


func test_polling_reports_and_caches_terminal_failure_when_no_receipt_path_can_be_written() -> void:
	var service := Service.new()
	service.start_single_video_job(
		_dependencies(ProjectSettings.globalize_path("user://video_sprite_workspace/unpersisted-failure")),
		Callable(self, "_fake_launcher"),
		"unpersisted-failure"
	)

	var failed: Dictionary = service.poll_job("unpersisted-failure", Callable(self, "_missing_receipt"), Callable(self, "_exited_process"), Callable(self, "_exit_code"), Callable(self, "_failing_receipt_writer"))
	assert_str(failed.get("state", "")).is_equal("failed")
	assert_bool(failed.get("receipt_persisted", true)).is_false()
	assert_array(failed.get("errors", PackedStringArray())).is_not_empty()
	var cached: Dictionary = service.poll_job("unpersisted-failure")
	assert_str(cached.get("state", "")).is_equal("failed")
	assert_bool(cached.get("receipt_persisted", true)).is_false()


func test_job_launch_does_not_overwrite_a_worker_completed_receipt() -> void:
	var service := Service.new()
	var result: Dictionary = service.start_single_video_job(
		_dependencies(ProjectSettings.globalize_path("user://video_sprite_workspace/race-job")),
		Callable(self, "_racing_launcher"),
		"race-job"
	)
	var receipt := _read_absolute(ProjectSettings.globalize_path(str(result["receipt_path"])))
	assert_str(receipt.get("state", "")).is_equal("worker_complete")


func test_dependency_status_preserves_missing_candidates_and_resolution_sources() -> void:
	var service := Service.new()
	var status: Dictionary = service.dependency_status({
		"pipeline_root": "E:/missing-pixelmotion",
		"sprite_gen_root": "E:/missing-sprite-gen",
		"python_executable": "E:/missing-python.exe",
		"ffprobe_executable": "E:/missing-ffprobe.exe",
	})
	for name in ["python", "pixelmotion", "sprite_gen", "worker_script", "ffprobe"]:
		var value := status[name] as Dictionary
		assert_str(value.get("path", "")).is_not_empty()
		assert_str(value.get("source", "")).is_not_empty()
		assert_str(value.get("resolution", "")).is_not_empty()


func _dependencies(staging: String) -> Dictionary:
	return {
		"source_video": ProjectSettings.globalize_path(SOURCE_VIDEO),
		"staging_directory": staging,
		"pipeline_root": ProjectSettings.globalize_path(PIPELINE_ROOT),
		"sprite_gen_root": ProjectSettings.globalize_path(SPRITE_GEN_ROOT),
		"python_executable": ProjectSettings.globalize_path(PYTHON_PATH),
		"ffprobe_executable": ProjectSettings.globalize_path(FFPROBE_PATH),
		"config_path": ProjectSettings.globalize_path(PIPELINE_ROOT + "/characters.json"),
	}


func _fake_launcher(_executable: String, arguments: PackedStringArray) -> int:
	launched_arguments = arguments
	return 4321


func _running_process(_pid: int) -> bool:
	return true


func _exited_process(_pid: int) -> bool:
	return false


func _exit_code(_pid: int) -> int:
	return 17


func _queued_receipt(_path: String) -> Dictionary:
	return {"job_id": "exited-job", "pid": 4321, "state": "queued"}


func _missing_pid_receipt(_path: String) -> Dictionary:
	return {"job_id": "missing-pid", "pid": 0, "state": "queued"}


func _missing_receipt(_path: String) -> Dictionary:
	return {}


func _wrong_job_id_receipt(_path: String) -> Dictionary:
	return {"job_id": "other-job", "state": "running", "pid": 4321}


func _missing_state_receipt(_path: String) -> Dictionary:
	return {"job_id": "missing-state", "pid": 4321}


func _missing_job_id_receipt(_path: String) -> Dictionary:
	return {"state": "running", "pid": 4321}


func _bad_pid_receipt(_path: String) -> Dictionary:
	return {"job_id": "bad-fields", "state": "running", "pid": "not-a-pid"}


func _bad_state_receipt(_path: String) -> Dictionary:
	return {"job_id": "bad-fields", "state": "unknown", "pid": 4321}


func _failing_receipt_writer(_path: String, _receipt: Dictionary) -> bool:
	return false


func _root_is_link(path: String) -> bool:
	return path == ProjectSettings.globalize_path("user://video_sprite_workspace")


func _racing_launcher(_executable: String, arguments: PackedStringArray) -> int:
	var receipt_index := arguments.find("--job-receipt") + 1
	_write_absolute(arguments[receipt_index], JSON.stringify({
		"job_id": "race-job", "pid": 4321, "state": "worker_complete"
	}))
	return 4321


func _running_receipt(_path: String) -> Dictionary:
	return {"job_id": "cancel-job", "state": "running", "completed_frames": 3}


func _write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_object(file).is_not_null()
	file.store_string(content)
	file.close()


func _write_absolute(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_object(file).is_not_null()
	file.store_string(content)
	file.close()


func _read_absolute(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}
