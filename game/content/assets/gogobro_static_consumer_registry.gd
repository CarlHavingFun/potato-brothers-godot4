class_name GogoStaticConsumerRegistry
extends RefCounted


static var _current_registry: GogoStaticConsumerRegistry

var _records: Array[Dictionary] = []
var _keys: Dictionary = {}


static func current() -> GogoStaticConsumerRegistry:
	if _current_registry == null:
		_current_registry = GogoStaticConsumerRegistry.new()
	return _current_registry


static func reset_current() -> void:
	_current_registry = GogoStaticConsumerRegistry.new()


static func observe_handle(
	handle: GogoStaticAssetHandle,
	scene_path: String,
	node_path: String,
	integer_display_scale := Vector2i.ONE,
	source_kind: StringName = &""
) -> bool:
	return current().observe(
		handle,
		scene_path,
		node_path,
		integer_display_scale,
		source_kind,
		false
	)


static func observe_visible_texture(
	handle: GogoStaticAssetHandle,
	canvas_item: CanvasItem,
	scene_path: String,
	node_path: String,
	integer_display_scale := Vector2i.ONE,
	source_kind: StringName = &""
) -> bool:
	if (
		handle == null
		or handle.texture == null
		or canvas_item == null
		or not canvas_item.is_inside_tree()
		or not canvas_item.is_visible_in_tree()
		or not _is_allowed_scene(scene_path)
		or node_path.strip_edges().is_empty()
		or _canvas_texture(canvas_item) != handle.texture
		or not _has_verified_provenance(canvas_item, scene_path, node_path)
		or not _has_verified_integer_scale(
			canvas_item,
			handle.texture,
			integer_display_scale
		)
	):
		return false
	return current().observe(
		handle,
		scene_path,
		node_path,
		integer_display_scale,
		source_kind,
		true
	)


static func observe_visible_option_icon(
	handle: GogoStaticAssetHandle,
	option: OptionButton,
	scene_path: String,
	node_path: String,
	expected_rendered_size: Vector2 = Vector2.ZERO,
	source_kind: StringName = &""
) -> bool:
	if (
		handle == null
		or handle.texture == null
		or option == null
		or not option.is_inside_tree()
		or not option.is_visible_in_tree()
		or option.selected < 0
		or option.selected >= option.item_count
		or option.get_item_icon(option.selected) != handle.texture
		or not _is_allowed_scene(scene_path)
		or node_path.strip_edges().is_empty()
		or not _has_verified_provenance(option, scene_path, node_path)
	):
		return false
	var texture_size := Vector2(handle.texture.get_width(), handle.texture.get_height())
	var rendered_size := _option_icon_rendered_size(option, texture_size)
	if (
		not rendered_size.is_finite()
		or rendered_size.x <= 0.0
		or rendered_size.y <= 0.0
		or (
			expected_rendered_size != Vector2.ZERO
			and not rendered_size.is_equal_approx(expected_rendered_size)
		)
	):
		return false
	return current()._observe_rendered(
		handle,
		scene_path,
		node_path,
		rendered_size,
		Vector2(rendered_size.x / texture_size.x, rendered_size.y / texture_size.y),
		source_kind,
		true
	)


func observe(
	handle: GogoStaticAssetHandle,
	scene_path: String,
	node_path: String,
	integer_display_scale := Vector2i.ONE,
	source_kind: StringName = &"",
	visible_texture: bool = false
) -> bool:
	return _append_record(
		handle,
		scene_path,
		node_path,
		integer_display_scale,
		Vector2.ZERO,
		Vector2.ZERO,
		source_kind,
		visible_texture
	)


func _observe_rendered(
	handle: GogoStaticAssetHandle,
	scene_path: String,
	node_path: String,
	rendered_size_px: Vector2,
	display_scale: Vector2,
	source_kind: StringName,
	visible_texture: bool
) -> bool:
	if (
		not rendered_size_px.is_finite()
		or rendered_size_px.x <= 0.0
		or rendered_size_px.y <= 0.0
		or not display_scale.is_finite()
		or display_scale.x <= 0.0
		or display_scale.y <= 0.0
	):
		return false
	return _append_record(
		handle,
		scene_path,
		node_path,
		Vector2i.ZERO,
		rendered_size_px,
		display_scale,
		source_kind,
		visible_texture
	)


func _append_record(
	handle: GogoStaticAssetHandle,
	scene_path: String,
	node_path: String,
	integer_display_scale: Vector2i,
	rendered_size_px: Vector2,
	display_scale: Vector2,
	source_kind: StringName,
	visible_texture: bool
) -> bool:
	if (
		handle == null
		or handle.texture == null
		or handle.asset_id.is_empty()
		or handle.role.is_empty()
		or not _is_allowed_scene(scene_path)
		or node_path.strip_edges().is_empty()
	):
		return false
	var resolved_source := source_kind if not source_kind.is_empty() else handle.source_kind
	if resolved_source.is_empty():
		resolved_source = &"approved_shipping"
	var measurement_key := (
		"rendered:%s:%s" % [rendered_size_px, display_scale]
		if rendered_size_px != Vector2.ZERO
		else "integer:%s" % integer_display_scale
	)
	var key := "%s|%s|%s|%s|%s|%s|%s|%s" % [
		handle.asset_id,
		handle.role,
		handle.selector,
		scene_path,
		node_path,
		resolved_source,
		visible_texture,
		measurement_key,
	]
	if _keys.has(key):
		return true
	_keys[key] = true
	var record := {
		"asset_id": handle.asset_id,
		"role": handle.role,
		"selector": handle.selector,
		"scene": scene_path,
		"node": node_path,
		"texture_size": Vector2i(handle.texture.get_width(), handle.texture.get_height()),
		"source_kind": resolved_source,
		"visible_texture": visible_texture,
	}
	if rendered_size_px != Vector2.ZERO:
		record["rendered_size_px"] = rendered_size_px
		record["display_scale"] = display_scale
	else:
		record["integer_display_scale"] = integer_display_scale
	_records.append(record)
	return true


func records() -> Array[Dictionary]:
	var result := _records.duplicate(true)
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_key := "%s|%s|%s|%s|%s" % [
			left.asset_id, left.role, left.selector, left.scene, left.node,
		]
		var right_key := "%s|%s|%s|%s|%s" % [
			right.asset_id, right.role, right.selector, right.scene, right.node,
		]
		return left_key < right_key
	)
	return result


func clear() -> void:
	_records.clear()
	_keys.clear()


static func _is_allowed_scene(scene_path: String) -> bool:
	var normalized := scene_path.replace("\\", "/").to_lower()
	return (
		normalized.begins_with("res://")
		and not normalized.contains("/tools/")
		and not normalized.contains("gallery")
		and not normalized.contains("preview_sheet")
	)


static func _canvas_texture(canvas_item: CanvasItem) -> Texture2D:
	for property: Dictionary in canvas_item.get_property_list():
		if String(property.get("name", "")) == "texture":
			return canvas_item.get("texture") as Texture2D
	return null


static func _option_icon_rendered_size(option: OptionButton, texture_size: Vector2) -> Vector2:
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return Vector2.ZERO
	var icon_max_width := option.get_theme_constant(&"icon_max_width")
	if icon_max_width <= 0 or texture_size.x <= float(icon_max_width):
		return texture_size.round()
	var scale := float(icon_max_width) / texture_size.x
	# Button::_fit_icon_size() rounds the scaled size before draw_texture_rect(),
	# so preserve the actual logical draw rect rather than an ideal aspect ratio.
	return (texture_size * scale).round()


static func _has_verified_provenance(
	canvas_item: CanvasItem,
	scene_path: String,
	node_path: String
) -> bool:
	var claimed_segments := node_path.replace("\\", "/").trim_prefix("/").split("/", false)
	if claimed_segments.is_empty():
		return false
	for segment: String in claimed_segments:
		if segment.strip_edges().is_empty() or segment in [".", ".."]:
			return false
	var expected_scene := scene_path.replace("\\", "/").to_lower()
	var scripted_ancestor: Node
	var cursor: Node = canvas_item
	while cursor != null:
		var node_script := cursor.get_script() as Script
		if (
			node_script != null
			and String(node_script.resource_path).replace("\\", "/").to_lower()
				== expected_scene
		):
			scripted_ancestor = cursor
			break
		cursor = cursor.get_parent()
	if scripted_ancestor == null:
		return false
	var actual_segments: Array[String] = []
	cursor = canvas_item
	while cursor != null:
		actual_segments.push_front(String(cursor.name))
		if cursor == scripted_ancestor:
			break
		cursor = cursor.get_parent()
	if claimed_segments.size() > actual_segments.size():
		return false
	var offset := actual_segments.size() - claimed_segments.size()
	for index in claimed_segments.size():
		if claimed_segments[index] != actual_segments[offset + index]:
			return false
	return true


static func _has_verified_integer_scale(
	canvas_item: CanvasItem,
	texture: Texture2D,
	integer_display_scale: Vector2i
) -> bool:
	if integer_display_scale.x <= 0 or integer_display_scale.y <= 0:
		return false
	# Nine-patch controls tile and stretch separate edge/center regions. Their
	# outer rect is not a uniform texture scale, so ONE records authored-pixel
	# sampling rather than claiming the whole rect is a scaled 64x64 image.
	if canvas_item is NinePatchRect:
		return integer_display_scale == Vector2i.ONE
	if not canvas_item is TextureRect:
		return false
	var texture_rect := canvas_item as TextureRect
	var texture_size := Vector2(texture.get_width(), texture.get_height())
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return false
	var rendered_size := _texture_rect_rendered_size(texture_rect, texture_size)
	var expected_size := Vector2(
		texture_size.x * integer_display_scale.x,
		texture_size.y * integer_display_scale.y
	)
	return rendered_size.is_equal_approx(expected_size)


static func _texture_rect_rendered_size(
	texture_rect: TextureRect,
	texture_size: Vector2
) -> Vector2:
	match texture_rect.stretch_mode:
		TextureRect.STRETCH_KEEP, TextureRect.STRETCH_KEEP_CENTERED:
			return texture_size
		TextureRect.STRETCH_KEEP_ASPECT, TextureRect.STRETCH_KEEP_ASPECT_CENTERED:
			var contained_scale := minf(
				texture_rect.size.x / texture_size.x,
				texture_rect.size.y / texture_size.y
			)
			return texture_size * contained_scale
		TextureRect.STRETCH_KEEP_ASPECT_COVERED:
			var covered_scale := maxf(
				texture_rect.size.x / texture_size.x,
				texture_rect.size.y / texture_size.y
			)
			return texture_size * covered_scale
		TextureRect.STRETCH_TILE:
			return texture_size
		_:
			return texture_rect.size
