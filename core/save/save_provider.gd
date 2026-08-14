class_name SaveProvider
extends RefCounted


func load_slot() -> Dictionary:
	return {}


func save_slot(_payload: Variant) -> Error:
	return ERR_UNAVAILABLE


func is_available() -> bool:
	return false
