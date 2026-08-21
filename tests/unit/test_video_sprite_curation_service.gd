extends GdUnitTestSuite


const SERVICE_PATH := "res://tools/video_sprites/video_sprite_curation_service.gd"
const JOB_SERVICE_PATH := "res://tools/video_sprites/video_sprite_job_service.gd"
const Importer = preload("res://tools/video_sprites/video_sprite_manifest_importer.gd")
const STAGING_ROOT := "user://video_sprite_workspace/task-2-gdunit"
const CHARACTER_ID := "task_2_gdunit_niko"
const OUTPUT_ROOT := "res://tools/sprites/" + CHARACTER_ID
const REPORT_ROOT := "res://reports/video_sprite_curation_service"
const CONFIG_PATH := REPORT_ROOT + "/character.json"
const AUTHORING_PATH := REPORT_ROOT + "/authoring/niko.tres"
const RUNTIME_ROOT := REPORT_ROOT + "/runtime"
const RUNTIME_MARKER := RUNTIME_ROOT + "/keep.bin"


func before_test() -> void:
	_remove_tree(STAGING_ROOT)
	_remove_project_tree(OUTPUT_ROOT)
	_remove_project_tree(REPORT_ROOT)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(STAGING_ROOT))
	_write_character_config()
	_write_text(RUNTIME_MARKER, "runtime-must-not-change")


func after_test() -> void:
	_remove_tree(STAGING_ROOT)
	_remove_project_tree(OUTPUT_ROOT)
	_remove_project_tree(REPORT_ROOT)


func test_curation_round_trip_preserves_order_duplicates_fps_loop_and_intent() -> void:
	var fixture := _write_external_fixture("round-trip", 3)
	var service: Variant = _new_service()
	if service == null:
		return
	var saved: Dictionary = service.save_curation({
		"manifest_path": fixture["manifest_path"],
		"selection": [2, 0, 2],
		"fps": 12.5,
		"loop": false,
		"character_id": "Niko",
		"action": "Dash",
		"take": "Burst One",
	})
	assert_array(saved.get("errors", PackedStringArray())).is_empty()
	assert_str(saved.get("curation_path", "")).ends_with("godot-curation.json")

	var loaded: Dictionary = service.load_curation({
		"manifest_path": fixture["manifest_path"],
	})
	assert_array(loaded.get("errors", PackedStringArray())).is_empty()
	assert_array(loaded.get("selection", [])).contains_exactly([2, 0, 2])
	assert_float(loaded.get("fps", 0.0)).is_equal_approx(12.5, 0.001)
	assert_bool(loaded.get("loop", true)).is_false()
	assert_str(loaded.get("character_id", "")).is_equal("Niko")
	assert_str(loaded.get("action", "")).is_equal("Dash")
	assert_str(loaded.get("take", "")).is_equal("Burst One")


func test_selection_rejects_empty_out_of_range_non_integer_and_invalid_fps() -> void:
	var fixture := _write_external_fixture("bad-selection", 3)
	var service: Variant = _new_service()
	if service == null:
		return
	for selection: Array in [[], [-1], [3], [1.5], [true], ["1"]]:
		var result: Dictionary = service.validate_selection({
			"manifest_path": fixture["manifest_path"],
			"selection": selection,
			"fps": 12.0,
			"loop": true,
		})
		assert_array(result.get("errors", PackedStringArray())).is_not_empty()
	for fps: Variant in [0.0, -2.0, "12"]:
		var result: Dictionary = service.validate_selection({
			"manifest_path": fixture["manifest_path"],
			"selection": [0],
			"fps": fps,
			"loop": true,
		})
		assert_array(result.get("errors", PackedStringArray())).is_not_empty()
	var loop_result: Dictionary = service.validate_selection({
		"manifest_path": fixture["manifest_path"],
		"selection": [0],
		"fps": 12.0,
		"loop": 1,
	})
	assert_array(loop_result.get("errors", PackedStringArray())).is_not_empty()


func test_loading_curation_rejects_stale_manifest_and_video_hashes() -> void:
	var fixture := _write_external_fixture("stale", 2)
	var service: Variant = _new_service()
	if service == null:
		return
	var saved: Dictionary = service.save_curation({
		"manifest_path": fixture["manifest_path"],
		"selection": [1, 0],
		"fps": 10.0,
		"loop": true,
		"character_id": "niko",
		"action": "dash",
		"take": "stale",
	})
	assert_array(saved.get("errors", PackedStringArray())).is_empty()

	var original_manifest := FileAccess.get_file_as_string(fixture["manifest_path"])
	_write_text(fixture["manifest_path"], original_manifest + "\n")
	var stale_manifest: Dictionary = service.load_curation({
		"manifest_path": fixture["manifest_path"],
	})
	assert_str("\n".join(stale_manifest.get("errors", PackedStringArray()))).contains("manifest hash")

	_write_text(fixture["manifest_path"], original_manifest)
	_write_text(fixture["video_path"], "changed-video")
	var stale_video: Dictionary = service.load_curation({
		"manifest_path": fixture["manifest_path"],
	})
	assert_str("\n".join(stale_video.get("errors", PackedStringArray()))).contains("video hash")


func test_external_manifest_validation_rejects_degraded_missing_hash_cell_and_rect_breaks() -> void:
	var fixture := _write_external_fixture("manifest-errors", 2)
	var service: Variant = _new_service()
	if service == null:
		return
	var manifest := _read_json(fixture["manifest_path"])
	manifest["degraded_static_fallback"] = true
	_assert_manifest_error(service, fixture["manifest_path"], manifest, "degraded")

	manifest = _read_json(fixture["manifest_path"])
	var missing_png := _resolve_external(fixture["manifest_path"],
		str(((manifest["source_frames"] as Array)[0] as Dictionary)["png"]))
	DirAccess.remove_absolute(missing_png)
	_assert_manifest_error(service, fixture["manifest_path"], manifest, "not found")

	fixture = _write_external_fixture("hash-errors", 2)
	manifest = _read_json(fixture["manifest_path"])
	((manifest["source_frames"] as Array)[0] as Dictionary)["sha256"] = "0".repeat(64)
	_assert_manifest_error(service, fixture["manifest_path"], manifest, "sha256")

	manifest = _read_json(fixture["manifest_path"])
	(manifest["cell"] as Dictionary)["width"] = 128
	_assert_manifest_error(service, fixture["manifest_path"], manifest, "256x256")

	manifest = _read_json(fixture["manifest_path"])
	var rect := ((((manifest["frame_layout"] as Dictionary)["rows"] as Dictionary)["source_all"] as Array)[0] as Dictionary)
	rect["x"] = 512
	((manifest["source_frames"] as Array)[0] as Dictionary)["rect"] = rect.duplicate(true)
	_assert_manifest_error(service, fixture["manifest_path"], manifest, "rectangle")


func test_external_manifest_validation_rejects_inconsistent_counts_timing_and_static_source() -> void:
	var fixture := _write_external_fixture("consistency", 2)
	var service: Variant = _new_service()
	if service == null:
		return
	var manifest := _read_json(fixture["manifest_path"])
	(manifest["source_frames"] as Array).pop_back()
	_assert_manifest_error(service, fixture["manifest_path"], manifest, "count")

	fixture = _write_external_fixture("timing-consistency", 2)
	manifest = _read_json(fixture["manifest_path"])
	((manifest["source_frames"] as Array)[1] as Dictionary)["timestamp_seconds"] = 0.0
	_assert_manifest_error(service, fixture["manifest_path"], manifest, "timestamp")

	fixture = _write_external_fixture("duration-consistency", 2)
	manifest = _read_json(fixture["manifest_path"])
	((manifest["source_frames"] as Array)[1] as Dictionary)["duration_ms"] = 45.0
	_assert_manifest_error(service, fixture["manifest_path"], manifest, "duration")

	fixture = _write_external_fixture("atlas-consistency", 2)
	manifest = _read_json(fixture["manifest_path"])
	var tampered_atlas := Image.load_from_file(ProjectSettings.globalize_path(fixture["root"] + "/atlas.png"))
	tampered_atlas.fill_rect(Rect2i(0, 0, 32, 32), Color.MAGENTA)
	assert_int(tampered_atlas.save_png(ProjectSettings.globalize_path(fixture["root"] + "/atlas.png"))).is_equal(OK)
	var atlas_result: Dictionary = service.validate_external_manifest(fixture["manifest_path"])
	assert_str("\n".join(atlas_result.get("errors", PackedStringArray()))).contains("does not match atlas")

	fixture = _write_external_fixture("static", 1)
	manifest = _read_json(fixture["manifest_path"])
	_assert_manifest_error(service, fixture["manifest_path"], manifest, "more than one")


func test_promotion_packs_unique_cells_reuses_duplicate_rects_and_emits_selected_only_resources() -> void:
	var fixture := _write_external_fixture("promote", 3)
	var service: Variant = _new_service()
	if service == null or not _require_method(service, "promote_selection"):
		return
	var result: Dictionary = service.promote_selection({
		"manifest_path": fixture["manifest_path"],
		"selection": [2, 0, 2],
		"fps": 12.0,
		"loop": false,
		"config_path": CONFIG_PATH,
		"character_id": CHARACTER_ID,
		"action": "dash",
		"take": "Burst One",
	})
	assert_array(result.get("errors", PackedStringArray())).is_empty()
	assert_str(result.get("take", "")).is_equal("burst_one")
	var take_root := OUTPUT_ROOT + "/dash/burst_one"
	assert_str(result.get("output_path", "")).is_equal(take_root)
	for required: String in [
		"atlas.png", "manifest.json", "provenance.json", "selected_frames.tres", "preview.tscn",
	]:
		assert_bool(FileAccess.file_exists(take_root.path_join(required))).is_true()
	var atlas := Image.load_from_file(ProjectSettings.globalize_path(take_root + "/atlas.png"))
	assert_int(atlas.get_width()).is_equal(512)
	assert_int(atlas.get_height()).is_equal(256)

	var manifest := _read_json(take_root + "/manifest.json")
	var imported_manifest := Importer.parse_manifest_file(take_root + "/manifest.json")
	assert_array(imported_manifest.get("errors", PackedStringArray())).is_empty()
	var rects := (((manifest["frame_layout"] as Dictionary)["rows"] as Dictionary)["source_all"] as Array)
	assert_int(rects.size()).is_equal(3)
	assert_dict(rects[0]).is_equal(rects[2])
	assert_dict(rects[0]).is_not_equal(rects[1])
	var source_frames := manifest["source_frames"] as Array
	assert_array(source_frames.map(func(frame: Dictionary) -> int: return int(frame["source_index"]))).contains_exactly([2, 0, 2])
	assert_array(source_frames.map(func(frame: Dictionary) -> int: return int(frame["source_frame"]))).contains_exactly([3, 1, 3])
	assert_float(float((source_frames[0] as Dictionary)["timestamp_seconds"])).is_equal_approx(0.08, 0.001)
	assert_float(float((source_frames[0] as Dictionary)["duration_ms"])).is_equal_approx(1000.0 / 12.0, 0.001)
	assert_bool((((manifest["animation"] as Dictionary)["rows"] as Dictionary)["source_all"] as Dictionary)["loop"]).is_false()

	var frame_files := _files_below(take_root + "/frames")
	assert_array(frame_files).contains_exactly_in_any_order(["source_001.png", "source_003.png"])
	assert_bool(FileAccess.file_exists(take_root + "/source.mp4")).is_false()
	assert_bool(FileAccess.file_exists(take_root + "/frames/source_002.png")).is_false()

	var selected := ResourceLoader.load(
		take_root + "/selected_frames.tres", "SpriteFrames", ResourceLoader.CACHE_MODE_REPLACE
	) as SpriteFrames
	assert_object(selected).is_not_null()
	assert_int(selected.get_frame_count(&"source_all")).is_equal(3)
	assert_float(selected.get_animation_speed(&"source_all")).is_equal_approx(12.0, 0.001)
	assert_bool(selected.get_animation_loop(&"source_all")).is_false()
	for index in selected.get_frame_count(&"source_all"):
		var texture := selected.get_frame_texture(&"source_all", index)
		assert_bool(texture is AtlasTexture).is_true()
		assert_object(texture).is_not_null()
		assert_object(texture as AtlasTexture).is_not_null()
		assert_bool((texture as AtlasTexture).region.size == Vector2(256, 256)).is_true()
	assert_bool(
		(selected.get_frame_texture(&"source_all", 0) as AtlasTexture).region
		== (selected.get_frame_texture(&"source_all", 2) as AtlasTexture).region
	).is_true()

	var config := _read_json(CONFIG_PATH)
	var dash := (config["actions"] as Dictionary)["dash"] as Dictionary
	assert_str(dash.get("preferred_take", "changed")).is_empty()
	assert_int((dash["takes"] as Array).size()).is_equal(1)
	var take := (dash["takes"] as Array)[0] as Dictionary
	assert_str(take["resource_path"]).is_equal(take_root + "/selected_frames.tres")
	assert_str(take["manifest_path"]).is_equal(take_root + "/manifest.json")
	var authoring := ResourceLoader.load(
		AUTHORING_PATH, "SpriteFrames", ResourceLoader.CACHE_MODE_REPLACE
	) as SpriteFrames
	assert_object(authoring).is_not_null()
	assert_int(authoring.get_frame_count(&"source__dash_down__burst_one")).is_equal(3)
	assert_bool(authoring.has_animation(&"dash_down")).is_false()
	assert_str(FileAccess.get_file_as_string(RUNTIME_MARKER)).is_equal("runtime-must-not-change")
	assert_bool(FileAccess.file_exists(RUNTIME_ROOT + "/task_2_gdunit_niko_runtime_frames.tres")).is_false()


func test_preview_suffixes_repeated_takes_and_resolved_take_refuses_overwrite() -> void:
	var fixture := _write_external_fixture("unique", 2)
	var service: Variant = _new_service()
	if service == null or not _require_method(service, "preview_promotion") or not _require_method(service, "promote_selection"):
		return
	var params := _promotion_params(fixture["manifest_path"], "repeat")
	var preview: Dictionary = service.preview_promotion(params)
	assert_array(preview.get("errors", PackedStringArray())).is_empty()
	assert_str(preview.get("take", "")).is_equal("repeat")
	params["resolved_take"] = "repeat"
	var first: Dictionary = service.promote_selection(params)
	assert_array(first.get("errors", PackedStringArray())).is_empty()

	var second_preview: Dictionary = service.preview_promotion(_promotion_params(fixture["manifest_path"], "repeat"))
	assert_str(second_preview.get("take", "")).is_equal("repeat_2")
	var overwrite_params := _promotion_params(fixture["manifest_path"], "repeat")
	overwrite_params["resolved_take"] = "repeat"
	var overwrite: Dictionary = service.promote_selection(overwrite_params)
	assert_str("\n".join(overwrite.get("errors", PackedStringArray()))).contains("already exists")
	assert_str(FileAccess.get_file_as_string(OUTPUT_ROOT + "/dash/repeat/manifest.json")).is_equal(
		FileAccess.get_file_as_string(first["manifest_path"])
	)


func test_failed_atomic_config_replacement_keeps_original_bytes_and_reports_failure() -> void:
	var fixture := _write_external_fixture("atomic", 2)
	var service: Variant = _new_service()
	if service == null or not _require_method(service, "promote_selection"):
		return
	assert_bool("config_replacer" in service).is_true()
	service.config_replacer = func(_temporary: String, _destination: String) -> bool: return false
	var original := FileAccess.get_file_as_bytes(CONFIG_PATH)
	var result: Dictionary = service.promote_selection(_promotion_params(fixture["manifest_path"], "atomic"))
	assert_array(result.get("errors", PackedStringArray())).is_not_empty()
	assert_array(FileAccess.get_file_as_bytes(CONFIG_PATH)).contains_exactly(original)
	assert_int((_read_json(CONFIG_PATH)["actions"]["dash"]["takes"] as Array).size()).is_equal(0)
	assert_bool(FileAccess.file_exists(AUTHORING_PATH)).is_false()


func test_preferred_take_changes_only_explicitly_and_rebuilds_authoring_without_runtime_publish() -> void:
	var fixture := _write_external_fixture("preferred", 2)
	var service: Variant = _new_service()
	if service == null or not _require_method(service, "promote_selection") or not _require_method(service, "set_preferred_take"):
		return
	var promoted: Dictionary = service.promote_selection(_promotion_params(fixture["manifest_path"], "chosen"))
	assert_array(promoted.get("errors", PackedStringArray())).is_empty()
	assert_str(_read_json(CONFIG_PATH)["actions"]["dash"]["preferred_take"]).is_empty()
	var preferred: Dictionary = service.set_preferred_take({
		"config_path": CONFIG_PATH,
		"character_id": CHARACTER_ID,
		"action": "dash",
		"take": "chosen",
	})
	assert_array(preferred.get("errors", PackedStringArray())).is_empty()
	assert_str(_read_json(CONFIG_PATH)["actions"]["dash"]["preferred_take"]).is_equal("chosen")
	var authoring := ResourceLoader.load(AUTHORING_PATH, "SpriteFrames", ResourceLoader.CACHE_MODE_REPLACE) as SpriteFrames
	assert_int(authoring.get_frame_count(&"dash_down")).is_equal(3)
	assert_str(FileAccess.get_file_as_string(RUNTIME_MARKER)).is_equal("runtime-must-not-change")
	var bytes_before := FileAccess.get_file_as_bytes(CONFIG_PATH)
	var missing: Dictionary = service.set_preferred_take({
		"config_path": CONFIG_PATH, "character_id": CHARACTER_ID,
		"action": "dash", "take": "missing",
	})
	assert_array(missing.get("errors", PackedStringArray())).is_not_empty()
	assert_array(FileAccess.get_file_as_bytes(CONFIG_PATH)).contains_exactly(bytes_before)


func test_cleanup_removes_one_exact_staged_cache_and_rejects_root_sibling_and_link_escape() -> void:
	var fixture := _write_external_fixture("cleanup", 2)
	var service: Variant = _new_service()
	if service == null or not _require_method(service, "cleanup_staging"):
		return
	var staging_root_absolute := ProjectSettings.globalize_path("user://video_sprite_workspace")
	for invalid: String in [staging_root_absolute, staging_root_absolute + "-sibling/cache"]:
		var rejected: Dictionary = service.cleanup_staging({"staging_directory": invalid})
		assert_array(rejected.get("errors", PackedStringArray())).is_not_empty()
	assert_bool("path_is_link" in service).is_true()
	service.path_is_link = func(path: String) -> bool: return path.ends_with("cleanup")
	var linked: Dictionary = service.cleanup_staging({
		"staging_directory": ProjectSettings.globalize_path(fixture["root"]),
	})
	assert_str("\n".join(linked.get("errors", PackedStringArray()))).contains("link")
	assert_bool(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(fixture["root"]))).is_true()
	service.path_is_link = Callable()
	var cleaned: Dictionary = service.cleanup_staging({
		"staging_directory": ProjectSettings.globalize_path(fixture["root"]),
	})
	assert_array(cleaned.get("errors", PackedStringArray())).is_empty()
	assert_str(cleaned.get("removed_path", "")).is_equal(ProjectSettings.globalize_path(fixture["root"]).simplify_path())
	assert_int(cleaned.get("removed_entries", 0)).is_greater(0)
	assert_bool(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(fixture["root"]))).is_false()


func test_cleanup_refuses_a_cache_owned_by_an_active_job_but_allows_terminal_jobs() -> void:
	var fixture := _write_external_fixture("active", 2)
	var service: Variant = _new_service()
	if service == null or not _require_method(service, "cleanup_staging"):
		return
	var job_script := load(JOB_SERVICE_PATH)
	var jobs: Variant = job_script.new()
	assert_bool("job_service" in service).is_true()
	service.job_service = jobs
	var receipt_path := STAGING_ROOT.path_join("active-receipt.json")
	_write_json(receipt_path, {
		"job_id": "active-job", "state": "running",
		"output_directory": ProjectSettings.globalize_path(fixture["root"]),
	})
	jobs.track_job("active-job", receipt_path, 123)
	var active: Dictionary = service.cleanup_staging({
		"staging_directory": ProjectSettings.globalize_path(fixture["root"]),
	})
	assert_str("\n".join(active.get("errors", PackedStringArray()))).contains("active job")
	assert_bool(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(fixture["root"]))).is_true()
	_write_json(receipt_path, {
		"job_id": "active-job", "state": "complete",
		"output_directory": ProjectSettings.globalize_path(fixture["root"]),
	})
	var terminal: Dictionary = service.cleanup_staging({
		"staging_directory": ProjectSettings.globalize_path(fixture["root"]),
	})
	assert_array(terminal.get("errors", PackedStringArray())).is_empty()


func _new_service() -> Variant:
	var script := load(SERVICE_PATH)
	assert_object(script).is_not_null()
	if script == null:
		return null
	var service: Variant = script.new()
	for method: String in [
		"save_curation", "load_curation", "validate_selection", "validate_external_manifest",
	]:
		assert_bool(service.has_method(method)).is_true()
	return service


func _require_method(service: Variant, method: String) -> bool:
	assert_bool(service.has_method(method)).is_true()
	return service.has_method(method)


func _promotion_params(manifest_path: String, take: String) -> Dictionary:
	return {
		"manifest_path": manifest_path,
		"selection": [1, 0, 1],
		"fps": 10.0,
		"loop": false,
		"config_path": CONFIG_PATH,
		"character_id": CHARACTER_ID,
		"action": "dash",
		"take": take,
	}


func _write_character_config() -> void:
	_write_json(CONFIG_PATH, {
		"schema_version": 1,
		"character_id": CHARACTER_ID,
		"expected_source_frame_count": 2,
		"clip_root": "res://tools/sprites/legacy-unused",
		"authoring_path": AUTHORING_PATH,
		"runtime_root": RUNTIME_ROOT,
		"required_actions": ["dash"],
		"actions": {"dash": {"loop": false, "preferred_take": "", "takes": []}},
	})


func _files_below(path: String) -> Array[String]:
	var result: Array[String] = []
	var directory := DirAccess.open(path)
	if directory == null:
		return result
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if not directory.current_is_dir():
			result.append(entry)
		entry = directory.get_next()
	directory.list_dir_end()
	return result


func _assert_manifest_error(service: Variant, manifest_path: String, manifest: Dictionary, expected: String) -> void:
	_write_json(manifest_path, manifest)
	var result: Dictionary = service.validate_external_manifest(manifest_path)
	assert_str("\n".join(result.get("errors", PackedStringArray()))).contains(expected)


func _write_external_fixture(name: String, frame_count: int) -> Dictionary:
	var root := STAGING_ROOT.path_join(name)
	var frames_root := root.path_join("frames")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(frames_root))
	var video_path := root.path_join("source.mp4")
	_write_text(video_path, "video-%s" % name)
	var source_frames: Array = []
	var rects: Array = []
	var durations: Array = []
	var atlas := Image.create(frame_count * 256, 256, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0, 0, 0, 0))
	for index in frame_count:
		var frame := Image.create(256, 256, false, Image.FORMAT_RGBA8)
		frame.fill(Color8(40 + index * 30, 80 + index * 20, 120 + index * 10, 255))
		var png_path := frames_root.path_join("frame_%03d.png" % (index + 1))
		assert_int(frame.save_png(ProjectSettings.globalize_path(png_path))).is_equal(OK)
		atlas.blit_rect(frame, Rect2i(0, 0, 256, 256), Vector2i(index * 256, 0))
		var rect := {"x": index * 256, "y": 0, "w": 256, "h": 256}
		rects.append(rect)
		durations.append(40.0)
		source_frames.append({
			"index": index,
			"source_frame": index + 1,
			"timestamp_seconds": index * 0.04,
			"duration_ms": 40.0,
			"png": "frames/frame_%03d.png" % (index + 1),
			"sha256": FileAccess.get_sha256(png_path),
			"rect": rect.duplicate(true),
		})
	assert_int(atlas.save_png(ProjectSettings.globalize_path(root.path_join("atlas.png")))).is_equal(OK)
	var manifest := {
		"schema_version": 1,
		"kind": "pixelmotion-video-sprite-library",
		"engine": "pixelmotion2d-cutout+sprite-gen-pixel-unfake",
		"clip_id": name.replace("-", "_"),
		"game_input": "atlas.png",
		"degraded_static_fallback": false,
		"source": {
			"absolute_path": ProjectSettings.globalize_path(video_path),
			"sha256": FileAccess.get_sha256(video_path),
			"frame_count": frame_count,
			"fps": {"numerator": 25, "denominator": 1, "value": 25.0},
		},
		"cell": {"width": 256, "height": 256, "safe_margin": 24},
		"root": {"x": 128, "y": 232},
		"animation": {"rows": {"source_all": {
			"frames": frame_count,
			"fps": 25.0,
			"durations_ms": durations,
			"loop": true,
		}}},
		"frame_layout": {
			"sheetWidth": frame_count * 256,
			"sheetHeight": 256,
			"cellWidth": 256,
			"cellHeight": 256,
			"rows": {"source_all": rects},
		},
		"source_frames": source_frames,
	}
	var manifest_path := root.path_join("manifest.json")
	_write_json(manifest_path, manifest)
	return {"root": root, "manifest_path": manifest_path, "video_path": video_path}


func _resolve_external(manifest_path: String, relative_path: String) -> String:
	return ProjectSettings.globalize_path(manifest_path.get_base_dir().path_join(relative_path))


func _read_json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path)) as Dictionary


func _write_json(path: String, value: Dictionary) -> void:
	_write_text(path, JSON.stringify(value, "  ") + "\n")


func _write_text(path: String, content: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	assert_object(file).is_not_null()
	file.store_string(content)
	file.close()


func _remove_tree(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	if not absolute.contains("video_sprite_workspace/task-2-gdunit"):
		fail("refusing unsafe fixture cleanup: %s" % absolute)
		return
	_remove_absolute_tree(absolute)


func _remove_project_tree(path: String) -> void:
	if path != OUTPUT_ROOT and path != REPORT_ROOT:
		fail("refusing unsafe project fixture cleanup: %s" % path)
		return
	_remove_absolute_tree(ProjectSettings.globalize_path(path))


func _remove_absolute_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		var child := path.path_join(entry)
		if directory.current_is_dir():
			_remove_absolute_tree(child)
		else:
			DirAccess.remove_absolute(child)
		entry = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(path)
