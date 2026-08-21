class_name VideoSpriteJobService
extends RefCounted


const STAGING_ROOT := "user://video_sprite_workspace"
const JOB_ROOT := "user://video_sprite_jobs"
const SPRITE_GEN_WORKER := "res://tools/video_sprites/spritegen_video_worker.py"
const PIPELINE_ROOT_SETTING := "video_sprites/pixelmotion_root"

var _jobs: Dictionary = {}


func dependency_status(params: Dictionary = {}) -> Dictionary:
	var pipeline_root := resolve_pipeline_root(params)
	var sprite_gen_root := resolve_sprite_gen_root(params)
	var python := resolve_python_executable(params, sprite_gen_root)
	var worker := ProjectSettings.globalize_path(SPRITE_GEN_WORKER)
	var ffprobe := resolve_ffprobe_executable(params)
	var status := {
		"python": _dependency(python, not python.is_empty()),
		"pixelmotion": _dependency(
			pipeline_root,
			not pipeline_root.is_empty()
			and FileAccess.file_exists(pipeline_root.path_join("pixelmotion2d/video_sprite_library.py"))
		),
		"sprite_gen": _dependency(sprite_gen_root, not sprite_gen_root.is_empty()),
		"worker_script": _dependency(worker, FileAccess.file_exists(worker)),
		"ffprobe": _dependency(ffprobe, not ffprobe.is_empty()),
	}
	status["ready"] = true
	for name in ["python", "pixelmotion", "sprite_gen", "worker_script", "ffprobe"]:
		if not bool((status[name] as Dictionary).get("resolved", false)):
			status["ready"] = false
	return status


func start_single_video_job(
	params: Dictionary,
	launcher: Callable = Callable(),
	fixed_job_id: String = ""
) -> Dictionary:
	var result := {"errors": PackedStringArray()}
	var source := str(params.get("source_video", ""))
	if source.is_empty() or not source.is_absolute_path() or not FileAccess.file_exists(source):
		_append_error(result, "source_video must be an existing absolute path")
		return result
	var staging := str(params.get("staging_directory", ""))
	var staging_error := validate_staging_directory(staging)
	if not staging_error.is_empty():
		_append_error(result, staging_error)
		return result
	var dependencies := dependency_status(params)
	if not bool(dependencies.get("ready", false)):
		for name in ["python", "pixelmotion", "sprite_gen", "worker_script", "ffprobe"]:
			var dependency := dependencies[name] as Dictionary
			if not bool(dependency.get("resolved", false)):
				_append_error(result, "%s is missing: %s" % [name, dependency.get("path", "")])
		return result
	var config := str(params.get("config_path", ""))
	if config.is_empty() or not config.is_absolute_path() or not FileAccess.file_exists(config):
		_append_error(result, "video sprite config must be an existing absolute path")
		return result
	var job_id := fixed_job_id if not fixed_job_id.is_empty() else _new_job_id()
	var receipt_path := JOB_ROOT.path_join("%s.json" % job_id)
	var receipt_absolute := ProjectSettings.globalize_path(receipt_path)
	var queued := {
		"schema_version": 2,
		"job_id": job_id,
		"state": "queued",
		"source_video": source,
		"output_directory": staging,
		"staging_directory": staging,
		"external_staging": true,
		"replace_selection": false,
	}
	if not _write_receipt(receipt_absolute, queued):
		_append_error(result, "could not create job receipt: %s" % receipt_path)
		return result
	var arguments := PackedStringArray([
		ProjectSettings.globalize_path(SPRITE_GEN_WORKER),
		"import-video",
		"--pixelmotion-root", str((dependencies["pixelmotion"] as Dictionary)["path"]),
		"--sprite-gen-root", str((dependencies["sprite_gen"] as Dictionary)["path"]),
		"--source-video", source,
		"--output-directory", staging,
		"--job-receipt", receipt_absolute,
		"--config", config,
		"--job-id", job_id,
		"--ffprobe", str((dependencies["ffprobe"] as Dictionary)["path"]),
	])
	if not str(params.get("clip_id", "")).is_empty():
		arguments.append_array(["--clip-id", str(params["clip_id"])])
	if bool(params.get("force_generated", false)):
		arguments.append("--force-generated")
	var python := str((dependencies["python"] as Dictionary)["path"])
	var pid := int(launcher.call(python, arguments)) if launcher.is_valid() else OS.create_process(python, arguments)
	if pid <= 0:
		queued["state"] = "failed"
		queued["error"] = "worker process could not be started"
		_write_receipt(receipt_absolute, queued)
		_append_error(result, "worker process could not be started")
		return result
	queued["pid"] = pid
	if not _write_receipt(receipt_absolute, queued):
		_append_error(result, "could not record worker PID in job receipt")
		return result
	_jobs[job_id] = {"receipt_path": receipt_path, "pid": pid}
	return {
		"errors": PackedStringArray(),
		"job_id": job_id,
		"pid": pid,
		"receipt_path": receipt_path,
		"state": "queued",
		"output_directory": staging,
	}


func track_job(job_id: String, receipt_path: String, pid: int = 0) -> void:
	_jobs[job_id] = {"receipt_path": receipt_path, "pid": pid}


func poll_job(job_id: String, receipt_reader: Callable = Callable()) -> Dictionary:
	if not _jobs.has(job_id):
		return {"errors": PackedStringArray(["unknown job ID: %s" % job_id])}
	var tracked := _jobs[job_id] as Dictionary
	var receipt_path := str(tracked["receipt_path"])
	var receipt_value: Variant = receipt_reader.call(receipt_path) if receipt_reader.is_valid() else _read_receipt(receipt_path)
	if not receipt_value is Dictionary or (receipt_value as Dictionary).is_empty():
		return {"errors": PackedStringArray(["job receipt is missing or malformed: %s" % receipt_path])}
	var receipt := receipt_value as Dictionary
	if str(receipt.get("job_id", "")) != job_id:
		return {"errors": PackedStringArray(["job receipt ID does not match: %s" % receipt_path])}
	receipt["errors"] = PackedStringArray()
	return receipt


func cancel_job(job_id: String, terminator: Callable = Callable()) -> Dictionary:
	if not _jobs.has(job_id):
		return {"errors": PackedStringArray(["unknown job ID: %s" % job_id])}
	var tracked := _jobs[job_id] as Dictionary
	var pid := int(tracked.get("pid", 0))
	if pid <= 0:
		return {"errors": PackedStringArray(["job has no recorded worker PID: %s" % job_id])}
	var receipt_path := str(tracked["receipt_path"])
	var receipt := _read_receipt(receipt_path)
	if receipt.is_empty() or str(receipt.get("job_id", "")) != job_id:
		return {"errors": PackedStringArray(["job receipt is missing or malformed: %s" % receipt_path])}
	if str(receipt.get("state", "")) in ["complete", "complete_with_errors", "failed", "cancelled"]:
		receipt["errors"] = PackedStringArray()
		return receipt
	var terminated := bool(terminator.call(pid)) if terminator.is_valid() else OS.kill(pid) == OK
	if not terminated:
		return {"errors": PackedStringArray(["could not terminate recorded worker PID: %d" % pid])}
	receipt["state"] = "cancelled"
	receipt["cancelled_pid"] = pid
	receipt["cancelled_at_unix"] = Time.get_unix_time_from_system()
	if not _write_receipt(ProjectSettings.globalize_path(receipt_path), receipt):
		return {"errors": PackedStringArray(["could not record cancelled job state"])}
	receipt["errors"] = PackedStringArray()
	return receipt


static func validate_staging_directory(path: String) -> String:
	if path.is_empty() or not path.is_absolute_path():
		return "staging_directory must be an absolute path"
	var staging_root := ProjectSettings.globalize_path(STAGING_ROOT).simplify_path()
	var candidate := path.simplify_path()
	if not candidate.begins_with(staging_root):
		return "staging_directory must remain under %s and outside res://" % staging_root
	var project_root := ProjectSettings.globalize_path("res://").simplify_path()
	if candidate.begins_with(project_root):
		return "staging_directory must remain outside res://"
	return ""


static func resolve_pipeline_root(params: Dictionary) -> String:
	var candidate := str(params.get("pipeline_root", ""))
	if candidate.is_empty():
		candidate = OS.get_environment("PIXELMOTION2D_ROOT")
	if candidate.is_empty():
		candidate = str(ProjectSettings.get_setting(PIPELINE_ROOT_SETTING, ""))
	if candidate.is_empty() or not candidate.is_absolute_path():
		return ""
	candidate = candidate.simplify_path()
	return candidate if DirAccess.dir_exists_absolute(candidate) else ""


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
	for script in ["scripts/prepare_sprite_run.py", "scripts/extract_sprite_row_frames.py"]:
		if not FileAccess.file_exists(candidate.path_join(script)):
			return ""
	return candidate


static func resolve_python_executable(params: Dictionary, sprite_gen_root: String) -> String:
	var candidate := str(params.get("python_executable", OS.get_environment("SPRITE_GEN_PYTHON")))
	if candidate.is_empty() and not sprite_gen_root.is_empty():
		candidate = sprite_gen_root.path_join(".venv/Scripts/python.exe")
	return candidate.simplify_path() if candidate.is_absolute_path() and FileAccess.file_exists(candidate) else ""


static func resolve_ffprobe_executable(params: Dictionary) -> String:
	var candidate := str(params.get("ffprobe_executable", params.get("ffprobe", "")))
	return candidate.simplify_path() if candidate.is_absolute_path() and FileAccess.file_exists(candidate) else ""


static func _dependency(path: String, resolved: bool) -> Dictionary:
	return {"path": path, "resolved": resolved}


static func _append_error(result: Dictionary, message: String) -> void:
	var errors := result.get("errors", PackedStringArray()) as PackedStringArray
	errors.append(message)
	result["errors"] = errors


static func _new_job_id() -> String:
	return "%d-%s" % [Time.get_unix_time_from_system(), str(randi()).sha256_text().left(10)]


static func _read_receipt(path: String) -> Dictionary:
	var absolute := ProjectSettings.globalize_path(path) if path.begins_with("user://") else path
	if not FileAccess.file_exists(absolute):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(absolute))
	return parsed as Dictionary if parsed is Dictionary else {}


static func _write_receipt(path: String, receipt: Dictionary) -> bool:
	var absolute := ProjectSettings.globalize_path(path) if path.begins_with("user://") else path
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var temporary := absolute + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(receipt, "\t") + "\n")
	file.close()
	if FileAccess.file_exists(absolute):
		DirAccess.remove_absolute(absolute)
	return DirAccess.rename_absolute(temporary, absolute) == OK
