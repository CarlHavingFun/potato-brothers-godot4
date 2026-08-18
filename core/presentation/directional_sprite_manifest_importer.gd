class_name DirectionalSpriteManifestImporter
extends RefCounted


const SCHEMA_VERSION := 1
const REQUIRED_DIRECTIONS: Array[StringName] = [
	&"down",
	&"down_right",
	&"right",
	&"up_right",
	&"up",
	&"up_left",
	&"left",
	&"down_left",
]
const ACTION_CONTRACT := {
	&"idle": {"frame_count": 6, "fps": 6.0, "loop": true, "directions": 8},
	&"walk": {"frame_count": 8, "fps": 10.0, "loop": true, "directions": 8},
	&"dash": {"frame_count": 6, "fps": 15.0, "loop": false, "directions": 8},
	&"hit": {"frame_count": 4, "fps": 16.0, "loop": false, "directions": 8},
	&"death": {"frame_count": 10, "fps": 10.0, "loop": false, "directions": 8},
	&"victory": {"frame_count": 12, "fps": 10.0, "loop": false, "directions": 1},
}


static func parse_manifest_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"errors": PackedStringArray(["manifest not found: %s" % path])}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return {"errors": PackedStringArray(["manifest is not a JSON object: %s" % path])}
	var manifest := parsed as Dictionary
	manifest["_manifest_path"] = path
	return {"manifest": manifest, "errors": validate_manifest(manifest, path)}


static func validate_manifest(manifest: Dictionary, manifest_path := "") -> PackedStringArray:
	var errors := PackedStringArray()
	if manifest_path.is_empty():
		manifest_path = str(manifest.get("_manifest_path", ""))
	if int(manifest.get("schema_version", 0)) != SCHEMA_VERSION:
		errors.append("schema_version must be %d" % SCHEMA_VERSION)
	var frame_size := manifest.get("frame_size", {}) as Dictionary
	if int(frame_size.get("width", 0)) != 256 or int(frame_size.get("height", 0)) != 256:
		errors.append("frame_size must be 256x256")
	var pivot := manifest.get("pivot", {}) as Dictionary
	if int(pivot.get("x", -1)) != 128 or int(pivot.get("y", -1)) != 232:
		errors.append("pivot must be (128, 232)")
	var actions := manifest.get("actions", {}) as Dictionary
	for action: StringName in ACTION_CONTRACT:
		var action_name := String(action)
		if not actions.has(action_name):
			errors.append("missing action: %s" % action_name)
			continue
		var action_data := actions[action_name] as Dictionary
		_validate_action(action, action_data, manifest_path, errors)
	return errors


static func build_sprite_frames(
	manifest: Dictionary,
	texture_loader: Callable = Callable()
) -> Dictionary:
	var errors := validate_manifest(manifest)
	if not errors.is_empty():
		return {"errors": errors}
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	var frame_size := manifest["frame_size"] as Dictionary
	var cell := Vector2i(int(frame_size["width"]), int(frame_size["height"]))
	var actions := manifest["actions"] as Dictionary
	for action: StringName in ACTION_CONTRACT:
		var action_data := actions[String(action)] as Dictionary
		var directions := action_data["directions"] as Dictionary
		for direction_value: Variant in directions:
			var direction := StringName(str(direction_value))
			var direction_data := directions[String(direction)] as Dictionary
			var animation_name := StringName("%s_%s" % [action, direction])
			var atlas_path := _resolve_resource_path(
				str(direction_data.get("atlas", "")),
				str(manifest.get("_manifest_path", ""))
			)
			var texture: Texture2D = (
				texture_loader.call(atlas_path)
				if texture_loader.is_valid()
				else ResourceLoader.load(atlas_path, "Texture2D") as Texture2D
			)
			if texture == null:
				errors.append("could not load atlas: %s" % atlas_path)
				continue
			var frame_count := int(direction_data.get("frame_count", action_data["frame_count"]))
			var required_size := Vector2i(frame_count * cell.x, cell.y)
			if Vector2i(texture.get_width(), texture.get_height()) != required_size:
				errors.append(
					"atlas %s is %dx%d; expected exactly %dx%d" % [
						atlas_path,
						texture.get_width(),
						texture.get_height(),
						required_size.x,
						required_size.y,
					]
				)
				continue
			frames.add_animation(animation_name)
			frames.set_animation_speed(animation_name, float(action_data["fps"]))
			frames.set_animation_loop(animation_name, bool(action_data["loop"]))
			for frame_index in frame_count:
				var atlas_frame := AtlasTexture.new()
				atlas_frame.atlas = texture
				atlas_frame.region = Rect2i(frame_index * cell.x, 0, cell.x, cell.y)
				frames.add_frame(animation_name, atlas_frame)
	if not errors.is_empty():
		return {"errors": errors}
	return {"sprite_frames": frames, "errors": errors}


static func _validate_action(
	action: StringName,
	action_data: Dictionary,
	manifest_path: String,
	errors: PackedStringArray
) -> void:
	var contract := ACTION_CONTRACT[action] as Dictionary
	if int(action_data.get("frame_count", 0)) != int(contract["frame_count"]):
		errors.append("%s frame_count must be %d" % [action, contract["frame_count"]])
	if not is_equal_approx(float(action_data.get("fps", 0.0)), float(contract["fps"])):
		errors.append("%s fps must be %s" % [action, contract["fps"]])
	if bool(action_data.get("loop", false)) != bool(contract["loop"]):
		errors.append("%s loop must be %s" % [action, contract["loop"]])
	var directions := action_data.get("directions", {}) as Dictionary
	var expected_directions: Array[StringName] = (
		[&"down"] as Array[StringName]
		if int(contract["directions"]) == 1
		else REQUIRED_DIRECTIONS
	)
	for direction: StringName in expected_directions:
		var direction_name := String(direction)
		if not directions.has(direction_name):
			errors.append("%s missing direction: %s" % [action, direction])
			continue
		var direction_data := directions[direction_name] as Dictionary
		if int(direction_data.get("frame_count", action_data.get("frame_count", 0))) != int(contract["frame_count"]):
			errors.append("%s_%s frame_count must be %d" % [action, direction, contract["frame_count"]])
		if direction_data.has("row"):
			errors.append("%s_%s row is unsupported; atlas must be one horizontal strip" % [action, direction])
		var atlas_path := str(direction_data.get("atlas", ""))
		if atlas_path.is_empty():
			errors.append("%s_%s atlas is empty" % [action, direction])
		elif not _is_project_resource_path(atlas_path, manifest_path):
			errors.append("%s_%s atlas must resolve inside res://" % [action, direction])
	for raw_direction: Variant in directions:
		if StringName(str(raw_direction)) not in expected_directions:
			errors.append("%s has unexpected direction: %s" % [action, raw_direction])


static func _is_project_resource_path(path: String, manifest_path: String) -> bool:
	if path.begins_with("res://"):
		return not path.contains("..")
	return manifest_path.begins_with("res://") and not path.is_absolute_path() and not path.contains("..")


static func _resolve_resource_path(path: String, manifest_path: String) -> String:
	if path.begins_with("res://"):
		return path.simplify_path()
	if manifest_path.begins_with("res://"):
		return manifest_path.get_base_dir().path_join(path).simplify_path()
	return path
