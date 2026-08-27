class_name GogoStaticPickupVisual
extends Node2D


var asset_id: StringName = &""
var sprite: Sprite2D


func configure(handle: GogoStaticAssetHandle) -> bool:
	if handle == null or handle.texture == null:
		return false
	asset_id = handle.asset_id
	if sprite == null:
		sprite = Sprite2D.new()
		sprite.name = "StaticVisual"
		sprite.centered = false
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(sprite)
	sprite.texture = handle.texture
	sprite.position = -Vector2(handle.pivot_px)
	return true
