class_name SessionConfig
extends RefCounted

var seed: int = 1
var character_id: StringName = &""
var starting_weapon_id: StringName = &""
var difficulty_id: StringName = &""
var zone_id: StringName = &""
var player_count: int = 1


func is_valid() -> bool:
	return (
		player_count == 1
		and not character_id.is_empty()
		and not starting_weapon_id.is_empty()
		and not difficulty_id.is_empty()
		and not zone_id.is_empty()
	)
