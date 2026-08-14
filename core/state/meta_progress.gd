class_name MetaProgress
extends RefCounted


var highest_unlocked_difficulty: int = 1
var character_highest_clears: Dictionary = {}
var aim_mode: int = AimMode.AUTO_TARGET
var locale: String = "zh_CN"
var music_volume: float = 0.7
var sfx_volume: float = 0.8
var fullscreen: bool = false
var resolution: String = "1920x1080"


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


func to_dict() -> Dictionary:
	return {
		"highest_unlocked_difficulty": highest_unlocked_difficulty,
		"character_highest_clears": character_highest_clears.duplicate(true),
		"aim_mode": aim_mode,
		"locale": locale,
		"music_volume": music_volume,
		"sfx_volume": sfx_volume,
		"fullscreen": fullscreen,
		"resolution": resolution,
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
	var restored_aim_mode := int(data.get("aim_mode", AimMode.AUTO_TARGET))
	result.aim_mode = restored_aim_mode if AimMode.is_valid(restored_aim_mode) else AimMode.AUTO_TARGET
	result.locale = str(data.get("locale", "zh_CN"))
	result.music_volume = clampf(float(data.get("music_volume", 0.7)), 0.0, 1.0)
	result.sfx_volume = clampf(float(data.get("sfx_volume", 0.8)), 0.0, 1.0)
	result.fullscreen = bool(data.get("fullscreen", false))
	result.resolution = str(data.get("resolution", "1920x1080"))
	return result
