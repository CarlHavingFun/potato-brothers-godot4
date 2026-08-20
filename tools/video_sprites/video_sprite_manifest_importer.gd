class_name VideoSpriteManifestImporter
extends RefCounted


const ENGINE := "pixelmotion2d-video-library"
const KIND := "pixelmotion-video-sprite-library"
const STATE := &"source_all"
const EXPECTED_CELL := Vector2i(256, 256)
const EXPECTED_ROOT := Vector2i(128, 232)


static func parse_manifest_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"errors": PackedStringArray(["manifest not found: %s" % path])}
	var parser := JSON.new()
	var parse_error := parser.parse(FileAccess.get_file_as_string(path))
	if parse_error != OK:
		return {"errors": PackedStringArray([
			"manifest JSON parse failed at line %d: %s" % [
				parser.get_error_line(), parser.get_error_message()
			]
		])}
	if not parser.data is Dictionary:
		return {"errors": PackedStringArray(["manifest is not a JSON object: %s" % path])}
	var manifest := parser.data as Dictionary
	manifest["_manifest_path"] = path
	return {"manifest": manifest, "errors": validate_manifest(manifest, path)}


static func validate_manifest(manifest: Dictionary, manifest_path := "") -> PackedStringArray:
	var errors := PackedStringArray()
	if manifest_path.is_empty():
		manifest_path = str(manifest.get("_manifest_path", ""))
	if str(manifest.get("kind", "")) != KIND:
		errors.append("kind must be %s" % KIND)
	if str(manifest.get("engine", "")) != ENGINE:
		errors.append("engine must be %s" % ENGINE)
	if bool(manifest.get("degraded_static_fallback", true)):
		errors.append("degraded_static_fallback must be false")
	var clip_id := str(manifest.get("clip_id", ""))
	if clip_id.is_empty() or not clip_id.is_valid_identifier():
		errors.append("clip_id must be a non-empty identifier")

	var atlas_declared := str(manifest.get("game_input", ""))
	var atlas_path := _resolve_resource_path(atlas_declared, manifest_path)
	if atlas_declared.is_empty() or not _is_project_resource_path(atlas_declared, manifest_path):
		errors.append("game_input must resolve inside res://")
	elif not FileAccess.file_exists(atlas_path):
		errors.append("atlas not found: %s" % atlas_path)

	var cell_value: Variant = manifest.get("cell", {})
	if not cell_value is Dictionary:
		errors.append("cell must be an object")
	else:
		var cell := cell_value as Dictionary
		if Vector2i(int(cell.get("width", 0)), int(cell.get("height", 0))) != EXPECTED_CELL:
			errors.append("cell must be 256x256")
	var root_value: Variant = manifest.get("root", {})
	if not root_value is Dictionary:
		errors.append("root must be an object")
	else:
		var root := root_value as Dictionary
		if Vector2i(int(root.get("x", -1)), int(root.get("y", -1))) != EXPECTED_ROOT:
			errors.append("root must be (128, 232)")

	var expected_count := _source_frame_count(manifest, errors)
	var layout := _layout_row(manifest, errors)
	var row := _animation_row(manifest, errors)
	if expected_count <= 0 or layout.is_empty() or row.is_empty():
		return errors
	var rects := layout["rects"] as Array
	if rects.size() != expected_count:
		errors.append("source_all frame layout count must match source.frame_count")
	var row_frames := int(row.get("frames", 0))
	if row_frames != expected_count:
		errors.append("source_all frames must match source.frame_count")
	var fps := float(row.get("fps", 0.0))
	if fps <= 0.0:
		errors.append("source_all fps must be positive")
	if not bool(row.get("loop", false)):
		errors.append("source_all loop must be true")
	var durations_value: Variant = row.get("durations_ms", null)
	if not durations_value is Array:
		errors.append("source_all durations_ms must be an array")
	else:
		var durations := durations_value as Array
		if durations.size() != expected_count:
			errors.append("source_all durations_ms count must match source.frame_count")
		for index in durations.size():
			if float(durations[index]) <= 0.0:
				errors.append("source_all duration %d must be positive" % index)

	var sheet_width := int(layout["sheet_width"])
	var sheet_height := int(layout["sheet_height"])
	for index in rects.size():
		_validate_rect(index, rects[index], sheet_width, sheet_height, errors)

	var sources_value: Variant = manifest.get("source_frames", null)
	if not sources_value is Array:
		errors.append("source_frames must be an array")
		return errors
	var sources := sources_value as Array
	if sources.size() != expected_count:
		errors.append("source_frames count must match source.frame_count")
	for index in sources.size():
		_validate_source_frame(index, sources[index], rects, manifest_path, errors)
	return errors


static func build_sprite_frames(
	manifest: Dictionary,
	texture_loader: Callable = Callable()
) -> Dictionary:
	var errors := validate_manifest(manifest)
	if not errors.is_empty():
		return {"errors": errors}
	var manifest_path := str(manifest.get("_manifest_path", ""))
	var atlas_path := _resolve_resource_path(str(manifest["game_input"]), manifest_path)
	var texture: Texture2D = (
		texture_loader.call(atlas_path)
		if texture_loader.is_valid()
		else ResourceLoader.load(atlas_path, "Texture2D") as Texture2D
	)
	if texture == null:
		return {"errors": PackedStringArray(["could not load atlas: %s" % atlas_path])}
	var frame_layout := manifest["frame_layout"] as Dictionary
	var expected_size := Vector2i(
		int(frame_layout["sheetWidth"]), int(frame_layout["sheetHeight"])
	)
	if Vector2i(texture.get_width(), texture.get_height()) != expected_size:
		return {"errors": PackedStringArray([
			"atlas %s is %dx%d; manifest declares %dx%d" % [
				atlas_path, texture.get_width(), texture.get_height(), expected_size.x, expected_size.y
			]
		])}
	var row := ((manifest["animation"] as Dictionary)["rows"] as Dictionary)[STATE] as Dictionary
	var rects := ((frame_layout["rows"] as Dictionary)[STATE] as Array)
	var durations := row["durations_ms"] as Array
	var fps := float(row["fps"])
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	frames.add_animation(STATE)
	frames.set_animation_speed(STATE, fps)
	frames.set_animation_loop(STATE, bool(row["loop"]))
	for index in rects.size():
		var value := rects[index] as Dictionary
		var atlas_frame := AtlasTexture.new()
		atlas_frame.atlas = texture
		atlas_frame.region = Rect2i(
			int(value["x"]), int(value["y"]), int(value["w"]), int(value["h"])
		)
		frames.add_frame(STATE, atlas_frame, float(durations[index]) / 1000.0 * fps)
	return {"sprite_frames": frames, "errors": errors, "atlas_path": atlas_path}


static func install_clip(manifest_path: String, replace_selection := false) -> Dictionary:
	var result := {
		"created": PackedStringArray(),
		"updated": PackedStringArray(),
		"preserved": PackedStringArray(),
		"errors": PackedStringArray(),
	}
	if not manifest_path.begins_with("res://") or manifest_path.contains(".."):
		_record_result(result, "errors", "manifest must resolve inside res://")
		return result
	var parsed := parse_manifest_file(manifest_path)
	var errors := parsed.get("errors", PackedStringArray()) as PackedStringArray
	if not errors.is_empty():
		result["errors"] = errors
		return result
	var manifest := parsed["manifest"] as Dictionary
	var built := build_sprite_frames(manifest)
	errors = built.get("errors", PackedStringArray()) as PackedStringArray
	if not errors.is_empty():
		result["errors"] = errors
		return result
	var directory := manifest_path.get_base_dir()
	var source_path := directory.path_join("source_all_frames.tres")
	var selection_path := directory.path_join("selection.tres")
	var source_existed := FileAccess.file_exists(source_path)
	var save_error := ResourceSaver.save(built["sprite_frames"] as SpriteFrames, source_path)
	if save_error != OK:
		_record_result(
			result,
			"errors",
			"could not save source SpriteFrames: %s" % error_string(save_error)
		)
		return result
	_record_result(result, "updated" if source_existed else "created", source_path)

	var selection_existed := FileAccess.file_exists(selection_path)
	if selection_existed and not replace_selection:
		_record_result(result, "preserved", selection_path)
	else:
		var selection := _selection_from_source(
			built["sprite_frames"] as SpriteFrames,
			StringName(str(manifest["clip_id"]))
		)
		save_error = ResourceSaver.save(selection, selection_path)
		if save_error != OK:
			_record_result(
				result,
				"errors",
				"could not save selection SpriteFrames: %s" % error_string(save_error)
			)
			return result
		_record_result(result, "updated" if selection_existed else "created", selection_path)
	result["clip_id"] = str(manifest["clip_id"])
	result["frame_count"] = (built["sprite_frames"] as SpriteFrames).get_frame_count(STATE)
	result["source_path"] = source_path
	result["selection_path"] = selection_path
	return result


static func _record_result(result: Dictionary, key: String, value: String) -> void:
	var values := result.get(key, PackedStringArray()) as PackedStringArray
	values.append(value)
	result[key] = values


static func _selection_from_source(source: SpriteFrames, animation_name: StringName) -> SpriteFrames:
	var selection := SpriteFrames.new()
	selection.remove_animation(&"default")
	selection.add_animation(animation_name)
	selection.set_animation_speed(animation_name, source.get_animation_speed(STATE))
	selection.set_animation_loop(animation_name, source.get_animation_loop(STATE))
	for index in source.get_frame_count(STATE):
		selection.add_frame(
			animation_name,
			source.get_frame_texture(STATE, index),
			source.get_frame_duration(STATE, index)
		)
	return selection


static func _source_frame_count(manifest: Dictionary, errors: PackedStringArray) -> int:
	var source_value: Variant = manifest.get("source", {})
	if not source_value is Dictionary:
		errors.append("source must be an object")
		return 0
	var count := int((source_value as Dictionary).get("frame_count", 0))
	if count <= 0:
		errors.append("source.frame_count must be positive")
	return count


static func _animation_row(manifest: Dictionary, errors: PackedStringArray) -> Dictionary:
	var animation_value: Variant = manifest.get("animation", {})
	if not animation_value is Dictionary:
		errors.append("animation must be an object")
		return {}
	var rows_value: Variant = (animation_value as Dictionary).get("rows", {})
	if not rows_value is Dictionary or not (rows_value as Dictionary).has(STATE):
		errors.append("missing animation state: source_all")
		return {}
	var row_value: Variant = (rows_value as Dictionary)[STATE]
	if not row_value is Dictionary:
		errors.append("animation.rows.source_all must be an object")
		return {}
	return row_value as Dictionary


static func _layout_row(manifest: Dictionary, errors: PackedStringArray) -> Dictionary:
	var layout_value: Variant = manifest.get("frame_layout", {})
	if not layout_value is Dictionary:
		errors.append("frame_layout must be an object")
		return {}
	var layout := layout_value as Dictionary
	var sheet_width := int(layout.get("sheetWidth", 0))
	var sheet_height := int(layout.get("sheetHeight", 0))
	if sheet_width <= 0 or sheet_height <= 0:
		errors.append("frame_layout sheet size must be positive")
	var rows_value: Variant = layout.get("rows", {})
	if not rows_value is Dictionary or not (rows_value as Dictionary).has(STATE):
		errors.append("missing frame layout state: source_all")
		return {}
	var rects_value: Variant = (rows_value as Dictionary)[STATE]
	if not rects_value is Array or (rects_value as Array).is_empty():
		errors.append("frame_layout.rows.source_all must be a non-empty array")
		return {}
	return {"rects": rects_value, "sheet_width": sheet_width, "sheet_height": sheet_height}


static func _validate_rect(
	index: int,
	value: Variant,
	sheet_width: int,
	sheet_height: int,
	errors: PackedStringArray
) -> void:
	if not value is Dictionary:
		errors.append("source_all rectangle %d must be an object" % index)
		return
	var rect_value := value as Dictionary
	var rect := Rect2i(
		int(rect_value.get("x", -1)), int(rect_value.get("y", -1)),
		int(rect_value.get("w", 0)), int(rect_value.get("h", 0))
	)
	if rect.size != EXPECTED_CELL:
		errors.append("source_all rectangle %d must be 256x256" % index)
	if rect.position.x < 0 or rect.position.y < 0:
		errors.append("source_all rectangle %d has a negative origin" % index)
	if rect.end.x > sheet_width or rect.end.y > sheet_height:
		errors.append("source_all rectangle %d exceeds the declared sheet" % index)


static func _validate_source_frame(
	index: int,
	value: Variant,
	rects: Array,
	manifest_path: String,
	errors: PackedStringArray
) -> void:
	if not value is Dictionary:
		errors.append("source frame %d must be an object" % index)
		return
	var source := value as Dictionary
	if int(source.get("index", -1)) != index:
		errors.append("source frame indices must be contiguous from zero at %d" % index)
	if int(source.get("source_frame", 0)) <= 0:
		errors.append("source frame %d source_frame must be positive" % index)
	if float(source.get("duration_ms", 0.0)) <= 0.0:
		errors.append("source frame %d duration_ms must be positive" % index)
	if index < rects.size() and source.get("rect", {}) != rects[index]:
		errors.append("source frame %d rectangle must match frame_layout" % index)
	var png_declared := str(source.get("png", ""))
	var png_path := _resolve_resource_path(png_declared, manifest_path)
	if png_declared.is_empty() or not _is_project_resource_path(png_declared, manifest_path):
		errors.append("source frame %d PNG must resolve inside res://" % index)
	elif not FileAccess.file_exists(png_path):
		errors.append("source frame %d PNG not found: %s" % [index, png_path])


static func _is_project_resource_path(path: String, manifest_path: String) -> bool:
	if path.begins_with("res://"):
		return not path.contains("..")
	return (
		manifest_path.begins_with("res://")
		and not path.is_absolute_path()
		and not path.contains("..")
	)


static func _resolve_resource_path(path: String, manifest_path: String) -> String:
	if path.begins_with("res://"):
		return path.simplify_path()
	if manifest_path.begins_with("res://"):
		return manifest_path.get_base_dir().path_join(path).simplify_path()
	return path
