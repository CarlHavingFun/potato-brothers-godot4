class_name GogoCharacterAttachmentRig
extends Resource

const SCHEMA_VERSION := "gogobro-character-attachment-rig-v2"
const MODE_RIGID := "RIGID"
const MODE_FRAME_OVERLAY := "FRAME_OVERLAY"

@export_storage var rig_id: StringName = &""
@export_storage var character_id: StringName = &""
@export_storage var character_atlas_path := ""
@export_storage var character_atlas_sha256 := ""
@export_storage var frame_size := Vector2i.ZERO
@export_storage var atlas_size := Vector2i.ZERO

@export_storage var _socket_catalog: Dictionary = {}
@export_storage var _animations: Dictionary = {}
@export_storage var _validation_errors := PackedStringArray()
@export_storage var _source_path := ""

var _socket_residuals: Dictionary = {}


static func load_from_path(path: String) -> GogoCharacterAttachmentRig:
	var rig := GogoCharacterAttachmentRig.new()
	rig._source_path = path
	if not FileAccess.file_exists(path):
		rig._validation_errors.append("attachment rig file does not exist: %s" % path)
		return rig
	var parser := JSON.new()
	var parse_error := parser.parse(FileAccess.get_file_as_string(path))
	if parse_error != OK:
		rig._validation_errors.append(
			"attachment rig JSON parse failed at line %d: %s" % [
				parser.get_error_line(),
				parser.get_error_message(),
			]
		)
		return rig
	if not parser.data is Dictionary:
		rig._validation_errors.append("attachment rig root must be an object")
		return rig
	rig._load_data(parser.data as Dictionary)
	return rig


func is_valid() -> bool:
	return (
		_validation_errors.is_empty()
		and not rig_id.is_empty()
		and not character_id.is_empty()
		and not character_atlas_path.is_empty()
		and frame_size.x > 0
		and frame_size.y > 0
		and atlas_size.x > 0
		and atlas_size.y > 0
		and not _socket_catalog.is_empty()
		and not _animations.is_empty()
	)


func validation_errors() -> PackedStringArray:
	return _validation_errors.duplicate()


func source_path() -> String:
	return _source_path


func required_socket_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for raw_socket_id in _socket_catalog.keys():
		result.append(String(raw_socket_id))
	result.sort()
	return result


func animation_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for raw_animation_id in _animations.keys():
		result.append(String(raw_animation_id))
	result.sort()
	return result


func frame_count(animation_id: StringName) -> int:
	var raw_state: Variant = _animations.get(String(animation_id))
	if not raw_state is Dictionary:
		return 0
	var state := raw_state as Dictionary
	return int(state.get("frame_count", 0))


func animation_fps(animation_id: StringName) -> float:
	var raw_state: Variant = _animations.get(String(animation_id))
	if not raw_state is Dictionary:
		return 0.0
	return float((raw_state as Dictionary).get("fps", 0.0))


func has_socket(animation_id: StringName, frame_index: int, socket_id: StringName) -> bool:
	return not _socket(animation_id, frame_index, socket_id).is_empty()


func socket_position_pixels(animation_id: StringName, frame_index: int, socket_id: StringName) -> Vector2i:
	var socket := _socket(animation_id, frame_index, socket_id)
	if socket.is_empty():
		return Vector2i(-1, -1)
	var position: Array = socket["position"]
	return Vector2i(int(position[0]), int(position[1]))


func socket_position_local(animation_id: StringName, frame_index: int, socket_id: StringName) -> Vector2:
	var pixel_position := socket_position_pixels(animation_id, frame_index, socket_id)
	if pixel_position == Vector2i(-1, -1):
		return Vector2.ZERO
	return Vector2(pixel_position) - Vector2(frame_size) * 0.5


func socket_flip_h(animation_id: StringName, frame_index: int, socket_id: StringName) -> bool:
	var socket := _socket(animation_id, frame_index, socket_id)
	if socket.is_empty():
		return false
	var raw_profile: Variant = _socket_catalog.get(String(socket_id))
	return bool((raw_profile as Dictionary).get("flip_h", false)) if raw_profile is Dictionary else false


func socket_slot(socket_id: StringName) -> StringName:
	var raw_profile: Variant = _socket_catalog.get(String(socket_id))
	return StringName((raw_profile as Dictionary).get("slot_id", "")) if raw_profile is Dictionary else &""


func socket_allows_mode(socket_id: StringName, mode_name: String) -> bool:
	var raw_profile: Variant = _socket_catalog.get(String(socket_id))
	if not raw_profile is Dictionary:
		return false
	var profile := raw_profile as Dictionary
	var modes: Array = profile.get("allowed_modes", [])
	return mode_name in modes


func socket_default_depth(socket_id: StringName) -> int:
	var raw_profile: Variant = _socket_catalog.get(String(socket_id))
	if not raw_profile is Dictionary:
		return 0
	return int((raw_profile as Dictionary).get("default_depth", 0))


func validate_sprite_frames(sprite_frames: SpriteFrames) -> PackedStringArray:
	var errors := PackedStringArray()
	if sprite_frames == null:
		errors.append("sprite frames are missing")
		return errors
	# Only animations declared by the rig carry equipment sockets. SpriteFrames may
	# additionally contain unbound states such as hurt or death; those states must
	# render without appearances and never borrow a walking frame's socket data.
	for animation_id in animation_ids():
		var animation := StringName(animation_id)
		if not sprite_frames.has_animation(animation):
			errors.append("sprite frames missing animation: %s" % animation_id)
			continue
		if sprite_frames.get_frame_count(animation) != frame_count(animation):
			errors.append("sprite frame count mismatch for %s" % animation_id)
			continue
		if not is_equal_approx(sprite_frames.get_animation_speed(animation), animation_fps(animation)):
			errors.append("sprite animation fps mismatch for %s" % animation_id)
		var state := _animations[String(animation)] as Dictionary
		var row := int(state.get("row", -1))
		for frame_index in frame_count(animation):
			var texture := sprite_frames.get_frame_texture(animation, frame_index)
			if not texture is AtlasTexture:
				errors.append("sprite frame must use bound AtlasTexture for %s frame %d" % [animation_id, frame_index])
				continue
			var atlas_texture := texture as AtlasTexture
			if atlas_texture.atlas == null:
				errors.append("sprite frame atlas is missing for %s frame %d" % [animation_id, frame_index])
				continue
			if atlas_texture.atlas.resource_path != character_atlas_path:
				errors.append("sprite frame atlas path mismatch for %s frame %d" % [animation_id, frame_index])
			if Vector2i(atlas_texture.atlas.get_size()) != atlas_size:
				errors.append("sprite frame atlas size mismatch for %s frame %d" % [animation_id, frame_index])
			var expected_region := Rect2(
				frame_index * frame_size.x,
				row * frame_size.y,
				frame_size.x,
				frame_size.y
			)
			if atlas_texture.region != expected_region:
				errors.append("sprite frame atlas region mismatch for %s frame %d" % [animation_id, frame_index])
			if Vector2i(atlas_texture.get_size()) != frame_size:
				errors.append("sprite frame size mismatch for %s frame %d" % [animation_id, frame_index])
	return errors


func _load_data(data: Dictionary) -> void:
	if data.get("schema_version") != SCHEMA_VERSION:
		_validation_errors.append("unsupported attachment rig schema")
	var raw_rig_id: Variant = data.get("rig_id")
	var raw_character_id: Variant = data.get("character_id")
	if not raw_rig_id is String or (raw_rig_id as String).is_empty():
		_validation_errors.append("rig_id must be a non-empty string")
	else:
		rig_id = StringName(raw_rig_id)
	if not raw_character_id is String or (raw_character_id as String).is_empty():
		_validation_errors.append("character_id must be a non-empty string")
	else:
		character_id = StringName(raw_character_id)
	var atlas: Variant = data.get("atlas")
	if not atlas is Dictionary:
		_validation_errors.append("atlas must be an object")
	else:
		character_atlas_path = String((atlas as Dictionary).get("path", ""))
		character_atlas_sha256 = String((atlas as Dictionary).get("sha256", "")).to_lower()
		if character_atlas_path.is_empty() or not ResourceLoader.exists(character_atlas_path, "Texture2D"):
			_validation_errors.append("atlas.path must reference an existing texture resource")
		if character_atlas_sha256.length() != 64:
			_validation_errors.append("atlas.sha256 must contain 64 hexadecimal characters")
		elif not character_atlas_path.is_empty() and FileAccess.file_exists(character_atlas_path):
			if FileAccess.get_sha256(character_atlas_path).to_lower() != character_atlas_sha256:
				_validation_errors.append("atlas.sha256 does not match atlas.path")
		frame_size = _read_positive_pair((atlas as Dictionary).get("frame_size"), "atlas.frame_size")
		atlas_size = _read_positive_pair((atlas as Dictionary).get("atlas_size"), "atlas.atlas_size")
		_validate_atlas_geometry()
	var raw_catalog: Variant = data.get("socket_catalog")
	if not raw_catalog is Dictionary or (raw_catalog as Dictionary).is_empty():
		_validation_errors.append("socket_catalog must be a non-empty object")
	else:
		_load_socket_catalog(raw_catalog as Dictionary)
	var raw_animations: Variant = data.get("animations")
	if not raw_animations is Dictionary or (raw_animations as Dictionary).is_empty():
		_validation_errors.append("animations must be a non-empty object")
	else:
		_load_animations(raw_animations as Dictionary)
	_validate_residual_jitter()


func _load_socket_catalog(catalog: Dictionary) -> void:
	for raw_socket_id in catalog.keys():
		if not raw_socket_id is String or (raw_socket_id as String).is_empty():
			_validation_errors.append("socket ids must be non-empty strings")
			continue
		var raw_profile: Variant = catalog[raw_socket_id]
		if not raw_profile is Dictionary:
			_validation_errors.append("socket catalog entry %s must be an object" % raw_socket_id)
			continue
		var profile := raw_profile as Dictionary
		var slot_id: Variant = profile.get("slot_id")
		if not slot_id is String or (slot_id as String).is_empty():
			_validation_errors.append("socket %s missing slot_id" % raw_socket_id)
		var raw_modes: Variant = profile.get("allowed_modes")
		if not raw_modes is Array or (raw_modes as Array).is_empty():
			_validation_errors.append("socket %s missing allowed_modes" % raw_socket_id)
		else:
			for raw_mode in raw_modes as Array:
				if raw_mode not in [MODE_RIGID, MODE_FRAME_OVERLAY]:
					_validation_errors.append("socket %s has invalid mode" % raw_socket_id)
		var depth: Variant = profile.get("default_depth")
		if not _is_integer(depth):
			_validation_errors.append("socket %s default_depth must be an integer" % raw_socket_id)
		elif String(slot_id) == "back" and int(depth) >= 0:
			_validation_errors.append("socket %s back default_depth must be negative" % raw_socket_id)
		elif String(slot_id) != "back" and int(depth) <= 0:
			_validation_errors.append("socket %s front default_depth must be positive" % raw_socket_id)
		var reference_region: Variant = profile.get("reference_region")
		if not reference_region is String or (reference_region as String).is_empty():
			_validation_errors.append("socket %s missing reference_region" % raw_socket_id)
		if typeof(profile.get("flip_h", false)) != TYPE_BOOL:
			_validation_errors.append("socket %s flip_h must be boolean" % raw_socket_id)
		var max_jitter: Variant = profile.get("max_residual_jitter_px")
		if not _is_integer(max_jitter) or int(max_jitter) < 0:
			_validation_errors.append("socket %s max_residual_jitter_px must be a non-negative integer" % raw_socket_id)
	_socket_catalog = catalog.duplicate(true)


func _load_animations(animations: Dictionary) -> void:
	var seen_rows := {}
	var atlas_columns := int(atlas_size.x / frame_size.x) if frame_size.x > 0 else 0
	var atlas_rows := int(atlas_size.y / frame_size.y) if frame_size.y > 0 else 0
	if (
		frame_size.x <= 0
		or frame_size.y <= 0
		or atlas_size.x % frame_size.x != 0
		or atlas_size.y % frame_size.y != 0
	):
		_validation_errors.append("atlas geometry must be an exact frame grid")
	for raw_animation_id in animations.keys():
		if not raw_animation_id is String or (raw_animation_id as String).is_empty():
			_validation_errors.append("animation ids must be non-empty strings")
			continue
		var raw_state: Variant = animations[raw_animation_id]
		if not raw_state is Dictionary:
			_validation_errors.append("animation %s must be an object" % raw_animation_id)
			continue
		var state := raw_state as Dictionary
		var raw_frame_count: Variant = state.get("frame_count")
		var raw_frames: Variant = state.get("frames")
		var raw_row: Variant = state.get("row")
		var raw_fps: Variant = state.get("fps")
		if not _is_integer(raw_frame_count) or int(raw_frame_count) <= 0:
			_validation_errors.append("animation %s frame_count must be positive" % raw_animation_id)
			continue
		if not _is_integer(raw_row) or int(raw_row) < 0:
			_validation_errors.append("animation %s row must be a non-negative integer" % raw_animation_id)
		else:
			var row := int(raw_row)
			if seen_rows.has(row):
				_validation_errors.append("animation %s duplicates atlas row %d" % [raw_animation_id, row])
			else:
				seen_rows[row] = String(raw_animation_id)
		if not _is_finite_number(raw_fps) or float(raw_fps) <= 0.0:
			_validation_errors.append("animation %s fps must be a positive number" % raw_animation_id)
		if not raw_frames is Array or (raw_frames as Array).size() != int(raw_frame_count):
			_validation_errors.append("animation %s frame array does not match frame_count" % raw_animation_id)
			continue
		if atlas_columns > 0 and int(raw_frame_count) != atlas_columns:
			_validation_errors.append("animation %s must cover every atlas column" % raw_animation_id)
		if (
			frame_size.x > 0
			and frame_size.y > 0
			and atlas_size.x > 0
			and atlas_size.y > 0
			and (
				int(raw_frame_count) * frame_size.x > atlas_size.x
				or (int(raw_row) + 1) * frame_size.y > atlas_size.y
			)
		):
			_validation_errors.append("animation %s frame grid exceeds atlas geometry" % raw_animation_id)
		for frame_index in int(raw_frame_count):
			_validate_frame(String(raw_animation_id), frame_index, (raw_frames as Array)[frame_index])
	if atlas_rows > 0:
		for row in atlas_rows:
			if not seen_rows.has(row):
				_validation_errors.append("attachment rig is missing animation row %d" % row)
		for raw_row in seen_rows.keys():
			if int(raw_row) < 0 or int(raw_row) >= atlas_rows:
				_validation_errors.append("attachment rig animation row %d is outside atlas rows" % int(raw_row))
	_animations = animations.duplicate(true)


func _validate_frame(animation_id: String, frame_index: int, raw_frame: Variant) -> void:
	if not raw_frame is Dictionary:
		_validation_errors.append("animation %s frame %d must be an object" % [animation_id, frame_index])
		return
	var frame := raw_frame as Dictionary
	if not _is_integer(frame.get("frame_index")) or int(frame.get("frame_index")) != frame_index:
		_validation_errors.append("animation %s frame_index sequence mismatch at %d" % [animation_id, frame_index])
	var frame_name: Variant = frame.get("frame_name")
	var expected_frame_name := "%s_%02d" % [animation_id, frame_index + 1]
	if not frame_name is String or frame_name != expected_frame_name:
		_validation_errors.append("animation %s frame %d identity mismatch" % [animation_id, frame_index])
	var raw_protected_regions: Variant = frame.get("protected_regions")
	if not raw_protected_regions is Dictionary or (raw_protected_regions as Dictionary).is_empty():
		_validation_errors.append("animation %s frame %d protected_regions must be a non-empty object" % [animation_id, frame_index])
	else:
		for raw_region_id in (raw_protected_regions as Dictionary).keys():
			_read_box(
				(raw_protected_regions as Dictionary)[raw_region_id],
				"%s.%d.protected_regions.%s" % [animation_id, frame_index, raw_region_id]
			)
	var raw_sockets: Variant = frame.get("sockets")
	if not raw_sockets is Dictionary:
		_validation_errors.append("animation %s frame %d sockets must be an object" % [animation_id, frame_index])
		return
	var sockets := raw_sockets as Dictionary
	var raw_regions: Variant = frame.get("regions")
	if not raw_regions is Dictionary:
		_validation_errors.append("animation %s frame %d regions must be an object" % [animation_id, frame_index])
		return
	var regions := raw_regions as Dictionary
	for raw_region_id in regions.keys():
		_read_box(regions[raw_region_id], "%s.%d.regions.%s" % [animation_id, frame_index, raw_region_id])
	var expected_ids := required_socket_ids()
	var actual_ids := PackedStringArray()
	for raw_socket_id in sockets.keys():
		actual_ids.append(String(raw_socket_id))
	actual_ids.sort()
	if actual_ids != expected_ids:
		_validation_errors.append("animation %s frame %d socket coverage mismatch" % [animation_id, frame_index])
	for socket_id in expected_ids:
		_validate_socket(animation_id, frame_index, socket_id, sockets.get(socket_id), regions)


func _validate_socket(
	animation_id: String,
	frame_index: int,
	socket_id: String,
	raw_socket: Variant,
	regions: Dictionary
) -> void:
	if not raw_socket is Array:
		_validation_errors.append("animation %s frame %d missing socket %s" % [animation_id, frame_index, socket_id])
		return
	var position := _read_pair(raw_socket, "%s.%d.%s.position" % [animation_id, frame_index, socket_id])
	var raw_profile: Variant = _socket_catalog.get(socket_id)
	if not raw_profile is Dictionary:
		return
	var profile := raw_profile as Dictionary
	var region_id := String(profile.get("reference_region", ""))
	var region := _read_box(regions.get(region_id), "%s.%d.regions.%s" % [animation_id, frame_index, region_id])
	if position.x < 0 or position.y < 0 or position.x >= frame_size.x or position.y >= frame_size.y:
		_validation_errors.append("animation %s frame %d socket %s is outside the frame" % [animation_id, frame_index, socket_id])
	if region.size != Vector2i.ZERO and not Rect2i(region.position, region.size).has_point(position):
		_validation_errors.append("animation %s frame %d socket %s is outside its reference region" % [animation_id, frame_index, socket_id])
	if region.size != Vector2i.ZERO:
		var region_center := region.position + Vector2i(region.size.x / 2, region.size.y / 2)
		var animation_residuals: Dictionary = _socket_residuals.get(animation_id, {})
		var residuals: Array = animation_residuals.get(socket_id, [])
		residuals.append(position - region_center)
		animation_residuals[socket_id] = residuals
		_socket_residuals[animation_id] = animation_residuals


func _socket(animation_id: StringName, frame_index: int, socket_id: StringName) -> Dictionary:
	var raw_state: Variant = _animations.get(String(animation_id))
	if not raw_state is Dictionary:
		return {}
	var state := raw_state as Dictionary
	if frame_index < 0 or frame_index >= int(state.get("frame_count", 0)):
		return {}
	var frames: Array = state["frames"]
	var raw_frame: Variant = frames[frame_index]
	if not raw_frame is Dictionary:
		return {}
	var frame := raw_frame as Dictionary
	var raw_sockets: Variant = frame.get("sockets")
	if not raw_sockets is Dictionary:
		return {}
	var sockets := raw_sockets as Dictionary
	var raw_socket: Variant = sockets.get(String(socket_id))
	if not raw_socket is Array:
		return {}
	return {"position": (raw_socket as Array).duplicate()}


func _read_positive_pair(raw: Variant, label: String) -> Vector2i:
	var result := _read_pair(raw, label)
	if result.x <= 0 or result.y <= 0:
		_validation_errors.append("%s values must be positive" % label)
	return result


func _read_pair(raw: Variant, label: String) -> Vector2i:
	if not raw is Array or (raw as Array).size() != 2:
		_validation_errors.append("%s must be a two-integer array" % label)
		return Vector2i.ZERO
	var values := raw as Array
	if not _is_integer(values[0]) or not _is_integer(values[1]):
		_validation_errors.append("%s must be a two-integer array" % label)
		return Vector2i.ZERO
	return Vector2i(int(values[0]), int(values[1]))


func _read_box(raw: Variant, label: String) -> Rect2i:
	if not raw is Array or (raw as Array).size() != 4:
		_validation_errors.append("%s must be a four-integer array" % label)
		return Rect2i()
	var values := raw as Array
	for value in values:
		if not _is_integer(value):
			_validation_errors.append("%s must be a four-integer array" % label)
			return Rect2i()
	var left := int(values[0])
	var top := int(values[1])
	var right := int(values[2])
	var bottom := int(values[3])
	if left < 0 or top < 0 or right <= left or bottom <= top or right > frame_size.x or bottom > frame_size.y:
		_validation_errors.append("%s must be an in-frame exclusive box" % label)
		return Rect2i()
	return Rect2i(left, top, right - left, bottom - top)


func _validate_atlas_geometry() -> void:
	if frame_size.x <= 0 or frame_size.y <= 0 or atlas_size.x <= 0 or atlas_size.y <= 0:
		return
	if frame_size.x > atlas_size.x or frame_size.y > atlas_size.y:
		_validation_errors.append("atlas.frame_size must fit inside atlas.atlas_size")
	if character_atlas_path.is_empty():
		return
	if not ResourceLoader.exists(character_atlas_path, "Texture2D"):
		_validation_errors.append("atlas.path must load as Texture2D")
		return
	var atlas_texture := ResourceLoader.load(character_atlas_path, "Texture2D") as Texture2D
	if atlas_texture == null:
		_validation_errors.append("atlas.path must load as Texture2D")
		return
	if Vector2i(atlas_texture.get_size()) != atlas_size:
		_validation_errors.append("atlas.atlas_size does not match atlas.path")


func _validate_residual_jitter() -> void:
	for raw_animation_id in _socket_residuals.keys():
		var animation_id := String(raw_animation_id)
		var animation_residuals := _socket_residuals[raw_animation_id] as Dictionary
		for raw_socket_id in animation_residuals.keys():
			var socket_id := String(raw_socket_id)
			var raw_values: Variant = animation_residuals[raw_socket_id]
			if not raw_values is Array or (raw_values as Array).is_empty():
				continue
			var raw_profile: Variant = _socket_catalog.get(socket_id)
			if not raw_profile is Dictionary:
				continue
			var profile := raw_profile as Dictionary
			var limit := int(profile.get("max_residual_jitter_px", -1))
			if limit < 0:
				continue
			var values := raw_values as Array
			var baseline := values[0] as Vector2i
			for raw_value in values:
				var value := raw_value as Vector2i
				if maxi(absi(value.x - baseline.x), absi(value.y - baseline.y)) > limit:
					_validation_errors.append(
						"animation %s socket %s exceeds max_residual_jitter_px" % [animation_id, socket_id]
					)
					break


func _is_finite_number(value: Variant) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	return is_finite(float(value))


func _is_integer(value: Variant) -> bool:
	# Godot's JSON decoder represents JSON numbers as floats. Preserve a strict
	# integer contract by rejecting non-finite and fractional numeric values.
	if not _is_finite_number(value):
		return false
	var number := float(value)
	return number == floor(number)
