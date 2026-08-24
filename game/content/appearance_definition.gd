class_name GogoAppearanceDefinition
extends Resource

enum Mode {
	LEGACY_STATIC,
	RIGID,
	FRAME_OVERLAY,
}

@export var appearance_id: StringName = &""
@export var target_character_id: StringName = &""
@export var texture: Texture2D
@export var slot: StringName = &""
@export var socket_id: StringName = &""
@export var mode := Mode.LEGACY_STATIC
@export var frame_overlay: SpriteFrames
@export var display_priority: int = 0
@export var depth: int = 1
@export var offset := Vector2.ZERO
@export var render_scale := Vector2.ONE
@export var rendered_pivot_px := Vector2i.ZERO
@export var local_offset_px := Vector2i.ZERO
@export var modulate := Color.WHITE


func is_valid() -> bool:
	if appearance_id.is_empty():
		return false
	if mode == Mode.FRAME_OVERLAY:
		return (
			frame_overlay != null
			and not target_character_id.is_empty()
			and not slot.is_empty()
			and not socket_id.is_empty()
			and render_scale == Vector2.ONE
		)
	if texture == null:
		return false
	if mode == Mode.RIGID:
		return (
			not target_character_id.is_empty()
			and not slot.is_empty()
			and not socket_id.is_empty()
			and is_finite(render_scale.x)
			and is_finite(render_scale.y)
			and render_scale.x > 0.0
			and render_scale.y > 0.0
		)
	return true


func mode_name() -> String:
	match mode:
		Mode.RIGID:
			return "RIGID"
		Mode.FRAME_OVERLAY:
			return "FRAME_OVERLAY"
		_:
			return "LEGACY_STATIC"
