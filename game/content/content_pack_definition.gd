class_name GogoContentPackDefinition
extends Resource

const API_VERSION := 1

@export var api_version: int = API_VERSION
@export var pack_id: StringName = &""
@export var pack_kind: StringName = &"core"
@export var definitions: Array[GogoContentDefinition] = []


func is_valid() -> bool:
	if api_version != API_VERSION or pack_id.is_empty():
		return false
	if not [&"core", &"character", &"weapon"].has(pack_kind):
		return false
	return definitions.all(func(value: GogoContentDefinition) -> bool: return value != null and value.is_valid())
