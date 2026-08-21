extends GdUnitTestSuite


const Service = preload("res://tools/video_sprites/video_sprite_job_service.gd")
const TEMP_ROOT := "res://reports/video_sprite_job_service"
const PIPELINE_ROOT := TEMP_ROOT + "/pipeline"
const SPRITE_GEN_ROOT := TEMP_ROOT + "/sprite-gen"
const PYTHON_PATH := TEMP_ROOT + "/python.exe"
const FFPROBE_PATH := TEMP_ROOT + "/ffprobe.exe"
const SOURCE_VIDEO := TEMP_ROOT + "/clip.mp4"

var launched_arguments := PackedStringArray()
var terminated_pid := -1


func before_test() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PIPELINE_ROOT + "/pixelmotion2d"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SPRITE_GEN_ROOT + "/scripts"))
	_write(PYTHON_PATH, "fixture")
	_write(FFPROBE_PATH, "fixture")
	_write(SOURCE_VIDEO, "fixture")
	_write(PIPELINE_ROOT + "/pixelmotion2d/video_sprite_library.py", "# fixture")
	_write(PIPELINE_ROOT + "/characters.json", "{\"sprite\": {}}")
	_write(SPRITE_GEN_ROOT + "/scripts/prepare_sprite_run.py", "# fixture")
	_write(SPRITE_GEN_ROOT + "/scripts/extract_sprite_row_frames.py", "# fixture")


func after_test() -> void:
	launched_arguments = PackedStringArray()
	terminated_pid = -1


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


func test_single_video_job_rejects_project_staging_path() -> void:
	var service := Service.new()
	var params := _dependencies(ProjectSettings.globalize_path("res://tools/sprites/bad"))
	var result: Dictionary = service.start_single_video_job(params, Callable(self, "_fake_launcher"), "bad")

	assert_str("\n".join(result.get("errors", PackedStringArray()))).contains("outside res://")


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


func test_polling_and_cancellation_only_use_the_recorded_job_pid() -> void:
	var service := Service.new()
	var result: Dictionary = service.start_single_video_job(
		_dependencies(ProjectSettings.globalize_path("user://video_sprite_workspace/cancel-job")),
		Callable(self, "_fake_launcher"),
		"cancel-job"
	)
	assert_array(result.get("errors", PackedStringArray())).is_empty()
	var running: Dictionary = service.poll_job("cancel-job", Callable(self, "_running_receipt"))
	assert_str(running.get("state", "")).is_equal("running")
	var cancelled: Dictionary = service.cancel_job("cancel-job", Callable(self, "_fake_terminator"))
	assert_array(cancelled.get("errors", PackedStringArray())).is_empty()
	assert_str(cancelled.get("state", "")).is_equal("cancelled")
	assert_int(terminated_pid).is_equal(4321)
	assert_str(service.poll_job("cancel-job").get("state", "")).is_equal("cancelled")


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


func _fake_terminator(pid: int) -> bool:
	terminated_pid = pid
	return pid == 4321


func _running_receipt(_path: String) -> Dictionary:
	return {"job_id": "cancel-job", "state": "running", "completed_frames": 3}


func _write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_object(file).is_not_null()
	file.store_string(content)
	file.close()
