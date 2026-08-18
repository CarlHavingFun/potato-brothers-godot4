class_name MetaProgress
extends RefCounted


var highest_unlocked_difficulty: int = 1
var character_highest_clears: Dictionary = {}
var character_endless_highs: Dictionary = {}
var aim_mode: int = AimMode.AUTO_TARGET
var locale: String = "zh_CN"
var music_volume: float = 0.7
var sfx_volume: float = 0.8
var fullscreen: bool = false
var resolution: String = "1920x1080"
var enemy_health_scale: float = 1.0
var enemy_damage_scale: float = 1.0
var enemy_speed_scale: float = 1.0
var discovered_content: Dictionary = {}
var unlocked_character_ids: Array[String] = []
var recent_run_summary: Dictionary = {}
var repair_notices: Array[String] = []
var input_bindings: Dictionary = {}


func mark_discovered(content_id: StringName) -> bool:
	if content_id.is_empty():
		return false
	var key := String(content_id)
	var changed := not discovered_content.has(key)
	discovered_content[key] = true
	return changed


func is_discovered(content_id: StringName) -> bool:
	return bool(discovered_content.get(String(content_id), false))


func unlock_character(content_id: StringName) -> bool:
	var key := String(content_id)
	if key.is_empty() or key in unlocked_character_ids:
		return false
	unlocked_character_ids.append(key)
	mark_discovered(content_id)
	return true


func record_victory(character_id: StringName, cleared_difficulty: int) -> bool:
	if character_id.is_empty() or cleared_difficulty < 1 or cleared_difficulty > 5:
		return false
	var key := String(character_id)
	character_highest_clears[key] = maxi(highest_clear_for(character_id), cleared_difficulty)
	if cleared_difficulty != highest_unlocked_difficulty or highest_unlocked_difficulty >= 5:
		return false
	highest_unlocked_difficulty += 1
	return true


func highest_clear_for(character_id: StringName) -> int:
	return int(character_highest_clears.get(String(character_id), 0))


func record_endless_wave(character_id: StringName, difficulty: int, wave: int) -> bool:
	if character_id.is_empty() or difficulty not in range(1, 6) or wave < 1:
		return false
	var key := _endless_key(character_id, difficulty)
	if wave <= int(character_endless_highs.get(key, 0)):
		return false
	character_endless_highs[key] = wave
	return true


func highest_endless_wave_for(character_id: StringName, difficulty: int) -> int:
	return int(character_endless_highs.get(_endless_key(character_id, difficulty), 0))


func highest_endless_wave_any(character_id: StringName) -> int:
	var result := 0
	for difficulty in range(1, 6):
		result = maxi(result, highest_endless_wave_for(character_id, difficulty))
	return result


func to_dict() -> Dictionary:
	return {
		"highest_unlocked_difficulty": highest_unlocked_difficulty,
		"character_highest_clears": character_highest_clears.duplicate(true),
		"character_endless_highs": character_endless_highs.duplicate(true),
		"discovered_content": discovered_content.duplicate(true),
		"unlocked_character_ids": unlocked_character_ids.duplicate(),
		"recent_run_summary": recent_run_summary.duplicate(true),
		"repair_notices": repair_notices.duplicate(),
	}


static func from_dict(data: Dictionary) -> MetaProgress:
	var result := MetaProgress.new()
	result.highest_unlocked_difficulty = clampi(
		int(data.get("highest_unlocked_difficulty", 1)), 1, 5
	)
	var raw_clears: Variant = data.get("character_highest_clears", {})
	if raw_clears is Dictionary:
		for raw_key: Variant in raw_clears:
			result.character_highest_clears[str(raw_key)] = clampi(int(raw_clears[raw_key]), 0, 5)
	var raw_endless: Variant = data.get("character_endless_highs", {})
	if raw_endless is Dictionary:
		for raw_key: Variant in raw_endless:
			result.character_endless_highs[str(raw_key)] = maxi(0, int(raw_endless[raw_key]))
	var restored_aim_mode := int(data.get("aim_mode", AimMode.AUTO_TARGET))
	result.aim_mode = restored_aim_mode if AimMode.is_valid(restored_aim_mode) else AimMode.AUTO_TARGET
	result.locale = str(data.get("locale", "zh_CN"))
	result.music_volume = clampf(float(data.get("music_volume", 0.7)), 0.0, 1.0)
	result.sfx_volume = clampf(float(data.get("sfx_volume", 0.8)), 0.0, 1.0)
	result.fullscreen = bool(data.get("fullscreen", false))
	result.resolution = str(data.get("resolution", "1920x1080"))
	result.enemy_health_scale = clampf(float(data.get("enemy_health_scale", 1.0)), 0.25, 2.0)
	result.enemy_damage_scale = clampf(float(data.get("enemy_damage_scale", 1.0)), 0.25, 2.0)
	result.enemy_speed_scale = clampf(float(data.get("enemy_speed_scale", 1.0)), 0.25, 2.0)
	var raw_discovered: Variant = data.get("discovered_content", {})
	if raw_discovered is Dictionary:
		for raw_id: Variant in raw_discovered:
			if bool(raw_discovered[raw_id]):
				result.discovered_content[str(raw_id)] = true
	var raw_unlocked: Variant = data.get("unlocked_character_ids", [])
	if raw_unlocked is Array:
		for raw_id: Variant in raw_unlocked:
			var content_id := str(raw_id)
			if not content_id.is_empty() and content_id not in result.unlocked_character_ids:
				result.unlocked_character_ids.append(content_id)
	var raw_summary: Variant = data.get("recent_run_summary", {})
	result.recent_run_summary = raw_summary.duplicate(true) if raw_summary is Dictionary else {}
	var raw_notices: Variant = data.get("repair_notices", [])
	if raw_notices is Array:
		for notice: Variant in raw_notices:
			result.repair_notices.append(str(notice))
	var raw_bindings: Variant = data.get("input_bindings", {})
	result.input_bindings = raw_bindings.duplicate(true) if raw_bindings is Dictionary else {}
	return result


func _endless_key(character_id: StringName, difficulty: int) -> String:
	return "%s|%d" % [String(character_id), clampi(difficulty, 1, 5)]
