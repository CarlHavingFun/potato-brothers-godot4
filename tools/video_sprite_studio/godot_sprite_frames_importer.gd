class_name VideoSpriteStudioImporter
extends RefCounted


const CELL := Vector2i(256, 256)


static func merge_animation(
	existing: SpriteFrames,
	manifest: Dictionary,
	animation: StringName,
	texture: Texture2D
) -> Dictionary:
	var errors := _validate(manifest, animation, texture)
	if not errors.is_empty():
		return {"errors": errors}
	# Shallow duplication keeps every untouched animation's existing Texture2D
	# references while isolating the saved aggregate resource from the loaded one.
	var frames: SpriteFrames = existing.duplicate(false) if existing != null else SpriteFrames.new()
	if existing == null and frames.has_animation(&"default"):
		frames.remove_animation(&"default")
	if frames.has_animation(animation):
		frames.clear(animation)
	else:
		frames.add_animation(animation)
	var state_name := String(animation)
	var row := ((manifest["animation"] as Dictionary)["rows"] as Dictionary)[state_name] as Dictionary
	var rects := ((manifest["frame_layout"] as Dictionary)["rows"] as Dictionary)[state_name] as Array
	var durations := row["durations_ms"] as Array
	var fps := float(row["fps"])
	frames.set_animation_speed(animation, fps)
	frames.set_animation_loop(animation, bool(row["loop"]))
	for index in rects.size():
		var value := rects[index] as Dictionary
		var atlas_frame := AtlasTexture.new()
		atlas_frame.atlas = texture
		atlas_frame.region = Rect2i(
			int(value["x"]), int(value["y"]), int(value["w"]), int(value["h"])
		)
		frames.add_frame(animation, atlas_frame, float(durations[index]) * fps / 1000.0)
	return {"errors": errors, "sprite_frames": frames}


static func _validate(
	manifest: Dictionary,
	animation: StringName,
	texture: Texture2D
) -> PackedStringArray:
	var errors := PackedStringArray()
	var state_name := String(animation)
	if state_name.is_empty():
		errors.append("animation is required")
		return errors
	if texture == null:
		errors.append("atlas texture is required")
		return errors
	var cell_value: Variant = manifest.get("cell", {})
	if not cell_value is Dictionary:
		errors.append("cell must be an object")
	elif Vector2i(int(cell_value.get("width", 0)), int(cell_value.get("height", 0))) != CELL:
		errors.append("cell must be 256x256")
	var animation_value: Variant = manifest.get("animation", {})
	var layout_value: Variant = manifest.get("frame_layout", {})
	if not animation_value is Dictionary or not layout_value is Dictionary:
		errors.append("animation and frame_layout must be objects")
		return errors
	var rows_value: Variant = animation_value.get("rows", {})
	var layout_rows_value: Variant = layout_value.get("rows", {})
	if not rows_value is Dictionary or not layout_rows_value is Dictionary:
		errors.append("animation.rows and frame_layout.rows must be objects")
		return errors
	if not rows_value.has(state_name) or not layout_rows_value.has(state_name):
		errors.append("missing animation state: %s" % state_name)
		return errors
	var row_value: Variant = rows_value[state_name]
	var rects_value: Variant = layout_rows_value[state_name]
	if not row_value is Dictionary or not rects_value is Array:
		errors.append("animation row and layout rectangles are invalid")
		return errors
	var row := row_value as Dictionary
	var rects := rects_value as Array
	if rects.is_empty():
		errors.append("%s must contain at least one frame" % state_name)
	var durations_value: Variant = row.get("durations_ms")
	if not durations_value is Array or (durations_value as Array).size() != rects.size():
		errors.append("%s durations must match frame count" % state_name)
	if int(row.get("frames", -1)) != rects.size():
		errors.append("%s declared frame count must match layout" % state_name)
	var fps := float(row.get("fps", 0.0))
	if fps < 0.1 or fps > 120.0:
		errors.append("%s fps must be 0.1..120" % state_name)
	for index in rects.size():
		var rect_value: Variant = rects[index]
		if not rect_value is Dictionary:
			errors.append("%s rectangle %d must be an object" % [state_name, index])
			continue
		var value := rect_value as Dictionary
		var rect := Rect2i(
			int(value.get("x", -1)), int(value.get("y", -1)),
			int(value.get("w", 0)), int(value.get("h", 0))
		)
		if rect.size != CELL:
			errors.append("%s rectangle %d must be 256x256" % [state_name, index])
		if rect.position.x < 0 or rect.position.y < 0:
			errors.append("%s rectangle %d has a negative origin" % [state_name, index])
		elif rect.end.x > texture.get_width() or rect.end.y > texture.get_height():
			errors.append("%s rectangle %d exceeds atlas bounds" % [state_name, index])
	return errors
