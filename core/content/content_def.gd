class_name ContentDef
extends Resource


@export var content_id: StringName
@export var presentation_id: StringName
@export var display_name_key: StringName
@export var description_key: StringName
@export var icon: Texture2D
@export var tags: Array[StringName] = []
@export var effects: Array[EffectDef] = []


func get_stable_id(pack_id: StringName) -> StringName:
	var local_id := String(content_id).strip_edges()
	if local_id.is_empty():
		return &""
	if local_id.contains(":"):
		return StringName(local_id)
	return StringName("%s:%s" % [pack_id, local_id])


func get_presentation_id(pack_id: StringName = &"") -> StringName:
	if not presentation_id.is_empty():
		return presentation_id
	var stable_id := get_stable_id(pack_id)
	return stable_id if not stable_id.is_empty() else content_id
