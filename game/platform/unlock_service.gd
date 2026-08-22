class_name UnlockService
extends RefCounted

var unlocked_ids: Dictionary = {}


func unlock(content_id: StringName) -> bool:
	if unlocked_ids.has(content_id):
		return false
	unlocked_ids[content_id] = true
	return true


func is_unlocked(content_id: StringName) -> bool:
	return bool(unlocked_ids.get(content_id, false))
