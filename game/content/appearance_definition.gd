class_name GogoAppearanceDefinition
extends Resource

@export var appearance_id: StringName = &""
@export var texture: Texture2D
@export var slot: StringName = &""
@export var display_priority: int = 0
@export var depth: int = 1
@export var offset := Vector2.ZERO
@export var modulate := Color.WHITE


func is_valid() -> bool:
	return not appearance_id.is_empty() and texture != null
