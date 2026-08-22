class_name ContentSnapshot
extends RefCounted

var pack_ids: Array[StringName] = []
var _by_kind: Dictionary = {}


func install_pack(pack: GogoContentPackDefinition) -> Error:
	if pack == null or not pack.is_valid() or pack_ids.has(pack.pack_id):
		return ERR_INVALID_DATA
	for definition in pack.definitions:
		var bucket: Dictionary = _by_kind.get(definition.kind, {})
		if bucket.has(definition.content_id):
			return ERR_ALREADY_EXISTS
		bucket[definition.content_id] = definition.duplicate(true)
		_by_kind[definition.kind] = bucket
	pack_ids.append(pack.pack_id)
	return OK


func seal() -> void:
	pack_ids.make_read_only()
	for bucket: Dictionary in _by_kind.values():
		bucket.make_read_only()
	_by_kind.make_read_only()


func has_definition(content_id: StringName, kind: StringName) -> bool:
	var bucket: Dictionary = _by_kind.get(kind, {})
	return bucket.has(content_id)


func definition(content_id: StringName, kind: StringName) -> GogoContentDefinition:
	var bucket: Dictionary = _by_kind.get(kind, {})
	var value: GogoContentDefinition = bucket.get(content_id)
	return value.duplicate(true) as GogoContentDefinition if value != null else null


func all(kind: StringName) -> Array[GogoContentDefinition]:
	var result: Array[GogoContentDefinition] = []
	var bucket: Dictionary = _by_kind.get(kind, {})
	for value: GogoContentDefinition in bucket.values():
		result.append(value.duplicate(true) as GogoContentDefinition)
	result.sort_custom(func(a: GogoContentDefinition, b: GogoContentDefinition) -> bool: return a.content_id < b.content_id)
	return result
