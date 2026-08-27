class_name GogoStaticAssetHandle
extends RefCounted

var binding_key: StringName = &""
var asset_id: StringName = &""
var role: StringName = &""
var selector: StringName = &""
var texture: Texture2D
var display_size_px := Vector2i.ZERO
var display_scale := Vector2.ONE
var pivot_px := Vector2i.ZERO
var anchors_px: Dictionary = {}
var atlas_rect_px := Rect2i()
var source_kind: StringName = &"approved_shipping"


func _configure(payload: Dictionary, loaded_texture: Texture2D) -> void:
	binding_key = payload.get("binding_key", &"")
	asset_id = payload.get("asset_id", &"")
	role = payload.get("role", &"")
	selector = payload.get("selector", &"")
	texture = loaded_texture
	display_size_px = payload.get("display_size_px", Vector2i.ZERO)
	display_scale = payload.get("display_scale", Vector2.ONE)
	pivot_px = payload.get("pivot_px", Vector2i.ZERO)
	anchors_px = (payload.get("anchors_px", {}) as Dictionary).duplicate(true)
	atlas_rect_px = payload.get("atlas_rect_px", Rect2i())
	source_kind = payload.get("source_kind", &"approved_shipping")
