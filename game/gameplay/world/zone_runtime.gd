class_name ZoneRuntime
extends RefCounted

var definition: GogoZoneDefinition


func configure(next_definition: GogoZoneDefinition) -> Error:
	if next_definition == null or next_definition.wave_ids.is_empty():
		return ERR_INVALID_PARAMETER
	definition = next_definition
	return OK


func wave_id(wave_number: int) -> StringName:
	if definition == null or wave_number < 1 or wave_number > definition.wave_ids.size():
		return &""
	return definition.wave_ids[wave_number - 1]
