class_name CoopRoster
extends RefCounted

const MAX_PLAYERS := 4

var slots: Array[Dictionary] = []


func join(device_id: int, character_id: StringName = &"") -> Error:
	if slots.size() >= MAX_PLAYERS or slots.any(func(slot: Dictionary) -> bool: return int(slot.device_id) == device_id):
		return ERR_ALREADY_EXISTS
	slots.append({"player_index": slots.size(), "device_id": device_id, "character_id": character_id})
	return OK


func leave(device_id: int) -> Error:
	var index := slots.find_custom(func(slot: Dictionary) -> bool: return int(slot.device_id) == device_id)
	if index < 0:
		return ERR_DOES_NOT_EXIST
	slots.remove_at(index)
	for player_index in slots.size():
		slots[player_index].player_index = player_index
	return OK


func freeze_for_session() -> Array[Dictionary]:
	return slots.duplicate(true)
