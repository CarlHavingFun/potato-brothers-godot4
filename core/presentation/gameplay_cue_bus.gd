class_name GameplayCueBus
extends Node


signal cue_emitted(cue_id: StringName, context: Dictionary)


func emit_cue(cue_id: StringName, context: Dictionary = {}) -> bool:
	if not is_semantic_id(cue_id):
		return false
	cue_emitted.emit(cue_id, context.duplicate(true))
	return true


static func is_semantic_id(cue_id: StringName) -> bool:
	var value := String(cue_id)
	if value.is_empty() or not value.contains(".") or value.begins_with(".") or value.ends_with("."):
		return false
	if value.contains(".."):
		return false
	for character: String in value:
		if character == "." or character == "_" or character >= "a" and character <= "z" or character >= "0" and character <= "9":
			continue
		return false
	return true
