class_name CodexService
extends RefCounted

var discovered_ids: Dictionary = {}


func discover(content_id: StringName) -> bool:
	if content_id.is_empty() or discovered_ids.has(content_id):
		return false
	discovered_ids[content_id] = true
	return true


func entries(snapshot: ContentSnapshot, kind: StringName) -> Array[GogoContentDefinition]:
	var result: Array[GogoContentDefinition] = []
	for definition in snapshot.all(kind):
		if discovered_ids.has(definition.content_id):
			result.append(definition)
	return result
