class_name SpriteGenStateImporter
extends RefCounted


const ENGINE := "component-row"
const EXPECTED_CELL := Vector2i(256, 256)
const EXPECTED_FRAMES := 8
const EXPECTED_FPS := 10.0
const EXPECTED_DURATION_MS := 100


static func parse_manifest_file(path: String, state := &"walk_down") -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"errors": PackedStringArray(["manifest not found: %s" % path])}
	var parser := JSON.new()
	var parse_error := parser.parse(FileAccess.get_file_as_string(path))
	if parse_error != OK:
		return {
			"errors": PackedStringArray([
				"manifest JSON parse failed at line %d: %s" % [
					parser.get_error_line(), parser.get_error_message()
				]
			])
		}
	var parsed: Variant = parser.data
	if not parsed is Dictionary:
		return {"errors": PackedStringArray(["manifest is not a JSON object: %s" % path])}
	var manifest := parsed as Dictionary
	manifest["_manifest_path"] = path
	return {
		"manifest": manifest,
		"errors": validate_manifest(manifest, state, path),
	}


static func validate_manifest(
	manifest: Dictionary,
	state := &"walk_down",
	manifest_path := ""
) -> PackedStringArray:
	var errors := PackedStringArray()
	if manifest_path.is_empty():
		manifest_path = str(manifest.get("_manifest_path", ""))
	if str(manifest.get("engine", "")) != ENGINE:
		errors.append("engine must be %s" % ENGINE)
	if bool(manifest.get("degraded_static_fallback", true)):
		errors.append("degraded_static_fallback must be false")
	if str(manifest.get("game_input", "")).is_empty():
		errors.append("game_input is empty")
	elif not _is_project_resource_path(str(manifest["game_input"]), manifest_path):
		errors.append("game_input must resolve inside res://")

	var cell_value: Variant = manifest.get("cell", {})
	if not cell_value is Dictionary:
		errors.append("cell must be an object")
	else:
		var cell := cell_value as Dictionary
		if Vector2i(int(cell.get("width", 0)), int(cell.get("height", 0))) != EXPECTED_CELL:
			errors.append("cell must be 256x256")

	var animation_value: Variant = manifest.get("animation", {})
	var frame_layout_value: Variant = manifest.get("frame_layout", {})
	if not animation_value is Dictionary:
		errors.append("animation must be an object")
		return errors
	if not frame_layout_value is Dictionary:
		errors.append("frame_layout must be an object")
		return errors

	var animation := animation_value as Dictionary
	var animation_rows_value: Variant = animation.get("rows", {})
	if not animation_rows_value is Dictionary:
		errors.append("animation.rows must be an object")
		return errors
	var animation_rows := animation_rows_value as Dictionary
	var state_name := String(state)
	if not animation_rows.has(state_name):
		errors.append("missing animation state: %s" % state_name)
		return errors
	var animation_row_value: Variant = animation_rows[state_name]
	if not animation_row_value is Dictionary:
		errors.append("animation.rows.%s must be an object" % state_name)
		return errors
	_validate_animation_row(state_name, animation_row_value as Dictionary, errors)

	var frame_layout := frame_layout_value as Dictionary
	var sheet_width := int(frame_layout.get("sheetWidth", 0))
	var sheet_height := int(frame_layout.get("sheetHeight", 0))
	if sheet_width <= 0 or sheet_height <= 0:
		errors.append("frame_layout sheet size must be positive")
	var layout_rows_value: Variant = frame_layout.get("rows", {})
	if not layout_rows_value is Dictionary:
		errors.append("frame_layout.rows must be an object")
		return errors
	var layout_rows := layout_rows_value as Dictionary
	if not layout_rows.has(state_name):
		errors.append("missing frame layout state: %s" % state_name)
		return errors
	var rects_value: Variant = layout_rows[state_name]
	if not rects_value is Array:
		errors.append("frame_layout.rows.%s must be an array" % state_name)
		return errors
	var rects := rects_value as Array
	if rects.size() != EXPECTED_FRAMES:
		errors.append("%s frame layout must contain %d rectangles" % [state_name, EXPECTED_FRAMES])
	for index in rects.size():
		_validate_rect(state_name, index, rects[index], sheet_width, sheet_height, errors)
	return errors


static func build_sprite_frames(
	manifest: Dictionary,
	state := &"walk_down",
	texture_loader: Callable = Callable()
) -> Dictionary:
	var errors := validate_manifest(manifest, state)
	if not errors.is_empty():
		return {"errors": errors}
	var state_name := String(state)
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
	var expected_sheet := Vector2i(
		int(frame_layout["sheetWidth"]), int(frame_layout["sheetHeight"])
	)
	if Vector2i(texture.get_width(), texture.get_height()) != expected_sheet:
		return {
			"errors": PackedStringArray([
				"atlas %s is %dx%d; manifest declares %dx%d" % [
					atlas_path,
					texture.get_width(),
					texture.get_height(),
					expected_sheet.x,
					expected_sheet.y,
				]
			])
		}

	var animation_row := ((manifest["animation"] as Dictionary)["rows"] as Dictionary)[state_name] as Dictionary
	var rects := ((frame_layout["rows"] as Dictionary)[state_name] as Array)
	var durations := animation_row["durations_ms"] as Array
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	frames.add_animation(state)
	frames.set_animation_speed(state, float(animation_row["fps"]))
	frames.set_animation_loop(state, bool(animation_row["loop"]))
	for index in rects.size():
		var value := rects[index] as Dictionary
		var region := Rect2i(
			int(value["x"]), int(value["y"]), int(value["w"]), int(value["h"])
		)
		var atlas_frame := AtlasTexture.new()
		atlas_frame.atlas = texture
		atlas_frame.region = region
		var duration_scale := float(durations[index]) * float(animation_row["fps"]) / 1000.0
		frames.add_frame(state, atlas_frame, duration_scale)
	return {"sprite_frames": frames, "errors": errors, "atlas_path": atlas_path}


static func import_file(manifest_path: String, state: StringName, output_path: String) -> Dictionary:
	if not output_path.begins_with("res://") or output_path.contains(".."):
		return {"errors": PackedStringArray(["output must resolve inside res://"])}
	if output_path.get_extension().to_lower() != "tres":
		return {"errors": PackedStringArray(["output must be a .tres resource"])}
	var parsed := parse_manifest_file(manifest_path, state)
	var errors := parsed.get("errors", PackedStringArray()) as PackedStringArray
	if not errors.is_empty():
		return {"errors": errors}
	var result := build_sprite_frames(parsed["manifest"] as Dictionary, state)
	errors = result.get("errors", PackedStringArray()) as PackedStringArray
	if not errors.is_empty():
		return {"errors": errors}
	var absolute_dir := ProjectSettings.globalize_path(output_path.get_base_dir())
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_dir)
	if directory_error != OK:
		return {"errors": PackedStringArray(["could not create output directory: %s" % error_string(directory_error)])}
	var save_error := ResourceSaver.save(result["sprite_frames"] as SpriteFrames, output_path)
	if save_error != OK:
		return {"errors": PackedStringArray(["could not save SpriteFrames: %s" % error_string(save_error)])}
	return {
		"errors": PackedStringArray(),
		"output": output_path,
		"state": String(state),
		"frames": EXPECTED_FRAMES,
	}


static func _validate_animation_row(
	state: String,
	row: Dictionary,
	errors: PackedStringArray
) -> void:
	if int(row.get("frames", 0)) != EXPECTED_FRAMES:
		errors.append("%s frames must be %d" % [state, EXPECTED_FRAMES])
	if not is_equal_approx(float(row.get("fps", 0.0)), EXPECTED_FPS):
		errors.append("%s fps must be %.1f" % [state, EXPECTED_FPS])
	if not bool(row.get("loop", false)):
		errors.append("%s loop must be true" % state)
	var durations_value: Variant = row.get("durations_ms", null)
	if not durations_value is Array:
		errors.append("%s durations_ms must be an array" % state)
		return
	var durations := durations_value as Array
	if durations.size() != EXPECTED_FRAMES:
		errors.append("%s durations_ms must contain %d values" % [state, EXPECTED_FRAMES])
		return
	for index in durations.size():
		if int(durations[index]) != EXPECTED_DURATION_MS:
			errors.append("%s duration %d must be %d ms" % [state, index, EXPECTED_DURATION_MS])


static func _validate_rect(
	state: String,
	index: int,
	value: Variant,
	sheet_width: int,
	sheet_height: int,
	errors: PackedStringArray
) -> void:
	if not value is Dictionary:
		errors.append("%s rectangle %d must be an object" % [state, index])
		return
	var rect_value := value as Dictionary
	var rect := Rect2i(
		int(rect_value.get("x", -1)),
		int(rect_value.get("y", -1)),
		int(rect_value.get("w", 0)),
		int(rect_value.get("h", 0))
	)
	if rect.size != EXPECTED_CELL:
		errors.append("%s rectangle %d must be 256x256" % [state, index])
	if rect.position.x < 0 or rect.position.y < 0:
		errors.append("%s rectangle %d has a negative origin" % [state, index])
	if rect.end.x > sheet_width or rect.end.y > sheet_height:
		errors.append("%s rectangle %d exceeds the declared sheet" % [state, index])


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
