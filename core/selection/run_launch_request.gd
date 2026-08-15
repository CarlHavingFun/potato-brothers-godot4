class_name RunLaunchRequest
extends RefCounted


var profile_id: int = 1
var character_id: StringName = &""
var weapon_id: StringName = &""
var difficulty: int = 1
var aim_mode: int = AimMode.AUTO_TARGET
var run_mode: int = RunMode.STANDARD
var random_seed: int = 0


static func from_draft(draft: SelectionDraft) -> RunLaunchRequest:
	if draft == null:
		return null
	var result := RunLaunchRequest.new()
	result.profile_id = draft.profile_id
	result.character_id = draft.character_id
	result.weapon_id = draft.weapon_id
	result.difficulty = draft.difficulty
	result.aim_mode = draft.aim_mode
	result.run_mode = draft.run_mode
	result.random_seed = draft.random_seed
	return result


func is_valid() -> bool:
	return (
		profile_id in range(1, 4)
		and not character_id.is_empty()
		and not weapon_id.is_empty()
		and difficulty in range(1, 6)
		and AimMode.is_valid(aim_mode)
		and RunMode.is_valid(run_mode)
	)


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
