class_name ChallengeService
extends RefCounted

var definitions: Dictionary = {}


func register(challenge_id: StringName, rules: Dictionary) -> Error:
	if challenge_id.is_empty() or definitions.has(challenge_id):
		return ERR_INVALID_DATA
	definitions[challenge_id] = rules.duplicate(true)
	return OK


func apply(challenge_id: StringName, config: SessionConfig) -> Error:
	if not definitions.has(challenge_id):
		return ERR_DOES_NOT_EXIST
	var rules: Dictionary = definitions[challenge_id]
	config.seed = int(rules.get("fixed_seed", config.seed))
	config.zone_id = StringName(rules.get("zone_id", config.zone_id))
	config.difficulty_id = StringName(rules.get("difficulty_id", config.difficulty_id))
	return OK
