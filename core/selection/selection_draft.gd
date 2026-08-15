class_name SelectionDraft
extends RefCounted


var profile_id: int = 1
var character_id: StringName = &""
var weapon_id: StringName = &""
var difficulty: int = 1
var aim_mode: int = AimMode.AUTO_TARGET
var run_mode: int = RunMode.STANDARD
var random_seed: int = 0


func to_dict() -> Dictionary:
	return {
		"profile_id": profile_id,
		"character_id": String(character_id),
		"weapon_id": String(weapon_id),
		"difficulty": difficulty,
		"aim_mode": aim_mode,
		"run_mode": run_mode,
		"random_seed": random_seed,
	}


static func from_dict(data: Dictionary) -> SelectionDraft:
	var result := SelectionDraft.new()
	result.profile_id = clampi(int(data.get("profile_id", 1)), 1, 3)
	result.character_id = StringName(str(data.get("character_id", "")))
	result.weapon_id = StringName(str(data.get("weapon_id", "")))
	result.difficulty = clampi(int(data.get("difficulty", 1)), 1, 5)
	var restored_aim_mode := int(data.get("aim_mode", AimMode.AUTO_TARGET))
	result.aim_mode = restored_aim_mode if AimMode.is_valid(restored_aim_mode) else AimMode.AUTO_TARGET
	var restored_run_mode := int(data.get("run_mode", RunMode.STANDARD))
	result.run_mode = restored_run_mode if RunMode.is_valid(restored_run_mode) else RunMode.STANDARD
	result.random_seed = int(data.get("random_seed", 0))
	return result
