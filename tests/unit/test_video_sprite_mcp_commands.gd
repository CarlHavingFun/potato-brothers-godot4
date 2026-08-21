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


class OwnedStatefulVideoService extends RefCounted:
	var response := {}

	func owns_job(job_id: String) -> bool:
		return job_id == "service-job"

	func poll_job(_job_id: String) -> Dictionary:
		return response.duplicate(true)


class FakeCurationService extends RefCounted:
	var calls: Array[Dictionary] = []

	func _record(operation: String, params: Dictionary) -> Dictionary:
		calls.append({"operation": operation, "params": params.duplicate(true)})
		return {"errors": PackedStringArray(), "operation": operation}

	func save_curation(params: Dictionary) -> Dictionary:
		return _record("save", params)

	func load_curation(params: Dictionary) -> Dictionary:
		return _record("load", params)

	func preview_promotion(params: Dictionary) -> Dictionary:
		return _record("preview", params)

	func promote_selection(params: Dictionary) -> Dictionary:
		return _record("promote", params)

	func cleanup_staging(params: Dictionary) -> Dictionary:
		return _record("cleanup", params)

	func set_preferred_take(params: Dictionary) -> Dictionary:
		return _record("preferred", params)


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
		"video_sprites.curation_save",
		"video_sprites.curation_load",
		"video_sprites.promotion_preview",
		"video_sprites.promote_selection",
		"video_sprites.cleanup_staging",
		"video_sprites.validate_library",
		"character_sprite.import_all",
		"character_sprite.publish",
		"character_sprite.status",
		"character_sprite.set_preferred_take",
	])
	commands.free()


func test_curation_cleanup_shares_the_owned_video_job_service_instance() -> void:
	var commands := Commands.new()
	assert_bool(commands.curation_service.job_service == commands.video_service).is_true()
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


func test_mcp_docs_describe_external_video_staging_and_job_controls() -> void:
	var commands := Commands.new()
	var docs: Dictionary = commands.get_command_docs()
	var video := docs["video_sprites.import_video"] as Dictionary
	var fields := {}
	for entry in video["params"] as Array:
		var field := entry as Dictionary
		fields[str(field["name"])] = field
	assert_dict(fields).contains_keys(["source_video", "staging_directory"])
	assert_bool((fields["source_video"] as Dictionary).get("required", false)).is_true()
	assert_str((fields["source_video"] as Dictionary).get("type", "")).is_equal("String")
	assert_bool((fields["staging_directory"] as Dictionary).get("required", true)).is_false()
	assert_str((fields["staging_directory"] as Dictionary).get("type", "")).is_equal("String")
	assert_str((fields["staging_directory"] as Dictionary).get("default", "not-empty")).is_empty()
	assert_bool(fields.has("output_directory")).is_false()
	assert_dict(docs).contains_keys(["video_sprites.dependency_status", "video_sprites.cancel_job"])
	commands.free()


func test_curation_mcp_commands_delegate_to_the_shared_service_and_return_the_service_result() -> void:
	var commands := Commands.new()
	var service := FakeCurationService.new()
	commands.curation_service = service
	var requests := {
		"video_sprites.curation_save": {"manifest_path": "E:/stage/manifest.json", "selection": [2, 0], "fps": 12.0, "loop": false},
		"video_sprites.curation_load": {"manifest_path": "E:/stage/manifest.json"},
		"video_sprites.promotion_preview": {"character_id": "niko", "action": "dash", "take": "one"},
		"video_sprites.promote_selection": {"manifest_path": "E:/stage/manifest.json", "selection": [2, 0], "fps": 12.0, "loop": false},
		"video_sprites.cleanup_staging": {"staging_directory": "E:/stage"},
		"character_sprite.set_preferred_take": {"character_id": "niko", "action": "dash", "take": "one"},
	}
	for command_name: String in requests:
		var response: Dictionary = commands.get_commands()[command_name].call(requests[command_name])
		assert_str(response.get("result", {}).get("operation", "")).is_not_empty()
	assert_int(service.calls.size()).is_equal(6)
	assert_array(service.calls.map(func(call: Dictionary) -> String: return str(call["operation"]))).contains_exactly([
		"save", "load", "preview", "promote", "cleanup", "preferred",
	])
	commands.free()


func test_curation_mcp_docs_use_typed_selection_fps_loop_and_registration_parameters() -> void:
	var commands := Commands.new()
	var docs := commands.get_command_docs()
	for command_name: String in ["video_sprites.curation_save", "video_sprites.promote_selection"]:
		var fields := {}
		for value: Variant in (docs[command_name] as Dictionary)["params"] as Array:
			var field := value as Dictionary
			fields[str(field["name"])] = str(field["type"])
		assert_str(fields["manifest_path"]).is_equal("String")
		assert_str(fields["selection"]).is_equal("Array[int]")
		assert_str(fields["fps"]).is_equal("float")
		assert_str(fields["loop"]).is_equal("bool")
	var preferred_fields := {}
	for value: Variant in (docs["character_sprite.set_preferred_take"] as Dictionary)["params"] as Array:
		var field := value as Dictionary
		preferred_fields[str(field["name"])] = field
	assert_dict(preferred_fields).contains_keys(["config_path", "character_id", "action", "take"])
	commands.free()


func test_mcp_job_status_preserves_owned_service_errors_instead_of_falling_back_to_legacy_jobs() -> void:
	var commands := Commands.new()
	var service := OwnedStatefulVideoService.new()
	commands.video_service = service
	service.response = {
		"job_id": "service-job",
		"state": "running",
		"error": "job receipt is corrupt",
		"errors": PackedStringArray(["job receipt is corrupt"]),
	}
	var live: Dictionary = commands.get_commands()["video_sprites.job_status"].call({"job_id": "service-job"})
	assert_str(live.get("result", {}).get("state", "")).is_equal("running")
	assert_str(live.get("result", {}).get("error", "")).contains("corrupt")

	service.response = {
		"job_id": "service-job",
		"state": "failed",
		"receipt_persisted": false,
		"errors": PackedStringArray(["could not persist failed job receipt"]),
	}
	var failed: Dictionary = commands.get_commands()["video_sprites.job_status"].call({"job_id": "service-job"})
	assert_str(failed.get("result", {}).get("state", "")).is_equal("failed")
	assert_bool(failed.get("result", {}).get("receipt_persisted", true)).is_false()
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
