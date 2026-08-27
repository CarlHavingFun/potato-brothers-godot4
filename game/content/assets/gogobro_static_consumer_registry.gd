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


func observe(
	handle: GogoStaticAssetHandle,
	scene_path: String,
	node_path: String,
	integer_display_scale := Vector2i.ONE,
	source_kind: StringName = &"",
	visible_texture: bool = false
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
	var key := "%s|%s|%s|%s|%s|%s|%s" % [
		handle.asset_id,
		handle.role,
		handle.selector,
		scene_path,
		node_path,
		resolved_source,
		visible_texture,
	]
	if _keys.has(key):
		return true
	_keys[key] = true
	_records.append({
		"asset_id": handle.asset_id,
		"role": handle.role,
		"selector": handle.selector,
		"scene": scene_path,
		"node": node_path,
		"texture_size": Vector2i(handle.texture.get_width(), handle.texture.get_height()),
		"integer_display_scale": integer_display_scale,
		"source_kind": resolved_source,
		"visible_texture": visible_texture,
	})
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
