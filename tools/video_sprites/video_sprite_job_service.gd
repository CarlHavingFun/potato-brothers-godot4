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
	var job_token := _new_job_token(job_id)
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
	var job_directory := JOB_ROOT.path_join(job_id)
	var receipt_path := job_directory.path_join("receipt.json")
	var cancel_request_path := job_directory.path_join("cancel-request.json")
	var receipt_absolute := ProjectSettings.globalize_path(receipt_path)
	var cancel_request_absolute := ProjectSettings.globalize_path(cancel_request_path)
	if FileAccess.file_exists(cancel_request_absolute):
		DirAccess.remove_absolute(cancel_request_absolute)
	var queued := {
		"schema_version": 2,
		"job_id": job_id,
		"job_token": job_token,
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
		"--job-token", job_token,
		"--cancel-request", ProjectSettings.globalize_path(cancel_request_path),
		"--allowed-staging-root", ProjectSettings.globalize_path(STAGING_ROOT),
		"--project-root", ProjectSettings.globalize_path("res://"),
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
	_jobs[job_id] = {
		"receipt_path": receipt_path, "cancel_request_path": cancel_request_path,
		"job_token": job_token, "pid": pid, "staging_directory": staging,
	}
	return {
		"errors": PackedStringArray(),
		"job_id": job_id,
		"pid": pid,
		"receipt_path": receipt_path,
		"cancel_request_path": cancel_request_path,
		"job_token": job_token,
		"state": "queued",
		"output_directory": staging,
	}


func track_job(job_id: String, receipt_path: String, pid: int = 0) -> void:
	_jobs[job_id] = {"receipt_path": receipt_path, "cancel_request_path": "", "job_token": "", "pid": pid}


func owns_job(job_id: String) -> bool:
	return _jobs.has(job_id)


func is_staging_directory_active(path: String) -> bool:
	var candidate := path.simplify_path()
	for job_id_value: Variant in _jobs:
		var tracked := _jobs[job_id_value] as Dictionary
		var receipt := _read_receipt(str(tracked.get("receipt_path", "")))
		var staging := str(tracked.get("staging_directory", ""))
		if staging.is_empty():
			staging = str(receipt.get("staging_directory", receipt.get("output_directory", "")))
		if staging.is_empty() or not _paths_overlap(candidate, staging.simplify_path()):
			continue
		if receipt.is_empty():
			return int(tracked.get("pid", 0)) > 0
		var state := str(receipt.get("state", ""))
		if state not in ["worker_complete", "complete", "complete_with_errors", "failed", "cancelled"]:
			return true
	return false


static func _paths_overlap(first: String, second: String) -> bool:
	first = _comparison_path(first)
	second = _comparison_path(second)
	return (
		first == second
		or first.begins_with(second.trim_suffix("/") + "/")
		or second.begins_with(first.trim_suffix("/") + "/")
	)


func poll_job(
	job_id: String,
	receipt_reader: Callable = Callable(),
	process_running: Callable = Callable(),
	process_exit_code: Callable = Callable(),
	terminal_receipt_writer: Callable = Callable()
) -> Dictionary:
	if not _jobs.has(job_id):
		return {"errors": PackedStringArray(["unknown job ID: %s" % job_id])}
	var tracked := _jobs[job_id] as Dictionary
	if tracked.has("terminal_result"):
		return (tracked["terminal_result"] as Dictionary).duplicate(true)
	var receipt_path := str(tracked["receipt_path"])
	var receipt_value: Variant = receipt_reader.call(receipt_path) if receipt_reader.is_valid() else _read_receipt(receipt_path)
	if not receipt_value is Dictionary or (receipt_value as Dictionary).is_empty():
		return _poll_missing_receipt(
			job_id, tracked, receipt_path, process_running, process_exit_code,
			terminal_receipt_writer, "job receipt is missing or malformed"
		)
	var receipt := receipt_value as Dictionary
	if _receipt_is_corrupt(receipt, job_id):
		return _poll_missing_receipt(
			job_id, tracked, receipt_path, process_running, process_exit_code,
			terminal_receipt_writer, "job receipt is corrupt"
		)
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


func _poll_missing_receipt(
	job_id: String,
	tracked: Dictionary,
	receipt_path: String,
	process_running: Callable,
	process_exit_code: Callable,
	terminal_receipt_writer: Callable = Callable(),
	receipt_problem := "job receipt is missing or malformed"
) -> Dictionary:
	var pid := int(tracked.get("pid", 0))
	var running := pid > 0 and (bool(process_running.call(pid)) if process_running.is_valid() else OS.is_process_running(pid))
	if running:
		return {
			"errors": PackedStringArray([receipt_problem]),
			"job_id": job_id,
			"state": "running",
			"receipt_path": receipt_path,
			"error": receipt_problem,
		}
	var exit_code := int(process_exit_code.call(pid)) if pid > 0 and process_exit_code.is_valid() else OS.get_process_exit_code(pid)
	var failed := {
		"schema_version": 2,
		"job_id": job_id,
		"job_token": str(tracked.get("job_token", "")),
		"state": "failed",
		"error": "%s after worker exit (exit %d)" % [receipt_problem, exit_code],
		"pid": 0,
	}
	var persistence := _persist_terminal_failure(job_id, receipt_path, failed, terminal_receipt_writer)
	failed["receipt_path"] = str(persistence["path"])
	failed["receipt_persisted"] = bool(persistence["persisted"])
	if bool(persistence["persisted"]):
		_neutralize_pid(job_id)
		failed["errors"] = PackedStringArray()
	else:
		failed["errors"] = PackedStringArray(["could not persist failed job receipt"])
		var cached_tracked := _jobs[job_id] as Dictionary
		cached_tracked["terminal_result"] = failed.duplicate(true)
		_jobs[job_id] = cached_tracked
	return failed


func _persist_terminal_failure(
	job_id: String,
	receipt_path: String,
	failed: Dictionary,
	terminal_receipt_writer: Callable = Callable()
) -> Dictionary:
	var absolute := ProjectSettings.globalize_path(receipt_path)
	if not FileAccess.file_exists(absolute) and _write_terminal_failure(absolute, failed, terminal_receipt_writer):
		return {"path": receipt_path, "persisted": true}
	var fallback_path := receipt_path.trim_suffix(".json") + ".failed.json"
	if _write_terminal_failure(ProjectSettings.globalize_path(fallback_path), failed, terminal_receipt_writer):
		var tracked := _jobs[job_id] as Dictionary
		tracked["receipt_path"] = fallback_path
		_jobs[job_id] = tracked
		return {"path": fallback_path, "persisted": true}
	return {"path": fallback_path, "persisted": false}


static func _write_terminal_failure(path: String, failed: Dictionary, writer: Callable) -> bool:
	return bool(writer.call(path, failed)) if writer.is_valid() else _write_new_json(path, failed)


static func _receipt_is_corrupt(receipt: Dictionary, job_id: String) -> bool:
	if not receipt.has("job_id") or not receipt["job_id"] is String or str(receipt["job_id"]) != job_id:
		return true
	if not receipt.has("state") or not receipt["state"] is String or str(receipt["state"]).is_empty():
		return true
	if str(receipt["state"]) not in ["queued", "running", "worker_complete", "complete", "complete_with_errors", "failed", "cancelled"]:
		return true
	if receipt.has("pid") and not _receipt_pid_is_valid(receipt["pid"]):
		return true
	if receipt.has("job_token") and not receipt["job_token"] is String:
		return true
	return false


static func _receipt_pid_is_valid(value: Variant) -> bool:
	return value is int or (value is float and is_equal_approx(value, floor(value)))


func cancel_job(job_id: String) -> Dictionary:
	if not _jobs.has(job_id):
		return {"errors": PackedStringArray(["unknown job ID: %s" % job_id])}
	var tracked := _jobs[job_id] as Dictionary
	var receipt_path := str(tracked["receipt_path"])
	var receipt := _read_receipt(receipt_path)
	if receipt.is_empty() or _receipt_is_corrupt(receipt, job_id):
		return {"errors": PackedStringArray(["job receipt is missing or malformed: %s" % receipt_path])}
	if str(receipt.get("state", "")) in ["worker_complete", "complete", "complete_with_errors", "failed", "cancelled"]:
		if str(receipt.get("state", "")) == "worker_complete":
			receipt["state"] = "complete"
		_neutralize_pid(job_id)
		receipt["errors"] = PackedStringArray()
		return receipt
	if str(receipt.get("job_token", "")) != str(tracked.get("job_token", "")):
		return {"errors": PackedStringArray(["job receipt token does not match tracked job"])}
	var request_path := str(tracked.get("cancel_request_path", ""))
	if request_path.is_empty():
		return {"errors": PackedStringArray(["job does not support cooperative cancellation: %s" % job_id])}
	var request := {
		"schema_version": 1,
		"job_id": job_id,
		"job_token": str(tracked.get("job_token", "")),
		"requested_at_unix": Time.get_unix_time_from_system(),
	}
	if not _write_new_json(ProjectSettings.globalize_path(request_path), request):
		return {"errors": PackedStringArray(["could not atomically record cancellation request"])}
	return {
		"errors": PackedStringArray(),
		"job_id": job_id,
		"state": "cancellation_requested",
		"cancel_request_path": request_path,
	}


static func validate_staging_directory(path: String, path_is_link: Callable = Callable()) -> String:
	if path.is_empty() or not path.is_absolute_path():
		return "staging_directory must be an absolute path"
	var staging_root := ProjectSettings.globalize_path(STAGING_ROOT).simplify_path()
	var candidate := path.simplify_path()
	var compared_candidate := _comparison_path(candidate)
	var compared_root := _comparison_path(staging_root)
	if not (compared_candidate == compared_root or compared_candidate.begins_with(compared_root.trim_suffix("/") + "/")):
		return "staging_directory must remain under %s and outside res://" % staging_root
	var project_root := ProjectSettings.globalize_path("res://").simplify_path()
	if compared_candidate.begins_with(_comparison_path(project_root)):
		return "staging_directory must remain outside res://"
	if _contains_link_component(staging_root, candidate, path_is_link):
		return "staging_directory must not traverse a symlink, junction, or reparse point"
	return ""


static func _contains_link_component(root: String, candidate: String, path_is_link: Callable) -> bool:
	if candidate == root:
		return _path_is_link(candidate, path_is_link)
	if _path_is_link(root, path_is_link):
		return true
	var root_prefix := root.trim_suffix("/") + "/"
	var relative := candidate.substr(root_prefix.length())
	var cursor := root
	for part in relative.split("/", false):
		cursor = cursor.path_join(part)
		if _path_is_link(cursor, path_is_link):
			return true
	return false


static func _comparison_path(path: String) -> String:
	var normalized := path.simplify_path().replace("\\", "/")
	return normalized.to_lower() if OS.get_name() == "Windows" else normalized


static func _path_is_link(path: String, path_is_link: Callable = Callable()) -> bool:
	if path_is_link.is_valid():
		return bool(path_is_link.call(path))
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


static func _new_job_token(job_id: String) -> String:
	return ("%s-%d-%d" % [job_id, Time.get_ticks_usec(), randi()]).sha256_text()


static func _read_receipt(path: String) -> Dictionary:
	var absolute := ProjectSettings.globalize_path(path) if path.begins_with("user://") else path
	if not FileAccess.file_exists(absolute):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(absolute))
	return parsed as Dictionary if parsed is Dictionary else {}


static func _write_new_json(path: String, value: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if FileAccess.file_exists(path):
		return true
	var temporary := "%s.%d.tmp" % [path, randi()]
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "\t") + "\n")
	file.close()
	var renamed := DirAccess.rename_absolute(temporary, path) == OK
	if not renamed and FileAccess.file_exists(temporary):
		DirAccess.remove_absolute(temporary)
	return renamed or FileAccess.file_exists(path)


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
