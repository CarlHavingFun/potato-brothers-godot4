class_name GogoContentDefinition
extends Resource

@export var content_id: StringName = &""
@export var display_name: String = ""
@export var kind: StringName = &""
@export var tags: Array[StringName] = []
@export var icon_asset_id: StringName = &""


func is_valid() -> bool:
	return not content_id.is_empty() and not kind.is_empty() and not display_name.is_empty()
