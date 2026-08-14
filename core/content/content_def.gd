class_name ContentDef
extends Resource


@export var content_id: StringName
@export var display_name_key: StringName
@export var description_key: StringName
@export var icon: Texture2D


func get_stable_id(pack_id: StringName) -> StringName:
	var local_id := String(content_id).strip_edges()
	if local_id.is_empty():
		return &""
	if local_id.contains(":"):
		return StringName(local_id)
	return StringName("%s:%s" % [pack_id, local_id])
