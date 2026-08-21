class_name VideoSpriteManifestImporter
extends RefCounted


const ENGINE := "pixelmotion2d-video-library"
const SPRITE_GEN_ENGINE := "pixelmotion2d-cutout+sprite-gen-pixel-unfake"
const KIND := "pixelmotion-video-sprite-library"
const STATE := &"source_all"
const EXPECTED_CELL := Vector2i(256, 256)
const EXPECTED_ROOT := Vector2i(128, 232)
const SOURCE_PREFIX := "source__"


static func parse_character_config_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"errors": PackedStringArray(["character config not found: %s" % path])}
	var parser := JSON.new()
	var parse_error := parser.parse(FileAccess.get_file_as_string(path))
	if parse_error != OK:
		return {"errors": PackedStringArray([
			"character config JSON parse failed at line %d: %s" % [
				parser.get_error_line(), parser.get_error_message()
			]
		])}
	if not parser.data is Dictionary:
		return {"errors": PackedStringArray(["character config must be a JSON object"])}
	var config := parser.data as Dictionary
	var errors := validate_character_config(config)
	return {"config": config, "errors": errors}


static func validate_character_config(config: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if int(config.get("schema_version", 0)) != 1:
		errors.append("character config schema_version must be 1")
	if str(config.get("character_id", "")).is_empty():
		errors.append("character config character_id must be non-empty")
	if int(config.get("expected_source_frame_count", 0)) <= 0:
		errors.append("character config expected_source_frame_count must be positive")
	var required_value: Variant = config.get("required_actions", null)
	if not required_value is Array or (required_value as Array).is_empty():
		errors.append("character config required_actions must be a non-empty array")
	var actions_value: Variant = config.get("actions", null)
	if not actions_value is Dictionary:
		errors.append("character config actions must be an object")
		return errors
	if required_value is Array:
		for required_action: Variant in required_value as Array:
			var required_name := str(required_action)
			if not (actions_value as Dictionary).has(required_name):
				errors.append("missing required action: %s" % required_name)
	for action_value: Variant in actions_value as Dictionary:
		var action := str(action_value)
		var action_data_value: Variant = (actions_value as Dictionary)[action_value]
		if not action_data_value is Dictionary:
			errors.append("character config action %s must be an object" % action)
			continue
		var action_data := action_data_value as Dictionary
		var takes_value: Variant = action_data.get("takes", null)
		if not takes_value is Array:
			errors.append("character config action %s takes must be an array" % action)
			continue
		var names := PackedStringArray()
		for take_value: Variant in takes_value as Array:
			if not take_value is Dictionary:
				errors.append("character config action %s take must be an object" % action)
				continue
			var take := take_value as Dictionary
			var name := str(take.get("name", ""))
			var clip_id := str(take.get("clip_id", ""))
			if name.is_empty() or clip_id.is_empty():
				errors.append("character config action %s take name and clip_id must be non-empty" % action)
			elif name in names:
				errors.append("character config action %s has duplicate take name: %s" % [action, name])
			else:
				names.append(name)
		var preferred := str(action_data.get("preferred_take", ""))
		if not names.is_empty() and preferred not in names:
			errors.append("character config action %s preferred_take does not resolve" % action)
	return errors


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
	var engine := str(manifest.get("engine", ""))
	if engine != ENGINE and engine != SPRITE_GEN_ENGINE:
		errors.append("engine must be one of: %s, %s" % [ENGINE, SPRITE_GEN_ENGINE])
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
		if int(cell.get("safe_margin", -1)) != 24:
			errors.append("cell safe_margin must be 24")
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
	var previous_timestamp := -1.0
	var expected_timestamp := 0.0
	for index in sources.size():
		_validate_source_frame(index, sources[index], rects, manifest_path, errors)
		if not sources[index] is Dictionary:
			continue
		var source_frame := sources[index] as Dictionary
		var timestamp := float(source_frame.get("timestamp_seconds", -1.0))
		if index > 0 and timestamp <= previous_timestamp:
			errors.append("source frame timestamps must increase at %d" % index)
		if timestamp >= 0.0 and absf(timestamp - expected_timestamp) > 0.002:
			errors.append("source frame %d timestamp does not match frame timing" % index)
		if durations_value is Array and index < (durations_value as Array).size():
			var layout_duration := float((durations_value as Array)[index])
			if absf(float(source_frame.get("duration_ms", 0.0)) - layout_duration) > 0.002:
				errors.append("source frame %d duration must match animation timing" % index)
			expected_timestamp += layout_duration / 1000.0
		previous_timestamp = timestamp
	return errors


static func validate_manifest_assets(manifest: Dictionary) -> PackedStringArray:
	var errors := validate_manifest(manifest)
	if not errors.is_empty():
		return errors
	var manifest_path := str(manifest.get("_manifest_path", ""))
	var atlas_path := _resolve_resource_path(str(manifest.get("game_input", "")), manifest_path)
	var atlas := Image.load_from_file(ProjectSettings.globalize_path(atlas_path))
	if atlas.is_empty():
		return PackedStringArray(["could not decode atlas PNG: %s" % atlas_path])
	atlas.convert(Image.FORMAT_RGBA8)
	var layout := manifest["frame_layout"] as Dictionary
	var expected_sheet := Vector2i(int(layout["sheetWidth"]), int(layout["sheetHeight"]))
	if Vector2i(atlas.get_width(), atlas.get_height()) != expected_sheet:
		errors.append(
			"atlas PNG size must match frame_layout: expected %s, found %s" % [
				expected_sheet, Vector2i(atlas.get_width(), atlas.get_height()),
			]
		)
		return errors
	var processing_value: Variant = manifest.get("processing", {})
	var processing := processing_value as Dictionary if processing_value is Dictionary else {}
	var palette_size := mini(int(processing.get("palette_size", 32)), 32)
	var cell := manifest["cell"] as Dictionary
	var safe_margin := int(cell.get("safe_margin", 24))
	var ground_y := int((manifest["root"] as Dictionary).get("y", EXPECTED_ROOT.y))
	var rects := ((layout["rows"] as Dictionary)[STATE] as Array)
	var sources := manifest["source_frames"] as Array
	var shared_colours: Dictionary = {}
	for index in sources.size():
		var source := sources[index] as Dictionary
		var png_path := _resolve_resource_path(str(source["png"]), manifest_path)
		var actual_sha := FileAccess.get_sha256(png_path)
		if actual_sha != str(source["sha256"]):
			errors.append("source frame %d sha256 mismatch" % index)
		var frame := Image.load_from_file(ProjectSettings.globalize_path(png_path))
		if frame.is_empty():
			errors.append("source frame %d PNG could not be decoded" % index)
			continue
		frame.convert(Image.FORMAT_RGBA8)
		if Vector2i(frame.get_width(), frame.get_height()) != EXPECTED_CELL:
			errors.append("source frame %d PNG must be 256x256" % index)
			continue
		var frame_data := frame.get_data()
		var has_soft_alpha := false
		var violates_margin := false
		var opaque_pixel_count := 0
		var lowest_opaque_y := -1
		for y in EXPECTED_CELL.y:
			for x in EXPECTED_CELL.x:
				var offset := (y * EXPECTED_CELL.x + x) * 4
				var alpha := int(frame_data[offset + 3])
				if alpha == 0:
					continue
				opaque_pixel_count += 1
				lowest_opaque_y = maxi(lowest_opaque_y, y)
				if alpha != 255:
					has_soft_alpha = true
				if (
					x < safe_margin
					or x >= EXPECTED_CELL.x - safe_margin
					or y < safe_margin
					or y >= ground_y
				):
					violates_margin = true
				var colour_key := (
					(int(frame_data[offset]) << 16)
					| (int(frame_data[offset + 1]) << 8)
					| int(frame_data[offset + 2])
				)
				shared_colours[colour_key] = true
		if has_soft_alpha:
			errors.append("source frame %d PNG must use hard alpha" % index)
		if opaque_pixel_count == 0:
			errors.append("source frame %d PNG must contain at least one opaque pixel" % index)
		elif lowest_opaque_y + 1 != ground_y:
			errors.append(
				"source frame %d must be grounded at root y=%d (opaque bbox bottom=%d)" % [
					index, ground_y, lowest_opaque_y + 1,
				]
			)
		if violates_margin:
			errors.append("source frame %d violates the 24px safe margin/root boundary" % index)
		var rect_value := rects[index] as Dictionary
		var rect := Rect2i(
			int(rect_value["x"]), int(rect_value["y"]),
			int(rect_value["w"]), int(rect_value["h"])
		)
		var atlas_region := atlas.get_region(rect)
		atlas_region.convert(Image.FORMAT_RGBA8)
		if atlas_region.get_data() != frame_data:
			errors.append("source frame %d PNG does not match atlas region" % index)
	if shared_colours.size() > palette_size:
		errors.append(
			"clip exceeds the shared %d-colour palette (%d colours found)" % [
				palette_size, shared_colours.size(),
			]
		)
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


static func build_character_sprite_frames(
	config: Dictionary,
	sources: Dictionary,
	existing: SpriteFrames = null
) -> Dictionary:
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	var character_id := str(config.get("character_id", ""))
	if character_id.is_empty():
		errors.append("character_id must be non-empty")
	var actions_value: Variant = config.get("actions", {})
	if not actions_value is Dictionary:
		errors.append("actions must be an object")
		return {"errors": errors}
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	var expected_source_frame_count := int(config.get("expected_source_frame_count", 0))
	if existing != null:
		for animation_name: StringName in existing.get_animation_names():
			if not String(animation_name).begins_with(SOURCE_PREFIX):
				_copy_animation(existing, animation_name, frames, animation_name)

	var source_take_count := 0
	var actions := actions_value as Dictionary
	for action_value: Variant in actions:
		var action := str(action_value)
		var action_value_data: Variant = actions[action_value]
		if not action_value_data is Dictionary:
			errors.append("action %s must be an object" % action)
			continue
		var action_data := action_value_data as Dictionary
		var takes_value: Variant = action_data.get("takes", [])
		if not takes_value is Array:
			errors.append("action %s takes must be an array" % action)
			continue
		var preferred_take := str(action_data.get("preferred_take", ""))
		var preferred_source_name := StringName()
		for take_value: Variant in takes_value as Array:
			if not take_value is Dictionary:
				errors.append("action %s take must be an object" % action)
				continue
			var take := take_value as Dictionary
			var take_name := str(take.get("name", ""))
			var clip_id := str(take.get("clip_id", ""))
			if take_name.is_empty() or clip_id.is_empty():
				errors.append("action %s take name and clip_id must be non-empty" % action)
				continue
			var source_value: Variant = sources.get(clip_id)
			if not source_value is SpriteFrames:
				errors.append("missing source SpriteFrames for clip: %s" % clip_id)
				continue
			var source := source_value as SpriteFrames
			if not source.has_animation(STATE) or source.get_frame_count(STATE) <= 0:
				errors.append("clip %s is missing source_all frames" % clip_id)
				continue
			var source_frame_count := source.get_frame_count(STATE)
			if expected_source_frame_count > 0 and source_frame_count != expected_source_frame_count:
				warnings.append(
					"%s has %d source frames; legacy expected_source_frame_count metadata is %d" % [
						clip_id, source_frame_count, expected_source_frame_count,
					]
				)
			var source_name := StringName("%s%s_down__%s" % [SOURCE_PREFIX, action, take_name])
			_copy_animation(source, STATE, frames, source_name)
			frames.set_animation_loop(source_name, bool(action_data.get("loop", false)))
			source_take_count += 1
			if take_name == preferred_take:
				preferred_source_name = source_name
		var runtime_name := StringName("%s_down" % action)
		if not frames.has_animation(runtime_name) and not preferred_source_name.is_empty():
			_copy_animation(frames, preferred_source_name, frames, runtime_name)
			frames.set_animation_loop(runtime_name, bool(action_data.get("loop", false)))
		elif not (takes_value as Array).is_empty() and preferred_source_name.is_empty():
			errors.append("action %s preferred_take does not resolve" % action)

	frames.set_meta("character_id", character_id)
	frames.set_meta("expected_source_frame_count", expected_source_frame_count)
	frames.set_meta("source_take_count", source_take_count)
	frames.set_meta("degraded_static_fallback", false)
	frames.set_meta("required_runtime_actions", configured_runtime_actions(config))
	return {"sprite_frames": frames, "errors": errors, "warnings": warnings}


static func configured_runtime_actions(config: Dictionary) -> PackedStringArray:
	var result := PackedStringArray()
	var actions_value: Variant = config.get("actions", {})
	if not actions_value is Dictionary:
		return result
	var required_value: Variant = config.get("required_actions", [])
	if not required_value is Array:
		return result
	for action_value: Variant in required_value as Array:
		var action := str(action_value)
		var action_data_value: Variant = (actions_value as Dictionary).get(action, {})
		if not action_data_value is Dictionary:
			continue
		var takes_value: Variant = (action_data_value as Dictionary).get("takes", [])
		if takes_value is Array and not (takes_value as Array).is_empty():
			result.append(action)
	return result


static func character_status(config: Dictionary, frames: SpriteFrames) -> Dictionary:
	var required := PackedStringArray()
	var required_value: Variant = config.get("required_actions", [])
	if required_value is Array:
		for action: Variant in required_value as Array:
			required.append(str(action))
	var missing := PackedStringArray()
	var source_take_count := 0
	if frames != null:
		for animation_name: StringName in frames.get_animation_names():
			if String(animation_name).begins_with(SOURCE_PREFIX):
				source_take_count += 1
		for action: String in required:
			var animation_name := StringName("%s_down" % action)
			if not frames.has_animation(animation_name) or frames.get_frame_count(animation_name) <= 0:
				missing.append(action)
	else:
		missing = required.duplicate()
	return {
		"character_id": str(config.get("character_id", "")),
		"required_actions": required,
		"missing_actions": missing,
		"source_take_count": source_take_count,
		"expected_source_frame_count": int(config.get("expected_source_frame_count", 0)),
		"degraded_static_fallback": false,
	}


static func install_character_library(
	config: Dictionary,
	clip_root: String,
	authoring_path: String,
	replace_runtime := false,
	source_loader: Callable = Callable()
) -> Dictionary:
	var errors := PackedStringArray()
	if not clip_root.begins_with("res://") or clip_root.contains(".."):
		errors.append("clip_root must resolve inside res://")
	if not authoring_path.begins_with("res://") or authoring_path.contains(".."):
		errors.append("authoring_path must resolve inside res://")
	elif authoring_path.get_extension().to_lower() != "tres":
		errors.append("authoring_path must be a .tres resource")
	if not errors.is_empty():
		return {"errors": errors}
	var sources: Dictionary = {}
	var actions_value: Variant = config.get("actions", {})
	if not actions_value is Dictionary:
		return {"errors": PackedStringArray(["actions must be an object"])}
	for action_value: Variant in actions_value as Dictionary:
		var action_data_value: Variant = (actions_value as Dictionary)[action_value]
		if not action_data_value is Dictionary:
			continue
		var takes_value: Variant = (action_data_value as Dictionary).get("takes", [])
		if not takes_value is Array:
			continue
		for take_value: Variant in takes_value as Array:
			if not take_value is Dictionary:
				continue
			var clip_id := str((take_value as Dictionary).get("clip_id", ""))
			if clip_id.is_empty() or sources.has(clip_id):
				continue
			var source_path := clip_root.path_join(clip_id).path_join("source_all_frames.tres")
			var source: SpriteFrames = (
				source_loader.call(source_path) as SpriteFrames
				if source_loader.is_valid()
				else ResourceLoader.load(
					source_path, "SpriteFrames", ResourceLoader.CACHE_MODE_REPLACE
				) as SpriteFrames
			)
			if source == null:
				errors.append("source SpriteFrames not found: %s" % source_path)
			else:
				sources[clip_id] = source
	if not errors.is_empty():
		return {"errors": errors}
	var existing: SpriteFrames = null
	if not replace_runtime and FileAccess.file_exists(authoring_path):
		existing = ResourceLoader.load(
			authoring_path, "SpriteFrames", ResourceLoader.CACHE_MODE_REPLACE
		) as SpriteFrames
		if existing == null:
			return {"errors": PackedStringArray(["could not load authoring resource: %s" % authoring_path])}
	var built := build_character_sprite_frames(config, sources, existing)
	errors = built.get("errors", PackedStringArray()) as PackedStringArray
	if not errors.is_empty():
		return {"errors": errors}
	var absolute_directory := ProjectSettings.globalize_path(authoring_path.get_base_dir())
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_directory)
	if directory_error != OK:
		return {"errors": PackedStringArray([
			"could not create authoring directory: %s" % error_string(directory_error)
		])}
	var frames := built["sprite_frames"] as SpriteFrames
	frames.set_meta("clip_root", clip_root)
	frames.set_meta("authoring_path", authoring_path)
	var save_error := ResourceSaver.save(frames, authoring_path)
	if save_error != OK:
		return {"errors": PackedStringArray([
			"could not save authoring SpriteFrames: %s" % error_string(save_error)
		])}
	var status := character_status(config, frames)
	status["errors"] = PackedStringArray()
	status["authoring_path"] = authoring_path
	status["runtime_preserved"] = existing != null
	return status


static func publish_character_runtime(
	authoring: SpriteFrames,
	character_id: String,
	output_root: String,
	page_texture_loader: Callable = Callable(),
	page_columns := 16,
	page_rows := 16
) -> Dictionary:
	var errors := PackedStringArray()
	if authoring == null:
		errors.append("authoring SpriteFrames is required")
	if character_id.is_empty():
		errors.append("character_id must be non-empty")
	if not output_root.begins_with("res://") or output_root.contains(".."):
		errors.append("output_root must resolve inside res://")
	if page_columns <= 0 or page_rows <= 0:
		errors.append("runtime atlas page dimensions must be positive")
	if authoring != null:
		var required_value: Variant = authoring.get_meta(
			"required_runtime_actions", PackedStringArray(["idle"])
		)
		var required_actions := PackedStringArray()
		if required_value is PackedStringArray:
			required_actions = required_value as PackedStringArray
		elif required_value is Array:
			for action_value: Variant in required_value as Array:
				required_actions.append(str(action_value))
		for action: String in required_actions:
			var animation_name := StringName("%s_down" % action)
			if (
				not authoring.has_animation(animation_name)
				or authoring.get_frame_count(animation_name) <= 0
			):
				errors.append(
					"%s must contain at least one frame before publishing" % animation_name
				)
	if not errors.is_empty():
		return {"errors": errors}

	var animation_names := PackedStringArray()
	var total_frames := 0
	for animation_name: StringName in authoring.get_animation_names():
		if String(animation_name).begins_with(SOURCE_PREFIX):
			continue
		var count := authoring.get_frame_count(animation_name)
		if count <= 0:
			continue
		animation_names.append(String(animation_name))
		total_frames += count
	if total_frames <= 0:
		return {"errors": PackedStringArray(["no runtime animation frames to publish"])}
	animation_names.sort()

	var capacity := page_columns * page_rows
	var page_count := ceili(float(total_frames) / float(capacity))
	var page_size := Vector2i(page_columns * EXPECTED_CELL.x, page_rows * EXPECTED_CELL.y)
	var page_images: Array[Image] = []
	for _page_index in page_count:
		var page := Image.create(page_size.x, page_size.y, false, Image.FORMAT_RGBA8)
		page.fill(Color(0, 0, 0, 0))
		page_images.append(page)

	var layout_rows: Dictionary = {}
	var animation_rows: Dictionary = {}
	var frame_records: Dictionary = {}
	var global_index := 0
	for animation_name_text: String in animation_names:
		var animation_name := StringName(animation_name_text)
		var rects: Array = []
		var records: Array = []
		var durations_ms: Array = []
		var fps := authoring.get_animation_speed(animation_name)
		if fps <= 0.0:
			return {"errors": PackedStringArray([
				"%s animation FPS must be positive" % animation_name_text
			])}
		for frame_index in authoring.get_frame_count(animation_name):
			var frame_texture := authoring.get_frame_texture(animation_name, frame_index)
			var frame_image := _texture_region_image(frame_texture)
			if frame_image == null or Vector2i(frame_image.get_width(), frame_image.get_height()) != EXPECTED_CELL:
				return {"errors": PackedStringArray([
					"%s frame %d must resolve to a 256x256 image" % [animation_name_text, frame_index]
				])}
			var page_index := global_index / capacity
			var page_cell := global_index % capacity
			var position := Vector2i(
				(page_cell % page_columns) * EXPECTED_CELL.x,
				(page_cell / page_columns) * EXPECTED_CELL.y
			)
			page_images[page_index].blit_rect(
				frame_image,
				Rect2i(Vector2i.ZERO, EXPECTED_CELL),
				position
			)
			var rect := {
				"page": page_index,
				"x": position.x,
				"y": position.y,
				"w": EXPECTED_CELL.x,
				"h": EXPECTED_CELL.y,
			}
			rects.append(rect)
			var duration_scale := authoring.get_frame_duration(animation_name, frame_index)
			var duration_ms := duration_scale / fps * 1000.0
			durations_ms.append(duration_ms)
			records.append({
				"index": frame_index,
				"duration_ms": duration_ms,
				"rect": rect.duplicate(true),
			})
			global_index += 1
		layout_rows[animation_name_text] = rects
		frame_records[animation_name_text] = records
		animation_rows[animation_name_text] = {
			"frames": rects.size(),
			"fps": fps,
			"loop": authoring.get_animation_loop(animation_name),
			"durations_ms": durations_ms,
		}

	var absolute_root := ProjectSettings.globalize_path(output_root)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_root)
	if directory_error != OK:
		return {"errors": PackedStringArray([
			"could not create runtime output directory: %s" % error_string(directory_error)
		])}
	var page_paths := PackedStringArray()
	for page_index in page_count:
		var page_path := output_root.path_join("runtime_atlas_%03d.png" % (page_index + 1))
		var save_image_error := page_images[page_index].save_png(
			ProjectSettings.globalize_path(page_path)
		)
		if save_image_error != OK:
			return {"errors": PackedStringArray([
				"could not save runtime atlas page: %s" % error_string(save_image_error)
			])}
		page_paths.append(page_path)

	var page_textures: Array[Texture2D] = []
	for page_path: String in page_paths:
		var texture: Texture2D = (
			page_texture_loader.call(page_path) as Texture2D
			if page_texture_loader.is_valid()
			else ResourceLoader.load(page_path, "Texture2D", ResourceLoader.CACHE_MODE_REPLACE) as Texture2D
		)
		if texture == null:
			return {"errors": PackedStringArray(["could not load runtime atlas page: %s" % page_path])}
		page_textures.append(texture)

	var runtime := SpriteFrames.new()
	runtime.remove_animation(&"default")
	for animation_name_text: String in animation_names:
		var animation_name := StringName(animation_name_text)
		runtime.add_animation(animation_name)
		runtime.set_animation_speed(animation_name, authoring.get_animation_speed(animation_name))
		runtime.set_animation_loop(animation_name, authoring.get_animation_loop(animation_name))
		var rects := layout_rows[animation_name_text] as Array
		for frame_index in rects.size():
			var rect_value := rects[frame_index] as Dictionary
			var atlas_frame := AtlasTexture.new()
			atlas_frame.atlas = page_textures[int(rect_value["page"])]
			atlas_frame.region = Rect2i(
				int(rect_value["x"]), int(rect_value["y"]),
				int(rect_value["w"]), int(rect_value["h"])
			)
			runtime.add_frame(
				animation_name,
				atlas_frame,
				authoring.get_frame_duration(animation_name, frame_index)
			)
	var runtime_path := output_root.path_join("%s_runtime_frames.tres" % character_id)
	var save_error := ResourceSaver.save(runtime, runtime_path)
	if save_error != OK:
		return {"errors": PackedStringArray([
			"could not save runtime SpriteFrames: %s" % error_string(save_error)
		])}
	var manifest := {
		"schema_version": 1,
		"kind": "character-sprite-runtime",
		"character_id": character_id,
		"degraded_static_fallback": false,
		"cell": {"width": EXPECTED_CELL.x, "height": EXPECTED_CELL.y},
		"root": {"x": EXPECTED_ROOT.x, "y": EXPECTED_ROOT.y},
		"pages": Array(page_paths),
		"animation": {"rows": animation_rows},
		"frame_layout": {
			"pageWidth": page_size.x,
			"pageHeight": page_size.y,
			"rows": layout_rows,
		},
		"frames": frame_records,
		"sprite_frames": runtime_path,
	}
	var manifest_path := output_root.path_join("manifest.json")
	var manifest_file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if manifest_file == null:
		return {"errors": PackedStringArray(["could not write runtime manifest: %s" % manifest_path])}
	manifest_file.store_string(JSON.stringify(manifest, "  "))
	manifest_file.close()
	return {
		"errors": PackedStringArray(),
		"character_id": character_id,
		"frame_count": total_frames,
		"animation_count": animation_names.size(),
		"page_count": page_count,
		"runtime_path": runtime_path,
		"manifest_path": manifest_path,
		"pages": page_paths,
	}


static func _texture_region_image(texture: Texture2D) -> Image:
	if texture == null:
		return null
	if texture is AtlasTexture:
		var atlas_texture := texture as AtlasTexture
		if atlas_texture.atlas == null:
			return null
		var atlas_image := atlas_texture.atlas.get_image()
		if atlas_image == null or atlas_image.is_empty():
			return null
		return atlas_image.get_region(Rect2i(atlas_texture.region))
	return texture.get_image()


static func _copy_animation(
	source: SpriteFrames,
	source_name: StringName,
	destination: SpriteFrames,
	destination_name: StringName
) -> void:
	if destination.has_animation(destination_name):
		destination.remove_animation(destination_name)
	destination.add_animation(destination_name)
	destination.set_animation_speed(destination_name, source.get_animation_speed(source_name))
	destination.set_animation_loop(destination_name, source.get_animation_loop(source_name))
	for index in source.get_frame_count(source_name):
		destination.add_frame(
			destination_name,
			source.get_frame_texture(source_name, index),
			source.get_frame_duration(source_name, index)
		)


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


static func write_preview_scene(manifest_path: String) -> Dictionary:
	var parsed := parse_manifest_file(manifest_path)
	var errors := parsed.get("errors", PackedStringArray()) as PackedStringArray
	if not errors.is_empty():
		return {"errors": errors}
	var manifest := parsed["manifest"] as Dictionary
	var selection_path := manifest_path.get_base_dir().path_join("selection.tres")
	if not FileAccess.file_exists(selection_path):
		return {"errors": PackedStringArray(["selection not found: %s" % selection_path])}
	var preview_path := manifest_path.get_base_dir().path_join("preview.tscn")
	var clip_id := str(manifest["clip_id"])
	var root := manifest["root"] as Dictionary
	var source := """[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://tools/video_sprites/video_sprite_preview.gd" id="1_preview"]
[ext_resource type="SpriteFrames" path="%s" id="2_frames"]

[node name="VideoSpritePreview" type="Node2D"]
script = ExtResource("1_preview")
clip_id = "%s"
root_anchor = Vector2(%d, %d)

[node name="Checkerboard" type="Node2D" parent="."]

[node name="RootGuide" type="Node2D" parent="."]

[node name="Sprite" type="AnimatedSprite2D" parent="."]
texture_filter = 1
sprite_frames = ExtResource("2_frames")
animation = &"%s"
autoplay = "%s"
centered = false

[node name="HUD" type="CanvasLayer" parent="."]

[node name="Info" type="Label" parent="HUD"]
offset_left = 18.0
offset_top = 18.0
offset_right = 900.0
offset_bottom = 50.0
theme_override_colors/font_color = Color(0.08, 0.09, 0.11, 1)
theme_override_colors/font_shadow_color = Color(1, 1, 1, 0.85)
theme_override_constants/shadow_offset_x = 1
theme_override_constants/shadow_offset_y = 1
text = "%s"
""" % [
		selection_path,
		clip_id.c_escape(),
		int(root["x"]),
		int(root["y"]),
		clip_id.c_escape(),
		clip_id.c_escape(),
		clip_id.c_escape(),
	]
	var file := FileAccess.open(preview_path, FileAccess.WRITE)
	if file == null:
		return {"errors": PackedStringArray(["could not write preview: %s" % preview_path])}
	file.store_string(source)
	file.close()
	return {"errors": PackedStringArray(), "preview_path": preview_path}


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
	if int(source.get("source_frame", 0)) != index + 1:
		errors.append("source frame %d source_frame must equal %d" % [index, index + 1])
	if float(source.get("timestamp_seconds", -1.0)) < 0.0:
		errors.append("source frame %d timestamp_seconds must be non-negative" % index)
	if float(source.get("duration_ms", 0.0)) <= 0.0:
		errors.append("source frame %d duration_ms must be positive" % index)
	if not _is_sha256(str(source.get("sha256", ""))):
		errors.append(
			"source frame %d sha256 must contain 64 lowercase hex characters" % index
		)
	if index < rects.size() and source.get("rect", {}) != rects[index]:
		errors.append("source frame %d rectangle must match frame_layout" % index)
	var png_declared := str(source.get("png", ""))
	var png_path := _resolve_resource_path(png_declared, manifest_path)
	if png_declared.is_empty() or not _is_project_resource_path(png_declared, manifest_path):
		errors.append("source frame %d PNG must resolve inside res://" % index)
	elif not FileAccess.file_exists(png_path):
		errors.append("source frame %d PNG not found: %s" % [index, png_path])


static func _is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for index in value.length():
		if value.substr(index, 1) not in "0123456789abcdef":
			return false
	return true


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
