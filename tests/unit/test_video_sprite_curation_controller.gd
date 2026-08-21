extends GdUnitTestSuite


const Controller = preload("res://addons/character_sprite_authoring/video_sprite_curation_controller.gd")


class FakeJobService extends RefCounted:
	var ready := true
	var started: Array[Dictionary] = []
	var polls: Dictionary = {}
	var cancelled: Array[String] = []

	func dependency_status(_params := {}) -> Dictionary:
		return {
			"ready": ready,
			"python": {"resolved": ready, "path": "C:/python.exe"},
			"pixelmotion": {"resolved": ready, "path": "C:/pixelmotion"},
			"sprite_gen": {"resolved": ready, "path": "C:/sprite-gen"},
			"worker_script": {"resolved": ready, "path": "C:/worker.py"},
			"ffprobe": {"resolved": ready, "path": "C:/ffprobe.exe"},
		}

	func start_single_video_job(params: Dictionary) -> Dictionary:
		started.append(params.duplicate(true))
		var number := started.size()
		return {
			"errors": PackedStringArray(), "job_id": "job-%d" % number, "state": "queued",
			"output_directory": "C:/stage/job-%d" % number,
		}

	func poll_job(job_id: String) -> Dictionary:
		return (polls.get(job_id, {"job_id": job_id, "state": "running"}) as Dictionary).duplicate(true)

	func cancel_job(job_id: String) -> Dictionary:
		cancelled.append(job_id)
		return {"errors": PackedStringArray(), "job_id": job_id, "state": "cancellation_requested"}


class FakeCurationService extends RefCounted:
	var manifest_result: Dictionary = {}
	var load_result: Dictionary = {"errors": PackedStringArray(["missing sidecar"])}
	var calls: Array[Dictionary] = []
	var cleanup_calls: Array[Dictionary] = []

	func validate_external_manifest(path: String) -> Dictionary:
		var result := manifest_result.duplicate(true)
		result["manifest_path"] = path
		return result

	func load_curation(params: Dictionary) -> Dictionary:
		calls.append({"method": "load", "params": params.duplicate(true)})
		return load_result.duplicate(true)

	func save_curation(params: Dictionary) -> Dictionary:
		calls.append({"method": "save", "params": params.duplicate(true)})
		return {"errors": PackedStringArray(), "curation_path": "C:/stage/job-1/godot-curation.json"}

	func preview_promotion(params: Dictionary) -> Dictionary:
		calls.append({"method": "preview", "params": params.duplicate(true)})
		return {"errors": PackedStringArray(), "take": "clip_2", "output_path": "res://tools/sprites/niko/walk/clip_2"}

	func promote_selection(params: Dictionary) -> Dictionary:
		calls.append({"method": "promote", "params": params.duplicate(true)})
		return {"errors": PackedStringArray(), "take": params["resolved_take"], "resource_path": "res://tools/sprites/niko/walk/clip_2/selection.tres"}

	func set_preferred_take(params: Dictionary) -> Dictionary:
		calls.append({"method": "preferred", "params": params.duplicate(true)})
		return {"errors": PackedStringArray(), "preferred_take": params["take"]}

	func cleanup_staging(params: Dictionary) -> Dictionary:
		cleanup_calls.append(params.duplicate(true))
		return {"errors": PackedStringArray(), "removed_path": params["staging_directory"], "removed_entries": 21}


var published := 0
var opened := PackedStringArray()
var refreshed := 0
var picked := PackedStringArray(["C:/drop/picked.MOV"])


func before_test() -> void:
	published = 0
	opened = PackedStringArray()
	refreshed = 0


func test_config_overview_is_driven_by_required_actions_takes_and_preferred_take() -> void:
	var controller := Controller.new()
	var result: Dictionary = controller.load_config("res://tools/video_sprites/niko_character_sources.json")
	assert_array(result.get("errors", PackedStringArray())).is_empty()
	assert_array(controller.action_names()).is_equal(["spawn", "idle", "walk", "dash", "hit", "death", "victory"])
	var walk: Dictionary = controller.action_overview("walk")
	assert_str(walk.get("preferred_take", "")).is_equal("happy")
	var take_names: Array = (walk.get("takes", []) as Array).map(
		func(take: Dictionary) -> String: return str(take["name"])
	)
	assert_array(take_names).is_equal(["happy", "power", "strong"])
	assert_array(controller.action_overview("dash").get("takes", [])).is_empty()


func test_video_drop_filters_extensions_assigns_hovered_then_selected_action_and_picker_never_infers_from_filename() -> void:
	var jobs := FakeJobService.new()
	var controller := Controller.new()
	controller.job_service = jobs
	controller.load_config("res://tools/video_sprites/niko_character_sources.json")
	controller.select_action("idle")

	var hovered: Dictionary = controller.accept_video_files([
		"C:/drop/name_says_idle.mp4", "C:/drop/second.WEBM", "C:/drop/readme.txt",
	], "walk")
	assert_array(hovered.get("errors", PackedStringArray())).is_empty()
	assert_int(jobs.started.size()).is_equal(2)
	var assigned_actions: Array = jobs.started.map(
		func(params: Dictionary) -> String: return str(params["action"])
	)
	assert_array(assigned_actions).is_equal(["walk", "walk"])

	controller.file_picker = Callable(self, "_pick_files")
	var picked_result: Dictionary = controller.pick_video_files()
	assert_array(picked_result.get("errors", PackedStringArray())).is_empty()
	assert_str(jobs.started.back()["action"]).is_equal("idle")
	assert_str(jobs.started.back()["source_video"]).is_equal("C:/drop/picked.MOV")

	controller.select_action("")
	var rejected: Dictionary = controller.accept_video_files(["C:/drop/walk.mp4"])
	assert_str("\n".join(rejected.get("errors", PackedStringArray()))).contains("请先选择动作")


func test_dependency_failure_is_visible_and_never_starts_or_falls_back_to_legacy_import() -> void:
	var jobs := FakeJobService.new()
	jobs.ready = false
	var controller := Controller.new()
	controller.job_service = jobs
	controller.load_config("res://tools/video_sprites/niko_character_sources.json")
	controller.select_action("walk")
	var result: Dictionary = controller.accept_video_files(["C:/drop/clip.mp4"])
	assert_int(jobs.started.size()).is_zero()
	assert_str("\n".join(result.get("errors", PackedStringArray()))).contains("依赖未就绪")
	assert_bool(result.get("legacy_fallback", true)).is_false()
	assert_dict(controller.dependency_diagnostics()).contains_keys(["python", "pixelmotion", "sprite_gen", "worker_script", "ffprobe"])


func test_poll_cancel_and_completion_load_exactly_one_valid_manifest_with_every_frame_including_18() -> void:
	var jobs := FakeJobService.new()
	var curation := FakeCurationService.new()
	curation.manifest_result = {"errors": PackedStringArray(), "manifest": _manifest(20)}
	var controller := Controller.new()
	controller.job_service = jobs
	controller.curation_service = curation
	controller.manifest_finder = Callable(self, "_find_manifest")
	controller.load_config("res://tools/video_sprites/niko_character_sources.json")
	controller.select_action("walk")
	controller.accept_video_files(["C:/drop/clip.mp4"])

	jobs.polls["job-1"] = {"job_id": "job-1", "state": "running", "completed_frames": 7, "total_frames": 20, "errors": PackedStringArray()}
	var running: Dictionary = controller.poll_jobs()[0]
	assert_str(running["state"]).is_equal("running")
	assert_float(running["progress"]).is_equal_approx(0.35, 0.001)
	var cancelling: Dictionary = controller.cancel_job("job-1")
	assert_str(cancelling["state"]).is_equal("cancelling")
	var still_cancelling: Dictionary = controller.poll_jobs()[0]
	assert_str(still_cancelling["state"]).is_equal("cancelling")

	jobs.polls["job-1"] = {"job_id": "job-1", "state": "complete", "errors": PackedStringArray()}
	var complete: Dictionary = controller.poll_jobs()[0]
	assert_str(complete["state"]).is_equal("complete")
	assert_int(controller.source_frames.size()).is_equal(20)
	assert_bool(controller.source_frames.any(func(frame: Dictionary) -> bool: return int(frame["source_frame"]) == 18)).is_true()
	assert_str(controller.source_frames[17]["png_path"]).is_equal("C:/stage/job-1/frames/frame_018.png")
	assert_array(controller.model.sequence).is_empty()
	assert_float(controller.model.fps).is_equal_approx(25.0, 0.001)


func test_sidecar_preview_promotion_preferred_publish_and_cleanup_are_explicit_and_separate() -> void:
	var jobs := FakeJobService.new()
	var curation := FakeCurationService.new()
	curation.manifest_result = {"errors": PackedStringArray(), "manifest": _manifest(3)}
	curation.load_result = {"errors": PackedStringArray(), "selection": [2, 0], "fps": 12.0, "loop": false}
	var controller := Controller.new()
	controller.job_service = jobs
	controller.curation_service = curation
	controller.manifest_finder = Callable(self, "_find_manifest")
	controller.publish_callback = Callable(self, "_publish")
	controller.open_resource_callback = Callable(self, "_open")
	controller.refresh_callback = Callable(self, "_refresh")
	controller.load_config("res://tools/video_sprites/niko_character_sources.json")
	controller.select_action("walk")
	controller.accept_video_files(["C:/drop/clip.mp4"])
	jobs.polls["job-1"] = {"job_id": "job-1", "state": "complete", "errors": PackedStringArray()}
	controller.poll_jobs()
	assert_array(controller.model.sequence).is_equal([2, 0])
	assert_float(controller.model.fps).is_equal_approx(12.0, 0.001)
	assert_bool(controller.model.loop).is_false()

	controller.save_curation("clip")
	var preview: Dictionary = controller.preview_promotion("clip")
	assert_str(preview["take"]).is_equal("clip_2")
	var promoted: Dictionary = controller.confirm_promotion()
	assert_str(promoted["take"]).is_equal("clip_2")
	assert_array(opened).is_equal(["res://tools/sprites/niko/walk/clip_2/selection.tres"])
	assert_int(refreshed).is_equal(1)
	controller.set_preferred_take("walk", "happy")
	assert_int(published).is_zero()

	var refused: Dictionary = controller.cleanup_current(false)
	assert_str("\n".join(refused.get("errors", PackedStringArray()))).contains("需要确认")
	assert_array(curation.cleanup_calls).is_empty()
	controller.publish_runtime()
	assert_int(published).is_equal(1)
	assert_int(curation.cleanup_calls.size()).is_zero()
	var cleaned: Dictionary = controller.cleanup_current(true)
	assert_int(cleaned.get("removed_entries", 0)).is_equal(21)
	assert_int(curation.cleanup_calls.size()).is_equal(1)


func test_multiple_completed_jobs_keep_independent_snapshots_and_never_change_visible_action() -> void:
	var jobs := FakeJobService.new()
	var curation := FakeCurationService.new()
	curation.manifest_result = {"errors": PackedStringArray(), "manifest": _manifest(3)}
	var controller := Controller.new()
	controller.job_service = jobs
	controller.curation_service = curation
	controller.manifest_finder = Callable(self, "_find_manifest")
	controller.load_config("res://tools/video_sprites/niko_character_sources.json")
	controller.select_action("walk")
	controller.accept_video_files(["C:/drop/one.mp4", "C:/drop/two.mp4"])
	controller.select_action("idle")
	jobs.polls["job-1"] = {"job_id": "job-1", "state": "complete", "errors": PackedStringArray()}
	jobs.polls["job-2"] = {"job_id": "job-2", "state": "complete", "errors": PackedStringArray()}
	controller.poll_jobs()
	assert_str(controller.selected_action).is_equal("idle")
	assert_str(controller.current_job_id).is_equal("job-1")
	assert_str(controller.current_action).is_equal("walk")
	controller.model.set_sequence([2, 0])
	controller.model.set_fps(17.0)
	controller.activate_job("job-1")
	assert_array(controller.model.sequence).is_equal([2, 0])
	assert_float(controller.model.fps).is_equal_approx(17.0, 0.001)
	assert_array(controller.activate_job("job-2").get("errors", PackedStringArray())).is_empty()
	assert_array(controller.model.sequence).is_empty()
	assert_array(controller.activate_job("job-1").get("errors", PackedStringArray())).is_empty()
	assert_array(controller.model.sequence).is_equal([2, 0])
	controller.save_curation("one")
	assert_str(curation.calls.back()["params"]["action"]).is_equal("walk")
	controller.preview_promotion("one")
	controller.activate_job("job-2")
	controller.confirm_promotion()
	assert_str(curation.calls.back()["method"]).is_equal("promote")
	var promote_params := curation.calls.back()["params"] as Dictionary
	assert_str(promote_params["manifest_path"]).is_equal("C:/stage/job-1/manifest.json")
	assert_str(promote_params["action"]).is_equal("walk")
	assert_array(promote_params["selection"]).is_equal([2, 0])


func test_switching_snapshots_resets_source_selection_and_shift_anchor() -> void:
	var jobs := FakeJobService.new()
	var curation := FakeCurationService.new()
	curation.manifest_result = {"errors": PackedStringArray(), "manifest": _manifest(3)}
	var controller := Controller.new()
	controller.job_service = jobs
	controller.curation_service = curation
	controller.manifest_finder = Callable(self, "_find_manifest")
	controller.load_config("res://tools/video_sprites/niko_character_sources.json")
	controller.select_action("walk")
	controller.accept_video_files(["C:/drop/one.mp4", "C:/drop/two.mp4"])
	jobs.polls["job-1"] = {"job_id": "job-1", "state": "complete", "errors": PackedStringArray()}
	jobs.polls["job-2"] = {"job_id": "job-2", "state": "complete", "errors": PackedStringArray()}
	controller.poll_jobs()
	controller.model.select_source(1)
	controller.model.select_source(2, false, true)
	assert_array(controller.model.selected_source_indices()).is_equal([1, 2])
	assert_int(controller.model.source_anchor).is_equal(1)
	controller.activate_job("job-2")
	assert_array(controller.model.selected_source_indices()).is_empty()
	assert_int(controller.model.source_anchor).is_equal(-1)
	controller.model.select_source(2, false, true)
	assert_array(controller.model.selected_source_indices()).is_equal([2])
	assert_int(controller.model.source_anchor).is_equal(2)


func test_manifest_animation_fps_is_used_before_the_ten_fps_fallback() -> void:
	var jobs := FakeJobService.new()
	var curation := FakeCurationService.new()
	var manifest := _manifest(3)
	(manifest["source"] as Dictionary).erase("fps")
	(((manifest["animation"] as Dictionary)["rows"] as Dictionary)["source_all"] as Dictionary)["fps"] = 15.0
	curation.manifest_result = {"errors": PackedStringArray(), "manifest": manifest}
	var controller := Controller.new()
	controller.job_service = jobs
	controller.curation_service = curation
	controller.manifest_finder = Callable(self, "_find_manifest")
	controller.load_config("res://tools/video_sprites/niko_character_sources.json")
	controller.select_action("walk")
	controller.accept_video_files(["C:/drop/clip.mp4"])
	jobs.polls["job-1"] = {"job_id": "job-1", "state": "complete", "errors": PackedStringArray()}
	controller.poll_jobs()
	assert_float(controller.model.fps).is_equal_approx(15.0, 0.001)


func test_completion_rejects_zero_or_multiple_valid_manifests() -> void:
	for finder: Callable in [Callable(self, "_find_no_manifests"), Callable(self, "_find_two_manifests")]:
		var jobs := FakeJobService.new()
		var curation := FakeCurationService.new()
		curation.manifest_result = {"errors": PackedStringArray(), "manifest": _manifest(3)}
		var controller := Controller.new()
		controller.job_service = jobs
		controller.curation_service = curation
		controller.manifest_finder = finder
		controller.load_config("res://tools/video_sprites/niko_character_sources.json")
		controller.select_action("walk")
		controller.accept_video_files(["C:/drop/clip.mp4"])
		jobs.polls["job-1"] = {"job_id": "job-1", "state": "complete", "errors": PackedStringArray()}
		var completed: Dictionary = controller.poll_jobs()[0]
		assert_str(completed.get("state", "")).is_equal("failed")
		assert_str("\n".join(completed.get("errors", PackedStringArray()))).contains("恰好包含一个")
		assert_array(controller.source_frames).is_empty()


func test_stale_sidecar_is_visible_while_default_snapshot_remains_available() -> void:
	var jobs := FakeJobService.new()
	var curation := FakeCurationService.new()
	curation.manifest_result = {"errors": PackedStringArray(), "manifest": _manifest(3)}
	curation.load_result = {"errors": PackedStringArray(["stale sidecar: manifest fingerprint changed"])}
	var controller := Controller.new()
	controller.job_service = jobs
	controller.curation_service = curation
	controller.manifest_finder = Callable(self, "_find_manifest")
	controller.load_config("res://tools/video_sprites/niko_character_sources.json")
	controller.select_action("walk")
	controller.accept_video_files(["C:/drop/clip.mp4"])
	jobs.polls["job-1"] = {"job_id": "job-1", "state": "complete", "errors": PackedStringArray()}
	var completed: Dictionary = controller.poll_jobs()[0]
	assert_str("\n".join(completed.get("errors", PackedStringArray()))).contains("stale sidecar")
	assert_int(controller.source_frames.size()).is_equal(3)
	assert_array(controller.model.sequence).is_empty()


func test_singular_service_error_is_not_hidden_by_an_empty_errors_array() -> void:
	var errors: PackedStringArray = Controller._errors_from({
		"errors": PackedStringArray(), "error": "worker failed",
	})
	assert_array(errors).is_equal(["worker failed"])


func test_save_sends_the_active_snapshot_fields_and_active_cleanup_is_refused() -> void:
	var jobs := FakeJobService.new()
	var curation := FakeCurationService.new()
	curation.manifest_result = {"errors": PackedStringArray(), "manifest": _manifest(3)}
	var controller := Controller.new()
	controller.job_service = jobs
	controller.curation_service = curation
	controller.manifest_finder = Callable(self, "_find_manifest")
	controller.load_config("res://tools/video_sprites/niko_character_sources.json")
	controller.select_action("walk")
	controller.accept_video_files(["C:/drop/clip.mp4"])
	jobs.polls["job-1"] = {"job_id": "job-1", "state": "complete", "errors": PackedStringArray()}
	controller.poll_jobs()
	controller.model.set_sequence([2, 0])
	controller.model.set_fps(14.0)
	controller.model.set_loop(false)
	controller.save_curation("chosen")
	var params := curation.calls.back()["params"] as Dictionary
	assert_str(params["manifest_path"]).is_equal("C:/stage/job-1/manifest.json")
	assert_array(params["selection"]).is_equal([2, 0])
	assert_float(params["fps"]).is_equal_approx(14.0, 0.001)
	assert_bool(params["loop"]).is_false()
	assert_str(params["action"]).is_equal("walk")
	assert_str(params["take"]).is_equal("clip")
	(controller.jobs["job-1"] as Dictionary)["state"] = "running"
	var refused: Dictionary = controller.cleanup_current(true)
	assert_str("\n".join(refused.get("errors", PackedStringArray()))).contains("活动任务不能清理")
	assert_array(curation.cleanup_calls).is_empty()


func _manifest(frame_count: int) -> Dictionary:
	var frames: Array[Dictionary] = []
	for index in frame_count:
		frames.append({
			"index": index, "source_frame": index + 1, "timestamp_seconds": index * 0.04,
			"duration_ms": 40.0, "png": "frames/frame_%03d.png" % (index + 1),
		})
	return {
		"source": {"frame_count": frame_count, "fps": {"value": 25.0}},
		"animation": {"rows": {"source_all": {"fps": 25.0, "loop": true}}},
		"source_frames": frames,
	}


func _find_manifest(staging: String) -> PackedStringArray:
	return PackedStringArray([staging.path_join("manifest.json")])


func _find_no_manifests(_staging: String) -> PackedStringArray:
	return PackedStringArray()


func _find_two_manifests(staging: String) -> PackedStringArray:
	return PackedStringArray([
		staging.path_join("one/manifest.json"), staging.path_join("two/manifest.json"),
	])


func _pick_files() -> PackedStringArray:
	return picked


func _publish() -> Dictionary:
	published += 1
	return {"errors": PackedStringArray()}


func _open(path: String) -> void:
	opened.append(path)


func _refresh() -> void:
	refreshed += 1
