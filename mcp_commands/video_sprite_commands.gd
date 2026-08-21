@tool
extends "res://addons/godot_mcp/commands/base_command.gd"


const Importer = preload("res://tools/video_sprites/video_sprite_manifest_importer.gd")
const VideoSpriteJobService = preload("res://tools/video_sprites/video_sprite_job_service.gd")
const DEFAULT_OUTPUT := "res://tools/sprites/niko_video_library"
const JOB_ROOT := "user://video_sprite_jobs"
const DEFAULT_CHARACTER_CONFIG := "res://tools/video_sprites/niko_character_sources.json"
const SPRITE_GEN_WORKER := "res://tools/video_sprites/spritegen_video_worker.py"
const PIPELINE_ROOT_SETTING := "video_sprites/pixelmotion_root"
const SOURCE_DIRECTORY_SETTING := "video_sprites/niko/source_directory"

var _jobs: Dictionary = {}
var video_service: Variant = VideoSpriteJobService.new()


func get_commands() -> Dictionary:
	return {
		"video_sprites.scan_directory": _scan_directory,
		"video_sprites.import_directory": _import_directory,
		"video_sprites.import_video": _import_video,
		"video_sprites.job_status": _job_status,
		"video_sprites.dependency_status": _dependency_status,
		"video_sprites.cancel_job": _cancel_job,
		"video_sprites.validate_library": _validate_library,
		"character_sprite.import_all": _character_import_all,
		"character_sprite.publish": _character_publish,
		"character_sprite.status": _character_status,
	}


static func validate_output_path(path: String) -> String:
	if not path.begins_with("res://"):
		return "output_directory must be a res:// path"
	if path.contains(".."):
		return "output_directory must not contain traversal"
	var simplified := path.simplify_path().trim_suffix("/")
	if not simplified.begins_with("res://tools/sprites/"):
		return "output_directory must remain below res://tools/sprites"
	return ""


func _scan_directory(params: Dictionary) -> Dictionary:
	var required := require_string(params, "source_directory")
	if required[1] != null:
		return required[1]
	var source_directory := str(required[0])
	if not source_directory.is_absolute_path() or not DirAccess.dir_exists_absolute(source_directory):
		return error_invalid_params("source_directory must be an existing absolute directory")
	var pipeline_root := resolve_pipeline_root(params)
	if pipeline_root.is_empty():
		return error_invalid_params("pipeline_root is missing or does not exist")
	var sprite_gen_root := resolve_sprite_gen_root(params)
	if sprite_gen_root.is_empty():
		return error_invalid_params("sprite_gen_root is missing or incomplete")
	var python := resolve_python_executable(params, sprite_gen_root)
	if python.is_empty():
		return error_invalid_params("could not resolve the sprite-gen venv Python executable")
	var script := ProjectSettings.globalize_path(SPRITE_GEN_WORKER)
	if not FileAccess.file_exists(script):
		return error_not_found("sprite-gen video worker", SPRITE_GEN_WORKER)
	var output: Array = []
	var exit_code := OS.execute(
		python,
		PackedStringArray([
			script, "scan",
			"--pixelmotion-root", pipeline_root,
			"--sprite-gen-root", sprite_gen_root,
			"--source-directory", source_directory,
		]),
		output,
		true
	)
	if exit_code != 0:
		return error_internal("video scan failed: %s" % "\n".join(output))
	var parsed: Variant = JSON.parse_string("\n".join(output))
	if not parsed is Dictionary:
		return error_internal("video scan returned malformed JSON")
	return success(parsed as Dictionary)


func _import_directory(params: Dictionary) -> Dictionary:
	return _start_import_response("import-directory", params)


func _import_video(params: Dictionary) -> Dictionary:
	var result: Dictionary = video_service.start_single_video_job(params)
	var errors := result.get("errors", PackedStringArray()) as PackedStringArray
	return error_invalid_params("\n".join(errors)) if not errors.is_empty() else success(result)


func _job_status(params: Dictionary) -> Dictionary:
	var required := require_string(params, "job_id")
	if required[1] != null:
		return required[1]
	var result: Dictionary = video_service.poll_job(str(required[0]))
	if not (result.get("errors", PackedStringArray()) as PackedStringArray).is_empty():
		result = poll_job(str(required[0]))
	var errors := result.get("errors", PackedStringArray()) as PackedStringArray
	if not errors.is_empty():
		return error_not_found("video sprite job '%s'" % str(required[0]), "\n".join(errors))
	return success(result)


func _dependency_status(params: Dictionary) -> Dictionary:
	return success(video_service.dependency_status(params))


func _cancel_job(params: Dictionary) -> Dictionary:
	var required := require_string(params, "job_id")
	if required[1] != null:
		return required[1]
	var result: Dictionary = video_service.cancel_job(str(required[0]))
	var errors := result.get("errors", PackedStringArray()) as PackedStringArray
	return error_not_found("video sprite job '%s'" % str(required[0]), "\n".join(errors)) if not errors.is_empty() else success(result)


func _validate_library(params: Dictionary) -> Dictionary:
	var output_path := optional_string(params, "output_directory", DEFAULT_OUTPUT)
	var path_error := validate_output_path(output_path)
	if not path_error.is_empty():
		return error_invalid_params(path_error)
	return success(validate_library_resources(output_path))


func _character_import_all(params: Dictionary) -> Dictionary:
	var context := _character_context(params)
	var context_errors := context.get("errors", PackedStringArray()) as PackedStringArray
	if not context_errors.is_empty():
		return error_invalid_params("\n".join(context_errors))
	var config := context["config"] as Dictionary
	var enriched := params.duplicate(true)
	enriched.erase("config_path")
	if params.has("worker_config_path"):
		enriched["config_path"] = params["worker_config_path"]
	enriched["source_directory"] = resolve_character_source_directory(config, enriched)
	if str(enriched["source_directory"]).is_empty():
		return error_invalid_params(
			"source_directory is missing; set %s, NIKO_VIDEO_SOURCE_DIRECTORY, or pass an override"
			% SOURCE_DIRECTORY_SETTING
		)
	enriched["output_directory"] = str(config.get("clip_root", DEFAULT_OUTPUT))
	enriched["character_config_path"] = str(context["config_path"])
	return _start_import_response("import-directory", enriched)


func _character_publish(params: Dictionary) -> Dictionary:
	var context := _character_context(params)
	var context_errors := context.get("errors", PackedStringArray()) as PackedStringArray
	if not context_errors.is_empty():
		return error_invalid_params("\n".join(context_errors))
	var config := context["config"] as Dictionary
	var authoring_path := str(config.get("authoring_path", ""))
	var authoring := ResourceLoader.load(
		authoring_path, "SpriteFrames", ResourceLoader.CACHE_MODE_REPLACE
	) as SpriteFrames
	if authoring == null:
		return error_not_found("character authoring SpriteFrames", authoring_path)
	var result := Importer.publish_character_runtime(
		authoring,
		str(config.get("character_id", "")),
		str(config.get("runtime_root", "")),
		Callable(self, "_load_published_texture")
	)
	var errors := result.get("errors", PackedStringArray()) as PackedStringArray
	if not errors.is_empty():
		return error_internal("\n".join(errors))
	return success(result)


func _character_status(params: Dictionary) -> Dictionary:
	var context := _character_context(params)
	var context_errors := context.get("errors", PackedStringArray()) as PackedStringArray
	if not context_errors.is_empty():
		return error_invalid_params("\n".join(context_errors))
	var config := context["config"] as Dictionary
	var authoring_path := str(config.get("authoring_path", ""))
	var frames := ResourceLoader.load(
		authoring_path, "SpriteFrames", ResourceLoader.CACHE_MODE_REPLACE
	) as SpriteFrames
	var status := Importer.character_status(config, frames)
	status["authoring_path"] = authoring_path
	status["authoring_exists"] = frames != null
	var runtime_root := str(config.get("runtime_root", ""))
	var runtime_path := runtime_root.path_join(
		"%s_runtime_frames.tres" % str(config.get("character_id", ""))
	)
	status["runtime_path"] = runtime_path
	status["runtime_exists"] = FileAccess.file_exists(runtime_path)
	return success(status)


func _character_context(params: Dictionary) -> Dictionary:
	var config_path := str(params.get("config_path", DEFAULT_CHARACTER_CONFIG))
	var parsed := Importer.parse_character_config_file(config_path)
	var errors := parsed.get("errors", PackedStringArray()) as PackedStringArray
	if not errors.is_empty():
		return {"errors": errors}
	var config := parsed["config"] as Dictionary
	var requested_id := str(params.get("character_id", config.get("character_id", "")))
	if requested_id != str(config.get("character_id", "")):
		return {"errors": PackedStringArray([
			"character_id does not match config: %s" % requested_id
		])}
	return {"config": config, "config_path": config_path, "errors": PackedStringArray()}


func _load_published_texture(path: String) -> Texture2D:
	var filesystem := EditorInterface.get_resource_filesystem()
	if filesystem != null:
		filesystem.update_file(path)
		filesystem.reimport_files(PackedStringArray([path]))
	var texture := ResourceLoader.load(
		path, "Texture2D", ResourceLoader.CACHE_MODE_REPLACE
	) as Texture2D
	if texture != null:
		return texture
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	return ImageTexture.create_from_image(image) if not image.is_empty() else null


static func resolve_pipeline_root(params: Dictionary) -> String:
	var candidate := str(params.get("pipeline_root", ""))
	if candidate.is_empty():
		candidate = OS.get_environment("PIXELMOTION2D_ROOT")
	if candidate.is_empty():
		candidate = str(ProjectSettings.get_setting(PIPELINE_ROOT_SETTING, ""))
	if candidate.is_empty():
		candidate = _discover_workspace_directory("pixelmotion-2d-niko")
	if candidate.is_empty() or not candidate.is_absolute_path():
		return ""
	candidate = candidate.simplify_path()
	return candidate if DirAccess.dir_exists_absolute(candidate) else ""


static func resolve_character_source_directory(
	config: Dictionary, params: Dictionary = {}
) -> String:
	var candidates := PackedStringArray([
		str(params.get("source_directory", "")),
		OS.get_environment("NIKO_VIDEO_SOURCE_DIRECTORY"),
		str(ProjectSettings.get_setting(SOURCE_DIRECTORY_SETTING, "")),
		str(config.get("source_directory", "")),
		_discover_workspace_directory("MINIMAX_OK/niko"),
	])
	for candidate_value: String in candidates:
		if candidate_value.is_empty() or not candidate_value.is_absolute_path():
			continue
		var candidate := candidate_value.simplify_path()
		if DirAccess.dir_exists_absolute(candidate):
			return candidate
	return ""


static func _discover_workspace_directory(relative_path: String) -> String:
	var cursor := ProjectSettings.globalize_path("res://").simplify_path()
	for _depth in 6:
		var candidate := cursor.path_join(relative_path).simplify_path()
		if DirAccess.dir_exists_absolute(candidate):
			return candidate
		var parent := cursor.get_base_dir()
		if parent == cursor:
			break
		cursor = parent
	return ""


static func resolve_sprite_gen_root(params: Dictionary) -> String:
	var candidate := str(params.get("sprite_gen_root", ""))
	if candidate.is_empty():
		candidate = OS.get_environment("SPRITE_GEN_ROOT")
	if candidate.is_empty():
		var user_profile := OS.get_environment("USERPROFILE")
		if not user_profile.is_empty():
			candidate = user_profile.path_join(".codex/skills/sprite-gen")
	if candidate.is_empty() or not candidate.is_absolute_path():
		return ""
	candidate = candidate.simplify_path()
	for required_script: String in [
		"scripts/prepare_sprite_run.py",
		"scripts/extract_sprite_row_frames.py",
	]:
		if not FileAccess.file_exists(candidate.path_join(required_script)):
			return ""
	return candidate


static func resolve_python_executable(params: Dictionary, sprite_gen_root: String) -> String:
	var explicit := str(params.get("python_executable", ""))
	if not explicit.is_empty():
		return explicit.simplify_path() if FileAccess.file_exists(explicit) else ""
	var environment := OS.get_environment("SPRITE_GEN_PYTHON")
	if not environment.is_empty():
		return environment.simplify_path() if FileAccess.file_exists(environment) else ""
	var bundled := sprite_gen_root.path_join(".venv/Scripts/python.exe")
	if FileAccess.file_exists(bundled):
		return bundled
	return ""


func start_import_job(
	command: String,
	params: Dictionary,
	launcher: Callable = Callable(),
	fixed_job_id := ""
) -> Dictionary:
	if command == "import-video":
		return video_service.start_single_video_job(params, launcher, fixed_job_id)
	var result := {"errors": PackedStringArray()}
	if command not in ["import-directory", "import-video"]:
		_append_result_error(result, "unsupported import command: %s" % command)
		return result
	var source_key := "source_directory" if command == "import-directory" else "source_video"
	var source := str(params.get(source_key, ""))
	if source.is_empty() or not source.is_absolute_path():
		_append_result_error(result, "%s must be an absolute path" % source_key)
		return result
	if command == "import-directory" and not DirAccess.dir_exists_absolute(source):
		_append_result_error(result, "%s does not exist" % source_key)
		return result
	if command == "import-video" and not FileAccess.file_exists(source):
		_append_result_error(result, "%s does not exist" % source_key)
		return result
	var output_path := str(params.get("output_directory", DEFAULT_OUTPUT))
	var output_error := validate_output_path(output_path)
	if not output_error.is_empty():
		_append_result_error(result, output_error)
		return result
	var pipeline_root := resolve_pipeline_root(params)
	if pipeline_root.is_empty():
		_append_result_error(result, "pipeline_root is missing or does not exist")
		return result
	var sprite_gen_root := resolve_sprite_gen_root(params)
	if sprite_gen_root.is_empty():
		_append_result_error(result, "sprite_gen_root is missing or incomplete")
		return result
	var python := resolve_python_executable(params, sprite_gen_root)
	if python.is_empty():
		_append_result_error(result, "could not resolve the sprite-gen venv Python executable")
		return result
	var script := ProjectSettings.globalize_path(SPRITE_GEN_WORKER)
	if not FileAccess.file_exists(script):
		_append_result_error(result, "sprite-gen video worker not found: %s" % SPRITE_GEN_WORKER)
		return result
	var config := str(params.get("config_path", pipeline_root.path_join("characters/niko-walk.json")))
	if not FileAccess.file_exists(config):
		_append_result_error(result, "video sprite config not found: %s" % config)
		return result
	var job_id := fixed_job_id if not fixed_job_id.is_empty() else _new_job_id()
	var job_directory := ProjectSettings.globalize_path(JOB_ROOT)
	DirAccess.make_dir_recursive_absolute(job_directory)
	var receipt_path := JOB_ROOT.path_join("%s.json" % job_id)
	var receipt_absolute := ProjectSettings.globalize_path(receipt_path)
	var output_absolute := ProjectSettings.globalize_path(output_path)
	var queued := {
		"schema_version": 1,
		"job_id": job_id,
		"state": "queued",
		"source_directory": source.get_base_dir() if command == "import-video" else source,
		"output_directory": output_absolute,
		"replace_selection": optional_bool(params, "replace_selection", false),
	}
	if not str(params.get("character_config_path", "")).is_empty():
		queued["character_config_path"] = str(params["character_config_path"])
	if not _write_receipt(receipt_absolute, queued):
		_append_result_error(result, "could not create job receipt: %s" % receipt_path)
		return result
	var arguments := PackedStringArray([
		script,
		command,
		"--pixelmotion-root", pipeline_root,
		"--sprite-gen-root", sprite_gen_root,
		"--%s" % source_key.replace("_", "-"), source,
		"--output-directory", output_absolute,
		"--job-receipt", receipt_absolute,
		"--config", config,
		"--job-id", job_id,
	])
	if command == "import-video" and not str(params.get("clip_id", "")).is_empty():
		arguments.append_array(["--clip-id", str(params["clip_id"])])
	if optional_bool(params, "force_generated", false):
		arguments.append("--force-generated")
	if optional_bool(params, "replace_selection", false):
		arguments.append("--replace-selection")
	var pid := int(launcher.call(python, arguments)) if launcher.is_valid() else OS.create_process(python, arguments)
	if pid <= 0:
		_append_result_error(result, "worker process could not be started")
		queued["state"] = "failed"
		queued["error"] = "OS.create_process returned an invalid pid"
		_write_receipt(receipt_absolute, queued)
		return result
	_jobs[job_id] = receipt_path
	return {
		"errors": PackedStringArray(),
		"job_id": job_id,
		"pid": pid,
		"receipt_path": receipt_path,
		"state": "queued",
	}


func track_job(job_id: String, receipt_path: String) -> void:
	_jobs[job_id] = receipt_path


func poll_job(
	job_id: String,
	receipt_reader: Callable = Callable(),
	finalizer: Callable = Callable()
) -> Dictionary:
	if not _jobs.has(job_id):
		return {"errors": PackedStringArray(["unknown job ID: %s" % job_id])}
	var receipt_path := str(_jobs[job_id])
	var receipt_value: Variant = (
		receipt_reader.call(receipt_path)
		if receipt_reader.is_valid()
		else _read_receipt(receipt_path)
	)
	if not receipt_value is Dictionary or (receipt_value as Dictionary).is_empty():
		return {"errors": PackedStringArray(["job receipt is missing or malformed: %s" % receipt_path])}
	var receipt := receipt_value as Dictionary
	if str(receipt.get("job_id", "")) != job_id:
		return {"errors": PackedStringArray(["job receipt ID does not match: %s" % receipt_path])}
	var state := str(receipt.get("state", ""))
	if state in ["worker_complete", "complete_with_errors"] and not bool(receipt.get("godot_finalized", false)):
		return (
			finalizer.call(receipt, receipt_path)
			if finalizer.is_valid()
			else _finalize_receipt(receipt, receipt_path)
		)
	receipt["errors"] = PackedStringArray()
	return receipt


func validate_library_resources(output_path: String) -> Dictionary:
	var root := DirAccess.open(output_path)
	if root == null:
		return {"valid": false, "clip_count": 0, "errors": ["library not found: %s" % output_path]}
	var clip_names := PackedStringArray()
	root.list_dir_begin()
	var entry := root.get_next()
	while not entry.is_empty():
		if root.current_is_dir() and FileAccess.file_exists(output_path.path_join(entry).path_join("manifest.json")):
			clip_names.append(entry)
		entry = root.get_next()
	root.list_dir_end()
	clip_names.sort()
	var errors: Array[String] = []
	var clips: Array[Dictionary] = []
	for clip_id in clip_names:
		var clip_root := output_path.path_join(clip_id)
		var parsed := Importer.parse_manifest_file(clip_root.path_join("manifest.json"))
		var clip_errors := parsed.get("errors", PackedStringArray()) as PackedStringArray
		if clip_errors.is_empty():
			clip_errors = Importer.validate_manifest_assets(parsed["manifest"] as Dictionary)
		for message in clip_errors:
			errors.append("%s: %s" % [clip_id, message])
		for required in ["source_all_frames.tres", "selection.tres", "preview.tscn"]:
			var resource_path := clip_root.path_join(required)
			if not ResourceLoader.exists(resource_path):
				errors.append("%s: missing Godot resource %s" % [clip_id, required])
		clips.append({"clip_id": clip_id, "valid": clip_errors.is_empty()})
	if clip_names.is_empty():
		errors.append("no installed clips found")
	return {"valid": errors.is_empty(), "clip_count": clip_names.size(), "clips": clips, "errors": errors}


func _start_import_response(command: String, params: Dictionary) -> Dictionary:
	var result := start_import_job(command, params)
	var errors := result.get("errors", PackedStringArray()) as PackedStringArray
	if not errors.is_empty():
		return error_invalid_params("\n".join(errors))
	return success(result)


func _read_receipt(path: String) -> Dictionary:
	var absolute := ProjectSettings.globalize_path(path) if path.begins_with("user://") else path
	if not FileAccess.file_exists(absolute):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(absolute))
	return parsed as Dictionary if parsed is Dictionary else {}


func _finalize_receipt(receipt: Dictionary, receipt_path: String) -> Dictionary:
	var output_absolute := str(receipt.get("output_directory", ""))
	var output_path := ProjectSettings.localize_path(output_absolute)
	var output_error := validate_output_path(output_path)
	if not output_error.is_empty():
		return {"errors": PackedStringArray([output_error]), "state": "failed"}
	var finalization_errors: Array[String] = []
	var clips_value: Variant = receipt.get("clips", [])
	if clips_value is Array:
		for clip_value in clips_value as Array:
			if not clip_value is Dictionary:
				continue
			var clip := clip_value as Dictionary
			if str(clip.get("status", "")) not in ["complete", "skipped"]:
				continue
			var clip_id := str(clip.get("clip_id", ""))
			var clip_root := output_path.path_join(clip_id)
			var atlas_path := clip_root.path_join("atlas.png")
			var filesystem := EditorInterface.get_resource_filesystem()
			if filesystem != null:
				filesystem.update_file(atlas_path)
				filesystem.reimport_files(PackedStringArray([atlas_path]))
			var installed := Importer.install_clip(
				clip_root.path_join("manifest.json"), bool(receipt.get("replace_selection", false))
			)
			var install_errors := installed.get("errors", PackedStringArray()) as PackedStringArray
			if install_errors.is_empty():
				var preview := Importer.write_preview_scene(clip_root.path_join("manifest.json"))
				install_errors = preview.get("errors", PackedStringArray()) as PackedStringArray
			if install_errors.is_empty():
				clip["godot_status"] = "complete"
			else:
				clip["godot_status"] = "failed"
				for message in install_errors:
					finalization_errors.append("%s: %s" % [clip_id, message])
	var character_config_path := str(receipt.get("character_config_path", ""))
	if not character_config_path.is_empty() and int(receipt.get("completed_clips", 0)) > 0:
		var parsed_config := Importer.parse_character_config_file(character_config_path)
		var character_errors := parsed_config.get("errors", PackedStringArray()) as PackedStringArray
		if character_errors.is_empty():
			var character_config := parsed_config["config"] as Dictionary
			var character_result := Importer.install_character_library(
				character_config,
				str(character_config.get("clip_root", output_path)),
				str(character_config.get("authoring_path", ""))
			)
			character_errors = character_result.get("errors", PackedStringArray()) as PackedStringArray
			receipt["character_authoring"] = character_result
		for message in character_errors:
			finalization_errors.append("character: %s" % message)
	receipt["godot_finalized"] = true
	receipt["finalization_errors"] = finalization_errors
	if finalization_errors.is_empty() and int(receipt.get("failed_clips", 0)) == 0:
		receipt["state"] = "complete"
	elif int(receipt.get("completed_clips", 0)) > 0:
		receipt["state"] = "complete_with_errors"
	else:
		receipt["state"] = "failed"
	receipt["errors"] = PackedStringArray()
	var absolute := ProjectSettings.globalize_path(receipt_path) if receipt_path.begins_with("user://") else receipt_path
	if not _write_receipt(absolute, receipt):
		return {"errors": PackedStringArray(["could not update finalized receipt"]), "state": "failed"}
	return receipt


static func _new_job_id() -> String:
	return "%d-%s" % [Time.get_unix_time_from_system(), str(randi()).sha256_text().left(10)]


static func _append_result_error(result: Dictionary, message: String) -> void:
	var errors := result.get("errors", PackedStringArray()) as PackedStringArray
	errors.append(message)
	result["errors"] = errors


static func _write_receipt(path: String, receipt: Dictionary) -> bool:
	var absolute := ProjectSettings.globalize_path(path) if path.begins_with("user://") else path
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var temporary := absolute + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(receipt))
	file.close()
	if FileAccess.file_exists(absolute):
		DirAccess.remove_absolute(absolute)
	return DirAccess.rename_absolute(temporary, absolute) == OK


func get_command_docs() -> Dictionary:
	return {
		"video_sprites.scan_directory": {
			"description": "Recursively probe every supported video and report full source frame counts.",
			"params": [
				doc_param("source_directory", "String", true, "Absolute source video directory."),
				doc_param("pipeline_root", "String", false, "PixelMotion 2D root."),
				doc_param("python_executable", "String", false, "Python executable override."),
			],
		},
		"video_sprites.import_directory": {
			"description": "Start an asynchronous full-frame video directory import.",
			"params": _import_docs("source_directory", "Absolute source video directory."),
		},
		"video_sprites.import_video": {
			"description": "Stage one video outside res://; no Godot resources are generated until curated promotion.",
			"params": _video_import_docs() + [
				doc_param("clip_id", "String", false, "Optional stable clip identifier."),
			],
		},
		"video_sprites.job_status": {
			"description": "Read authoritative progress for an external staged or legacy directory job.",
			"params": [doc_param("job_id", "String", true, "Job ID returned by an import command.")],
		},
		"video_sprites.dependency_status": {
			"description": "Report resolved or missing Python, PixelMotion, sprite-gen, worker, and ffprobe paths.",
			"params": [
				doc_param("pipeline_root", "String", false, "PixelMotion 2D root override."),
				doc_param("sprite_gen_root", "String", false, "sprite-gen root override."),
				doc_param("python_executable", "String", false, "Python override."),
				doc_param("ffprobe_executable", "String", false, "ffprobe override."),
			],
		},
		"video_sprites.cancel_job": {
			"description": "Cancel only the PID owned by the recorded non-terminal external video job.",
			"params": [doc_param("job_id", "String", true, "External video job ID to cancel.")],
		},
		"video_sprites.validate_library": {
			"description": "Read-only validation of installed manifests and Godot selection resources.",
			"params": [doc_param("output_directory", "String", false, "Library below res://tools/sprites.")],
		},
		"character_sprite.import_all": {
			"description": "Import every configured source video and refresh one character authoring library.",
			"params": _character_docs(true),
		},
		"character_sprite.publish": {
			"description": "Publish edited runtime tracks into compact atlases and SpriteFrames.",
			"params": _character_docs(false),
		},
		"character_sprite.status": {
			"description": "Report required actions, imported takes, missing actions, and publish state.",
			"params": _character_docs(false),
		},
	}


func _import_docs(source_name: String, source_description: String) -> Array:
	return [
		doc_param(source_name, "String", true, source_description),
		doc_param("output_directory", "String", false, "Destination below res://tools/sprites."),
		doc_param("pipeline_root", "String", false, "PixelMotion 2D root."),
		doc_param("sprite_gen_root", "String", false, "sprite-gen skill root."),
		doc_param("python_executable", "String", false, "sprite-gen venv Python override."),
		doc_param("config_path", "String", false, "PixelMotion character config override."),
		doc_param("force_generated", "bool", false, "Rebuild generated PNG/atlas/manifest files."),
		doc_param("replace_selection", "bool", false, "Explicitly replace selection.tres during finalization."),
	]


func _video_import_docs() -> Array:
	return [
		doc_param("source_video", "String", true, "Absolute source video path."),
		doc_param("staging_directory", "String", false, "Optional absolute directory below user://video_sprite_workspace; defaults to a unique job directory."),
		doc_param("pipeline_root", "String", false, "PixelMotion 2D root; workspace/environment/settings discovery remains available."),
		doc_param("sprite_gen_root", "String", false, "sprite-gen skill root."),
		doc_param("python_executable", "String", false, "sprite-gen venv Python override."),
		doc_param("ffprobe_executable", "String", false, "ffprobe override; PATH lookup is used when omitted."),
		doc_param("config_path", "String", false, "Optional PixelMotion character config override."),
		doc_param("force_generated", "bool", false, "Rebuild generated external staging artifacts."),
	]


func _character_docs(include_worker: bool) -> Array:
	var docs: Array = [
		doc_param("character_id", "String", false, "Configured character ID; defaults to niko."),
		doc_param("config_path", "String", false, "Character action/take configuration resource."),
	]
	if include_worker:
		docs.append_array([
			doc_param("source_directory", "String", false, "Optional source video directory override."),
			doc_param("pipeline_root", "String", false, "PixelMotion 2D root."),
			doc_param("sprite_gen_root", "String", false, "sprite-gen skill root."),
			doc_param("python_executable", "String", false, "sprite-gen venv Python override."),
			doc_param("force_generated", "bool", false, "Rebuild generated full-frame artifacts."),
		])
	return docs
