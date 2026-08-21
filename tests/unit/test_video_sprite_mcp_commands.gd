extends GdUnitTestSuite


const Commands = preload("res://mcp_commands/video_sprite_commands.gd")
const ImportJobTracker = preload(
	"res://addons/character_sprite_authoring/import_job_tracker.gd"
)
const TEMP_ROOT := "res://reports/video_sprite_mcp"
const PIPELINE_ROOT := TEMP_ROOT + "/pipeline"
const SPRITE_GEN_ROOT := TEMP_ROOT + "/sprite-gen"
const PYTHON_PATH := TEMP_ROOT + "/python.exe"

var launched_executable := ""
var launched_arguments := PackedStringArray()


class FakeJobCommands extends Node:
	var poll_count := 0

	func poll_job(job_id: String) -> Dictionary:
		poll_count += 1
		return {
			"errors": PackedStringArray(),
			"job_id": job_id,
			"state": "running" if poll_count == 1 else "complete",
		}


class FakeVideoService extends RefCounted:
	var received_params := {}

	func start_single_video_job(params: Dictionary) -> Dictionary:
		received_params = params
		return {
			"errors": PackedStringArray(),
			"job_id": "delegated-video",
			"state": "queued",
			"output_directory": "E:/external/video_sprite_workspace/delegated-video",
		}

	func poll_job(_job_id: String) -> Dictionary:
		return {"errors": PackedStringArray(["unknown job ID"])}

	func dependency_status(_params: Dictionary) -> Dictionary:
		return {"ready": true}

	func cancel_job(_job_id: String) -> Dictionary:
		return {"errors": PackedStringArray(["unknown job ID"])}


func before_test() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PIPELINE_ROOT + "/tools"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SPRITE_GEN_ROOT + "/scripts"))
	_write(PYTHON_PATH, "fixture")
	_write(PIPELINE_ROOT + "/tools/build_video_sprite_library.py", "# fixture")
	_write(PIPELINE_ROOT + "/characters.json", "{}")
	_write(SPRITE_GEN_ROOT + "/scripts/prepare_sprite_run.py", "# fixture")
	_write(SPRITE_GEN_ROOT + "/scripts/extract_sprite_row_frames.py", "# fixture")


func after_test() -> void:
	launched_executable = ""
	launched_arguments = PackedStringArray()


func test_registers_video_import_and_character_authoring_commands() -> void:
	var commands := Commands.new()
	assert_array(commands.get_commands().keys()).contains_exactly_in_any_order([
		"video_sprites.scan_directory",
		"video_sprites.import_directory",
		"video_sprites.import_video",
		"video_sprites.job_status",
		"video_sprites.dependency_status",
		"video_sprites.cancel_job",
		"video_sprites.validate_library",
		"character_sprite.import_all",
		"character_sprite.publish",
		"character_sprite.status",
	])
	commands.free()


func test_output_path_is_confined_below_tools_sprites() -> void:
	assert_str(Commands.validate_output_path("res://tools/sprites/niko_video_library")).is_empty()
	assert_str(Commands.validate_output_path("res://content_packs")).is_not_empty()
	assert_str(Commands.validate_output_path("res://tools/sprites/../content_packs")).is_not_empty()
	assert_str(Commands.validate_output_path("E:/outside")).is_not_empty()


func test_mcp_video_import_delegates_to_the_external_staging_service_without_changing_response_shape() -> void:
	var commands := Commands.new()
	var service := FakeVideoService.new()
	commands.video_service = service
	var response: Dictionary = commands.get_commands()["video_sprites.import_video"].call({
		"source_video": "E:/videos/niko.mp4",
		"staging_directory": "E:/external/video_sprite_workspace/delegated-video",
	})

	assert_dict(service.received_params).contains_keys(["source_video", "staging_directory"])
	assert_str(response.get("result", {}).get("job_id", "")).is_equal("delegated-video")
	assert_str(response.get("result", {}).get("state", "")).is_equal("queued")
	commands.free()


func test_readme_explains_all_commands_and_non_destructive_selection_workflow() -> void:
	var readme := FileAccess.get_file_as_string("res://tools/video_sprites/README.md")
	for command in [
		"video_sprites.scan_directory",
		"video_sprites.import_directory",
		"video_sprites.import_video",
		"video_sprites.job_status",
		"video_sprites.validate_library",
		"character_sprite.import_all",
		"character_sprite.publish",
		"character_sprite.status",
	]:
		assert_str(readme).contains(command)
	assert_str(readme).contains("source_all_frames.tres")
	assert_str(readme).contains("selection.tres")
	assert_str(readme).contains("24 FPS")
	assert_str(readme).contains("selected FPS")
	assert_str(readme).contains("never overwrites")


func test_import_launch_builds_exact_worker_arguments_and_returns_immediately() -> void:
	var source_absolute := ProjectSettings.globalize_path(TEMP_ROOT)
	var commands := Commands.new()
	var result: Dictionary = commands.start_import_job(
		"import-directory",
		{
			"source_directory": source_absolute,
			"output_directory": "res://tools/sprites/niko_video_library",
			"pipeline_root": ProjectSettings.globalize_path(PIPELINE_ROOT),
			"sprite_gen_root": ProjectSettings.globalize_path(SPRITE_GEN_ROOT),
			"python_executable": ProjectSettings.globalize_path(PYTHON_PATH),
			"config_path": ProjectSettings.globalize_path(PIPELINE_ROOT + "/characters.json"),
			"force_generated": true,
			"replace_selection": true,
		},
		Callable(self, "_fake_launcher"),
		"job-fixed"
	)
	assert_array(result.get("errors", PackedStringArray())).is_empty()
	assert_int(result.get("pid", 0)).is_equal(4321)
	assert_str(result.get("job_id", "")).is_equal("job-fixed")
	assert_str(result.get("state", "")).is_equal("queued")
	assert_str(launched_executable).is_equal(ProjectSettings.globalize_path(PYTHON_PATH))
	assert_array(launched_arguments).contains_exactly([
		ProjectSettings.globalize_path("res://tools/video_sprites/spritegen_video_worker.py"),
		"import-directory",
		"--pixelmotion-root", ProjectSettings.globalize_path(PIPELINE_ROOT),
		"--sprite-gen-root", ProjectSettings.globalize_path(SPRITE_GEN_ROOT),
		"--source-directory", source_absolute,
		"--output-directory", ProjectSettings.globalize_path("res://tools/sprites/niko_video_library"),
		"--job-receipt", ProjectSettings.globalize_path("user://video_sprite_jobs/job-fixed.json"),
		"--config", ProjectSettings.globalize_path(PIPELINE_ROOT + "/characters.json"),
		"--job-id", "job-fixed",
		"--force-generated",
		"--replace-selection",
	])
	commands.free()


func test_job_polling_reports_running_and_finalizes_worker_complete_receipts() -> void:
	var commands := Commands.new()
	commands.track_job("job-test", "user://video_sprite_jobs/job-test.json")
	var running: Dictionary = commands.poll_job(
		"job-test", Callable(self, "_running_receipt"), Callable(self, "_finalize_receipt")
	)
	assert_array(running.get("errors", PackedStringArray())).is_empty()
	assert_str(running.get("state", "")).is_equal("running")
	assert_int(running.get("completed_frames", 0)).is_equal(12)
	var complete: Dictionary = commands.poll_job(
		"job-test", Callable(self, "_worker_complete_receipt"), Callable(self, "_finalize_receipt")
	)
	assert_array(complete.get("errors", PackedStringArray())).is_empty()
	assert_str(complete.get("state", "")).is_equal("complete")
	assert_bool(complete.get("finalized", false)).is_true()
	commands.free()


func test_job_polling_rejects_missing_receipts_and_passes_failed_state_through() -> void:
	var commands := Commands.new()
	var unknown: Dictionary = commands.poll_job("unknown", Callable(self, "_missing_receipt"))
	assert_str("\n".join(unknown.get("errors", PackedStringArray()))).contains("unknown job ID")
	commands.track_job("job-failed", "user://video_sprite_jobs/job-failed.json")
	var missing: Dictionary = commands.poll_job("job-failed", Callable(self, "_missing_receipt"))
	assert_str("\n".join(missing.get("errors", PackedStringArray()))).contains("missing or malformed")
	var failed: Dictionary = commands.poll_job("job-failed", Callable(self, "_failed_receipt"))
	assert_array(failed.get("errors", PackedStringArray())).is_empty()
	assert_str(failed.get("state", "")).is_equal("failed")
	commands.free()


func test_editor_import_retains_and_polls_the_job_until_godot_finalization() -> void:
	var tracker := ImportJobTracker.new()
	var fake := auto_free(FakeJobCommands.new()) as FakeJobCommands
	tracker.commands = fake
	assert_bool(tracker.track_import_result(
		{"result": {"job_id": "job-editor", "state": "queued"}}
	)).is_true()
	assert_str(tracker.active_job_id).is_equal("job-editor")
	tracker.poll_import_job()
	assert_int(fake.poll_count).is_equal(1)
	assert_str(tracker.active_job_id).is_equal("job-editor")
	tracker.poll_import_job()
	assert_int(fake.poll_count).is_equal(2)
	assert_str(tracker.active_job_id).is_empty()


func test_idle_editor_import_tracker_returns_silently_without_an_error() -> void:
	var tracker := ImportJobTracker.new()
	var result := tracker.poll_import_job()
	assert_array(result.get("errors", PackedStringArray())).is_empty()
	assert_str(result.get("state", "")).is_equal("idle")


func test_editor_import_uses_portable_source_and_pipeline_resolution() -> void:
	var plugin_source := FileAccess.get_file_as_string(
		"res://addons/character_sprite_authoring/plugin.gd"
	)
	assert_str(plugin_source).not_contains("E:/01_gobro/pixelmotion-2d-niko")
	assert_str(plugin_source).contains("resolve_character_source_directory")
	assert_str(plugin_source).contains("resolve_pipeline_root")


func _fake_launcher(executable: String, arguments: PackedStringArray) -> int:
	launched_executable = executable
	launched_arguments = arguments
	return 4321


func _running_receipt(_path: String) -> Dictionary:
	return {"job_id": "job-test", "state": "running", "completed_frames": 12}


func _worker_complete_receipt(_path: String) -> Dictionary:
	return {"job_id": "job-test", "state": "worker_complete", "completed_frames": 124}


func _missing_receipt(_path: String) -> Dictionary:
	return {}


func _failed_receipt(_path: String) -> Dictionary:
	return {"job_id": "job-failed", "state": "failed", "error": "fixture"}


func _finalize_receipt(receipt: Dictionary, _path: String) -> Dictionary:
	receipt["state"] = "complete"
	receipt["finalized"] = true
	return receipt


func _write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_object(file).is_not_null()
	file.store_string(content)
	file.close()
