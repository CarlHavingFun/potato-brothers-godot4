class_name AchievementService
extends RefCounted

signal unlocked(achievement_id: StringName)

var unlocked_ids: Dictionary = {}


func grant(achievement_id: StringName) -> bool:
	if achievement_id.is_empty() or unlocked_ids.has(achievement_id):
		return false
	unlocked_ids[achievement_id] = true
	unlocked.emit(achievement_id)
	return true
