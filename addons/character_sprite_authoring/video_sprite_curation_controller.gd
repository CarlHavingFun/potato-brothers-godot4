class_name CharacterSpriteCurationController
extends RefCounted


const Importer = preload("res://tools/video_sprites/video_sprite_manifest_importer.gd")
const JobService = preload("res://tools/video_sprites/video_sprite_job_service.gd")
const CurationService = preload("res://tools/video_sprites/video_sprite_curation_service.gd")
const Model = preload("res://addons/character_sprite_authoring/video_sprite_curation_model.gd")
const VIDEO_EXTENSIONS := ["mp4", "mov", "mkv", "webm", "avi"]
const TERMINAL_STATES := ["complete", "complete_with_errors", "failed", "cancelled"]

var job_service: Variant = JobService.new()
var curation_service: Variant = CurationService.new()
var model: CharacterSpriteCurationModel = Model.new()
var file_picker: Callable = Callable()
var manifest_finder: Callable = Callable()
var publish_callback: Callable = Callable()
var open_resource_callback: Callable = Callable()
var refresh_callback: Callable = Callable()

var config_path := ""
var config: Dictionary = {}
var selected_action := ""
var jobs: Dictionary = {}
var job_order: Array[String] = []
var source_frames: Array[Dictionary] = []
var current_job_id := ""
var current_action := ""
var current_manifest_path := ""
var current_staging_directory := ""
var current_take := ""
var pending_promotion: Dictionary = {}
var last_errors := PackedStringArray()
var _dependencies: Dictionary = {}
var _job_fingerprints: Dictionary = {}


func load_config(path: String) -> Dictionary:
	var result := Importer.parse_character_config_file(path)
	var errors := result.get("errors", PackedStringArray()) as PackedStringArray
	if errors.is_empty():
		config_path = path
		config = (result["config"] as Dictionary).duplicate(true)
	elif config.is_empty():
		config_path = path
	last_errors = errors
	return result


func action_names() -> Array[String]:
	var result: Array[String] = []
	for action: Variant in config.get("required_actions", []) as Array:
		result.append(str(action))
	return result


func action_overview(action: String) -> Dictionary:
	var actions := config.get("actions", {}) as Dictionary
	if not actions.has(action) or not actions[action] is Dictionary:
		return {}
	var result := (actions[action] as Dictionary).duplicate(true)
	result["name"] = action
	return result


func select_action(action: String) -> bool:
	if action.is_empty():
		selected_action = ""
		return true
	if action not in action_names():
		return false
	selected_action = action
	return true


func dependency_diagnostics() -> Dictionary:
	_dependencies = job_service.dependency_status({}) as Dictionary
	return _dependencies.duplicate(true)


func accept_video_files(paths: Variant, hovered_action := "") -> Dictionary:
	var action := hovered_action if hovered_action in action_names() else selected_action
	if action.is_empty():
		return {"errors": PackedStringArray(["请先选择动作，再添加视频"]), "legacy_fallback": false}
	var accepted := _filter_video_files(paths)
	if accepted.is_empty():
		return {"errors": PackedStringArray(["未找到支持的绝对视频文件"]), "legacy_fallback": false}
	var dependencies := dependency_diagnostics()
	if not bool(dependencies.get("ready", false)):
		return {"errors": PackedStringArray(["视频处理依赖未就绪，请检查依赖详情"]), "dependencies": dependencies, "legacy_fallback": false}
	var started: Array[Dictionary] = []
	var errors := PackedStringArray()
	for path: String in accepted:
		var params := {
			"source_video": path,
			"action": action,
		}
		var result := job_service.start_single_video_job(params) as Dictionary
		var result_errors := _errors_from(result)
		if not result_errors.is_empty():
			errors.append_array(result_errors)
			continue
		var job_id := str(result.get("job_id", ""))
		var staging := str(result.get("output_directory", result.get("staging_directory", "")))
		var row := result.duplicate(true)
		row["action"] = action
		row["take"] = path.get_file().get_basename()
		row["source_video"] = path
		row["staging_directory"] = staging
		row["progress"] = 0.0
		jobs[job_id] = row
		job_order.append(job_id)
		started.append(row.duplicate(true))
	return {
		"errors": errors,
		"jobs": started,
		"message": "已创建 %d 个任务" % started.size(),
		"legacy_fallback": false,
	}


func pick_video_files() -> Dictionary:
	if not file_picker.is_valid():
		return {"errors": PackedStringArray(["文件选择器不可用"]), "legacy_fallback": false}
	return accept_video_files(file_picker.call())


func poll_jobs() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var ordered_ids: Array[String] = job_order.duplicate()
	for job_id_value: Variant in jobs.keys():
		var untracked_id := str(job_id_value)
		if untracked_id not in ordered_ids:
			ordered_ids.append(untracked_id)
	for job_id: String in ordered_ids:
		var row := jobs[job_id] as Dictionary
		if str(row.get("state", "")) in TERMINAL_STATES:
			_append_changed_job(job_id, row, results)
			continue
		var cancellation_pending := bool(row.get("cancellation_pending", false))
		var polled := job_service.poll_job(job_id) as Dictionary
		row.merge(polled, true)
		if cancellation_pending and str(polled.get("state", "")) not in TERMINAL_STATES:
			row["state"] = "cancelling"
		else:
			row.erase("cancellation_pending")
		row["action"] = str(row.get("action", ""))
		row["take"] = str(row.get("take", "take"))
		row["staging_directory"] = str(row.get("staging_directory", row.get("output_directory", "")))
		row["progress"] = _progress(polled)
		if str(row.get("state", "")) in ["complete", "complete_with_errors"] and not bool(row.get("manifest_loaded", false)):
			_complete_job(row)
		jobs[job_id] = row
		_append_changed_job(job_id, row, results)
	return results


func cancel_job(job_id: String) -> Dictionary:
	if not jobs.has(job_id):
		return {"errors": PackedStringArray(["未知任务：%s" % job_id])}
	if str((jobs[job_id] as Dictionary).get("state", "")) in TERMINAL_STATES:
		return {"errors": PackedStringArray(["任务已结束，不能取消：%s" % job_id])}
	var result := job_service.cancel_job(job_id) as Dictionary
	if _errors_from(result).is_empty() and str(result.get("state", "")) == "cancellation_requested":
		var row := jobs[job_id] as Dictionary
		row["state"] = "cancelling"
		row["cancellation_pending"] = true
		jobs[job_id] = row
		result["state"] = "cancelling"
	return result


func set_fps(value: float) -> Dictionary:
	if not model.set_fps(value):
		return {"errors": PackedStringArray(["FPS 必须在 0.1 到 120 之间"])}
	return {"errors": PackedStringArray(), "fps": model.fps, "preview": preview_sequence()}


func set_loop(value: bool) -> Dictionary:
	model.set_loop(value)
	return {"errors": PackedStringArray(), "loop": model.loop, "preview": preview_sequence()}


func set_active_take(value: String) -> void:
	current_take = value
	_store_active_snapshot()


func preview_sequence() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for source_index: int in model.sequence:
		if source_index >= 0 and source_index < source_frames.size():
			result.append(source_frames[source_index].duplicate(true))
	return result


func save_curation(_take := "") -> Dictionary:
	var result := curation_service.save_curation(_curation_params()) as Dictionary
	last_errors = _errors_from(result)
	return result


func preview_promotion(_take := "") -> Dictionary:
	var preview_params := _curation_params()
	var result := curation_service.preview_promotion(preview_params) as Dictionary
	last_errors = _errors_from(result)
	pending_promotion = result.duplicate(true) if last_errors.is_empty() else {}
	if not pending_promotion.is_empty():
		pending_promotion["_params"] = preview_params.duplicate(true)
	return result


func confirm_promotion() -> Dictionary:
	if pending_promotion.is_empty():
		return {"errors": PackedStringArray(["请先预览并确认将要创建的 take"])}
	var params := (pending_promotion.get("_params", {}) as Dictionary).duplicate(true)
	if params.is_empty():
		return {"errors": PackedStringArray(["提升预览参数已失效，请重新预览"])}
	params["resolved_take"] = str(pending_promotion["take"])
	var result := curation_service.promote_selection(params) as Dictionary
	last_errors = _errors_from(result)
	if last_errors.is_empty():
		set_active_take(str(result.get("take", params["resolved_take"])))
		load_config(config_path)
		if refresh_callback.is_valid():
			refresh_callback.call()
		var resource_path := str(result.get("resource_path", ""))
		if not resource_path.is_empty() and open_resource_callback.is_valid():
			open_resource_callback.call(resource_path)
		pending_promotion.clear()
	return result


func set_preferred_take(action: String, take: String) -> Dictionary:
	var registered := false
	for take_value: Variant in action_overview(action).get("takes", []) as Array:
		if str((take_value as Dictionary).get("name", "")) == take:
			registered = true
			break
	if not registered:
		return {"errors": PackedStringArray(["动作 %s 中没有已注册 take：%s" % [action, take]])}
	var result := curation_service.set_preferred_take({
		"config_path": config_path,
		"character_id": str(config.get("character_id", "niko")),
		"action": action,
		"take": take,
	}) as Dictionary
	last_errors = _errors_from(result)
	if last_errors.is_empty():
		load_config(config_path)
		if refresh_callback.is_valid():
			refresh_callback.call()
	return result


func publish_runtime() -> Dictionary:
	if not publish_callback.is_valid():
		return {"errors": PackedStringArray(["运行时发布器不可用"])}
	return publish_callback.call() as Dictionary


func cleanup_current(confirmed: bool) -> Dictionary:
	if not confirmed:
		return {"errors": PackedStringArray(["清理外部暂存需要确认"])}
	if current_staging_directory.is_empty():
		return {"errors": PackedStringArray(["当前没有可清理的外部暂存"])}
	if not current_job_id.is_empty() and jobs.has(current_job_id):
		var state := str((jobs[current_job_id] as Dictionary).get("state", ""))
		if state not in TERMINAL_STATES:
			return {"errors": PackedStringArray(["活动任务不能清理，请先取消并等待终态"])}
	var result := curation_service.cleanup_staging({"staging_directory": current_staging_directory}) as Dictionary
	last_errors = _errors_from(result)
	if last_errors.is_empty():
		if jobs.has(current_job_id):
			var row := jobs[current_job_id] as Dictionary
			row.erase("curation")
			row["staging_removed"] = true
			jobs[current_job_id] = row
		source_frames.clear()
		model.set_source_count(0)
		model.set_sequence([])
		current_job_id = ""
		current_action = ""
		current_manifest_path = ""
		current_staging_directory = ""
		current_take = ""
		pending_promotion.clear()
	return result


func activate_job(job_id: String) -> Dictionary:
	if not jobs.has(job_id):
		return {"errors": PackedStringArray(["未知任务：%s" % job_id])}
	_store_active_snapshot()
	var row := jobs[job_id] as Dictionary
	if not row.get("curation", {}) is Dictionary or (row.get("curation", {}) as Dictionary).is_empty():
		return {"errors": PackedStringArray(["任务尚无可编辑的挑帧结果：%s" % job_id])}
	_apply_snapshot(job_id, row)
	return {"errors": PackedStringArray(), "job_id": job_id, "state": row.get("state", "")}


func _complete_job(row: Dictionary) -> void:
	var staging := str(row.get("staging_directory", row.get("output_directory", "")))
	var candidates: PackedStringArray = (
		manifest_finder.call(staging) as PackedStringArray
		if manifest_finder.is_valid()
		else _find_manifests(staging)
	)
	var valid: Array[Dictionary] = []
	var errors := PackedStringArray()
	for path: String in candidates:
		var checked := curation_service.validate_external_manifest(path) as Dictionary
		var checked_errors := _errors_from(checked)
		if checked_errors.is_empty():
			valid.append(checked)
		else:
			errors.append_array(checked_errors)
	if valid.size() != 1:
		row["state"] = "failed"
		errors.append("完成的任务必须恰好包含一个有效外部 manifest，实际为 %d" % valid.size())
		row["errors"] = errors
		return
	var manifest_result := valid[0]
	var manifest := manifest_result["manifest"] as Dictionary
	var manifest_path := str(manifest_result.get("manifest_path", candidates[0]))
	var timing := _default_timing(manifest)
	var snapshot := {
		"manifest_path": manifest_path,
		"staging_directory": staging,
		"action": str(row.get("action", "")),
		"take": str(row.get("take", "take")),
		"source_frames": _source_frames_from(manifest, manifest_path),
		"selection": [],
		"fps": float(timing["fps"]),
		"loop": bool(timing["loop"]),
	}
	row["manifest_path"] = manifest_path
	row["manifest_loaded"] = true
	var resumed := curation_service.load_curation({"manifest_path": manifest_path}) as Dictionary
	var resume_errors := _errors_from(resumed)
	if resume_errors.is_empty():
		snapshot["selection"] = (resumed.get("selection", []) as Array).duplicate()
		snapshot["fps"] = float(resumed.get("fps", snapshot["fps"]))
		snapshot["loop"] = bool(resumed.get("loop", snapshot["loop"]))
	elif not _is_missing_sidecar(resume_errors):
		row["errors"] = resume_errors
		last_errors = resume_errors
	row["curation"] = snapshot
	if current_job_id.is_empty():
		_apply_snapshot(str(row.get("job_id", "")), row)


func _source_frames_from(manifest: Dictionary, manifest_path: String) -> Array[Dictionary]:
	var frames: Array[Dictionary] = []
	for frame_value: Variant in manifest.get("source_frames", []) as Array:
		var frame := (frame_value as Dictionary).duplicate(true)
		frame["png_path"] = manifest_path.get_base_dir().path_join(str(frame.get("png", ""))).simplify_path()
		frames.append(frame)
	return frames


func _default_timing(manifest: Dictionary) -> Dictionary:
	var source := manifest.get("source", {}) as Dictionary
	var row := (((manifest.get("animation", {}) as Dictionary).get("rows", {}) as Dictionary).get("source_all", {}) as Dictionary)
	var default_fps := _fps_value(source.get("fps", null))
	if default_fps <= 0.0:
		default_fps = _fps_value(row.get("fps", null))
	if default_fps <= 0.0:
		for frame_value: Variant in manifest.get("source_frames", []) as Array:
			var duration_ms := float((frame_value as Dictionary).get("duration_ms", 0.0))
			if duration_ms > 0.0:
				default_fps = 1000.0 / duration_ms
				break
	if default_fps < 0.1 or default_fps > 120.0:
		default_fps = 10.0
	return {"fps": default_fps, "loop": bool(row.get("loop", true))}


func _store_active_snapshot() -> void:
	if current_job_id.is_empty() or not jobs.has(current_job_id):
		return
	var row := jobs[current_job_id] as Dictionary
	var snapshot := row.get("curation", {}) as Dictionary
	if snapshot.is_empty():
		return
	snapshot["selection"] = model.sequence.duplicate()
	snapshot["fps"] = model.fps
	snapshot["loop"] = model.loop
	snapshot["take"] = current_take
	row["curation"] = snapshot
	jobs[current_job_id] = row


func _apply_snapshot(job_id: String, row: Dictionary) -> void:
	var snapshot := row.get("curation", {}) as Dictionary
	current_job_id = job_id
	current_action = str(snapshot.get("action", row.get("action", "")))
	current_take = str(snapshot.get("take", row.get("take", "take")))
	current_staging_directory = str(snapshot.get("staging_directory", row.get("staging_directory", "")))
	current_manifest_path = str(snapshot.get("manifest_path", row.get("manifest_path", "")))
	source_frames.clear()
	for frame_value: Variant in snapshot.get("source_frames", []) as Array:
		source_frames.append((frame_value as Dictionary).duplicate(true))
	model.set_source_count(source_frames.size())
	model.reset_source_selection()
	model.set_sequence(snapshot.get("selection", []) as Array)
	if not model.set_fps(float(snapshot.get("fps", 10.0))):
		model.set_fps(10.0)
	model.set_loop(bool(snapshot.get("loop", true)))


func _curation_params() -> Dictionary:
	return {
		"manifest_path": current_manifest_path,
		"selection": model.sequence.duplicate(),
		"fps": model.fps,
		"loop": model.loop,
		"config_path": config_path,
		"character_id": str(config.get("character_id", "niko")),
		"action": current_action,
		"take": current_take,
	}


static func _filter_video_files(paths: Variant) -> PackedStringArray:
	var result := PackedStringArray()
	if not paths is Array and not paths is PackedStringArray:
		return result
	for value: Variant in paths:
		var path := str(value).replace("\\", "/")
		if path.is_absolute_path() and path.get_extension().to_lower() in VIDEO_EXTENSIONS:
			result.append(path)
	return result


static func _progress(result: Dictionary) -> float:
	var completed := float(result.get("completed_frames", result.get("completed", 0)))
	var total := float(result.get("total_frames", result.get("total", 0)))
	return clampf(completed / total, 0.0, 1.0) if total > 0.0 else 0.0


func _append_changed_job(job_id: String, row: Dictionary, results: Array[Dictionary]) -> void:
	var fingerprint := _job_fingerprint(row)
	if str(_job_fingerprints.get(job_id, "")) == fingerprint:
		return
	_job_fingerprints[job_id] = fingerprint
	results.append(row.duplicate(true))


static func _job_fingerprint(row: Dictionary) -> String:
	return JSON.stringify({
		"state": str(row.get("state", "")),
		"progress": float(row.get("progress", 0.0)),
		"completed": int(row.get("completed_frames", row.get("completed", 0))),
		"total": int(row.get("total_frames", row.get("total", 0))),
		"errors": "\n".join(_errors_from(row)),
		"cancellation_pending": bool(row.get("cancellation_pending", false)),
	})


static func _fps_value(value: Variant) -> float:
	if value is Dictionary:
		return float((value as Dictionary).get("value", 0.0))
	if value is float or value is int:
		return float(value)
	return 0.0


static func _errors_from(result: Dictionary) -> PackedStringArray:
	var value: Variant = result.get("errors", PackedStringArray())
	var errors := PackedStringArray()
	if value is PackedStringArray:
		errors = (value as PackedStringArray).duplicate()
	elif value is Array:
		for error: Variant in value:
			errors.append(str(error))
	elif not str(value).is_empty():
		errors.append(str(value))
	var singular := str(result.get("error", ""))
	if not singular.is_empty() and singular not in errors:
		errors.append(singular)
	return errors


static func _is_missing_sidecar(errors: PackedStringArray) -> bool:
	var text := "\n".join(errors).to_lower()
	return text.contains("not found") or text.contains("missing sidecar")


static func _find_manifests(root: String) -> PackedStringArray:
	var result := PackedStringArray()
	_scan_manifests(root, result)
	result.sort()
	return result


static func _scan_manifests(path: String, result: PackedStringArray) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child := path.path_join(entry)
			if directory.current_is_dir():
				_scan_manifests(child, result)
			elif entry == "manifest.json":
				result.append(child)
		entry = directory.get_next()
	directory.list_dir_end()
