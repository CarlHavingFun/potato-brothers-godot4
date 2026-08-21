class_name VideoSpriteCurationService
extends RefCounted


const JobService = preload("res://tools/video_sprites/video_sprite_job_service.gd")
const Importer = preload("res://tools/video_sprites/video_sprite_manifest_importer.gd")
const SIDECAR_NAME := "godot-curation.json"
const DEFAULT_CONFIG := "res://tools/video_sprites/niko_character_sources.json"
const PROMOTION_ROOT := "res://tools/sprites"
const STATE := "source_all"
const CELL_SIZE := Vector2i(256, 256)
const VALID_ENGINES := [
	"pixelmotion2d-video-library",
	"pixelmotion2d-cutout+sprite-gen-pixel-unfake",
]

var config_replacer: Callable = Callable()
var config_restorer: Callable = Callable()
var authoring_installer: Callable = Callable()
var output_mutator: Callable = Callable()
var output_cleaner: Callable = Callable()
var directory_maker: Callable = Callable()
var path_is_link: Callable = Callable()
var job_service: Variant = JobService.new()


func save_curation(params: Dictionary) -> Dictionary:
	var validated := validate_selection(params)
	var errors := validated.get("errors", PackedStringArray()) as PackedStringArray
	if not errors.is_empty():
		return {"errors": errors}
	var manifest_path := str(validated["manifest_path"])
	var manifest := validated["manifest"] as Dictionary
	var source := manifest.get("source", {}) as Dictionary
	var state := {
		"schema_version": 1,
		"source_manifest_path": manifest_path,
		"source_manifest_sha256": FileAccess.get_sha256(manifest_path),
		"source_video_sha256": _current_video_hash(source),
		"selection": (validated["selection"] as Array).duplicate(),
		"fps": float(validated["fps"]),
		"loop": bool(validated["loop"]),
		"character_id": str(params.get("character_id", "")),
		"action": str(params.get("action", "")),
		"take": str(params.get("take", "")),
		"updated_at_unix": Time.get_unix_time_from_system(),
	}
	var curation_path := manifest_path.get_base_dir().path_join(SIDECAR_NAME)
	if not _write_json_replacing(curation_path, state):
		return {"errors": PackedStringArray(["could not save curation sidecar: %s" % curation_path])}
	state["curation_path"] = curation_path
	state["errors"] = PackedStringArray()
	return state


func load_curation(params: Dictionary) -> Dictionary:
	var manifest_path := str(params.get("manifest_path", ""))
	var path_error := _validate_external_manifest_path(manifest_path)
	if not path_error.is_empty():
		return {"errors": PackedStringArray([path_error])}
	manifest_path = _absolute_path(manifest_path)
	var curation_path := str(params.get(
		"curation_path", manifest_path.get_base_dir().path_join(SIDECAR_NAME)
	))
	curation_path = _absolute_path(curation_path)
	if curation_path != manifest_path.get_base_dir().path_join(SIDECAR_NAME):
		return {"errors": PackedStringArray(["curation_path must be godot-curation.json next to the manifest"])}
	var parsed := _parse_json_file(curation_path, "curation sidecar")
	var errors := parsed.get("errors", PackedStringArray()) as PackedStringArray
	if not errors.is_empty():
		return {"errors": errors}
	var state := parsed["value"] as Dictionary
	if int(state.get("schema_version", 0)) != 1:
		return {"errors": PackedStringArray(["curation sidecar schema_version must be 1"])}
	if _absolute_path(str(state.get("source_manifest_path", ""))) != manifest_path:
		return {"errors": PackedStringArray(["curation sidecar source manifest path does not match"])}
	if str(state.get("source_manifest_sha256", "")) != FileAccess.get_sha256(manifest_path):
		return {"errors": PackedStringArray(["curation sidecar manifest hash is stale"])}
	var raw_manifest := _parse_json_file(manifest_path, "external manifest")
	errors = raw_manifest.get("errors", PackedStringArray()) as PackedStringArray
	if not errors.is_empty():
		return {"errors": errors}
	var raw_source := (raw_manifest["value"] as Dictionary).get("source", {}) as Dictionary
	var stored_video_hash := str(state.get("source_video_sha256", ""))
	if not stored_video_hash.is_empty() and stored_video_hash != _current_video_hash(raw_source):
		return {"errors": PackedStringArray(["curation sidecar video hash is stale"])}
	var manifest_result := validate_external_manifest(manifest_path)
	errors = manifest_result.get("errors", PackedStringArray()) as PackedStringArray
	if not errors.is_empty():
		return {"errors": errors}
	var manifest := manifest_result["manifest"] as Dictionary
	var stored_selection: Variant = _json_integer_array(state.get("selection", null))
	var selection_result := _validate_selection_values(
		stored_selection,
		state.get("fps", null),
		state.get("loop", null),
		int((manifest["source"] as Dictionary)["frame_count"])
	)
	errors = selection_result.get("errors", PackedStringArray()) as PackedStringArray
	if not errors.is_empty():
		return {"errors": errors}
	state["selection"] = (selection_result["selection"] as Array).duplicate()
	state["fps"] = float(selection_result["fps"])
	state["loop"] = bool(selection_result["loop"])
	state["manifest_path"] = manifest_path
	state["curation_path"] = curation_path
	state["errors"] = PackedStringArray()
	return state


func validate_selection(params: Dictionary) -> Dictionary:
	var manifest_result := validate_external_manifest(str(params.get("manifest_path", "")))
	var errors := manifest_result.get("errors", PackedStringArray()) as PackedStringArray
	if not errors.is_empty():
		return {"errors": errors}
	var manifest := manifest_result["manifest"] as Dictionary
	var selection_result := _validate_selection_values(
		params.get("selection", null),
		params.get("fps", null),
		params.get("loop", null),
		int((manifest["source"] as Dictionary)["frame_count"])
	)
	errors = selection_result.get("errors", PackedStringArray()) as PackedStringArray
	if not errors.is_empty():
		return {"errors": errors}
	selection_result["manifest"] = manifest
	selection_result["manifest_path"] = str(manifest_result["manifest_path"])
	return selection_result


func validate_external_manifest(path: String) -> Dictionary:
	var path_error := _validate_external_manifest_path(path)
	if not path_error.is_empty():
		return {"errors": PackedStringArray([path_error])}
	var manifest_path := _absolute_path(path)
	var parsed := _parse_json_file(manifest_path, "external manifest")
	var errors := parsed.get("errors", PackedStringArray()) as PackedStringArray
	if not errors.is_empty():
		return {"errors": errors}
	var manifest := parsed["value"] as Dictionary
	_validate_manifest_structure(manifest, manifest_path, errors)
	return {
		"manifest": manifest,
		"manifest_path": manifest_path,
		"manifest_sha256": FileAccess.get_sha256(manifest_path),
		"errors": errors,
	}


func preview_promotion(params: Dictionary) -> Dictionary:
	var context := _promotion_context(params)
	var errors := context.get("errors", PackedStringArray()) as PackedStringArray
	if not errors.is_empty():
		return {"errors": errors}
	var config := context["config"] as Dictionary
	var character_id := str(context["character_id"])
	var action := str(context["action"])
	var action_data := ((config["actions"] as Dictionary)[action] as Dictionary)
	var base_take := _sanitize_identifier(str(params.get("take", "take")), "take")
	var occupied: Dictionary = {}
	for take_value: Variant in action_data.get("takes", []) as Array:
		if take_value is Dictionary:
			occupied[str((take_value as Dictionary).get("name", ""))] = true
	var action_root := PROMOTION_ROOT.path_join(character_id).path_join(action)
	var directory := DirAccess.open(action_root)
	if directory != null:
		directory.list_dir_begin()
		var entry := directory.get_next()
		while not entry.is_empty():
			if directory.current_is_dir():
				occupied[entry] = true
			entry = directory.get_next()
		directory.list_dir_end()
	var take := base_take
	var suffix := 2
	while occupied.has(take):
		take = "%s_%d" % [base_take, suffix]
		suffix += 1
	return {
		"errors": PackedStringArray(),
		"character_id": character_id,
		"action": action,
		"take": take,
		"clip_id": "%s_%s_%s" % [character_id, action, take],
		"output_path": action_root.path_join(take),
		"config_path": str(context["config_path"]),
	}


func promote_selection(params: Dictionary) -> Dictionary:
	var validated := validate_selection(params)
	var errors := validated.get("errors", PackedStringArray()) as PackedStringArray
	if not errors.is_empty():
		return {"errors": errors}
	var context := _promotion_context(params)
	errors = context.get("errors", PackedStringArray()) as PackedStringArray
	if not errors.is_empty():
		return {"errors": errors}
	var preview := preview_promotion(params)
	errors = preview.get("errors", PackedStringArray()) as PackedStringArray
	if not errors.is_empty():
		return {"errors": errors}
	var resolved_requested := str(params.get("resolved_take", ""))
	if not resolved_requested.is_empty():
		var exact_take := _sanitize_identifier(resolved_requested, "take")
		var exact_path := PROMOTION_ROOT.path_join(str(context["character_id"])).path_join(str(context["action"])).path_join(exact_take)
		if exact_take != str(preview["take"]) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(exact_path)):
			return {"errors": PackedStringArray(["resolved take already exists: %s" % exact_take])}
		preview["take"] = exact_take
		preview["clip_id"] = "%s_%s_%s" % [context["character_id"], context["action"], exact_take]
		preview["output_path"] = exact_path

	var output_path := str(preview["output_path"])
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output_path)):
		return {"errors": PackedStringArray(["take output already exists: %s" % output_path])}
	var frames_directory := ProjectSettings.globalize_path(output_path.path_join("frames"))
	var directory_error: int = (
		int(directory_maker.call(frames_directory))
		if directory_maker.is_valid()
		else DirAccess.make_dir_recursive_absolute(frames_directory)
	)
	if directory_error != OK:
		var mkdir_errors := PackedStringArray(["could not create promoted take directory: %s" % error_string(directory_error)])
		return (
			_failure_after_output(mkdir_errors, output_path)
			if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output_path))
			else {"errors": mkdir_errors}
		)
	var emitted := _emit_promoted_take(
		validated["manifest"] as Dictionary,
		str(validated["manifest_path"]),
		validated["selection"] as Array,
		float(validated["fps"]),
		bool(validated["loop"]),
		preview
	)
	errors = emitted.get("errors", PackedStringArray()) as PackedStringArray
	if not errors.is_empty():
		return _failure_after_output(errors, output_path)
	if output_mutator.is_valid():
		output_mutator.call(emitted)
	var output_validation := _validate_promoted_output(emitted)
	errors = output_validation.get("errors", PackedStringArray()) as PackedStringArray
	if not errors.is_empty():
		return _failure_after_output(errors, output_path)

	var config := (context["config"] as Dictionary).duplicate(true)
	var action_data := ((config["actions"] as Dictionary)[str(context["action"])] as Dictionary)
	var takes := action_data.get("takes", []) as Array
	takes.append({
		"name": str(preview["take"]),
		"clip_id": str(preview["clip_id"]),
		"resource_path": str(emitted["resource_path"]),
		"manifest_path": str(emitted["manifest_path"]),
		"loop": bool(validated["loop"]),
	})
	action_data["takes"] = takes
	var config_errors := Importer.validate_character_config(config)
	if not config_errors.is_empty():
		return _failure_after_output(config_errors, output_path)
	var original_config := FileAccess.get_file_as_bytes(str(context["config_path"]))
	if not _commit_config(str(context["config_path"]), config):
		return _failure_after_output(PackedStringArray(["could not atomically register promoted take"]), output_path)
	var installed := _install_authoring(config)
	errors = installed.get("errors", PackedStringArray()) as PackedStringArray
	if not errors.is_empty():
		var restored := _restore_config(str(context["config_path"]), original_config)
		if not restored:
			errors.append("config rollback failed; original bytes could not be restored")
		return _failure_after_output(errors, output_path, restored)
	var result := preview.duplicate(true)
	result.merge(emitted, true)
	result["authoring_path"] = str(config.get("authoring_path", ""))
	result["preferred_take"] = str(action_data.get("preferred_take", ""))
	result["errors"] = PackedStringArray()
	return result


func set_preferred_take(params: Dictionary) -> Dictionary:
	var context := _promotion_context(params)
	var errors := context.get("errors", PackedStringArray()) as PackedStringArray
	if not errors.is_empty():
		return {"errors": errors}
	var config := (context["config"] as Dictionary).duplicate(true)
	var action := str(context["action"])
	var take := _sanitize_identifier(str(params.get("take", "")), "")
	var action_data := ((config["actions"] as Dictionary)[action] as Dictionary)
	var found := false
	for take_value: Variant in action_data.get("takes", []) as Array:
		if take_value is Dictionary and str((take_value as Dictionary).get("name", "")) == take:
			found = true
			break
	if take.is_empty() or not found:
		return {"errors": PackedStringArray(["preferred take is not registered: %s" % take])}
	action_data["preferred_take"] = take
	var original_config := FileAccess.get_file_as_bytes(str(context["config_path"]))
	if not _commit_config(str(context["config_path"]), config):
		return {"errors": PackedStringArray(["could not atomically update preferred take"])}
	var installed := _install_authoring(config)
	errors = installed.get("errors", PackedStringArray()) as PackedStringArray
	if not errors.is_empty():
		if not _restore_config(str(context["config_path"]), original_config):
			errors.append("config rollback failed; original bytes could not be restored")
		return {"errors": errors}
	return {
		"errors": PackedStringArray(), "character_id": context["character_id"],
		"action": action, "preferred_take": take,
		"authoring_path": str(config.get("authoring_path", "")),
	}


func cleanup_staging(params: Dictionary) -> Dictionary:
	var requested := str(params.get("staging_directory", ""))
	if requested.is_empty():
		return {"errors": PackedStringArray(["staging_directory is required"])}
	var candidate := _absolute_path(requested)
	var root := ProjectSettings.globalize_path(JobService.STAGING_ROOT).simplify_path()
	if candidate == root:
		return {"errors": PackedStringArray(["staging root itself cannot be removed"])}
	var path_error := JobService.validate_staging_directory(candidate, path_is_link)
	if not path_error.is_empty():
		return {"errors": PackedStringArray([path_error])}
	if not DirAccess.dir_exists_absolute(candidate):
		return {"errors": PackedStringArray(["staged cache directory not found: %s" % candidate])}
	if _tree_contains_link(candidate):
		return {"errors": PackedStringArray(["staged cache must not contain a symlink, junction, or reparse-point link"])}
	if job_service != null and job_service.has_method("is_staging_directory_active") and bool(job_service.is_staging_directory_active(candidate)):
		return {"errors": PackedStringArray(["staged cache belongs to an active job"])}
	var removed_entries := _count_tree_entries(candidate)
	if not _remove_tree_exact(candidate):
		return {"errors": PackedStringArray(["could not remove staged cache: %s" % candidate])}
	return {
		"errors": PackedStringArray(), "removed_path": candidate,
		"removed_entries": removed_entries,
	}


func _tree_contains_link(path: String) -> bool:
	var directory := DirAccess.open(path)
	if directory == null:
		return false
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		var child := path.path_join(entry)
		if directory.is_link(entry) or (path_is_link.is_valid() and bool(path_is_link.call(child))):
			directory.list_dir_end()
			return true
		if directory.current_is_dir() and _tree_contains_link(child):
			directory.list_dir_end()
			return true
		entry = directory.get_next()
	directory.list_dir_end()
	return false


static func _count_tree_entries(path: String) -> int:
	var directory := DirAccess.open(path)
	if directory == null:
		return 0
	var count := 0
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		count += 1
		if directory.current_is_dir():
			count += _count_tree_entries(path.path_join(entry))
		entry = directory.get_next()
	directory.list_dir_end()
	return count


static func _remove_tree_exact(path: String) -> bool:
	var directory := DirAccess.open(path)
	if directory == null:
		return false
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		var child := path.path_join(entry)
		var removed := _remove_tree_exact(child) if directory.current_is_dir() else DirAccess.remove_absolute(child) == OK
		if not removed:
			directory.list_dir_end()
			return false
		entry = directory.get_next()
	directory.list_dir_end()
	return DirAccess.remove_absolute(path) == OK


func _promotion_context(params: Dictionary) -> Dictionary:
	var config_path := str(params.get("config_path", DEFAULT_CONFIG)).simplify_path()
	if not config_path.begins_with("res://") or config_path.contains(".."):
		return {"errors": PackedStringArray(["config_path must resolve inside res://"])}
	var parsed := Importer.parse_character_config_file(config_path)
	var errors := parsed.get("errors", PackedStringArray()) as PackedStringArray
	if not errors.is_empty():
		return {"errors": errors}
	var config := parsed["config"] as Dictionary
	var configured_character := str(config.get("character_id", ""))
	var requested_character := str(params.get("character_id", configured_character))
	if requested_character != configured_character:
		return {"errors": PackedStringArray(["character_id does not match config: %s" % requested_character])}
	var character_id := _sanitize_identifier(configured_character, "character")
	var action := _sanitize_identifier(str(params.get("action", "")), "")
	var actions_value: Variant = config.get("actions", null)
	if action.is_empty() or not actions_value is Dictionary or not (actions_value as Dictionary).has(action):
		return {"errors": PackedStringArray(["action is not configured: %s" % action])}
	return {
		"errors": PackedStringArray(), "config": config, "config_path": config_path,
		"character_id": character_id, "action": action,
	}


func _emit_promoted_take(
	manifest: Dictionary,
	manifest_path: String,
	selection: Array,
	fps: float,
	loop: bool,
	preview: Dictionary
) -> Dictionary:
	var errors := PackedStringArray()
	var output_path := str(preview["output_path"])
	var unique_indices: Array[int] = []
	var atlas_cells: Dictionary = {}
	for value: Variant in selection:
		var source_index := int(value)
		if not atlas_cells.has(source_index):
			atlas_cells[source_index] = unique_indices.size()
			unique_indices.append(source_index)
	var atlas := Image.create(unique_indices.size() * CELL_SIZE.x, CELL_SIZE.y, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0, 0, 0, 0))
	var source_frames := manifest["source_frames"] as Array
	var copied_paths: Dictionary = {}
	for source_index: int in unique_indices:
		var source_frame := source_frames[source_index] as Dictionary
		var source_png := _resolve_staged_asset(manifest_path, str(source_frame["png"]))
		var image := Image.load_from_file(source_png)
		if image.is_empty() or Vector2i(image.get_width(), image.get_height()) != CELL_SIZE:
			errors.append("could not decode selected source frame %d" % source_index)
			continue
		var cell_index := int(atlas_cells[source_index])
		atlas.blit_rect(image, Rect2i(Vector2i.ZERO, CELL_SIZE), Vector2i(cell_index * CELL_SIZE.x, 0))
		var copied_path := output_path.path_join("frames/source_%03d.png" % (source_index + 1))
		var copy_error := DirAccess.copy_absolute(source_png, ProjectSettings.globalize_path(copied_path))
		if copy_error != OK:
			errors.append("could not copy selected source frame %d: %s" % [source_index, error_string(copy_error)])
		else:
			copied_paths[source_index] = copied_path
	if not errors.is_empty():
		return {"errors": errors}
	var atlas_path := output_path.path_join("atlas.png")
	var atlas_error := atlas.save_png(ProjectSettings.globalize_path(atlas_path))
	if atlas_error != OK:
		return {"errors": PackedStringArray(["could not write promoted atlas: %s" % error_string(atlas_error)])}

	var duration_ms := 1000.0 / fps
	var playback_rects: Array = []
	var promoted_frames: Array = []
	var durations: Array = []
	for playback_index in selection.size():
		var source_index := int(selection[playback_index])
		var source_frame := source_frames[source_index] as Dictionary
		var rect := {
			"x": int(atlas_cells[source_index]) * CELL_SIZE.x,
			"y": 0, "w": CELL_SIZE.x, "h": CELL_SIZE.y,
		}
		playback_rects.append(rect)
		durations.append(duration_ms)
		var copied_path := str(copied_paths[source_index])
		promoted_frames.append({
			"index": playback_index,
			"source_index": source_index,
			"source_frame": int(source_frame["source_frame"]),
			"timestamp_seconds": float(source_frame.get("timestamp_seconds", 0.0)),
			"source_duration_ms": float(source_frame.get("duration_ms", 0.0)),
			"duration_ms": duration_ms,
			"png": "frames/" + copied_path.get_file(),
			"sha256": FileAccess.get_sha256(copied_path),
			"rect": rect.duplicate(true),
		})
	var source := manifest["source"] as Dictionary
	var promoted_manifest := {
		"schema_version": 1,
		"kind": "pixelmotion-video-sprite-library",
		"engine": "pixelmotion2d-video-library",
		"clip_id": str(preview["clip_id"]),
		"game_input": "atlas.png",
		"degraded_static_fallback": false,
		"curated_selection": true,
		"source": {
			"frame_count": selection.size(),
			"original_frame_count": int(source.get("frame_count", 0)),
			"sha256": str(source.get("sha256", "")),
			"fps": {"numerator": int(round(fps * 1000.0)), "denominator": 1000, "value": fps},
		},
		"cell": {"width": 256, "height": 256, "safe_margin": 24},
		"root": (manifest.get("root", {"x": 128, "y": 232}) as Dictionary).duplicate(true),
		"animation": {"rows": {STATE: {
			"frames": selection.size(), "fps": fps, "durations_ms": durations, "loop": loop,
		}}},
		"frame_layout": {
			"sheetWidth": unique_indices.size() * CELL_SIZE.x,
			"sheetHeight": CELL_SIZE.y,
			"cellWidth": CELL_SIZE.x,
			"cellHeight": CELL_SIZE.y,
			"rows": {STATE: playback_rects},
		},
		"source_frames": promoted_frames,
	}
	var promoted_manifest_path := output_path.path_join("manifest.json")
	if not _write_json_replacing(promoted_manifest_path, promoted_manifest):
		return {"errors": PackedStringArray(["could not write promoted manifest"])}
	var provenance_path := output_path.path_join("provenance.json")
	var provenance := {
		"schema_version": 1,
		"source_manifest_path": manifest_path,
		"source_manifest_sha256": FileAccess.get_sha256(manifest_path),
		"source_video_sha256": str(source.get("sha256", "")),
		"ordered_source_indices": selection.duplicate(),
		"unique_source_indices": unique_indices,
		"fps": fps,
		"loop": loop,
		"character_id": str(preview.get("character_id", "")),
		"action": str(preview.get("action", "")),
		"take": str(preview.get("take", "")),
		"promoted_at_unix": Time.get_unix_time_from_system(),
	}
	if not _write_json_replacing(provenance_path, provenance):
		return {"errors": PackedStringArray(["could not write promoted provenance"])}

	var texture := ImageTexture.create_from_image(atlas)
	var sprite_frames := SpriteFrames.new()
	sprite_frames.remove_animation(&"default")
	sprite_frames.add_animation(&"source_all")
	sprite_frames.set_animation_speed(&"source_all", fps)
	sprite_frames.set_animation_loop(&"source_all", loop)
	for rect_value: Variant in playback_rects:
		var rect := rect_value as Dictionary
		var atlas_frame := AtlasTexture.new()
		atlas_frame.atlas = texture
		atlas_frame.region = Rect2i(int(rect["x"]), int(rect["y"]), int(rect["w"]), int(rect["h"]))
		sprite_frames.add_frame(&"source_all", atlas_frame, 1.0)
	var resource_path := output_path.path_join("selected_frames.tres")
	var save_error := ResourceSaver.save(sprite_frames, resource_path)
	if save_error != OK:
		return {"errors": PackedStringArray(["could not save selected SpriteFrames: %s" % error_string(save_error)])}
	var preview_path := output_path.path_join("preview.tscn")
	var preview_source := """[gd_scene load_steps=2 format=3]

[ext_resource type="SpriteFrames" path="%s" id="1_frames"]

[node name="CuratedVideoSpritePreview" type="Node2D"]

[node name="Sprite" type="AnimatedSprite2D" parent="."]
texture_filter = 1
sprite_frames = ExtResource("1_frames")
animation = &"source_all"
autoplay = "source_all"
centered = false
""" % resource_path
	if not _write_text_replacing(preview_path, preview_source):
		return {"errors": PackedStringArray(["could not write promoted preview"])}
	return {
		"errors": PackedStringArray(),
		"atlas_path": atlas_path,
		"manifest_path": promoted_manifest_path,
		"provenance_path": provenance_path,
		"resource_path": resource_path,
		"preview_path": preview_path,
		"unique_frame_count": unique_indices.size(),
		"playback_frame_count": selection.size(),
		"selection": selection.duplicate(),
		"fps": fps,
		"loop": loop,
		"source_manifest": manifest.duplicate(true),
		"source_manifest_path": manifest_path,
		"character_id": preview.get("character_id", ""),
		"action": preview.get("action", ""),
		"output_path": output_path,
		"take": preview["take"],
	}


func _validate_promoted_output(emitted: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	for key: String in ["atlas_path", "manifest_path", "provenance_path", "resource_path", "preview_path"]:
		if not FileAccess.file_exists(str(emitted.get(key, ""))):
			errors.append("promoted output is missing %s" % key)
	var atlas := Image.load_from_file(ProjectSettings.globalize_path(str(emitted.get("atlas_path", ""))))
	if atlas.is_empty() or atlas.get_height() != CELL_SIZE.y or atlas.get_width() != int(emitted.get("unique_frame_count", 0)) * CELL_SIZE.x:
		errors.append("promoted atlas dimensions are invalid")
	var manifest_result := _parse_json_file(str(emitted.get("manifest_path", "")), "promoted manifest")
	var provenance_result := _parse_json_file(str(emitted.get("provenance_path", "")), "promoted provenance")
	errors.append_array(manifest_result.get("errors", PackedStringArray()))
	errors.append_array(provenance_result.get("errors", PackedStringArray()))
	if (manifest_result.get("value", null) is Dictionary and provenance_result.get("value", null) is Dictionary):
		var manifest := manifest_result["value"] as Dictionary
		var provenance := provenance_result["value"] as Dictionary
		var expected_selection := emitted.get("selection", []) as Array
		var original := emitted.get("source_manifest", {}) as Dictionary
		var original_frames := original.get("source_frames", []) as Array
		var original_source := original.get("source", {}) as Dictionary
		if _json_integer_array(provenance.get("ordered_source_indices", null)) != expected_selection:
			errors.append("promoted provenance ordered selection failed readback")
		var expected_unique: Array = []
		for selected: Variant in expected_selection:
			if selected not in expected_unique:
				expected_unique.append(selected)
		if _json_integer_array(provenance.get("unique_source_indices", null)) != expected_unique:
			errors.append("promoted provenance unique source indices failed readback")
		if str(provenance.get("source_manifest_sha256", "")) != FileAccess.get_sha256(str(emitted.get("source_manifest_path", ""))) or str(provenance.get("source_video_sha256", "")) != str(original_source.get("sha256", "")):
			errors.append("promoted provenance source hashes failed readback")
		if not is_equal_approx(float(provenance.get("fps", 0.0)), float(emitted.get("fps", 0.0))) or bool(provenance.get("loop", false)) != bool(emitted.get("loop", false)):
			errors.append("promoted provenance timing failed readback")
		for key: String in ["character_id", "action", "take"]:
			if str(provenance.get(key, "")) != str(emitted.get(key, "")):
				errors.append("promoted provenance intent failed readback")
		var row := ((manifest.get("animation", {}) as Dictionary).get("rows", {}) as Dictionary).get(STATE, {}) as Dictionary
		if not is_equal_approx(float(row.get("fps", 0.0)), float(emitted.get("fps", 0.0))) or bool(row.get("loop", false)) != bool(emitted.get("loop", false)):
			errors.append("promoted manifest FPS/loop failed readback")
		var source_frames := manifest.get("source_frames", []) as Array
		var rects := (((manifest.get("frame_layout", {}) as Dictionary).get("rows", {}) as Dictionary).get(STATE, []) as Array)
		var durations := row.get("durations_ms", []) as Array
		if int(row.get("frames", 0)) != expected_selection.size() or durations.size() != expected_selection.size() or rects.size() != expected_selection.size():
			errors.append("promoted animation/layout counts failed readback")
		for duration: Variant in durations:
			if not is_equal_approx(float(duration), 1000.0 / float(emitted.get("fps", 1.0))):
				errors.append("promoted animation durations failed readback")
		if source_frames.size() != expected_selection.size():
			errors.append("promoted manifest frame count failed readback")
		var seen_rects: Dictionary = {}
		for playback_index in source_frames.size():
			var frame_value: Variant = source_frames[playback_index]
			if not frame_value is Dictionary:
				errors.append("promoted manifest frame failed readback")
				continue
			var frame := frame_value as Dictionary
			if playback_index >= rects.size() or frame.get("rect", null) != rects[playback_index]:
				errors.append("promoted manifest/frame_layout rect failed readback")
			var source_index := int(expected_selection[playback_index]) if playback_index < expected_selection.size() else -1
			if source_index < 0 or source_index >= original_frames.size():
				errors.append("promoted manifest source index failed readback")
				continue
			var source_frame := original_frames[source_index] as Dictionary
			if int(frame.get("source_index", -1)) != source_index or int(frame.get("source_frame", 0)) != int(source_frame.get("source_frame", 0)) or not is_equal_approx(float(frame.get("timestamp_seconds", -1.0)), float(source_frame.get("timestamp_seconds", -2.0))) or str(frame.get("sha256", "")) != str(source_frame.get("sha256", "")):
				errors.append("promoted manifest source provenance failed readback")
			if not is_equal_approx(float(frame.get("source_duration_ms", 0.0)), float(source_frame.get("duration_ms", -1.0))) or not is_equal_approx(float(frame.get("duration_ms", 0.0)), 1000.0 / float(emitted.get("fps", 1.0))):
				errors.append("promoted manifest duration failed readback")
			var png_path := str(emitted.get("output_path", "")).path_join(str(frame.get("png", "")))
			if not FileAccess.file_exists(png_path) or FileAccess.get_sha256(png_path) != str(frame.get("sha256", "")):
				errors.append("promoted PNG hash failed readback")
			if not frame.get("rect", null) is Dictionary or Vector2i(int((frame["rect"] as Dictionary).get("w", 0)), int((frame["rect"] as Dictionary).get("h", 0))) != CELL_SIZE:
				errors.append("promoted manifest region failed readback")
			else:
				var rv := frame["rect"] as Dictionary
				var rect := Rect2i(int(rv.get("x", -1)), int(rv.get("y", -1)), int(rv.get("w", 0)), int(rv.get("h", 0)))
				if rect.position.x < 0 or rect.position.y < 0 or rect.end.x > atlas.get_width() or rect.end.y > atlas.get_height():
					errors.append("promoted manifest region out of bounds")
				else:
					var selected_png := Image.load_from_file(ProjectSettings.globalize_path(png_path))
					if selected_png.is_empty() or atlas.get_region(rect).get_data() != selected_png.get_data():
						errors.append("promoted atlas rect pixels do not match selected PNG")
			if seen_rects.has(source_index) and seen_rects[source_index] != frame["rect"]:
				errors.append("promoted manifest unique mapping failed readback")
			else:
				seen_rects[source_index] = frame["rect"]
	var frames := ResourceLoader.load(
		str(emitted.get("resource_path", "")), "SpriteFrames", ResourceLoader.CACHE_MODE_REPLACE
	) as SpriteFrames
	if frames == null or not frames.has_animation(&"source_all") or frames.get_frame_count(&"source_all") != int(emitted.get("playback_frame_count", 0)):
		errors.append("promoted selected SpriteFrames failed validation")
	elif not is_equal_approx(frames.get_animation_speed(&"source_all"), float(emitted.get("fps", 0.0))) or frames.get_animation_loop(&"source_all") != bool(emitted.get("loop", false)):
		errors.append("promoted selected SpriteFrames timing failed validation")
	else:
		var manifest := manifest_result.get("value", {}) as Dictionary
		var rects := (((manifest.get("frame_layout", {}) as Dictionary).get("rows", {}) as Dictionary).get(STATE, []) as Array)
		var atlas_data := atlas.get_data() if not atlas.is_empty() else PackedByteArray()
		for index in frames.get_frame_count(&"source_all"):
			var texture := frames.get_frame_texture(&"source_all", index)
			if not texture is AtlasTexture or index >= rects.size():
				errors.append("promoted selected SpriteFrames region failed validation")
				continue
			var expected_rect_value := rects[index] as Dictionary
			var expected_rect := Rect2(int(expected_rect_value["x"]), int(expected_rect_value["y"]), int(expected_rect_value["w"]), int(expected_rect_value["h"]))
			var atlas_texture := texture as AtlasTexture
			if atlas_texture.region != expected_rect or atlas_texture.atlas == null or atlas_texture.atlas.get_image().get_data() != atlas_data:
				errors.append("promoted selected SpriteFrames region/atlas failed validation")
			if not is_equal_approx(frames.get_frame_duration(&"source_all", index), 1.0):
				errors.append("promoted selected SpriteFrames duration failed validation")
	return {"errors": errors}


func _commit_config(config_path: String, config: Dictionary) -> bool:
	var absolute := ProjectSettings.globalize_path(config_path)
	var temporary := "%s.%d.tmp" % [absolute, Time.get_ticks_usec()]
	if not _write_json_new_absolute(temporary, config):
		return false
	var replaced := (
		bool(config_replacer.call(temporary, absolute))
		if config_replacer.is_valid()
		else _replace_file_direct(temporary, absolute)
	)
	if FileAccess.file_exists(temporary):
		DirAccess.remove_absolute(temporary)
	return replaced


static func _replace_file_direct(temporary: String, destination: String) -> bool:
	return DirAccess.rename_absolute(temporary, destination) == OK


func _restore_config(config_path: String, bytes: PackedByteArray) -> bool:
	if config_restorer.is_valid():
		return bool(config_restorer.call(config_path, bytes))
	var absolute := ProjectSettings.globalize_path(config_path)
	var temporary := "%s.%d.restore" % [absolute, Time.get_ticks_usec()]
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.close()
	return _replace_file_direct(temporary, absolute)


func _install_authoring(config: Dictionary) -> Dictionary:
	var clip_root := str(config.get("clip_root", PROMOTION_ROOT))
	var authoring_path := str(config.get("authoring_path", ""))
	return (
		authoring_installer.call(config, clip_root, authoring_path) as Dictionary
		if authoring_installer.is_valid()
		else Importer.install_character_library(config, clip_root, authoring_path)
	)


func _discard_promoted_output(path: String) -> bool:
	if output_cleaner.is_valid():
		return bool(output_cleaner.call(path))
	var absolute := ProjectSettings.globalize_path(path).simplify_path()
	var root := ProjectSettings.globalize_path(PROMOTION_ROOT).simplify_path()
	var compared := absolute.to_lower() if OS.get_name() == "Windows" else absolute
	var compared_root := root.to_lower() if OS.get_name() == "Windows" else root
	if not compared.begins_with(compared_root.trim_suffix("/") + "/"):
		return false
	return not DirAccess.dir_exists_absolute(absolute) or _remove_tree_exact(absolute)


func _failure_after_output(errors: PackedStringArray, output_path: String, cleanup_allowed := true) -> Dictionary:
	var result := {"errors": errors, "output_path": output_path}
	if not cleanup_allowed:
		result["output_retained"] = true
		return result
	if not _discard_promoted_output(output_path):
		errors.append("promoted output cleanup failed: %s" % output_path)
		result["cleanup_failed"] = true
	return result


static func _write_json_new_absolute(path: String, value: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "  ") + "\n")
	file.close()
	return true


static func _write_text_replacing(path: String, content: String) -> bool:
	var absolute := ProjectSettings.globalize_path(path)
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(content)
	file.close()
	return true


static func _sanitize_identifier(value: String, fallback: String) -> String:
	var result := ""
	var previous_separator := false
	for index in value.length():
		var character := value.substr(index, 1).to_lower()
		var allowed := character in "abcdefghijklmnopqrstuvwxyz0123456789"
		if allowed:
			result += character
			previous_separator = false
		elif not previous_separator and not result.is_empty():
			result += "_"
			previous_separator = true
	result = result.trim_suffix("_")
	if result.is_empty():
		result = fallback
	if not result.is_empty() and result.substr(0, 1) in "0123456789":
		result = "take_" + result
	return result


static func _validate_selection_values(
	selection_value: Variant,
	fps_value: Variant,
	loop_value: Variant,
	frame_count: int
) -> Dictionary:
	var errors := PackedStringArray()
	var selection: Array = []
	if not selection_value is Array or (selection_value as Array).is_empty():
		errors.append("selection must be a non-empty array of source frame indices")
	elif selection_value is Array:
		for value: Variant in selection_value as Array:
			if value is bool or not value is int:
				errors.append("selection entries must be integers")
				continue
			var index := int(value)
			if index < 0 or index >= frame_count:
				errors.append("selection index %d is outside source frame range 0..%d" % [index, frame_count - 1])
			else:
				selection.append(index)
	if fps_value is bool or not (fps_value is int or fps_value is float):
		errors.append("fps must be a positive number")
	elif float(fps_value) <= 0.0 or not is_finite(float(fps_value)):
		errors.append("fps must be a positive finite number")
	if not loop_value is bool:
		errors.append("loop must be a bool")
	return {
		"selection": selection,
		"fps": float(fps_value) if fps_value is int or fps_value is float else 0.0,
		"loop": bool(loop_value) if loop_value is bool else false,
		"errors": errors,
	}


func _validate_manifest_structure(
	manifest: Dictionary,
	manifest_path: String,
	errors: PackedStringArray
) -> void:
	if str(manifest.get("kind", "")) != "pixelmotion-video-sprite-library":
		errors.append("kind must be pixelmotion-video-sprite-library")
	if str(manifest.get("engine", "")) not in VALID_ENGINES:
		errors.append("external manifest engine is unsupported")
	if bool(manifest.get("degraded_static_fallback", true)):
		errors.append("degraded/static fallback manifests cannot be curated")
	var cell_value: Variant = manifest.get("cell", null)
	if not cell_value is Dictionary or Vector2i(
		int((cell_value as Dictionary).get("width", 0)),
		int((cell_value as Dictionary).get("height", 0))
	) != CELL_SIZE:
		errors.append("external manifest cell must be 256x256")
	var source_value: Variant = manifest.get("source", null)
	if not source_value is Dictionary:
		errors.append("external manifest source must be an object")
		return
	var source := source_value as Dictionary
	var frame_count := int(source.get("frame_count", 0))
	if frame_count <= 1:
		errors.append("external source must contain more than one frame")
	var video_path := str(source.get("absolute_path", ""))
	var declared_video_hash := str(source.get("sha256", ""))
	if not video_path.is_empty() and FileAccess.file_exists(video_path):
		if not _is_sha256(declared_video_hash) or FileAccess.get_sha256(video_path) != declared_video_hash:
			errors.append("source video sha256 does not match")

	var layout_value: Variant = manifest.get("frame_layout", null)
	var rects: Array = []
	var sheet_width := 0
	var sheet_height := 0
	if not layout_value is Dictionary:
		errors.append("frame_layout must be an object")
	else:
		var layout := layout_value as Dictionary
		sheet_width = int(layout.get("sheetWidth", 0))
		sheet_height = int(layout.get("sheetHeight", 0))
		if int(layout.get("cellWidth", 0)) != CELL_SIZE.x or int(layout.get("cellHeight", 0)) != CELL_SIZE.y:
			errors.append("frame_layout cell must be 256x256")
		var rows_value: Variant = layout.get("rows", null)
		if rows_value is Dictionary and (rows_value as Dictionary).get(STATE, null) is Array:
			rects = (rows_value as Dictionary)[STATE] as Array
		else:
			errors.append("frame_layout source_all rectangles are required")
	if rects.size() != frame_count:
		errors.append("frame layout count must match source frame count")
	for index in rects.size():
		_validate_rect(rects[index], index, sheet_width, sheet_height, errors)

	var row: Dictionary = {}
	var row_durations: Array = []
	var animation_value: Variant = manifest.get("animation", null)
	if animation_value is Dictionary:
		var rows_value: Variant = (animation_value as Dictionary).get("rows", null)
		if rows_value is Dictionary and (rows_value as Dictionary).get(STATE, null) is Dictionary:
			row = (rows_value as Dictionary)[STATE] as Dictionary
	if row.is_empty():
		errors.append("animation source_all timing is required")
	else:
		if int(row.get("frames", 0)) != frame_count:
			errors.append("animation frame count must match source frame count")
		if float(row.get("fps", 0.0)) <= 0.0:
			errors.append("animation fps must be positive")
		var durations_value: Variant = row.get("durations_ms", null)
		if not durations_value is Array or (durations_value as Array).size() != frame_count:
			errors.append("animation duration count must match source frame count")
		else:
			row_durations = durations_value as Array

	var sources_value: Variant = manifest.get("source_frames", null)
	if not sources_value is Array:
		errors.append("source_frames must be an array")
		return
	var sources := sources_value as Array
	if sources.size() != frame_count:
		errors.append("source_frames count must match source frame count")
	var previous_timestamp := -1.0
	var expected_timestamp := 0.0
	for index in sources.size():
		var frame_value: Variant = sources[index]
		if not frame_value is Dictionary:
			errors.append("source frame %d must be an object" % index)
			continue
		var frame := frame_value as Dictionary
		if not _is_integer_value(frame.get("index", null)) or int(frame.get("index", -1)) != index:
			errors.append("source frame indices must be contiguous from zero")
		if not _is_integer_value(frame.get("source_frame", null)) or int(frame.get("source_frame", 0)) <= 0:
			errors.append("source frame %d source_frame must be a positive integer" % index)
		if float(frame.get("duration_ms", 0.0)) <= 0.0:
			errors.append("source frame %d duration must be positive" % index)
		elif index < row_durations.size() and absf(float(frame.get("duration_ms", 0.0)) - float(row_durations[index])) > 0.002:
			errors.append("source frame %d duration must match animation timing" % index)
		var timestamp := float(frame.get("timestamp_seconds", -1.0))
		if timestamp < 0.0 or (index > 0 and timestamp <= previous_timestamp):
			errors.append("source frame timestamp must increase at %d" % index)
		elif absf(timestamp - expected_timestamp) > 0.002:
			errors.append("source frame %d timestamp must match animation timing" % index)
		previous_timestamp = timestamp
		if index < row_durations.size():
			expected_timestamp += float(row_durations[index]) / 1000.0
		if index < rects.size() and frame.get("rect", null) != rects[index]:
			errors.append("source frame %d rectangle must match frame layout" % index)
		var png_declared := str(frame.get("png", ""))
		var png_path := _resolve_staged_asset(manifest_path, png_declared)
		if png_path.is_empty() or not FileAccess.file_exists(png_path):
			errors.append("source frame %d PNG not found inside staging or traverses a link: %s" % [index, png_declared])
		elif not _is_sha256(str(frame.get("sha256", ""))) or FileAccess.get_sha256(png_path) != str(frame.get("sha256", "")):
			errors.append("source frame %d PNG sha256 mismatch" % index)
		else:
			var image := Image.load_from_file(png_path)
			if image.is_empty() or Vector2i(image.get_width(), image.get_height()) != CELL_SIZE:
				errors.append("source frame %d PNG must decode as 256x256" % index)

	var atlas_path := _resolve_staged_asset(manifest_path, str(manifest.get("game_input", "")))
	if atlas_path.is_empty() or not FileAccess.file_exists(atlas_path):
		errors.append("source atlas not found inside staging or traverses a link")
	else:
		var atlas := Image.load_from_file(atlas_path)
		if atlas.is_empty() or Vector2i(atlas.get_width(), atlas.get_height()) != Vector2i(sheet_width, sheet_height):
			errors.append("source atlas dimensions must match frame_layout")
		else:
			atlas.convert(Image.FORMAT_RGBA8)
			for index in mini(sources.size(), rects.size()):
				if not sources[index] is Dictionary or not rects[index] is Dictionary:
					continue
				var frame := sources[index] as Dictionary
				var png_path := _resolve_staged_asset(manifest_path, str(frame.get("png", "")))
				if png_path.is_empty() or not FileAccess.file_exists(png_path):
					continue
				var image := Image.load_from_file(png_path)
				if image.is_empty():
					continue
				image.convert(Image.FORMAT_RGBA8)
				var rect_value := rects[index] as Dictionary
				var rect := Rect2i(
					int(rect_value.get("x", 0)), int(rect_value.get("y", 0)),
					int(rect_value.get("w", 0)), int(rect_value.get("h", 0))
				)
				if rect.size == CELL_SIZE and atlas.get_region(rect).get_data() != image.get_data():
					errors.append("source frame %d PNG does not match atlas rectangle" % index)


static func _validate_rect(
	value: Variant,
	index: int,
	sheet_width: int,
	sheet_height: int,
	errors: PackedStringArray
) -> void:
	if not value is Dictionary:
		errors.append("source rectangle %d must be an object" % index)
		return
	var rect_value := value as Dictionary
	for key: String in ["x", "y", "w", "h"]:
		if not _is_integer_value(rect_value.get(key, null)):
			errors.append("source rectangle %d values must be integers" % index)
			return
	var rect := Rect2i(
		int(rect_value["x"]), int(rect_value["y"]),
		int(rect_value["w"]), int(rect_value["h"])
	)
	if rect.size != CELL_SIZE or rect.position.x < 0 or rect.position.y < 0 or rect.end.x > sheet_width or rect.end.y > sheet_height:
		errors.append("source rectangle %d must be an in-bounds 256x256 cell" % index)


func _validate_external_manifest_path(path: String) -> String:
	if path.is_empty():
		return "manifest_path is required"
	var absolute := _absolute_path(path)
	if not absolute.is_absolute_path() or not FileAccess.file_exists(absolute):
		return "manifest_path must be an existing absolute/user path"
	var staging_error := JobService.validate_staging_directory(absolute, path_is_link)
	if not staging_error.is_empty():
		return staging_error.replace("staging_directory", "manifest_path")
	return ""


func _resolve_staged_asset(manifest_path: String, declared: String) -> String:
	if declared.is_empty() or declared.is_absolute_path() or declared.contains(".."):
		return ""
	var root := manifest_path.get_base_dir().simplify_path()
	var candidate := root.path_join(declared).simplify_path()
	if not candidate.begins_with(root.trim_suffix("/") + "/"):
		return ""
	if not JobService.validate_staging_directory(candidate, path_is_link).is_empty():
		return ""
	return candidate


static func _current_video_hash(source: Dictionary) -> String:
	var path := str(source.get("absolute_path", ""))
	return FileAccess.get_sha256(path) if not path.is_empty() and FileAccess.file_exists(path) else ""


static func _absolute_path(path: String) -> String:
	return ProjectSettings.globalize_path(path).simplify_path() if path.begins_with("user://") or path.begins_with("res://") else path.simplify_path()


static func _parse_json_file(path: String, label: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"errors": PackedStringArray(["%s not found: %s" % [label, path]])}
	var parser := JSON.new()
	var parse_error := parser.parse(FileAccess.get_file_as_string(path))
	if parse_error != OK:
		return {"errors": PackedStringArray(["%s JSON parse failed: %s" % [label, parser.get_error_message()]])}
	if not parser.data is Dictionary:
		return {"errors": PackedStringArray(["%s must be a JSON object" % label])}
	return {"value": parser.data as Dictionary, "errors": PackedStringArray()}


static func _write_json_replacing(path: String, value: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var temporary := "%s.%d.tmp" % [path, Time.get_ticks_usec()]
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "  ") + "\n")
	file.close()
	if FileAccess.file_exists(path) and DirAccess.remove_absolute(path) != OK:
		DirAccess.remove_absolute(temporary)
		return false
	var renamed := DirAccess.rename_absolute(temporary, path) == OK
	if not renamed and FileAccess.file_exists(temporary):
		DirAccess.remove_absolute(temporary)
	return renamed


static func _is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for index in value.length():
		if value.substr(index, 1) not in "0123456789abcdef":
			return false
	return true


static func _is_integer_value(value: Variant) -> bool:
	return value is int or (value is float and is_equal_approx(float(value), floor(float(value))))


static func _json_integer_array(value: Variant) -> Variant:
	if not value is Array:
		return value
	var result: Array = []
	for entry: Variant in value as Array:
		result.append(int(entry) if _is_integer_value(entry) else entry)
	return result
