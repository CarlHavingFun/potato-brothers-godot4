class_name VideoSpriteJobService
extends RefCounted


const STAGING_ROOT := "user://video_sprite_workspace"
const JOB_ROOT := "user://video_sprite_jobs"
const SPRITE_GEN_WORKER := "res://tools/video_sprites/spritegen_video_worker.py"
const PIPELINE_ROOT_SETTING := "video_sprites/pixelmotion_root"

var _jobs: Dictionary = {}


func dependency_status(params: Dictionary = {}) -> Dictionary:
	var pipeline_attempt := _pipeline_attempt(params)
	var sprite_attempt := _sprite_attempt(params)
	var python_attempt := _python_attempt(params, str(sprite_attempt["path"]))
	var ffprobe_attempt := _ffprobe_attempt(params)
	var pipeline_root := resolve_pipeline_root(params)
	var sprite_gen_root := resolve_sprite_gen_root(params)
	var python := resolve_python_executable(params, sprite_gen_root)
	var worker := ProjectSettings.globalize_path(SPRITE_GEN_WORKER)
	var ffprobe := resolve_ffprobe_executable(params)
	var status := {
		"python": _dependency(str(python_attempt["path"]), not python.is_empty(), str(python_attempt["source"])),
		"pixelmotion": _dependency(
			str(pipeline_attempt["path"]),
			not pipeline_root.is_empty()
			and FileAccess.file_exists(pipeline_root.path_join("pixelmotion2d/video_sprite_library.py")),
			str(pipeline_attempt["source"])
		),
		"sprite_gen": _dependency(str(sprite_attempt["path"]), not sprite_gen_root.is_empty(), str(sprite_attempt["source"])),
		"worker_script": _dependency(worker, FileAccess.file_exists(worker), "project resource"),
		"ffprobe": _dependency(str(ffprobe_attempt["path"]), not ffprobe.is_empty(), str(ffprobe_attempt["source"])),
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
	var job_id := fixed_job_id if not fixed_job_id.is_empty() else _new_job_id()
	var staging := str(params.get("staging_directory", ""))
	if staging.is_empty():
		staging = ProjectSettings.globalize_path(STAGING_ROOT).path_join(job_id)
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
	var config := str(params.get("config_path", pipeline_root_default_config(dependencies)))
	if config.is_empty() or not config.is_absolute_path() or not FileAccess.file_exists(config):
		_append_error(result, "video sprite config must be an existing absolute path")
		return result
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
		"pid": 0,
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
	# The worker owns subsequent receipt writes and records its PID itself. Never
	# rewrite this queued receipt after launch: a fast worker may already have
	# published running/complete state.
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


func poll_job(
	job_id: String,
	receipt_reader: Callable = Callable(),
	process_running: Callable = Callable(),
	process_exit_code: Callable = Callable()
) -> Dictionary:
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
	var state := str(receipt.get("state", ""))
	if state == "worker_complete":
		receipt["state"] = "complete"
		_neutralize_pid(job_id)
		_publish_polled_receipt(receipt_path, receipt, receipt_reader)
	elif state not in ["complete", "complete_with_errors", "failed", "cancelled"]:
		var pid := int(tracked.get("pid", 0))
		if pid <= 0:
			receipt["state"] = "failed"
			receipt["error"] = "worker receipt is nonterminal but has no recorded worker PID"
			_publish_polled_receipt(receipt_path, receipt, receipt_reader)
		else:
			var running: bool = bool(process_running.call(pid)) if process_running.is_valid() else OS.is_process_running(pid)
			if not running:
				var exit_code := int(process_exit_code.call(pid)) if process_exit_code.is_valid() else OS.get_process_exit_code(pid)
				receipt["state"] = "failed"
				receipt["error"] = "worker exited before terminal receipt state (exit %d)" % exit_code
				_neutralize_pid(job_id)
				_publish_polled_receipt(receipt_path, receipt, receipt_reader)
	else:
		_neutralize_pid(job_id)
	receipt["errors"] = PackedStringArray()
	return receipt


func cancel_job(job_id: String, terminator: Callable = Callable()) -> Dictionary:
	if not _jobs.has(job_id):
		return {"errors": PackedStringArray(["unknown job ID: %s" % job_id])}
	var tracked := _jobs[job_id] as Dictionary
	var receipt_path := str(tracked["receipt_path"])
	var receipt := _read_receipt(receipt_path)
	if receipt.is_empty() or str(receipt.get("job_id", "")) != job_id:
		return {"errors": PackedStringArray(["job receipt is missing or malformed: %s" % receipt_path])}
	if str(receipt.get("state", "")) in ["worker_complete", "complete", "complete_with_errors", "failed", "cancelled"]:
		if str(receipt.get("state", "")) == "worker_complete":
			receipt["state"] = "complete"
		_neutralize_pid(job_id)
		receipt["errors"] = PackedStringArray()
		return receipt
	var pid := int(tracked.get("pid", 0))
	if pid <= 0:
		return {"errors": PackedStringArray(["job has no recorded worker PID: %s" % job_id])}
	if int(receipt.get("pid", 0)) != pid:
		return {"errors": PackedStringArray(["job receipt PID does not match recorded worker PID: %d" % pid])}
	var terminated := bool(terminator.call(pid)) if terminator.is_valid() else OS.kill(pid) == OK
	if not terminated:
		return {"errors": PackedStringArray(["could not terminate recorded worker PID: %d" % pid])}
	receipt["state"] = "cancelled"
	receipt["cancelled_pid"] = pid
	receipt["cancelled_at_unix"] = Time.get_unix_time_from_system()
	if not _write_receipt(ProjectSettings.globalize_path(receipt_path), receipt):
		return {"errors": PackedStringArray(["could not record cancelled job state"])}
	_neutralize_pid(job_id)
	receipt["errors"] = PackedStringArray()
	return receipt


static func validate_staging_directory(path: String) -> String:
	if path.is_empty() or not path.is_absolute_path():
		return "staging_directory must be an absolute path"
	var staging_root := ProjectSettings.globalize_path(STAGING_ROOT).simplify_path()
	var candidate := path.simplify_path()
	if not (candidate == staging_root or candidate.begins_with(staging_root.trim_suffix("/") + "/")):
		return "staging_directory must remain under %s and outside res://" % staging_root
	var project_root := ProjectSettings.globalize_path("res://").simplify_path()
	if candidate.begins_with(project_root):
		return "staging_directory must remain outside res://"
	if _contains_link_component(staging_root, candidate):
		return "staging_directory must not traverse a symlink, junction, or reparse point"
	return ""


static func _contains_link_component(root: String, candidate: String) -> bool:
	if candidate == root:
		return _path_is_link(candidate)
	var relative := candidate.trim_prefix(root.trim_suffix("/") + "/")
	var cursor := root
	for part in relative.split("/", false):
		cursor = cursor.path_join(part)
		if DirAccess.dir_exists_absolute(cursor) and _path_is_link(cursor):
			return true
	return false


static func _path_is_link(path: String) -> bool:
	var parent := DirAccess.open(path.get_base_dir())
	return parent != null and parent.is_link(path.get_file())


func _neutralize_pid(job_id: String) -> void:
	if _jobs.has(job_id):
		var tracked := _jobs[job_id] as Dictionary
		tracked["pid"] = 0
		_jobs[job_id] = tracked


func _publish_polled_receipt(receipt_path: String, receipt: Dictionary, receipt_reader: Callable) -> void:
	if not receipt_reader.is_valid():
		_write_receipt(receipt_path, receipt)


static func pipeline_root_default_config(dependencies: Dictionary) -> String:
	var pixelmotion := dependencies.get("pixelmotion", {}) as Dictionary
	return str(pixelmotion.get("path", "")).path_join("characters/niko-walk.json")


static func resolve_pipeline_root(params: Dictionary) -> String:
	var candidate := str(_pipeline_attempt(params)["path"])
	if candidate.is_empty() or not candidate.is_absolute_path():
		return ""
	candidate = candidate.simplify_path()
	return candidate if DirAccess.dir_exists_absolute(candidate) else ""


static func resolve_sprite_gen_root(params: Dictionary) -> String:
	var candidate := str(_sprite_attempt(params)["path"])
	if candidate.is_empty() or not candidate.is_absolute_path():
		return ""
	candidate = candidate.simplify_path()
	for script in ["scripts/prepare_sprite_run.py", "scripts/extract_sprite_row_frames.py"]:
		if not FileAccess.file_exists(candidate.path_join(script)):
			return ""
	return candidate


static func resolve_python_executable(params: Dictionary, sprite_gen_root: String) -> String:
	var candidate := str(_python_attempt(params, sprite_gen_root)["path"])
	return candidate.simplify_path() if candidate.is_absolute_path() and FileAccess.file_exists(candidate) else ""


static func resolve_ffprobe_executable(params: Dictionary) -> String:
	var candidate := str(_ffprobe_attempt(params)["path"])
	if candidate.is_absolute_path() and FileAccess.file_exists(candidate):
		return candidate.simplify_path()
	return _find_path_executable(candidate) if candidate == "ffprobe" else ""


static func _pipeline_attempt(params: Dictionary) -> Dictionary:
	if not str(params.get("pipeline_root", "")).is_empty():
		return {"path": str(params["pipeline_root"]), "source": "params.pipeline_root"}
	if not OS.get_environment("PIXELMOTION2D_ROOT").is_empty():
		return {"path": OS.get_environment("PIXELMOTION2D_ROOT"), "source": "PIXELMOTION2D_ROOT"}
	if not str(ProjectSettings.get_setting(PIPELINE_ROOT_SETTING, "")).is_empty():
		return {"path": str(ProjectSettings.get_setting(PIPELINE_ROOT_SETTING)), "source": PIPELINE_ROOT_SETTING}
	return {"path": _discover_workspace_directory("pixelmotion-2d-niko"), "source": "workspace discovery"}


static func _sprite_attempt(params: Dictionary) -> Dictionary:
	if not str(params.get("sprite_gen_root", "")).is_empty():
		return {"path": str(params["sprite_gen_root"]), "source": "params.sprite_gen_root"}
	if not OS.get_environment("SPRITE_GEN_ROOT").is_empty():
		return {"path": OS.get_environment("SPRITE_GEN_ROOT"), "source": "SPRITE_GEN_ROOT"}
	return {"path": OS.get_environment("USERPROFILE").path_join(".codex/skills/sprite-gen"), "source": "USERPROFILE default"}


static func _python_attempt(params: Dictionary, sprite_root: String) -> Dictionary:
	if not str(params.get("python_executable", "")).is_empty():
		return {"path": str(params["python_executable"]), "source": "params.python_executable"}
	if not OS.get_environment("SPRITE_GEN_PYTHON").is_empty():
		return {"path": OS.get_environment("SPRITE_GEN_PYTHON"), "source": "SPRITE_GEN_PYTHON"}
	return {"path": sprite_root.path_join(".venv/Scripts/python.exe"), "source": "sprite-gen venv"}


static func _ffprobe_attempt(params: Dictionary) -> Dictionary:
	if not str(params.get("ffprobe_executable", "")).is_empty():
		return {"path": str(params["ffprobe_executable"]), "source": "params.ffprobe_executable"}
	if not str(params.get("ffprobe", "")).is_empty():
		return {"path": str(params["ffprobe"]), "source": "params.ffprobe"}
	return {"path": "ffprobe", "source": "PATH"}


static func _find_path_executable(name: String) -> String:
	for directory in OS.get_environment("PATH").split(";", false):
		for suffix in ["", ".exe"]:
			var candidate := directory.path_join(name + suffix)
			if FileAccess.file_exists(candidate):
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


static func _dependency(path: String, resolved: bool, source: String) -> Dictionary:
	return {"path": path, "resolved": resolved, "source": source, "resolution": "resolved" if resolved else "missing"}


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
